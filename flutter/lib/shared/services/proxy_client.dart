import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_service.dart';
import 'recording_service.dart' show AudioData;

part 'proxy_client.g.dart';

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
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
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
}

@Riverpod(keepAlive: true)
ProxyClient proxyClient(Ref ref) => ProxyClient(ref);
