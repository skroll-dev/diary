import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/repositories/entry_repository.dart';
import '../../../shared/services/auth_service.dart';
import '../../../shared/widgets/profile_avatar_button.dart';

class EntryScreen extends ConsumerWidget {
  final String date;
  const EntryScreen({super.key, required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final authAsync = ref.watch(authServiceProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(date),
        actions: const [ProfileAvatarButton(), SizedBox(width: 8)],
      ),
      body: authAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (user) => _Body(user: user, cs: cs, tt: tt),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.user, required this.cs, required this.tt});

  final User user;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<int>(
      future: ref.read(entryRepositoryProvider).getEntryCount(),
      builder: (context, snap) {
        final count = snap.data;

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          children: [
            // ── Account section ──────────────────────────────────────────────
            _SectionLabel(label: 'Konto', cs: cs, tt: tt),
            const SizedBox(height: 12),
            _InfoTile(
              icon: user.isAnonymous
                  ? Icons.person_outline_rounded
                  : Icons.verified_user_outlined,
              label: 'Status',
              value: user.isAnonymous ? 'Anonym' : 'Angemeldet',
              cs: cs,
              tt: tt,
            ),
            if (!user.isAnonymous && user.email != null) ...[
              const SizedBox(height: 8),
              _InfoTile(
                icon: Icons.mail_outline_rounded,
                label: 'E-Mail',
                value: user.email!,
                cs: cs,
                tt: tt,
              ),
            ],
            if (!user.isAnonymous && user.providerData.isNotEmpty) ...[
              const SizedBox(height: 8),
              _InfoTile(
                icon: Icons.link_rounded,
                label: 'Anmeldung',
                value: _providerLabel(user.providerData.first.providerId),
                cs: cs,
                tt: tt,
              ),
            ],
            const SizedBox(height: 28),

            // ── Diary section ────────────────────────────────────────────────
            _SectionLabel(label: 'Tagebuch', cs: cs, tt: tt),
            const SizedBox(height: 12),
            _InfoTile(
              icon: Icons.book_outlined,
              label: 'Gespeicherte Einträge',
              value: count != null ? '$count' : '…',
              cs: cs,
              tt: tt,
            ),
          ],
        );
      },
    );
  }

  String _providerLabel(String providerId) => switch (providerId) {
        'google.com' => 'Google',
        'password' => 'E-Mail-Link',
        'emailLink' => 'E-Mail-Link',
        _ => providerId,
      };
}

// ── Small components ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(
      {required this.label, required this.cs, required this.tt});
  final String label;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: tt.labelSmall?.copyWith(
        color: cs.outline,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.cs,
    required this.tt,
  });
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
