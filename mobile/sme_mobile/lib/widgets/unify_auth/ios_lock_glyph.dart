import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// An Apple-style animated padlock glyph.
///
/// Features a spring-loaded shackle that pivots open with physics-inspired
/// motion, an ambient glow halo, and responsive unlock state feedback.
class IosLockGlyph extends StatefulWidget {
  const IosLockGlyph({
    super.key,
    this.isUnlocked = false,
    this.progress,
    this.size = 28.0,
    this.onTap,
    this.showGlow = true,
  });

  /// Explicit unlock state. Overridden by [progress] if provided.
  final bool isUnlocked;

  /// Swipe-up progress from 0.0 (locked) to 1.0 (unlocked).
  final double? progress;

  final double size;
  final VoidCallback? onTap;
  final bool showGlow;

  @override
  State<IosLockGlyph> createState() => _IosLockGlyphState();
}

class _IosLockGlyphState extends State<IosLockGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _unlockAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );

    _unlockAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
      reverseCurve: Curves.easeInCubic,
    );

    if (widget.isUnlocked) {
      _animController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant IosLockGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress != null) {
      // Progress-driven: lock opens past threshold
      final target = (widget.progress! * 1.5).clamp(0.0, 1.0);
      _animController.value = target;
    } else if (widget.isUnlocked != oldWidget.isUnlocked) {
      if (widget.isUnlocked) {
        _animController.forward(from: 0.0);
      } else {
        _animController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          final t = _unlockAnimation.value;
          final isUnlockedVisual = t > 0.45;

          return SizedBox(
            width: widget.size * 1.7,
            height: widget.size * 1.7,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Ambient unlock halo
                if (widget.showGlow)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    width: widget.size * (1.2 + t * 0.45),
                    height: widget.size * (1.2 + t * 0.45),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: isUnlockedVisual
                              ? AppColors.cyan.withValues(alpha: 0.35 * (0.6 + t * 0.4))
                              : Colors.white.withValues(alpha: 0.08),
                          blurRadius: isUnlockedVisual ? 18 : 8,
                          spreadRadius: isUnlockedVisual ? 4 : 1,
                        ),
                      ],
                    ),
                  ),

                CustomPaint(
                  size: Size(widget.size, widget.size * 1.2),
                  painter: _IosLockPainter(
                    unlockProgress: t,
                    color: isUnlockedVisual ? AppColors.cyan : Colors.white,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _IosLockPainter extends CustomPainter {
  const _IosLockPainter({
    required this.unlockProgress,
    required this.color,
  });

  final double unlockProgress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final bodyPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shacklePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.17
      ..strokeCap = StrokeCap.round;

    final keyholePaint = Paint()
      ..color = AppColors.bgTop
      ..style = PaintingStyle.fill;

    // Body dimensions (lower 58% of height)
    final bodyHeight = h * 0.56;
    final bodyWidth = w * 0.88;
    final bodyLeft = (w - bodyWidth) / 2;
    final bodyTop = h - bodyHeight;
    final bodyRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(bodyLeft, bodyTop, bodyWidth, bodyHeight),
      Radius.circular(w * 0.22),
    );

    // Draw Lock Shackle with Apple-style spring unlock
    // When unlocking: lifts up and pivots to the left
    final shackleRadius = w * 0.25;
    final shackleBaseY = bodyTop + w * 0.08;
    final lift = unlockProgress * (w * 0.22);
    final pivotAngle = unlockProgress * (-math.pi * 0.16);

    canvas.save();
    // Pivot around the left anchor of the shackle
    final pivotX = w * 0.5 - shackleRadius;
    final pivotY = shackleBaseY - lift;
    canvas.translate(pivotX, pivotY);
    canvas.rotate(pivotAngle);
    canvas.translate(-pivotX, -pivotY);

    final shacklePath = Path();
    // Left leg
    shacklePath.moveTo(w * 0.5 - shackleRadius, shackleBaseY);
    shacklePath.lineTo(w * 0.5 - shackleRadius, shackleBaseY - shackleRadius * 1.05 - lift);
    // Arc over top
    shacklePath.arcToPoint(
      Offset(w * 0.5 + shackleRadius, shackleBaseY - shackleRadius * 1.05 - lift),
      radius: Radius.circular(shackleRadius),
      clockwise: true,
    );
    // Right leg
    shacklePath.lineTo(
      w * 0.5 + shackleRadius,
      shackleBaseY - (unlockProgress * w * 0.14),
    );

    canvas.drawPath(shacklePath, shacklePaint);
    canvas.restore();

    // Draw Body
    canvas.drawRRect(bodyRRect, bodyPaint);

    // Draw keyhole dot
    canvas.drawCircle(
      Offset(w * 0.5, bodyTop + bodyHeight * 0.44),
      w * 0.08,
      keyholePaint,
    );
    // Keyhole slit
    final slitRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, bodyTop + bodyHeight * 0.62),
        width: w * 0.075,
        height: bodyHeight * 0.32,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(slitRRect, keyholePaint);
  }

  @override
  bool shouldRepaint(covariant _IosLockPainter oldDelegate) {
    return oldDelegate.unlockProgress != unlockProgress ||
        oldDelegate.color != color;
  }
}
