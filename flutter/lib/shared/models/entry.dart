/// Datenmodell – spiegelt das TypeScript-Schema aus MVP-Konzept §7
enum Mood { happy, calm, neutral, tense, sad, mixed }

class Transcript {
  final String id;
  final String? audioUrl;
  final String text;
  final DateTime createdAt;

  const Transcript({
    required this.id,
    this.audioUrl,
    required this.text,
    required this.createdAt,
  });

  factory Transcript.fromMap(Map<String, dynamic> map) => Transcript(
        id: map['id'] as String,
        audioUrl: map['audioUrl'] as String?,
        text: map['text'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        if (audioUrl != null) 'audioUrl': audioUrl,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
      };
}

class Entry {
  final String id;
  final String userId;
  final String date; // YYYY-MM-DD
  final DateTime createdAt;
  final DateTime updatedAt;

  final String bodyMarkdown;
  final List<Transcript> rawTranscripts;
  final List<String> followUpQuestions;
  final Mood mood;
  final double moodScore; // -1.0 bis +1.0

  final int durationSeconds;
  final String language;
  final int version;

  const Entry({
    required this.id,
    required this.userId,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    required this.bodyMarkdown,
    required this.rawTranscripts,
    required this.followUpQuestions,
    required this.mood,
    required this.moodScore,
    required this.durationSeconds,
    this.language = 'de',
    this.version = 1,
  });

  factory Entry.fromMap(Map<String, dynamic> map) => Entry(
        id: map['id'] as String,
        userId: map['userId'] as String,
        date: map['date'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
        bodyMarkdown: map['bodyMarkdown'] as String,
        rawTranscripts: (map['rawTranscripts'] as List)
            .map((t) => Transcript.fromMap(t as Map<String, dynamic>))
            .toList(),
        followUpQuestions:
            List<String>.from(map['followUpQuestions'] as List),
        mood: Mood.values.byName(map['mood'] as String),
        moodScore: (map['moodScore'] as num).toDouble(),
        durationSeconds: map['durationSeconds'] as int,
        language: map['language'] as String? ?? 'de',
        version: map['version'] as int? ?? 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'userId': userId,
        'date': date,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'bodyMarkdown': bodyMarkdown,
        'rawTranscripts': rawTranscripts.map((t) => t.toMap()).toList(),
        'followUpQuestions': followUpQuestions,
        'mood': mood.name,
        'moodScore': moodScore,
        'durationSeconds': durationSeconds,
        'language': language,
        'version': version,
      };
}
