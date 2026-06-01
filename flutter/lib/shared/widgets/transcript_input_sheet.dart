import 'dart:math' show min;
import 'package:flutter/material.dart';

/// Shows a keyboard-aware bottom sheet for multi-line text input.
/// Returns the entered text, or null if cancelled.
Future<String?> showTranscriptInputSheet(
  BuildContext context, {
  String title = 'Text eingeben',
  String hint = 'Hier tippen …',
  String initialValue = '',
  String confirmLabel = 'Verarbeiten',
}) async {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _TranscriptInputSheet(
      title: title,
      hint: hint,
      initialValue: initialValue,
      confirmLabel: confirmLabel,
    ),
  );
}

class _TranscriptInputSheet extends StatefulWidget {
  const _TranscriptInputSheet({
    required this.title,
    required this.hint,
    required this.initialValue,
    required this.confirmLabel,
  });

  final String title;
  final String hint;
  final String initialValue;
  final String confirmLabel;

  @override
  State<_TranscriptInputSheet> createState() => _TranscriptInputSheetState();
}

class _TranscriptInputSheetState extends State<_TranscriptInputSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);
    final keyboardHeight = mq.viewInsets.bottom;
    // Clamp sheet height: never taller than what fits above the keyboard,
    // never shorter than ~280 dp (enough for handle + title + field + buttons).
    final availableHeight =
        mq.size.height - keyboardHeight - mq.padding.top - 48;
    final sheetHeight = min(availableHeight, 420.0);

    return Padding(
      // Lifts the sheet exactly above the keyboard — no double-compensation.
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Container(
        height: sheetHeight,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Title
            Text(
              widget.title,
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            // Text field fills all remaining space so buttons stay anchored.
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: tt.bodyMedium?.copyWith(color: cs.outline),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: cs.primary, width: 2),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
                style: tt.bodyLarge,
              ),
            ),
            const SizedBox(height: 16),
            // Actions — always visible at the bottom.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Abbrechen'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () {
                      final text = _controller.text.trim();
                      if (text.isNotEmpty) Navigator.of(context).pop(text);
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(widget.confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
