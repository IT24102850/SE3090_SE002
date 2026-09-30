import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'inventory_panel.dart';

class InventoryLoadingState extends StatefulWidget {
  const InventoryLoadingState({
    super.key,
    this.message = 'Loading inventory',
    this.detail = 'Preparing your stock workspace',
  });

  final String message;
  final String detail;

  @override
  State<InventoryLoadingState> createState() => _InventoryLoadingStateState();
}

class _InventoryLoadingStateState extends State<InventoryLoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: InventoryPanel(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final pulse = _controller.value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: .96 + pulse * .08,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.cyan.withValues(alpha: .22 + pulse * .12),
                            AppColors.violet
                                .withValues(alpha: .16 + pulse * .1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(21),
                        border: Border.all(
                          color: AppColors.cyan
                              .withValues(alpha: .25 + pulse * .3),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.cyan
                                .withValues(alpha: .08 + pulse * .12),
                            blurRadius: 16 + pulse * 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.inventory_2_rounded,
                        color: AppColors.cyan,
                        size: 31,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.subtitle.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.detail,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List<Widget>.generate(3, (index) {
                      final phase = (pulse + index / 3) % 1;
                      final emphasis = 1 - (phase - .5).abs() * 2;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Container(
                          width: 24,
                          height: 5,
                          decoration: BoxDecoration(
                            color: AppColors.cyan.withValues(
                              alpha: .2 + emphasis * .8,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
