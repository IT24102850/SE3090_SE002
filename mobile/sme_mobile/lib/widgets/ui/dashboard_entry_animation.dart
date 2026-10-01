import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DashboardEntryAnimation
// ─────────────────────────────────────────────────────────────────────────────
//
// Wraps any child (the DashboardScreen) and plays a one-shot cinematic unlock
// reveal on first build:
//
//   Phase 0 – 150 ms  : Deep-space black veil covers the screen.
//   Phase 1 – 380 ms  : Shockwave ring bursts from centre; neon bloom
//                        (cyan + magenta) blossoms and immediately starts
//                        fading.  Spark particles shoot radially outward.
//   Phase 2 – 700 ms  : Bloom, ring and sparks all fully dissolve.  The child
//                        (dashboard) fades in from below with a springy
//                        scale-up.
//   Phase 3 – done    : Overlay widget is removed from the tree, interaction
//                        reaches the dashboard unimpeded.
//
// The whole effect completes in ~1 350 ms.
// ─────────────────────────────────────────────────────────────────────────────

class DashboardEntryAnimation extends StatefulWidget {
  const DashboardEntryAnimation({super.key, required this.child});

  final Widget child;

  @override
  State<DashboardEntryAnimation> createState() =>
      _DashboardEntryAnimationState();
}

