import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The signature surface: a near-transparent white fill over a blurred copy of
/// whatever sits behind it, with a hairline rim to catch the light.
///
/// Every card, panel and list row in the app is one of these. The [ClipRRect]
/// is what makes the blur usable — a [BackdropFilter] with no clip blurs the
/// whole layer, not just the card's footprint.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = AppRadii.card,
    this.blurSigma = 20,
    this.onTap,
    this.borderColor,
    this.fill,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double blurSigma;

  /// When set, the whole card becomes tappable with an on-theme ripple.
  final VoidCallback? onTap;

  /// Overrides the rim — used to tint a card by status or mark a selection.
  final Color? borderColor;

  /// Overrides the fill, for the rare card that must read as selected.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill ?? AppColors.glassFill,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? AppColors.glassBorder, width: 1),
      ),
      child: child,
    );

    if (onTap != null) {
      content = Stack(
        children: [
          content,
          // The ripple rides above the fill rather than under it: painting the
          // splash onto the decorated container would hide it behind the fill.
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: radius,
                onTap: onTap,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: content,
      ),
    );
  }
}
