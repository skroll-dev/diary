sealed class RecordingContext {
  const RecordingContext();
}

final class FreshRecording extends RecordingContext {
  const FreshRecording();
}

final class ExtendingTopic extends RecordingContext {
  const ExtendingTopic({
    required this.entryId,
    required this.topicTitle,
    this.followUpHint,
  });
  final String entryId;
  final String topicTitle;
  final String? followUpHint;
}

/// General continuation — user keeps talking without a specific topic target.
/// Mein KI-Tagebuch decides which topic(s) the new content belongs to.
final class ContinuingEntry extends RecordingContext {
  const ContinuingEntry({required this.entryId});
  final String entryId;
}
