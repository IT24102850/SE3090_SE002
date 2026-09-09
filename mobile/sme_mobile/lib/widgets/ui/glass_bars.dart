import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// The fixed action bar at the bottom of a detail screen: blurred glass, a
/// hairline along the top, and safe-area padding so the buttons clear the home
/// indicator.
class GlassFooterBar extends StatelessWidget {
  const GlassFooterBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.chromeFill,
            border: Border(top: BorderSide(color: AppColors.hairline, width: 1)),
          ),
          child: SafeArea(top: false, child: Padding(padding: padding, child: child)),
        ),
      ),
    );
  }
}

/// One destination in a [GlassNavBar].
class GlassNavItem {
  const GlassNavItem({required this.icon, required this.label, this.activeIcon});

  final IconData icon;
  final IconData? activeIcon;
  final String label;
}

/// A floating glass pill instead of a Material bottom bar: inset from the
/// screen edges, blurred, with the active item in cyan under a soft glow.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  final List<GlassNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: margin,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              height: 68,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(color: AppColors.glassBorder, width: 1),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _NavCell(
                        item: items[i],
                        selected: i == currentIndex,
                        onTap: () => onTap(i),
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

class _NavCell extends StatelessWidget {
  const _NavCell({required this.item, required this.selected, required this.onTap});

  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.cyan : AppColors.textMuted;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // A short scale-up on selection, so switching tabs reads as a
            // response rather than an instant repaint.
            AnimatedScale(
              scale: selected ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: Container(
                decoration: selected
                    ? const BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: AppColors.buttonGlow, blurRadius: 16, spreadRadius: 1),
                        ],
                      )
                    : null,
                child: Icon(selected ? (item.activeIcon ?? item.icon) : item.icon,
                    size: 22, color: color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: AppTextStyles.caption.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
