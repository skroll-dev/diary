import 'dart:async';
import 'package:flutter/material.dart';

/// Displays live speech-to-text output during recording.
///
/// Shows [confirmedText] (finalized segments, muted) and [interimText]
/// (current partial, italic) in a scrollable sliding-window container.
/// Collapsed by default (~80 dp, 3 lines); tap to expand to ~180 dp.
/// Auto-scrolls to the bottom as new text arrives.
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
  bool _expanded = false;
  final _scrollController = ScrollController();
  bool _cursorVisible = true;
  Timer? _cursorTimer;

  static const double _collapsedHeight = 80.0;
  static const double _expandedHeight = 180.0;

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
  void didUpdateWidget(covariant LiveTranscriptDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients &&
          _scrollController.position.hasContentDimensions) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _cursorTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _hasContent =>
      widget.confirmedText.isNotEmpty || widget.interimText.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: _hasContent ? _buildContent(context) : const SizedBox.shrink(),
    );
  }

  Widget _buildContent(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final textWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: RichText(
        textAlign: TextAlign.center,
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
            TextSpan(
              text: _cursorVisible ? ' │' : '  ',
              style: tt.bodyMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        height: _expanded ? _expandedHeight : _collapsedHeight,
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scrollController,
              physics: _expanded
                  ? const BouncingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: textWidget,
            ),
            // Top fade hints at text above when collapsed
            if (!_expanded)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 24,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          cs.surface,
                          cs.surface.withValues(alpha: 0),
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
}
