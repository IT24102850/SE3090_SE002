import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// The primary call to action: a full-width gradient bar with a cyan glow
/// pooling underneath it.
///
/// The gradient lives on a [Container] and the ripple on a transparent
/// [Material] stacked above it — [ElevatedButton] can't carry a gradient, and
/// painting the ink splash straight onto the gradient container would put the
/// splash *behind* it.
class NeonButton extends StatelessWidget {
  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.height = 54,
    this.icon,
    this.expand = true,
  });

  final String label;

  /// Null disables the button (the gradient dims and the glow drops away).
  final VoidCallback? onPressed;

  /// While true the label is swapped for a spinner and taps are ignored, so a
  /// double-tap can't fire the action twice.
  final bool isLoading;

  final double height;
  final IconData? icon;

  /// Full-width by default; set false for a button sized to its label.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final radius = BorderRadius.circular(AppRadii.control);

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Container(
        height: height,
        width: expand ? double.infinity : null,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: AppColors.buttonGradient,
          // One glow, not two: a second offset shadow in the opposite hue
          // stacked up into a visible slab under the button instead of reading
          // as light. The negative spread pulls the shadow inside the button's
          // own footprint for the same reason — without it the offset leaves a
          // hard-edged lip poking out below.
          boxShadow: enabled
              ? const [
                  BoxShadow(
                    color: AppColors.buttonGlow,
                    blurRadius: 28,
                    spreadRadius: -6,
                    offset: Offset(0, 10),
                  ),
                ]
              : null,
        ),
        // Dim the whole bar rather than recolouring it, so a disabled button
        // still reads as the same control.
        foregroundDecoration: enabled
            ? null
            : BoxDecoration(
                borderRadius: radius,
                color: AppColors.bgTop.withValues(alpha: 0.55),
              ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: enabled ? onPressed : null,
            splashColor: Colors.white.withValues(alpha: 0.18),
            highlightColor: Colors.white.withValues(alpha: 0.08),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 20, color: AppColors.textPrimary),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            style: AppTextStyles.button,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
