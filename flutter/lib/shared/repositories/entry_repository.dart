import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../services/auth_service.dart';
import '../services/proxy_client.dart' show TopicDto;

part 'entry_repository.g.dart';

const _uuid = Uuid();

class ProfileStats {
  const ProfileStats({
    required this.totalEntries,
    required this.totalDurationSeconds,
    required this.firstEntryDate,
    required this.latestEntryDate,
    required this.moodBreakdown,
  });

  const ProfileStats.empty()
      : totalEntries = 0,
        totalDurationSeconds = 0,
        firstEntryDate = null,
        latestEntryDate = null,
        moodBreakdown = const {};

  final int totalEntries;
  final int totalDurationSeconds;
  final String? firstEntryDate;
  final String? latestEntryDate;
  final Map<String, int> moodBreakdown;

  String? get topMood => moodBreakdown.isEmpty
      ? null
      : (moodBreakdown.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .first
          .key;
}

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
    List<String> tags = const [],
    String transcriptReason = 'initial',
  }) async {
    final user = await _auth.getUser();
    final now = DateTime.now().toIso8601String();
    final entryId = _uuid.v4();
    final transcriptId = _uuid.v4();
    final topicsJson = jsonEncode(topics.map((t) => t.toJson()).toList());
    final questionsJson = jsonEncode(followUpQuestions);
    final tagsJson = jsonEncode(tags);

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
              tags: Value(tagsJson),
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
      tags: tags,
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
    List<String> tags = const [],
    String transcriptReason = 'continuation',
  }) async {
    final user = await _auth.getUser();
    final now = DateTime.now().toIso8601String();
    final transcriptId = _uuid.v4();
    final topicsJson = jsonEncode(topics.map((t) => t.toJson()).toList());
    final questionsJson = jsonEncode(followUpQuestions);
    final tagsJson = jsonEncode(tags);

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
            tags: Value(tagsJson),
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
      tags: tags,
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
    List<String> tags = const [],
  }) async {
    final user = await _auth.getUser();
    final now = DateTime.now().toIso8601String();
    final topicsJson = jsonEncode(topics.map((t) => t.toJson()).toList());
    final questionsJson = jsonEncode(followUpQuestions);
    final tagsJson = jsonEncode(tags);

    await (_db.update(_db.entries)
          ..where((e) => e.date.equals(date) & e.userId.equals(user.uid)))
        .write(EntriesCompanion(
          bodyMarkdown: Value(bodyMarkdown),
          mood: Value(mood),
          moodScore: Value(moodScore),
          followUpQuestions: Value(questionsJson),
          topics: Value(topicsJson),
          tags: Value(tagsJson),
          updatedAt: Value(now),
          synced: const Value(false),
        ));
  }

  Future<List<String>> getAllTags() async {
    final user = FirebaseAuth.instance.currentUser ?? await _auth.getUser();
    final rows = await (_db.select(_db.entries)
          ..where((e) => e.userId.equals(user.uid)))
        .get();
    final tagSet = <String>{};
    for (final row in rows) {
      try {
        tagSet.addAll((jsonDecode(row.tags) as List).cast<String>());
      } catch (_) {}
    }
    return tagSet.toList();
  }

  Stream<List<Entry>> watchAllEntries() async* {
    final user = FirebaseAuth.instance.currentUser ?? await _auth.getUser();
    yield* (_db.select(_db.entries)
          ..where((e) => e.userId.equals(user.uid))
          ..orderBy([(e) => OrderingTerm.desc(e.date)]))
        .watch();
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

  /// Wipes every locally cached entry/transcript on this device (all users,
  /// not just the current one — catches orphaned rows left behind by an
  /// anonymous session that never got linked, see [getOrphanedEntryForDate]).
  /// Call on sign-out so a shared/reused device doesn't keep a previous
  /// account's diary readable locally. Also clears the per-account
  /// "history synced" flags so a later login re-triggers a full re-sync
  /// from Firestore instead of assuming the (now-empty) local DB is current.
  Future<void> clearAllLocalData() async {
    await _db.delete(_db.rawTranscripts).go();
    await _db.delete(_db.entries).go();

    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (key.startsWith('history_synced_')) {
        await prefs.remove(key);
      }
    }
  }

  Future<Entry?> getLocalEntryForDate(String date) async {
    final user = FirebaseAuth.instance.currentUser ?? await _auth.getUser();
    return (_db.select(_db.entries)
          ..where((e) => e.date.equals(date) & e.userId.equals(user.uid))
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Returns a local entry for [date] recorded under a DIFFERENT user (e.g. an
  /// anonymous session that was active before sign-in). Used to detect conflicts.
  Future<Entry?> getOrphanedEntryForDate(String date, String currentUid) async {
    return (_db.select(_db.entries)
          ..where((e) => e.date.equals(date) & e.userId.isNotValue(currentUid))
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<RawTranscript>> getTranscriptsForEntry(String entryId) {
    return (_db.select(_db.rawTranscripts)
          ..where((t) => t.entryId.equals(entryId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<void> deleteEntryById(String entryId) async {
    await (_db.delete(_db.rawTranscripts)
          ..where((t) => t.entryId.equals(entryId)))
        .go();
    await (_db.delete(_db.entries)
          ..where((e) => e.id.equals(entryId)))
        .go();
  }

  Future<int> getEntryCount() async {
    final user = await _auth.getUser();
    final rows = await (_db.select(_db.entries)
          ..where((e) => e.userId.equals(user.uid)))
        .get();
    return rows.length;
  }

  Future<ProfileStats> getProfileStats() async {
    final user = await _auth.getUser();
    final rows = await (_db.select(_db.entries)
          ..where((e) => e.userId.equals(user.uid))
          ..orderBy([(e) => OrderingTerm.asc(e.date)]))
        .get();
    if (rows.isEmpty) return const ProfileStats.empty();

    final totalDuration = rows.fold<int>(0, (s, e) => s + e.durationSeconds);

    final moodCounts = <String, int>{};
    for (final e in rows) {
      moodCounts[e.mood] = (moodCounts[e.mood] ?? 0) + 1;
    }

    return ProfileStats(
      totalEntries: rows.length,
      totalDurationSeconds: totalDuration,
      firstEntryDate: rows.first.date,
      latestEntryDate: rows.last.date,
      moodBreakdown: moodCounts,
    );
  }

  // ── Firestore → Drift sync-down ──────────────────────────────────────────────

  // Returns true if an entry for [date] exists (already in Drift or synced from
  // Firestore). Inserts into Drift on first call so TopicsReviewScreen can pick
  // it up via its existing _loadFromDbIfEmpty path.
  Future<bool> syncEntryFromFirestoreIfMissing(String date) async {
    // Use FirebaseAuth.instance.currentUser directly — Riverpod state can lag
    // behind immediately after a sign-in that changes the UID.
    final user = FirebaseAuth.instance.currentUser ?? await _auth.getUser();
    // ignore: avoid_print
    print('[EntryRepository] sync: date=$date uid=${user.uid} anon=${user.isAnonymous}');

    // Fast path — already in Drift
    final existing = await (_db.select(_db.entries)
          ..where((e) => e.date.equals(date) & e.userId.equals(user.uid)))
        .getSingleOrNull();
    if (existing != null) {
      // ignore: avoid_print
      print('[EntryRepository] sync: found in Drift, skipping Firestore');
      return true;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('entries')
          .doc(date)
          .get();
      // ignore: avoid_print
      print('[EntryRepository] sync: Firestore doc.exists=${doc.exists}');
      if (!doc.exists) return false;

      await _insertEntryFromFirestoreDoc(doc, user.uid, date);
      return true;
    } catch (e, st) {
      // ignore: avoid_print
      print('[EntryRepository] syncEntryFromFirestoreIfMissing failed: $e\n$st');
      return false;
    }
  }

  // ── Firestore → Drift bulk sync (full history, e.g. on login) ───────────────

  /// Fetches every entry doc under `users/{uid}/entries` and inserts any that
  /// are missing locally. Never overwrites a date that already exists in
  /// Drift. Reports (loaded, total) progress after each doc is processed —
  /// [onProgress] is called once with (0, total) before the loop starts.
  Future<int> syncAllEntriesFromFirestore({
    void Function(int loaded, int total)? onProgress,
  }) async {
    final user = FirebaseAuth.instance.currentUser ?? await _auth.getUser();

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('entries')
        .get();

    final total = snapshot.docs.length;
    onProgress?.call(0, total);
    if (total == 0) return 0;

    final localDates = (await (_db.select(_db.entries)
              ..where((e) => e.userId.equals(user.uid)))
            .get())
        .map((e) => e.date)
        .toSet();

    var inserted = 0;
    var loaded = 0;
    for (final doc in snapshot.docs) {
      if (!localDates.contains(doc.id)) {
        try {
          await _insertEntryFromFirestoreDoc(doc, user.uid, doc.id);
          inserted++;
        } catch (e, st) {
          // ignore: avoid_print
          print('[EntryRepository] syncAllEntriesFromFirestore: failed for ${doc.id}: $e\n$st');
        }
      }
      loaded++;
      onProgress?.call(loaded, total);
    }
    return inserted;
  }

  Future<bool> hasHistorySynced(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('history_synced_$uid') ?? false;
  }

  Future<void> markHistorySynced(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('history_synced_$uid', true);
  }

  // ── Shared Firestore doc → Drift row conversion ──────────────────────────────

  Future<void> _insertEntryFromFirestoreDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String uid,
    String date,
  ) async {
    final data = doc.data()!;
    final entryId = data['id'] as String? ?? _uuid.v4();
    final now = DateTime.now().toIso8601String();

    // Firestore stores followUpQuestions and topics as native lists;
    // Drift stores them as JSON strings.
    final fqRaw = data['followUpQuestions'];
    final followUpJson = fqRaw is List ? jsonEncode(fqRaw) : (fqRaw as String? ?? '[]');
    final topicsRaw = data['topics'];
    final topicsJson = topicsRaw is List ? jsonEncode(topicsRaw) : (topicsRaw as String? ?? '[]');

    await _db.into(_db.entries).insert(
      EntriesCompanion.insert(
        id: entryId,
        userId: uid,
        date: date,
        bodyMarkdown: data['bodyMarkdown'] as String? ?? '',
        mood: Value(data['mood'] as String? ?? 'neutral'),
        moodScore: Value((data['moodScore'] as num?)?.toDouble() ?? 0.0),
        durationSeconds: (data['durationSeconds'] as num?)?.toInt() ?? 0,
        language: Value(data['language'] as String? ?? 'de'),
        version: Value(1),
        followUpQuestions: Value(followUpJson),
        topics: Value(topicsJson),
        createdAt: _tsToString(data['createdAt'], now),
        updatedAt: _tsToString(data['updatedAt'], now),
        synced: Value(true),
      ),
    );

    final rawTranscripts = data['rawTranscripts'] as List<dynamic>?;
    if (rawTranscripts != null) {
      for (final t in rawTranscripts) {
        final m = t as Map<String, dynamic>;
        await _db.into(_db.rawTranscripts).insert(
          RawTranscriptsCompanion.insert(
            id: m['id'] as String? ?? _uuid.v4(),
            entryId: entryId,
            content: m['raw'] as String? ?? '',
            normalizedContent: Value(m['normalized'] as String? ?? ''),
            reason: Value(m['reason'] as String? ?? 'initial'),
            createdAt: _tsToString(m['createdAt'], now),
          ),
        );
      }
    }
  }

  // Firestore may store timestamps as Timestamp objects or ISO strings.
  String _tsToString(dynamic value, String fallback) {
    if (value == null) return fallback;
    if (value is String) return value;
    if (value is Timestamp) return value.toDate().toIso8601String();
    return fallback;
  }

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
    required List<String> tags,
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
        'tags': tags,
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
    required List<String> tags,
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
        'tags': tags,
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
