import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'file_io_web.dart' if (dart.library.io) 'file_io_native.dart';

part 'recording_service.g.dart';

typedef AudioData = ({Uint8List bytes, String contentType});

class RecordingPermissionDenied implements Exception {}

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
      // Native: start() does not request RECORD_AUDIO itself — without this,
      // AudioRecord init fails silently on Android (status -1).
      if (!await _recorder.hasPermission()) {
        throw RecordingPermissionDenied();
      }
      final dir = await getTemporaryDirectory();
      _tempPath =
          '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
      // WAV/PCM, not AAC-in-MP4: some Android vendors' hardware AAC encoders
      // produce MP4 containers that Chirp 3's AutoDetectDecodingConfig
      // silently fails to decode (0 results, no error) even though the file
      // is valid and plays back fine locally. WAV sidesteps that entirely.
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
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
    return (bytes: bytes, contentType: 'audio/wav');
  }

  Future<void> dispose() => _recorder.dispose();
}

@Riverpod(keepAlive: true)
RecordingService recordingService(Ref ref) {
  final svc = RecordingService();
  ref.onDispose(svc.dispose);
  return svc;
}
