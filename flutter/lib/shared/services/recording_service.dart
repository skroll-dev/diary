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
  Stream<Uint8List>? _webStream;

  // Native AudioContext rate on most browsers/OS — no resampling needed.
  // Forcing 16000 Hz causes Chrome to report an inconsistent context rate,
  // making the worklet passthrough incorrect audio (sounds WAY too slow).
  static const int webSampleRate = 44100;

  Future<void> start() async {
    if (kIsWeb) {
      _webStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: webSampleRate,
          numChannels: 1,
          streamBufferSize: 8192, // AudioWorklet max; WS batching in proxy_client
        ),
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

  /// Web only: the live audio stream started by [start].
  Stream<Uint8List> get webAudioStream {
    assert(kIsWeb && _webStream != null, 'webAudioStream accessed outside web recording session');
    return _webStream!;
  }

  /// Web only: stops the recorder, which closes [webAudioStream].
  Future<void> stopStream() async {
    await _recorder.stop();
    _webStream = null;
  }

  /// Native only: stops the recorder and returns the recorded bytes.
  Future<AudioData> stopAndRead() async {
    final path = await _recorder.stop();
    final bytes = await readAndDeleteFile(_tempPath ?? path ?? '');
    _tempPath = null;
    return (bytes: bytes, contentType: 'audio/m4a');
  }

  Future<void> dispose() => _recorder.dispose();
}

@Riverpod(keepAlive: true)
RecordingService recordingService(Ref ref) {
  final svc = RecordingService();
  ref.onDispose(svc.dispose);
  return svc;
}
