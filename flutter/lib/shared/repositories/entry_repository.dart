import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../services/auth_service.dart';
import '../services/proxy_client.dart' show TopicDto;

part 'entry_repository.g.dart';

const _uuid = Uuid();

class EntryRepository {
  EntryRepository(this._db, this._auth);
  final AppDatabase _db;
  final AuthService _auth;

  // ── Save new entry (first recording of the day) ─────────────────────────────

  Future<void> saveEntry({
    required String date,
    required String rawTranscript,
    required String normalizedText,
    required int durationSeconds,
    required String bodyMarkdown,
    required String mood,
    required double moodScore,
    required List<String> followUpQuestions,
    required List<TopicDto> topics,
    String transcriptReason = 'initial',
  }) async {
    final user = await _auth.getUser();
    final now = DateTime.now().toIso8601String();
    final entryId = _uuid.v4();
    final transcriptId = _uuid.v4();
    final topicsJson = jsonEncode(topics.map((t) => t.toJson()).toList());
    final questionsJson = jsonEncode(followUpQuestions);

    await _db.transaction(() async {
      await _db.into(_db.entries).insertOnConflictUpdate(
            EntriesCompanion.insert(
              id: entryId,
              userId: user.uid,
              date: date,
              bodyMarkdown: bodyMarkdown,
              mood: Value(mood),
              moodScore: Value(moodScore),
              durationSeconds: durationSeconds,
              followUpQuestions: Value(questionsJson),
              topics: Value(topicsJson),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _db.into(_db.rawTranscripts).insert(
            RawTranscriptsCompanion.insert(
              id: transcriptId,
              entryId: entryId,
              content: rawTranscript,
              normalizedContent: Value(normalizedText),
              reason: Value(transcriptReason),
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
      topics: topics,
      rawTranscript: rawTranscript,
      normalizedText: normalizedText,
      transcriptId: transcriptId,
      transcriptReason: transcriptReason,
      durationSeconds: durationSeconds,
      now: now,
    ));
  }

  // ── Merge new recording into existing day entry ─────────────────────────────

  Future<String> mergeEntry({
    required String date,
    required String rawTranscript,
    required String normalizedText,
    required String bodyMarkdown,
    required String mood,
    required double moodScore,
    required List<String> followUpQuestions,
    required List<TopicDto> topics,
    String transcriptReason = 'continuation',
  }) async {
    final user = await _auth.getUser();
    final now = DateTime.now().toIso8601String();
    final transcriptId = _uuid.v4();
    final topicsJson = jsonEncode(topics.map((t) => t.toJson()).toList());
    final questionsJson = jsonEncode(followUpQuestions);

    // Find the existing entry for this date
    final existing = await (_db.select(_db.entries)
          ..where((e) => e.date.equals(date) & e.userId.equals(user.uid)))
        .getSingleOrNull();

    if (existing == null) {
      // Shouldn't happen, but fall back to saveEntry
      await saveEntry(
        date: date,
        rawTranscript: rawTranscript,
        normalizedText: normalizedText,
        durationSeconds: 0,
        bodyMarkdown: bodyMarkdown,
        mood: mood,
        moodScore: moodScore,
        followUpQuestions: followUpQuestions,
        topics: topics,
        transcriptReason: transcriptReason,
      );
      return date;
    }

    await _db.transaction(() async {
      await (_db.update(_db.entries)
            ..where((e) => e.id.equals(existing.id)))
          .write(EntriesCompanion(
            bodyMarkdown: Value(bodyMarkdown),
            mood: Value(mood),
            moodScore: Value(moodScore),
            followUpQuestions: Value(questionsJson),
            topics: Value(topicsJson),
            updatedAt: Value(now),
            synced: const Value(false),
          ));
      await _db.into(_db.rawTranscripts).insert(
            RawTranscriptsCompanion.insert(
              id: transcriptId,
              entryId: existing.id,
              content: rawTranscript,
              normalizedContent: Value(normalizedText),
              reason: Value(transcriptReason),
              createdAt: now,
            ),
          );
    });

    unawaited(_updateFirestore(
      uid: user.uid,
      entryId: existing.id,
      date: date,
      bodyMarkdown: bodyMarkdown,
      mood: mood,
      moodScore: moodScore,
      followUpQuestions: followUpQuestions,
      topics: topics,
      rawTranscript: rawTranscript,
      normalizedText: normalizedText,
      transcriptId: transcriptId,
      transcriptReason: transcriptReason,
      now: now,
    ));

    return existing.id;
  }

  // ── Update entry fields after re-derivation ─────────────────────────────────

  Future<void> updateEntry({
    required String date,
    required String bodyMarkdown,
    required String mood,
    required double moodScore,
    required List<String> followUpQuestions,
    required List<TopicDto> topics,
  }) async {
    final user = await _auth.getUser();
    final now = DateTime.now().toIso8601String();
    final topicsJson = jsonEncode(topics.map((t) => t.toJson()).toList());
    final questionsJson = jsonEncode(followUpQuestions);

    await (_db.update(_db.entries)
          ..where((e) => e.date.equals(date) & e.userId.equals(user.uid)))
        .write(EntriesCompanion(
          bodyMarkdown: Value(bodyMarkdown),
          mood: Value(mood),
          moodScore: Value(moodScore),
          followUpQuestions: Value(questionsJson),
          topics: Value(topicsJson),
          updatedAt: Value(now),
          synced: const Value(false),
        ));
  }

  // ── Update a single normalized transcript ────────────────────────────────────

  Future<void> updateTranscript({
    required String transcriptId,
    required String normalizedContent,
  }) async {
    await (_db.update(_db.rawTranscripts)
          ..where((t) => t.id.equals(transcriptId)))
        .write(RawTranscriptsCompanion(
          normalizedContent: Value(normalizedContent),
        ));
  }

  // ── Delete a transcript ──────────────────────────────────────────────────────

  Future<void> deleteTranscript(String transcriptId) async {
    await (_db.delete(_db.rawTranscripts)
          ..where((t) => t.id.equals(transcriptId)))
        .go();
  }

  // ── Delete the full entry for a date (transcripts first, then entry) ─────────

  Future<void> deleteEntryForDate(String date) async {
    final user = await _auth.getUser();
    final entry = await (_db.select(_db.entries)
          ..where((e) => e.date.equals(date) & e.userId.equals(user.uid)))
        .getSingleOrNull();
    if (entry == null) return;
    await (_db.delete(_db.rawTranscripts)
          ..where((t) => t.entryId.equals(entry.id)))
        .go();
    await (_db.delete(_db.entries)
          ..where((e) => e.id.equals(entry.id)))
        .go();
    unawaited(_deleteFromFirestore(uid: user.uid, date: date));
  }

  // ── Local-only entry lookup (no auth — single-user device DB) ───────────────

  Future<Entry?> getLocalEntryForDate(String date) =>
      (_db.select(_db.entries)
            ..where((e) => e.date.equals(date))
            ..orderBy([(e) => OrderingTerm.desc(e.createdAt)])
            ..limit(1))
          .getSingleOrNull();

  // ── Read helpers for re-derivation ───────────────────────────────────────────

  Future<List<RawTranscript>> getTranscriptsForDate(String date) async {
    final user = await _auth.getUser();
    final entry = await (_db.select(_db.entries)
          ..where((e) => e.date.equals(date) & e.userId.equals(user.uid)))
        .getSingleOrNull();
    if (entry == null) return [];
    return (_db.select(_db.rawTranscripts)
          ..where((t) => t.entryId.equals(entry.id))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  // ── Firestore sync ────────────────────────────────────────────────────────────

  Future<void> _deleteFromFirestore({
    required String uid,
    required String date,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('entries')
          .doc(date)
          .delete();
    } catch (_) {
      // Best-effort — document may not exist if sync never completed
    }
  }

  Future<void> _syncToFirestore({
    required String uid,
    required String entryId,
    required String date,
    required String bodyMarkdown,
    required String mood,
    required double moodScore,
    required List<String> followUpQuestions,
    required List<TopicDto> topics,
    required String rawTranscript,
    required String normalizedText,
    required String transcriptId,
    required String transcriptReason,
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
        'topics': topics.map((t) => t.toJson()).toList(),
        'durationSeconds': durationSeconds,
        'language': 'de',
        'version': 1,
        'createdAt': now,
        'updatedAt': now,
        'rawTranscripts': [
          {
            'id': transcriptId,
            'raw': rawTranscript,
            'normalized': normalizedText,
            'reason': transcriptReason,
            'createdAt': now
          },
        ],
      }, SetOptions(merge: true));

      await (_db.update(_db.entries)..where((e) => e.id.equals(entryId)))
          .write(const EntriesCompanion(synced: Value(true)));
    } catch (e) {
      // Best-effort — remains unsynced until next save
    }
  }

  Future<void> _updateFirestore({
    required String uid,
    required String entryId,
    required String date,
    required String bodyMarkdown,
    required String mood,
    required double moodScore,
    required List<String> followUpQuestions,
    required List<TopicDto> topics,
    required String rawTranscript,
    required String normalizedText,
    required String transcriptId,
    required String transcriptReason,
    required String now,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('entries')
          .doc(date)
          .set({
        'bodyMarkdown': bodyMarkdown,
        'mood': mood,
        'moodScore': moodScore,
        'followUpQuestions': followUpQuestions,
        'topics': topics.map((t) => t.toJson()).toList(),
        'updatedAt': now,
        'rawTranscripts': FieldValue.arrayUnion([
          {
            'id': transcriptId,
            'raw': rawTranscript,
            'normalized': normalizedText,
            'reason': transcriptReason,
            'createdAt': now,
          }
        ]),
      }, SetOptions(merge: true));

      await (_db.update(_db.entries)..where((e) => e.id.equals(entryId)))
          .write(const EntriesCompanion(synced: Value(true)));
    } catch (e) {
      // Best-effort
    }
  }
}

@Riverpod(keepAlive: true)
EntryRepository entryRepository(Ref ref) => EntryRepository(
      ref.watch(appDatabaseProvider),
      ref.read(authServiceProvider.notifier),
    );
