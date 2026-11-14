import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app_preferences.dart';
import 'auth_service.dart';

part 'ai_consent_service.g.dart';

/// Bump when what the consent sheet discloses changes materially: every user
/// is then asked again.
const kAiConsentVersion = 1;

/// Whether the user currently allows their content to be sent to the AI
/// providers. Nothing may reach `ProxyClient` without it; use
/// `ensureAiConsent` from `ai_consent_sheet.dart`.
@Riverpod(keepAlive: true)
class AiConsent extends _$AiConsent {
  @override
  Future<bool> build() async {
    // The uid changes on an anonymous → existing-account swap, and the proof
    // of consent has to follow the user to that account.
    ref.listen(authServiceProvider, (previous, next) {
      final uid = next.value?.uid;
      if (uid != null && uid != previous?.value?.uid && state.value == true) {
        unawaited(_recordCurrentConsent());
      }
    });
    final prefs = await ref.watch(appPreferencesProvider.future);
    return prefs.aiConsentVersion == kAiConsentVersion;
  }

  Future<void> grant(String languageCode) async {
    final prefs = await ref.read(appPreferencesProvider.future);
    await prefs.setAiConsent(
      version: kAiConsentVersion,
      grantedAt: DateTime.now().toUtc(),
      languageCode: languageCode,
    );
    state = const AsyncData(true);
    await _recordCurrentConsent();
  }

  Future<void> withdraw() async {
    final prefs = await ref.read(appPreferencesProvider.future);
    await prefs.clearAiConsent();
    state = const AsyncData(false);
    _record({
      'status': 'withdrawn',
      'version': kAiConsentVersion,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _recordCurrentConsent() async {
    final prefs = await ref.read(appPreferencesProvider.future);
    _record({
      'status': 'granted',
      'version': prefs.aiConsentVersion,
      'at': prefs.aiConsentGrantedAt?.toIso8601String(),
      'locale': prefs.aiConsentLanguageCode,
    });
  }

  // Proof of consent (Art. 7(1) GDPR). Best-effort, like all Firestore sync:
  // the local preference is what gates AI calls.
  void _record(Map<String, Object?> consent) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    unawaited(FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'aiConsent': consent}, SetOptions(merge: true))
        .catchError((Object e) => debugPrint('[AiConsent] sync failed: $e')));
  }
}
