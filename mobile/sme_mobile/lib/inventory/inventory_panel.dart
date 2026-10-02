import 'package:flutter/material.dart';

/// A gradient surface with finite entrance and tactile press animations.
class InventoryPanel extends StatefulWidget {
  const InventoryPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 24,
    this.onTap,
    this.borderColor,
    this.fill,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? fill;

  @override
  State<InventoryPanel> createState() => _InventoryPanelState();
}

class _InventoryPanelState extends State<InventoryPanel> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    final surface = widget.fill ?? const Color(0xFF172F3B);
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reducedMotion ? 1 : 0, end: 1),
      duration: Duration(milliseconds: reducedMotion ? 0 : 360),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
              offset: Offset(0, 10 * (1 - value)), child: child)),
      child: AnimatedScale(
          scale: _pressed ? .985 : 1,
          duration: Duration(milliseconds: reducedMotion ? 0 : 140),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(surface, const Color(0xFFC4FCE4), .07)!,
                  surface,
                  Color.lerp(surface, const Color(0xFF101C2B), .45)!,
                ],
                stops: const [0, .35, 1],
              ),
              borderRadius: radius,
              border: Border.all(
                color: widget.borderColor ?? const Color(0xFF36555E),
                width: 1,
              ),
              boxShadow: [
                const BoxShadow(
                  color: Color(0x30000000),
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
                if (widget.borderColor != null)
                  BoxShadow(
                    color: widget.borderColor!.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: radius,
              child: InkWell(
                onTap: widget.onTap,
                onHighlightChanged: widget.onTap == null
                    ? null
                    : (value) => setState(() => _pressed = value),
                splashColor: const Color(0xFF00E5FF).withValues(alpha: .12),
                highlightColor: const Color(0xFF00E5FF).withValues(alpha: .04),
                borderRadius: radius,
                child: Padding(padding: widget.padding, child: widget.child),
              ),
            ),
          )),
    );
  }
}
