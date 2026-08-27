import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:animated_reorderable_list/animated_reorderable_list.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/presentation/auth_sheet.dart';
import '../../recording/recording_context.dart';
import '../../../shared/constants/image_limits.dart';
import '../../../shared/models/entry_image.dart';
import '../../../shared/repositories/entry_repository.dart';
import '../../../shared/services/auth_service.dart';
import '../../../shared/services/image_proxy_client.dart';
import '../../../shared/widgets/fullscreen_image_viewer.dart';
import '../../../shared/widgets/profile_avatar_button.dart';
import '../../../shared/widgets/storage_image.dart';
import '../../../shared/services/proxy_client.dart';
import '../../../shared/widgets/history_sync_dialog.dart';
import '../../../shared/widgets/recording_controls.dart';
import '../../../shared/widgets/transcript_input_sheet.dart';
import '../../../shared/constants/transcript_limits.dart';

// ── Local upload-in-progress placeholder ────────────────────────────────────

class _UploadingImage {
  _UploadingImage({required this.id, required this.bytes});
  final String id;
  final Uint8List bytes;
}

// ── Internal data models ───────────────────────────────────────────────────────

class _TopicData {
  const _TopicData({
    required this.title,
    required this.text,
    required this.cardColor,
    required this.accentColor,
  });
  final String title;
  final String text;
  final Color cardColor;
  final Color accentColor;
}

class _RecordingRecord {
  _RecordingRecord({
    this.dbId,
    required this.normalizedText,
    required this.reason,
    required this.timestamp,
  });
  final String? dbId;
  String normalizedText;
  final String reason;
  final DateTime timestamp;

  String get provenanceLabel {
    if (reason == 'initial') return 'Erste Aufnahme';
    if (reason == 'continuation') return 'Ergänzung';
    if (reason.startsWith('followUp:')) {
      final q = reason.substring('followUp:'.length);
      return 'Antwort auf: „$q"';
    }
    return 'Aufnahme';
  }
}

// ── Color palette ─────────────────────────────────────────────────────────────

