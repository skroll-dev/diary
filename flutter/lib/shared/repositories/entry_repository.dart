import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../models/entry_image.dart';
import '../services/auth_service.dart';
import '../services/image_proxy_client.dart';
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
  EntryRepository(this._db, this._auth, this._imageProxy);
  final AppDatabase _db;
  final AuthService _auth;
  final ImageProxyClient _imageProxy;

  // ── Save new entry (first recording of the day) ─────────────────────────────

  Future<String> saveEntry({
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

    return entryId;
  }

  // ── Merge new recording into an existing entry ───────────────────────────────

  Future<String> mergeEntry({
    required String entryId,
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

    final existing = await getEntryById(entryId);
    if (existing == null) {
      debugPrint('[EntryRepository] mergeEntry: no entry found for id $entryId');
      return entryId;
    }

    await _db.transaction(() async {
      await (_db.update(_db.entries)..where((e) => e.id.equals(entryId)))
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
              entryId: entryId,
              content: rawTranscript,
              normalizedContent: Value(normalizedText),
              reason: Value(transcriptReason),
              createdAt: now,
            ),
          );
    });

    unawaited(_updateFirestore(
      uid: user.uid,
      entryId: entryId,
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

    return entryId;
  }

  // ── Update entry fields after re-derivation ─────────────────────────────────

  Future<void> updateEntry({
    required String entryId,
    required String bodyMarkdown,
    required String mood,
    required double moodScore,
    required List<String> followUpQuestions,
    required List<TopicDto> topics,
    List<String> tags = const [],
  }) async {
    final now = DateTime.now().toIso8601String();
    final topicsJson = jsonEncode(topics.map((t) => t.toJson()).toList());
    final questionsJson = jsonEncode(followUpQuestions);
    final tagsJson = jsonEncode(tags);

    await (_db.update(_db.entries)..where((e) => e.id.equals(entryId)))
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

  /// Pushes every entry that hasn't reached Firestore yet (`synced == false`)
  /// for [uid] (defaults to the current user). `saveEntry`/`mergeEntry` fire
  /// their Firestore writes unawaited for a snappy UI, so an entry can still
  /// be in flight — or have failed silently — when the user signs out.
  /// [clearAllLocalData] wipes local Drift rows unconditionally, so any
  /// entry that hasn't actually landed in Firestore by then is lost for
  /// good. Call this and await it before clearing local data.
  Future<void> flushPendingSyncs({String? uid}) async {
    final user = FirebaseAuth.instance.currentUser ?? await _auth.getUser();
    final targetUid = uid ?? user.uid;

    final pending = await (_db.select(_db.entries)
          ..where((e) => e.userId.equals(targetUid) & e.synced.equals(false)))
        .get();
    if (pending.isEmpty) return;

    for (final entry in pending) {
      try {
        await _pushEntryToFirestore(entry, targetUid);
      } catch (e) {
        debugPrint('[EntryRepository] flushPendingSyncs failed for ${entry.id}: $e');
      }
    }
  }

  /// Writes the full state of [entry] (plus its transcripts) to
  /// `users/{targetUid}/entries/{entry.id}` and marks it synced. Shared by
  /// [flushPendingSyncs] and [reparentEntryToUser].
  Future<void> _pushEntryToFirestore(Entry entry, String targetUid) async {
    final transcripts = await getTranscriptsForEntry(entry.id);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(targetUid)
        .collection('entries')
        .doc(entry.id)
        .set({
      'id': entry.id,
      'userId': targetUid,
      'date': entry.date,
      'bodyMarkdown': entry.bodyMarkdown,
      'mood': entry.mood,
      'moodScore': entry.moodScore,
      'followUpQuestions': jsonDecode(entry.followUpQuestions),
      'topics': jsonDecode(entry.topics),
      'tags': jsonDecode(entry.tags),
      'images': jsonDecode(entry.images),
      'durationSeconds': entry.durationSeconds,
      'language': entry.language,
      'version': entry.version,
      'createdAt': entry.createdAt,
      'updatedAt': entry.updatedAt,
      'rawTranscripts': transcripts
          .map((t) => {
                'id': t.id,
                'raw': t.content,
                'normalized': t.normalizedContent,
                'reason': t.reason,
                'createdAt': t.createdAt,
              })
          .toList(),
    }, SetOptions(merge: true));

    await (_db.update(_db.entries)..where((e) => e.id.equals(entry.id)))
        .write(const EntriesCompanion(synced: Value(true)));
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
    final user = FirebaseAuth.instance.currentUser ?? await _auth.getUser();
    final entry = await getEntryById(entryId); // read BEFORE deleting, to know its images
    await (_db.delete(_db.rawTranscripts)
          ..where((t) => t.entryId.equals(entryId)))
        .go();
    await (_db.delete(_db.entries)
          ..where((e) => e.id.equals(entryId)))
        .go();
    unawaited(_deleteFromFirestore(uid: user.uid, entryId: entryId));

    final images = entry != null ? parseEntryImages(entry.images) : const <EntryImage>[];
    if (images.isNotEmpty) {
      final paths = images.expand((i) => [i.fullPath, i.thumbPath]).toList();
      unawaited(_imageProxy.deleteImages(paths).catchError((Object e) {
        debugPrint('[EntryRepository] deleteEntryById: image cleanup failed for $entryId: $e');
      }));
    }
  }

  // ── Image attachments ────────────────────────────────────────────────────────

  /// Single write path for all image mutations (add/delete/reorder). Writes
  /// the Drift row, then fires an unawaited partial Firestore merge so a
  /// concurrent edit elsewhere (e.g. [_updateFirestore]'s continuation-merge
  /// write, which deliberately omits `images`) can never clobber it.
  Future<void> updateEntryImages({
    required String entryId,
    required List<EntryImage> images,
  }) async {
    final now = DateTime.now().toIso8601String();
    final imagesJson = encodeEntryImages(images);

    await (_db.update(_db.entries)..where((e) => e.id.equals(entryId)))
        .write(EntriesCompanion(
          images: Value(imagesJson),
          updatedAt: Value(now),
          synced: const Value(false),
        ));

    final user = FirebaseAuth.instance.currentUser ?? await _auth.getUser();
    unawaited(_syncImagesToFirestore(
      uid: user.uid,
      entryId: entryId,
      images: images,
      now: now,
    ));
  }

  Future<void> _syncImagesToFirestore({
    required String uid,
    required String entryId,
    required List<EntryImage> images,
    required String now,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('entries')
          .doc(entryId)
          .set({
        'images': images.map((i) => i.toJson()).toList(),
        'updatedAt': now,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[EntryRepository] _syncImagesToFirestore failed for $entryId: $e');
      // Best-effort — remains unsynced locally until the next successful sync.
    }
  }

  /// Returns the 1-based ordinal of [entryId] among this user's entries
  /// created on [date] (ordered by createdAt ascending). Used ONLY to build
  /// a human-browsable Storage folder name (`{date}_entry{ordinal}`) — NEVER
  /// as a stable identifier or lookup key, since object paths are stored
  /// verbatim in the `images` column and never reconstructed from it. Can
  /// drift if entries for the same date are created concurrently on two
  /// devices, or a later history-sync backfill inserts an older entry —
  /// accepted as a cosmetic-only limitation.
  Future<int> getEntryOrdinalForDate(String date, String entryId) async {
    final user = FirebaseAuth.instance.currentUser ?? await _auth.getUser();
    final rows = await (_db.select(_db.entries)
          ..where((e) => e.userId.equals(user.uid) & e.date.equals(date))
          ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]))
        .get();
    final idx = rows.indexWhere((e) => e.id == entryId);
    return idx >= 0 ? idx + 1 : rows.length + 1;
  }

  Future<Entry?> getEntryById(String entryId) {
    return (_db.select(_db.entries)..where((e) => e.id.equals(entryId)))
        .getSingleOrNull();
  }

  /// Reassigns a locally-orphaned entry (recorded under a previous anonymous
  /// session, see [getOrphanedEntryForDate]) to the now-signed-in [newUserId],
  /// and pushes it to that account's Firestore collection as its own
  /// independent entry — it is never merged into another entry's content.
  Future<void> reparentEntryToUser(String entryId, String newUserId) async {
    await (_db.update(_db.entries)..where((e) => e.id.equals(entryId))).write(
      EntriesCompanion(userId: Value(newUserId), synced: const Value(false)),
    );
    final entry = await getEntryById(entryId);
    if (entry != null) {
      unawaited(_pushEntryToFirestore(entry, newUserId));
    }
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

  // ── Firestore → Drift bulk sync (full history, e.g. on login) ───────────────

  /// Fetches every entry doc under `users/{uid}/entries` and inserts any that
  /// are missing locally. Doc IDs are entry ids for docs written after the
  /// multi-entry-per-day migration, but may still be legacy date strings for
  /// older docs — either way `data['id']` is the authoritative entry id, so
  /// dedup and insertion key off that (falling back to `doc.id`/`doc data
  /// date` for docs written before the `id`/`date` fields existed). Never
  /// overwrites an entry that already exists locally. Reports (loaded,
  /// total) progress after each doc is processed — [onProgress] is called
  /// once with (0, total) before the loop starts.
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

    final localEntryIds = (await (_db.select(_db.entries)
              ..where((e) => e.userId.equals(user.uid)))
            .get())
        .map((e) => e.id)
        .toSet();

    var inserted = 0;
    var loaded = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final resolvedEntryId = data['id'] as String? ?? doc.id;
      if (!localEntryIds.contains(resolvedEntryId)) {
        try {
          final resolvedDate = data['date'] as String? ?? doc.id;
          await _insertEntryFromFirestoreDoc(doc, user.uid, resolvedDate);
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
    final tagsRaw = data['tags'];
    final tagsJson = tagsRaw is List ? jsonEncode(tagsRaw) : (tagsRaw as String? ?? '[]');
    final imagesRaw = data['images'];
    final imagesJson = imagesRaw is List ? jsonEncode(imagesRaw) : (imagesRaw as String? ?? '[]');

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
        tags: Value(tagsJson),
        images: Value(imagesJson),
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

  // ── Firestore sync ────────────────────────────────────────────────────────────

  Future<void> _deleteFromFirestore({
    required String uid,
    required String entryId,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('entries')
          .doc(entryId)
          .delete();
    } catch (e) {
      debugPrint('[EntryRepository] _deleteFromFirestore failed for $entryId: $e');
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
          .doc(entryId)
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
      debugPrint('[EntryRepository] _syncToFirestore failed for $entryId: $e');
      // Best-effort — remains unsynced until next save or flushPendingSyncs()
    }
  }

  Future<void> _updateFirestore({
    required String uid,
    required String entryId,
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
          .doc(entryId)
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
      debugPrint('[EntryRepository] _updateFirestore failed for $entryId: $e');
      // Best-effort — remains unsynced until next save or flushPendingSyncs()
    }
  }
}

@Riverpod(keepAlive: true)
EntryRepository entryRepository(Ref ref) => EntryRepository(
      ref.watch(appDatabaseProvider),
      ref.read(authServiceProvider.notifier),
      ref.read(imageProxyClientProvider),
    );
