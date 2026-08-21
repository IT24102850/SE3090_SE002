import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../models/tenant_profile_model.dart';
import '../providers/api_service_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/tenant_profile_provider.dart';
import '../theme/app_theme.dart';

const _suggestedAmenities = ['Free WiFi', 'Parking', 'Beginner Friendly', 'Equipment Rental', 'Air Conditioning', 'Wheelchair Accessible'];

/// Admin/Manager Business Profile editor - the Flutter counterpart to
/// frontend/src/features/settings/BusinessProfilePage.tsx, hitting the same
/// TenantProfileController/MediaController endpoints. Works identically for
/// every business type; nothing here is Tourism/sub-type-specific.
class BusinessProfileEditorScreen extends ConsumerStatefulWidget {
  const BusinessProfileEditorScreen({super.key});

  @override
  ConsumerState<BusinessProfileEditorScreen> createState() => _BusinessProfileEditorScreenState();
}

class _BusinessProfileEditorScreenState extends ConsumerState<BusinessProfileEditorScreen> {
  String? _logoUrl;
  String? _coverImageUrl;
  final _taglineController = TextEditingController();
  final _descriptionController = TextEditingController();
  List<String> _amenities = [];
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _websiteController = TextEditingController();
  final _instagramController = TextEditingController();
  final _facebookController = TextEditingController();
  List<BusinessHourEntry> _hours = [];

  bool _profileDirty = false;
  bool _logoDirty = false;
  bool _coverDirty = false;
  bool _uploadingLogo = false;
  bool _uploadingCover = false;
  bool _saving = false;
  bool _initialized = false;

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  List<BusinessHourEntry> _defaultHours() =>
      _days.map((d) => BusinessHourEntry(dayOfWeek: d, openTime: '09:00', closeTime: '17:00', isClosed: d == 'Sunday')).toList();

  void _hydrate(TenantProfile profile) {
    if (_initialized) return;
    _initialized = true;
    _logoUrl = profile.logoUrl;
    _coverImageUrl = profile.coverImageUrl;
    _taglineController.text = profile.shortTagline ?? '';
    _descriptionController.text = profile.description ?? '';
    _amenities = List.of(profile.amenities);
    _phoneController.text = profile.contactPhone ?? '';
    _emailController.text = profile.contactEmail ?? '';
    _websiteController.text = profile.website ?? '';
    _instagramController.text = profile.socialLinks['instagram'] ?? '';
    _facebookController.text = profile.socialLinks['facebook'] ?? '';
    _hours = profile.businessHours.isNotEmpty ? List.of(profile.businessHours) : _defaultHours();
  }

  @override
  void dispose() {
    _taglineController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _instagramController.dispose();
    _facebookController.dispose();
    super.dispose();
  }

  BusinessHourEntry? get _hoursError {
    for (final h in _hours) {
      if (!h.isClosed && h.openTime != null && h.closeTime != null && h.openTime!.compareTo(h.closeTime!) >= 0) {
        return h;
      }
    }
    return null;
  }

  void _markProfileDirty() => setState(() => _profileDirty = true);

