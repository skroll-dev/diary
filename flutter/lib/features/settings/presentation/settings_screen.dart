import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/extensions/localization_extensions.dart';
import '../../../shared/providers/locale_provider.dart';
import '../../../shared/repositories/entry_repository.dart';
import '../../../shared/services/auth_service.dart';
import '../../../shared/services/gdpr_export_client.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final selectedLocale = ref.watch(localeControllerProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(l10n.settingsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
        children: [
          Text(
            l10n.settingsLanguageSection.toUpperCase(),
            style: tt.labelSmall?.copyWith(
              color: cs.outline,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _LanguageOption(
            label: l10n.settingsLanguageSystem,
            selected: selectedLocale == null,
            onTap: () => ref.read(localeControllerProvider.notifier).setLocale(null),
          ),
          const SizedBox(height: 8),
          _LanguageOption(
            label: l10n.settingsLanguageGerman,
            selected: selectedLocale?.languageCode == 'de',
            onTap: () => ref
                .read(localeControllerProvider.notifier)
                .setLocale(const Locale('de')),
          ),
          const SizedBox(height: 8),
          _LanguageOption(
            label: l10n.settingsLanguageEnglish,
            selected: selectedLocale?.languageCode == 'en',
            onTap: () => ref
                .read(localeControllerProvider.notifier)
                .setLocale(const Locale('en')),
          ),
          const SizedBox(height: 36),

          // ── Danger zone ──────────────────────────────────────────────────
          Text(
            l10n.sectionDangerZone.toUpperCase(),
            style: tt.labelSmall?.copyWith(
              color: cs.outline,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _confirmWipeAllData(context, ref),
            icon: Icon(Icons.delete_forever_rounded, color: cs.error, size: 18),
            label: Text(
              l10n.profileDeleteAllData,
              style: TextStyle(color: cs.error),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: cs.error),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              textStyle: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmWipeAllData(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmWord = l10n.profileWipeConfirmWord;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _WipeConfirmDialog(confirmWord: confirmWord),
    );
    if (confirmed != true || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Theme.of(ctx).colorScheme.primary),
                  const SizedBox(height: 20),
                  Text(l10n.profileWipingDataProgress,
                      style: Theme.of(ctx).textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      // Remote deletion first — only wipe local data once the account and
      // its Firestore data are confirmed gone, so a failed request never
      // loses data that only existed on this device.
      await ref.read(gdprExportClientProvider).deleteAccount();
      await ref.read(entryRepositoryProvider).clearAllLocalData();
      await ref.read(authServiceProvider.notifier).signOut();
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        context.go('/');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(l10n.profileDeleteFailedTitle),
            content: Text(l10n.profileDeleteFailedBody('$e')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.ok),
              ),
            ],
          ),
        );
      }
    }
  }
}

// ── Wipe-all-data confirmation dialog ───────────────────────────────────────────

// Owns its TextEditingController via State so Flutter disposes it as part of
// the widget's own lifecycle. Disposing it manually right after showDialog()
// returns races the dialog's closing transition (still rebuilding this
// TextField for a few more frames) and throws "used after being disposed".
class _WipeConfirmDialog extends StatefulWidget {
  const _WipeConfirmDialog({required this.confirmWord});
  final String confirmWord;

  @override
  State<_WipeConfirmDialog> createState() => _WipeConfirmDialogState();
}

class _WipeConfirmDialogState extends State<_WipeConfirmDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final match = _ctrl.text.trim().toUpperCase() == widget.confirmWord;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(l10n.profileWipeConfirmTitle,
          style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.profileWipeConfirmBody),
          const SizedBox(height: 16),
          Text(l10n.profileWipeConfirmPrompt(widget.confirmWord),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(hintText: widget.confirmWord),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: match ? () => Navigator.of(context).pop(true) : null,
          style: TextButton.styleFrom(foregroundColor: cs.error),
          child: Text(l10n.profileWipeConfirmButton),
        ),
      ],
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

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
            Expanded(
              child: Text(label, style: tt.bodyMedium),
            ),
            if (selected) Icon(Icons.check_rounded, color: cs.primary, size: 20),
          ],
        ),
      ),
    );
  }
}
