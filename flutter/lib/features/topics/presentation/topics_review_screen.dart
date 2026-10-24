import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:animated_reorderable_list/animated_reorderable_list.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:intl/intl.dart' hide TextDirection;

import '../../auth/presentation/auth_sheet.dart';
import '../../recording/recording_context.dart';
import 'entry_date_sheet.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/constants/image_limits.dart';
import '../../../shared/extensions/localization_extensions.dart';
import '../../../shared/models/entry_image.dart';
import '../../../shared/repositories/entry_repository.dart';
import '../../../shared/services/auth_service.dart';
import '../../../shared/services/image_proxy_client.dart';
import '../../../shared/utils/mood_labels.dart';
import '../../../shared/widgets/fullscreen_image_viewer.dart';
import '../../../shared/widgets/profile_avatar_button.dart';
import '../../../shared/widgets/storage_image.dart';
import '../../../shared/services/proxy_client.dart';
import '../../../shared/widgets/history_sync_dialog.dart';
import '../../../shared/widgets/marker_style.dart';
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
  });
  final String title;
  final String text;
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

  String provenanceLabel(AppLocalizations l10n) {
    if (reason == 'initial') return l10n.topicsProvenanceInitial;
    if (reason == 'continuation') return l10n.topicsProvenanceContinuation;
    if (reason.startsWith('followUp:')) {
      final q = reason.substring('followUp:'.length);
      return l10n.topicsProvenanceFollowUp(q);
    }
    return l10n.topicsProvenanceDefault;
  }
}

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
    this.isEditMode = false,
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
  // true when opened from History to edit an already-saved entry: back
  // navigation must never offer to discard/delete it, only fresh recordings
  // (not yet confirmed by the user) get that option.
  final bool isEditMode;

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
  late final String _entryId = widget.entryId;
  late final bool _isEditMode = widget.isEditMode;

  // Open by default: the recordings are the part the user can edit, and the
  // topics below are derived from them.
  bool _isRecordingsExpanded = true;
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
      dtos.map((dto) => _TopicData(title: dto.title, text: dto.text)).toList();

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

      final l10n = context.l10n;
      final languageCode = Localizations.localeOf(context).languageCode;
      final sw = Stopwatch()..start();
      _setRegenStep(l10n.pipelineReadingText, 0.0, 0.35);
      final normalized =
          await ref.read(proxyClientProvider).normalize(rawTranscript, languageCode: languageCode);
      _completeRegenStep(0.35);
      debugPrint('[Pipeline] normalize (merge): ${sw.elapsedMilliseconds}ms');
      sw.reset(); sw.start();

      _setRegenStep(l10n.pipelineMerging, 0.36, 1.0);
      final existingTags = await ref.read(entryRepositoryProvider).getAllTags();
      final entry = await ref.read(proxyClientProvider).mergeEntry(
            existingBody: _bodyMarkdown,
            newTranscript: normalized,
            previousQuestions: _followUpQuestions,
            languageCode: languageCode,
            existingTags: existingTags,
          );
      _completeRegenStep(1.0);
      debugPrint('[Pipeline] merge: ${sw.elapsedMilliseconds}ms');

      // Update UI immediately — DB save is best-effort and must not block this
      if (mounted) {
        setState(() {
          _bodyMarkdown = entry.bodyMarkdown;
          _mood = entry.mood;
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
            languageCode: languageCode,
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
          SnackBar(content: Text(context.l10n.topicsMergeError)),
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
      title: context.l10n.topicsTextTooLongTitle,
      hint: message,
      initialValue: offendingText,
      confirmLabel: context.l10n.topicsResendConfirm,
    );
    if (edited == null || edited.isEmpty || !mounted) return;
    await onRetry(edited);
  }

  // ── Transcript edit/delete ────────────────────────────────────────────────────

  Future<void> _editRecording(int index) async {
    final record = _recordings[index];
    final result = await showTranscriptInputSheet(
      context,
      title: context.l10n.topicsEditRecordingTitle,
      hint: '',
      initialValue: record.normalizedText,
      confirmLabel: context.l10n.save,
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
      title: context.l10n.topicsDeleteRecordingTitle,
      body: context.l10n.topicsDeleteRecordingBody,
      confirmLabel: context.l10n.delete,
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
    final l10n = context.l10n;
    final languageCode = Localizations.localeOf(context).languageCode;
    final combined =
        overrideText ?? _recordings.map((r) => r.normalizedText).join('\n\n');
    try {
      final sw = Stopwatch()..start();
      _setRegenStep(l10n.pipelineThinking, 0.0, 1.0);
      final existingTags = await ref.read(entryRepositoryProvider).getAllTags();
      final entry = await ref.read(proxyClientProvider).generateEntry(
        combined,
        languageCode: languageCode,
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
            languageCode: languageCode,
            tags: entry.tags,
          );
      if (mounted) {
        setState(() {
          _bodyMarkdown = entry.bodyMarkdown;
          _mood = entry.mood;
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
          SnackBar(content: Text(context.l10n.topicsUpdateError)),
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
                title: Text(context.l10n.topicsCamera),
                onTap: () => Navigator.of(sheetCtx).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(context.l10n.topicsGallery),
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

  // A fresh recording has no stored date yet; it belongs to today.
  DateTime get _entryDate =>
      DateTime.tryParse(_resolvedDate ?? '') ?? DateUtils.dateOnly(DateTime.now());

  // Assigns this (fresh, not opened-from-Diary) entry to another day. UI
  // updates first; the DB write is best-effort like every save here.
  Future<void> _changeEntryDate() async {
    if (_isEditMode || _entryId.isEmpty) return;
    final repo = ref.read(entryRepositoryProvider);
    Map<String, int> counts = const {};
    try {
      counts = await repo.getEntryCountsByDate(excludeEntryId: _entryId);
    } catch (_) {}
    if (!mounted) return;

    final current = _entryDate;
    final picked = await showEntryDateSheet(
      context,
      initialDate: current,
      entryCounts: counts,
    );
    if (picked == null || !mounted || DateUtils.isSameDay(picked, current)) {
      return;
    }

    final iso = DateFormat('yyyy-MM-dd').format(picked);
    setState(() {
      _resolvedDate = iso;
      // The Storage folder ordinal is per date — recompute on next upload.
      _cachedEntryOrdinal = null;
    });
    try {
      await repo.updateEntryDate(entryId: _entryId, date: iso);
    } catch (_) {}
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
        SnackBar(content: Text(context.l10n.topicsPhotoUploadError)),
      );
    }
  }

  Future<void> _deleteImage(EntryImage target) async {
    final originalIndex = _images.indexOf(target);
    if (originalIndex < 0) return;

    // Instant, no confirmation — re-adding a photo costs a couple of taps
    // from the same camera roll, so an undo/confirm step isn't worth the
    // extra UI (matches "remove from album" elsewhere, e.g. iOS/Google Photos).
    setState(() => _images = List.of(_images)..removeAt(originalIndex));

    // Persist the removal and clean up Storage. The Storage delete is
    // best-effort — a failure there (e.g. an orphaned object from a
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
      crossAxisSpacing: 6,
      mainAxisSpacing: 6,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.l10n.historyPhotosLabel(_images.length),
              style: tt.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.outline,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            // Also shown while _isEditingPhotos, even with zero images left —
            // deleting the last photo mid-edit must not strand the user in
            // edit mode with no escape hatch back to the "Hinzufügen" tile
            // (which only renders in the non-editing branch below).
            if (_images.isNotEmpty || _isEditingPhotos)
              TextButton(
                onPressed: () =>
                    setState(() => _isEditingPhotos = !_isEditingPhotos),
                child: Text(_isEditingPhotos ? context.l10n.done : context.l10n.edit),
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

  // ── Back navigation ──────────────────────────────────────────────────────
  //
  // Edit mode (opened from History for an already-saved entry): every change
  // on this screen already autosaves in place (mergeEntry/updateEntry/
  // updateTranscript/updateEntryImages all write immediately as the user
  // acts), so there is nothing left to "save or discard" — just flush any
  // pending sync and leave. Crucially, this path must never call
  // deleteEntryById: that would destroy a persisted diary entry the user
  // only meant to stop editing.
  //
  // Fresh-recording mode: the entry already exists locally at this point
  // (saveEntry ran back on RecordingScreen), but the user hasn't confirmed
  // they want to keep it yet, so leaving via the back button asks them to
  // either finish it (same as "Eintrag abschließen") or discard it outright.

  Future<void> _handleBackPressed() async {
    if (_isEditMode) {
      unawaited(ref.read(entryRepositoryProvider).flushPendingSyncs());
      _leaveScreen();
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(ctx.l10n.topicsUnsavedEntryTitle,
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          content: Text(
            ctx.l10n.topicsUnsavedEntryBody,
            style: tt.bodyMedium,
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: Text(ctx.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('delete'),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: Text(ctx.l10n.topicsDiscard),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('save'),
              child: Text(ctx.l10n.save),
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
      title: context.l10n.topicsResetAllTitle,
      body: context.l10n.topicsResetAllBody,
      confirmLabel: context.l10n.topicsDeleteAllConfirm,
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
                child: Text(ctx.l10n.cancel)),
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
                                tooltip: context.l10n.topicsBackTooltip,
                              ),
                          ],
                        ),
                      ),
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
                                      Text(context.l10n.topicsResetAll,
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
                      150 + MediaQuery.of(context).padding.bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header: the same date leaf and highlighted
                        // title the Diary overview uses.
                        _animated(0, _buildHeader(context)),

                        // ── Aufnahmen section ──────────────────────────────
                        _animated(1, _buildRecordingsSection(context)),
                        const SizedBox(height: 22),
                        Divider(
                            height: 1,
                            color: cs.outlineVariant.withValues(alpha: 0.4)),
                        const SizedBox(height: 18),

                        // ── Themen ─────────────────────────────────────────
                        // Named as what they are: text derived from the
                        // recordings above, not something to edit directly.
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _animated(
                            1,
                            _sectionHeading(
                              context,
                              title: _topics.isEmpty
                                  ? context.l10n.topicsNoTopics
                                  : context.l10n
                                      .topicsDetectedLabel(_topics.length),
                              hint: context.l10n.topicsDetectedHint,
                            ),
                          ),
                        ),
                        for (int i = 0; i < _topics.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _animated(
                              i + 2,
                              _TopicCard(
                                key: ValueKey(_topics[i].title),
                                topic: _topics[i],
                                mood: _mood,
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
                        context.l10n.topicsNearLimitWarning,
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
                    label: Text(context.l10n.topicsDeepenEntry),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onSurface,
                      side: BorderSide(color: cs.outlineVariant),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: const RoundedRectangleBorder(
                          borderRadius: _kButtonRadius),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed:
                        _topics.isNotEmpty ? () => _handleFinishEntry() : null,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(context.l10n.topicsFinishEntry),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: const RoundedRectangleBorder(
                          borderRadius: _kButtonRadius),
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

  // ── Header ────────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final date = _entryDate;
    final mood = moodColor(_mood);
    // When the entry was made: its first recording's time. That is "now" for
    // a fresh recording and the stored time once loaded from the database.
    final at =
        _recordings.isNotEmpty ? _recordings.first.timestamp : DateTime.now();
    final time = '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    // An entry dated to an earlier day than it was recorded on says so
    // instead of showing a time that belongs to another day.
    final backdated = !DateUtils.isSameDay(date, at);
    final madeLabel = backdated
        ? context.l10n.entryDateBackdatedOn(DateFormat.MMMd(locale).format(at))
        : context.l10n.historyTimeSuffix(time);

    // The leaf names weekday and day, the title beside it month and year.
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _isEditMode
                ? MarkerDateLeaf(date: date)
                : Semantics(
                    button: true,
                    label: context.l10n.entryDateChangeLabel,
                    child: GestureDetector(
                      onTap: _changeEntryDate,
                      child: MarkerDateLeaf(date: date),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarkerHighlightedTitle(
                  text: DateFormat.yMMMM(locale).format(date),
                  style: markerSerif(
                      size: 23, height: 1.2, weight: 600, color: cs.onSurface),
                  color: moodHighlight(mood, theme.brightness),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '$madeLabel · '),
                      TextSpan(
                        text: moodLabel(context, _mood).toLowerCase(),
                        style: markerSerif(
                          size: 14,
                          italic: true,
                          color: moodInk(mood, theme.brightness),
                        ),
                      ),
                    ],
                  ),
                  style: tt.labelSmall?.copyWith(color: cs.outline),
                ),
                // Only a fresh entry can be dated to another day — one opened
                // from the Diary keeps its date.
                if (!_isEditMode) ...[
                  const SizedBox(height: 8),
                  _buildDateChip(context, date),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateChip(BuildContext context, DateTime date) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).languageCode;
    final today = DateUtils.dateOnly(DateTime.now());
    final String label;
    if (DateUtils.isSameDay(date, today)) {
      label = l10n.entryDateToday;
    } else if (DateUtils.isSameDay(
        date, today.subtract(const Duration(days: 1)))) {
      label = l10n.entryDateYesterday;
    } else {
      label = DateFormat.MMMEd(locale).format(date);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: l10n.entryDateChangeLabel,
        child: ActionChip(
          onPressed: _changeEntryDate,
          avatar: Icon(Icons.calendar_today_outlined, size: 15, color: cs.primary),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded, size: 16, color: cs.primary),
            ],
          ),
          labelStyle: TextStyle(
              color: cs.primary, fontWeight: FontWeight.w600, fontSize: 13),
          backgroundColor: cs.primaryContainer.withValues(alpha: 0.35),
          side: BorderSide(color: cs.primary.withValues(alpha: 0.6)),
          shape: const StadiumBorder(),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  // A section's headline with one line saying what the section is for.
  Widget _sectionHeading(
    BuildContext context, {
    required String title,
    required String hint,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 2),
        Text(hint, style: tt.bodySmall?.copyWith(color: cs.outline)),
      ],
    );
  }

  // ── Aufnahmen section ────────────────────────────────────────────────────────

  Widget _buildRecordingsSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Heading row doubles as the collapse toggle
        InkWell(
          onTap: () => setState(
              () => _isRecordingsExpanded = !_isRecordingsExpanded),
          child: _sectionHeading(
            context,
            title: l10n.topicsRecordingsLabel,
            hint: l10n.topicsRecordingsHint,
            trailing: AnimatedRotation(
              turns: _isRecordingsExpanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: Icon(Icons.expand_more_rounded,
                  size: 22, color: cs.outline),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _isRecordingsExpanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < _recordings.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _NormalizedTextBubble(
                          record: _recordings[i],
                          onEdit: () => _editRecording(i),
                          onDelete: () => _deleteRecording(i),
                        ),
                      ),
                  ],
                )
              : const SizedBox(width: double.infinity),
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
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: _sectionHeading(
            context,
            title: context.l10n.topicsAiAsks,
            hint: context.l10n.topicsWantToDeepen,
          ),
        ),
        if (_isNearTranscriptLimit)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              context.l10n.topicsNearLimitWarning,
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
                        topicTitle: context.l10n.topicsAiAsks,
                        followUpHint: _followUpQuestions[i],
                      ),
                    ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _followUpQuestions[i],
                      style: markerSerif(
                        size: 16,
                        height: 1.36,
                        italic: true,
                        color: cs.onSurface.withValues(
                            alpha: _isNearTranscriptLimit ? 0.4 : 0.85),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // The mic says what a tap does: answer by voice.
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.mic_none_rounded,
                        size: 18,
                        color: _isNearTranscriptLimit
                            ? cs.outline
                            : cs.primary),
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

const _kButtonRadius = BorderRadius.all(Radius.circular(6));
const _kPhotoRadius = BorderRadius.all(Radius.circular(4));

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

    final l10n = context.l10n;
    final contextLabel = switch (recordingContext) {
      ExtendingTopic(:final topicTitle) when topicTitle == l10n.topicsAiAsks =>
        l10n.topicsAnswerRecording,
      ExtendingTopic(:final topicTitle) => l10n.contextChipExtending(topicTitle),
      ContinuingEntry() => l10n.topicsAddLabel,
      _ => l10n.topicsProvenanceDefault,
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
                tooltip: l10n.cancel,
              ),
            ],
          ),
          // Hint text
          if (recordingContext is ExtendingTopic) ...[
            const SizedBox(height: 12),
            Text(
              (recordingContext as ExtendingTopic).followUpHint ??
                  l10n.topicsWhatToAddHint,
              style: markerSerif(
                size: 16,
                height: 1.36,
                italic: true,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          RecordingControls(
            recordingContext: recordingContext,
            onComplete: onComplete,
            onCancel: onCancel,
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

  static String _formatTime(DateTime dt, String locale) {
    final weekday = DateFormat.E(locale).format(dt);
    final month = DateFormat.MMM(locale).format(dt);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final datePart = locale == 'de' ? '$weekday, ${dt.day}. $month' : '$weekday, $month ${dt.day}';
    return '$datePart · $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Provenance + timestamp row, with the edit/delete actions
        Row(
          children: [
            Expanded(
              child: Text(
                '${_formatTime(record.timestamp, Localizations.localeOf(context).languageCode)} · ${record.provenanceLabel(context.l10n)}',
                style: tt.labelSmall?.copyWith(color: cs.outline),
              ),
            ),
            InkWell(
              onTap: onEdit,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_outlined, size: 15, color: cs.primary),
                    const SizedBox(width: 4),
                    Text(
                      context.l10n.edit,
                      style: tt.labelMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            InkResponse(
              onTap: onDelete,
              radius: 18,
              child: Icon(Icons.delete_outline_rounded,
                  size: 16, color: cs.outline),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Framed like a text field, so it reads as something you can edit.
        Material(
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: _kPhotoRadius,
            side: BorderSide(color: cs.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onEdit,
            onLongPress: onDelete,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  record.normalizedText,
                  style: markerSerif(
                      size: 15.5, height: 1.42, color: cs.onSurface),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Topic card ────────────────────────────────────────────────────────────────

class _TopicCard extends StatelessWidget {
  const _TopicCard({super.key, required this.topic, required this.mood});
  final _TopicData topic;
  final String mood;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkerHighlightedTitle(
          text: topic.title,
          style: markerSerif(
              size: 21, height: 1.2, weight: 600, color: cs.onSurface),
          color: moodHighlight(moodColor(mood), theme.brightness),
        ),
        const SizedBox(height: 3),
        Text(
          topic.text,
          style: markerSerif(size: 15.5, height: 1.36, color: cs.onSurface),
        ),
      ],
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
            borderRadius: _kPhotoRadius,
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
            borderRadius: _kPhotoRadius,
            child: Image.memory(bytes, fit: BoxFit.cover),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: _kPhotoRadius,
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
      borderRadius: _kPhotoRadius,
      child: DottedBorderBox(
        color: cs.primary,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 22, color: cs.primary),
            const SizedBox(height: 4),
            Text(context.l10n.topicsAddPhoto,
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
        Offset.zero & size, const Radius.circular(4));
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