  Future<void> _pickAndUpload(String purpose, bool isLogo) async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    setState(() {
      if (isLogo) {
        _uploadingLogo = true;
      } else {
        _uploadingCover = true;
      }
    });
    try {
      final bytes = await picked.readAsBytes();
      final dio = ref.read(apiServiceProvider);
      final result = await uploadTenantMedia(dio, bytes: bytes, fileName: picked.name, purpose: purpose);
      setState(() {
        if (isLogo) {
          _logoUrl = result.url;
          _logoDirty = true;
        } else {
          _coverImageUrl = result.url;
          _coverDirty = true;
        }
      });
      _showSnack('Image uploaded — remember to save.');
    } on TenantProfileRequestException catch (e) {
      // Deliberately does NOT touch _logoUrl/_coverImageUrl here - a failed
      // upload must never clear an already-saved image.
      _showSnack(e.message, isError: true);
    } finally {
      if (mounted) {
        setState(() {
          if (isLogo) {
            _uploadingLogo = false;
          } else {
            _uploadingCover = false;
          }
        });
      }
    }
  }

  void _addAmenity(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    if (_amenities.any((a) => a.toLowerCase() == trimmed.toLowerCase())) return; // no duplicates
    setState(() => _amenities.add(trimmed));
    _markProfileDirty();
  }

  void _removeAmenity(String value) {
    setState(() => _amenities.remove(value));
    _markProfileDirty();
  }

  void _copyMondayToWeekdays() {
    final monday = _hours.firstWhere((h) => h.dayOfWeek == 'Monday', orElse: () => _hours.first);
    setState(() {
      _hours = _hours
          .map((h) => ['Tuesday', 'Wednesday', 'Thursday', 'Friday'].contains(h.dayOfWeek)
              ? BusinessHourEntry(dayOfWeek: h.dayOfWeek, openTime: monday.openTime, closeTime: monday.closeTime, isClosed: monday.isClosed)
              : h)
          .toList();
    });
    _markProfileDirty();
  }

  void _updateHour(String day, {String? openTime, String? closeTime, bool? isClosed}) {
    setState(() {
      _hours = _hours
          .map((h) => h.dayOfWeek == day
              ? BusinessHourEntry(
                  dayOfWeek: h.dayOfWeek,
                  openTime: openTime ?? h.openTime,
                  closeTime: closeTime ?? h.closeTime,
                  isClosed: isClosed ?? h.isClosed,
                )
              : h)
          .toList();
    });
    _markProfileDirty();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? AppColors.danger : null),
    );
  }

  Future<void> _save(String tenantId) async {
    if (_hoursError != null) {
      _showSnack('${_hoursError!.dayOfWeek}: open time must be before close time.', isError: true);
      return;
    }
    setState(() => _saving = true);
    final dio = ref.read(apiServiceProvider);
    try {
      if (_logoDirty && _logoUrl != null) await setTenantLogo(dio, tenantId, _logoUrl!);
      if (_coverDirty && _coverImageUrl != null) await setTenantCoverImage(dio, tenantId, _coverImageUrl!);
      if (_profileDirty) {
        await updateTenantProfileFields(
          dio,
          tenantId,
          description: _descriptionController.text,
          shortTagline: _taglineController.text,
          amenities: _amenities,
          contactPhone: _phoneController.text,
          contactEmail: _emailController.text,
          website: _websiteController.text,
          socialLinks: {
            if (_instagramController.text.trim().isNotEmpty) 'instagram': _instagramController.text.trim(),
            if (_facebookController.text.trim().isNotEmpty) 'facebook': _facebookController.text.trim(),
          },
          businessHours: _hours,
        );
      }
      setState(() {
        _profileDirty = false;
        _logoDirty = false;
        _coverDirty = false;
      });
      ref.invalidate(tenantProfileProvider(tenantId));
      _showSnack('Business profile saved.');
    } on TenantProfileRequestException catch (e) {
      _showSnack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantId = ref.watch(authProvider).user?.tenantId ?? '';
    final profileAsync = ref.watch(tenantProfileProvider(tenantId));
    final anyDirty = _profileDirty || _logoDirty || _coverDirty;
    final anyUploading = _uploadingLogo || _uploadingCover;

    return Scaffold(
      appBar: AppBar(title: const Text('Business Profile')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load your business profile.'),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => ref.invalidate(tenantProfileProvider(tenantId)), child: const Text('Retry')),
              ],
            ),
          ),
        ),
        data: (profile) {
          _hydrate(profile);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              _sectionCard(
                title: 'Logo & Cover image',
                child: Row(
                  children: [
                    Expanded(
                      child: _UploadZone(
                        label: 'Logo',
                        imageUrl: _logoUrl,
                        uploading: _uploadingLogo,
                        round: true,
                        onTap: () => _pickAndUpload('logo', true),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _UploadZone(
                        label: 'Cover image',
                        imageUrl: _coverImageUrl,
                        uploading: _uploadingCover,
                        round: false,
                        onTap: () => _pickAndUpload('cover', false),
                      ),
                    ),
                  ],
                ),
              ),
              _GallerySection(tenantId: tenantId, galleryImageUrls: profile.galleryImageUrls),
              _sectionCard(
                title: 'About',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _taglineController,
                      maxLength: 100,
                      decoration: const InputDecoration(labelText: 'Tagline', hintText: 'e.g. PADI 5-Star Dive Center'),
                      onChanged: (_) => _markProfileDirty(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descriptionController,
                      maxLength: 5000,
                      maxLines: 5,
                      decoration: const InputDecoration(labelText: 'Description'),
                      onChanged: (_) => _markProfileDirty(),
                    ),
                  ],
                ),
              ),
              _sectionCard(
                title: 'Amenities',
                child: _AmenityInput(amenities: _amenities, onAdd: _addAmenity, onRemove: _removeAmenity),
              ),
              _sectionCard(
                title: 'Contact & Hours',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone'), onChanged: (_) => _markProfileDirty()),
                    const SizedBox(height: 8),
                    TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email'), onChanged: (_) => _markProfileDirty()),
                    const SizedBox(height: 8),
                    TextField(controller: _websiteController, decoration: const InputDecoration(labelText: 'Website'), onChanged: (_) => _markProfileDirty()),
                    const SizedBox(height: 8),
                    TextField(controller: _instagramController, decoration: const InputDecoration(labelText: 'Instagram'), onChanged: (_) => _markProfileDirty()),
                    const SizedBox(height: 8),
                    TextField(controller: _facebookController, decoration: const InputDecoration(labelText: 'Facebook'), onChanged: (_) => _markProfileDirty()),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Business hours', style: TextStyle(fontWeight: FontWeight.bold)),
                        TextButton(onPressed: _copyMondayToWeekdays, child: const Text('Copy Monday to weekdays')),
                      ],
                    ),
                    ..._hours.map((h) => _HourEditorRow(entry: h, onChange: _updateHour)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: (!anyDirty || _saving || anyUploading) ? null : () => _save(tenantId),
                  child: _saving ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Text('Save changes'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: GlassStyle.elevatedCard(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _UploadZone extends StatelessWidget {
  final String label;
  final String? imageUrl;
  final bool uploading;
  final bool round;
  final VoidCallback onTap;

  const _UploadZone({required this.label, required this.imageUrl, required this.uploading, required this.round, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: uploading ? null : onTap,
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(round ? 50 : 12),
              border: Border.all(color: Colors.grey.shade300, width: 2, style: BorderStyle.solid),
              color: Colors.grey.shade100,
              image: imageUrl != null ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover) : null,
            ),
            child: uploading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : (imageUrl == null ? Icon(Icons.add_photo_alternate_outlined, color: Colors.grey.shade500) : null),
          ),
        ),
      ],
    );
  }
}

