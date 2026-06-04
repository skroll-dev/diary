import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'transcript_input_sheet.dart';
import 'live_transcript_display.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/proxy_client.dart';
import '../services/recording_service.dart';
import '../../features/recording/recording_context.dart';

export 'recording_controls.dart' show WaveformPainter;

enum RecordingPhase { idle, recording, processing }

/// Reusable recording UI: waveform, timer, mic/stop button, processing state.
/// Handles audio capture + transcription for both web (WebSocket) and native
/// (HTTP). Calls [onComplete] with the raw transcript string when done.
class RecordingControls extends ConsumerStatefulWidget {
  const RecordingControls({
    super.key,
    required this.recordingContext,
    required this.onComplete,
    this.onCancel,
    this.idleLabel = 'Aufnahme starten',
  });

  final RecordingContext recordingContext;
  final Future<void> Function(String rawTranscript) onComplete;
  final VoidCallback? onCancel;
  final String idleLabel;

  @override
  ConsumerState<RecordingControls> createState() => _RecordingControlsState();
}

class _RecordingControlsState extends ConsumerState<RecordingControls>
    with TickerProviderStateMixin {
  RecordingPhase _phase = RecordingPhase.idle;

  late final AnimationController _waveController;
  late final AnimationController _pulseController;
  final _rng = Random(42);
  late final List<double> _barSeeds;

  Timer? _timer;
  int _seconds = 0;
  Future<String>? _wsTranscriptFuture;
  String _confirmedTranscript = '';
  String _interimText = '';

  bool get _hasText => _confirmedTranscript.isNotEmpty || _interimText.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _barSeeds = List.generate(22, (_) => 0.2 + _rng.nextDouble() * 0.8);
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
  }

  @override
  void dispose() {
    _waveController.dispose();
    _pulseController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String get _timerLabel {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _start() async {
    final svc = ref.read(recordingServiceProvider);
    await svc.start();
    if (kIsWeb) {
      _wsTranscriptFuture = ref.read(proxyClientProvider).transcribeWebSocket(
        svc.webAudioStream,
        onInterim: (text) {
          if (mounted) setState(() => _interimText = text);
        },
        onSegment: (text) {
          if (mounted) {
            setState(() {
              _confirmedTranscript = _confirmedTranscript.isEmpty
                  ? text
                  : '$_confirmedTranscript $text';
              _interimText = '';
            });
          }
        },
      );
    }
    setState(() {
      _phase = RecordingPhase.recording;
      _seconds = 0;
    });
    _waveController.repeat();
    _pulseController.repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  Future<void> _showTypeDialog() async {
    final text = await showTranscriptInputSheet(
      context,
      title: 'Transkript eingeben',
      hint: 'Text statt Sprache …',
    );
    if (text == null || text.isEmpty) return;

    setState(() => _phase = RecordingPhase.processing);
    await widget.onComplete(text);
    if (mounted) setState(() => _phase = RecordingPhase.idle);
  }

  Future<void> _stop() async {
    _timer?.cancel();
    _waveController.stop();
    _pulseController.stop();
    _pulseController.reset();
    setState(() => _phase = RecordingPhase.processing);

    try {
      final String rawTranscript;
      if (kIsWeb) {
        await ref.read(recordingServiceProvider).stopStream();
        rawTranscript = await _wsTranscriptFuture!;
      } else {
        final audio = await ref.read(recordingServiceProvider).stopAndRead();
        rawTranscript = await ref.read(proxyClientProvider).transcribe(audio);
      }
      await widget.onComplete(rawTranscript);
    } catch (e) {
      debugPrint('[RecordingControls] error: $e');
    }

    if (mounted) {
      setState(() {
        _phase = RecordingPhase.idle;
        _seconds = 0;
        _wsTranscriptFuture = null;
        _confirmedTranscript = '';
        _interimText = '';
      });
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    _waveController.stop();
    _pulseController.stop();
    _pulseController.reset();
    try {
      if (kIsWeb) {
        await ref.read(recordingServiceProvider).stopStream();
      } else {
        await ref.read(recordingServiceProvider).stopAndRead(); // discard
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _phase = RecordingPhase.idle;
        _seconds = 0;
        _wsTranscriptFuture = null;
        _confirmedTranscript = '';
        _interimText = '';
      });
      widget.onCancel?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isRecording = _phase == RecordingPhase.recording;
    final isProcessing = _phase == RecordingPhase.processing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Waveform + timer + live transcript (visible while recording)
        AnimatedSize(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOut,
          child: isRecording
              ? Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      height: _hasText ? 44 : 80,
                      width: double.infinity,
                      child: AnimatedBuilder(
                        animation: _waveController,
                        builder: (_, __) => CustomPaint(
                          painter: WaveformPainter(
                            value: _waveController.value,
                            seeds: _barSeeds,
                            activeColor: cs.primary,
                            inactiveColor: cs.outlineVariant,
                            compact: _hasText,
                          ),
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      height: _hasText ? 8 : 16,
                    ),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      style: (_hasText
                              ? tt.titleLarge
                              : tt.displaySmall)
                          ?.copyWith(
                            fontWeight: FontWeight.w300,
                            letterSpacing: 3,
                          ) ??
                          const TextStyle(),
                      child: Text(_timerLabel, textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 130),
                      child: LiveTranscriptDisplay(
                        confirmedText: _confirmedTranscript,
                        interimText: _interimText,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                )
              : const SizedBox.shrink(),
        ),

        // Processing state
        if (isProcessing) ...[
          SizedBox(
            width: 36,
            height: 36,
            child:
                CircularProgressIndicator(strokeWidth: 2.0, color: cs.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'Mathias verarbeitet …',
            style: tt.bodyMedium?.copyWith(color: cs.outline),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],

        // Mic / stop button
        if (!isProcessing) ...[
          Stack(
            alignment: Alignment.center,
            children: [
              // Layout anchor — fixed size so the pulse ring (Positioned) never
              // causes 60fps layout thrashing on the parent Column.
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: isRecording ? 114 : 88,
                height: isRecording ? 114 : 88,
              ),
              // Pulse ring is Positioned — purely visual, zero layout impact.
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, __) {
                    final pulse = isRecording
                        ? Curves.easeInOut.transform(_pulseController.value)
                        : 0.0;
                    return Center(
                      child: Container(
                        width: isRecording ? 106 + 8 * pulse : 0,
                        height: isRecording ? 106 + 8 * pulse : 0,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.primary.withValues(
                            alpha: isRecording ? 0.08 + 0.06 * pulse : 0.0,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              GestureDetector(
                onTap: isRecording ? _stop : _start,
                onLongPress: isRecording ? null : _showTypeDialog,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  width: isRecording ? 66 : 88,
                  height: isRecording ? 66 : 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary,
                    boxShadow: isRecording
                        ? [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.22),
                              blurRadius: 14,
                              spreadRadius: 2,
                            ),
                          ]
                        : [],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                      key: ValueKey(isRecording),
                      color: cs.onPrimary,
                      size: isRecording ? 26 : 36,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onDoubleTap: isRecording ? null : _showTypeDialog,
            child: Text(
              isRecording ? 'Tippe zum Beenden' : widget.idleLabel,
              style: tt.bodyMedium?.copyWith(color: cs.outline),
              textAlign: TextAlign.center,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: isRecording
                ? GestureDetector(
                    onTap: _cancel,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      child: Text(
                        'Aufnahme abbrechen',
                        style: tt.labelMedium?.copyWith(
                          color: cs.error.withValues(alpha: 0.65),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }
}

class WaveformPainter extends CustomPainter {
  const WaveformPainter({
    required this.value,
    required this.seeds,
    required this.activeColor,
    required this.inactiveColor,
    this.compact = false,
  });

  final double value;
  final List<double> seeds;
  final Color activeColor;
  final Color inactiveColor;
  final bool compact;

  static const int _count = 22;
  static const double _barW = 4.0;
  static const double _gap = 5.0;
  static const double _minH = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    const totalW = _count * _barW + (_count - 1) * _gap;
    final startX = (size.width - totalW) / 2;
    final cy = size.height / 2;

    for (int i = 0; i < _count; i++) {
      final phase = (i / _count) * 2 * pi;
      final wave = sin(value * 2 * pi + phase) * 0.5 +
          sin(value * 2 * pi * 1.7 + phase * 1.3 + 0.9) * 0.3 +
          sin(value * 2 * pi * 0.5 + phase * 0.7) * 0.2;
      final maxH = compact ? 24.0 : 68.0;
      final h = _minH + seeds[i] * ((wave + 1) / 2) * (maxH - _minH);

      final distFromCenter = (i - _count / 2).abs() / (_count / 2);
      final isActive = distFromCenter < 0.55;

      final x = startX + i * (_barW + _gap) + _barW / 2;
      canvas.drawLine(
        Offset(x, cy - h / 2),
        Offset(x, cy + h / 2),
        Paint()
          ..color = isActive ? activeColor : inactiveColor
          ..strokeWidth = _barW
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) => old.value != value || old.compact != compact;
}
