import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'app_preferences.dart';
import 'auth_service.dart';
import 'recording_service.dart' show RecordingService;

part 'proxy_client.g.dart';

/// Thrown when the backend rejects a request with a 422 Pydantic validation
/// error (e.g. a transcript exceeding the length limit).
class ProxyValidationException implements Exception {
  ProxyValidationException(this.field, this.message);
  final String field;
  final String message;

  @override
  String toString() => 'ProxyValidationException($field: $message)';
}

/// Parses a FastAPI 422 response body into a [ProxyValidationException], or
/// rethrows [e] unchanged if it isn't a recognizable validation error.
Never _rethrowAsValidationError(DioException e) {
  if (e.response?.statusCode == 422) {
    final detail = e.response?.data is Map
        ? (e.response?.data as Map)['detail']
        : null;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map) {
        final loc = first['loc'];
        final field = (loc is List && loc.isNotEmpty) ? '${loc.last}' : '';
        final msg = first['msg'] as String? ?? 'Validation error';
        throw ProxyValidationException(field, msg);
      }
    }
  }
  throw e;
}

class TopicDto {
  const TopicDto({
    required this.title,
    required this.text,
  });
  final String title;
  final String text;

  factory TopicDto.fromJson(Map<String, dynamic> j) => TopicDto(
        title: j['title'] as String? ?? '',
        text: j['text'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'text': text,
      };
}

class EntryDto {
  const EntryDto({
    required this.bodyMarkdown,
    required this.mood,
    required this.moodScore,
    required this.followUpQuestions,
    required this.topics,
    required this.tags,
  });
  final String bodyMarkdown;
  final String mood;
  final double moodScore;
  final List<String> followUpQuestions;
  final List<TopicDto> topics;
  final List<String> tags;

  factory EntryDto.fromJson(Map<String, dynamic> j) => EntryDto(
        bodyMarkdown: j['body_markdown'] as String? ?? '',
        mood: j['mood'] as String? ?? 'neutral',
        moodScore: (j['mood_score'] as num?)?.toDouble() ?? 0.0,
        followUpQuestions:
            (j['follow_up_questions'] as List?)?.cast<String>() ?? [],
        topics: (j['topics'] as List?)
                ?.map((t) => TopicDto.fromJson(t as Map<String, dynamic>))
                .toList() ??
            [],
        tags: (j['tags'] as List?)?.cast<String>() ?? [],
      );
}

const _baseUrl = String.fromEnvironment(
  'PROXY_BASE_URL',
  defaultValue: 'https://ai-proxy-918937960824.europe-west3.run.app',
);

class ProxyClient {
  const ProxyClient(this._ref);
  final Ref _ref;

