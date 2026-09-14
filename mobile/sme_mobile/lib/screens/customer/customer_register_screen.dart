import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/public_tenant_model.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ui/ui.dart';

/// FR-C1: patient self-registration, scoped to the specific clinic they were
/// browsing — the correct counterpart to [RegisterScreen], which is business
/// onboarding and creates a brand new tenant. This screen never does that;
/// it signs the caller up as a Customer of [tenant] via POST /auth/register.
class CustomerRegisterScreen extends ConsumerStatefulWidget {
  final PublicTenant tenant;
  const CustomerRegisterScreen({super.key, required this.tenant});

  @override
  ConsumerState<CustomerRegisterScreen> createState() => _CustomerRegisterScreenState();
}

class _CustomerRegisterScreenState extends ConsumerState<CustomerRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final success = await ref.read(authProvider.notifier).registerCustomer(
          tenantId: widget.tenant.id,
          fullName: _fullNameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        );

    if (success && mounted) {
      // Signed up as a customer of this specific business — hand control
      // straight back to whoever pushed this screen (the "book with X" flow).
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return AppBackgroundScaffold(
      showParticles: true,
      appBar: const GlassAppBar(title: 'Create account'),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SignUpHero(businessName: widget.tenant.businessName),
              const SizedBox(height: 28),
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (auth.error != null) ...[
                        InlineErrorBanner(
                          message: auth.error!,
                          onDismiss: () => ref.read(authProvider.notifier).clearError(),
                        ),
                        const SizedBox(height: 18),
                      ],
                      NeonInputField(
                        label: 'Full name',
                        icon: Icons.person_outline,
                        controller: _fullNameController,
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 18),
                      NeonInputField(
                        label: 'Email',
                        icon: Icons.email_outlined,
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      NeonInputField(
                        label: 'Password',
                        icon: Icons.lock_outline,
                        controller: _passwordController,
                        obscurable: true,
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (v.length < 6) return 'At least 6 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      NeonInputField(
                        label: 'Phone (optional)',
                        icon: Icons.phone_android,
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                      ),
                      const SizedBox(height: 26),
                      NeonButton(
                        label: 'Create account',
                        isLoading: auth.isLoading,
                        onPressed: auth.isLoading ? null : _handleRegister,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed:
                            auth.isLoading ? null : () => Navigator.of(context).pop(false),
                        child: Text(
                          'Already have an account? Sign in',
                          style: AppTextStyles.body.copyWith(color: AppColors.cyan),
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
}

class _SignUpHero extends StatelessWidget {
  const _SignUpHero({required this.businessName});

  final String businessName;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: const [
              BoxShadow(color: AppColors.dangerGlow, blurRadius: 32, spreadRadius: -10),
            ],
          ),
          child: const Icon(Icons.person_add_alt_1_rounded, size: 36, color: AppColors.magenta),
        ),
        const SizedBox(height: 18),
        Text(
          'Sign up with $businessName',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineSmall.copyWith(fontSize: 21),
        ),
        const SizedBox(height: 8),
        Text(
          'Create a free account to book, track, and manage your appointments.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMuted,
        ),
      ],
    );
  }
}
