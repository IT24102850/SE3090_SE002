import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tourism_subtype.dart';
import '../providers/auth_provider.dart';
import '../screens/dashboard_screen.dart';
import '../theme/app_theme.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _adminFullNameController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  final _adminPhoneController = TextEditingController();

  String _businessType = 'Clinic';
  String? _subType;

  static const _businessTypes = [
    'Clinic',
    'Restaurant',
    'Gym',
    'School',
    'RealEstate',
    'Tourism',
    'General',
  ];

  @override
  void dispose() {
    _businessNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _adminFullNameController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    _adminPhoneController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final success = await ref.read(authProvider.notifier).register(
          businessName: _businessNameController.text.trim(),
          businessType: _businessType,
          address: _addressController.text.trim(),
          phone: _phoneController.text.trim(),
          adminEmail: _adminEmailController.text.trim(),
          adminPassword: _adminPasswordController.text,
          adminFullName: _adminFullNameController.text.trim(),
          adminPhone: _adminPhoneController.text.trim().isEmpty
              ? null
              : _adminPhoneController.text.trim(),
          subType: _businessType == 'Tourism' ? _subType : null,
        );

    if (success && mounted) {
      // Pop all routes and go to dashboard
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
        (route) => false,
      );
    }
  }

  /// Dropdowns can't use [NeonInputField] (it wraps a TextFormField), so they
  /// borrow the same decoration to stay visually identical to the text fields
  /// stacked around them.
  InputDecoration _dropdownDecoration(IconData icon) {
    OutlineInputBorder border(Color color, {double width = 1}) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      filled: true,
      fillColor: AppColors.inputFill,
      prefixIcon: Icon(icon, color: AppColors.iconSecondary, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: border(AppColors.inputBorder),
      focusedBorder: border(AppColors.cyan, width: 1.6),
      errorBorder: border(AppColors.danger),
      focusedErrorBorder: border(AppColors.danger, width: 1.6),
      errorStyle: AppTextStyles.caption.copyWith(color: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return AppBackgroundScaffold(
      showParticles: true,
      appBar: const GlassAppBar(title: 'Register Business'),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _RegisterHero(),
                const SizedBox(height: 28),

                if (auth.error != null) ...[
                  InlineErrorBanner(
                    message: auth.error!,
                    onDismiss: () => ref.read(authProvider.notifier).clearError(),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Business Information ─────────────────
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader('Business Information'),
                      const SizedBox(height: 4),
                      NeonInputField(
                        label: 'Business Name *',
                        icon: Icons.business,
                        controller: _businessNameController,
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      Text('BUSINESS TYPE *', style: AppTextStyles.label),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _businessType,
                        decoration: _dropdownDecoration(Icons.category),
                        dropdownColor: AppColors.overlaySurface,
                        borderRadius: BorderRadius.circular(AppRadii.control),
                        style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
                        icon: const Icon(Icons.expand_more_rounded, color: AppColors.iconSecondary),
                        items: _businessTypes
                            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _businessType = v;
                              if (v != 'Tourism') _subType = null;
                            });
                          }
                        },
                      ),
                      if (_businessType == 'Tourism') ...[
                        const SizedBox(height: 16),
                        Text('TOURISM SUB-TYPE *', style: AppTextStyles.label),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: _subType,
                          decoration: _dropdownDecoration(Icons.travel_explore),
                          dropdownColor: AppColors.overlaySurface,
                          borderRadius: BorderRadius.circular(AppRadii.control),
                          style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
                          icon: const Icon(Icons.expand_more_rounded, color: AppColors.iconSecondary),
                          hint: Text('Select tourism sub-type...', style: AppTextStyles.bodyMuted),
                          items: kTourismSubTypeLabels
                              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                              .toList(),
                          onChanged: (v) => setState(() => _subType = v),
                          validator: (v) => (_businessType == 'Tourism' && (v == null || v.isEmpty))
                              ? 'Required for Tourism businesses'
                              : null,
                        ),
                      ],
                      const SizedBox(height: 16),
                      NeonInputField(
                        label: 'Address',
                        icon: Icons.location_on_outlined,
                        controller: _addressController,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      NeonInputField(
                        label: 'Business Phone',
                        icon: Icons.phone_outlined,
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Admin Account ────────────────────────
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader('Admin Account'),
                      const SizedBox(height: 4),
                      NeonInputField(
                        label: 'Full Name *',
                        icon: Icons.person_outline,
                        controller: _adminFullNameController,
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      NeonInputField(
                        label: 'Admin Email *',
                        icon: Icons.email_outlined,
                        controller: _adminEmailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (!v.contains('@')) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      NeonInputField(
                        label: 'Password *',
                        icon: Icons.lock_outline,
                        controller: _adminPasswordController,
                        obscurable: true,
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (v.length < 6) return 'At least 6 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      NeonInputField(
                        label: 'Phone (optional)',
                        icon: Icons.phone_android,
                        controller: _adminPhoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                NeonButton(
                  label: 'Create Business Account',
                  isLoading: auth.isLoading,
                  onPressed: auth.isLoading ? null : _handleRegister,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: auth.isLoading ? null : () => Navigator.of(context).pop(),
                  child: Text(
                    'Already have an account? Sign in',
                    style: AppTextStyles.body.copyWith(color: AppColors.cyan),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RegisterHero extends StatelessWidget {
  const _RegisterHero();

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
              BoxShadow(color: AppColors.buttonGlow, blurRadius: 32, spreadRadius: -8),
            ],
          ),
          child: const Icon(Icons.add_business_rounded, size: 36, color: AppColors.cyan),
        ),
        const SizedBox(height: 18),
        Text('Grow with Unify', textAlign: TextAlign.center, style: AppTextStyles.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Set up your business account in a couple of minutes.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMuted,
        ),
      ],
    );
  }
}
