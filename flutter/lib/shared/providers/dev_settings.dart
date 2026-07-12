import 'package:flutter_riverpod/flutter_riverpod.dart';

final useFakeHistoryProvider =
    NotifierProvider<_FakeHistoryNotifier, bool>(_FakeHistoryNotifier.new);

class _FakeHistoryNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}
