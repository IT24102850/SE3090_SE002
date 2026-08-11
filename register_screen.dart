import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'dashboard_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    if (auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()));
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Register Business')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (auth.error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8)),
                    child: Text(auth.error!, style: TextStyle(color: Colors.red.shade700)),
                  ),

                const Text('Business Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _businessNameController,
                  decoration: _inputDecoration('Business Name', Icons.business),
                  validator: (v) => v?.isEmpty == true ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  value: _businessType,
                  decoration: _inputDecoration('Business Type', Icons.category),
                  items: const [
                    DropdownMenuItem(value: 'Clinic', child: Text('Clinic')),
                    DropdownMenuItem(value: 'Restaurant', child: Text('Restaurant')),
                    DropdownMenuItem(value: 'Gym', child: Text('Gym')),
                    DropdownMenuItem(value: 'School', child: Text('School')),
                    DropdownMenuItem(value: 'RealEstate', child: Text('Real Estate')),
                    DropdownMenuItem(value: 'Tourism', child: Text('Tourism')),
                    DropdownMenuItem(value: 'General', child: Text('General')),
                  ],
                  onChanged: (v) => setState(() => _businessType = v!),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _addressController,
                  decoration: _inputDecoration('Address', Icons.location_on),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _phoneController,
                  decoration: _inputDecoration('Business Phone', Icons.phone),
                ),
                const SizedBox(height: 24),

                const Text('Admin Account',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _adminFullNameController,
                  decoration: _inputDecoration('Full Name', Icons.person),
                  validator: (v) => v?.isEmpty == true ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _adminEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDecoration('Admin Email', Icons.email),
                  validator: (v) => v?.isEmpty == true ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _adminPasswordController,
                  obscureText: true,
                  decoration: _inputDecoration('Password', Icons.lock),
                  validator: (v) => v?.isEmpty == true ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _adminPhoneController,
                  decoration: _inputDecoration('Phone', Icons.phone_android),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: auth.isLoading ? null : () async {
                      if (_formKey.currentState!.validate()) {
                        await ref.read(authProvider.notifier).register(
                          businessName: _businessNameController.text.trim(),
                          businessType: _businessType,
                          address: _addressController.text.trim(),
                          phone: _phoneController.text.trim(),
                          adminEmail: _adminEmailController.text.trim(),
                          adminPassword: _adminPasswordController.text,
                          adminFullName: _adminFullNameController.text.trim(),
                          adminPhone: _adminPhoneController.text.trim(),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: auth.isLoading
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create Business Account', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}