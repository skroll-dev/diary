import 'dart:async';
import 'package:flutter/material.dart';

/// Displays live speech-to-text output during recording.
///
/// Uses reverse scroll so the latest text is always anchored at the bottom
/// of the available space — no manual scrolling or gradient masking needed.
class LiveTranscriptDisplay extends StatefulWidget {
  const LiveTranscriptDisplay({
    super.key,
    required this.confirmedText,
    required this.interimText,
  });

  final String confirmedText;
  final String interimText;

  @override
  State<LiveTranscriptDisplay> createState() => _LiveTranscriptDisplayState();
}

class _LiveTranscriptDisplayState extends State<LiveTranscriptDisplay> {
  bool _cursorVisible = true;
  Timer? _cursorTimer;

  @override
  void initState() {
    super.initState();
    _cursorTimer = Timer.periodic(
      const Duration(milliseconds: 530),
      (_) {
        if (mounted) setState(() => _cursorVisible = !_cursorVisible);
      },
    );
  }

  @override
  void dispose() {
    _cursorTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // reverse: true anchors content at the bottom. New words appear at the
    // bottom edge and never cause a partial line at the top of the viewport.
    return SingleChildScrollView(
      reverse: true,
      padding: const EdgeInsets.only(top: 8),
      child: RichText(
        textAlign: TextAlign.left,
        text: TextSpan(
          children: [
            if (widget.confirmedText.isNotEmpty)
              TextSpan(
                text: '${widget.confirmedText} ',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.50),
                ),
              ),
            if (widget.interimText.isNotEmpty)
              TextSpan(
                text: widget.interimText,
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.85),
                  fontStyle: FontStyle.italic,
                ),
              ),
            // Cursor: always same width, opacity toggles to avoid layout shift.
            TextSpan(
              text: ' │',
              style: tt.bodyMedium?.copyWith(
                color: _cursorVisible ? cs.primary : Colors.transparent,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
