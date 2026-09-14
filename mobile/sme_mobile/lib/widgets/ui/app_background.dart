import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The full-bleed backdrop every screen sits on: a vertical navy ramp, a
/// couple of soft radial blooms, and — where it earns its place — a scatter of
/// neon specks.
///
/// Meant to be the first child of a [Stack] under [Positioned.fill]; it paints
/// and never sizes itself, so the content above drives the layout. No screen
/// in the app should use a flat background colour instead.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, this.showParticles = false});

  /// Decorative specks. Worth it on hero-led screens (auth, dashboard);
  /// switched off on dense content screens where they'd just read as noise
  /// behind the cards.
  final bool showParticles;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
            ),
          ),

          // Large violet bloom, upper right. Oversized and pushed off the edge
          // so only the soft shoulder of the gradient lands on screen.
          const Positioned(
            top: -160,
            right: -180,
            child: _Glow(diameter: 520, color: AppColors.violet, opacity: 0.28),
          ),

          // Fainter cyan bloom, lower left, to keep the bottom third from
          // going flat behind the content.
          const Positioned(
            bottom: -140,
            left: -200,
            child: _Glow(diameter: 460, color: AppColors.cyan, opacity: 0.15),
          ),

          // Magenta kicker, tying the accent hue back into the canvas.
          const Positioned(
            top: 180,
            left: -80,
            child: _Glow(diameter: 300, color: AppColors.magenta, opacity: 0.15),
          ),

          if (showParticles)
            Positioned.fill(child: CustomPaint(painter: _ParticlePainter())),
        ],
      ),
    );
  }
}

/// Wraps [child] in a [Scaffold]-ready stack: background behind, content in
/// front. Saves every screen repeating the same three lines.
class AppBackgroundScaffold extends StatelessWidget {
  const AppBackgroundScaffold({
    super.key,
    required this.child,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.drawer,
    this.showParticles = false,
    this.extendBodyBehindAppBar = true,
    this.resizeToAvoidBottomInset,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final bool showParticles;
  final bool extendBodyBehindAppBar;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Transparent so the gradient below shows through the whole frame,
      // including behind a glass app bar and a floating nav bar.
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      extendBody: true,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: appBar,
      drawer: drawer,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      body: Stack(
        children: [
          Positioned.fill(child: AppBackground(showParticles: showParticles)),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

/// One radial bloom: opaque-ish at the centre, fully transparent at the rim.
class _Glow extends StatelessWidget {
  const _Glow({required this.diameter, required this.color, required this.opacity});

  final double diameter;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: opacity * 0.45),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }
}

/// A single decorative speck: either a filled dot or an outlined hexagon.
class _Particle {
  const _Particle({
    required this.dx,
    required this.dy,
    required this.radius,
    required this.color,
    required this.opacity,
    required this.isHexagon,
    required this.rotation,
  });

  /// Fractions of the paint size, so the scatter survives any screen size.
  final double dx;
  final double dy;
  final double radius;
  final Color color;
  final double opacity;
  final bool isHexagon;
  final double rotation;
}

/// Built once with a fixed seed rather than per-frame: the scatter should look
/// random but stay put across rebuilds (keyboard opening, navigation…).
final List<_Particle> _particles = _buildParticles();

List<_Particle> _buildParticles() {
  final random = math.Random(20250909);
  return List<_Particle>.generate(15, (i) {
    final isHexagon = i.isEven;
    return _Particle(
      dx: 0.04 + random.nextDouble() * 0.92,
      // Upper 60% of the screen only — below that the content takes over and
      // specks behind frosted glass just read as noise.
      dy: 0.03 + random.nextDouble() * 0.57,
      radius: isHexagon ? 4.0 + random.nextDouble() * 5.0 : 1.2 + random.nextDouble() * 2.0,
      color: random.nextBool() ? AppColors.cyan : AppColors.magenta,
      opacity: 0.4 + random.nextDouble() * 0.3,
      isHexagon: isHexagon,
      rotation: random.nextDouble() * math.pi,
    );
  });
}

class _ParticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in _particles) {
      final center = Offset(particle.dx * size.width, particle.dy * size.height);
      final paint = Paint()
        ..color = particle.color.withValues(alpha: particle.opacity)
        ..isAntiAlias = true;

      if (particle.isHexagon) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawPath(_hexagonPath(center, particle.radius, particle.rotation), paint);
      } else {
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(center, particle.radius, paint);
        // A faint halo, so dots read as glowing rather than as dust.
        canvas.drawCircle(
          center,
          particle.radius * 2.6,
          Paint()..color = particle.color.withValues(alpha: particle.opacity * 0.18),
        );
      }
    }
  }

  Path _hexagonPath(Offset center, double radius, double rotation) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = rotation + i * math.pi / 3;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => false;
}
