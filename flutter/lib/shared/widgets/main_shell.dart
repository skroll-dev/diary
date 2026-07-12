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
            icon: Icons.history_rounded,
            label: 'Verlauf',
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
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
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
                  child: Icon(icon, size: 24, color: c),
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
