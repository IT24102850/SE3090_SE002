import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// An indeterminate loader: orbital light, a floating icon and flowing dots.
class WorkflowLoadingState extends StatefulWidget {
  const WorkflowLoadingState({
    super.key,
    required this.message,
    this.detail,
    this.icon = Icons.receipt_long_rounded,
    this.compact = false,
  });

  final String message;
  final String? detail;
  final IconData icon;
  final bool compact;

  @override
  State<WorkflowLoadingState> createState() => _WorkflowLoadingStateState();
}

class _WorkflowLoadingStateState extends State<WorkflowLoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _motion
        ..stop()
        ..value = .25;
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.detail == null
            ? widget.message
            : '${widget.message}. ${widget.detail}',
        liveRegion: true,
        child: ExcludeSemantics(
            child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _motion,
            builder: (context, _) {
              final phase = _motion.value;
              final emblem = SizedBox.square(
                dimension: widget.compact ? 36 : 108,
                child: CustomPaint(
                  painter: _OrbitPainter(phase),
                  child: Center(
                      child: Transform.translate(
                    offset: Offset(0,
                        widget.compact ? 0 : math.sin(phase * math.pi * 2) * 3),
                    child: Container(
                      padding: EdgeInsets.all(widget.compact ? 6 : 19),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF285C56), Color(0xFF17333E)]),
                        borderRadius:
                            BorderRadius.circular(widget.compact ? 10 : 22),
                        border: Border.all(
                            color:
                                const Color(0xFF91E8CA).withValues(alpha: .3)),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.cyan.withValues(alpha: .12),
                              blurRadius: 24)
                        ],
                      ),
                      child: Icon(widget.icon,
                          color: const Color(0xFF9EF2D5),
                          size: widget.compact ? 16 : 30),
                    ),
                  )),
                ),
              );
              if (widget.compact) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                      color: const Color(0xFF193A40),
                      borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    emblem,
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(widget.message,
                            style: AppTextStyles.caption
                                .copyWith(color: const Color(0xFFB8EADB)))),
                  ]),
                );
              }
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  emblem,
                  const SizedBox(height: 18),
                  Text(widget.message,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.subtitle
                          .copyWith(fontWeight: FontWeight.w800)),
                  if (widget.detail != null) ...[
                    const SizedBox(height: 6),
                    Text(widget.detail!,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary, height: 1.5)),
                  ],
                  const SizedBox(height: 22),
                  Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (index) {
                        final emphasis =
                            (math.sin(phase * math.pi * 2 - index * 1.1) + 1) /
                                2;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Transform.translate(
                              offset: Offset(0, -4 * emphasis),
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF9EF2D5)
                                        .withValues(alpha: .3 + .7 * emphasis)),
                              )),
                        );
                      })),
                ]),
              );
            },
          ),
        )),
      );
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter(this.phase);
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 3;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius,
        paint..color = const Color(0xFF9EF2D5).withValues(alpha: .1));
    for (var index = 0; index < 2; index++) {
      final angle = phase * math.pi * 2 + index * math.pi;
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          angle,
          .8,
          false,
          paint
            ..color = (index == 0 ? const Color(0xFF9EF2D5) : AppColors.cyan));
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) =>
      phase != oldDelegate.phase;
}
