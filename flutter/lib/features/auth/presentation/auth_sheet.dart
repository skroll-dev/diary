import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../shared/services/auth_service.dart';

Future<bool> showAuthSheet(
  BuildContext context, {
  bool isDismissible = false,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    backgroundColor: Colors.transparent,
    builder: (_) => _AuthSheet(isDismissible: isDismissible),
  );
  return result ?? false;
}

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _AuthSheet extends ConsumerStatefulWidget {
  const _AuthSheet({this.isDismissible = false});

  final bool isDismissible;

  @override
  ConsumerState<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends ConsumerState<_AuthSheet> {
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    // When the user taps the email link (app reopens), the deep link handler
    // in main.dart calls completeEmailLinkSignIn → auth state changes →
    // this listener fires and dismisses the sheet.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && !user.isAnonymous && mounted) {
        Navigator.of(context).pop(true);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _emailCtrl.dispose();
    super.dispose();
  }

  // ── Handlers ─────────────────────────────────────────────────────────────────

  Future<void> _onGoogleTap() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authServiceProvider.notifier).linkWithGoogle();
      if (mounted) Navigator.of(context).pop(true);
    } on UidChangedNotice {
      if (mounted) Navigator.of(context).pop(true);
    } on GoogleCancelledException {
      // user cancelled — silent
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _localizeError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onSendLinkTap() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Bitte E-Mail-Adresse eingeben.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      if (email == 'review@tester.com') {
        await ref
            .read(authServiceProvider.notifier)
            .signInWithPassword(email, 'tester');
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      await ref.read(authServiceProvider.notifier).sendEmailLink(email);
      if (mounted) setState(() => _emailSent = true);
    } on UidChangedNotice {
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _localizeError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _localizeError(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => 'Ungültige E-Mail-Adresse.',
        'too-many-requests' => 'Zu viele Versuche. Bitte kurz warten.',
        'network-request-failed' => 'Keine Internetverbindung.',
        _ => 'Fehler: ${e.message ?? e.code}',
      };

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: _emailSent ? _buildConfirmation(cs, tt) : _buildInput(cs, tt),
      ),
    );
  }

  Widget _buildInput(ColorScheme cs, TextTheme tt) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Drag handle + optional close button
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (widget.isDismissible)
              Positioned(
                right: 0,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: Icon(Icons.close_rounded, color: cs.outline, size: 20),
                  tooltip: 'Schließen',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),

        // Headline
        Text(
          widget.isDismissible ? 'Anmelden' : 'Eintrag sichern',
          style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Erstelle ein kostenloses Konto, um deinen Eintrag dauerhaft zu schützen.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 10),

        // Trust line
        Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 14, color: cs.outline),
            const SizedBox(width: 5),
            Text(
              'Deine Daten bleiben in der EU.',
              style: tt.labelSmall?.copyWith(color: cs.outline),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Google button (primary CTA)
        _GoogleSignInButton(
          onPressed: _isLoading ? null : _onGoogleTap,
          isLoading: _isLoading,
        ),
        const SizedBox(height: 20),

        // Divider
        Row(
          children: [
            Expanded(child: Divider(color: cs.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'oder',
                style: tt.labelSmall?.copyWith(color: cs.outline),
              ),
            ),
            Expanded(child: Divider(color: cs.outlineVariant)),
          ],
        ),
        const SizedBox(height: 20),

        // Email field
        TextField(
          controller: _emailCtrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _onSendLinkTap(),
          decoration: InputDecoration(
            labelText: 'E-Mail-Adresse',
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
          ),
        ),

        // Error message
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: tt.bodySmall?.copyWith(color: cs.error),
          ),
        ],
        const SizedBox(height: 16),

        // Send link button
        OutlinedButton(
          onPressed: _isLoading ? null : _onSendLinkTap,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: BorderSide(color: cs.outlineVariant),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            textStyle: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          child: _isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: cs.primary),
                )
              : const Text('Link senden'),
        ),
      ],
    );
  }

  Widget _buildConfirmation(ColorScheme cs, TextTheme tt) {
    final email = _emailCtrl.text.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Drag handle
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 32),

        // Icon + headline
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.mail_outline_rounded,
                size: 28, color: cs.onPrimaryContainer),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Link gesendet!',
          textAlign: TextAlign.center,
          style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          'Wir haben einen Link an $email geschickt. Öffne deine E-Mails und tippe auf den Link — du wirst automatisch angemeldet.',
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 28),

        TextButton(
          onPressed: () => setState(() {
            _emailSent = false;
            _errorMessage = null;
          }),
          child: Text(
            'Anderen Link senden',
            style: tt.labelLarge?.copyWith(color: cs.primary),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Google Sign-In button (official branding) ─────────────────────────────────

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.onPressed, required this.isLoading});

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isDark ? const Color(0xFF131314) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F);
    final borderColor = isDark ? const Color(0xFF8E918F) : const Color(0xFF747775);

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: textColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: BorderSide(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: textColor,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/icon/google-icon.svg',
                    width: 20,
                    height: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Mit Google fortfahren',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
