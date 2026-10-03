import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/ui/ui.dart';

/// Shared presentation for inventory workflows, without owning their data.
class InventoryScaffold extends StatelessWidget {
  const InventoryScaffold({
    super.key,
    required this.child,
    this.appBar,
    this.floatingActionButton,
    this.showParticles = false,
    this.extendBodyBehindAppBar = true,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final bool showParticles;
  final bool extendBodyBehindAppBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: AppColors.cyan.withValues(alpha: .2)),
    );
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: const Color(0xFF132D35),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
              borderSide: const BorderSide(color: AppColors.cyan, width: 1.5)),
        ),
        chipTheme: theme.chipTheme.copyWith(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: AppColors.cyan.withValues(alpha: .2)),
          selectedColor: AppColors.cyan.withValues(alpha: .18),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          hoverColor: AppColors.cyan.withValues(alpha: .12),
        )),
        textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
          foregroundColor: AppColors.cyan,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        )),
      ),
      child: AppBackgroundScaffold(
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        showParticles: showParticles,
        extendBodyBehindAppBar: extendBodyBehindAppBar,
        child: Stack(children: [
          const Positioned.fill(
            child: IgnorePointer(
                child: RepaintBoundary(
              child: CustomPaint(painter: _InventoryBackdrop()),
            )),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: reducedMotion ? 1 : 0, end: 1),
            duration: Duration(milliseconds: reducedMotion ? 0 : 480),
            curve: Curves.easeOutCubic,
            child: child,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                  offset: Offset(0, 12 * (1 - value)), child: child),
            ),
          ),
        ]),
      ),
    );
  }
}

class _InventoryBackdrop extends CustomPainter {
  const _InventoryBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
        bounds,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF123E43), Color(0xFF0D202B), Color(0xFF101B2D)],
            stops: [0, .45, 1],
          ).createShader(bounds));
    final center = Offset(size.width * .95, size.height * .12);
    canvas.drawCircle(
        center,
        240,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFF77EBC6).withValues(alpha: .13),
              Colors.transparent
            ],
          ).createShader(Rect.fromCircle(center: center, radius: 240)));
    final ring = Paint()
      ..color = const Color(0xFFB0F3DD).withValues(alpha: .06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final radius in [120.0, 165.0, 210.0]) {
      canvas.drawCircle(Offset(size.width + 45, 110), radius, ring);
    }
    final dots = Paint()..color = Colors.white.withValues(alpha: .035);
    for (var x = 18.0; x < size.width; x += 28) {
      for (var y = 18.0; y < size.height; y += 28) {
        canvas.drawCircle(Offset(x, y), .7, dots);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _InventoryBackdrop oldDelegate) => false;
}
