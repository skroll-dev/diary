import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'app_preferences.g.dart';

/// Central store for user-configurable app preferences.
/// Backed by SharedPreferences (key-value, survives restarts).
/// Add new preferences here; the settings screen will expose them later.
class AppPreferences {
  AppPreferences(this._prefs);
  final SharedPreferences _prefs;

  // ── Keys ──────────────────────────────────────────────────────────────────
  static const _kDenoiseAudio = 'denoise_audio';
  static const _kLocale = 'app_locale';

  // ── Transcription ─────────────────────────────────────────────────────────

  /// Enable Chirp 3's built-in noise reducer (removes background noise such as
  /// rain, traffic, or music; cannot remove background voices).
  /// Defaults to false.
  bool get denoiseAudio => _prefs.getBool(_kDenoiseAudio) ?? false;

  Future<void> setDenoiseAudio(bool value) =>
      _prefs.setBool(_kDenoiseAudio, value);

  // ── Language ──────────────────────────────────────────────────────────────

  /// User-selected language code ('de' or 'en'), or null to follow the
  /// device's system language.
  String? get localeCode => _prefs.getString(_kLocale);

  Future<void> setLocaleCode(String? code) => code == null
      ? _prefs.remove(_kLocale)
      : _prefs.setString(_kLocale, code);
}

@Riverpod(keepAlive: true)
Future<AppPreferences> appPreferences(Ref ref) async {
  final prefs = await SharedPreferences.getInstance();
  return AppPreferences(prefs);
}
