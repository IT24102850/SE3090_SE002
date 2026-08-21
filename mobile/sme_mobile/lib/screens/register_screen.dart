import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tourism_subtype.dart';
import '../providers/auth_provider.dart';
import '../screens/dashboard_screen.dart';
import '../theme/app_theme.dart';

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
  bool _obscurePassword = true;

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

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Register Business'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 56, 24, 44),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF065F46), Color(0xFF059669)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: const Icon(Icons.add_business_rounded, size: 36, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Grow with SME Platform',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Set up your business account in a couple of minutes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                    ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Error banner
                        if (auth.error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    color: Colors.red.shade700, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    auth.error!,
                                    style: TextStyle(
                                        color: Colors.red.shade700, fontSize: 13),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () =>
                                      ref.read(authProvider.notifier).clearError(),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // ── Business Information ─────────────────
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: GlassStyle.elevatedCard(radius: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Business Information',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _businessNameController,
                                textInputAction: TextInputAction.next,
                                decoration: _decoration('Business Name *', Icons.business),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: _businessType,
                                decoration: _decoration('Business Type *', Icons.category),
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
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  value: _subType,
                                  decoration: _decoration('Tourism Sub-Type *', Icons.travel_explore),
                                  hint: const Text('Select tourism sub-type...'),
                                  items: kTourismSubTypeLabels
                                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                                      .toList(),
                                  onChanged: (v) => setState(() => _subType = v),
                                  validator: (v) => (_businessType == 'Tourism' && (v == null || v.isEmpty))
                                      ? 'Required for Tourism businesses'
                                      : null,
                                ),
                              ],
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _addressController,
                                textInputAction: TextInputAction.next,
                                decoration:
                                    _decoration('Address', Icons.location_on_outlined),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                decoration:
                                    _decoration('Business Phone', Icons.phone_outlined),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Admin Account ────────────────────────
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: GlassStyle.elevatedCard(radius: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Admin Account',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _adminFullNameController,
                                textInputAction: TextInputAction.next,
                                decoration: _decoration('Full Name *', Icons.person_outline),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _adminEmailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                decoration:
                                    _decoration('Admin Email *', Icons.email_outlined),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Required';
                                  if (!v.contains('@')) return 'Enter a valid email';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _adminPasswordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Password *',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'Required';
                                  if (v.length < 6) return 'At least 6 characters';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _adminPhoneController,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.done,
                                decoration:
                                    _decoration('Phone (optional)', Icons.phone_android),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Submit
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: auth.isLoading ? null : _handleRegister,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  const Color(0xFF059669).withValues(alpha: 0.6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: auth.isLoading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Create Business Account',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: auth.isLoading
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('Already have an account? Sign in'),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
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
