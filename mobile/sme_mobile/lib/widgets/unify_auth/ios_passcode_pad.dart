import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../../services/biometric_auth_service.dart';
import '../../theme/app_colors.dart';
import 'ios_lock_glyph.dart';

enum _BiometricResult { success, failure }

/// An ultra-attractive, production-grade iPhone Passcode & Biometric unlock pad.
///
/// Features:
/// - Real device biometrics (Face ID & Fingerprint) with animated holographic scanner
/// - 4 glowing passcode dots with elastic spring pop and shockwave burst
/// - Authentic iOS horizontal error shake on invalid PIN
/// - Frosted glass circular keypad buttons with tactile press-scale & ambient neon rim
/// - Dynamic Biometrics button (Face ID or Touch ID based on hardware)
/// - Zero demo text or mock hints — pure enterprise-grade polish
class IosPasscodePad extends StatefulWidget {
  const IosPasscodePad({
    super.key,
    required this.onPinSubmit,
    required this.onBiometricSubmit,
    this.title = 'Enter Passcode',
    this.subtitle = 'Unlock your Unify workspace',
    this.onCancel,
  });

  /// Called when 4 digits are entered. Return true if valid, false if invalid.
  final Future<bool> Function(String pin) onPinSubmit;

  /// Called when Face ID / Fingerprint succeeds.
  final Future<bool> Function() onBiometricSubmit;

  final String title;
  final String subtitle;
  final VoidCallback? onCancel;

  @override
  State<IosPasscodePad> createState() => _IosPasscodePadState();
}

