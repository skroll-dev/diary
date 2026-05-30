import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../services/auth_service.dart';

part 'entry_repository.g.dart';

const _uuid = Uuid();

class EntryRepository {
  EntryRepository(this._db, this._auth);
  final AppDatabase _db;
  final AuthService _auth;

  Future<void> saveEntry({
    required String date,
    required String rawTranscript,
    required String normalizedText,
    required int durationSeconds,
    required String bodyMarkdown,
    required String mood,
    required double moodScore,
    required List<String> followUpQuestions,
  }) async {
    final user = await _auth.getUser();
    final now = DateTime.now().toIso8601String();
    final entryId = _uuid.v4();
    final transcriptId = _uuid.v4();

    await _db.transaction(() async {
      await _db.into(_db.entries).insertOnConflictUpdate(
            EntriesCompanion.insert(
              id: entryId,
              userId: user.uid,
              date: date,
              bodyMarkdown: bodyMarkdown,
              durationSeconds: durationSeconds,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _db.into(_db.rawTranscripts).insert(
            RawTranscriptsCompanion.insert(
              id: transcriptId,
              entryId: entryId,
              content: rawTranscript,
              createdAt: now,
            ),
          );
    });

    unawaited(_syncToFirestore(
      uid: user.uid,
      entryId: entryId,
      date: date,
      bodyMarkdown: bodyMarkdown,
      mood: mood,
      moodScore: moodScore,
      followUpQuestions: followUpQuestions,
      rawTranscript: rawTranscript,
      transcriptId: transcriptId,
      durationSeconds: durationSeconds,
      now: now,
    ));
  }

  Future<void> _syncToFirestore({
    required String uid,
    required String entryId,
    required String date,
    required String bodyMarkdown,
    required String mood,
    required double moodScore,
    required List<String> followUpQuestions,
    required String rawTranscript,
    required String transcriptId,
    required int durationSeconds,
    required String now,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('entries')
          .doc(date)
          .set({
        'id': entryId,
        'userId': uid,
        'date': date,
        'bodyMarkdown': bodyMarkdown,
        'mood': mood,
        'moodScore': moodScore,
        'followUpQuestions': followUpQuestions,
        'durationSeconds': durationSeconds,
        'language': 'de',
        'version': 1,
        'createdAt': now,
        'updatedAt': now,
        'rawTranscripts': [
          {'id': transcriptId, 'text': rawTranscript, 'createdAt': now},
        ],
      }, SetOptions(merge: true));

      await (_db.update(_db.entries)
            ..where((e) => e.id.equals(entryId)))
          .write(const EntriesCompanion(synced: Value(true)));
    } catch (e) {
      // Best-effort — will remain unsynced until next save
    }
  }
}

@Riverpod(keepAlive: true)
EntryRepository entryRepository(Ref ref) => EntryRepository(
      ref.watch(appDatabaseProvider),
      ref.read(authServiceProvider.notifier),
    );
