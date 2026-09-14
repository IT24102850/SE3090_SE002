import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The "or continue with" row: three circular provider buttons separated by
/// hairline rules.
///
/// The brand marks are painted rather than shipped as assets — three tiny
/// glyphs aren't worth an SVG dependency plus a licence-bound asset folder,
/// and painted marks stay crisp at any density.
class SocialSignInRow extends StatelessWidget {
  const SocialSignInRow({super.key, required this.onProviderTap});

  /// Called with the provider's display name ("Google", "Apple", …).
  final ValueChanged<String> onProviderTap;

  @override
  Widget build(BuildContext context) {
    // Three 48px buttons plus the rules need ~226px; the card has only ~216px
    // to give on a 320dp phone. Scaling down keeps the row's proportions
    // instead of letting it overflow or cramming the dividers to nothing.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _SocialButton(
            label: 'Google',
            onTap: () => onProviderTap('Google'),
            child: const _Glyph(painter: _GoogleGlyphPainter()),
          ),
          const _Divider(),
          _SocialButton(
            label: 'Apple',
            onTap: () => onProviderTap('Apple'),
            // Apple's mark ships with Material Icons — nothing to paint.
            child: const Icon(Icons.apple, color: Colors.white, size: 24),
          ),
          const _Divider(),
          _SocialButton(
            label: 'Microsoft',
            onTap: () => onProviderTap('Microsoft'),
            child: const _Glyph(painter: _MicrosoftGlyphPainter()),
          ),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Continue with $label',
      child: Material(
        color: AppColors.iconWell,
        shape: const CircleBorder(side: BorderSide(color: AppColors.hairline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 48, height: 48, child: Center(child: child)),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      color: Colors.white.withValues(alpha: 0.12),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.painter});

  final CustomPainter painter;

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size.square(22), painter: painter);
}

/// Google's four-colour "G": one ring split into four arcs plus the blue bar
/// running from the centre out to the right edge.
class _GoogleGlyphPainter extends CustomPainter {
  const _GoogleGlyphPainter();

  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  /// Degrees, clockwise from the 3 o'clock position (Flutter's canvas has y
  /// pointing down, so "up" is 270°).
  static const _arcs = <(double, double, Color)>[
    (330, 85, _blue),
    (55, 88, _green),
    (143, 62, _yellow),
    (205, 125, _red),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = size.width * 0.26;
    final radius = size.width / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..isAntiAlias = true;

    for (final (start, sweep, color) in _arcs) {
      canvas.drawArc(rect, _rad(start), _rad(sweep), false, paint..color = color);
    }

    // The crossbar. Starts just left of centre so it tucks under the blue arc
    // instead of leaving a seam where the two meet.
    canvas.drawRect(
      Rect.fromLTRB(
        center.dx - stroke * 0.1,
        center.dy - stroke * 0.38,
        center.dx + radius + stroke / 2,
        center.dy + stroke * 0.38,
      ),
      Paint()..color = _blue,
    );
  }

  double _rad(double degrees) => degrees * math.pi / 180;

  @override
  bool shouldRepaint(covariant _GoogleGlyphPainter oldDelegate) => false;
}

/// Microsoft's four squares: red, green, blue, yellow, clockwise from top left.
class _MicrosoftGlyphPainter extends CustomPainter {
  const _MicrosoftGlyphPainter();

  static const _tiles = <(int, int, Color)>[
    (0, 0, Color(0xFFF25022)),
    (1, 0, Color(0xFF7FBA00)),
    (0, 1, Color(0xFF00A4EF)),
    (1, 1, Color(0xFFFFB900)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width * 0.09;
    final tile = (size.width - gap) / 2;

    for (final (col, row, color) in _tiles) {
      canvas.drawRect(
        Rect.fromLTWH(col * (tile + gap), row * (tile + gap), tile, tile),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MicrosoftGlyphPainter oldDelegate) => false;
}
