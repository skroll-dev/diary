import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/extensions/localization_extensions.dart';
import '../../../shared/widgets/profile_avatar_button.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.analyticsTitle),
        actions: const [ProfileAvatarButton(), SizedBox(width: 8)],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_rounded, size: 56, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text(
              context.l10n.analyticsComingSoonTitle,
              style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.analyticsComingSoonBody,
              style: tt.bodyMedium?.copyWith(color: cs.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
