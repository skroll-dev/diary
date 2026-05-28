import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/recording/presentation/recording_screen.dart';
import '../../features/recording/recording_context.dart';
import '../../features/topics/presentation/topics_review_screen.dart';
import '../../features/entry/presentation/entry_screen.dart';
import '../../features/history/presentation/history_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => RecordingScreen(
          recordingContext:
              state.extra as RecordingContext? ?? const FreshRecording(),
        ),
      ),
      GoRoute(
        path: '/topics',
        builder: (context, state) {
          final args = state.extra as ({String date, String duration})?;
          return TopicsReviewScreen(
            date: args?.date ?? '',
            duration: args?.duration ?? '',
          );
        },
      ),
      GoRoute(
        path: '/entry/:date',
        builder: (context, state) =>
            EntryScreen(date: state.pathParameters['date']!),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
    ],
  );
});
