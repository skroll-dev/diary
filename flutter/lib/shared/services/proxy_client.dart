import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_service.dart';
import 'recording_service.dart' show AudioData;

part 'proxy_client.g.dart';

class TopicDto {
  const TopicDto({
    required this.title,
    required this.summary,
    required this.followUpHint,
  });
  final String title;
  final String summary;
  final String followUpHint;

  factory TopicDto.fromJson(Map<String, dynamic> j) => TopicDto(
        title: j['title'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        followUpHint: j['follow_up_hint'] as String? ?? '',
      );
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
    final dio = await _dio();
    final parts = audio.contentType.split('/');
    final form = FormData.fromMap({
      'audio': MultipartFile.fromBytes(
        audio.bytes,
        filename: 'recording.${parts.last}',
        contentType: DioMediaType(parts.first, parts.last),
      ),
    });
    final resp = await dio.post('/transcribe/', data: form);
    return resp.data['transcript'] as String;
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
}

@Riverpod(keepAlive: true)
ProxyClient proxyClient(Ref ref) => ProxyClient(ref);
