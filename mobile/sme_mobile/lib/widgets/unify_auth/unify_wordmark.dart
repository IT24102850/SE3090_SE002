import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The "Unify" logotype, with the tittle of the "i" replaced by a glowing
/// cyan dot.
///
/// No font exposes a "dotless i" reliably, so the word is set normally and the
/// neon dot is stacked on top of the tittle — sized a shade larger than the
/// glyph's own dot so nothing white peeks out from under it. Line height is
/// pinned to 1.0 so the dot's offset can be expressed as a fraction of the
/// font size and stay correct at any [fontSize].
class UnifyWordmark extends StatelessWidget {
  const UnifyWordmark({super.key, this.fontSize = 44});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
      height: 1.0,
      letterSpacing: -0.5,
    );

    // Measured against Roboto Bold at 44pt: the tittle's centre sits 0.17em
    // below the top of the line box and a hair right of the glyph box's
    // centre. Both are expressed as fractions of [fontSize] so the dot tracks
    // the type at any size.
    final dotSize = fontSize * 0.22;
    const tittleCentreY = 0.155;
    const tittleNudgeX = 0.03;

    return Semantics(
      label: 'Unify',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Un', style: style),
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Text('i', style: style),
                Positioned(
                  top: fontSize * tittleCentreY - dotSize / 2,
                  child: Transform.translate(
                    offset: Offset(fontSize * tittleNudgeX, 0),
                    child: Container(
                      width: dotSize,
                      height: dotSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.cyan,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.cyan.withValues(alpha: 0.85),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                          BoxShadow(
                            color: AppColors.cyan.withValues(alpha: 0.35),
                            blurRadius: 26,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Text('fy', style: style),
          ],
        ),
      ),
    );
  }
}
