/// Must stay in sync with `MAX_TRANSCRIPT_CHARS` in
/// ai-proxy/app/routes/entries.py.
const kMaxTranscriptChars = 20000;

/// Must stay in sync with the `min_length` of `/entries/generate` and
/// `/entries/merge` in ai-proxy/app/routes/entries.py. Shorter text can only
/// fail there.
const kMinTranscriptChars = 10;

bool isUsableTranscript(String text) =>
    text.trim().length >= kMinTranscriptChars;

/// Fraction of [kMaxTranscriptChars] at which the UI should start blocking
/// new recordings, before the server would ever reject a request.
const kTranscriptWarnThreshold = 0.9;
