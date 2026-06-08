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
