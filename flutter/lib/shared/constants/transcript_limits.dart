/// Must stay in sync with `MAX_TRANSCRIPT_CHARS` in
/// ai-proxy/app/routes/entries.py.
const kMaxTranscriptChars = 20000;

/// Fraction of [kMaxTranscriptChars] at which the UI should start blocking
/// new recordings, before the server would ever reject a request.
const kTranscriptWarnThreshold = 0.9;
