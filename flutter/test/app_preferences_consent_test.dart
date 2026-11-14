import 'package:ai_tagebuch/shared/services/app_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<AppPreferences> prefs() async {
    SharedPreferences.setMockInitialValues({});
    return AppPreferences(await SharedPreferences.getInstance());
  }

  test('has no consent by default', () async {
    final p = await prefs();

    expect(p.aiConsentVersion, isNull);
    expect(p.aiConsentGrantedAt, isNull);
  });

  test('keeps version, time and language of a grant', () async {
    final p = await prefs();
    final at = DateTime.utc(2026, 11, 1, 12);

    await p.setAiConsent(version: 1, grantedAt: at, languageCode: 'de');

    expect(p.aiConsentVersion, 1);
    expect(p.aiConsentGrantedAt, at);
    expect(p.aiConsentLanguageCode, 'de');
  });

  test('withdrawing clears everything', () async {
    final p = await prefs();
    await p.setAiConsent(
        version: 1, grantedAt: DateTime.utc(2026), languageCode: 'en');

    await p.clearAiConsent();

    expect(p.aiConsentVersion, isNull);
    expect(p.aiConsentGrantedAt, isNull);
    expect(p.aiConsentLanguageCode, isNull);
  });
}
