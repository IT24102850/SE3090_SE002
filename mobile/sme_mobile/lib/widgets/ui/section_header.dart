import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// A spaced-caps label that groups the content under it — the treatment the
/// auth screens use for "EMAIL", applied to every section on every screen.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.label, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: 10),
  });

  /// Rendered uppercase — passing "Details" and "DETAILS" look the same.
  final String label;

  /// Optional action on the right of the header ("See all", a count…).
  final Widget? trailing;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: AppTextStyles.label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null)
            DefaultTextStyle.merge(
              style: AppTextStyles.caption.copyWith(color: AppColors.cyan),
              child: trailing!,
            ),
        ],
      ),
    );
  }
}