class _DashboardEntryAnimationState extends State<DashboardEntryAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // ── ring ──────────────────────────────────────────────────────────────────
  late final Animation<double> _ringRadius;   // 0 → 1 (fraction of screen)
  late final Animation<double> _ringOpacity;  // 1 → 0

  // ── bloom ─────────────────────────────────────────────────────────────────
  late final Animation<double> _bloomScale;
  late final Animation<double> _bloomOpacity;

  // ── sparks ────────────────────────────────────────────────────────────────
  late final Animation<double> _sparkProgress; // 0 → 1 travel distance
  late final Animation<double> _sparkOpacity;

  // ── veil / content ────────────────────────────────────────────────────────
  late final Animation<double> _contentOpacity;
  late final Animation<double> _contentScale;

  bool _overlayDone = false;

  static const _sparks = 22;
  static final List<_Spark> _sparkDefs = _buildSparks();

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );

    // Ring: expands 0→1.4× screen diagonal in first 45% of timeline,
    // opacity: full → 0 across same window.
    _ringRadius = Tween<double>(begin: 0.0, end: 1.4).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.05, 0.50, curve: Curves.easeOutCubic),
      ),
    );
    _ringOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.20, 0.55, curve: Curves.easeInCubic),
      ),
    );

    // Bloom: scale from 0 to 1.6, opacity peaks at 0.85 then drops to 0.
    _bloomScale = Tween<double>(begin: 0.0, end: 1.6).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.42, curve: Curves.easeOutCubic),
      ),
    );
    _bloomOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 0.85),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.85, end: 0.0),
        weight: 85,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.60),
      ),
    );

    // Sparks: travel 0→1 (fractions of screen) between 5% and 55%, then fade.
    _sparkProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.05, 0.55, curve: Curves.easeOutCubic),
      ),
    );
    _sparkOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.35, 0.62, curve: Curves.easeIn),
      ),
    );

    // Content (dashboard): fade+scale in from 55% → 100%.
    _contentOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.50, 0.85, curve: Curves.easeOut),
      ),
    );
    _contentScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.50, 0.95, curve: Curves.elasticOut),
      ),
    );

    _ctrl.forward().whenComplete(() {
      if (mounted) setState(() => _overlayDone = true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static List<_Spark> _buildSparks() {
    final rng = math.Random(0xC0FFEE);
    return List.generate(_sparks, (i) {
      final angle = (i / _sparks) * math.pi * 2 + rng.nextDouble() * 0.4;
      final speed = 0.22 + rng.nextDouble() * 0.20; // fraction of screen
      final size = 2.0 + rng.nextDouble() * 3.0;
      final color = rng.nextBool() ? AppColors.cyan : AppColors.magenta;
      return _Spark(angle: angle, speed: speed, size: size, color: color);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Once animation is done, pass through with zero overhead.
    if (_overlayDone) return widget.child;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // ── Content (dashboard) underneath everything ─────────────────
            FadeTransition(
              opacity: _contentOpacity,
              child: ScaleTransition(
                scale: _contentScale,
                child: widget.child,
              ),
            ),

            // ── Overlay: all VFX painted on top ──────────────────────────
            if (_ctrl.value < 0.95)
              IgnorePointer(
                child: CustomPaint(
                  painter: _UnlockPainter(
                    ringRadius: _ringRadius.value,
                    ringOpacity: _ringOpacity.value,
                    bloomScale: _bloomScale.value,
                    bloomOpacity: _bloomOpacity.value,
                    sparkProgress: _sparkProgress.value,
                    sparkOpacity: _sparkOpacity.value,
                    sparks: _sparkDefs,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data
// ─────────────────────────────────────────────────────────────────────────────

class _Spark {
  const _Spark({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
  });

  final double angle;
  final double speed;
  final double size;
  final Color color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────

class _UnlockPainter extends CustomPainter {
  const _UnlockPainter({
    required this.ringRadius,
    required this.ringOpacity,
    required this.bloomScale,
    required this.bloomOpacity,
    required this.sparkProgress,
    required this.sparkOpacity,
    required this.sparks,
  });

  final double ringRadius;
  final double ringOpacity;
  final double bloomScale;
  final double bloomOpacity;
  final double sparkProgress;
  final double sparkOpacity;
  final List<_Spark> sparks;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final diagonal = math.sqrt(size.width * size.width + size.height * size.height);

    // ── 1. Neon bloom (cyan core + magenta rim) ───────────────────────────
    if (bloomOpacity > 0.001) {
      final bloomR = (size.width * 0.5) * bloomScale;

      // Cyan core
      canvas.drawCircle(
        center,
        bloomR,
        Paint()
          ..shader = RadialGradient(
            colors: [
              AppColors.cyan.withValues(alpha: bloomOpacity),
              AppColors.cyan.withValues(alpha: bloomOpacity * 0.55),
              AppColors.magenta.withValues(alpha: bloomOpacity * 0.30),
              Colors.transparent,
            ],
            stops: const [0.0, 0.25, 0.55, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: bloomR)),
      );

      // Outer magenta halo — oversized
      final haloR = bloomR * 1.6;
      canvas.drawCircle(
        center,
        haloR,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.transparent,
              AppColors.magenta.withValues(alpha: bloomOpacity * 0.18),
              Colors.transparent,
            ],
            stops: const [0.45, 0.70, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: haloR)),
      );
    }

    // ── 2. Shockwave ring ─────────────────────────────────────────────────
    if (ringOpacity > 0.001) {
      final actualRadius = (diagonal / 2) * ringRadius;
      // Paint 3 rings: thick translucent base, thin bright, ultra-thin outer.
      for (final (width, alpha, colorFrac) in [
        (14.0, ringOpacity * 0.25, 0.0),
        (3.0, ringOpacity * 0.85, 0.3),
        (1.0, ringOpacity * 0.50, 0.7),
      ]) {
        final c = Color.lerp(AppColors.cyan, AppColors.magenta, colorFrac)!;
        canvas.drawCircle(
          center,
          actualRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..color = c.withValues(alpha: alpha)
            ..maskFilter = width > 5
                ? const MaskFilter.blur(BlurStyle.normal, 8)
                : null,
        );
      }
    }

    // ── 3. Spark particles ────────────────────────────────────────────────
    if (sparkOpacity > 0.001) {
      for (final spark in sparks) {
        final dist = spark.speed * sparkProgress * (size.height * 0.48);
        final pos = Offset(
          center.dx + math.cos(spark.angle) * dist,
          center.dy + math.sin(spark.angle) * dist,
        );

        // Glow halo
        canvas.drawCircle(
          pos,
          spark.size * 3.0,
          Paint()
            ..color = spark.color.withValues(alpha: sparkOpacity * 0.20),
        );

        // Bright core
        canvas.drawCircle(
          pos,
          spark.size,
          Paint()
            ..color = spark.color.withValues(alpha: sparkOpacity)
            ..maskFilter =
                const MaskFilter.blur(BlurStyle.normal, 1.5),
        );

        // Trailing streak
        if (sparkProgress > 0.05) {
          final trailDist = dist * 0.15;
          final trailStart = Offset(
            center.dx + math.cos(spark.angle) * (dist - trailDist),
            center.dy + math.sin(spark.angle) * (dist - trailDist),
          );
          canvas.drawLine(
            trailStart,
            pos,
            Paint()
              ..color = spark.color.withValues(alpha: sparkOpacity * 0.45)
              ..strokeWidth = spark.size * 0.5
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _UnlockPainter old) =>
      old.ringRadius != ringRadius ||
      old.bloomOpacity != bloomOpacity ||
      old.sparkProgress != sparkProgress;
}
