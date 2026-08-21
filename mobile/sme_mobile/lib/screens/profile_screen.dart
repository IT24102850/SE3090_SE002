import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

/// FR-C2: view/update the logged-in user's own profile — contact info plus
/// medical/insurance details for patients. Backed by PUT /api/auth/me.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _insuranceProviderController;
  late final TextEditingController _insuranceNumberController;
  late final TextEditingController _medicalNotesController;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _fullNameController = TextEditingController(text: user?.fullName ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
    _addressController = TextEditingController(text: user?.address ?? '');
    _insuranceProviderController = TextEditingController(text: user?.insuranceProvider ?? '');
    _insuranceNumberController = TextEditingController(text: user?.insuranceNumber ?? '');
    _medicalNotesController = TextEditingController(text: user?.medicalNotes ?? '');
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _insuranceProviderController.dispose();
    _insuranceNumberController.dispose();
    _medicalNotesController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final success = await ref.read(authProvider.notifier).updateProfile(
          fullName: _fullNameController.text.trim(),
          phone: _phoneController.text.trim(),
          address: _addressController.text.trim(),
          insuranceProvider: _insuranceProviderController.text.trim(),
          insuranceNumber: _insuranceNumberController.text.trim(),
          medicalNotes: _medicalNotesController.text.trim(),
        );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated.'), backgroundColor: AppColors.success),
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
    final user = auth.user;
    final isPatient = user?.role == 'Customer';

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                      Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(auth.error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                    ],
                  ),
                ),
              ],
              Container(
                padding: const EdgeInsets.all(18),
                decoration: GlassStyle.elevatedCard(radius: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Contact information', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _fullNameController,
                      decoration: _decoration('Full name', Icons.person_outline),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: user?.email ?? '',
                      enabled: false,
                      decoration: _decoration('Email', Icons.email_outlined),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _decoration('Phone', Icons.phone_android),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressController,
                      decoration: _decoration('Address', Icons.location_on_outlined),
                    ),
                  ],
                ),
              ),
              if (isPatient) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: GlassStyle.elevatedCard(radius: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Medical & insurance', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Shared with clinic staff only.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _insuranceProviderController,
                        decoration: _decoration('Insurance provider', Icons.shield_outlined),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _insuranceNumberController,
                        decoration: _decoration('Insurance number', Icons.badge_outlined),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _medicalNotesController,
                        maxLines: 3,
                        decoration: _decoration('Medical notes (allergies, conditions, etc.)', Icons.medical_information_outlined),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: auth.isLoading ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: auth.isLoading
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('Save changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
