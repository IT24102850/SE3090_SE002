import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../services/secure_storage_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/unify_auth/orbit_hero.dart';
import '../../widgets/unify_auth/unify_logo_mark.dart';
import '../../widgets/unify_auth/unify_wordmark.dart';
import '../customer/book_business_list_screen.dart';
import '../register_screen.dart';
import '../customer/customer_register_screen.dart';
import 'password_recovery_screen.dart';
import '../../widgets/unify_auth/ios_lock_glyph.dart';
import '../../widgets/unify_auth/ios_passcode_pad.dart';

/// The app's first screen for a signed-out visitor: sign in to Unify —
/// Enterprise Management System.
///
/// One column over a full-bleed backdrop: wordmark, the orbiting hero
/// sculpture, then a frosted card carrying the form. It is sized to the
/// viewport rather than scrolled - the hero takes the leftover space and the
/// spacing tightens on short screens, so everything fits on one screen. The
/// only exception is when the keyboard is up, where scrolling is the only way
/// to keep the password field reachable.
///
/// On success nothing here navigates — main.dart watches [authProvider] and
/// swaps the app's home for the dashboard (or profile setup) as soon as the
/// token lands.
class UnifyLoginScreen extends ConsumerStatefulWidget {
  const UnifyLoginScreen({super.key, this.onBackToWelcome});

  final VoidCallback? onBackToWelcome;

  @override
  ConsumerState<UnifyLoginScreen> createState() => _UnifyLoginScreenState();
}

