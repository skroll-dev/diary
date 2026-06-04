import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'app_preferences.dart';
import 'auth_service.dart';
import 'recording_service.dart' show AudioData, RecordingService;

part 'proxy_client.g.dart';

class TopicDto {
  const TopicDto({
    required this.title,
    required this.text,
    required this.followUpHint,
  });
  final String title;
  final String text;
  final String followUpHint;

  factory TopicDto.fromJson(Map<String, dynamic> j) => TopicDto(
        title: j['title'] as String? ?? '',
        text: j['text'] as String? ?? '',
        followUpHint: j['follow_up_hint'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'text': text,
        'follow_up_hint': followUpHint,
      };
}

class EntryDto {
  const EntryDto({
    required this.bodyMarkdown,
    required this.mood,
    required this.moodScore,
    required this.followUpQuestions,
    required this.topics,
  });
  final String bodyMarkdown;
  final String mood;
  final double moodScore;
  final List<String> followUpQuestions;
  final List<TopicDto> topics;

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
      );
}

const _baseUrl = String.fromEnvironment(
  'PROXY_BASE_URL',
  defaultValue: 'http://localhost:8080',
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
    dio.interceptors.add(LogInterceptor(
      requestHeader: false,
      requestBody: true,
      responseBody: true,
      responseHeader: false,
      error: true,
      logPrint: (o) => debugPrint('[ProxyClient] $o'),
    ));
    return dio;
  }

  Future<String> transcribe(AudioData audio) async {
    final prefs = await _ref.read(appPreferencesProvider.future);
    final dio = await _dio();
    final parts = audio.contentType.split('/');
    final form = FormData.fromMap({
      'audio': MultipartFile.fromBytes(
        audio.bytes,
        filename: 'recording.${parts.last}',
        contentType: DioMediaType(parts.first, parts.last),
      ),
      'denoise': prefs.denoiseAudio ? '1' : '0',
    });
    final resp = await dio.post('/transcribe/', data: form);
    return resp.data['transcript'] as String;
  }

  /// Web streaming path: pipes [audioStream] chunks over WebSocket.
  /// Calls [onInterim] with each partial result and [onSegment] when a
  /// segment is confirmed. Returns the full transcript when the stream ends.
  Future<String> transcribeWebSocket(
    Stream<Uint8List> audioStream, {
    void Function(String text)? onInterim,
    void Function(String text)? onSegment,
  }) async {
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
      'sr=${RecordingService.webSampleRate}',
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
          debugPrint('[WS] interim: $text');
          onInterim?.call(text);
        } else if (data['type'] == 'segment') {
          final text = data['text'] as String? ?? '';
          debugPrint('[WS] segment: $text');
          onSegment?.call(text);
        } else if (data['type'] == 'final' || data['transcript'] != null) {
          final text = data['transcript'] as String? ?? '';
          debugPrint('[WS] final: $text');
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

    // Batch small AudioWorklet buffers into ~2 s chunks before sending.
    // 44100 Hz * 2 bytes * 1 ch * 2 s = 176400 bytes
    const batchTarget = 176400;

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

    await for (final chunk in audioStream) {
      pending.add(chunk);
      pendingBytes += chunk.lengthInBytes;
      if (pendingBytes >= batchTarget) await flush();
    }
    await flush(); // send any remaining bytes
    debugPrint('[WS] sent done after $chunkIndex chunks');
    channel.sink.add('done');

    final transcript = await completer.future;
    await channel.sink.close();
    return transcript;
  }

  Future<String> normalize(String transcript) async {
    final dio = await _dio();
    final resp = await dio.post(
      '/entries/normalize',
      data: {'transcript': transcript},
    );
    return resp.data['normalized_text'] as String;
  }

  Future<EntryDto> generateEntry(String transcript) async {
    final dio = await _dio();
    final resp = await dio.post(
      '/entries/generate',
      data: {'transcript': transcript},
    );
    return EntryDto.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<EntryDto> mergeEntry({
    required String existingBody,
    required String newTranscript,
    required List<String> previousQuestions,
  }) async {
    final dio = await _dio();
    final resp = await dio.post(
      '/entries/merge',
      data: {
        'existing_entry': existingBody,
        'new_transcript': newTranscript,
        'previous_questions': previousQuestions,
      },
    );
    return EntryDto.fromJson(resp.data as Map<String, dynamic>);
  }
}

@Riverpod(keepAlive: true)
ProxyClient proxyClient(Ref ref) => ProxyClient(ref);
