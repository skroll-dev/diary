import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Screen 5: Verlauf
/// Chronologische Liste vergangener Tage (MVP-Konzept §6)
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: historyProvider watch
    return Scaffold(
      appBar: AppBar(title: const Text('Verlauf')),
      body: const Center(
        child: Text('Keine Einträge vorhanden.'),
      ),
    );
  }
}
