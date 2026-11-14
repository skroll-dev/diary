import 'package:ai_tagebuch/shared/constants/transcript_limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isUsableTranscript', () {
    test('rejects silence', () {
      expect(isUsableTranscript(''), isFalse);
      expect(isUsableTranscript('   \n '), isFalse);
    });

    test('rejects text the backend would refuse', () {
      expect(isUsableTranscript('a' * (kMinTranscriptChars - 1)), isFalse);
    });

    test('ignores surrounding whitespace when measuring', () {
      expect(isUsableTranscript('  ${'a' * (kMinTranscriptChars - 1)}  '), isFalse);
    });

    test('accepts text at the minimum length', () {
      expect(isUsableTranscript('a' * kMinTranscriptChars), isTrue);
    });
  });
}
