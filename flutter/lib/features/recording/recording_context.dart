sealed class RecordingContext {
  const RecordingContext();
}

final class FreshRecording extends RecordingContext {
  const FreshRecording();
}

final class ExtendingTopic extends RecordingContext {
  const ExtendingTopic({required this.topicTitle, this.followUpHint});
  final String topicTitle;
  final String? followUpHint;
}

final class AddingTopic extends RecordingContext {
  const AddingTopic();
}
