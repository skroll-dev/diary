import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/recording/presentation/recording_screen.dart';
import '../../features/entry/presentation/entry_screen.dart';
import '../../features/history/presentation/history_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const RecordingScreen(),
      ),
      GoRoute(
        path: '/entry/:date',
        builder: (context, state) => EntryScreen(date: state.pathParameters['date']!),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
    ],
  );
});
