import 'package:flutter/material.dart';

/// A quiet, solid surface for inventory screens. The restrained border and
/// shadow keep dense operational data readable over the app background.
class InventoryPanel extends StatelessWidget {
  const InventoryPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 18,
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
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final surface = fill ?? const Color(0xF5121B2B);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(surface, Colors.white, .045)!,
            Color.lerp(surface, Colors.black, .12)!,
          ],
        ),
        borderRadius: radius,
        border: Border.all(
          color: borderColor ?? const Color(0xFF2C3C56),
          width: 1,
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0x40000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
          if (borderColor != null)
            BoxShadow(
              color: borderColor!.withValues(alpha: 0.16),
              blurRadius: 14,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