class _GallerySection extends ConsumerStatefulWidget {
  final String tenantId;
  final List<String> galleryImageUrls;
  const _GallerySection({required this.tenantId, required this.galleryImageUrls});

  @override
  ConsumerState<_GallerySection> createState() => _GallerySectionState();
}

class _GallerySectionState extends ConsumerState<_GallerySection> {
  bool _uploading = false;

  Future<void> _addPhotos() async {
    final picker = ImagePicker();
    final List<XFile> picked = await picker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return;

    setState(() => _uploading = true);
    final dio = ref.read(apiServiceProvider);
    try {
      for (final file in picked) {
        final bytes = await file.readAsBytes();
        final result = await uploadTenantMedia(dio, bytes: bytes, fileName: file.name, purpose: 'gallery');
        await addTenantGalleryImage(dio, widget.tenantId, result.url);
      }
      ref.invalidate(tenantProfileProvider(widget.tenantId));
    } on TenantProfileRequestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _remove(int index) async {
    final dio = ref.read(apiServiceProvider);
    try {
      await removeTenantGalleryImage(dio, widget.tenantId, index);
      ref.invalidate(tenantProfileProvider(widget.tenantId));
    } on TenantProfileRequestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // Up/down arrows chosen over drag-and-drop, matching the React editor's
  // choice - deterministic, no drag library needed.
  Future<void> _move(int index, int direction) async {
    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= widget.galleryImageUrls.length) return;
    final reordered = List<String>.of(widget.galleryImageUrls);
    final item = reordered.removeAt(index);
    reordered.insert(newIndex, item);
    final dio = ref.read(apiServiceProvider);
    try {
      await reorderTenantGalleryImages(dio, widget.tenantId, reordered);
      ref.invalidate(tenantProfileProvider(widget.tenantId));
    } on TenantProfileRequestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: GlassStyle.elevatedCard(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Gallery', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: _uploading ? null : _addPhotos,
                icon: _uploading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add, size: 18),
                label: const Text('Add photos'),
              ),
            ],
          ),
          if (widget.galleryImageUrls.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No photos yet.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: widget.galleryImageUrls.length,
              itemBuilder: (context, i) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(widget.galleryImageUrls[i], fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => _remove(i),
                        child: const CircleAvatar(radius: 11, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 13, color: Colors.white)),
                      ),
                    ),
                    Positioned(
                      bottom: 2,
                      left: 2,
                      child: Row(
                        children: [
                          _arrowButton(Icons.arrow_upward, i > 0, () => _move(i, -1)),
                          const SizedBox(width: 2),
                          _arrowButton(Icons.arrow_downward, i < widget.galleryImageUrls.length - 1, () => _move(i, 1)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _arrowButton(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: CircleAvatar(
        radius: 11,
        backgroundColor: enabled ? Colors.black54 : Colors.black26,
        child: Icon(icon, size: 12, color: Colors.white),
      ),
    );
  }
}

class _AmenityInput extends StatefulWidget {
  final List<String> amenities;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  const _AmenityInput({required this.amenities, required this.onAdd, required this.onRemove});

  @override
  State<_AmenityInput> createState() => _AmenityInputState();
}

class _AmenityInputState extends State<_AmenityInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.amenities
              .map((a) => Chip(
                    label: Text(a, style: const TextStyle(fontSize: 12)),
                    onDeleted: () => widget.onRemove(a),
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          decoration: const InputDecoration(hintText: 'Type an amenity and press enter…'),
          onSubmitted: (value) {
            widget.onAdd(value);
            _controller.clear();
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _suggestedAmenities
              .where((s) => !widget.amenities.contains(s))
              .map((s) => ActionChip(label: Text('+ $s', style: const TextStyle(fontSize: 11)), onPressed: () => widget.onAdd(s)))
              .toList(),
        ),
      ],
    );
  }
}

