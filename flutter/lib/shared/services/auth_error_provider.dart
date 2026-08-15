import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_service.dart' show AuthLinkError;

part 'auth_error_provider.g.dart';

@Riverpod(keepAlive: true)
class AuthLinkErrorNotifier extends _$AuthLinkErrorNotifier {
  @override
  AuthLinkError? build() => null;

  void set(AuthLinkError error) => state = error;
  void clear() => state = null;
}

/// Set to true after an email-link sign-in completes successfully, so the UI
/// can show a one-shot confirmation and then clear it.
@Riverpod(keepAlive: true)
class AuthLinkSuccessNotifier extends _$AuthLinkSuccessNotifier {
  @override
  bool build() => false;

  void set() => state = true;
  void clear() => state = false;
}
