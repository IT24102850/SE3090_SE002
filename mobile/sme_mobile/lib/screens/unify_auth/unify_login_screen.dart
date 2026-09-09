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
/// One scrolling column over a full-bleed backdrop: wordmark, the orbiting
/// hero sculpture, then a frosted card carrying the form. Everything scrolls
/// as a unit so the keyboard pushes the whole composition up rather than
/// clipping the card.
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
    final media = MediaQuery.of(context);
    // The hero is the one element that has to give ground on small phones —
    // capped at its design size, shrunk proportionally below that.
    final heroSize = math.min(340.0, media.size.width * 0.82);

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
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 28),
                      const UnifyWordmark(),
                      const SizedBox(height: 10),
                      Text(
                        'Enterprise Management System',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 1.5,
                          color: Colors.white.withValues(alpha: 0.70),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OrbitHero(size: heroSize),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _buildCard(),
                      ),
                      const SizedBox(height: 20),
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
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    final auth = ref.watch(authProvider);

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Welcome Back',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Sign in to your workspace',
              style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),

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
            const SizedBox(height: 20),

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
              const SizedBox(height: 16),
              _ErrorBanner(message: auth.error!),
            ],
            const SizedBox(height: 26),

            NeonButton(
              label: 'Sign In',
              isLoading: auth.isLoading,
              onPressed: _handleSignIn,
            ),
            const SizedBox(height: 18),

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
            const SizedBox(height: 24),

            const Center(
              child: Text(
                'Or continue with',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 18),

            SocialSignInRow(onProviderTap: _showComingSoon),
            const SizedBox(height: 26),

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: child,
      ),
    );
  }
}