class _IosPasscodePadState extends State<IosPasscodePad>
    with TickerProviderStateMixin {
  String _pin = '';
  bool _isUnlocked = false;
  bool _isVerifying = false;
  bool _hasError = false;
  bool _isScanningBiometric = false;
  bool _hasBiometrics = false;
  bool _hasFingerprint = false;
  bool _hasFaceId = false;
  String? _biometricMessage;
  _BiometricResult? _biometricResult;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  late final AnimationController _successController;
  late final Animation<double> _successScale;

  late final AnimationController _scanController;
  late final Animation<double> _scanAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );

    _shakeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _successScale = CurvedAnimation(
      parent: _successController,
      curve: Curves.elasticOut,
    );

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scanAnimation = CurvedAnimation(
      parent: _scanController,
      curve: Curves.easeInOut,
    );
    _scanController.repeat(reverse: true);

    _checkHardwareBiometrics();
  }

  @override
  void reassemble() {
    super.reassemble();
    // A hot reload can leave an existing state with its animation controller
    // initialized but stopped. Resume it without introducing new late fields.
    if (!_scanController.isAnimating) {
      _scanController.repeat(reverse: true);
    }
  }

  Future<void> _checkHardwareBiometrics() async {
    final types = await BiometricAuthService.getAvailableBiometrics();
    if (mounted) {
      setState(() {
        // Android reports enrolled biometrics as weak/strong rather than
        // identifying the sensor as face or fingerprint. The OS authentication
        // sheet selects the enrolled sensor when the user taps the control.
        _hasBiometrics = types.isNotEmpty;
        _hasFingerprint = types.contains(BiometricType.fingerprint);
        _hasFaceId = types.contains(BiometricType.face);
      });
    }
  }

  String get _biometricLabel {
    if (_hasFaceId && _hasFingerprint) return 'Face + Touch ID';
    if (_hasFaceId) return 'Face ID';
    if (_hasFingerprint) return 'Fingerprint';
    return 'Biometric';
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _successController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  void _onDigitPressed(String digit) {
    if (_pin.length >= 4 || _isVerifying || _isUnlocked) return;

    HapticFeedback.selectionClick();
    setState(() {
      _hasError = false;
      _biometricMessage = null;
      _biometricResult = null;
      _pin += digit;
    });

    if (_pin.length == 4) {
      _verifyPin();
    }
  }

  void _onDelete() {
    if (_pin.isEmpty || _isVerifying || _isUnlocked) return;
    HapticFeedback.selectionClick();
    setState(() {
      _hasError = false;
      _biometricMessage = null;
      _biometricResult = null;
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  Future<void> _verifyPin() async {
    setState(() => _isVerifying = true);

    final success = await widget.onPinSubmit(_pin);

    if (success) {
      HapticFeedback.mediumImpact();
      setState(() {
        _isUnlocked = true;
      });
      _successController.forward();
    } else {
      // Wrong PIN: trigger authentic iOS shake
      HapticFeedback.heavyImpact();
      setState(() {
        _hasError = true;
      });
      await _shakeController.forward(from: 0.0);
      if (!mounted) return;
      setState(() {
        _pin = '';
        _isVerifying = false;
      });
    }
  }

  Future<void> _triggerBiometric() async {
    if (_isVerifying || _isUnlocked) return;

    HapticFeedback.lightImpact();
    setState(() {
      _isVerifying = true;
      _isScanningBiometric = true;
      _biometricMessage = null;
      _biometricResult = null;
    });
    _scanController.repeat(reverse: true);

    final authenticated = await BiometricAuthService.authenticate();

    if (!mounted) return;

    if (!authenticated) {
      _showBiometricFailure(
        message: _hasBiometrics
            ? 'Biometric check was cancelled or did not match. Try again or enter your PIN.'
            : 'No enrolled biometrics were detected. Enroll Face ID or a fingerprint in your device settings.',
      );
      return;
    }

    setState(() {
      _isScanningBiometric = false;
      _biometricResult = _BiometricResult.success;
    });
    // Let the sensor-specific success flourish complete before the app swaps
    // the lock screen for the dashboard.
    await Future<void>.delayed(const Duration(milliseconds: 680));
    if (!mounted) return;

    final sessionUnlocked = await widget.onBiometricSubmit();
    if (!mounted) return;
    if (!sessionUnlocked) {
      _showBiometricFailure(
        message:
            'Biometrics matched, but this saved session could not be unlocked. Sign in with Work Email.',
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isVerifying = false;
      _isUnlocked = true;
      _biometricMessage = null;
    });
    _successController.forward(from: 0);
  }

  void _showBiometricFailure({required String message}) {
    HapticFeedback.heavyImpact();
    setState(() {
      _isVerifying = false;
      _isScanningBiometric = false;
      _isUnlocked = false;
      _biometricResult = _BiometricResult.failure;
      _biometricMessage = message;
    });
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _biometricResult == _BiometricResult.failure) {
        setState(() => _biometricResult = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top Lock Glyph with spring unlock pop
        ScaleTransition(
          scale: Tween<double>(begin: 1.0, end: 1.15).animate(_successScale),
          child: IosLockGlyph(
            isUnlocked: _isUnlocked,
            size: 32,
            showGlow: true,
          ),
        ),

        const SizedBox(height: 12),

        // Title
        Text(
          widget.title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            letterSpacing: 0.2,
          ),
        ),

        const SizedBox(height: 5),

        Text(
          widget.subtitle,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),

        const SizedBox(height: 22),

        // Biometric Scanner or 4 Passcode Dots
        if (_isScanningBiometric)
          _buildBiometricScanner()
        else if (_biometricResult != null)
          _buildBiometricResult()
        else
          _buildPasscodeDots(),

        if (_biometricMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            _biometricMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],

        const SizedBox(height: 26),

        // iOS Glass Keypad Matrix (1-9, 0)
        _buildKeypad(),

        const SizedBox(height: 8),

        // Enterprise Security status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _hasBiometrics
                    ? (_hasFingerprint
                        ? Icons.fingerprint_rounded
                        : (_hasFaceId
                            ? Icons.face_unlock_rounded
                            : Icons.security_rounded))
                    : Icons.security_rounded,
                size: 13,
                color: AppColors.cyan,
              ),
              const SizedBox(width: 6),
              Text(
                _hasBiometrics
                    ? '$_biometricLabel & PIN Protected'
                    : 'PIN Protected',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBiometricScanner() {
    return AnimatedBuilder(
      animation: _scanAnimation,
      builder: (context, child) {
        final progress = _scanAnimation.value;
        final scanOffset = progress * 42.0 - 21.0;
        final icon = _biometricIcon;
        return SizedBox(
          width: 88,
          height: 88,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Expanding light rings give the sensor a clear scanning pulse.
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.cyan.withValues(
                      alpha: 0.12 + (0.28 * progress),
                    ),
                  ),
                ),
              ),
              Transform.scale(
                scale: 0.84 + (0.16 * progress),
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.cyan.withValues(alpha: 0.11),
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.60),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cyan.withValues(
                          alpha: 0.14 + (0.22 * progress),
                        ),
                        blurRadius: 18 + (8 * progress),
                        spreadRadius: 1 + (2 * progress),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 38,
                        color: AppColors.cyan,
                        shadows: [
                          Shadow(
                            color: AppColors.cyan.withValues(alpha: 0.55),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      if (_hasFaceId)
                        Transform.translate(
                          offset: Offset(0, scanOffset),
                          child: Container(
                            width: 48,
                            height: 1.5,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.cyan,
                                  blurRadius: 9,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBiometricResult() {
    final succeeded = _biometricResult == _BiometricResult.success;
    final isFaceId = _hasFaceId && !_hasFingerprint;
    final color = succeeded ? AppColors.cyan : AppColors.magenta;
    final sensorName =
        isFaceId ? 'Face ID' : (_hasFingerprint ? 'Fingerprint' : 'Biometrics');

    return TweenAnimationBuilder<double>(
      key: ValueKey('${_biometricResult}_$sensorName'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutBack,
      builder: (context, progress, child) {
        final shake = succeeded
            ? 0.0
            : math.sin(progress * math.pi * 5) * 8 * (1 - progress);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 92,
              height: 92,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Face ID gets a scanning frame; fingerprint gets expanding
                  // rings, so the two sensor types have distinct feedback.
                  if (isFaceId)
                    Container(
                      width: 64 + (18 * progress),
                      height: 64 + (18 * progress),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color:
                              color.withValues(alpha: 0.18 + progress * 0.42),
                          width: 1.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                color.withValues(alpha: 0.12 + progress * 0.2),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      width: 58 + (26 * progress),
                      height: 58 + (26 * progress),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              color.withValues(alpha: 0.12 + progress * 0.45),
                          width: 1.4,
                        ),
                      ),
                    ),
                  Transform.translate(
                    offset: Offset(shake, 0),
                    child: Transform.scale(
                      scale: 0.58 + (0.42 * progress),
                      child: Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          shape:
                              isFaceId ? BoxShape.rectangle : BoxShape.circle,
                          borderRadius:
                              isFaceId ? BorderRadius.circular(20) : null,
                          color: color.withValues(alpha: 0.12),
                          border: Border.all(
                            color: color.withValues(alpha: 0.72),
                            width: 1.6,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.25 * progress),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              isFaceId
                                  ? Icons.face_unlock_rounded
                                  : Icons.fingerprint_rounded,
                              color: color,
                              size: 37,
                            ),
                            if (isFaceId && succeeded)
                              Align(
                                alignment: Alignment(0, -0.45 + progress * 0.9),
                                child: Container(
                                  width: 42,
                                  height: 1.5,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.cyan,
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Transform.scale(
                      scale: progress,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          border: Border.all(color: AppColors.bgTop, width: 2),
                        ),
                        child: Icon(
                          succeeded ? Icons.check_rounded : Icons.close_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              succeeded ? '$sensorName verified' : '$sensorName not verified',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        );
      },
    );
  }

  IconData get _biometricIcon => _hasFaceId && !_hasFingerprint
      ? Icons.face_unlock_rounded
      : Icons.fingerprint_rounded;

  Widget _buildBiometricActionKey() {
    return InkResponse(
      onTap: _triggerBiometric,
      radius: 38,
      splashColor: AppColors.cyan.withValues(alpha: 0.28),
      child: AnimatedBuilder(
        // Reuse the scanner controller, which is initialized with the keypad
        // state and remains safe across hot reloads.
        animation: _scanController,
        builder: (context, child) {
          final pulse = _scanController.value;
          return Transform.scale(
            scale: 0.96 + (pulse * 0.04),
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cyan.withValues(alpha: 0.035 + pulse * 0.055),
                border: Border.all(
                  color: AppColors.cyan.withValues(alpha: 0.18 + pulse * 0.25),
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        AppColors.cyan.withValues(alpha: 0.04 + pulse * 0.13),
                    blurRadius: 8 + pulse * 10,
                    spreadRadius: pulse * 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _biometricIcon,
                    color: AppColors.cyan,
                    size: 25 + pulse * 2,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _biometricLabel,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.15,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPasscodeDots() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        // Authentic iOS dampening shake curve
        final offset = _hasError
            ? math.sin(_shakeAnimation.value * math.pi * 5.0) *
                14.0 *
                (1.0 - _shakeAnimation.value)
            : 0.0;

        return Transform.translate(
          offset: Offset(offset, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              final isFilled = index < _pin.length;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                margin: const EdgeInsets.symmetric(horizontal: 11),
                width: isFilled ? 16 : 14,
                height: isFilled ? 16 : 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled
                      ? (_hasError
                          ? AppColors.magenta
                          : (_isUnlocked ? AppColors.cyan : Colors.white))
                      : Colors.transparent,
                  border: Border.all(
                    color: _hasError
                        ? AppColors.magenta
                        : (_isUnlocked
                            ? AppColors.cyan
                            : (isFilled
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.35))),
                    width: 1.5,
                  ),
                  boxShadow: isFilled
                      ? [
                          BoxShadow(
                            color: (_isUnlocked ? AppColors.cyan : Colors.white)
                                .withValues(alpha: 0.45),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        _buildKeyRow(['1', '2', '3'], ['', 'ABC', 'DEF']),
        const SizedBox(height: 12),
        _buildKeyRow(['4', '5', '6'], ['GHI', 'JKL', 'MNO']),
        const SizedBox(height: 12),
        _buildKeyRow(['7', '8', '9'], ['PQRS', 'TUV', 'WXYZ']),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Face ID / Touch ID Biometric Button
            _buildBiometricActionKey(),
            const SizedBox(width: 22),
            // '0' Key
            _buildKey('0', '+'),
            const SizedBox(width: 22),
            // Delete Key
            _buildSpecialKey(
              icon: Icons.backspace_outlined,
              label: 'Delete',
              onTap: _onDelete,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeyRow(List<String> digits, List<String> subs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildKey(digits[0], subs[0]),
        const SizedBox(width: 22),
        _buildKey(digits[1], subs[1]),
        const SizedBox(width: 22),
        _buildKey(digits[2], subs[2]),
      ],
    );
  }

  Widget _buildKey(String digit, String sub) {
    return _KeypadButton(
      digit: digit,
      subText: sub,
      onTap: () => _onDigitPressed(digit),
    );
  }

  Widget _buildSpecialKey({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkResponse(
      onTap: onTap,
      radius: 34,
      splashColor: AppColors.cyan.withValues(alpha: 0.25),
      highlightColor: Colors.white.withValues(alpha: 0.1),
      child: Container(
        width: 68,
        height: 68,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.cyan, size: 26),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9.5,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KeypadButton extends StatefulWidget {
  const _KeypadButton({
    required this.digit,
    required this.subText,
    required this.onTap,
  });

  final String digit;
  final String subText;
  final VoidCallback onTap;

  @override
  State<_KeypadButton> createState() => _KeypadButtonState();
}

class _KeypadButtonState extends State<_KeypadButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.91 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isPressed
                ? AppColors.cyan.withValues(alpha: 0.30)
                : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: _isPressed
                  ? AppColors.cyan.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.15),
              width: 1.3,
            ),
            boxShadow: _isPressed
                ? [
                    BoxShadow(
                      color: AppColors.cyan.withValues(alpha: 0.40),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.digit,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w400,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              if (widget.subText.isNotEmpty)
                Text(
                  widget.subText,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                )
              else
                const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
