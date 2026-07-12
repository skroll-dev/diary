import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';

import '../../../core/database/app_database.dart' as db;
import '../../../shared/models/entry.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/providers/dev_settings.dart';
import '../../../shared/repositories/entry_repository.dart';
import '../../../shared/widgets/profile_avatar_button.dart';

// ─── Palette (mirrors _topicPalette in topics_review_screen.dart) ────────────

const _tagPalette = [
  (Color(0xFFEDE9FF), Color(0xFF5E35B1)),
  (Color(0xFFE8F5E9), Color(0xFF2E7D32)),
  (Color(0xFFFFF3E0), Color(0xFFBF360C)),
  (Color(0xFFE3F2FD), Color(0xFF1565C0)),
  (Color(0xFFFCE4EC), Color(0xFFC62828)),
];

// ─── Local data model ────────────────────────────────────────────────────────

class _EntryPreview {
  const _EntryPreview({
    required this.date,
    required this.mood,
    required this.title,
    required this.preview,
    required this.durationSeconds,
    required this.tags,
    required this.paletteIndex,
    this.allTopics = const [],
    this.entryDate = '',
  });

  final DateTime date;
  final Mood mood;
  final String title;
  final String preview;
  final int durationSeconds;
  final List<String> tags;
  final int paletteIndex;
  final List<Map<String, dynamic>> allTopics;
  final String entryDate; // raw yyyy-MM-dd string for DB operations
}

// ─── Index entry (for scrubber) ───────────────────────────────────────────────

class _IndexEntry {
  const _IndexEntry({
    required this.year,
    required this.month,
    required this.label,
    required this.estimatedOffset,
  });

  final int year;
  final int month; // 0 = year-level entry
  final String label;
  final double estimatedOffset;

  bool get isYear => month == 0;
}

// ─── Mock data generation ────────────────────────────────────────────────────

const _mockTitles = [
  'Gespräch mit Mama',
  'Gedanken nach der Arbeit',
  'Langer Spaziergang im Regen',
  'Endlich Feierabend',
  'Streit vergessen',
  'Sommergewitter gestern Nacht',
  'Neue Woche, neue Energie',
  'Wochenende zuhause',
  'Träume der letzten Nacht',
  'Kurze Pause im Alltag',
  'Kino mit Freunden',
  'Stadtbummel',
  'Endlich wieder Sport',
  'Herbststimmung',
  'Gedanken über die Zukunft',
  'Eltern besucht',
  'Einfach nur müde',
  'Etwas Neues ausprobiert',
  'Ruhiger Abend',
  'Morgen wird besser',
];

const _mockPreviews = [
  'Wir haben lange geredet, mehr als sonst. Es war schön, aber auch aufwühlend. Ich merke, wie sehr mir das gefehlt hat.',
  'Der Tag war anstrengend. Im Meeting gab es wieder Diskussionen, aber am Ende haben wir eine Lösung gefunden.',
  'Trotz des Regens bin ich rausgegangen. Der Wald war still und ich konnte endlich wieder klar denken.',
  'Heute war richtig produktiv. Ich hab alles erledigt was auf der Liste stand und das fühlt sich gut an.',
  'Der Ärger von gestern ist verflogen. Manchmal hilft einfach eine Nacht schlafen mehr als stundenlange Gespräche.',
  'Das Gewitter hat mich um vier Uhr morgens geweckt. Seltsam beruhigend, der Regen auf dem Dach.',
  'Montag und trotzdem motiviert. Ich versuche, diese Energie durch die Woche zu retten.',
  'Nichts geplant, einfach zuhause geblieben. Gelesen, gekocht, Musik gehört. Genau das was ich brauchte.',
  'Ich erinnere mich kaum noch, aber das Gefühl bleibt: Irgendwas Wichtiges wurde mir gezeigt.',
  'Fünfzehn Minuten auf der Bank vor dem Büro. Die Sonne, der Kaffee. Das war genug.',
  'Wir haben einen alten Film gesehen und danach noch ewig geredet. Genau so Freundschaft.',
  'Einfach durch die Stadt gelaufen, ohne Ziel. Man sieht so viel mehr, wenn man nicht hetzen muss.',
  'Erster Lauf seit Monaten. Kurz und langsam, aber ich war draußen. Das ist was zählt.',
  'Die Bäume werden langsam bunt. Ich stehe jeden Morgen länger am Fenster und schaue raus.',
  'Wo will ich in fünf Jahren sein? Ich merke, dass ich immer noch keine klare Antwort habe.',
  'Das Mittagessen war lang und laut und schön. So sollte Familie sein.',
  'Nichts Besonderes passiert. Ich bin einfach müde und das ist okay.',
  'Ich hab zum ersten Mal gekocht ohne Rezept. Hat nicht perfekt geschmeckt, aber ich war stolz.',
  'Tee, Buch, Couch. Die beste Variante eines Abends die ich mir vorstellen kann.',
  'Es war ein harter Tag. Aber ich glaube, morgen wird es leichter. Das muss ich einfach glauben.',
];

