import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_service.dart';
import '../models/entry_image.dart';

part 'image_proxy_client.g.dart';

/// Thrown when image-proxy rejects an upload with a 422 validation error
/// (e.g. the per-entry image cap).
class ImageProxyValidationException implements Exception {
  ImageProxyValidationException(this.message);
  final String message;

  @override
  String toString() => 'ImageProxyValidationException($message)';
}

Never _rethrowAsValidationError(DioException e) {
  if (e.response?.statusCode == 422) {
    final detail = e.response?.data is Map ? (e.response?.data as Map)['detail'] : null;
    if (detail is String) {
      throw ImageProxyValidationException(detail);
    }
  }
  throw e;
}

const _baseUrl = String.fromEnvironment(
  'IMAGE_PROXY_BASE_URL',
  defaultValue: 'https://image-proxy-918937960824.europe-west3.run.app',
);

class ImageProxyClient {
  const ImageProxyClient(this._ref);
  final Ref _ref;

  // Unlike ProxyClient, this always attaches the real ID token — even for a
  // local image-proxy — so local runs resolve the same uid as production
  // rather than a synthetic one (image-proxy has no ENV=development auth
  // bypass; see image-proxy/app/services/auth.py).
  Future<Dio> _dio() async {
    final token = await _ref.read(authServiceProvider.notifier).getIdToken();
    return Dio(BaseOptions(
      baseUrl: _baseUrl,
      headers: {'Authorization': 'Bearer $token'},
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));
  }

  /// Uploads a single photo. image-proxy resizes it into a full + thumb
  /// variant and writes both to Storage under the caller's own uid folder
  /// (derived server-side from the ID token — never trust a client uid).
  Future<EntryImage> uploadImage({
    required String entryId,
    required String date,
    required int entryOrdinal,
    required int existingImageCount,
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    final dio = await _dio();
    final parts = contentType.split('/');
    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType(parts.first, parts.last),
      ),
      'date': date,
      'entry_ordinal': '$entryOrdinal',
      'entry_id': entryId,
      'existing_image_count': '$existingImageCount',
    });
    try {
      final resp = await dio.post('/images/upload', data: form);
      final j = resp.data as Map<String, dynamic>;
      return EntryImage(
        fullPath: j['full_path'] as String,
        thumbPath: j['thumb_path'] as String,
        order: existingImageCount,
        width: j['width'] as int,
        height: j['height'] as int,
        thumbWidth: j['thumb_width'] as int,
        thumbHeight: j['thumb_height'] as int,
      );
    } on DioException catch (e) {
      _rethrowAsValidationError(e);
    }
  }

  /// Deletes the given Storage object paths (full + thumb variants). Silent
  /// no-op for an empty list.
  Future<void> deleteImages(List<String> objectPaths) async {
    if (objectPaths.isEmpty) return;
    final dio = await _dio();
    await dio.post('/images/delete', data: {'object_paths': objectPaths});
  }
}

@Riverpod(keepAlive: true)
ImageProxyClient imageProxyClient(Ref ref) => ImageProxyClient(ref);
