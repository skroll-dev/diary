import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/repositories/entry_repository.dart';
import '../../../shared/services/auth_service.dart';

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
  late final AnimationController _pulseController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _nameOpacity;
  late final Animation<Offset> _nameSlide;
  late final Animation<double> _sloganOpacity;
  late final Animation<double> _exitOpacity;
  late final Animation<double> _pulseScale;

  bool _isSyncingHistory = false;
  int _historyLoaded = 0;
  int _historyTotal = 0;

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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
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
    _pulseScale = Tween(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Entrance animations
    await _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 100));
    _textController.forward();

    _pulseController.repeat(reverse: true);

    // Run min-1s hold + DB check + (if needed) full history sync in parallel
    final results = await Future.wait([
      Future.delayed(const Duration(milliseconds: 1200)),
      _checkTodaysEntry(),
      _syncFullHistoryIfNeeded(),
    ]);

    final destination = results[1] as _Destination;

    // Exit
    _pulseController.stop();
    await _exitController.forward();
    if (mounted) _navigate(destination);
  }

  Future<_Destination> _checkTodaysEntry() async {
    final isoDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      final repo = ref.read(entryRepositoryProvider);
      await repo.syncEntryFromFirestoreIfMissing(isoDate);
      final entry = await repo.getLocalEntryForDate(isoDate);
      // Today already has a saved entry — land on the "Mein Tagebuch"
      // overview with it highlighted, not back in the post-recording review
      // flow (that's only entered right after finishing a recording).
      return entry == null ? _Destination.recording : _Destination.history;
    } catch (_) {
      return _Destination.recording;
    }
  }

  // One-time (per device, per account) backfill of full entry history from
  // Firestore — covers reinstalls / new devices for an already-logged-in
  // account. Anonymous accounts and already-synced devices are a no-op.
  Future<void> _syncFullHistoryIfNeeded() async {
    try {
      final user = await ref.read(authServiceProvider.notifier).getUser();
      if (user.isAnonymous) return;

      final repo = ref.read(entryRepositoryProvider);
      if (await repo.hasHistorySynced(user.uid)) return;

      if (mounted) setState(() => _isSyncingHistory = true);
      await repo.syncAllEntriesFromFirestore(
        onProgress: (loaded, total) {
          if (mounted) {
            setState(() {
              _historyLoaded = loaded;
              _historyTotal = total;
            });
          }
        },
      );
      await repo.markHistorySynced(user.uid);
    } catch (_) {
      // Best-effort — today's entry check still proceeds independently.
    } finally {
      if (mounted) setState(() => _isSyncingHistory = false);
    }
  }

  void _navigate(_Destination dest) {
    switch (dest) {
      case _Destination.history:
        context.go('/history');
      case _Destination.recording:
        context.go('/');
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _exitController.dispose();
    _pulseController.dispose();
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
                  scale: _pulseScale,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: FadeTransition(
                      opacity: _logoOpacity,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C3158),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color: const Color(0xFF4A90D9).withValues(alpha: 0.22),
                              blurRadius: 36,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(18),
                        child: Image.asset(
                          'assets/icon/icon2-no-bg.png',
                          fit: BoxFit.contain,
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
                      'Mein KI-Tagebuch',
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
                    'Sprich. Mein KI-Tagebuch schreibt.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.5),
                          letterSpacing: 0.5,
                        ),
                  ),
                ),
                // Full-history sync progress (only visible during a one-time
                // per-device backfill for an already-logged-in account)
                AnimatedOpacity(
                  opacity: _isSyncingHistory ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Column(
                      children: [
                        SizedBox(
                          width: 140,
                          child: LinearProgressIndicator(
                            value: _historyTotal == 0
                                ? null
                                : _historyLoaded / _historyTotal,
                            color: const Color(0xFF4A90D9),
                            backgroundColor: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _historyTotal == 0
                              ? 'Einträge werden gesucht …'
                              : 'Lade deine Einträge … $_historyLoaded/$_historyTotal',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                        ),
                      ],
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

enum _Destination { recording, history }
