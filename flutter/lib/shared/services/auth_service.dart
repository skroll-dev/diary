import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'auth_service.g.dart';

class GoogleCancelledException implements Exception {
  const GoogleCancelledException();
}

class UidChangedNotice implements Exception {
  const UidChangedNotice();
}

class EmailNotFoundForLinkException implements Exception {
  const EmailNotFoundForLinkException();
}

enum AuthLinkError { expiredLink, emailNotFound }

@Riverpod(keepAlive: true)
class AuthService extends _$AuthService {
  @override
  Future<User> build() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return auth.currentUser!;
    final cred = await auth.signInAnonymously();
    return cred.user!;
  }

  Future<User> getUser() => future;

  Future<String> getIdToken() async {
    final user = await future;
    return await user.getIdToken() ?? '';
  }

  bool get isAnonymous {
    final s = state;
    if (s is AsyncData<User>) return s.value.isAnonymous;
    return true;
  }

  Future<void> sendEmailLink(String email) async {
    // On web use the current origin so links work on localhost too.
    final continueUrl =
        kIsWeb ? Uri.base.origin : 'https://diary-6fa61.firebaseapp.com';
    final settings = ActionCodeSettings(
      url: continueUrl,
      handleCodeInApp: true,
      iOSBundleId: 'com.diary.app',
      androidPackageName: 'com.diary.app',
      androidInstallApp: false,
      androidMinimumVersion: '1',
    );
    await FirebaseAuth.instance.sendSignInLinkToEmail(
      email: email,
      actionCodeSettings: settings,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('email_link_pending', email);
  }

  Future<void> completeEmailLinkSignIn(String link) async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email_link_pending');
    if (email == null) throw const EmailNotFoundForLinkException();

    final credential = EmailAuthProvider.credentialWithLink(
      email: email,
      emailLink: link,
    );
    final currentUser = await getUser();
    if (currentUser.isAnonymous) {
      try {
        final result = await currentUser.linkWithCredential(credential);
        _updateState(result.user!);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use' ||
            e.code == 'credential-already-in-use') {
          final result =
              await FirebaseAuth.instance.signInWithCredential(credential);
          _updateState(result.user!);
          throw const UidChangedNotice();
        }
        rethrow;
      }
    } else {
      final result =
          await FirebaseAuth.instance.signInWithCredential(credential);
      _updateState(result.user!);
    }
    await prefs.remove('email_link_pending');
  }

  Future<void> linkWithGoogle() async {
    final auth = FirebaseAuth.instance;
    final currentUser = await getUser();
    OAuthCredential credential;

    if (kIsWeb) {
      final result = await auth.signInWithPopup(GoogleAuthProvider());
      credential = GoogleAuthProvider.credential(
        accessToken: result.credential?.accessToken,
        idToken: (result.credential as OAuthCredential?)?.idToken,
      );
    } else {
      final account = await GoogleSignIn().signIn();
      if (account == null) throw const GoogleCancelledException();
      final googleAuth = await account.authentication;
      credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
    }

    if (currentUser.isAnonymous) {
      try {
        final result = await currentUser.linkWithCredential(credential);
        _updateState(result.user!);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'credential-already-in-use') {
          final result = await auth.signInWithCredential(credential);
          _updateState(result.user!);
          throw const UidChangedNotice();
        }
        rethrow;
      }
    } else {
      final result = await auth.signInWithCredential(credential);
      _updateState(result.user!);
    }
  }

  Future<void> updateDisplayName(String name) async {
    final user = await getUser();
    await user.updateDisplayName(name.trim().isEmpty ? null : name.trim());
    _updateState(FirebaseAuth.instance.currentUser!);
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    final cred = await FirebaseAuth.instance.signInAnonymously();
    _updateState(cred.user!);
  }

  void _updateState(User user) => state = AsyncData(user);
}
