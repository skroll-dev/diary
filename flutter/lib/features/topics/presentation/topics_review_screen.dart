import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../recording/recording_context.dart';
import '../../../shared/services/proxy_client.dart' show TopicDto;

class _TopicData {
  final String title;
  final String summary;
  final Color cardColor;
  final Color accentColor;
  final String followUpHint;

  const _TopicData({
    required this.title,
    required this.summary,
    required this.cardColor,
    required this.accentColor,
    required this.followUpHint,
  });
}

// ── Transcript data ───────────────────────────────────────────────────────────

class _TranscriptEntry {
  const _TranscriptEntry({required this.timestamp, required this.text});
  final DateTime timestamp;
  final String text;
}

// ── Color palette cycled per topic ────────────────────────────────────────────

const _topicPalette = [
  (Color(0xFFEDE9FF), Color(0xFF5E35B1)),
  (Color(0xFFE8F5E9), Color(0xFF2E7D32)),
  (Color(0xFFFFF3E0), Color(0xFFBF360C)),
  (Color(0xFFE3F2FD), Color(0xFF1565C0)),
  (Color(0xFFFCE4EC), Color(0xFFC62828)),
];

class TopicsReviewScreen extends ConsumerStatefulWidget {
  const TopicsReviewScreen({
    super.key,
    this.date = '',
    this.duration = '',
    this.topics = const [],
    this.transcript = '',
  });

  final String date;
  final String duration;
  final List<TopicDto> topics;
  final String transcript;

  @override
  ConsumerState<TopicsReviewScreen> createState() => _TopicsReviewScreenState();
}