  Future<Dio> _dio() async {
    // Skip auth for local dev — Firebase anonymous auth is not required on localhost
    final isLocal = _baseUrl.contains('localhost') || _baseUrl.contains('127.0.0.1');
    final headers = <String, dynamic>{};
    if (!isLocal) {
      final token = await _ref.read(authServiceProvider.notifier).getIdToken();
      headers['Authorization'] = 'Bearer $token';
    }
    final dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      headers: headers,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
    ));
    // Bodies are diary content: debugPrint also reaches the device log in
    // release builds.
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        requestHeader: false,
        requestBody: true,
        responseBody: true,
        responseHeader: false,
        error: true,
        logPrint: (o) => debugPrint('[ProxyClient] $o'),
      ));
    }
    return dio;
  }

  /// Pipes [audioStream] chunks over WebSocket (all platforms).
  /// Calls [onInterim] with each partial result and [onSegment] when a
  /// segment is confirmed. Returns the full transcript when the stream ends.
  Future<String> transcribeWebSocket(
    Stream<Uint8List> audioStream, {
    required String languageCode,
    void Function(String text)? onInterim,
    void Function(String text)? onSegment,
  }) async {
    // Subscribe before the first await: the recorder is already running, and
    // audio emitted while the token and socket are set up must not be lost.
    final audio = StreamController<Uint8List>();
    final audioSub = audioStream.listen(
      audio.add,
      onError: audio.addError,
      onDone: audio.close,
    );

    final wsBase = _baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');

    final isLocal =
        _baseUrl.contains('localhost') || _baseUrl.contains('127.0.0.1');
    final token =
        isLocal ? '' : await _ref.read(authServiceProvider.notifier).getIdToken();
    final prefs = await _ref.read(appPreferencesProvider.future);

    final params = <String>[
      if (token.isNotEmpty) 'token=${Uri.encodeQueryComponent(token)}',
      if (!prefs.denoiseAudio) 'denoise=0',
      'sr=${RecordingService.sampleRate}',
      'language=$languageCode',
    ];
    final uri = Uri.parse(
      '$wsBase/transcribe/ws${params.isEmpty ? '' : '?${params.join('&')}'}',
    );

    final channel = WebSocketChannel.connect(uri);
    final completer = Completer<String>();

    channel.stream.listen(
      (msg) {
        final data = jsonDecode(msg as String) as Map<String, dynamic>;
        if (data['error'] != null) {
          if (!completer.isCompleted) {
            completer.completeError(Exception(data['error'] as String));
          }
        } else if (data['type'] == 'interim') {
          final text = data['text'] as String? ?? '';
          onInterim?.call(text);
        } else if (data['type'] == 'segment') {
          final text = data['text'] as String? ?? '';
          onSegment?.call(text);
        } else if (data['type'] == 'final' || data['transcript'] != null) {
          final text = data['transcript'] as String? ?? '';
          if (!completer.isCompleted) {
            completer.complete(text);
          }
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(Exception('WebSocket closed without response'));
        }
      },
    );

    // Batch small recorder buffers into ~2 s chunks before sending.
    // Sample rate * 2 bytes * 1 ch * 2 s
    final batchTarget = RecordingService.sampleRate * 2 * 2;

    var chunkIndex = 0;
    final pending = <Uint8List>[];
    var pendingBytes = 0;

    Future<void> flush() async {
      if (pending.isEmpty) return;
      final batch = Uint8List(pendingBytes);
      var offset = 0;
      for (final c in pending) {
        batch.setRange(offset, offset + c.lengthInBytes, c);
        offset += c.lengthInBytes;
      }
      pending.clear();
      pendingBytes = 0;
      channel.sink.add(batch);
      chunkIndex++;
      debugPrint('[WS] chunk $chunkIndex — ${batch.lengthInBytes} bytes');
    }

    try {
      await for (final chunk in audio.stream) {
        pending.add(chunk);
        pendingBytes += chunk.lengthInBytes;
        if (pendingBytes >= batchTarget) await flush();
      }
      await flush(); // send any remaining bytes
      debugPrint('[WS] sent done after $chunkIndex chunks');
      channel.sink.add('done');

      // A socket that dies silently never reports back; don't wait forever.
      return await completer.future.timeout(const Duration(seconds: 60));
    } finally {
      await audioSub.cancel();
      await channel.sink.close();
    }
  }

  Future<String> normalize(String transcript, {required String languageCode}) async {
    final dio = await _dio();
    try {
      final resp = await dio.post(
        '/entries/normalize',
        data: {'transcript': transcript, 'language': languageCode},
      );
      return resp.data['normalized_text'] as String;
    } on DioException catch (e) {
      _rethrowAsValidationError(e);
    }
  }

  Future<EntryDto> generateEntry(
    String transcript, {
    required String languageCode,
    List<String> existingTags = const [],
  }) async {
    final dio = await _dio();
    try {
      final resp = await dio.post(
        '/entries/generate',
        data: {
          'transcript': transcript,
          'language': languageCode,
          if (existingTags.isNotEmpty) 'existing_tags': existingTags,
        },
      );
      return EntryDto.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _rethrowAsValidationError(e);
    }
  }

  Future<EntryDto> mergeEntry({
    required String existingBody,
    required String newTranscript,
    required List<String> previousQuestions,
    required String languageCode,
    List<String> existingTags = const [],
  }) async {
    final dio = await _dio();
    try {
      final resp = await dio.post(
        '/entries/merge',
        data: {
          'existing_entry': existingBody,
          'new_transcript': newTranscript,
          'previous_questions': previousQuestions,
          'language': languageCode,
          if (existingTags.isNotEmpty) 'existing_tags': existingTags,
        },
      );
      return EntryDto.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _rethrowAsValidationError(e);
    }
  }
}

@Riverpod(keepAlive: true)
ProxyClient proxyClient(Ref ref) => ProxyClient(ref);
