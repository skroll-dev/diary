import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/repositories/entry_repository.dart';
import '../../../shared/services/proxy_client.dart';
import '../../../shared/services/recording_service.dart';
import '../../../shared/widgets/recording_controls.dart';
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
  Future<String>? _wsTranscriptFuture;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _barSeeds = List.generate(22, (_) => 0.2 + _rng.nextDouble() * 0.8);
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'v${info.version}');
    });
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
    final svc = ref.read(recordingServiceProvider);
    await svc.start();
    if (kIsWeb) {
      _wsTranscriptFuture = ref
          .read(proxyClientProvider)
          .transcribeWebSocket(svc.webAudioStream);
    }
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
    final reason = _transcriptReason;

    var topics = <TopicDto>[];
    var normalizedText = '';
    var bodyMarkdown = '';
    var mood = 'neutral';
    var moodScore = 0.0;
    var followUpQuestions = <String>[];

    try {
      final String rawTranscript;
      if (kIsWeb) {
        await ref.read(recordingServiceProvider).stopStream();
        rawTranscript = await _wsTranscriptFuture!;
      } else {
        final audio = await ref.read(recordingServiceProvider).stopAndRead();
        rawTranscript = await ref.read(proxyClientProvider).transcribe(audio);
      }
      normalizedText = await ref.read(proxyClientProvider).normalize(rawTranscript);
      final entry = await ref.read(proxyClientProvider).generateEntry(normalizedText);
      topics = entry.topics;
      bodyMarkdown = entry.bodyMarkdown;
      mood = entry.mood;
      moodScore = entry.moodScore;
      followUpQuestions = entry.followUpQuestions;
      await ref.read(entryRepositoryProvider).saveEntry(
            date: isoDate,
            rawTranscript: rawTranscript,
            normalizedText: normalizedText,
            durationSeconds: durationSec,
            bodyMarkdown: bodyMarkdown,
            mood: mood,
            moodScore: moodScore,
            followUpQuestions: followUpQuestions,
            topics: topics,
            transcriptReason: reason,
          );
    } catch (e) {
      debugPrint('[RecordingScreen] pipeline error: $e');
    }

    if (mounted) {
      setState(() {
        _state = _RecordingState.idle;
        _seconds = 0;
        _wsTranscriptFuture = null;
      });
      context.push('/topics', extra: (
        date: date,
        duration: duration,
        topics: topics,
        normalizedTranscript: normalizedText,
        bodyMarkdown: bodyMarkdown,
        mood: mood,
        moodScore: moodScore,
        followUpQuestions: followUpQuestions,
        transcriptReason: reason,
      ));
    }
  }

  // Debug: long-press mic to inject text transcript
  Future<void> _showTranscriptDialog() async {
    final controller = TextEditingController();
    final rawTranscript = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transkript eingeben'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Rohes Transkript …',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Verarbeiten'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (rawTranscript == null || rawTranscript.isEmpty) return;

    setState(() => _state = _RecordingState.processing);
    final date = _dateLabel;
    final isoDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final reason = _transcriptReason;

    var topics = <TopicDto>[];
    var normalizedText = '';
    var bodyMarkdown = '';
    var mood = 'neutral';
    var moodScore = 0.0;
    var followUpQuestions = <String>[];

    try {
      normalizedText = await ref.read(proxyClientProvider).normalize(rawTranscript);
      final entry = await ref.read(proxyClientProvider).generateEntry(normalizedText);
      topics = entry.topics;
      bodyMarkdown = entry.bodyMarkdown;
      mood = entry.mood;
      moodScore = entry.moodScore;
      followUpQuestions = entry.followUpQuestions;
      await ref.read(entryRepositoryProvider).saveEntry(
            date: isoDate,
            rawTranscript: rawTranscript,
            normalizedText: normalizedText,
            durationSeconds: 0,
            bodyMarkdown: bodyMarkdown,
            mood: mood,
            moodScore: moodScore,
            followUpQuestions: followUpQuestions,
            topics: topics,
            transcriptReason: reason,
          );
    } catch (e) {
      debugPrint('[RecordingScreen] debug pipeline error: $e');
    }

    if (mounted) {
      setState(() => _state = _RecordingState.idle);
      context.push('/topics', extra: (
        date: date,
        duration: '00:00',
        topics: topics,
        normalizedTranscript: normalizedText,
        bodyMarkdown: bodyMarkdown,
        mood: mood,
        moodScore: moodScore,
        followUpQuestions: followUpQuestions,
        transcriptReason: reason,
      ));
    }
  }

  String get _transcriptReason => switch (widget.recordingContext) {
        ExtendingTopic(:final followUpHint) when followUpHint != null =>
          'followUp:$followUpHint',
        ExtendingTopic() => 'continuation',
        ContinuingEntry() => 'continuation',
        _ => 'initial',
      };

  String get _timerLabel {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _dateLabel {
    final now = DateTime.now();
    const weekdays = [
      '', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag',
      'Freitag', 'Samstag', 'Sonntag'
    ];
    const months = [
      '', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
    ];
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
    final isRecording = _state == _RecordingState.recording;
    final isProcessing = _state == _RecordingState.processing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 52),
          _buildHeader(context),
          const SizedBox(height: 28),
          // Subtitle / processing indicator
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: isProcessing
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
          // Waveform + timer while recording
          AnimatedSize(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOut,
            child: isRecording
                ? Column(
                    children: [
                      const SizedBox(height: 40),
                      SizedBox(
                        height: 80,
                        width: double.infinity,
                        child: AnimatedBuilder(
                          animation: _waveController,
                          builder: (_, __) => CustomPaint(
                            painter: WaveformPainter(
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
          const Spacer(),
          if (!isProcessing) _buildMicButton(context),
          const SizedBox(height: 16),
          if (_version.isNotEmpty && _state == _RecordingState.idle)
            Text(
              _version,
              textAlign: TextAlign.center,
              style: tt.labelSmall?.copyWith(color: cs.outlineVariant),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ctx = widget.recordingContext;
    final showChip = _state != _RecordingState.processing && ctx is! FreshRecording;

    final String title = switch (_state) {
      _RecordingState.idle => 'Mathias',
      _RecordingState.recording => 'Mathias hört zu',
      _RecordingState.processing => 'Einen Moment …',
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.12), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey('$title-${ctx.runtimeType}'),
        children: [
          Text(_dateLabel, style: tt.bodyMedium?.copyWith(color: cs.outline)),
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
      ContinuingEntry() => (
          Icons.post_add_rounded,
          'Ergänzt den Eintrag',
          cs.primary,
          cs.primaryContainer,
        ),
      _ => (Icons.circle, '', cs.outline, cs.surfaceContainerHighest),
    };

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(label, style: tt.labelMedium?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }

  String get _subtitleText => switch (widget.recordingContext) {
        ExtendingTopic(:final followUpHint) when followUpHint != null =>
          followUpHint,
        ExtendingTopic(:final topicTitle) =>
          'Was möchtest du zu\n„$topicTitle" ergänzen?',
        ContinuingEntry() =>
          'Einfach weiterreden —\nMathias ordnet es ein.',
        _ => 'Erzähl einfach drauflos.\nMathias strukturiert es nachher.',
      };

  Widget _buildMicButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
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
              onLongPress: isRecording ? null : _showTranscriptDialog,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary,
                  boxShadow: isRecording
                      ? [BoxShadow(color: cs.primary.withValues(alpha: 0.28), blurRadius: 24, spreadRadius: 4)]
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

