import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/recording/presentation/recording_screen.dart';
import '../../features/recording/recording_context.dart';
import '../../features/topics/presentation/topics_review_screen.dart';
import '../../features/entry/presentation/entry_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../shared/services/proxy_client.dart' show TopicDto;

typedef TopicsArgs = ({
  String date,
  String duration,
  List<TopicDto> topics,
  String transcript,
});

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
          final args = state.extra as TopicsArgs?;
          return TopicsReviewScreen(
            date: args?.date ?? '',
            duration: args?.duration ?? '',
            topics: args?.topics ?? [],
            transcript: args?.transcript ?? '',
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
