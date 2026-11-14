import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/legal_urls.dart';
import '../extensions/localization_extensions.dart';
import '../services/ai_consent_service.dart';

/// Returns true once the user allows sending content to the AI providers,
/// asking first if needed. Call before any user content leaves the device.
Future<bool> ensureAiConsent(BuildContext context, WidgetRef ref) async {
  if (await ref.read(aiConsentProvider.future)) return true;
  if (!context.mounted) return false;
  final languageCode = Localizations.localeOf(context).languageCode;
  final agreed = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const AiConsentSheet(),
  );
  if (agreed != true) return false;
  await ref.read(aiConsentProvider.notifier).grant(languageCode);
  return true;
}

class AiConsentSheet extends StatelessWidget {
  const AiConsentSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final languageCode = Localizations.localeOf(context).languageCode;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.aiConsentTitle,
                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.aiConsentIntro,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _Disclosure(
                icon: Icons.mic_none_rounded,
                title: l10n.aiConsentWhatTitle,
                body: l10n.aiConsentWhatBody,
              ),
              _Disclosure(
                icon: Icons.cloud_outlined,
                title: l10n.aiConsentWhoTitle,
                body: l10n.aiConsentWhoBody,
              ),
              _Disclosure(
                icon: Icons.lock_outline_rounded,
                title: l10n.aiConsentWhereTitle,
                body: l10n.aiConsentWhereBody,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.aiConsentSensitive,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => openLegalUrl(privacyPolicyUrl(languageCode)),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: Text(l10n.legalPrivacyPolicy),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(l10n.aiConsentDecline),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(l10n.aiConsentAgree),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Disclosure extends StatelessWidget {
  const _Disclosure({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  body,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
