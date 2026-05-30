import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'recording_service.g.dart';

class RecordingService {
  final _recorder = AudioRecorder();
  String? _tempPath;

  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    _tempPath =
        '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000),
      path: _tempPath!,
    );
  }

  Future<Uint8List> stopAndRead() async {
    await _recorder.stop();
    final file = File(_tempPath!);
    final bytes = await file.readAsBytes();
    await file.delete();
    _tempPath = null;
    return bytes;
  }

  Future<void> dispose() => _recorder.dispose();
}

@Riverpod(keepAlive: true)
RecordingService recordingService(Ref ref) {
  final svc = RecordingService();
  ref.onDispose(svc.dispose);
  return svc;
}
