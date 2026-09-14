import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The hero "sculpture": intertwined chrome rings orbiting a glowing orb.
///
/// Stands in for the 3D render in the design. Each ring is a thin circle
/// stroked with a sweep gradient (silver → cyan → magenta) and pushed through
/// a perspective [Matrix4], so it reads as a tilted metallic loop rather than
/// a flat outline. The rings turn at different speeds and around different
/// axes, which is what sells the "intertwined" look — at any moment some rings
/// are edge-on while others are face-on.
class OrbitHero extends StatefulWidget {
  const OrbitHero({super.key, this.size = 340, this.animate = true});

  final double size;

  /// Off in tests and for reduced-motion, where a spinning hero is noise.
  final bool animate;

  @override
  State<OrbitHero> createState() => _OrbitHeroState();
}

class _OrbitHeroState extends State<OrbitHero> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// One slow master turn drives every ring; each ring scales it by its own
  /// [_RingSpec.speed] so they never lock into the same rhythm.
  static const _period = Duration(seconds: 28);

  static const List<_RingSpec> _rings = [
    _RingSpec(scale: 1.00, tiltX: 1.15, tiltY: 0.10, speed: 1.0, phase: 0.0, color: Color(0xFFE8ECF8), opacity: 0.45),
    _RingSpec(scale: 0.84, tiltX: 0.55, tiltY: 0.85, speed: -1.6, phase: 0.8, color: AppColors.cyan, opacity: 0.50),
    _RingSpec(scale: 0.68, tiltX: 1.35, tiltY: -0.60, speed: 2.1, phase: 1.9, color: AppColors.magenta, opacity: 0.40),
    _RingSpec(scale: 0.52, tiltX: 0.25, tiltY: 0.35, speed: -2.8, phase: 3.1, color: Color(0xFFCBD5F5), opacity: 0.28),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _period);
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(OrbitHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ambient bloom the rings float in front of.
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.violet.withValues(alpha: 0.30),
                    AppColors.electricBlue.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),

            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final turn = _controller.value * 2 * math.pi;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    for (final ring in _rings)
                      Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          // A little perspective, so the far side of each ring
                          // narrows instead of staying a flat ellipse.
                          ..setEntry(3, 2, 0.0014)
                          ..rotateX(ring.tiltX)
                          ..rotateY(ring.tiltY + turn * ring.speed * 0.35)
                          ..rotateZ(ring.phase + turn * ring.speed),
                        child: CustomPaint(
                          size: Size.square(widget.size * ring.scale),
                          painter: _RingPainter(ring),
                        ),
                      ),
                  ],
                );
              },
            ),

            // The orb at the centre of the sculpture.
            Container(
              // Proportional, not fixed: the hero shrinks to fit short
              // screens, and a hardcoded orb would swamp the rings there
              // instead of sitting inside them. 0.17 reproduces the original
              // 58px orb at the 340px design size.
              width: widget.size * 0.17,
              height: widget.size * 0.17,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Colors.white, Color(0xFFD8F6FF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.55),
                    blurRadius: widget.size * 0.118,
                    spreadRadius: widget.size * 0.012,
                  ),
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.45),
                    blurRadius: widget.size * 0.176,
                    spreadRadius: widget.size * 0.035,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingSpec {
  const _RingSpec({
    required this.scale,
    required this.tiltX,
    required this.tiltY,
    required this.speed,
    required this.phase,
    required this.color,
    required this.opacity,
  });

  /// Diameter as a fraction of the hero box.
  final double scale;
  final double tiltX;
  final double tiltY;

  /// Multiplier on the master turn; negative reverses the ring.
  final double speed;
  final double phase;

  /// The ring's dominant hue — the sweep gradient blends it with chrome so no
  /// ring is a single flat colour.
  final Color color;
  final double opacity;
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.spec);

  final _RingSpec spec;

  static const _chrome = Color(0xFFF2F5FF);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = size.width / 2 - 1;

    // Sweep gradient = the iridescent highlight travelling around the loop:
    // chrome at the highlights, the ring's own hue in between.
    final shader = SweepGradient(
      colors: [
        _chrome.withValues(alpha: spec.opacity),
        spec.color.withValues(alpha: spec.opacity),
        _chrome.withValues(alpha: spec.opacity * 0.35),
        spec.color.withValues(alpha: spec.opacity * 0.9),
        _chrome.withValues(alpha: spec.opacity),
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
    ).createShader(rect);

    canvas.drawCircle(
      rect.center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = shader
        ..isAntiAlias = true,
    );

    // A wider, much fainter pass under the crisp stroke reads as the bloom
    // coming off polished metal.
    canvas.drawCircle(
      rect.center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = spec.color.withValues(alpha: spec.opacity * 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.spec != spec;
}
