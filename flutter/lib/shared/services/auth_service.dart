import 'package:firebase_auth/firebase_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_service.g.dart';

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
}
