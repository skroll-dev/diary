import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_service.dart';

part 'gdpr_export_client.g.dart';

const _baseUrl = String.fromEnvironment(
  'GDPR_EXPORT_BASE_URL',
  defaultValue: 'http://localhost:8081',
);

class GdprExportClient {
  const GdprExportClient(this._ref);
  final Ref _ref;

  Future<Dio> _dio() async {
    final token = await _ref.read(authServiceProvider.notifier).getIdToken();
    return Dio(BaseOptions(
      baseUrl: _baseUrl,
      headers: {'Authorization': 'Bearer $token'},
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));
  }

  /// Permanently deletes all Firestore data and the Firebase Auth account for
  /// the current user (DSGVO Art. 17 — right to erasure). Irreversible.
  Future<void> deleteAccount() async {
    final dio = await _dio();
    await dio.delete('/account');
  }
}

@Riverpod(keepAlive: true)
GdprExportClient gdprExportClient(Ref ref) => GdprExportClient(ref);
