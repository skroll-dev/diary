import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/repositories/entry_repository.dart';
import '../../../shared/services/auth_error_provider.dart';
import '../../../shared/services/auth_service.dart'
    show AuthLinkError, authServiceProvider;
import '../../../shared/services/proxy_client.dart';
import '../../../shared/widgets/profile_avatar_button.dart';
import '../../../shared/services/recording_service.dart';
import '../../auth/presentation/auth_sheet.dart';
import '../../../shared/widgets/live_transcript_display.dart';
import '../../../shared/widgets/recording_controls.dart';
import '../../../shared/widgets/transcript_input_sheet.dart';
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
  String _confirmedTranscript = '';
  String _interimText = '';
  String _version = '';
  StreamSubscription<User?>? _authSub;
  bool _checkingEntry = false;
  bool _authSheetOpen = false;

  // Pipeline progress
  double _pipelinePercent = 0.0;
  String _pipelineStep = '';
  Timer? _progressTimer;

  bool get _hasText => _confirmedTranscript.isNotEmpty || _interimText.isNotEmpty;

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
    // Only react to auth state changes when NO explicit sign-in is in progress.
    // This covers email-link on web (fresh page load, no auth sheet).
    // Google/email-sheet flows are handled by _onSignInTap instead.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && !user.isAnonymous && mounted && !_authSheetOpen) {
        _checkForExistingTodayEntry();
      }
    });
    // ref.listen only fires on changes; if the error was set before this
    // screen was built (e.g. expired email link on cold start), check once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final error = ref.read(authLinkErrorProvider);
      if (error != null && mounted) {
        ref.read(authLinkErrorProvider.notifier).clear();
        _showAuthLinkErrorDialog(error);
      }
    });
  }

  void _setStep(String label, double start, double end) {
    _progressTimer?.cancel();
    setState(() {
      _pipelinePercent = start;
      _pipelineStep = label;
    });
    // Exponential approach: each tick closes 2.5% of remaining gap.
    // Self-adapting — no timing estimate needed. Reaches ~97% of the range
    // after ~14s, so the final snap to _completeStep is barely visible.
    _progressTimer = Timer.periodic(const Duration(milliseconds: 80), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _pipelinePercent += (end - _pipelinePercent) * 0.025);
    });
  }

  void _completeStep(double pct) {
    _progressTimer?.cancel();
    if (mounted) setState(() => _pipelinePercent = pct);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _waveController.dispose();
    _pulseController.dispose();
    _timer?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final svc = ref.read(recordingServiceProvider);
    await svc.start();
    // Reset transcripts here in case a previous session's late callbacks wrote
    // stale text after a cancel.
    _confirmedTranscript = '';
    _interimText = '';
    if (kIsWeb) {
      _wsTranscriptFuture = ref.read(proxyClientProvider).transcribeWebSocket(
        svc.webAudioStream,
        onInterim: (text) {
          if (mounted && _state == _RecordingState.recording) {
            setState(() => _interimText = text);
          }
        },
        onSegment: (text) {
          if (mounted && _state == _RecordingState.recording) {
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
      final sw = Stopwatch()..start();

      _setStep('Mathias hört zu …', 0.0, 0.35);
      final String rawTranscript;
      if (kIsWeb) {
        await ref.read(recordingServiceProvider).stopStream();
        rawTranscript = await _wsTranscriptFuture!;
      } else {
        final audio = await ref.read(recordingServiceProvider).stopAndRead();
        rawTranscript = await ref.read(proxyClientProvider).transcribe(audio);
      }
      _completeStep(0.35);
      debugPrint('[Pipeline] transcribe: ${sw.elapsedMilliseconds}ms');
      sw.reset(); sw.start();

      _setStep('Mathias liest deinen Text …', 0.36, 0.55);
      normalizedText = await ref.read(proxyClientProvider).normalize(rawTranscript);
      _completeStep(0.55);
      debugPrint('[Pipeline] normalize: ${sw.elapsedMilliseconds}ms');
      sw.reset(); sw.start();

      _setStep('Mathias denkt nach …', 0.56, 1.0);
      final entry = await ref.read(proxyClientProvider).generateEntry(normalizedText);
      topics = entry.topics;
      bodyMarkdown = entry.bodyMarkdown;
      mood = entry.mood;
      moodScore = entry.moodScore;
      followUpQuestions = entry.followUpQuestions;
      _completeStep(1.0);
      debugPrint('[Pipeline] generate: ${sw.elapsedMilliseconds}ms');
      sw.reset(); sw.start();

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
      debugPrint('[Pipeline] save: ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('[RecordingScreen] pipeline error: $e');
    }

    if (mounted) {
      setState(() {
        _state = _RecordingState.idle;
        _seconds = 0;
        _wsTranscriptFuture = null;
        _confirmedTranscript = '';
        _interimText = '';
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

  Future<void> _cancelRecording() async {
    _timer?.cancel();
    _waveController.stop();
    _pulseController.stop();
    _pulseController.reset();
    try {
      if (kIsWeb) {
        await ref.read(recordingServiceProvider).stopStream();
      } else {
        await ref.read(recordingServiceProvider).stopAndRead(); // discard bytes
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _state = _RecordingState.idle;
        _seconds = 0;
        _wsTranscriptFuture = null;
        _confirmedTranscript = '';
        _interimText = '';
      });
    }
  }

  // Long-press mic: type a transcript instead of speaking (works in all builds)
  Future<void> _showTranscriptDialog() async {
    final rawTranscript = await showTranscriptInputSheet(
      context,
      title: 'Transkript eingeben',
      hint: 'Rohes Transkript …',
    );
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
      final sw = Stopwatch()..start();

      _setStep('Mathias liest deinen Text …', 0.0, 0.30);
      normalizedText = await ref.read(proxyClientProvider).normalize(rawTranscript);
      _completeStep(0.30);
      debugPrint('[Pipeline] normalize (typed): ${sw.elapsedMilliseconds}ms');
      sw.reset(); sw.start();

      _setStep('Mathias denkt nach …', 0.31, 1.0);
      final entry = await ref.read(proxyClientProvider).generateEntry(normalizedText);
      topics = entry.topics;
      bodyMarkdown = entry.bodyMarkdown;
      mood = entry.mood;
      moodScore = entry.moodScore;
      followUpQuestions = entry.followUpQuestions;
      _completeStep(1.0);
      debugPrint('[Pipeline] generate (typed): ${sw.elapsedMilliseconds}ms');
      sw.reset(); sw.start();

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
      debugPrint('[Pipeline] save (typed): ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('[RecordingScreen] pipeline error: $e');
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

  void _showAuthLinkErrorDialog(AuthLinkError error) {
    final (title, message) = switch (error) {
      AuthLinkError.expiredLink => (
          'Link abgelaufen',
          'Dieser Anmelde-Link ist nicht mehr gültig. Bitte fordere einen neuen Link an.',
        ),
      AuthLinkError.emailNotFound => (
          'E-Mail nicht gefunden',
          'Bitte öffne den Link in demselben Browser, in dem du die E-Mail angefordert hast, oder fordere einen neuen Link an.',
        ),
    };
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              showAuthSheet(context, isDismissible: true);
            },
            child: const Text('Neuen Link anfordern'),
          ),
        ],
      ),
    );
  }

  Future<void> _onSignInTap() async {
    _authSheetOpen = true;
    final success = await showAuthSheet(context, isDismissible: true);
    _authSheetOpen = false;
    if (!success || !mounted) return;
    await _checkForExistingTodayEntry();
  }

  Future<void> _checkForExistingTodayEntry() async {
    if (_checkingEntry) return;
    if (!mounted) return;
    _checkingEntry = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                      color: Theme.of(ctx).colorScheme.primary),
                  const SizedBox(height: 20),
                  Text('Eintrag wird geladen …',
                      style: Theme.of(ctx).textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final isoDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final repo = ref.read(entryRepositoryProvider);
    final currentUid = FirebaseAuth.instance.currentUser!.uid;

    // Detect recording made as anonymous user before this sign-in.
    final orphan = await repo.getOrphanedEntryForDate(isoDate, currentUid);

    await repo.syncEntryFromFirestoreIfMissing(isoDate);
    var entry = await repo.getLocalEntryForDate(isoDate);

    // If we recorded as anonymous AND the account already has an entry today,
    // merge them so nothing is lost.
    if (orphan != null && entry != null) {
      final orphanTranscripts = await repo.getTranscriptsForEntry(orphan.id);
      final combined = orphanTranscripts
          .map((t) => t.normalizedContent.isNotEmpty ? t.normalizedContent : t.content)
          .where((s) => s.isNotEmpty)
          .join('\n\n');
      if (combined.isNotEmpty) {
        try {
          final merged = await ref.read(proxyClientProvider).mergeEntry(
                existingBody: entry.bodyMarkdown,
                newTranscript: combined,
                previousQuestions:
                    (jsonDecode(entry.followUpQuestions) as List).cast<String>(),
              );
          await repo.mergeEntry(
            date: isoDate,
            rawTranscript: combined,
            normalizedText: combined,
            bodyMarkdown: merged.bodyMarkdown,
            mood: merged.mood,
            moodScore: merged.moodScore,
            followUpQuestions: merged.followUpQuestions,
            topics: merged.topics,
            transcriptReason: 'continuation',
          );
          entry = await repo.getLocalEntryForDate(isoDate);
        } catch (_) {
          // Merge failed — fall through and show the cloud entry unchanged.
        }
      }
      // Clean up the orphaned anonymous entry.
      unawaited(repo.deleteEntryById(orphan.id).catchError((_) {}));
    }

    _checkingEntry = false;
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (entry == null) return;

    final topics = (jsonDecode(entry.topics) as List)
        .map((t) => TopicDto.fromJson(t as Map<String, dynamic>))
        .toList();
    final questions =
        (jsonDecode(entry.followUpQuestions) as List).cast<String>();

    final now = DateTime.now();
    const weekdays = [
      '', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag',
      'Freitag', 'Samstag', 'Sonntag'
    ];
    const months = [
      '', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
    ];
    final dateLabel =
        '${weekdays[now.weekday]}, ${now.day}. ${months[now.month]}';

    if (mounted) {
      context.push('/topics', extra: (
        date: dateLabel,
        duration: '',
        topics: topics,
        normalizedTranscript: '',
        bodyMarkdown: entry.bodyMarkdown,
        mood: entry.mood,
        moodScore: entry.moodScore,
        followUpQuestions: questions,
        transcriptReason: 'initial',
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
    ref.listen<AuthLinkError?>(authLinkErrorProvider, (_, error) {
      if (error == null || !mounted) return;
      ref.read(authLinkErrorProvider.notifier).clear();
      _showAuthLinkErrorDialog(error);
    });

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Stack(
          children: [
            _appView(context),
            const Positioned(
              top: 8, right: 12,
              child: ProfileAvatarButton(),
            ),
          ],
        ),
      ),
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
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: _pipelinePercent),
                        duration: const Duration(milliseconds: 200),
                        builder: (_, v, __) => Text(
                          '${(v * 100).round()}%',
                          style: tt.displayLarge?.copyWith(
                            fontSize: 88,
                            fontWeight: FontWeight.w200,
                            color: cs.primary,
                            letterSpacing: -2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _pipelineStep,
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
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        height: _hasText ? 20 : 40,
                      ),
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
                        height: _hasText ? 10 : 28,
                      ),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        style: (_hasText ? tt.titleLarge : tt.displaySmall)
                                ?.copyWith(
                                  fontWeight: FontWeight.w300,
                                  letterSpacing: 3,
                                ) ??
                            const TextStyle(),
                        child: Text(_timerLabel, textAlign: TextAlign.center),
                      ),
                      const SizedBox(height: 16),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          // Live transcript fills all remaining space between timer and button
          Expanded(
            child: isRecording
                ? LiveTranscriptDisplay(
                    confirmedText: _confirmedTranscript,
                    interimText: _interimText,
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          if (!isProcessing) _buildMicButton(context),
          const SizedBox(height: 16),
          if (_state == _RecordingState.idle &&
              ref.watch(authServiceProvider).when(
                data: (u) => u.isAnonymous,
                loading: () => true,
                error: (_, __) => true,
              )) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () async {
                _authSheetOpen = true;
                final success = await showAuthSheet(context, isDismissible: true);
                _authSheetOpen = false;
                if (success && mounted) await _checkForExistingTodayEntry();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 13, color: cs.onSurface.withValues(alpha: 0.35)),
                    const SizedBox(width: 6),
                    Text(
                      'Bereits registriert? ',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                    Text(
                      'Anmelden',
                      style: tt.labelSmall?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_version.isNotEmpty && _state == _RecordingState.idle)
            GestureDetector(
              onDoubleTap: _showTranscriptDialog,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _version,
                  textAlign: TextAlign.center,
                  style: tt.labelSmall?.copyWith(color: cs.outlineVariant),
                ),
              ),
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
            // Layout anchor — transitions once on start/stop, never on pulse frames.
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: isRecording ? 114 : 96,
              height: isRecording ? 114 : 96,
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
              onTap: isRecording ? _stopRecording : _startRecording,
              onLongPress: isRecording ? null : _showTranscriptDialog,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: isRecording ? 66 : 96,
                height: isRecording ? 66 : 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary,
                  boxShadow: isRecording
                      ? [BoxShadow(color: cs.primary.withValues(alpha: 0.22), blurRadius: 14, spreadRadius: 2)]
                      : [],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                    key: ValueKey(isRecording),
                    color: cs.onPrimary,
                    size: isRecording ? 26 : 38,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            isRecording ? 'Tippe zum Beenden' : 'Tagebucheintrag starten',
            key: ValueKey(isRecording),
            style: tt.bodyMedium?.copyWith(color: cs.outline),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: isRecording
              ? GestureDetector(
                  onTap: _cancelRecording,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 10),
                    child: Text(
                      'Aufnahme abbrechen',
                      style: tt.labelMedium?.copyWith(
                        color: cs.error.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

