import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slide = Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeIn);
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  void _onTap(int index) {
    HapticFeedback.selectionClick();
    widget.shell.goBranch(
      index,
      initialLocation: index == widget.shell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: _NavBar(
            currentIndex: widget.shell.currentIndex,
            onTap: _onTap,
          ),
        ),
      ),
    );
  }
}

// ── Bottom navigation bar ─────────────────────────────────────────────────────

class _NavBar extends StatelessWidget {
  const _NavBar({required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Row(
        children: [
          _NavItem(
            icon: Icons.mic_none_rounded,
            label: 'Heute',
            selected: currentIndex == 0,
            onTap: () => onTap(0),
          ),
          _NavItem(
            iconBuilder: (color, size) => _DiaryBookIcon(color: color, size: size),
            label: 'Tagebuch',
            selected: currentIndex == 1,
            onTap: () => onTap(1),
          ),
          _NavItem(
            icon: Icons.bar_chart_rounded,
            label: 'Analyse',
            selected: currentIndex == 2,
            onTap: () => onTap(2),
          ),
        ],
      ),
    );
  }
}

// ── Single nav item ───────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.iconBuilder,
  }) : assert(icon != null || iconBuilder != null);

  final IconData? icon;
  final Widget Function(Color color, double size)? iconBuilder;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(
            begin: selected ? cs.primary : cs.outline,
            end: selected ? cs.primary : cs.outline,
          ),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          builder: (context, color, _) {
            final c = color ?? (selected ? cs.primary : cs.outline);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: selected ? 1.12 : 1.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: iconBuilder != null
                      ? iconBuilder!(c, 24)
                      : Icon(icon, size: 24, color: c),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  style: (tt.labelSmall ?? const TextStyle()).copyWith(
                    color: c,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  child: Text(label),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Diary book icon ───────────────────────────────────────────────────────────

class _DiaryBookIcon extends StatelessWidget {
  const _DiaryBookIcon({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _DiaryBookPainter(color: color),
    );
  }
}

class _DiaryBookPainter extends CustomPainter {
  const _DiaryBookPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Book geometry
    const bookTopF = 0.20;
    const bookBottomF = 0.92;
    const spineF = 0.50;
    const leftEdgeF = 0.05;
    const rightEdgeF = 0.95;

    final bookTop = h * bookTopF;
    final bookBottom = h * bookBottomF;
    final spine = w * spineF;
    final leftEdge = w * leftEdgeF;
    final rightEdge = w * rightEdgeF;

    // ── Stroke weight ──────────────────────────────────────────────────────
    final sw = (w * 0.083).clamp(1.5, 2.5);

    // ── Left page ──────────────────────────────────────────────────────────
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw;

    final leftPage = Path()
      ..moveTo(spine, bookTop)
      ..lineTo(leftEdge, bookTop)
      ..lineTo(leftEdge, bookBottom)
      ..lineTo(spine, bookBottom);
    canvas.drawPath(leftPage, paint);

    // ── Right page ─────────────────────────────────────────────────────────
    final rightPage = Path()
      ..moveTo(spine, bookTop)
      ..lineTo(rightEdge, bookTop)
      ..lineTo(rightEdge, bookBottom)
      ..lineTo(spine, bookBottom);
    canvas.drawPath(rightPage, paint);

    // ── Spine line ─────────────────────────────────────────────────────────
    canvas.drawLine(Offset(spine, bookTop), Offset(spine, bookBottom), paint);

    // ── Bookmark ribbon (left page, filled) ────────────────────────────────
    paint.style = PaintingStyle.fill;

    final bmLeft = w * 0.19;
    final bmRight = w * 0.35;
    final bmMid = (bmLeft + bmRight) / 2;
    final bmTop = 0.0;
    final bmBottom = h * 0.42;
    final bmNotch = h * 0.08; // depth of the V notch at bottom

    final bookmarkPath = Path()
      ..moveTo(bmLeft, bmTop)
      ..lineTo(bmRight, bmTop)
      ..lineTo(bmRight, bmBottom)
      ..lineTo(bmMid, bmBottom - bmNotch)
      ..lineTo(bmLeft, bmBottom)
      ..close();
    canvas.drawPath(bookmarkPath, paint);

    // ── Text lines on left page ────────────────────────────────────────────
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw * 0.65;

    final lineLeft = w * 0.14;
    final lineRight = w * 0.44;
    canvas.drawLine(
        Offset(lineLeft, h * 0.55), Offset(lineRight, h * 0.55), paint);
    canvas.drawLine(
        Offset(lineLeft, h * 0.66), Offset(lineRight, h * 0.66), paint);
    canvas.drawLine(
        Offset(lineLeft, h * 0.77), Offset(w * 0.38, h * 0.77), paint);
  }

  @override
  bool shouldRepaint(_DiaryBookPainter old) => old.color != color;
}
