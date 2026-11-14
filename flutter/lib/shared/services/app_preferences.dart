import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'app_preferences.g.dart';

/// One-time UI hints. Each is shown once per device, then remembered as seen.
/// Add new hints here; the enum name is part of the stored key, so never
/// rename an existing value.
enum AppHint {
  /// Pencil on the date leaf of a fresh entry changes its date.
  entryDatePencil,
}

/// Central store for user-configurable app preferences.
/// Backed by SharedPreferences (key-value, survives restarts).
/// Add new preferences here; the settings screen will expose them later.
class AppPreferences {
  AppPreferences(this._prefs);
  final SharedPreferences _prefs;

  // ── Keys ──────────────────────────────────────────────────────────────────
  static const _kDenoiseAudio = 'denoise_audio';
  static const _kLocale = 'app_locale';
  static const _kAiConsentVersion = 'ai_consent_version';
  static const _kAiConsentGrantedAt = 'ai_consent_granted_at';
  static const _kAiConsentLanguageCode = 'ai_consent_language_code';

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

  // ── AI consent ────────────────────────────────────────────────────────────

  /// Version of the consent text the user agreed to, or null if they haven't
  /// (or have withdrawn). Read it through `aiConsentProvider`.
  int? get aiConsentVersion => _prefs.getInt(_kAiConsentVersion);

  DateTime? get aiConsentGrantedAt {
    final stored = _prefs.getString(_kAiConsentGrantedAt);
    return stored == null ? null : DateTime.parse(stored);
  }

  String? get aiConsentLanguageCode => _prefs.getString(_kAiConsentLanguageCode);

  Future<void> setAiConsent({
    required int version,
    required DateTime grantedAt,
    required String languageCode,
  }) async {
    await _prefs.setInt(_kAiConsentVersion, version);
    await _prefs.setString(_kAiConsentGrantedAt, grantedAt.toIso8601String());
    await _prefs.setString(_kAiConsentLanguageCode, languageCode);
  }

  Future<void> clearAiConsent() async {
    await _prefs.remove(_kAiConsentVersion);
    await _prefs.remove(_kAiConsentGrantedAt);
    await _prefs.remove(_kAiConsentLanguageCode);
  }

  // ── Hints ─────────────────────────────────────────────────────────────────

  static String _hintKey(AppHint hint) => 'hint_seen_${hint.name}';

  bool isHintSeen(AppHint hint) => _prefs.getBool(_hintKey(hint)) ?? false;

  Future<void> markHintSeen(AppHint hint) =>
      _prefs.setBool(_hintKey(hint), true);
}

@Riverpod(keepAlive: true)
Future<AppPreferences> appPreferences(Ref ref) async {
  final prefs = await SharedPreferences.getInstance();
  return AppPreferences(prefs);
}
