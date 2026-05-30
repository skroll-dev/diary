import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/repositories/entry_repository.dart';
import '../../../shared/services/proxy_client.dart';
import '../../../shared/services/recording_service.dart';
import '../recording_context.dart';

enum _RecordingState { idle, recording, processing }

class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({
    super.key,
    this.recordingContext = const FreshRecording(),
  });

  final RecordingContext recordingContext;

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen>
    with TickerProviderStateMixin {
  _RecordingState _state = _RecordingState.idle;

  late final AnimationController _waveController;
  late final AnimationController _pulseController;

  final _rng = Random(42);
  late final List<double> _barSeeds;

  Timer? _timer;
  int _seconds = 0;
  // True after the first recording has been sent to TopicsReviewScreen.
  // Popping back from there means "add more" — not "start fresh".
  bool _hasExistingEntry = false;
  String _lastDate = '';
  String _lastDuration = '';

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

  Future<void> _startRecording() async {
    await ref.read(recordingServiceProvider).start();
    setState(() {
      _state = _RecordingState.recording;
      _seconds = 0;
    });
    _waveController.repeat();
    _pulseController.repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _waveController.stop();
    _pulseController.stop();
    _pulseController.reset();
    setState(() => _state = _RecordingState.processing);

    final date = _dateLabel;
    final duration = _timerLabel;
    final durationSec = _seconds;
    final isoDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      final audio = await ref.read(recordingServiceProvider).stopAndRead();
      final rawTranscript =
          await ref.read(proxyClientProvider).transcribe(audio);
      final normalizedText =
          await ref.read(proxyClientProvider).normalize(rawTranscript);
      await ref.read(entryRepositoryProvider).saveEntry(
            date: isoDate,
            rawTranscript: rawTranscript,
            normalizedText: normalizedText,
            durationSeconds: durationSec,
          );
    } catch (e) {
      debugPrint('[RecordingScreen] pipeline error: $e');
      // TODO: show error snackbar
    }

    if (mounted) {
      setState(() {
        _state = _RecordingState.idle;
        _seconds = 0;
        _hasExistingEntry = true;
        _lastDate = date;
        _lastDuration = duration;
      });
      context.push('/topics', extra: (date: date, duration: duration));
    }
  }

  String get _timerLabel {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _dateLabel {
    final now = DateTime.now();
    const weekdays = ['', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
    const months = ['', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
    return '${weekdays[now.weekday]}, ${now.day}. ${months[now.month]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(child: _appView(context)),
    );
  }

  Widget _appView(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final showBackToTopics =
        _hasExistingEntry && _state == _RecordingState.idle;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showBackToTopics) ...[
            SizedBox(
              height: 44,
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.push(
                    '/topics',
                    extra: (date: _lastDate, duration: _lastDuration),
                  ),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                  label: const Text('Themen'),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.primary,
                    textStyle: tt.bodyMedium,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 52),
          _buildHeader(context),
          const SizedBox(height: 28),
          _buildCenterContent(context),
          const Spacer(),
          _buildCTA(context),
          const SizedBox(height: 56),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final String title = switch (_state) {
      _RecordingState.idle => 'Mathias',
      _RecordingState.recording => 'Mathias hört zu',
      _RecordingState.processing => 'Einen Moment …',
    };

    // Context chip only shown when not processing
    final ctx = widget.recordingContext;
    final showChip = _state != _RecordingState.processing &&
        (ctx is! FreshRecording || _hasExistingEntry);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey('$title-${ctx.runtimeType}'),
        children: [
          Text(
            _dateLabel,
            style: tt.bodyMedium?.copyWith(color: cs.outline),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: tt.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          if (showChip) ...[
            const SizedBox(height: 12),
            _buildContextChip(context),
          ],
        ],
      ),
    );
  }

  Widget _buildContextChip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ctx = widget.recordingContext;

    final (IconData icon, String label, Color color, Color bg) = switch (ctx) {
      ExtendingTopic(:final topicTitle) => (
          Icons.edit_note_rounded,
          'Ergänzt · $topicTitle',
          const Color(0xFF5E35B1),
          const Color(0xFFEDE9FF),
        ),
      AddingTopic() => (
          Icons.add_rounded,
          'Neues Thema',
          cs.primary,
          cs.primaryContainer,
        ),
      FreshRecording() when _hasExistingEntry => (
          Icons.post_add_rounded,
          'Wird zum Eintrag ergänzt',
          cs.primary,
          cs.primaryContainer,
        ),
      _ => (Icons.circle, '', cs.outline, cs.surfaceContainerHighest),
    };

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: tt.labelMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }

  String get _subtitleText {
    return switch (widget.recordingContext) {
      ExtendingTopic(:final followUpHint) when followUpHint != null =>
        followUpHint,
      ExtendingTopic(:final topicTitle) =>
        'Was möchtest du zu\n„$topicTitle" ergänzen?',
      AddingTopic() =>
        'Worum geht es beim neuen Thema?\nErzähl, was dir wichtig ist.',
      FreshRecording() when _hasExistingEntry =>
        'Was möchtest du noch hinzufügen?\nMathias ergänzt deinen Eintrag.',
      _ => 'Erzähl einfach drauflos.\nMathias strukturiert es nachher.',
    };
  }

  Widget _buildCenterContent(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: _state == _RecordingState.processing
              ? Column(
                  key: const ValueKey('processing'),
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.0, color: cs.primary),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Mathias strukturiert deinen Eintrag …',
                      style: tt.bodyMedium?.copyWith(color: cs.outline),
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : Text(
                  key: ValueKey(_subtitleText),
                  _subtitleText,
                  style: tt.bodyLarge?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.38),
                    height: 1.65,
                  ),
                  textAlign: TextAlign.center,
                ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOut,
          child: _state == _RecordingState.recording
              ? Column(
                  children: [
                    const SizedBox(height: 40),
                    SizedBox(
                      height: 80,
                      width: double.infinity,
                      child: AnimatedBuilder(
                        animation: _waveController,
                        builder: (_, __) => CustomPaint(
                          painter: _WaveformPainter(
                            value: _waveController.value,
                            seeds: _barSeeds,
                            activeColor: cs.primary,
                            inactiveColor: cs.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      _timerLabel,
                      textAlign: TextAlign.center,
                      style: tt.displaySmall?.copyWith(
                        fontWeight: FontWeight.w300,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildCTA(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (_state == _RecordingState.processing) {
      return const SizedBox(height: 160);
    }

    final isRecording = _state == _RecordingState.recording;

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, __) {
                final pulse = isRecording
                    ? Curves.easeInOut.transform(_pulseController.value)
                    : 0.0;
                return Container(
                  width: isRecording ? 148 + 10 * pulse : 96,
                  height: isRecording ? 148 + 10 * pulse : 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary.withValues(
                      alpha: isRecording ? 0.08 + 0.06 * pulse : 0.0,
                    ),
                  ),
                );
              },
            ),
            GestureDetector(
              onTap: isRecording ? _stopRecording : _startRecording,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary,
                  boxShadow: isRecording
                      ? [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.28),
                            blurRadius: 24,
                            spreadRadius: 4,
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
                    size: 38,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            isRecording ? 'Tippe zum Beenden' : 'Tagebucheintrag starten',
            key: ValueKey(isRecording),
            style: tt.bodyMedium?.copyWith(color: cs.outline),
          ),
        ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.value,
    required this.seeds,
    required this.activeColor,
    required this.inactiveColor,
  });

  final double value;
  final List<double> seeds;
  final Color activeColor;
  final Color inactiveColor;

  static const int _count = 22;
  static const double _barW = 4.0;
  static const double _gap = 5.0;
  static const double _maxH = 68.0;
  static const double _minH = 5.0;

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
      final h = _minH + seeds[i] * ((wave + 1) / 2) * (_maxH - _minH);

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
  bool shouldRepaint(_WaveformPainter old) => old.value != value;
}