class _UnifyLoginScreenState extends ConsumerState<UnifyLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _usePinMode = true;
  bool _hasConfiguredPin = false;
  bool _canQuickUnlock = false;
  bool _isSigningIn = false;

  @override
  void initState() {
    super.initState();
    Future.wait([
      SecureStorageService.hasPin(),
      SecureStorageService.getToken(),
      SecureStorageService.getUser(),
    ]).then((values) {
      final canQuickUnlock = values[0] as bool &&
          (values[1] as String?)?.isNotEmpty == true &&
          values[2] != null;
      if (mounted) {
        setState(() {
          _hasConfiguredPin = values[0] as bool;
          _canQuickUnlock = canQuickUnlock;
        });
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSigningIn = true);
    // Failures surface through auth.error, which the card renders inline.
    await ref.read(authProvider.notifier).login(
          _emailController.text.trim(),
          _passwordController.text,
        );
    if (mounted) setState(() => _isSigningIn = false);
  }

  void _openRegister() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  // A customer account is global - no business to pick - so it has its own
  // entry point here rather than only from a business's page.
  void _openCustomerRegister() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CustomerRegisterScreen()),
    );
  }

  void _openBrowse() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BookBusinessListScreen()),
    );
  }

  void _openPasswordRecovery() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PasswordRecoveryScreen(
          initialEmail: _emailController.text.trim(),
        ),
      ),
    );
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your work email';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').isEmpty) return 'Enter your password';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

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
          // Translucent, not opaque: taps on blank space dismiss the keyboard
          // while taps on the fields and buttons still reach them.
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            // Expand, so the backdrop covers the whole viewport: left to size
            // itself the Stack shrink-wraps the scroll view, and on a tall
            // screen where the content does not fill the height the Scaffold
            // colour shows through in a band under the card.
            fit: StackFit.expand,
            children: [
              const Positioned.fill(child: AppBackground(showParticles: true)),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Sized to the viewport rather than scrolled. The card
                    // is the immovable part (~600px of fields, button and
                    // links), so compression is continuous rather than a
                    // binary breakpoint: every gap, the card padding and the
                    // display type scale with how much height there is, and
                    // the hero soaks up whatever is left.
                    //
                    // Measured floor is ~700dp - below that the card alone
                    // cannot fit, and scrolling beats clipping the form.
                    final height = constraints.maxHeight;
                    final tooShort = height < _minFittableHeight;
                    final t = ((height - 700) / 240).clamp(0.0, 1.0);
                    final m = _Metrics(
                      gap: 0.46 + 0.39 * t,
                      cardPadding: 14 + 18 * t,
                      wordmark: 32 + 12 * t,
                      tagline: 11.5 + 2.5 * t,
                      title: 22 + 6 * t,
                    );

                    final column = Column(
                      mainAxisSize:
                          _usePinMode ? MainAxisSize.min : MainAxisSize.max,
                      children: [
                        if (widget.onBackToWelcome != null)
                          GestureDetector(
                            onTap: widget.onBackToWelcome,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 4),
                              child: Column(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 4.5,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Swipe down to lock',
                                    style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        SizedBox(height: (widget.onBackToWelcome != null ? 8 : 24) * m.gap),
                        // Brand lockup: the official mark beside the
                        // wordmark, not above it - a horizontal lockup adds
                        // no height, and height is the one thing this layout
                        // has none to spare. The tile matches the wordmark's
                        // cap height so the two read as one unit.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            UnifyLogoMark(size: m.wordmark * 0.98),
                            SizedBox(width: m.wordmark * 0.3),
                            UnifyWordmark(fontSize: m.wordmark),
                          ],
                        ),
                        SizedBox(height: 8 * m.gap),
                        Text(
                          'Enterprise Management System',
                          style: TextStyle(
                            fontSize: m.tagline,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 1.5,
                            color: Colors.white.withValues(alpha: 0.70),
                          ),
                        ),

                        // The slack. Caps at the 340 design size on a tall
                        // screen, shrinks on a short one, and drops out
                        // entirely rather than forcing an overflow.
                        if (!tooShort && !_usePinMode)
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, slack) {
                                final size = math.min(
                                  math.min(slack.maxHeight - 8,
                                      slack.maxWidth * 0.82),
                                  340.0,
                                );
                                if (size < _minHeroSize) {
                                  return const SizedBox.shrink();
                                }
                                return Center(child: OrbitHero(size: size));
                              },
                            ),
                          )
                        else
                          SizedBox(height: (_usePinMode ? 8 : 16) * m.gap),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _buildCard(m),
                        ),
                        SizedBox(height: 12 * m.gap),
                        // Customers could browse the public business list from
                        // the old landing screen without an account. This screen
                        // replaced it, so that route keeps an entry point here.
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              onTap: _openBrowse,
                              borderRadius: BorderRadius.circular(18),
                              child: Ink(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 15,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.glassFill,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: AppColors.cyan.withValues(alpha: 0.24),
                                  ),
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.cyan.withValues(alpha: 0.08),
                                      AppColors.violet.withValues(alpha: 0.08),
                                    ],
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: AppColors.cyan.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: const Icon(
                                        Icons.explore_rounded,
                                        size: 19,
                                        color: AppColors.cyan,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'Browse businesses without an account',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textBody,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 17,
                                      color: AppColors.cyan,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 8 * m.gap),
                      ],
                    );

                    // The one case that still has to scroll: the keyboard eats
                    // roughly half the viewport, and no amount of compressing
                    // keeps the password field reachable under it.
                    // The passcode pad is taller than the email form. Keep
                    // the entire lock view reachable on compact phones rather
                    // than letting the keypad/status banner overflow.
                    // The PIN page has a fixed-height keypad and can exceed
                    // the viewport even when the device reports a tall logical
                    // height. Scroll its natural content directly; don't put
                    // it through IntrinsicHeight or a flex spacer.
                    if (_usePinMode) {
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: column,
                      );
                    }
                    if (!keyboardOpen && !tooShort) {
                      return column;
                    }
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: IntrinsicHeight(child: column),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _usePinMode = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: !_usePinMode
                      ? AppColors.cyan.withValues(alpha: 0.22)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: !_usePinMode
                      ? Border.all(color: AppColors.cyan.withValues(alpha: 0.45))
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.mail_outline_rounded,
                      size: 15,
                      color:
                          !_usePinMode ? AppColors.cyan : AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Work Email',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color:
                            !_usePinMode ? Colors.white : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _usePinMode = true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _usePinMode
                      ? AppColors.cyan.withValues(alpha: 0.22)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: _usePinMode
                      ? Border.all(color: AppColors.cyan.withValues(alpha: 0.45))
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.dialpad_rounded,
                      size: 15,
                      color: _usePinMode ? AppColors.cyan : AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Quick PIN',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _usePinMode ? Colors.white : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// [m] carries the viewport-derived compression. The controls keep their
  /// real sizes - only the air between them and the display type give - so a
  /// short screen loses whitespace, not legibility or tap targets.
  Widget _buildCard(_Metrics m) {
    final auth = ref.watch(authProvider);
    final gap = m.gap;

    return GlassCard(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: m.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildModeToggle(),
          if (_usePinMode)
            Column(
              children: [
                IosPasscodePad(
                  title: 'Security Passcode',
                  subtitle: _canQuickUnlock
                      ? 'Scan Biometrics or enter your 4-digit PIN'
                      : 'Enter your PIN, or choose Work Email if you signed out.',
                  onPinSubmit: (pin) async =>
                      ref.read(authProvider.notifier).unlockWithPin(pin),
                  onBiometricSubmit: () async =>
                      ref.read(authProvider.notifier).unlockWithBiometrics(),
                ),
                if (!_hasConfiguredPin) _buildPinUnavailableMessage(),
                if (auth.error != null) ...[
                  const SizedBox(height: 12),
                  _ErrorBanner(message: auth.error!),
                ],
              ],
            )
          else
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome Back',
                            style: TextStyle(
                              fontSize: m.title,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              height: 1.1,
                            ),
                          ),
                          SizedBox(height: 4 * gap),
                          const Text(
                            'Sign in to your workspace',
                            style: TextStyle(
                                fontSize: 14, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      IosLockGlyph(
                        isUnlocked: _isSigningIn || auth.isAuthenticated,
                        size: 26,
                      ),
                    ],
                  ),
                  SizedBox(height: 20 * gap),
            NeonInputField(
              label: 'Email',
              hintText: 'name@company.com',
              icon: Icons.mail_outline,
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              validator: _validateEmail,
            ),
            SizedBox(height: 18 * gap),
            NeonInputField(
              label: 'Password',
              hintText: '••••••••',
              icon: Icons.lock_outline,
              controller: _passwordController,
              obscurable: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              validator: _validatePassword,
              onFieldSubmitted: (_) => _handleSignIn(),
            ),
            if (auth.error != null) ...[
              SizedBox(height: 14 * gap),
              _ErrorBanner(message: auth.error!),
            ],
            SizedBox(height: 22 * gap),
            NeonButton(
              label: 'Sign In',
              isLoading: auth.isLoading,
              onPressed: _handleSignIn,
            ),
            SizedBox(height: 14 * gap),
            Center(
              child: _TextLink(
                onTap: _openPasswordRecovery,
                child: const Text(
                  'Forgot Password?',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            SizedBox(height: 20 * gap),

            // Both ways in on one row. There are two kinds of sign-up now -
            // a customer account, which belongs to no business, and business
            // onboarding - but this layout compresses to fit rather than
            // scrolling, and a second stacked line overflows a 360x740 phone
            // (test/unify_login_screen_test.dart pins that).
            // scaleDown keeps it to one line on a narrow phone: wrapping to
            // two is what tips the column into overflow.
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TextLink(
                      onTap: _openCustomerRegister,
                      child: const Text(
                        'Sign up to book',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.cyan,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        '·',
                        style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                      ),
                    ),
                    _TextLink(
                      onTap: _openRegister,
                      child: const Text(
                        'Register a business',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.cyan,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  ),
);
}

  Widget _buildPinUnavailableMessage() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
      child: Column(
        children: [
          const Icon(Icons.lock_outline_rounded,
              color: AppColors.cyan, size: 34),
          const SizedBox(height: 12),
          Text(
            _hasConfiguredPin
                ? 'Your PIN is saved. Sign in with your work email to create a session; the PIN will unlock it next time.'
                : 'No Quick PIN is set up. Sign in with your work email, then set one under Security.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() => _usePinMode = false),
            child: const Text('Continue with Work Email'),
          ),
        ],
      ),
    );
  }
}

