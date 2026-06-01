import 'package:flutter/material.dart';

/// Shows a keyboard-safe dialog for multi-line text input.
///
/// Uses [showDialog] instead of a bottom sheet — dialogs center in the screen
/// and are naturally above the keyboard on all platforms, including iOS Safari
/// where bottom-sheet viewInsets are unreliable.
///
/// Returns the entered text, or null if cancelled.
Future<String?> showTranscriptInputSheet(
  BuildContext context, {
  String title = 'Text eingeben',
  String hint = 'Hier tippen …',
  String initialValue = '',
  String confirmLabel = 'Verarbeiten',
}) async {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      // Anchor to the top of the screen so the keyboard (which opens from the
      // bottom) can never cover the dialog — no viewInsets needed.
      final topPadding = MediaQuery.of(ctx).padding.top + 16;
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, topPadding, 20, 0),
          child: _TranscriptInputDialog(
            title: title,
            hint: hint,
            initialValue: initialValue,
            confirmLabel: confirmLabel,
          ),
        ),
      );
    },
  );
}

class _TranscriptInputDialog extends StatefulWidget {
  const _TranscriptInputDialog({
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
  State<_TranscriptInputDialog> createState() => _TranscriptInputDialogState();
}

class _TranscriptInputDialogState extends State<_TranscriptInputDialog> {
  late final TextEditingController _controller;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      borderRadius: BorderRadius.circular(20),
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Text(
              widget.title,
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            // Scrollable text area — capped at 180 dp so total dialog height
            // stays under the ~420 dp available above a standard iOS keyboard.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 120, maxHeight: 180),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: TextField(
                  controller: _controller,
                  scrollController: _scrollController,
                  autofocus: true,
                  maxLines: null,
                  minLines: 6,
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
