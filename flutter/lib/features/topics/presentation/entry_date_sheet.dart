import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../shared/extensions/localization_extensions.dart';
import '../../../shared/widgets/marker_style.dart';

/// Lets the user assign a fresh entry to today or any past day. Returns the
/// chosen day (date only), or null when dismissed. [entryCounts] maps ISO
/// dates (`yyyy-MM-dd`) to the number of other entries on that day; those
/// days get a dot, and choosing one shows that this entry joins them.
Future<DateTime?> showEntryDateSheet(
  BuildContext context, {
  required DateTime initialDate,
  required Map<String, int> entryCounts,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EntryDateSheet(
      initialDate: initialDate,
      entryCounts: entryCounts,
    ),
  );
}

class _EntryDateSheet extends StatefulWidget {
  const _EntryDateSheet({required this.initialDate, required this.entryCounts});

  final DateTime initialDate;
  final Map<String, int> entryCounts;

  @override
  State<_EntryDateSheet> createState() => _EntryDateSheetState();
}

class _EntryDateSheetState extends State<_EntryDateSheet> {
  static final _iso = DateFormat('yyyy-MM-dd');

  late final DateTime _today = DateUtils.dateOnly(DateTime.now());
  late DateTime _selected = DateUtils.dateOnly(widget.initialDate);
  late DateTime _month = DateTime(_selected.year, _selected.month);

  int _countFor(DateTime day) => widget.entryCounts[_iso.format(day)] ?? 0;

  bool get _isCurrentMonth =>
      _month.year == _today.year && _month.month == _today.month;

  void _select(DateTime day) => setState(() {
        _selected = day;
        _month = DateTime(day.year, day.month);
      });

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).languageCode;

    final quickDays = [
      (_today, l10n.entryDateToday),
      (_today.subtract(const Duration(days: 1)), l10n.entryDateYesterday),
      (_today.subtract(const Duration(days: 2)), l10n.entryDateDayBeforeYesterday),
    ];
    final selectedLabel = DateFormat.MMMEd(locale).format(_selected);
    final existing = _countFor(_selected);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.entryDateSheetTitle,
                style: markerSerif(
                    size: 22, height: 1.2, weight: 600, color: cs.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.entryDateSheetHint,
                style: tt.bodySmall?.copyWith(color: cs.outline),
              ),
              const SizedBox(height: 14),

              // ── Quick picks ────────────────────────────────────────────
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (day, label) in quickDays)
                    ChoiceChip(
                      label: Text(label),
                      selected: DateUtils.isSameDay(day, _selected),
                      showCheckmark: false,
                      onSelected: (_) => _select(day),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // ── Month navigation ───────────────────────────────────────
              Row(
                children: [
                  IconButton(
                    tooltip: l10n.entryDatePreviousMonth,
                    icon: const Icon(Icons.chevron_left_rounded),
                    color: cs.primary,
                    onPressed: () => _shiftMonth(-1),
                  ),
                  Expanded(
                    child: Text(
                      DateFormat.yMMMM(locale).format(_month),
                      textAlign: TextAlign.center,
                      style: markerSerif(
                          size: 18, weight: 600, color: cs.onSurface),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.entryDateNextMonth,
                    icon: const Icon(Icons.chevron_right_rounded),
                    color: cs.primary,
                    // Entries can't be dated into the future.
                    onPressed: _isCurrentMonth ? null : () => _shiftMonth(1),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _MonthGrid(
                month: _month,
                today: _today,
                selected: _selected,
                hasEntry: (day) => _countFor(day) > 0,
                onSelect: _select,
              ),
              const SizedBox(height: 10),

              // ── Existing entries on the chosen day ─────────────────────
              if (existing > 0) ...[
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 18, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.entryDateExistingHint(existing, selectedLabel),
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onPrimaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: cs.primary, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.entryDateLegendHasEntry,
                    style: tt.labelSmall?.copyWith(color: cs.outline),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () => Navigator.of(context).pop(_selected),
                child: Text(l10n.entryDateConfirm(selectedLabel)),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.selected,
    required this.hasEntry,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime today;
  final DateTime selected;
  final bool Function(DateTime day) hasEntry;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final locale = Localizations.localeOf(context).languageCode;

    // Monday-first, matching the DACH convention the app is built for.
    final leading = DateTime(month.year, month.month, 1).weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var d = 1; d <= daysInMonth; d++) DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    // 2024-01-01 is a Monday — any Monday-anchored week works for labels.
    final weekdays = [
      for (var i = 0; i < 7; i++)
        DateFormat.E(locale)
            .format(DateTime(2024, 1, 1 + i))
            .replaceAll('.', '')
            .toUpperCase(),
    ];

    return Column(
      children: [
        Row(
          children: [
            for (final w in weekdays)
              Expanded(
                child: Text(
                  w,
                  textAlign: TextAlign.center,
                  style: tt.labelSmall?.copyWith(
                    color: cs.outline,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < cells.length ~/ 7; row++)
          Row(
            children: [
              for (final day in cells.sublist(row * 7, row * 7 + 7))
                Expanded(
                  child: day == null
                      ? const SizedBox(height: 44)
                      : _DayCell(
                          day: day,
                          isToday: DateUtils.isSameDay(day, today),
                          isSelected: DateUtils.isSameDay(day, selected),
                          isFuture: day.isAfter(today),
                          hasEntry: hasEntry(day),
                          onTap: () => onSelect(day),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.isFuture,
    required this.hasEntry,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final bool isFuture;
  final bool hasEntry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).languageCode;

    final Color textColor;
    if (isSelected) {
      textColor = cs.onPrimary;
    } else if (isFuture) {
      textColor = cs.outlineVariant;
    } else if (isToday) {
      textColor = cs.primary;
    } else {
      textColor = cs.onSurface;
    }

    return Semantics(
      button: !isFuture,
      selected: isSelected,
      label: DateFormat.yMMMMEEEEd(locale).format(day),
      excludeSemantics: true,
      child: InkResponse(
        onTap: isFuture ? null : onTap,
        radius: 22,
        child: SizedBox(
          height: 44,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? cs.primary : null,
                  border: isToday && !isSelected
                      ? Border.all(color: cs.primary, width: 1.5)
                      : null,
                ),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor,
                    fontWeight: isSelected || isToday
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasEntry ? cs.primary : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
