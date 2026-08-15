import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/analytics/presentation/analytics_screen.dart';
import '../../features/recording/presentation/recording_screen.dart';
import '../../features/recording/recording_context.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/topics/presentation/topics_review_screen.dart';
import '../../features/entry/presentation/entry_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../shared/services/proxy_client.dart' show TopicDto;
import '../../shared/widgets/main_shell.dart';

typedef TopicsArgs = ({
  String date,
  String duration,
  List<TopicDto> topics,
  String normalizedTranscript,
  String bodyMarkdown,
  String mood,
  double moodScore,
  List<String> followUpQuestions,
  String transcriptReason, // 'initial' | 'followUp:...' | 'continuation'
});

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    // On Android/iOS, the platform can report the raw incoming email-link
    // sign-in URL (e.g. https://diary-6fa61.firebaseapp.com/__/auth/links?...)
    // as the initial route before app_links/auth_service finish handling it
    // in the background. Redirect any such unrecognized absolute-URL route to
    // splash instead of letting go_router throw "no routes for location".
    redirect: (context, state) {
      final uri = state.uri;
      if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
        return '/splash';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),

      // ── Shell: screens with bottom navigation ──────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(shell: shell),
        branches: [
          // Heute
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => RecordingScreen(
                  recordingContext:
                      state.extra as RecordingContext? ?? const FreshRecording(),
                ),
              ),
            ],
          ),
          // Verlauf
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (context, state) => const HistoryScreen(),
              ),
            ],
          ),
          // Analyse
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/analytics',
                builder: (context, state) => const AnalyticsScreen(),
              ),
            ],
          ),
        ],
      ),

      // ── Screens without bottom navigation ─────────────────────────────────
      GoRoute(
        path: '/topics',
        builder: (context, state) {
          final args = state.extra as TopicsArgs?;
          return TopicsReviewScreen(
            date: args?.date ?? '',
            duration: args?.duration ?? '',
            topics: args?.topics ?? [],
            normalizedTranscript: args?.normalizedTranscript ?? '',
            bodyMarkdown: args?.bodyMarkdown ?? '',
            mood: args?.mood ?? 'neutral',
            moodScore: args?.moodScore ?? 0.0,
            followUpQuestions: args?.followUpQuestions ?? [],
            transcriptReason: args?.transcriptReason ?? 'initial',
          );
        },
      ),
      GoRoute(
        path: '/entry/:date',
        builder: (context, state) =>
            EntryScreen(date: state.pathParameters['date']!),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
    ],
  );
});
