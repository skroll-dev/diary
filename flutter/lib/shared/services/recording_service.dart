import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'file_io_web.dart' if (dart.library.io) 'file_io_native.dart';

part 'recording_service.g.dart';

typedef AudioData = ({Uint8List bytes, String contentType});

class RecordingService {
  final _recorder = AudioRecorder();
  String? _tempPath;

  Future<void> start() async {
    if (kIsWeb) {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: '',
      );
    } else {
      final dir = await getTemporaryDirectory();
      _tempPath =
          '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000),
        path: _tempPath!,
      );
    }
  }

  Future<AudioData> stopAndRead() async {
    final path = await _recorder.stop();

    if (kIsWeb) {
      final response = await Dio().get<List<int>>(
        path!,
        options: Options(responseType: ResponseType.bytes),
      );
      return (
        bytes: Uint8List.fromList(response.data!),
        contentType: 'audio/wav',
      );
    } else {
      final bytes = await readAndDeleteFile(_tempPath!);
      _tempPath = null;
      return (bytes: bytes, contentType: 'audio/m4a');
    }
  }

  Future<void> dispose() => _recorder.dispose();
}

@Riverpod(keepAlive: true)
RecordingService recordingService(Ref ref) {
  final svc = RecordingService();
  ref.onDispose(svc.dispose);
  return svc;
}
