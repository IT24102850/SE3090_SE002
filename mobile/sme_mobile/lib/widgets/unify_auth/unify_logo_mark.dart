import 'package:flutter/material.dart';

/// The official Unify brand mark: a navy rounded tile carrying the "U"
/// monogram in a cyan→blue gradient, with the convergence node at its base.
///
/// A faithful port of frontend/public/unify-logo.svg (also the web favicon
/// and the sidebar mark), painted rather than loaded so it needs no
/// flutter_svg dependency or asset registration and stays crisp at any size.
/// Every coordinate below is the SVG's own, in its 64-unit viewBox, scaled
/// at paint time — change the SVG and this is the file to update.
class UnifyLogoMark extends StatelessWidget {
  const UnifyLogoMark({super.key, this.size = 48, this.glow = true});

  final double size;

  /// A soft cyan bloom behind the tile. On the auth screens' near-black
  /// backdrop the tile's own #0A0F1D fill is almost invisible; the glow is
  /// what gives the mark an edge there. Off for light surfaces.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Unify logo',
      child: Container(
        width: size,
        height: size,
        decoration: glow
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(size * 14 / 64),
                boxShadow: [
                  BoxShadow(
                    color: _UnifyLogoPainter.gradientStart.withValues(alpha: 0.35),
                    blurRadius: size * 0.45,
                    spreadRadius: size * 0.02,
                  ),
                ],
              )
            : null,
        child: const CustomPaint(painter: _UnifyLogoPainter()),
      ),
    );
  }
}

class _UnifyLogoPainter extends CustomPainter {
  const _UnifyLogoPainter();

  // Verbatim from the SVG.
  static const tileFill = Color(0xFF0A0F1D);
  static const gradientStart = Color(0xFF06B6D4);
  static const gradientEnd = Color(0xFF2563EB);
  static const node = Color(0xFF38BDF8);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;

    // <rect width="64" height="64" rx="14" fill="#0A0F1D"/>
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(14 * s)),
      Paint()..color = tileFill,
    );

    // <linearGradient x1="8" y1="12" x2="56" y2="52" gradientUnits="userSpaceOnUse">
    final shader = const LinearGradient(
      colors: [gradientStart, gradientEnd],
    ).createShader(Rect.fromPoints(Offset(8 * s, 12 * s), Offset(56 * s, 52 * s)));

    // <path d="M18 18 V36 C18 43.732 24.268 50 32 50 C39.732 50 46 43.732 46 36 V18"
    //       stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>
    final u = Path()
      ..moveTo(18 * s, 18 * s)
      ..lineTo(18 * s, 36 * s)
      ..cubicTo(18 * s, 43.732 * s, 24.268 * s, 50 * s, 32 * s, 50 * s)
      ..cubicTo(39.732 * s, 50 * s, 46 * s, 43.732 * s, 46 * s, 36 * s)
      ..lineTo(46 * s, 18 * s);

    canvas.drawPath(
      u,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = shader
        ..isAntiAlias = true,
    );

    // <circle cx="32" cy="36" r="3.5" fill="#38BDF8"/>
    canvas.drawCircle(Offset(32 * s, 36 * s), 3.5 * s, Paint()..color = node);
  }

  @override
  bool shouldRepaint(covariant _UnifyLogoPainter oldDelegate) => false;
}
