import 'package:flutter/widgets.dart';

import '../extensions/localization_extensions.dart';

/// Human-readable label for a Firebase Auth provider id, e.g. as shown next
/// to "Anmeldung"/"Sign-in" on the profile and entry screens.
String providerLabel(BuildContext context, String providerId) => switch (providerId) {
      'google.com' => 'Google',
      'password' || 'emailLink' => context.l10n.providerEmailLink,
      _ => providerId,
    };
