import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/app_preferences.dart';

part 'locale_provider.g.dart';

/// The user's explicitly chosen app language, or null to follow the device's
/// system language (resolved by [MaterialApp.localeResolutionCallback]).
@Riverpod(keepAlive: true)
class LocaleController extends _$LocaleController {
  @override
  Locale? build() {
    final prefsAsync = ref.watch(appPreferencesProvider);
    return prefsAsync.when(
      data: (prefs) => prefs.localeCode == null ? null : Locale(prefs.localeCode!),
      loading: () => null,
      error: (_, __) => null,
    );
  }

  Future<void> setLocale(Locale? locale) async {
    state = locale; // optimistic — UI reacts immediately
    final prefs = await ref.read(appPreferencesProvider.future);
    await prefs.setLocaleCode(locale?.languageCode);
  }
}