class _HourEditorRow extends StatelessWidget {
  final BusinessHourEntry entry;
  final void Function(String day, {String? openTime, String? closeTime, bool? isClosed}) onChange;
  const _HourEditorRow({required this.entry, required this.onChange});

  Future<void> _pickTime(BuildContext context, bool isOpen) async {
    final current = (isOpen ? entry.openTime : entry.closeTime) ?? '09:00';
    final parts = current.split(':');
    final initial = TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final formatted = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    onChange(entry.dayOfWeek, openTime: isOpen ? formatted : null, closeTime: isOpen ? null : formatted);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(entry.dayOfWeek, style: const TextStyle(fontSize: 12.5))),
          Checkbox(value: entry.isClosed, onChanged: (v) => onChange(entry.dayOfWeek, isClosed: v ?? false), visualDensity: VisualDensity.compact),
          const Text('Closed', style: TextStyle(fontSize: 11)),
          const Spacer(),
          if (!entry.isClosed) ...[
            TextButton(onPressed: () => _pickTime(context, true), child: Text(entry.openTime ?? '09:00', style: const TextStyle(fontSize: 12))),
            const Text('–', style: TextStyle(fontSize: 12)),
            TextButton(onPressed: () => _pickTime(context, false), child: Text(entry.closeTime ?? '17:00', style: const TextStyle(fontSize: 12))),
          ],
        ],
      ),
    );
  }
}
