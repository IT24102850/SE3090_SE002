import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// The app bar for every screen: no solid fill, just a blurred pane over the
/// background with a hairline along the bottom.
///
/// Built on a real [AppBar] rather than a bespoke [Row] so the automatic
/// leading (back arrow, drawer button), `actions`, and scaffold integration all
/// keep working — only the paint changes. Screens using it should set
/// `extendBodyBehindAppBar: true` (which [AppBackgroundScaffold] already does)
/// so the blur has something to blur.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.bottom,
    this.blurSigma = 18,
  });

  final String? title;

  /// Use instead of [title] when the bar needs more than a string.
  final Widget? titleWidget;

  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  /// A [TabBar], typically. Its height is added to [preferredSize].
  final PreferredSizeWidget? bottom;

  final double blurSigma;

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + 1 + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading,
      iconTheme: const IconThemeData(color: AppColors.iconPrimary),
      actionsIconTheme: const IconThemeData(color: AppColors.iconPrimary),
      title: titleWidget ?? (title == null ? null : Text(title!, style: AppTextStyles.title)),
      actions: actions,
      bottom: bottom,
      // ClipRect bounds the blur to the bar; without it the filter samples the
      // entire layer and the whole screen goes soft.
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.chromeFill,
              border: Border(bottom: BorderSide(color: AppColors.hairline, width: 1)),
            ),
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}