class _TopicsReviewScreenState extends ConsumerState<TopicsReviewScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late List<_TopicData> _topics;
  bool _isTranscriptExpanded = false;

  String get _headerDateLine {
    final d = widget.date;
    final dur = widget.duration;
    if (d.isEmpty && dur.isEmpty) return '';
    if (dur.isEmpty) return d;
    return '$d · $dur';
  }

  @override
  void initState() {
    super.initState();
    _topics = widget.topics.indexed.map((e) {
      final (i, dto) = e;
      final (cardColor, accentColor) = _topicPalette[i % _topicPalette.length];
      return _TopicData(
        title: dto.title,
        summary: dto.summary,
        cardColor: cardColor,
        accentColor: accentColor,
        followUpHint: dto.followUpHint,
      );
    }).toList();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _confirmDeleteTopic(int index) async {
    final topic = _topics[index];
    final confirmed = await _showConfirmDialog(
      title: 'Thema entfernen?',
      body: '„${topic.title}" wird aus deinem Eintrag entfernt.',
      confirmLabel: 'Entfernen',
    );
    if (confirmed && mounted) {
      setState(() => _topics.removeAt(index));
      if (mounted && _topics.isEmpty) context.go('/');
    }
  }

  Future<void> _confirmDeleteAll() async {
    final confirmed = await _showConfirmDialog(
      title: 'Von vorne anfangen?',
      body:
          'Alle erkannten Themen und die aktuelle Aufnahme werden gelöscht. Das lässt sich nicht rückgängig machen.',
      confirmLabel: 'Alles löschen',
    );
    if (confirmed && mounted) {
      context.go('/');
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            title,
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          content: Text(body, style: tt.bodyMedium),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen'),
            ),
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

  // ── Entrance animation ───────────────────────────────────────────────────────

  Widget _animated(int index, Widget child) {
    const stagger = 0.11;
    final start = (index * stagger).clamp(0.0, 0.55);
    final end = (start + 0.45).clamp(0.0, 1.0);
    final curve = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position:
            Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(curve),
        child: child,
      ),
    );
  }

  // ── Transcript section ───────────────────────────────────────────────────────

  Widget _buildTranscriptSection(BuildContext context) {
    if (widget.transcript.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final entry = _TranscriptEntry(timestamp: DateTime.now(), text: widget.transcript);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () =>
              setState(() => _isTranscriptExpanded = !_isTranscriptExpanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.mic_none_rounded, size: 15, color: cs.outline),
                const SizedBox(width: 6),
                Text('Originaltext',
                    style: tt.labelMedium?.copyWith(color: cs.onSurface)),
                const SizedBox(width: 8),
                Text('1 Aufnahme',
                    style: tt.labelSmall?.copyWith(color: cs.outline)),
                const Spacer(),
                AnimatedRotation(
                  turns: _isTranscriptExpanded ? 0.5 : 0.0,
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
          child: _isTranscriptExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 10),
                  child: _TranscriptBubble(entry: entry),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Column: nav bar in flow + scrollable content ───────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Nav bar — in layout flow, never overlaps scroll content
                SizedBox(
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        left: 4,
                        child: IconButton(
                          onPressed: () => _topics.isEmpty
                              ? context.go('/')
                              : context.pop(),
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 20,
                            color: cs.onSurface,
                          ),
                          tooltip: 'Zurück',
                        ),
                      ),
                      if (_headerDateLine.isNotEmpty)
                        Text(
                          _headerDateLine,
                          style: tt.bodyMedium?.copyWith(color: cs.outline),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 116),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  // Header
                  _animated(
                    0,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _topics.isEmpty
                              ? 'Keine Themen mehr.\nMöchtest du von vorne anfangen?'
                              : '${_topics.length} ${_topics.length == 1 ? 'Thema' : 'Themen'} erkannt.\nMöchtest du etwas vertiefen?',
                          style: tt.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),

                  // Transcript section
                  _buildTranscriptSection(context),
                  const SizedBox(height: 20),

                  // Topic cards
                  for (int i = 0; i < _topics.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _animated(
                        i + 1,
                        _TopicCard(
                          topic: _topics[i],
                          onExtend: () => context.go(
                            '/',
                            extra: ExtendingTopic(
                              topicTitle: _topics[i].title,
                              followUpHint: _topics[i].followUpHint,
                            ),
                          ),
                          onDelete: () => _confirmDeleteTopic(i),
                        ),
                      ),
                    ),

                  const SizedBox(height: 4),

                  // Add topic button
                  _animated(
                    _topics.length + 1,
                    _AddTopicButton(
                      onTap: () => context.go('/', extra: const AddingTopic()),
                    ),
                  ),

                  // ── Destructive zone — visually separated ──────────────────
                  const SizedBox(height: 28),
                  Divider(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                    thickness: 1,
                  ),
                  const SizedBox(height: 4),
                  _animated(
                    _topics.length + 2,
                    Center(
                      child: TextButton.icon(
                        onPressed: _confirmDeleteAll,
                        icon: Icon(
                          Icons.restart_alt_rounded,
                          size: 18,
                          color: cs.error,
                        ),
                        label: Text(
                          'Von vorne anfangen',
                          style: tt.bodyMedium?.copyWith(color: cs.error),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: cs.error,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
                ),
              ],
            ),

            // ── Sticky bottom CTA ──────────────────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(
                    top: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: FilledButton(
                  onPressed:
                      _topics.isNotEmpty ? () => context.push('/entry/today') : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF3730A3),
                    disabledBackgroundColor:
                        const Color(0xFF3730A3).withValues(alpha: 0.38),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle:
                        tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Eintrag erstellen'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Topic card ─────────────────────────────────────────────────────────────────

class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.topic,
    required this.onExtend,
    required this.onDelete,
  });

  final _TopicData topic;
  final VoidCallback onExtend;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final titleColor = Color.lerp(topic.accentColor, Colors.black, 0.25)!;
    final deleteColor = titleColor.withValues(alpha: 0.4);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: topic.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row with delete button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  topic.title,
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
              ),
              // ×  button — padded for 44pt touch target
              GestureDetector(
                onTap: onDelete,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 8),
                  child: Icon(Icons.close_rounded, size: 18, color: deleteColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            topic.summary,
            style: tt.bodyMedium?.copyWith(color: topic.accentColor),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onExtend,
            style: OutlinedButton.styleFrom(
              foregroundColor: topic.accentColor,
              side: BorderSide(color: topic.accentColor, width: 1.5),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              textStyle: tt.labelLarge,
            ),
            child: const Text('Ergänzen'),
          ),
        ],
      ),
    );
  }
}

// ── Transcript bubble ──────────────────────────────────────────────────────────

class _TranscriptBubble extends StatelessWidget {
  const _TranscriptBubble({required this.entry});
  final _TranscriptEntry entry;

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
        // Timestamp row
        Row(
          children: [
            Icon(Icons.mic_rounded, size: 12, color: cs.outline),
            const SizedBox(width: 4),
            Text(
              _formatTime(entry.timestamp),
              style: tt.labelSmall?.copyWith(color: cs.outline),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Chat bubble — flat top-left corner signals "first in thread" origin
        Container(
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
          child: Text(
            entry.text,
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurface,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Add topic button ───────────────────────────────────────────────────────────

class _AddTopicButton extends StatelessWidget {
  const _AddTopicButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: cs.outline.withValues(alpha: 0.45),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 20, color: cs.outline),
              const SizedBox(width: 8),
              Text(
                'Neues Thema hinzufügen',
                style: tt.bodyLarge?.copyWith(color: cs.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dashed border painter ──────────────────────────────────────────────────────

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});
  final Color color;

  static const double _radius = 16;
  static const double _dash = 8;
  static const double _gap = 5;
  static const double _stroke = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _stroke
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
          _stroke / 2, _stroke / 2, size.width - _stroke, size.height - _stroke),
      const Radius.circular(_radius),
    );

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(
            metric.extractPath(d, (d + _dash).clamp(0.0, metric.length)),
            paint);
        d += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}