const _mockTagPools = [
  ['Familie', 'Gespräch'],
  ['Natur', 'Spaziergang'],
  ['Arbeit', 'Stress'],
  ['Freunde', 'Freizeit'],
  ['Gedanken', 'Träume'],
];

List<_EntryPreview> _generateMockEntries() {
  final rng = Random(42);
  final entries = <_EntryPreview>[];
  int entryIndex = 0;

  const moods = Mood.values;
  const moodWeights = [2, 4, 4, 1, 1, 2]; // happy calm neutral tense sad mixed

  for (var year = 2016; year <= 2025; year++) {
    for (var month = 1; month <= 12; month++) {
      if (rng.nextDouble() < 0.65) continue;

      final daysInMonth = DateTime(year, month + 1, 0).day;
      final entryCount = 1 + rng.nextInt(7);

      final days = <int>{};
      while (days.length < entryCount && days.length < daysInMonth) {
        days.add(1 + rng.nextInt(daysInMonth));
      }

      for (final day in days) {
        final palette = entryIndex % 5;
        final titleIdx = entryIndex % _mockTitles.length;
        final tags = List<String>.from(_mockTagPools[palette]);
        if (rng.nextBool()) tags.removeLast();

        final roll = rng.nextInt(moodWeights.fold(0, (a, b) => a + b));
        var acc = 0;
        var moodIdx = 0;
        for (var i = 0; i < moodWeights.length; i++) {
          acc += moodWeights[i];
          if (roll < acc) {
            moodIdx = i;
            break;
          }
        }

        entries.add(_EntryPreview(
          date: DateTime(year, month, day),
          mood: moods[moodIdx],
          title: _mockTitles[titleIdx],
          preview: _mockPreviews[titleIdx],
          durationSeconds: 120 + rng.nextInt(781),
          tags: tags,
          paletteIndex: palette,
        ));

        entryIndex++;
      }
    }
  }

  entries.sort((a, b) => b.date.compareTo(a.date));
  return entries;
}

// ─── Grouping helper ─────────────────────────────────────────────────────────

Map<int, Map<int, List<_EntryPreview>>> _groupEntries(
    List<_EntryPreview> entries) {
  final result = <int, Map<int, List<_EntryPreview>>>{};
  for (final e in entries) {
    result
        .putIfAbsent(e.date.year, () => {})
        .putIfAbsent(e.date.month, () => [])
        .add(e);
  }
  return result;
}

// ─── Index builder for scrubber ───────────────────────────────────────────────

const _kYearHeaderH = 57.0;
const _kMonthHeaderH = 44.0;
const _kCardH = 130.0;

const _monthNamesShort = [
  '',
  'Jan.',
  'Feb.',
  'März',
  'Apr.',
  'Mai',
  'Juni',
  'Juli',
  'Aug.',
  'Sep.',
  'Okt.',
  'Nov.',
  'Dez.',
];

(List<_IndexEntry>, double) _buildIndex(
    Map<int, Map<int, List<_EntryPreview>>> grouped) {
  final entries = <_IndexEntry>[];
  double offset = 0;

  for (final year in grouped.keys) {
    entries.add(_IndexEntry(
      year: year,
      month: 0,
      label: '$year',
      estimatedOffset: offset,
    ));
    offset += _kYearHeaderH;

    for (final month in grouped[year]!.keys) {
      entries.add(_IndexEntry(
        year: year,
        month: month,
        label: '${_monthNamesShort[month]} $year',
        estimatedOffset: offset,
      ));
      offset += _kMonthHeaderH;
      offset += grouped[year]![month]!.length * _kCardH;
    }
  }

  return (entries, offset);
}

// ─── Date / duration helpers ─────────────────────────────────────────────────

