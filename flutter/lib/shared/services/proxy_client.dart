import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_service.dart';

part 'proxy_client.g.dart';

const _baseUrl = String.fromEnvironment(
  'PROXY_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

class ProxyClient {
  const ProxyClient(this._ref);
  final Ref _ref;

  Future<Dio> _dio() async {
    final token = await _ref.read(authServiceProvider.notifier).getIdToken();
    final dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      headers: {'Authorization': 'Bearer $token'},
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

  Future<String> transcribe(Uint8List audioBytes) async {
    final dio = await _dio();
    final form = FormData.fromMap({
      'audio': MultipartFile.fromBytes(
        audioBytes,
        filename: 'recording.m4a',
        contentType: DioMediaType('audio', 'm4a'),
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
