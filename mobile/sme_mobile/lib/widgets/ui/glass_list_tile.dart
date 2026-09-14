import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'glass_card.dart';

/// A list row as a glass card: a circular icon well on the left, title and
/// subtitle in the middle, a chevron (or custom trailing) on the right.
///
/// Replaces [ListTile] everywhere in the app — the Material default paints its
/// own text colours and splash, both of which fight this theme.
class GlassListTile extends StatelessWidget {
  const GlassListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.leading,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.borderColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  });

  final String title;
  final String? subtitle;

  /// Rendered inside a small dark circle. Ignored when [leading] is given.
  final IconData? icon;
  final Color? iconColor;

  /// Full override of the leading slot — an avatar, a status dot, a thumbnail.
  final Widget? leading;

  /// Defaults to a chevron when [onTap] is set and [showChevron] is true.
  final Widget? trailing;

  final VoidCallback? onTap;
  final bool showChevron;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final effectiveTrailing = trailing ??
        (onTap != null && showChevron
            ? const Icon(Icons.chevron_right_rounded, color: AppColors.chevron, size: 22)
            : null);

    return GlassCard(
      onTap: onTap,
      padding: padding,
      borderRadius: AppRadii.row,
      borderColor: borderColor,
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (icon != null)
            IconWell(icon: icon!, color: iconColor),
          if (leading != null || icon != null) const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: AppTextStyles.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (effectiveTrailing != null) ...[
            const SizedBox(width: 10),
            effectiveTrailing,
          ],
        ],
      ),
    );
  }
}

/// The small circular container a row icon sits in. Public because detail
/// screens reuse it outside of list rows.
class IconWell extends StatelessWidget {
  const IconWell({super.key, required this.icon, this.color, this.size = 40});

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.iconWell,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.hairline),
      ),
      child: Icon(icon, size: size * 0.5, color: color ?? AppColors.iconPrimary),
    );
  }
}
