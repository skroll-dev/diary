import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/repositories/entry_repository.dart';
import '../../../shared/services/auth_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final authAsync = ref.watch(authServiceProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Profil'),
      ),
      body: authAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (user) => _ProfileBody(user: user),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.user});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return FutureBuilder<ProfileStats>(
      future: ref.read(entryRepositoryProvider).getProfileStats(),
      builder: (context, snap) {
        final stats = snap.data;

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
          children: [
            // ── User header ──────────────────────────────────────────────────
            Center(
              child: Column(
                children: [
                  _Avatar(photoUrl: user.photoURL, size: 72),
                  const SizedBox(height: 14),
                  if (user.displayName != null) ...[
                    Text(
                      user.displayName!,
                      style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (user.email != null)
                    Text(
                      user.email!,
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  const SizedBox(height: 8),
                  _ProviderChip(providerId: _primaryProviderId(user)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Name tile ────────────────────────────────────────────────────
            _SectionLabel('Persönlich', cs: cs, tt: tt),
            const SizedBox(height: 12),
            _EditableTile(
              icon: Icons.badge_outlined,
              label: 'Name',
              value: user.displayName,
              placeholder: 'Kein Name gesetzt',
              cs: cs,
              tt: tt,
              onTap: () => _editName(context, ref, user.displayName),
            ),
            const SizedBox(height: 32),

            // ── Statistics ───────────────────────────────────────────────────
            _SectionLabel('Statistiken', cs: cs, tt: tt),
            const SizedBox(height: 12),
            _StatTile(
              icon: Icons.book_outlined,
              label: 'Einträge gesamt',
              value: stats != null ? '${stats.totalEntries}' : '…',
              cs: cs, tt: tt,
            ),
            const SizedBox(height: 8),
            _StatTile(
              icon: Icons.timer_outlined,
              label: 'Gesamtdauer',
              value: stats != null ? _formatDuration(stats.totalDurationSeconds) : '…',
              cs: cs, tt: tt,
            ),
            if (stats?.firstEntryDate != null) ...[
              const SizedBox(height: 8),
              _StatTile(
                icon: Icons.calendar_today_outlined,
                label: 'Erste Aufnahme',
                value: _formatDate(stats!.firstEntryDate!),
                cs: cs, tt: tt,
              ),
            ],
            if (stats?.latestEntryDate != null) ...[
              const SizedBox(height: 8),
              _StatTile(
                icon: Icons.update_rounded,
                label: 'Letzte Aufnahme',
                value: _formatDate(stats!.latestEntryDate!),
                cs: cs, tt: tt,
              ),
            ],
            if (stats?.topMood != null) ...[
              const SizedBox(height: 8),
              _StatTile(
                icon: Icons.mood_rounded,
                label: 'Häufigste Stimmung',
                value: _moodLabel(stats!.topMood!),
                cs: cs, tt: tt,
              ),
            ],
            const SizedBox(height: 36),

            // ── Account actions ──────────────────────────────────────────────
            _SectionLabel('Konto', cs: cs, tt: tt),
            const SizedBox(height: 12),
            _StatTile(
              icon: Icons.fingerprint_rounded,
              label: 'Benutzer-ID',
              value: user.uid,
              cs: cs, tt: tt,
              valueStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context, ref),
              icon: Icon(Icons.logout_rounded, color: cs.error, size: 18),
              label: Text(
                'Abmelden',
                style: TextStyle(color: cs.error),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: BorderSide(color: cs.error.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  String _primaryProviderId(User user) =>
      user.providerData.isNotEmpty ? user.providerData.first.providerId : '';

  Future<void> _editName(
      BuildContext context, WidgetRef ref, String? current) async {
    final ctrl = TextEditingController(text: current ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Dein Name'),
          onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (saved == null || !context.mounted) return;
    await ref.read(authServiceProvider.notifier).updateDisplayName(saved);
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Abmelden?'),
          content: const Text(
              'Du wirst abgemeldet. Deine Einträge bleiben auf diesem Gerät gespeichert.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: const Text('Abmelden'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await ref.read(entryRepositoryProvider).clearUserData();
    await ref.read(authServiceProvider.notifier).signOut();
    if (context.mounted) context.go('/');
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatDuration(int totalSeconds) {
  if (totalSeconds == 0) return '—';
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}min';
  if (m > 0) return '${m}min';
  return '${totalSeconds}s';
}

String _formatDate(String isoDate) {
  try {
    final d = DateTime.parse(isoDate);
    const months = [
      '', 'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
      'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
    ];
    return '${d.day}. ${months[d.month]} ${d.year}';
  } catch (_) {
    return isoDate;
  }
}

String _moodLabel(String mood) => switch (mood) {
      'happy' => '😊 Glücklich',
      'calm' => '😌 Ruhig',
      'tense' => '😰 Angespannt',
      'sad' => '😔 Traurig',
      'mixed' => '🤔 Gemischt',
      _ => '😐 Neutral',
    };

// ── Small components ──────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoUrl, required this.size});

  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: cs.primaryContainer,
      backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
      child: photoUrl == null
          ? Icon(Icons.person_rounded,
              size: size * 0.55, color: cs.onPrimaryContainer)
          : null,
    );
  }
}

class _ProviderChip extends StatelessWidget {
  const _ProviderChip({required this.providerId});

  final String providerId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (IconData icon, String label) = switch (providerId) {
      'google.com' => (Icons.g_mobiledata_rounded, 'Google'),
      'emailLink' || 'password' => (Icons.mail_outline_rounded, 'E-Mail-Link'),
      _ => (Icons.person_outline_rounded, 'Konto'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {required this.cs, required this.tt});

  final String label;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) => Text(
        label.toUpperCase(),
        style: tt.labelSmall?.copyWith(
          color: cs.outline,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      );
}

class _EditableTile extends StatelessWidget {
  const _EditableTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.cs,
    required this.tt,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String placeholder;
  final ColorScheme cs;
  final TextTheme tt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSet = value != null && value!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
              child: Text(label,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
            Text(
              isSet ? value! : placeholder,
              style: tt.bodyMedium?.copyWith(
                fontWeight: isSet ? FontWeight.w600 : FontWeight.w400,
                color: isSet ? null : cs.outline,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.edit_outlined, size: 14, color: cs.outline),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.cs,
    required this.tt,
    this.valueStyle,
  });

  final IconData icon;
  final String label;
  final String value;
  final ColorScheme cs;
  final TextTheme tt;
  final TextStyle? valueStyle;

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
            child: Text(label,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Text(
            value,
            style: valueStyle ??
                tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
