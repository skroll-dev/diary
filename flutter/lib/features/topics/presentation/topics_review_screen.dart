import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../recording/recording_context.dart';
import '../../../shared/repositories/entry_repository.dart';
import '../../../shared/services/proxy_client.dart';
import '../../../shared/widgets/recording_controls.dart';
import '../../../shared/widgets/transcript_input_sheet.dart';

// ── Internal data models ───────────────────────────────────────────────────────

class _TopicData {
  const _TopicData({
    required this.title,
    required this.text,
    required this.followUpHint,
    required this.cardColor,
    required this.accentColor,
  });
  final String title;
  final String text;
  final String followUpHint;
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
  late String _isoDate;

  bool _isRecordingsExpanded = false;
  bool _isRegenerating = false;

  // ── Init ────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _isoDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
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

    // On web refresh state.extra is lost — reload today's entry from Drift
    if (_topics.isEmpty) _loadFromDbIfEmpty();
  }

  Future<void> _loadFromDbIfEmpty() async {
    try {
      final repo = ref.read(entryRepositoryProvider);
      final entry = await repo.getLocalEntryForDate(_isoDate);
      if (entry == null || !mounted) return;

      final topicDtos = (jsonDecode(entry.topics) as List)
          .map((e) => TopicDto.fromJson(e as Map<String, dynamic>))
          .toList();
      final questions = (jsonDecode(entry.followUpQuestions) as List)
          .map((e) => e as String)
          .toList();
      final transcripts = await repo.getTranscriptsForDate(_isoDate);

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
    try {
      final rows = await ref
          .read(entryRepositoryProvider)
          .getTranscriptsForDate(_isoDate);
      if (!mounted || rows.isEmpty) return;
      setState(() {
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
          followUpHint: dto.followUpHint,
          cardColor: card,
          accentColor: accent,
        );
      }).toList();

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
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

      final normalized =
          await ref.read(proxyClientProvider).normalize(rawTranscript);
      final entry = await ref.read(proxyClientProvider).mergeEntry(
            existingBody: _bodyMarkdown,
            newTranscript: normalized,
            previousQuestions: _followUpQuestions,
          );

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
            date: _isoDate,
            rawTranscript: rawTranscript,
            normalizedText: normalized,
            bodyMarkdown: entry.bodyMarkdown,
            mood: entry.mood,
            moodScore: entry.moodScore,
            followUpQuestions: entry.followUpQuestions,
            topics: entry.topics,
            transcriptReason: reason,
          ).then((_) => _loadTranscriptIds()).catchError((_) {}));
    } catch (e) {
      debugPrint('[TopicsReviewScreen] merge error: $e');
    } finally {
      if (mounted) setState(() => _isRegenerating = false);
    }
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

  Future<void> _rederiveFromTranscripts() async {
    setState(() => _isRegenerating = true);
    try {
      final combined =
          _recordings.map((r) => r.normalizedText).join('\n\n');
      final entry =
          await ref.read(proxyClientProvider).generateEntry(combined);
      await ref.read(entryRepositoryProvider).updateEntry(
            date: _isoDate,
            bodyMarkdown: entry.bodyMarkdown,
            mood: entry.mood,
            moodScore: entry.moodScore,
            followUpQuestions: entry.followUpQuestions,
            topics: entry.topics,
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
    } catch (e) {
      debugPrint('[TopicsReviewScreen] re-derive error: $e');
    } finally {
      if (mounted) setState(() => _isRegenerating = false);
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
      await ref.read(entryRepositoryProvider).deleteEntryForDate(_isoDate);
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

    return Scaffold(
      backgroundColor: cs.surface,
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
                      if (context.canPop())
                        Positioned(
                          left: 4,
                          child: IconButton(
                            onPressed: () => context.pop(),
                            icon: Icon(Icons.arrow_back_ios_new_rounded,
                                size: 20, color: cs.onSurface),
                            tooltip: 'Zurück',
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
                            _MoodChip(mood: _mood, moodScore: _moodScore),
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
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Headline
                        _animated(
                          0,
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Text(
                              _topics.isEmpty
                                  ? 'Keine Themen erkannt.'
                                  : '${_topics.length} ${_topics.length == 1 ? 'Thema' : 'Themen'} erkannt.\nMöchtest du etwas vertiefen?',
                              style: tt.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                                letterSpacing: -0.5,
                              ),
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
                                onExtend: () => _showRecordingOverlay(
                                  ExtendingTopic(
                                    topicTitle: _topics[i].title,
                                    followUpHint: _topics[i].followUpHint,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // ── General Ergänzen ───────────────────────────────
                        _animated(
                          _topics.length + 2,
                          _ErgaenzenButton(
                            onTap: () => _showRecordingOverlay(
                              const ContinuingEntry(),
                            ),
                          ),
                        ),

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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(
                    top: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.5))),
              ),
              child: FilledButton(
                onPressed: _topics.isNotEmpty
                    ? () => context.push('/entry/today')
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3730A3),
                  disabledBackgroundColor:
                      const Color(0xFF3730A3).withValues(alpha: 0.38),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                child: const Text('Eintrag erstellen'),
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
                        horizontal: 32, vertical: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 20),
                        Text('Mathias überarbeitet …',
                            style:
                                Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
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
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text('Mathias fragt',
                  style:
                      tt.labelMedium?.copyWith(color: cs.primary)),
            ],
          ),
        ),
        ...List.generate(
          _followUpQuestions.length,
          (i) => InkWell(
            onTap: () => _showRecordingOverlay(
              ExtendingTopic(
                topicTitle: 'Mathias fragt',
                followUpHint: _followUpQuestions[i],
              ),
            ),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _followUpQuestions[i],
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.75),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.mic_none_rounded, size: 18, color: cs.primary),
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
      ExtendingTopic(:final topicTitle) when topicTitle == 'Mathias fragt' =>
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

class _TopicCard extends StatefulWidget {
  const _TopicCard({super.key, required this.topic, required this.onExtend});
  final _TopicData topic;
  final VoidCallback onExtend;

  @override
  State<_TopicCard> createState() => _TopicCardState();
}

class _TopicCardState extends State<_TopicCard> {

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final titleColor =
        Color.lerp(widget.topic.accentColor, Colors.black, 0.25)!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: widget.topic.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            widget.topic.title,
            style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w700, color: titleColor),
          ),
          const SizedBox(height: 10),
          // Topic text — always fully shown
          Text(
            widget.topic.text,
            style: tt.bodyMedium?.copyWith(
                color: widget.topic.accentColor, height: 1.55),
          ),
          // Follow-up hint
          if (widget.topic.followUpHint.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '💬 ${widget.topic.followUpHint}',
              style: tt.bodySmall?.copyWith(
                color: titleColor.withValues(alpha: 0.75),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 14),
          // Ergänzen button
          OutlinedButton.icon(
            onPressed: widget.onExtend,
            icon: Icon(Icons.mic_none_rounded,
                size: 15, color: widget.topic.accentColor),
            label: const Text('Ergänzen'),
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.topic.accentColor,
              side: BorderSide(color: widget.topic.accentColor, width: 1.5),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              textStyle: tt.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}

// ── General Ergänzen button ────────────────────────────────────────────────────

class _ErgaenzenButton extends StatelessWidget {
  const _ErgaenzenButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(Icons.mic_none_rounded, size: 18, color: cs.primary),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ergänzen',
              style: tt.labelLarge?.copyWith(color: cs.primary)),
          Text('Einfach weiterreden — Mathias ordnet es ein',
              style: tt.labelSmall?.copyWith(
                  color: cs.outline)),
        ],
      ),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        foregroundColor: cs.primary,
        side: BorderSide(color: cs.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
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
