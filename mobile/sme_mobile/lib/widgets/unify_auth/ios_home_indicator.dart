import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// The iconic iOS home indicator and animated upward swipe prompt.
///
/// Features a continuous light-sweep shimmer across the typography,
/// an upward-gliding chevron with breathing opacity. The operating system
/// draws its own home indicator, so this widget avoids duplicating that pill.
class IosHomeIndicator extends StatefulWidget {
  const IosHomeIndicator({
    super.key,
    this.label = 'Swipe up to enter Unify',
  });

  final String label;

  @override
  State<IosHomeIndicator> createState() => _IosHomeIndicatorState();
}

class _IosHomeIndicatorState extends State<IosHomeIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loopController;

  @override
  void initState() {
    super.initState();
    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _loopController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: _loopController,
        builder: (context, child) {
          final t = _loopController.value;

          // Upward chevron bounce & fade
          final chevronOffset1 = -9.0 * (1.0 - (t * 2 - 1.0).abs());
          final chevronOpacity1 = (0.35 + 0.65 * (1.0 - (t * 2 - 1.0).abs())).clamp(0.0, 1.0);
          final t2 = (t + 0.18) % 1.0;
          final chevronOffset2 = -9.0 * (1.0 - (t2 * 2 - 1.0).abs());
          final chevronOpacity2 = (0.20 + 0.50 * (1.0 - (t2 * 2 - 1.0).abs())).clamp(0.0, 1.0);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cascading dual upward chevrons
              SizedBox(
                height: 20,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.translate(
                      offset: Offset(0, chevronOffset2 - 4),
                      child: Opacity(
                        opacity: chevronOpacity2,
                        child: const Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: AppColors.cyan,
                          size: 20,
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(0, chevronOffset1 + 3),
                      child: Opacity(
                        opacity: chevronOpacity1,
                        child: const Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 2),

              // Shimmering "Swipe up to unlock" text
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) {
                  return LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: const [
                      Color(0x80FFFFFF),
                      Color(0xFFFFFFFF),
                      AppColors.cyan,
                      Color(0x80FFFFFF),
                    ],
                    stops: [
                      (t - 0.35).clamp(0.0, 1.0),
                      (t - 0.10).clamp(0.0, 1.0),
                      t.clamp(0.0, 1.0),
                      (t + 0.30).clamp(0.0, 1.0),
                    ],
                  ).createShader(bounds);
                },
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

            ],
          );
        },
    );
  }
}
