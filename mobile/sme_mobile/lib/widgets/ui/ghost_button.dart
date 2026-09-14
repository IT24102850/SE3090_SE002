import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// The secondary action: an outlined cyan control with no fill until pressed.
/// Sits next to (or under) a [NeonButton] without competing with it.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 50,
    this.expand = true,
    this.color = AppColors.cyan,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final bool expand;

  /// Defaults to cyan; pass [AppColors.danger] for a destructive secondary
  /// action, so the outline carries the warning instead of a filled button.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(AppRadii.control);
    final tint = enabled ? color : AppColors.textMuted;

    return SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          splashColor: tint.withValues(alpha: 0.10),
          highlightColor: tint.withValues(alpha: 0.06),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: tint.withValues(alpha: 0.5), width: 1.5),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: tint),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: AppTextStyles.button.copyWith(fontSize: 15, color: tint),
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
