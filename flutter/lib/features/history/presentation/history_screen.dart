import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/profile_avatar_button.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verlauf'),
        actions: const [ProfileAvatarButton(), SizedBox(width: 8)],
      ),
      body: const Center(
        child: Text('Keine Einträge vorhanden.'),
      ),
    );
  }
}
