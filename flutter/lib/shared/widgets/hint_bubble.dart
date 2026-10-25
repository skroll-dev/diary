import 'package:flutter/material.dart';

import '../extensions/localization_extensions.dart';

/// Shows a small one-time hint bubble below [child] while [visible] is true.
///
/// The bubble lives in the overlay, so it floats over whatever follows the
/// anchor instead of pushing it down, and follows the anchor while scrolling.
/// Any tap on the screen (the ✕ included) calls [onDismiss]; the tap still
/// reaches whatever is underneath, so tapping the anchored control both
/// closes the hint and triggers the control.
///
/// Whether a hint was already seen is the caller's business — see
/// `AppPreferences.isHintSeen`/`markHintSeen`.
class HintAnchor extends StatefulWidget {
  const HintAnchor({
    super.key,
    required this.visible,
    required this.message,
    required this.onDismiss,
    required this.child,
    this.arrowOffset = 24,
    this.width = 280,
  });

  final bool visible;
  final String message;
  final VoidCallback onDismiss;
  final Widget child;

  /// Horizontal distance from the anchor's left edge to the arrow's center.
  final double arrowOffset;
  final double width;

  @override
  State<HintAnchor> createState() => _HintAnchorState();
}

class _HintAnchorState extends State<HintAnchor> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  static const _arrowSize = 8.0;
  static const _bubbleInset = 6.0; // bubble starts this far left of the anchor

  @override
  void initState() {
    super.initState();
    if (widget.visible) _controller.show();
  }

  @override
  void didUpdateWidget(HintAnchor old) {
    super.didUpdateWidget(old);
    if (widget.visible == old.visible) return;
    // OverlayPortalController must not be toggled mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.visible ? _controller.show() : _controller.hide();
    });
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: _buildOverlay,
        child: widget.child,
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final background = cs.inverseSurface;

    return Stack(
      children: [
        // Translucent catch-all: closes the hint on any tap without
        // swallowing the tap itself.
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => widget.onDismiss(),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          offset: const Offset(-_bubbleInset, 6),
          child: Align(
            alignment: Alignment.topLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * -6),
                  child: child,
                ),
              ),
              child: SizedBox(
                width: widget.width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        left: widget.arrowOffset + _bubbleInset - _arrowSize,
                      ),
                      child: CustomPaint(
                        size: const Size(_arrowSize * 2, _arrowSize),
                        painter: _ArrowPainter(background),
                      ),
                    ),
                    Material(
                      color: background,
                      elevation: 6,
                      shadowColor: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  widget.message,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onInverseSurface,
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: context.l10n.hintDismiss,
                              onPressed: widget.onDismiss,
                              visualDensity: VisualDensity.compact,
                              iconSize: 16,
                              color: cs.onInverseSurface.withValues(alpha: 0.8),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}
