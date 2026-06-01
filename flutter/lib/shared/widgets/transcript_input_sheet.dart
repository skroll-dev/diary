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
    // AnimatedPadding smoothly lifts the sheet as the keyboard value arrives.
    // The sheet itself is mainAxisSize.min with a capped text field height,
    // so it is always compact enough to fit above any keyboard without
    // needing to know the keyboard height before the first frame.
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            // Text field — capped at 5 lines so the sheet stays compact.
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 4,
              maxLines: 5,
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
            const SizedBox(height: 16),
            // Actions
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
