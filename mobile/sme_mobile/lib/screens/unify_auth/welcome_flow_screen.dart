import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/unify_auth/ios_home_indicator.dart';
import '../../widgets/unify_auth/ios_lock_glyph.dart';
import '../../widgets/unify_auth/orbit_hero.dart';
import '../../widgets/unify_auth/unify_logo_mark.dart';
import '../../widgets/unify_auth/unify_wordmark.dart';
import 'unify_login_screen.dart';

/// An iPhone-authentic Welcome & Lock Screen flow.
///
/// Features:
/// - iOS-style Lock Screen with live clock, date, and animated Apple padlock
/// - Interactive physics-based vertical swipe gesture with 1:1 finger tracking
/// - Depth parallax transition: welcome screen scales down and blurs away while
///   the login card rises with authentic spring physics
/// - Shimmering "Swipe up to unlock" prompt and glowing iOS home indicator bar
/// - Reversible gesture: pull down on the login screen to return to the lock screen
class WelcomeFlowScreen extends StatefulWidget {
  const WelcomeFlowScreen({super.key});

  @override
  State<WelcomeFlowScreen> createState() => _WelcomeFlowScreenState();
}

class _WelcomeFlowScreenState extends State<WelcomeFlowScreen>
    with SingleTickerProviderStateMixin {
  AnimationController? _swipeController;
  Animation<double>? _curvedAnimation;

  AnimationController get _controller => _swipeController ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 650),
      );

  Animation<double> get _curve => _curvedAnimation ??= CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

  Timer? _clockTimer;
  DateTime _currentTime = DateTime.now();

  double _dragStartY = 0.0;
  double _dragStartValue = 0.0;

  @override
  void initState() {
    super.initState();
    // Ensure initialized
    _controller;
    _curve;

    // Keep lock screen clock fresh
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        setState(() => _currentTime = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _swipeController?.dispose();
    super.dispose();
  }

  void _openSignIn() {
    HapticFeedback.lightImpact();
    _controller.animateTo(
      1.0,
      duration: const Duration(milliseconds: 680),
      curve: Curves.easeOutCubic,
    );
  }

  void _backToWelcome() {
    HapticFeedback.lightImpact();
    _controller.animateTo(
      0.0,
      duration: const Duration(milliseconds: 580),
      curve: Curves.easeOutCubic,
    );
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _dragStartY = details.globalPosition.dy;
    _dragStartValue = _controller.value;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, double screenHeight) {
    final deltaY = _dragStartY - details.globalPosition.dy;
    final progress = (_dragStartValue + (deltaY / screenHeight)).clamp(0.0, 1.0);
    _controller.value = progress;
  }

  void _onVerticalDragEnd(DragEndDetails details, double screenHeight) {
    final velocity = details.primaryVelocity ?? 0.0;
    // Velocity is negative when swiping up
    if (velocity < -350 || _controller.value > 0.28) {
      _openSignIn();
    } else {
      _backToWelcome();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final height = size.height;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.bgBottom,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.bgTop,
        body: GestureDetector(
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: (details) =>
              _onVerticalDragUpdate(details, height),
          onVerticalDragEnd: (details) => _onVerticalDragEnd(details, height),
          behavior: HitTestBehavior.translucent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Ambient living background
              const AppBackground(showParticles: true),

              // Animated Transition Layer
              AnimatedBuilder(
                animation: _curve,
                builder: (context, child) {
                  final progress = _controller.value;
                  final curved = _curve.value;

                  // Welcome Screen Parallax & Depth
                  final welcomeScale = (1.0 - (curved * 0.09)).clamp(0.90, 1.0);
                  final welcomeOffset = -140.0 * curved;
                  final welcomeOpacity =
                      (1.0 - (progress * 1.6)).clamp(0.0, 1.0);
                  final blurSigma = curved * 6.0;

                  // Login Screen Rise & Expansion
                  final loginOffset = height * (1.0 - curved);
                  final loginScale = (0.92 + (0.08 * curved)).clamp(0.92, 1.0);
                  final loginOpacity = (progress * 2.2).clamp(0.0, 1.0);

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // LAYER 1: Welcome / Lock Screen
                      if (welcomeOpacity > 0.01)
                        Transform.translate(
                          offset: Offset(0, welcomeOffset),
                          child: Transform.scale(
                            scale: welcomeScale,
                            child: Opacity(
                              opacity: welcomeOpacity,
                              child: ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(
                                  sigmaX: blurSigma,
                                  sigmaY: blurSigma,
                                ),
                                child: _IosWelcomePage(
                                  currentTime: _currentTime,
                                  swipeProgress: progress,
                                ),
                              ),
                            ),
                          ),
                        ),

                      // LAYER 2: Sign-in Screen (slides up with iOS spring dynamics)
                      if (loginOpacity > 0.01)
                        Transform.translate(
                          offset: Offset(0, loginOffset),
                          child: Transform.scale(
                            scale: loginScale,
                            child: Opacity(
                              opacity: loginOpacity,
                              child: UnifyLoginScreen(
                                onBackToWelcome: _backToWelcome,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IosWelcomePage extends StatelessWidget {
  const _IosWelcomePage({
    required this.currentTime,
    required this.swipeProgress,
  });

  final DateTime currentTime;
  final double swipeProgress;

  String _formatDate(DateTime d) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  String _formatTime(DateTime d) {
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _getGreeting(DateTime d) {
    final h = d.hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final heroSize = (height * 0.25).clamp(135.0, 240.0);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 6, 26, 12),
        child: Column(
          children: [
            // Dynamic Island Status Capsule
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.glassFill,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: swipeProgress > 0.4
                        ? AppColors.cyan.withValues(alpha: 0.5)
                        : AppColors.glassBorder,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: swipeProgress > 0.4
                          ? AppColors.cyan.withValues(alpha: 0.25)
                          : Colors.black.withValues(alpha: 0.2),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IosLockGlyph(
                      progress: swipeProgress,
                      size: 17,
                      showGlow: false,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      swipeProgress > 0.4 ? 'UNLOCKED' : 'UNIFY SECURED',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: swipeProgress > 0.4
                            ? AppColors.cyan
                            : Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: swipeProgress > 0.4
                            ? AppColors.cyan
                            : const Color(0xFF00E676),
                        boxShadow: [
                          BoxShadow(
                            color: swipeProgress > 0.4
                                ? AppColors.cyan
                                : const Color(0xFF00E676),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ),

            const SizedBox(height: 10),

            // Dynamic Greeting & iOS Lock Screen Date
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  currentTime.hour >= 6 && currentTime.hour < 18
                      ? Icons.wb_sunny_rounded
                      : Icons.nightlight_round,
                  size: 13,
                  color: AppColors.cyan,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_getGreeting(currentTime).toUpperCase()} • ${_formatDate(currentTime).toUpperCase()}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 2),

            // iOS Lock Screen Large Clock with depth shadow
            Text(
              _formatTime(currentTime),
              style: TextStyle(
                fontSize: 74,
                fontWeight: FontWeight.w200,
                letterSpacing: -2.5,
                color: Colors.white,
                height: 1.0,
                shadows: [
                  Shadow(
                    color: AppColors.cyan.withValues(alpha: 0.28),
                    blurRadius: 30,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Unify Brand Lockup
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                UnifyLogoMark(size: 24),
                SizedBox(width: 8),
                UnifyWordmark(fontSize: 22),
              ],
            ),

            // Hero 3D Sculpture with ambient radial backlight
            Expanded(
              flex: 5,
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: heroSize * 1.3,
                      height: heroSize * 1.3,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.cyan.withValues(alpha: 0.16),
                            AppColors.magenta.withValues(alpha: 0.10),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                    OrbitHero(size: heroSize),
                  ],
                ),
              ),
            ),

            // Headline
            const Text(
              'Everything flows\nwith Unify.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 32,
                height: 1.15,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.0,
              ),
            ),

            const SizedBox(height: 8),

            // Subtitle
            const Text(
              'Run your business, connect with customers, and keep every appointment moving effortlessly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textBody,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),

            const SizedBox(height: 12),

            // Benefit Pills
            const Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _Benefit(
                    icon: Icons.storefront_rounded, label: 'Grow your business'),
                _Benefit(
                    icon: Icons.event_available_rounded, label: 'Manage bookings'),
                _Benefit(
                    icon: Icons.inventory_2_rounded, label: 'Manage inventory'),
                _Benefit(
                    icon: Icons.fingerprint_rounded, label: 'Biometric Security'),
              ],
            ),

            const Spacer(flex: 2),


            // iPhone Home Indicator Bar & Shimmer Prompt
            const IosHomeIndicator(label: 'Swipe up to enter Unify'),

            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.cyan),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textBody,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}
