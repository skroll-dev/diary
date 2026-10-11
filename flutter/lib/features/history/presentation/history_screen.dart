import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';

import '../../../core/database/app_database.dart' as db;
import '../../../shared/models/entry.dart';
import '../../../shared/models/entry_image.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../l10n/app_localizations.dart';
import '../../../shared/extensions/localization_extensions.dart';
import '../../../shared/providers/dev_settings.dart';
import '../../../shared/repositories/entry_repository.dart';
import '../../../shared/services/auth_service.dart';
import '../../../shared/services/proxy_client.dart' show TopicDto;
import '../../../shared/utils/mood_labels.dart';
import '../../../shared/widgets/fullscreen_image_viewer.dart';
import '../../../shared/widgets/history_sync_dialog.dart';
import '../../../shared/widgets/marker_style.dart';
import '../../../shared/widgets/profile_avatar_button.dart';
import '../../../shared/widgets/storage_image.dart';

// ─── Local data model ────────────────────────────────────────────────────────

class _EntryPreview {
  const _EntryPreview({
    required this.date,
    required this.mood,
    required this.title,
    required this.preview,
    required this.durationSeconds,
    required this.tags,
    this.allTopics = const [],
    this.entryDate = '',
    this.createdTime = '',
    this.rawEntry,
    this.images = const [],
  });

