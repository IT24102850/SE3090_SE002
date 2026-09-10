import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/unify_auth/orbit_hero.dart';
import '../../widgets/unify_auth/social_sign_in_row.dart';
import '../../widgets/unify_auth/unify_wordmark.dart';
import '../customer/book_business_list_screen.dart';
import '../register_screen.dart';

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
  const UnifyLoginScreen({super.key});

  @override
  ConsumerState<UnifyLoginScreen> createState() => _UnifyLoginScreenState();
}

class _UnifyLoginScreenState extends ConsumerState<UnifyLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Failures surface through auth.error, which the card renders inline.
    await ref.read(authProvider.notifier).login(
          _emailController.text.trim(),
          _passwordController.text,
        );
  }

  void _openRegister() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  void _openBrowse() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BookBusinessListScreen()),
    );
  }

  void _showComingSoon([String? provider]) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            provider == null ? 'Coming soon' : '$provider sign-in — coming soon',
          ),
          backgroundColor: AppColors.inputFill,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
            side: const BorderSide(color: AppColors.glassBorder),
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
                      children: [
                        SizedBox(height: 24 * m.gap),
                        UnifyWordmark(fontSize: m.wordmark),
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
                        if (!tooShort)
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, slack) {
                                final size = math.min(
                                  math.min(slack.maxHeight - 8, slack.maxWidth * 0.82),
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
                          SizedBox(height: 16 * m.gap),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _buildCard(m),
                        ),
                        SizedBox(height: 12 * m.gap),
                        // Customers could browse the public business list from
                        // the old landing screen without an account. This screen
                        // replaced it, so that route keeps an entry point here.
                        _TextLink(
                          onTap: _openBrowse,
                          child: Text(
                            'Browse businesses without an account',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                              decoration: TextDecoration.underline,
                              decorationColor:
                                  Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                        SizedBox(height: 8 * m.gap),
                      ],
                    );

                    // The one case that still has to scroll: the keyboard eats
                    // roughly half the viewport, and no amount of compressing
                    // keeps the password field reachable under it.
                    if (!keyboardOpen && !tooShort) return column;
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

  /// [m] carries the viewport-derived compression. The controls keep their
  /// real sizes - only the air between them and the display type give - so a
  /// short screen loses whitespace, not legibility or tap targets.
  Widget _buildCard(_Metrics m) {
    final auth = ref.watch(authProvider);
    final gap = m.gap;

    return GlassCard(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: m.cardPadding),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            SizedBox(height: 6 * gap),
            const Text(
              'Sign in to your workspace',
              style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
            ),
            SizedBox(height: 24 * gap),

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
                onTap: () => _showComingSoon('Password reset'),
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
            SizedBox(height: 18 * gap),

            const Center(
              child: Text(
                'Or continue with',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ),
            SizedBox(height: 14 * gap),

            SocialSignInRow(onProviderTap: _showComingSoon),
            SizedBox(height: 20 * gap),

            Center(
              child: _TextLink(
                onTap: _openRegister,
                child: const Text.rich(
                  TextSpan(
                    text: 'New to Unify? ',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                    children: [
                      TextSpan(
                        text: 'Create account',
                        style: TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