const _topicPalette = [
  (Color(0xFFEDE9FF), Color(0xFF5E35B1)),
  (Color(0xFFE8F5E9), Color(0xFF2E7D32)),
  (Color(0xFFFFF3E0), Color(0xFFBF360C)),
  (Color(0xFFE3F2FD), Color(0xFF1565C0)),
  (Color(0xFFFCE4EC), Color(0xFFC62828)),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class TopicsReviewScreen extends ConsumerStatefulWidget {
  const TopicsReviewScreen({
    super.key,
    required this.entryId,
    this.date = '',
    this.duration = '',
    this.topics = const [],
    this.normalizedTranscript = '',
    this.bodyMarkdown = '',
    this.mood = 'neutral',
    this.moodScore = 0.0,
    this.followUpQuestions = const [],
    this.transcriptReason = 'initial',
  });

  final String entryId;
  final String date;
  final String duration;
  final List<TopicDto> topics;
  final String normalizedTranscript;
  final String bodyMarkdown;
  final String mood;
  final double moodScore;
  final List<String> followUpQuestions;
  final String transcriptReason;

  @override
  ConsumerState<TopicsReviewScreen> createState() => _TopicsReviewScreenState();
}

class _TopicsReviewScreenState extends ConsumerState<TopicsReviewScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  late List<_TopicData> _topics;
  late List<_RecordingRecord> _recordings;
  late List<String> _followUpQuestions;
  late String _bodyMarkdown;
  late String _mood;
  late double _moodScore;
  late final String _entryId = widget.entryId;

  bool _isRecordingsExpanded = false;
  bool _isRegenerating = false;

  // ── Photos ──────────────────────────────────────────────────────────────────
  List<EntryImage> _images = [];
  final List<_UploadingImage> _uploadingImages = [];
  bool _isEditingPhotos = false;
  // Resolved fresh from Drift (not widget.date, which is populated
  // inconsistently across navigation paths) and cached per session.
  String? _resolvedDate;
  int? _cachedEntryOrdinal;

  // Pipeline progress for the re-generating overlay
  double _regenPercent = 0.0;
  String _regenStep = '';
  Timer? _regenTimer;

  int get _combinedTranscriptChars =>
      _recordings.fold(0, (sum, r) => sum + r.normalizedText.length);

  bool get _isNearTranscriptLimit =>
      _combinedTranscriptChars >=
      kMaxTranscriptChars * kTranscriptWarnThreshold;

  // ── Init ────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _bodyMarkdown = widget.bodyMarkdown;
    _mood = widget.mood;
    _moodScore = widget.moodScore;
    _followUpQuestions = List.of(widget.followUpQuestions);
    _topics = _mapTopics(widget.topics);
    _recordings = [
      if (widget.normalizedTranscript.isNotEmpty)
        _RecordingRecord(
          normalizedText: widget.normalizedTranscript,
          reason: widget.transcriptReason,
          timestamp: DateTime.now(),
        ),
    ];
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    // Load DB transcript IDs so edit/delete can target the right rows
    _loadTranscriptIds();

    // On web refresh state.extra is lost — reload this entry from Drift
    if (_topics.isEmpty) _loadFromDbIfEmpty();

    // Images are never carried via route `extra` (TopicsArgs predates this
    // feature and attaching photos only ever happens after recording, per
    // the mockup) — always resolve fresh from Drift, which also gives us the
    // canonical ISO date for Storage path-building.
    _loadImagesAndDate();
  }

  Future<void> _loadImagesAndDate() async {
    if (_entryId.isEmpty) return;
    try {
      final entry = await ref.read(entryRepositoryProvider).getEntryById(_entryId);
      if (entry == null || !mounted) return;
      setState(() {
        _images = parseEntryImages(entry.images);
        _resolvedDate = entry.date;
      });
    } catch (_) {}
  }

  Future<void> _loadFromDbIfEmpty() async {
    if (_entryId.isEmpty) return;
    try {
      final repo = ref.read(entryRepositoryProvider);
      final entry = await repo.getEntryById(_entryId);
      if (entry == null || !mounted) return;

      final topicDtos = (jsonDecode(entry.topics) as List)
          .map((e) => TopicDto.fromJson(e as Map<String, dynamic>))
          .toList();
      final questions = (jsonDecode(entry.followUpQuestions) as List)
          .map((e) => e as String)
          .toList();
      final transcripts = await repo.getTranscriptsForEntry(_entryId);

      setState(() {
        _bodyMarkdown = entry.bodyMarkdown;
        _mood = entry.mood;
        _moodScore = entry.moodScore;
        _followUpQuestions = questions;
        _topics = _mapTopics(topicDtos);
        _recordings = transcripts.map((t) => _RecordingRecord(
          dbId: t.id,
          normalizedText: t.normalizedContent.isNotEmpty ? t.normalizedContent : t.content,
          reason: t.reason,
          timestamp: DateTime.tryParse(t.createdAt) ?? DateTime.now(),
        )).toList();
      });
    } catch (_) {}
  }

  Future<void> _loadTranscriptIds() async {
    if (_entryId.isEmpty) return;
    try {
      final rows = await ref
          .read(entryRepositoryProvider)
          .getTranscriptsForEntry(_entryId);
      if (!mounted || rows.isEmpty) return;
      setState(() {
        if (_recordings.isEmpty) {
          // Navigated here without a fresh transcript (e.g. post-login sync) —
          // populate recordings entirely from DB.
          _recordings = rows.map((r) => _RecordingRecord(
            dbId: r.id,
            normalizedText: r.normalizedContent.isNotEmpty ? r.normalizedContent : r.content,
            reason: r.reason,
            timestamp: DateTime.tryParse(r.createdAt) ?? DateTime.now(),
          )).toList();
        } else {
          for (int i = 0; i < rows.length && i < _recordings.length; i++) {
            _recordings[i] = _RecordingRecord(
              dbId: rows[i].id,
              normalizedText: rows[i].normalizedContent.isNotEmpty
                  ? rows[i].normalizedContent
                  : _recordings[i].normalizedText,
              reason: rows[i].reason,
              timestamp: DateTime.tryParse(rows[i].createdAt) ?? DateTime.now(),
            );
          }
        }
      });
    } catch (_) {}
  }

  List<_TopicData> _mapTopics(List<TopicDto> dtos) =>
      dtos.indexed.map((e) {
        final (i, dto) = e;
        final (card, accent) = _topicPalette[i % _topicPalette.length];
        return _TopicData(
          title: dto.title,
          text: dto.text,
          cardColor: card,
          accentColor: accent,
        );
      }).toList();

  @override
  void dispose() {
    _entrance.dispose();
    _regenTimer?.cancel();
    super.dispose();
  }

  void _setRegenStep(String label, double start, double end) {
    _regenTimer?.cancel();
    setState(() {
      _regenPercent = start;
      _regenStep = label;
    });
    _regenTimer = Timer.periodic(const Duration(milliseconds: 80), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _regenPercent += (end - _regenPercent) * 0.025);
    });
  }

  void _completeRegenStep(double pct) {
    _regenTimer?.cancel();
    if (mounted) setState(() => _regenPercent = pct);
  }

  // ── Header helpers ───────────────────────────────────────────────────────────

  String get _headerDateLine {
    final d = widget.date;
    final dur = widget.duration;
    if (d.isEmpty && dur.isEmpty) return '';
    if (dur.isEmpty) return d;
    return '$d · $dur';
  }

  // ── Recording overlay ────────────────────────────────────────────────────────

  void _showRecordingOverlay(RecordingContext ctx) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _RecordingOverlay(
        recordingContext: ctx,
        onComplete: (rawTranscript) async {
          if (Navigator.of(sheetCtx).canPop()) Navigator.of(sheetCtx).pop();
          await _runMergePipeline(rawTranscript, ctx);
        },
        onCancel: () {
          if (Navigator.of(sheetCtx).canPop()) Navigator.of(sheetCtx).pop();
        },
      ),
    );
  }

  Future<void> _runMergePipeline(
      String rawTranscript, RecordingContext ctx) async {
    setState(() => _isRegenerating = true);
    try {
      final reason = switch (ctx) {
        ExtendingTopic(:final followUpHint) when followUpHint != null =>
          'followUp:$followUpHint',
        ExtendingTopic() => 'continuation',
        ContinuingEntry() => 'continuation',
        _ => 'continuation',
      };

      final sw = Stopwatch()..start();
      _setRegenStep('Mein KI-Tagebuch liest deinen Text …', 0.0, 0.35);
      final normalized =
          await ref.read(proxyClientProvider).normalize(rawTranscript);
      _completeRegenStep(0.35);
      debugPrint('[Pipeline] normalize (merge): ${sw.elapsedMilliseconds}ms');
      sw.reset(); sw.start();

      _setRegenStep('Mein KI-Tagebuch fügt alles zusammen …', 0.36, 1.0);
      final existingTags = await ref.read(entryRepositoryProvider).getAllTags();
      final entry = await ref.read(proxyClientProvider).mergeEntry(
            existingBody: _bodyMarkdown,
            newTranscript: normalized,
            previousQuestions: _followUpQuestions,
            existingTags: existingTags,
          );
      _completeRegenStep(1.0);
      debugPrint('[Pipeline] merge: ${sw.elapsedMilliseconds}ms');

      // Update UI immediately — DB save is best-effort and must not block this
      if (mounted) {
        setState(() {
          _bodyMarkdown = entry.bodyMarkdown;
          _mood = entry.mood;
          _moodScore = entry.moodScore;
          _followUpQuestions = List.of(entry.followUpQuestions);
          _topics = _mapTopics(entry.topics);
          _recordings.add(_RecordingRecord(
            normalizedText: normalized,
            reason: reason,
            timestamp: DateTime.now(),
          ));
          _entrance.forward(from: 0.0);
        });
      }

      unawaited(ref.read(entryRepositoryProvider).mergeEntry(
            entryId: _entryId,
            rawTranscript: rawTranscript,
            normalizedText: normalized,
            bodyMarkdown: entry.bodyMarkdown,
            mood: entry.mood,
            moodScore: entry.moodScore,
            followUpQuestions: entry.followUpQuestions,
            topics: entry.topics,
            tags: entry.tags,
            transcriptReason: reason,
          ).then((_) => _loadTranscriptIds()).catchError((_) {}));
    } on ProxyValidationException catch (e) {
      if (mounted) setState(() => _isRegenerating = false);
      await _retryWithEditedText(
        offendingText: rawTranscript,
        message: e.message,
        onRetry: (edited) => _runMergePipeline(edited, ctx),
      );
      return;
    } catch (e) {
      debugPrint('[TopicsReviewScreen] merge error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Beim Ergänzen ist etwas schiefgelaufen. Bitte versuche es erneut.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRegenerating = false);
    }
  }

  /// Shows the offending text pre-filled in an editable sheet, and retries
  /// [onRetry] with the user's shortened version if they confirm.
  Future<void> _retryWithEditedText({
    required String offendingText,
    required String message,
    required Future<void> Function(String edited) onRetry,
  }) async {
    if (!mounted) return;
    final edited = await showTranscriptInputSheet(
      context,
      title: 'Text ist zu lang',
      hint: message,
      initialValue: offendingText,
      confirmLabel: 'Erneut senden',
    );
    if (edited == null || edited.isEmpty || !mounted) return;
    await onRetry(edited);
  }

  // ── Transcript edit/delete ────────────────────────────────────────────────────

  Future<void> _editRecording(int index) async {
    final record = _recordings[index];
    final result = await showTranscriptInputSheet(
      context,
      title: 'Aufnahme bearbeiten',
      hint: '',
      initialValue: record.normalizedText,
      confirmLabel: 'Speichern',
    );
    if (result == null || result.isEmpty || result == record.normalizedText) return;

    setState(() => _recordings[index].normalizedText = result);

    if (record.dbId != null) {
      await ref.read(entryRepositoryProvider).updateTranscript(
            transcriptId: record.dbId!,
            normalizedContent: result,
          );
    }
    await _rederiveFromTranscripts();
  }

  Future<void> _deleteRecording(int index) async {
    final confirmed = await _showConfirmDialog(
      title: 'Aufnahme löschen?',
      body: 'Diese Aufnahme wird dauerhaft entfernt und der Eintrag neu erstellt.',
      confirmLabel: 'Löschen',
    );
    if (!confirmed || !mounted) return;

    final record = _recordings[index];
    if (record.dbId != null) {
      await ref
          .read(entryRepositoryProvider)
          .deleteTranscript(record.dbId!);
    }
    setState(() => _recordings.removeAt(index));

    if (_recordings.isEmpty) {
      if (mounted) context.go('/');
      return;
    }
    await _rederiveFromTranscripts();
  }

  Future<void> _rederiveFromTranscripts([String? overrideText]) async {
    setState(() => _isRegenerating = true);
    final combined =
        overrideText ?? _recordings.map((r) => r.normalizedText).join('\n\n');
    try {
      final sw = Stopwatch()..start();
      _setRegenStep('Mein KI-Tagebuch denkt nach …', 0.0, 1.0);
      final existingTags = await ref.read(entryRepositoryProvider).getAllTags();
      final entry = await ref.read(proxyClientProvider).generateEntry(
        combined,
        existingTags: existingTags,
      );
      _completeRegenStep(1.0);
      debugPrint('[Pipeline] re-derive: ${sw.elapsedMilliseconds}ms');
      await ref.read(entryRepositoryProvider).updateEntry(
            entryId: _entryId,
            bodyMarkdown: entry.bodyMarkdown,
            mood: entry.mood,
            moodScore: entry.moodScore,
            followUpQuestions: entry.followUpQuestions,
            topics: entry.topics,
            tags: entry.tags,
          );
      if (mounted) {
        setState(() {
          _bodyMarkdown = entry.bodyMarkdown;
          _mood = entry.mood;
          _moodScore = entry.moodScore;
          _followUpQuestions = List.of(entry.followUpQuestions);
          _topics = _mapTopics(entry.topics);
          _entrance.forward(from: 0.0);
        });
      }
    } on ProxyValidationException catch (e) {
      if (mounted) setState(() => _isRegenerating = false);
      await _retryWithEditedText(
        offendingText: combined,
        message: e.message,
        onRetry: (edited) => _rederiveFromTranscripts(edited),
      );
      return;
    } catch (e) {
      debugPrint('[TopicsReviewScreen] re-derive error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Beim Aktualisieren ist etwas schiefgelaufen. Bitte versuche es erneut.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRegenerating = false);
    }
  }

  // ── Photos ────────────────────────────────────────────────────────────────────

  Future<void> _showImageSourceSheet() async {
    final cs = Theme.of(context).colorScheme;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Kamera'),
                onTap: () => Navigator.of(sheetCtx).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Fotos'),
                onTap: () => Navigator.of(sheetCtx).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    await _pickAndUploadImages(source);
  }

  int get _totalImageCount => _images.length + _uploadingImages.length;

  Future<void> _pickAndUploadImages(ImageSource source) async {
    final remaining = kMaxImagesPerEntry - _totalImageCount;
    if (remaining <= 0) return;

    final picker = ImagePicker();
    List<XFile> picked;
    if (source == ImageSource.camera) {
      final file = await picker.pickImage(source: ImageSource.camera);
      picked = file != null ? [file] : [];
    } else {
      picked = await picker.pickMultiImage(limit: remaining);
    }
    if (picked.isEmpty || !mounted) return;

    final date = await _resolveDateForUpload();
    if (date == null || !mounted) return;
    _cachedEntryOrdinal ??=
        await ref.read(entryRepositoryProvider).getEntryOrdinalForDate(date, _entryId);
    if (!mounted) return;

    for (final file in picked.take(remaining)) {
      await _uploadOne(file, date);
    }
  }

  Future<String?> _resolveDateForUpload() async {
    if (_resolvedDate != null) return _resolvedDate;
    await _loadImagesAndDate();
    return _resolvedDate;
  }

  Future<void> _uploadOne(XFile file, String date) async {
    final bytes = await file.readAsBytes();
    final placeholder = _UploadingImage(id: UniqueKey().toString(), bytes: bytes);

    // Optimistic placeholder — the image genuinely doesn't exist until the
    // upload returns a Storage path, so this is as early as "UI updates
    // before awaiting network" can honestly happen here.
    setState(() => _uploadingImages.add(placeholder));

    try {
      final image = await ref.read(imageProxyClientProvider).uploadImage(
            entryId: _entryId,
            date: date,
            entryOrdinal: _cachedEntryOrdinal!,
            existingImageCount: _images.length,
            bytes: bytes,
            filename: file.name,
            contentType: file.mimeType ?? 'image/jpeg',
          );
      if (!mounted) return;
      setState(() {
        _uploadingImages.removeWhere((u) => u.id == placeholder.id);
        _images = [..._images, image.copyWith(order: _images.length)];
      });
      await ref.read(entryRepositoryProvider).updateEntryImages(
            entryId: _entryId,
            images: _images,
          );
    } catch (e) {
      debugPrint('[TopicsReviewScreen] image upload failed: $e');
      if (!mounted) return;
      setState(() => _uploadingImages.removeWhere((u) => u.id == placeholder.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Foto konnte nicht hochgeladen werden.')),
      );
    }
  }

  Future<void> _deleteImage(EntryImage target) async {
    final originalIndex = _images.indexOf(target);
    if (originalIndex < 0) return;

    setState(() => _images = List.of(_images)..removeAt(originalIndex));

    final messenger = ScaffoldMessenger.of(context);
    final actionColor = Theme.of(context).colorScheme.inversePrimary;
    var undone = false;

    // Hand-rolled instead of the single-action SnackBar API so we can offer
    // both an explicit "Bestätigen" (commit now, don't wait out the timeout)
    // and "Rückgängig" — both just close the SnackBar early via
    // hideCurrentSnackBar(); the `undone` flag (not SnackBarClosedReason)
    // decides afterwards whether to commit.
    final controller = messenger.showSnackBar(SnackBar(
      content: Row(
        children: [
          const Expanded(child: Text('Foto gelöscht')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: actionColor),
            onPressed: () => messenger.hideCurrentSnackBar(),
            child: const Text('Bestätigen'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: actionColor),
            onPressed: () {
              undone = true;
              if (mounted) {
                setState(() =>
                    _images = List.of(_images)..insert(originalIndex, target));
              }
              messenger.hideCurrentSnackBar();
            },
            child: const Text('Rückgängig'),
          ),
        ],
      ),
    ));

    await controller.closed;
    if (undone || !mounted) return;

    // Commit: persist the removal and clean up Storage. The Storage delete
    // is best-effort — a failure there (e.g. an orphaned object from a
    // previous auth/account) must not surface as an unhandled exception,
    // matching the fire-and-forget cleanup pattern used elsewhere
    // (EntryRepository's Firestore syncs, deleteEntryById's image cleanup).
    await ref
        .read(entryRepositoryProvider)
        .updateEntryImages(entryId: _entryId, images: _images);
    unawaited(ref
        .read(imageProxyClientProvider)
        .deleteImages([target.fullPath, target.thumbPath])
        .catchError((Object e) {
      debugPrint('[TopicsReviewScreen] image delete cleanup failed: $e');
    }));
  }

  // Matches this package's own README example verbatim — unlike raw
  // Flutter ReorderableListView/SliverReorderableList, its onReorder indices
  // are already pre-adjusted for a direct removeAt/insert, no manual
  // "if (oldIndex < newIndex) newIndex -= 1" off-by-one correction needed.
  void _onReorderImages(int oldIndex, int newIndex) {
    setState(() {
      final item = _images.removeAt(oldIndex);
      _images.insert(newIndex, item);
      for (var i = 0; i < _images.length; i++) {
        _images[i] = _images[i].copyWith(order: i);
      }
    });
    unawaited(ref
        .read(entryRepositoryProvider)
        .updateEntryImages(entryId: _entryId, images: _images));
  }

  Widget _buildPhotosSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget tileFor(EntryImage img) => _PhotoTile(
          key: ValueKey(img.fullPath),
          objectPath: img.thumbPath,
          isEditing: _isEditingPhotos,
          onTap: _isEditingPhotos
              ? null
              : () => FullscreenImageViewer.open(context,
                  images: _images, initialIndex: _images.indexOf(img)),
          onDelete: () => _deleteImage(img),
        );

    const gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Fotos · ${_images.length}',
                style: tt.labelMedium?.copyWith(color: cs.onSurface)),
            const Spacer(),
            // Also shown while _isEditingPhotos, even with zero images left —
            // deleting the last photo mid-edit must not strand the user in
            // edit mode with no escape hatch back to the "Hinzufügen" tile
            // (which only renders in the non-editing branch below).
            if (_images.isNotEmpty || _isEditingPhotos)
              TextButton(
                onPressed: () =>
                    setState(() => _isEditingPhotos = !_isEditingPhotos),
                child: Text(_isEditingPhotos ? 'Fertig' : 'Bearbeiten'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Two separate rendering paths rather than one mixed-type grid:
        // AnimatedReorderableGridView's `items` list is homogeneously typed
        // (List<EntryImage>), so it can't also host the "Hinzufügen" add-tile
        // or in-flight upload placeholders — and it never needs to, since
        // editing and adding are mutually exclusive states here already.
        if (_isEditingPhotos)
          AnimatedReorderableGridView<EntryImage>(
            items: _images,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            sliverGridDelegate: gridDelegate,
            isSameItem: (a, b) => a.fullPath == b.fullPath,
            itemBuilder: (context, index) => tileFor(_images[index]),
            onReorder: _onReorderImages,
            // The drag gesture's own completion already animates the new
            // order; enableSwap's same-length diff pass (which re-detects
            // "swapped" pairs whenever the `items` list we hand back via
            // setState differs from the previous build) then runs AGAIN on
            // top of that and can call moveItem for both directions of a
            // detected pair, undoing the very reorder that just happened.
            // Pure reordering doesn't need this reconciliation — inserts/
            // removes (upload/delete) go through the length-changing branch
            // below it, which is unaffected.
            enableSwap: false,
          )
        else
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: gridDelegate,
            children: [
              for (final img in _images) tileFor(img),
              for (final u in _uploadingImages)
                KeyedSubtree(
                  key: ValueKey(u.id),
                  child: _UploadingTile(bytes: u.bytes),
                ),
              if (_totalImageCount < kMaxImagesPerEntry)
                _AddPhotoTile(
                  key: const ValueKey('add-photo-tile'),
                  onTap: _showImageSourceSheet,
                ),
            ],
          ),
      ],
    );
  }

  // ── Finish entry ─────────────────────────────────────────────────────────────

  Future<void> _handleFinishEntry() async {
    if (ref.read(authServiceProvider.notifier).isAnonymous) {
      final success = await showAuthSheet(context);
      if (!success || !mounted) return;
      await runHistorySyncWithProgress(context, ref);
      if (!mounted) return;
    }
    if (mounted) context.go('/history');
  }

  // ── Back navigation — the entry already exists locally at this point
  // (saveEntry ran back on RecordingScreen), so leaving via the back button
  // must not silently abandon it half-synced. Ask the user to either finish
  // it (same as "Eintrag abschließen") or discard it outright.

  Future<void> _handleBackPressed() async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Eintrag noch nicht abgeschlossen',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          content: Text(
            'Möchtest du deinen Eintrag speichern oder verwerfen?',
            style: tt.bodyMedium,
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('delete'),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: const Text('Verwerfen'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('save'),
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );

    if (action == null || action == 'cancel' || !mounted) return;

    if (action == 'delete') {
      await ref.read(entryRepositoryProvider).deleteEntryById(_entryId);
      if (mounted) _leaveScreen();
      return;
    }

    // action == 'save' — same finalize path as "Eintrag abschließen",
    // then continue the back-navigation the user originally asked for.
    if (ref.read(authServiceProvider.notifier).isAnonymous) {
      final success = await showAuthSheet(context);
      if (!success || !mounted) return;
      await runHistorySyncWithProgress(context, ref);
      if (!mounted) return;
    } else {
      await ref.read(entryRepositoryProvider).flushPendingSyncs();
      if (!mounted) return;
    }
    if (mounted) _leaveScreen();
  }

  // context.pop() throws if this screen isn't on top of a pushed route (e.g.
  // reached directly, or the stack was lost on a web refresh) — fall back to
  // the recording screen in that case instead of crashing.
  void _leaveScreen() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  // ── Von vorne anfangen ────────────────────────────────────────────────────────

  Future<void> _confirmDeleteAll() async {
    final confirmed = await _showConfirmDialog(
      title: 'Von vorne anfangen?',
      body: 'Alle Aufnahmen und der aktuelle Eintrag werden gelöscht.',
      confirmLabel: 'Alles löschen',
    );
    if (confirmed && mounted) {
      await ref.read(entryRepositoryProvider).deleteEntryById(_entryId);
      if (mounted) context.go('/');
    }
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title,
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          content: Text(body, style: tt.bodyMedium),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Abbrechen')),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  // ── Entrance animation ────────────────────────────────────────────────────────

  Widget _animated(int index, Widget child) {
    const stagger = 0.11;
    final start = (index * stagger).clamp(0.0, 0.55);
    final end = (start + 0.45).clamp(0.0, 1.0);
    final curve = CurvedAnimation(
        parent: _entrance,
        curve: Interval(start, end, curve: Curves.easeOut));
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position:
            Tween(begin: const Offset(0, 0.10), end: Offset.zero).animate(curve),
        child: child,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPressed();
      },
      child: Scaffold(
      backgroundColor: cs.surface,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Nav bar ────────────────────────────────────────────────
                SizedBox(
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        left: 4,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (context.canPop())
                              IconButton(
                                onPressed: _handleBackPressed,
                                icon: Icon(Icons.arrow_back_ios_new_rounded,
                                    size: 20, color: cs.onSurface),
                                tooltip: 'Zurück',
                              ),
                            const SizedBox(width: 4),
                            _MoodChip(mood: _mood, moodScore: _moodScore),
                          ],
                        ),
                      ),
                      if (_headerDateLine.isNotEmpty)
                        Text(_headerDateLine,
                            style: tt.bodyMedium?.copyWith(color: cs.outline)),
                      Positioned(
                        right: 4,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const ProfileAvatarButton(),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert_rounded,
                                  color: cs.onSurface),
                              onSelected: (v) {
                                if (v == 'reset') _confirmDeleteAll();
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'reset',
                                  child: Row(
                                    children: [
                                      Icon(Icons.restart_alt_rounded,
                                          size: 18, color: cs.error),
                                      const SizedBox(width: 10),
                                      Text('Von vorne anfangen',
                                          style: TextStyle(color: cs.error)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Scrollable content ─────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      20, 4, 20,
                      160 + MediaQuery.of(context).padding.bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Headline
                        _animated(
                          0,
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _topics.isEmpty
                                      ? 'Keine Themen erkannt.'
                                      : '${_topics.length} ${_topics.length == 1 ? 'Thema' : 'Themen'} erkannt.',
                                  style: tt.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                if (_topics.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Möchtest du etwas vertiefen?',
                                    style: tt.bodyMedium?.copyWith(
                                      color: cs.primary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        // ── Aufnahmen section ──────────────────────────────
                        _animated(1, _buildRecordingsSection(context)),
                        const SizedBox(height: 24),

                        // ── Themen ─────────────────────────────────────────
                        for (int i = 0; i < _topics.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _animated(
                              i + 2,
                              _TopicCard(
                                key: ValueKey(_topics[i].title),
                                topic: _topics[i],
                              ),
                            ),
                          ),

                        // ── Fotos ───────────────────────────────────────────
                        // Deliberately NOT wrapped in _animated(): the
                        // reorderable grid measures each tile's on-screen
                        // position via GlobalKey + localToGlobal() for its
                        // drag math, which a live SlideTransition/
                        // FadeTransition ancestor would keep out of sync
                        // with the actual rendered position.
                        if (_resolvedDate != null) ...[
                          _buildPhotosSection(context),
                          const SizedBox(height: 24),
                        ],

                        // ── Weitere Fragen ─────────────────────────────────
                        if (_followUpQuestions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _animated(
                            _topics.length + 3,
                            _buildQuestionsSection(context),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Sticky CTA ──────────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                20, 12, 20,
                MediaQuery.of(context).padding.bottom + 16,
              ),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(
                    top: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.5))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isNearTranscriptLimit)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Dein Eintrag ist heute schon sehr umfangreich — '
                        'bitte kürze bestehenden Text, um mehr zu ergänzen.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.error,
                            ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _isNearTranscriptLimit
                        ? null
                        : () => _showRecordingOverlay(
                              ContinuingEntry(entryId: _entryId),
                            ),
                    icon: const Icon(Icons.mic_none_rounded, size: 18),
                    label: const Text('Eintrag vertiefen'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onSurface,
                      side: BorderSide(color: cs.outlineVariant),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _topics.isNotEmpty
                        ? () => _handleFinishEntry()
                        : null,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Eintrag abschließen'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onSurface,
                      side: BorderSide(color: cs.outlineVariant),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Re-generating overlay ────────────────────────────────────────
          if (_isRegenerating)
            Container(
              color: Colors.black.withValues(alpha: 0.35),
              child: Center(
                child: Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: _regenPercent),
                          duration: const Duration(milliseconds: 200),
                          builder: (_, v, __) => Text(
                            '${(v * 100).round()}%',
                            style: Theme.of(context)
                                .textTheme
                                .displayMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w200,
                                  color: Theme.of(context).colorScheme.primary,
                                  letterSpacing: -1,
                                ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _regenStep,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }

  // ── Aufnahmen section ────────────────────────────────────────────────────────

  Widget _buildRecordingsSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toggle row
        GestureDetector(
          onTap: () => setState(
              () => _isRecordingsExpanded = !_isRecordingsExpanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.mic_none_rounded, size: 15, color: cs.outline),
                const SizedBox(width: 6),
                Text('Aufnahmen',
                    style: tt.labelMedium?.copyWith(color: cs.onSurface)),
                const SizedBox(width: 8),
                Text(
                  '${_recordings.length} ${_recordings.length == 1 ? 'Aufnahme' : 'Aufnahmen'}',
                  style: tt.labelSmall?.copyWith(color: cs.outline),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _isRecordingsExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20, color: cs.outline),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOut,
          child: _isRecordingsExpanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    for (int i = 0; i < _recordings.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _NormalizedTextBubble(
                          record: _recordings[i],
                          onEdit: () => _editRecording(i),
                          onDelete: () => _deleteRecording(i),
                        ),
                      ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ── Weitere Fragen section ────────────────────────────────────────────────────

  Widget _buildQuestionsSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.auto_awesome_rounded,
                    size: 16, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mein KI-Tagebuch fragt',
                      style: tt.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    '${_followUpQuestions.length} ${_followUpQuestions.length == 1 ? 'Impuls' : 'Impulse'} zum Vertiefen',
                    style: tt.labelSmall?.copyWith(color: cs.outline),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_isNearTranscriptLimit)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Dein Eintrag ist heute schon sehr umfangreich — '
              'bitte kürze bestehenden Text, um mehr zu ergänzen.',
              style: tt.bodySmall?.copyWith(color: cs.error),
            ),
          ),
        ...List.generate(
          _followUpQuestions.length,
          (i) => InkWell(
            onTap: _isNearTranscriptLimit
                ? null
                : () => _showRecordingOverlay(
                      ExtendingTopic(
                        entryId: _entryId,
                        topicTitle: 'Mein KI-Tagebuch fragt',
                        followUpHint: _followUpQuestions[i],
                      ),
                    ),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.chat_bubble_outline_rounded,
                        size: 16,
                        color: _isNearTranscriptLimit
                            ? cs.outline
                            : cs.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _followUpQuestions[i],
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurface.withValues(
                            alpha: _isNearTranscriptLimit ? 0.4 : 0.75),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Recording overlay sheet ───────────────────────────────────────────────────

class _RecordingOverlay extends StatelessWidget {
  const _RecordingOverlay({
    required this.recordingContext,
    required this.onComplete,
    required this.onCancel,
  });

  final RecordingContext recordingContext;
  final Future<void> Function(String rawTranscript) onComplete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final contextLabel = switch (recordingContext) {
      ExtendingTopic(:final topicTitle) when topicTitle == 'Mein KI-Tagebuch fragt' =>
        'Antwort aufnehmen',
      ExtendingTopic(:final topicTitle) => 'Ergänzt · $topicTitle',
      ContinuingEntry() => 'Ergänzen',
      _ => 'Aufnahme',
    };

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Context chip + close
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(contextLabel,
                    style: tt.labelMedium
                        ?.copyWith(color: cs.onPrimaryContainer)),
              ),
              const Spacer(),
              IconButton(
                onPressed: onCancel,
                icon: Icon(Icons.close_rounded, color: cs.outline),
                tooltip: 'Abbrechen',
              ),
            ],
          ),
          // Hint text
          if (recordingContext is ExtendingTopic) ...[
            const SizedBox(height: 12),
            Text(
              (recordingContext as ExtendingTopic).followUpHint ??
                  'Was möchtest du ergänzen?',
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.6),
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          RecordingControls(
            recordingContext: recordingContext,
            onComplete: onComplete,
            onCancel: onCancel,
            idleLabel: 'Aufnahme starten',
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Normalized text bubble ────────────────────────────────────────────────────

class _NormalizedTextBubble extends StatelessWidget {
  const _NormalizedTextBubble({
    required this.record,
    required this.onEdit,
    required this.onDelete,
  });

  final _RecordingRecord record;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static String _formatTime(DateTime dt) {
    const weekdays = ['', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    const months = [
      '', 'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
      'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${weekdays[dt.weekday]}, ${dt.day}. ${months[dt.month]} · $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Provenance + timestamp row
        Row(
          children: [
            Icon(Icons.mic_rounded, size: 12, color: cs.outline),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${_formatTime(record.timestamp)} · ${record.provenanceLabel}',
                style: tt.labelSmall?.copyWith(color: cs.outline),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onEdit,
          onLongPress: onDelete,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  record.normalizedText,
                  style:
                      tt.bodyMedium?.copyWith(color: cs.onSurface, height: 1.55),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: onEdit,
                      child: Icon(Icons.edit_outlined,
                          size: 14,
                          color: cs.outline.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: onDelete,
                      child: Icon(Icons.delete_outline_rounded,
                          size: 14,
                          color: cs.outline.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Topic card ────────────────────────────────────────────────────────────────

class _TopicCard extends StatelessWidget {
  const _TopicCard({super.key, required this.topic});
  final _TopicData topic;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: topic.accentColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topic.title.toUpperCase(),
                        style: tt.labelSmall?.copyWith(
                          color: topic.accentColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        topic.text,
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurface,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Photo tile ─────────────────────────────────────────────────────────────────

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    super.key,
    required this.objectPath,
    required this.isEditing,
    required this.onTap,
    required this.onDelete,
  });

  final String objectPath;
  final bool isEditing;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            // onTap is null while editing (see callers) — a GestureDetector
            // with no active callback registers no recognizer, so it never
            // competes with the drag detector the ancestor
            // AnimatedReorderableGridView wraps around this whole tile
            // (which is what makes the ENTIRE card draggable, not just the
            // drag-handle icon). Deliberately NOT IgnorePointer here — that
            // would remove this subtree from hit-testing altogether, which
            // also hides it from the ancestor's own deferToChild-based hit
            // detection and breaks dragging over the image area entirely.
            child: GestureDetector(
              onTap: onTap,
              child: StorageImage(objectPath: objectPath),
            ),
          ),
        ),
        if (isEditing) ...[
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.close_rounded,
                    size: 15, color: Colors.white),
              ),
            ),
          ),
          const Positioned(
            top: 6,
            left: 6,
            child: _DragHandle(),
          ),
        ],
      ],
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.drag_indicator_rounded,
          size: 14, color: Colors.white),
    );
  }
}

class _UploadingTile extends StatelessWidget {
  const _UploadingTile({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(bytes, fit: BoxFit.cover),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: DottedBorderBox(
        color: cs.primary,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 22, color: cs.primary),
            const SizedBox(height: 4),
            Text('Hinzufügen',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.primary)),
          ],
        ),
      ),
    );
  }
}

/// Minimal dashed-border container — avoids pulling in a dependency just for
/// a single dashed rectangle.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: color),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(14));
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

// ── Mood chip ──────────────────────────────────────────────────────────────────

class _MoodChip extends StatelessWidget {
  const _MoodChip({required this.mood, required this.moodScore});
  final String mood;
  final double moodScore;

  String get _emoji => switch (mood) {
        'happy' => '😊',
        'calm' => '😌',
        'tense' => '😰',
        'sad' => '😔',
        'mixed' => '🤔',
        _ => '😐',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _emoji,
        style: tt.labelSmall,
      ),
    );
  }
}