/// Sign-in failures from [authProvider], shown in the card rather than as a
/// snackbar — the message belongs next to the fields it is about.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.magenta.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.magenta.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.magenta, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

}

/// How hard the layout is squeezing, derived once per build from the viewport
/// height and threaded through the column and the card so both compress in
/// step.
class _Metrics {
  const _Metrics({
    required this.gap,
    required this.cardPadding,
    required this.wordmark,
    required this.tagline,
    required this.title,
  });

  /// Multiplier applied to every vertical gap.
  final double gap;
  final double cardPadding;
  final double wordmark;
  final double tagline;
  final double title;
}

/// Below this the card alone is taller than the viewport, so the screen
/// scrolls instead of clipping the form. Measured, not guessed: at full
/// compression the card plus branding plus footer needs about this much.
const double _minFittableHeight = 720;

/// A hero smaller than this reads as a smudge rather than a sculpture, so it
/// is dropped instead.
const double _minHeroSize = 52;

/// A tap target around inline text. Padded out to a comfortable hit area —
/// bare [GestureDetector]s around 14pt text are a hair thin to hit.
class _TextLink extends StatelessWidget {
  const _TextLink({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      splashColor: AppColors.cyan.withValues(alpha: 0.10),
      highlightColor: AppColors.cyan.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: child,
      ),
    );
  }
}
