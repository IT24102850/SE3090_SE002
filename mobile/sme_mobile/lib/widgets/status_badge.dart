import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatusBadge extends StatefulWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  @override
  State<StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<StatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _isActive {
    switch (widget.status) {
      case 'Confirmed':
      case 'CheckedIn':
      case 'InProgress':
        return true;
      default:
        return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    if (_isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant StatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_isActive && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = BookingStatusVisual.of(widget.status);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = _isActive ? 0.72 + (_controller.value * 0.28) : 0.72;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: visual.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: visual.color
                  .withValues(alpha: _isActive ? 0.42 * pulse : 0.2),
            ),
            boxShadow: _isActive
                ? [
                    BoxShadow(
                      color: visual.color.withValues(alpha: 0.16 * pulse),
                      blurRadius: 10 + (pulse * 5),
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                if (_isActive)
                  Positioned.fill(
                    child: FractionallySizedBox(
                      widthFactor: 0.32,
                      alignment: Alignment(-1.0 + (_controller.value * 4.0), 0),
                      child: Transform.rotate(
                        angle: -0.24,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                visual.color.withValues(alpha: 0.28),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(visual.icon, size: 13, color: visual.color),
                    const SizedBox(width: 5),
                    Text(
                      visual.label,
                      style: TextStyle(
                        color: visual.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
