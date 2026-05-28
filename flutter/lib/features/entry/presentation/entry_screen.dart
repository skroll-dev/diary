import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EntryScreen extends ConsumerWidget {
  final String date;
  const EntryScreen({super.key, required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(date),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction_rounded, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'IN PROGRESS',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: cs.outline,
                    letterSpacing: 2,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
