import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/repositories/entry_repository.dart';
import '../../../shared/services/proxy_client.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _textController;
  late final AnimationController _exitController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _nameOpacity;
  late final Animation<Offset> _nameSlide;
  late final Animation<double> _sloganOpacity;
  late final Animation<double> _exitOpacity;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _logoScale = Tween(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _logoOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _logoController,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _nameOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _textController,
          curve: const Interval(0.0, 0.7, curve: Curves.easeOut)),
    );
    _nameSlide = Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(
          parent: _textController,
          curve: const Interval(0.0, 0.8, curve: Curves.easeOut)),
    );
    _sloganOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _textController,
          curve: const Interval(0.35, 1.0, curve: Curves.easeOut)),
    );
    _exitOpacity = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeIn),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Entrance animations
    await _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 100));
    _textController.forward();

    // Run min-1s hold + DB check in parallel
    final results = await Future.wait([
      Future.delayed(const Duration(milliseconds: 1200)),
      _checkTodaysEntry(),
    ]);

    final destination = results[1] as _Destination;

    // Exit
    await _exitController.forward();
    if (mounted) _navigate(destination);
  }

  Future<_Destination> _checkTodaysEntry() async {
    final isoDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      final repo = ref.read(entryRepositoryProvider);
      await repo.syncEntryFromFirestoreIfMissing(isoDate);
      final entry = await repo.getLocalEntryForDate(isoDate);
      if (entry == null) return const _Destination.recording();

      final topics = (jsonDecode(entry.topics) as List)
          .map((t) => TopicDto.fromJson(t as Map<String, dynamic>))
          .toList();
      final questions =
          (jsonDecode(entry.followUpQuestions) as List).cast<String>();

      return _Destination.topics(
        bodyMarkdown: entry.bodyMarkdown,
        mood: entry.mood,
        moodScore: entry.moodScore,
        followUpQuestions: questions,
        topics: topics,
      );
    } catch (_) {
      return const _Destination.recording();
    }
  }

  void _navigate(_Destination dest) {
    if (dest.goToTopics) {
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

      context.go('/topics', extra: (
        date: dateLabel,
        duration: '',
        topics: dest.topics!,
        normalizedTranscript: '',
        bodyMarkdown: dest.bodyMarkdown!,
        mood: dest.mood!,
        moodScore: dest.moodScore!,
        followUpQuestions: dest.followUpQuestions!,
        transcriptReason: 'initial',
      ));
    } else {
      context.go('/');
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _exitOpacity,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                ScaleTransition(
                  scale: _logoScale,
                  child: FadeTransition(
                    opacity: _logoOpacity,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4A90D9).withValues(alpha: 0.35),
                            blurRadius: 40,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset(
                          'assets/icon/icon.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // App name
                SlideTransition(
                  position: _nameSlide,
                  child: FadeTransition(
                    opacity: _nameOpacity,
                    child: Text(
                      'Mathias',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Slogan
                FadeTransition(
                  opacity: _sloganOpacity,
                  child: Text(
                    'Sprich. Mathias schreibt.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.5),
                          letterSpacing: 0.5,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Destination ───────────────────────────────────────────────────────────────

class _Destination {
  const _Destination.recording()
      : goToTopics = false,
        topics = null,
        bodyMarkdown = null,
        mood = null,
        moodScore = null,
        followUpQuestions = null;

  const _Destination.topics({
    required List<TopicDto> this.topics,
    required String this.bodyMarkdown,
    required String this.mood,
    required double this.moodScore,
    required List<String> this.followUpQuestions,
  }) : goToTopics = true;

  final bool goToTopics;
  final List<TopicDto>? topics;
  final String? bodyMarkdown;
  final String? mood;
  final double? moodScore;
  final List<String>? followUpQuestions;
}