const _weekdays = ['', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const _monthNames = [
  '',
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

String _formatEntryDate(DateTime dt) =>
    '${_weekdays[dt.weekday]}, ${dt.day}. ${_monthNames[dt.month]}';

String _formatDuration(int seconds) => '${(seconds / 60).round()} Min';

String _moodEmoji(Mood m) => switch (m) {
      Mood.happy => '😊',
      Mood.calm => '😌',
      Mood.tense => '😰',
      Mood.sad => '😔',
      Mood.mixed => '🤔',
      _ => '😐',
    };

// ─── Real-data provider ───────────────────────────────────────────────────────

final _historyEntriesProvider = StreamProvider<List<db.Entry>>((ref) {
  return ref.watch(entryRepositoryProvider).watchAllEntries();
});

// ─── DB → preview mapping ─────────────────────────────────────────────────────

List<String> _parseTags(String json) {
  try {
    return (jsonDecode(json) as List).cast<String>();
  } catch (_) {
    return [];
  }
}

List<Map<String, dynamic>> _parseTopics(String json) {
  try {
    return (jsonDecode(json) as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return [];
  }
}

String _stripMarkdown(String md) {
  return md
      .replaceAll(RegExp(r'#{1,6} '), '')
      .replaceAll('**', '')
      .replaceAll('*', '')
      .replaceAll('__', '')
      .replaceAll('_', '')
      .replaceAll('\n', ' ')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
}

_EntryPreview _toPreview(db.Entry e, int index) {
  final topics = _parseTopics(e.topics);
  final title = topics.isNotEmpty
      ? (topics.first['title'] as String? ?? '')
      : e.date;
  final date = DateTime.tryParse(e.date) ?? DateTime.now();
  return _EntryPreview(
    date: date,
    mood: Mood.values.firstWhere(
      (m) => m.name == e.mood,
      orElse: () => Mood.neutral,
    ),
    title: title,
    preview: _stripMarkdown(e.bodyMarkdown),
    durationSeconds: e.durationSeconds,
    tags: _parseTags(e.tags),
    paletteIndex: index % 5,
    allTopics: topics,
    entryDate: e.date,
  );
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  static final _entries = _generateMockEntries();

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  AppBar _appBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      title: const Text('Mein Tagebuch'),
      actions: const [ProfileAvatarButton(), SizedBox(width: 8)],
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    Map<int, Map<int, List<_EntryPreview>>> grouped,
  ) {
    final cs = Theme.of(context).colorScheme;
    final built = _buildIndex(grouped);
    final indexEntries = built.$1;
    final totalH = built.$2;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: _appBar(context),
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              for (final year in grouped.keys)
                SliverStickyHeader(
                  header: _YearHeader(year: year),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      for (final month in grouped[year]!.keys)
                        SliverStickyHeader(
                          header: _MonthHeader(year: year, month: month),
                          sliver: SliverList.builder(
                            itemCount: grouped[year]![month]!.length,
                            itemBuilder: (ctx, i) {
                              final e = grouped[year]![month]![i];
                              return _EntryCard(entry: e)
                                  .animate()
                                  .fadeIn(duration: 250.ms, delay: (i * 30).ms)
                                  .slideY(begin: 0.05, end: 0);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
          if (indexEntries.isNotEmpty)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: _ScrollScrubber(
                entries: indexEntries,
                controller: _scrollController,
                totalEstimatedHeight: totalH,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: _appBar(context),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.book_outlined, size: 56, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'Noch keine Einträge',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Nimm deinen ersten Tagebucheintrag auf\nund er erscheint hier.',
              style: tt.bodyMedium?.copyWith(color: cs.outline),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.mic_rounded),
              label: const Text('Ersten Eintrag aufnehmen'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final useFakeHistory = ref.watch(useFakeHistoryProvider);

    if (useFakeHistory) {
      return _buildScaffold(context, _groupEntries(HistoryScreen._entries));
    }

    final async = ref.watch(_historyEntriesProvider);
    return async.when(
      loading: () => Scaffold(
        appBar: _appBar(context),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: _appBar(context),
        body: const Center(child: Text('Fehler beim Laden')),
      ),
      data: (dbEntries) {
        if (dbEntries.isEmpty) return _buildEmptyState(context);
        final previews = dbEntries
            .asMap()
            .entries
            .map((e) => _toPreview(e.value, e.key))
            .toList();
        return _buildScaffold(context, _groupEntries(previews));
      },
    );
  }
}

// ─── Year sticky header ───────────────────────────────────────────────────────

class _YearHeader extends StatelessWidget {
  const _YearHeader({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ColoredBox(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              '$year',
              style: tt.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: cs.onSurface,
              ),
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            indent: 20,
            endIndent: 20,
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

// ─── Month sticky header ──────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.year, required this.month});

  final int year;
  final int month;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final label = '${_monthNames[month]} $year';
    return ColoredBox(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
        child: Text(
          label,
          style: tt.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.primary,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}

// ─── Entry card ───────────────────────────────────────────────────────────────

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final _EntryPreview entry;

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EntryDetailSheet(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: entry.allTopics.isNotEmpty ? () => _openDetail(context) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _moodEmoji(entry.mood),
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatEntryDate(entry.date)} · ${_formatDuration(entry.durationSeconds)}',
                      style: tt.labelSmall?.copyWith(color: cs.outline),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    if (entry.allTopics.length > 1) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: entry.allTopics
                            .map((t) => _TopicChip(
                                  label: t['title'] as String? ?? '',
                                  paletteIndex: entry.paletteIndex,
                                ))
                            .toList(),
                      ),
                    ],
                    if (entry.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: entry.tags
                            .map((t) => _TagChip(
                                  tag: t,
                                  paletteIndex: entry.paletteIndex,
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              if (entry.allTopics.isNotEmpty)
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: cs.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Topic chip (card summary) ────────────────────────────────────────────────

class _TopicChip extends StatelessWidget {
  const _TopicChip({required this.label, required this.paletteIndex});

  final String label;
  final int paletteIndex;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _tagPalette[paletteIndex % _tagPalette.length];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}

// ─── Entry detail sheet ───────────────────────────────────────────────────────

class _EntryDetailSheet extends ConsumerWidget {
  const _EntryDetailSheet({required this.entry});

  final _EntryPreview entry;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: const Text(
            'Dieser Eintrag wird dauerhaft gelöscht und kann nicht wiederhergestellt werden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(entryRepositoryProvider).deleteEntryForDate(entry.entryDate);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Text(_moodEmoji(entry.mood),
                      style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatEntryDate(entry.date),
                          style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _formatDuration(entry.durationSeconds),
                          style:
                              tt.labelSmall?.copyWith(color: cs.outline),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: cs.outlineVariant.withValues(alpha: 0.4)),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  if (entry.preview.isNotEmpty) ...[
                    Text(
                      entry.preview,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    'Themen',
                    style: tt.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.outline,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (int i = 0; i < entry.allTopics.length; i++) ...[
                    _DetailTopicCard(
                      topic: entry.allTopics[i],
                      paletteIndex: (entry.paletteIndex + i) % _tagPalette.length,
                    ),
                    if (i < entry.allTopics.length - 1)
                      const SizedBox(height: 12),
                  ],
                  if (entry.tags.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: entry.tags
                          .map((t) => _TagChip(
                                tag: t,
                                paletteIndex: entry.paletteIndex,
                              ))
                          .toList(),
                    ),
                  ],
                  if (entry.entryDate.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Divider(color: cs.outlineVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => _confirmDelete(context, ref),
                        icon: Icon(Icons.delete_outline_rounded,
                            color: cs.error, size: 18),
                        label: Text('Eintrag löschen',
                            style: TextStyle(color: cs.error)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Detail topic card ────────────────────────────────────────────────────────

class _DetailTopicCard extends StatelessWidget {
  const _DetailTopicCard(
      {required this.topic, required this.paletteIndex});

  final Map<String, dynamic> topic;
  final int paletteIndex;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (_, accent) = _tagPalette[paletteIndex % _tagPalette.length];
    final title = topic['title'] as String? ?? '';
    final text = topic['text'] as String? ?? '';

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
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.toUpperCase(),
                        style: tt.labelSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        text,
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

// ─── Tag chip ─────────────────────────────────────────────────────────────────

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag, required this.paletteIndex});

  final String tag;
  final int paletteIndex;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _tagPalette[paletteIndex % _tagPalette.length];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '#$tag',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// ─── Scroll scrubber ──────────────────────────────────────────────────────────

class _ScrollScrubber extends StatefulWidget {
  const _ScrollScrubber({
    required this.entries,
    required this.controller,
    required this.totalEstimatedHeight,
  });

  final List<_IndexEntry> entries;
  final ScrollController controller;
  final double totalEstimatedHeight;

  @override
  State<_ScrollScrubber> createState() => _ScrollScrubberState();
}

class _ScrollScrubberState extends State<_ScrollScrubber> {
  bool _isDragging = false;
  int _activeIndex = 0;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_isDragging) return;
    if (!widget.controller.hasClients) return;
    final offset = widget.controller.offset;
    int best = 0;
    for (int i = 0; i < widget.entries.length; i++) {
      if (widget.entries[i].estimatedOffset <= offset) {
        best = i;
      } else {
        break;
      }
    }
    if (_activeIndex != best) setState(() => _activeIndex = best);
  }

  int _bestIndex(double dy, double barHeight) {
    final fraction = (dy / barHeight).clamp(0.0, 1.0);
    final targetOffset = fraction * widget.totalEstimatedHeight;
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < widget.entries.length; i++) {
      final d = (widget.entries[i].estimatedOffset - targetOffset).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  void _jumpTo(int index) {
    if (!widget.controller.hasClients) return;
    widget.controller.jumpTo(
      widget.entries[index].estimatedOffset
          .clamp(0, widget.controller.position.maxScrollExtent),
    );
  }

  void _onTap(TapDownDetails details, double barHeight) {
    final best = _bestIndex(details.localPosition.dy, barHeight);
    setState(() => _activeIndex = best);
    _jumpTo(best);
  }

  void _onDragUpdate(DragUpdateDetails details, double barHeight) {
    final best = _bestIndex(details.localPosition.dy, barHeight);
    setState(() {
      _isDragging = true;
      _activeIndex = best;
    });
    _jumpTo(best);
  }

  void _onDragEnd(DragEndDetails _) {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _isDragging = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final barHeight = constraints.maxHeight;

        return SizedBox(
          width: 52,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (d) => _onTap(d, barHeight),
            onVerticalDragStart: (_) => setState(() => _isDragging = true),
            onVerticalDragUpdate: (d) => _onDragUpdate(d, barHeight),
            onVerticalDragEnd: _onDragEnd,
            child: AnimatedOpacity(
              opacity: _isDragging ? 1.0 : 0.45,
              duration: const Duration(milliseconds: 200),
              child: CustomPaint(
                size: Size(52, barHeight),
                painter: _ScrubberPainter(
                  entries: widget.entries,
                  activeIndex: _activeIndex,
                  totalEstimatedHeight: widget.totalEstimatedHeight,
                  barHeight: barHeight,
                  color: cs.onSurface,
                  activeColor: cs.primary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Scrubber painter ─────────────────────────────────────────────────────────

class _ScrubberPainter extends CustomPainter {
  _ScrubberPainter({
    required this.entries,
    required this.activeIndex,
    required this.totalEstimatedHeight,
    required this.barHeight,
    required this.color,
    required this.activeColor,
  });

  final List<_IndexEntry> entries;
  final int activeIndex;
  final double totalEstimatedHeight;
  final double barHeight;
  final Color color;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Track runs along the right edge; year labels paint to the left of it.
    final cx = size.width - 10; // = 42 with the 52px canvas

    // Track line
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.height),
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final fraction = totalEstimatedHeight > 0
          ? (entry.estimatedOffset / totalEstimatedHeight).clamp(0.0, 1.0)
          : 0.0;
      final y = fraction * size.height;
      final isActive = i == activeIndex;

      if (entry.isYear) {
        final tickColor =
            isActive ? activeColor : color.withValues(alpha: 0.65);

        // Tick: fixed left anchor so it never overlaps the label.
        // Active state is expressed via color/weight only, not geometry.
        const tickLeft = 12.0; // distance left of cx where tick starts
        canvas.drawLine(
          Offset(cx - tickLeft, y),
          Offset(cx + 3, y),
          Paint()
            ..color = tickColor
            ..strokeWidth = isActive ? 2.5 : 2.0
            ..strokeCap = StrokeCap.round,
        );

        // Year label with 4 px breathing room before the tick (Material 4dp unit).
        const labelGap = 4.0;
        final tp = TextPainter(
          text: TextSpan(
            text: '${entry.year}',
            style: TextStyle(
              color: tickColor,
              fontSize: 9.0,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final tickLeftX = cx - tickLeft;
        final textX = (tickLeftX - labelGap - tp.width).clamp(1.0, tickLeftX - labelGap);
        final textY = (y - tp.height / 2).clamp(0.0, size.height - tp.height);
        tp.paint(canvas, Offset(textX, textY));
      } else {
        canvas.drawCircle(
          Offset(cx, y),
          isActive ? 3.5 : 2.0,
          Paint()
            ..color =
                isActive ? activeColor : color.withValues(alpha: 0.45)
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ScrubberPainter old) =>
      old.activeIndex != activeIndex ||
      old.barHeight != barHeight ||
      old.color != color ||
      old.activeColor != activeColor;
}

