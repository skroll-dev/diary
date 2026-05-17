import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Screen 4: Eintrag-Ansicht
/// Zeigt generierten Eintrag + Stimmungs-Tag + Folgefragen (MVP-Konzept §6)
class EntryScreen extends ConsumerWidget {
  final String date;
  const EntryScreen({super.key, required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: entryProvider(date) watch
    return Scaffold(
      appBar: AppBar(title: Text(date)),
      body: const Center(
        child: Text('Eintrag wird geladen…'),
      ),
    );
  }
}