  final DateTime date;
  final Mood mood;
  final String title;
  final String preview;
  final int durationSeconds;
  final List<String> tags;
  final List<Map<String, dynamic>> allTopics;
  final String entryDate;
  final String createdTime; // "HH:mm Uhr" — shown when durationSeconds == 0
  // Deliberately empty for mock-data entries — the photo strip only ever
  // appears when real photos exist, never as a placeholder.
  final List<EntryImage> images;
  // Full Drift row, needed for id-based edit/delete. Null only for the
  // mock-data (dev "Fake Verlauf-Daten") path.
  final db.Entry? rawEntry;
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

const _kMonthHeaderH = 34.0;
// One topic block: highlighted title + up to three lines of prose.
const _kTopicH = 104.0;
// Per entry, on top of its topics: time/mood line, tags, padding.
const _kEntryChromeH = 44.0;
// Photo strip plus its position rail, added for entries with photos.
const _kCarouselH = 220.0;
// Extra padding at the top and bottom of each day's band.
const _kDayGapH = 16.0;

int _uniqueDayCount(List<_EntryPreview> entries) {
  final days = <DateTime>{};
  for (final e in entries) {
    days.add(DateTime(e.date.year, e.date.month, e.date.day));
  }
  return days.length;
}

(List<_IndexEntry>, double) _buildIndex(
    Map<int, Map<int, List<_EntryPreview>>> grouped, String locale) {
  final entries = <_IndexEntry>[];
  double offset = 0;

  for (final year in grouped.keys) {
    entries.add(_IndexEntry(
      year: year,
      month: 0,
      label: '$year',
      estimatedOffset: offset,
    ));

    for (final month in grouped[year]!.keys) {
      final monthName = DateFormat.MMM(locale).format(DateTime(year, month));
      entries.add(_IndexEntry(
        year: year,
        month: month,
        label: '$monthName $year',
        estimatedOffset: offset,
      ));
      offset += _kMonthHeaderH;
      final monthEntries = grouped[year]![month]!;
      for (final e in monthEntries) {
        offset += _topicBlocks(e).length * _kTopicH +
            _kEntryChromeH +
            (e.images.isNotEmpty ? _kCarouselH : 0);
      }
      offset += _uniqueDayCount(monthEntries) * _kDayGapH;
    }
  }

  return (entries, offset);
}

// ─── Date / duration helpers ─────────────────────────────────────────────────

String _formatEntryDate(DateTime dt, String locale) {
  final weekday = DateFormat.E(locale).format(dt);
  final month = DateFormat.MMMM(locale).format(dt);
  return locale == 'de'
      ? '$weekday, ${dt.day}. $month'
      : '$weekday, $month ${dt.day}';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _formatDuration(int seconds, AppLocalizations l10n) =>
    l10n.historyDurationMinutes((seconds / 60).round());

String _formatCreatedTime(String iso, AppLocalizations l10n) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final time =
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  return l10n.historyTimeSuffix(time);
}

// ─── Real-data provider ───────────────────────────────────────────────────────

final _historyEntriesProvider = StreamProvider<List<db.Entry>>((ref) {
  // watchAllEntries() resolves the current uid once, at subscription time —
  // re-watch on auth state changes (e.g. anonymous → signed-in) so the query
  // picks up the new uid instead of staying stuck on the old one.
  ref.watch(authServiceProvider);
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

_EntryPreview _toPreview(db.Entry e, int index, AppLocalizations l10n) {
  final topics = _parseTopics(e.topics);
  final title =
      topics.isNotEmpty ? (topics.first['title'] as String? ?? '') : e.date;
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
    allTopics: topics,
    entryDate: e.date,
    createdTime: _formatCreatedTime(e.createdAt, l10n),
    rawEntry: e,
    images: parseEntryImages(e.images),
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
      title: Text(context.l10n.historyTitle),
      actions: const [ProfileAvatarButton(), SizedBox(width: 8)],
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    Map<int, Map<int, List<_EntryPreview>>> grouped, {
    Future<void> Function()? onRefresh,
  }) {
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    final built = _buildIndex(grouped, locale);
    final indexEntries = built.$1;
    final totalH = built.$2;

    // Days alternate between two faint background tones, so each day reads as
    // one band. The count runs on across month boundaries.
    final tinted = <_EntryPreview, bool>{};
    var dayIndex = -1;
    DateTime? lastDate;
    for (final months in grouped.values) {
      for (final monthEntries in months.values) {
        for (final e in monthEntries) {
          if (lastDate == null || !_isSameDay(lastDate, e.date)) dayIndex++;
          lastDate = e.date;
          tinted[e] = dayIndex.isEven;
        }
      }
    }

    final scrollView = CustomScrollView(
      controller: _scrollController,
      // Keeps pull-to-refresh reachable when the entries don't fill the screen.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // No separate year header: the sticky month header already names the
        // year and swaps as the list scrolls.
        for (final year in grouped.keys)
          for (final month in grouped[year]!.keys)
            SliverStickyHeader(
              header: _MonthHeader(year: year, month: month),
              sliver: SliverList.builder(
                itemCount: grouped[year]![month]!.length,
                itemBuilder: (ctx, i) {
                  final monthEntries = grouped[year]![month]!;
                  final e = monthEntries[i];
                  final isFirstOfDay =
                      i == 0 || !_isSameDay(monthEntries[i - 1].date, e.date);
                  final isLastOfDay = i == monthEntries.length - 1 ||
                      !_isSameDay(monthEntries[i + 1].date, e.date);
                  return _MarkerEntry(
                    entry: e,
                    showDate: isFirstOfDay,
                    endsDay: isLastOfDay,
                    tinted: tinted[e] ?? false,
                  ).animate().fadeIn(duration: 250.ms);
                },
              ),
            ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: _appBar(context),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/'),
        tooltip: context.l10n.historyNewEntryTooltip,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add_rounded),
      ),
      body: Stack(
        children: [
          onRefresh != null
              ? RefreshIndicator(onRefresh: onRefresh, child: scrollView)
              : scrollView,
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

  Widget _buildEmptyState(
    BuildContext context, {
    Future<void> Function()? onRefresh,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.book_outlined, size: 56, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text(
            context.l10n.historyEmptyTitle,
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.historyEmptyBody,
            style: tt.bodyMedium?.copyWith(color: cs.outline),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.mic_rounded),
            label: Text(context.l10n.historyEmptyButton),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: _appBar(context),
      body: onRefresh == null
          ? content
          : RefreshIndicator(
              onRefresh: onRefresh,
              child: LayoutBuilder(
                builder: (context, constraints) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: constraints.maxHeight,
                      child: content,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _handleRefresh() => runHistorySyncWithProgress(context, ref);

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
        body: Center(child: Text(context.l10n.historyLoadError)),
      ),
      data: (dbEntries) {
        if (dbEntries.isEmpty) {
          return _buildEmptyState(context, onRefresh: _handleRefresh);
        }
        final l10n = context.l10n;
        final previews = dbEntries
            .asMap()
            .entries
            .map((e) => _toPreview(e.value, e.key, l10n))
            .toList();
        return _buildScaffold(
          context,
          _groupEntries(previews),
          onRefresh: _handleRefresh,
        );
      },
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
    final locale = Localizations.localeOf(context).languageCode;
    final monthName = DateFormat.MMMM(locale).format(DateTime(year, month));
    final label = '$monthName $year';
    return ColoredBox(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
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

// ─── Marker entry (calendar-leaf style: drop-cap date, highlighted title) ─────

const _kEntryLeftInset = 20.0;
// Keeps prose clear of the scrubber track on the right edge.
const _kEntryRightInset = 28.0;
const _kCapGap = 12.0;

// One (title, text) pair per identified topic. Entries without topics fall
// back to their own title and body.
List<(String, String)> _topicBlocks(_EntryPreview e) {
  final blocks = [
    for (final t in e.allTopics)
      (
        (t['title'] as String? ?? '').trim(),
        _stripMarkdown(t['text'] as String? ?? ''),
      ),
  ].where((b) => b.$1.isNotEmpty || b.$2.isNotEmpty).toList();
  return blocks.isEmpty ? [(e.title, e.preview)] : blocks;
}

class _MarkerEntry extends StatelessWidget {
  const _MarkerEntry({
    required this.entry,
    required this.showDate,
    required this.endsDay,
    required this.tinted,
  });

  final _EntryPreview entry;
  // First entry of its day — carries the date leaf.
  final bool showDate;
  // Last entry of its day — closes the day's band.
  final bool endsDay;
  // Whether this entry's day sits on the tinted band or the plain one.
  final bool tinted;

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

    // Material, not ColoredBox, so the InkWell's splash paints on the band.
    return Material(
      color: tinted ? cs.surfaceContainer : cs.surface,
      child: InkWell(
        onTap: entry.allTopics.isNotEmpty ? () => _openDetail(context) : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              _kEntryLeftInset, showDate ? 14 : 4, 0, endsDay ? 14 : 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Every topic of the entry is listed; only the first carries the
              // date cap and the entry's time/mood line.
              for (final (i, (title, text)) in _topicBlocks(entry).indexed)
                Padding(
                  padding: EdgeInsets.only(
                      top: i == 0 ? 0 : 10, right: _kEntryRightInset),
                  child: _MarkerText(
                    entry: entry,
                    title: title,
                    text: text,
                    showDate: showDate && i == 0,
                    showMeta: i == 0,
                  ),
                ),
              if (entry.tags.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(0, 6, _kEntryRightInset, 0),
                  child: Text(
                    entry.tags.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              // The photos close the entry — on a day with several entries they
              // are the only thing between one entry's topics and the next.
              if (entry.images.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _PhotoCarousel(images: entry.images),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Marker text (date cap, title, meta, preview) ─────────────────────────────

class _MarkerText extends StatelessWidget {
  const _MarkerText({
    required this.entry,
    required this.title,
    required this.text,
    required this.showDate,
    required this.showMeta,
    this.expanded = false,
    this.metaPrefix,
  });

  final _EntryPreview entry;
  final String title;
  final String text;
  final bool showDate;
  // Time and mood belong to the entry, so only its first topic shows them.
  final bool showMeta;
  // Detail sheet: the whole text instead of the overview's three-line preview.
  final bool expanded;
  // Leads the time/mood line — the detail sheet names month and year there,
  // since it has no sticky month header above it.
  final String? metaPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final mood = moodColor(entry.mood.name);

    final titleStyle =
        markerSerif(size: 21, height: 1.2, weight: 600, color: cs.onSurface);
    final bodyStyle =
        markerSerif(size: 15.5, height: 1.36, color: cs.onSurface);

    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MarkerHighlightedTitle(
          text: title,
          style: titleStyle,
          color: moodHighlight(mood, theme.brightness),
        ),
        if (showMeta) const SizedBox(height: 2),
        if (showMeta)
          Text.rich(
            TextSpan(
              children: [
                if (metaPrefix != null) TextSpan(text: '$metaPrefix · '),
                if (entry.createdTime.isNotEmpty)
                  TextSpan(text: '${entry.createdTime} · '),
                TextSpan(
                  text: moodLabel(context, entry.mood.name).toLowerCase(),
                  style: markerSerif(
                    size: 14,
                    italic: true,
                    color: moodInk(mood, theme.brightness),
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.labelSmall?.copyWith(color: cs.outline),
          ),
      ],
    );

    if (!showDate) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          head,
          if (text.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              text,
              maxLines: expanded ? null : 3,
              overflow: expanded ? null : TextOverflow.ellipsis,
              style: bodyStyle,
            ),
          ],
        ],
      );
    }

    final inherited = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    TextPainter measure(String text, TextStyle style, {int? maxLines}) =>
        TextPainter(
          text: TextSpan(text: text, style: inherited.merge(style)),
          textDirection: direction,
          textScaler: scaler,
          maxLines: maxLines,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrowWidth =
            max(0.0, constraints.maxWidth - kMarkerLeafWidth - _kCapGap);

        // Flutter has no float layout, so the wrap around the leaf is done by
        // hand: a one-line title leaves room for exactly one line of prose
        // beside it, and the rest continues at full width below it.
        final titlePainter = measure(title, titleStyle, maxLines: 2)
          ..layout(maxWidth: narrowWidth);
        final titleLines = titlePainter.computeLineMetrics().length;
        titlePainter.dispose();

        var firstLine = '';
        var rest = text;
        if (titleLines == 1 && rest.isNotEmpty) {
          // The text can be a whole chapter — only its start matters here.
          final probe = rest.length > 300 ? rest.substring(0, 300) : rest;
          final probePainter = measure(probe, bodyStyle, maxLines: 1)
            ..layout(maxWidth: narrowWidth);
          final end =
              probePainter.getLineBoundary(const TextPosition(offset: 0)).end;
          probePainter.dispose();
          firstLine = rest.substring(0, end).trimRight();
          rest = rest.substring(end).trimLeft();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 5),
                  child: MarkerDateLeaf(date: entry.date),
                ),
                const SizedBox(width: _kCapGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      head,
                      if (firstLine.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          firstLine,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: bodyStyle,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (rest.isNotEmpty)
              Text(
                rest,
                maxLines: expanded ? null : (firstLine.isEmpty ? 3 : 2),
                overflow: expanded ? null : TextOverflow.ellipsis,
                style: bodyStyle,
              ),
          ],
        );
      },
    );
  }
}

// ─── Photo carousel (auto-rotating, swipeable photos) ─────────────────────────

class _PhotoCarousel extends StatefulWidget {
  const _PhotoCarousel({required this.images});

  final List<EntryImage> images;

  @override
  State<_PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<_PhotoCarousel> {
  static const _interval = Duration(seconds: 5);
  static const _slide = Duration(milliseconds: 900);
  static const _height = 190.0;
  static const _radius = BorderRadius.all(Radius.circular(4));

  // Starts away from zero so the PageView can be swiped in both directions;
  // the real image is always `page % images.length`. Kept small on purpose:
  // the scroll offset is `page * width`, and with a fractional page width a
  // six-digit page offset loses enough double precision to trip a layout
  // assertion in RenderSliverFixedExtentBoxAdaptor (seen at page ~5000).
  late final int _homePage = widget.images.length * 10;
  late final PageController _controller =
      PageController(initialPage: _homePage);
  late int _page = _controller.initialPage;
  Timer? _timer;

  bool get _multiple => widget.images.length > 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant _PhotoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.images.length != widget.images.length) _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // One-shot, re-armed after every page change — so a manual swipe always
  // grants the new photo its full five seconds.
  void _restartTimer() {
    _timer?.cancel();
    if (!_multiple || MediaQuery.disableAnimationsOf(context)) return;
    _timer = Timer(_interval, () {
      if (!mounted || !_controller.hasClients) return;
      // Auto-rotation would otherwise walk the page index up without bound;
      // hop back to the same photo near the home page before sliding on.
      if ((_page - _homePage).abs() >= _homePage) {
        _controller.jumpToPage(_homePage + _page % widget.images.length);
      }
      _controller.nextPage(duration: _slide, curve: Curves.easeInOutCubic);
    });
  }

  // Tapping a photo opens it full screen; the rest of the entry still opens
  // the detail sheet.
  Widget _photo(int index) => GestureDetector(
        onTap: () => FullscreenImageViewer.open(
          context,
          images: widget.images,
          initialIndex: index,
        ),
        child: SizedBox.expand(
          child: StorageImage(objectPath: widget.images[index].fullPath),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final images = widget.images;

    if (!_multiple) {
      return Padding(
        padding: const EdgeInsets.only(right: _kEntryLeftInset),
        child: SizedBox(
          height: _height,
          child: ClipRRect(borderRadius: _radius, child: _photo(0)),
        ),
      );
    }

    final index = _page % images.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: _kEntryLeftInset),
          child: SizedBox(
            height: _height,
            child: ClipRRect(
              borderRadius: _radius,
              // Hold the rotation while a finger is down, so the photo never
              // slides away mid-drag.
              child: Listener(
                onPointerDown: (_) => _timer?.cancel(),
                onPointerUp: (_) => _restartTimer(),
                onPointerCancel: (_) => _restartTimer(),
                child: PageView.builder(
                  controller: _controller,
                  // Keeps the neighbouring photos built, so a slide never
                  // reveals an unloaded placeholder.
                  allowImplicitScrolling: true,
                  onPageChanged: (page) {
                    setState(() => _page = page);
                    _restartTimer();
                  },
                  itemBuilder: (_, i) => _photo(i % images.length),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, _kEntryLeftInset, 0),
          child: Row(
            children: [
              Text(
                context.l10n.historyPhotoPosition(index + 1, images.length),
                style: markerSerif(size: 13, italic: true, color: cs.outline),
              ),
              const SizedBox(width: 10),
              // Rail: the thumb is one photo wide and slides a step per photo.
              Expanded(
                child: SizedBox(
                  height: 2,
                  child: ColoredBox(
                    color: cs.outlineVariant,
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      alignment:
                          Alignment(-1 + 2 * index / (images.length - 1), 0),
                      child: FractionallySizedBox(
                        widthFactor: 1 / images.length,
                        heightFactor: 1,
                        child: ColoredBox(color: cs.onSurface),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Entry detail sheet ───────────────────────────────────────────────────────

class _EntryDetailSheet extends ConsumerWidget {
  const _EntryDetailSheet({required this.entry});

  final _EntryPreview entry;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.historyDeleteEntryTitle),
        content: Text(l10n.historyDeleteEntryBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    final id = entry.rawEntry?.id;
    if (confirmed == true && id != null && context.mounted) {
      await ref.read(entryRepositoryProvider).deleteEntryById(id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  void _edit(BuildContext context) {
    final e = entry.rawEntry!;
    Navigator.of(context).pop();
    context.push('/topics?entryId=${e.id}', extra: (
      entryId: e.id,
      date: _formatEntryDate(
          entry.date, Localizations.localeOf(context).languageCode),
      duration: entry.durationSeconds > 0
          ? _formatDuration(entry.durationSeconds, context.l10n)
          : '',
      topics: entry.allTopics.map((t) => TopicDto.fromJson(t)).toList(),
      normalizedTranscript: '',
      bodyMarkdown: e.bodyMarkdown,
      mood: e.mood,
      moodScore: e.moodScore,
      followUpQuestions: _parseTags(e.followUpQuestions),
      transcriptReason: 'initial',
      isEditMode: true,
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final entryId = entry.rawEntry?.id;

    return DraggableScrollableSheet(
      // Opens nearly full height: the point of tapping an entry is to read
      // all of it without another gesture.
      initialChildSize: 0.92,
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
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Same shape as the overview, so opening an entry reads as
                  // that entry unfolding: the first topic carries the date
                  // cap, and every topic shows its whole text.
                  for (final (i, (title, text)) in _topicBlocks(entry).indexed)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
                      child: _MarkerText(
                        entry: entry,
                        title: title,
                        text: text,
                        showDate: i == 0,
                        showMeta: i == 0,
                        expanded: true,
                        metaPrefix: i == 0
                            ? DateFormat.yMMMM(Localizations.localeOf(context)
                                    .languageCode)
                                .format(entry.date)
                            : null,
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (entry.images.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: entry.images.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                        childAspectRatio: 1.15,
                      ),
                      itemBuilder: (context, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: GestureDetector(
                          onTap: () => FullscreenImageViewer.open(
                            context,
                            images: entry.images,
                            initialIndex: i,
                          ),
                          child: StorageImage(
                              objectPath: entry.images[i].thumbPath),
                        ),
                      ),
                    ),
                  ],
                  if (entry.tags.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      entry.tags.join(' · '),
                      style: tt.labelMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (entryId != null) _RecordingsSection(entryId: entryId),
                ],
              ),
            ),
            if (entry.entryDate.isNotEmpty)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (entry.rawEntry != null)
                        TextButton.icon(
                          onPressed: () => _edit(context),
                          icon: Icon(Icons.edit_outlined,
                              color: cs.primary, size: 18),
                          label: Text(context.l10n.historyEditEntry,
                              style: TextStyle(color: cs.primary)),
                        )
                      else
                        const SizedBox.shrink(),
                      TextButton.icon(
                        onPressed: () => _confirmDelete(context, ref),
                        icon: Icon(Icons.delete_outline_rounded,
                            color: cs.error, size: 18),
                        label: Text(context.l10n.historyDeleteEntry,
                            style: TextStyle(color: cs.error)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Recordings (what was actually said, collapsed by default) ────────────────

String _provenanceLabel(String reason, AppLocalizations l10n) {
  if (reason == 'initial') return l10n.topicsProvenanceInitial;
  if (reason == 'continuation') return l10n.topicsProvenanceContinuation;
  if (reason.startsWith('followUp:')) {
    return l10n.topicsProvenanceFollowUp(reason.substring('followUp:'.length));
  }
  return l10n.topicsProvenanceDefault;
}

class _RecordingsSection extends ConsumerStatefulWidget {
  const _RecordingsSection({required this.entryId});

  final String entryId;

  @override
  ConsumerState<_RecordingsSection> createState() => _RecordingsSectionState();
}

class _RecordingsSectionState extends ConsumerState<_RecordingsSection> {
  // Memoized, so a rebuild (e.g. on expand) never re-queries the database.
  late final Future<List<db.RawTranscript>> _transcripts =
      ref.read(entryRepositoryProvider).getTranscriptsForEntry(widget.entryId);
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = context.l10n;

    return FutureBuilder<List<db.RawTranscript>>(
      future: _transcripts,
      builder: (context, snap) {
        final recordings = (snap.data ?? const <db.RawTranscript>[])
            .where((t) => t.normalizedContent.trim().isNotEmpty)
            .toList();
        if (recordings.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Divider(
                  height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
              InkWell(
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.topicsRecordingsCount(recordings.length),
                          style: tt.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.outline,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.expand_more_rounded,
                            size: 20, color: cs.outline),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !_open
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final t in recordings)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    [
                                      _formatCreatedTime(t.createdAt, l10n),
                                      _provenanceLabel(t.reason, l10n),
                                    ].where((s) => s.isNotEmpty).join(' · '),
                                    style: tt.labelSmall
                                        ?.copyWith(color: cs.outline),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    t.normalizedContent.trim(),
                                    style: markerSerif(
                                      size: 15,
                                      height: 1.45,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
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
        final textX =
            (tickLeftX - labelGap - tp.width).clamp(1.0, tickLeftX - labelGap);
        final textY = (y - tp.height / 2).clamp(0.0, size.height - tp.height);
        tp.paint(canvas, Offset(textX, textY));
      } else {
        canvas.drawCircle(
          Offset(cx, y),
          isActive ? 3.5 : 2.0,
          Paint()
            ..color = isActive ? activeColor : color.withValues(alpha: 0.45)
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
