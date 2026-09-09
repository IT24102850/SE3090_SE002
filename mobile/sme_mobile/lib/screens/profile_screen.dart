import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/api_service_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/tenant_profile_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';

/// FR-C2: view/update the logged-in user's own profile — contact info plus
/// medical/insurance details for patients. Backed by PUT /api/auth/me.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _profilePictureUrl;
  bool _uploadingPhoto = false;
  bool _photoDirty = false;
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
    _profilePictureUrl = user?.profilePictureUrl;
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

  Future<void> _pickAndUploadPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final result = await uploadTenantMedia(
        ref.read(apiServiceProvider),
        bytes: bytes,
        fileName: picked.name,
        purpose: 'avatar',
      );
      if (!mounted) return;
      setState(() {
        _profilePictureUrl = result.url;
        _photoDirty = true;
      });
      AppSnackBar.success(context, 'Photo uploaded — remember to save.');
    } on TenantProfileRequestException catch (e) {
      // Deliberately leaves _profilePictureUrl alone: a failed upload must
      // never wipe a photo the user already has saved.
      if (mounted) AppSnackBar.error(context, e.message);
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _removePhoto() {
    setState(() {
      _profilePictureUrl = null;
      _photoDirty = true;
    });
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
          profilePictureUrl: _profilePictureUrl,
          removeProfilePicture: _photoDirty && _profilePictureUrl == null,
        );

    if (success && mounted) {
      setState(() => _photoDirty = false);
      AppSnackBar.success(context, 'Profile updated.');
    }
  }

  static String _initials(String? fullName) {
    final parts = (fullName ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
    if (parts.isEmpty) return '?';
    return parts.map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final isPatient = user?.role == 'Customer';

    return AppBackgroundScaffold(
      appBar: const GlassAppBar(title: 'My Profile'),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (auth.error != null) ...[
                  InlineErrorBanner(message: auth.error!),
                  const SizedBox(height: 16),
                ],

                // Avatar sits above the form so it reads as identity, not as
                // just another field. Works the same for a tenant Admin and a
                // Customer - PUT /auth/me is the logged-in user either way.
                _AvatarBlock(
                  photoUrl: _profilePictureUrl,
                  initials: _initials(user?.fullName),
                  uploading: _uploadingPhoto,
                  onPick: _pickAndUploadPhoto,
                  onRemove: _removePhoto,
                ),
                const SizedBox(height: 24),

                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader('Contact information'),
                      NeonInputField(
                        label: 'Full name',
                        icon: Icons.person_outline,
                        controller: _fullNameController,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      NeonInputField(
                        label: 'Email',
                        icon: Icons.email_outlined,
                        initialValue: user?.email ?? '',
                        enabled: false,
                      ),
                      const SizedBox(height: 16),
                      NeonInputField(
                        label: 'Phone',
                        icon: Icons.phone_android,
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      NeonInputField(
                        label: 'Address',
                        icon: Icons.location_on_outlined,
                        controller: _addressController,
                      ),
                    ],
                  ),
                ),

                if (isPatient) ...[
                  const SizedBox(height: 16),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader('Medical & insurance', padding: EdgeInsets.only(bottom: 4)),
                        Text('Shared with clinic staff only.', style: AppTextStyles.caption),
                        const SizedBox(height: 16),
                        NeonInputField(
                          label: 'Insurance provider',
                          icon: Icons.shield_outlined,
                          controller: _insuranceProviderController,
                        ),
                        const SizedBox(height: 16),
                        NeonInputField(
                          label: 'Insurance number',
                          icon: Icons.badge_outlined,
                          controller: _insuranceNumberController,
                        ),
                        const SizedBox(height: 16),
                        NeonInputField(
                          label: 'Medical notes',
                          hintText: 'Allergies, conditions, etc.',
                          icon: Icons.medical_information_outlined,
                          controller: _medicalNotesController,
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                NeonButton(
                  label: 'Save changes',
                  isLoading: auth.isLoading,
                  onPressed: auth.isLoading ? null : _handleSave,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar, camera badge, and the add/replace/remove controls.
class _AvatarBlock extends StatelessWidget {
  const _AvatarBlock({
    required this.photoUrl,
    required this.initials,
    required this.uploading,
    required this.onPick,
    required this.onRemove,
  });

  final String? photoUrl;
  final String initials;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.buttonGlow, blurRadius: 28, spreadRadius: -4)],
                ),
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: AppColors.iconWell,
                  backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
                  child: uploading
                      ? const AppLoader(size: 24, strokeWidth: 2.5)
                      : (photoUrl == null
                          ? Text(
                              initials,
                              style: AppTextStyles.headline.copyWith(color: AppColors.cyan),
                            )
                          : null),
                ),
              ),
              Material(
                color: AppColors.cyan,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: uploading ? null : onPick,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.photo_camera_outlined, size: 18, color: AppColors.onPrimary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Wrap, not Row: "Replace photo" + "Remove" together overflow a
          // narrow phone width, so let them fall onto a second line instead
          // of clipping.
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              GhostButton(
                label: photoUrl == null ? 'Add photo' : 'Replace photo',
                icon: Icons.upload_outlined,
                height: 42,
                expand: false,
                onPressed: uploading ? null : onPick,
              ),
              if (photoUrl != null)
                GhostButton(
                  label: 'Remove',
                  icon: Icons.delete_outline,
                  height: 42,
                  expand: false,
                  color: AppColors.danger,
                  onPressed: uploading ? null : onRemove,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
