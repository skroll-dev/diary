import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'recording_service.g.dart';

class RecordingPermissionDenied implements Exception {}

class RecordingService {
  final _recorder = AudioRecorder();
  Stream<Uint8List>? _audioStream;

  // Native AudioContext rate on most browsers/OS — no resampling needed.
  // Forcing 16000 Hz causes Chrome to report an inconsistent context rate,
  // making the worklet passthrough incorrect audio (sounds WAY too slow).
  static const int webSampleRate = 44100;
  static const int nativeSampleRate = 16000;

  /// PCM16 mono rate of [audioStream].
  static int get sampleRate => kIsWeb ? webSampleRate : nativeSampleRate;

  /// Starts streaming PCM16 audio. Audio stays in memory and is never written
  /// to disk.
  Future<void> start() async {
    // Native: starting does not request RECORD_AUDIO itself — without this,
    // AudioRecord init fails silently on Android (status -1).
    if (!kIsWeb && !await _recorder.hasPermission()) {
      throw RecordingPermissionDenied();
    }
    _audioStream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        // AudioWorklet max; WS batching in proxy_client
        streamBufferSize: kIsWeb ? 8192 : null,
      ),
    );
  }

  /// The live audio stream started by [start].
  Stream<Uint8List> get audioStream {
    assert(_audioStream != null, 'audioStream accessed outside a recording session');
    return _audioStream!;
  }

  /// Stops the recorder, which closes [audioStream].
  Future<void> stop() async {
    await _recorder.stop();
    _audioStream = null;
  }

  Future<void> dispose() => _recorder.dispose();
}

@Riverpod(keepAlive: true)
RecordingService recordingService(Ref ref) {
  final svc = RecordingService();
  ref.onDispose(svc.dispose);
  return svc;
}
