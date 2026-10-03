import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/tenant_profile_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'ui/ui.dart';

/// The ONE shared "TripAdvisor listing" header, used by both
/// BookingDashboardScreen (Tourism tenants with a resolved sub-type) and
/// BusinessDetailScreen (every other tenant). Zero business-type-specific
/// logic lives here - it only ever renders whatever [themeColor]/[themeIcon]
/// the caller hands it (the sub-type registry's, or BusinessTypeVisual's).
///
/// Not a Sliver itself - callers wrap it in a SliverToBoxAdapter alongside
/// their own existing content slivers below it.
class BusinessProfileHeader extends StatelessWidget {
  final String businessName;
  final String? address;
  final TenantProfile? profile; // null while loading
  final bool hasError;
  final VoidCallback? onRetry;
  final Color themeColor;
  final IconData themeIcon;

  /// Injectable "current time" for testing "Open now"/"Closed now" against
  /// a fixed mock time. Defaults to DateTime.now() in production.
  final DateTime? now;

  const BusinessProfileHeader({
    super.key,
    required this.businessName,
    this.address,
    required this.profile,
    this.hasError = false,
    this.onRetry,
    required this.themeColor,
    required this.themeIcon,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    if (hasError) return _ErrorState(onRetry: onRetry);
    if (profile == null) return _SkeletonState(themeColor: themeColor);

    final p = profile!;
    final effectiveNow = now ?? DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Hero(profile: p, businessName: businessName, themeColor: themeColor, themeIcon: themeIcon),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(businessName, style: AppTextStyles.headlineSmall.copyWith(fontSize: 20)),
              if (p.shortTagline != null && p.shortTagline!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(p.shortTagline!, style: AppTextStyles.bodyMuted.copyWith(fontSize: 13)),
              ],
              if (address != null && address!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: AppColors.iconDisabled),
                    const SizedBox(width: 4),
                    Expanded(child: Text(address!, style: AppTextStyles.caption.copyWith(fontSize: 12.5))),
                  ],
                ),
              ],
              // TripAdvisor convention: never show "0.0 stars" for a
              // business with no reviews yet - hide the row entirely.
              if (p.reviewCount > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 16, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text(
                      (p.averageRating ?? 0).toStringAsFixed(1),
                      style: AppTextStyles.subtitle.copyWith(fontSize: 13),
                    ),
                    const SizedBox(width: 4),
                    Text('(${p.reviewCount})', style: AppTextStyles.caption.copyWith(fontSize: 12.5)),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (p.galleryImageUrls.isNotEmpty) ...[
          const SizedBox(height: 18),
          _GalleryStrip(imageUrls: p.galleryImageUrls),
        ],
        if ((p.description != null && p.description!.trim().isNotEmpty) || p.amenities.isNotEmpty) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _AboutSection(description: p.description, amenities: p.amenities, themeColor: themeColor),
          ),
        ],
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _ContactAndHoursSection(profile: p, now: effectiveNow, themeColor: themeColor),
        ),
        const SizedBox(height: 8),
        const Divider(color: AppColors.hairline, height: 32),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  final TenantProfile profile;
  final String businessName;
  final Color themeColor;
  final IconData themeIcon;

  const _Hero({required this.profile, required this.businessName, required this.themeColor, required this.themeIcon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Cover: real image, or a themed gradient fallback - never a
          // broken-image icon.
          Positioned.fill(
            bottom: 40,
            child: profile.coverImageUrl != null
                ? Image.network(
                    profile.coverImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _CoverFallback(themeColor: themeColor),
                  )
                : _CoverFallback(themeColor: themeColor),
          ),
          // Logo avatar, overlapping the cover's bottom edge.
          Positioned(
            left: 20,
            bottom: 0,
            child: Container(
              width: 76,
              height: 76,
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: AppColors.bgMid, shape: BoxShape.circle),
              child: ClipOval(
                child: profile.logoUrl != null
                    ? Image.network(
                        profile.logoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _LogoFallback(themeColor: themeColor, themeIcon: themeIcon),
                      )
                    : _LogoFallback(themeColor: themeColor, themeIcon: themeIcon),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  final Color themeColor;
  const _CoverFallback({required this.themeColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [themeColor, themeColor.withValues(alpha: 0.6)],
        ),
      ),
    );
  }
}

class _LogoFallback extends StatelessWidget {
  final Color themeColor;
  final IconData themeIcon;
  const _LogoFallback({required this.themeColor, required this.themeIcon});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: themeColor.withValues(alpha: 0.15),
      child: Icon(themeIcon, color: themeColor, size: 30),
    );
  }
}

class _GalleryStrip extends StatelessWidget {
  final List<String> imageUrls;
  const _GalleryStrip({required this.imageUrls});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: imageUrls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => _GalleryViewer(imageUrls: imageUrls, initialIndex: i)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              imageUrls[i],
              width: 84,
              height: 84,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 84,
                height: 84,
                color: AppColors.iconWell,
                child: const Icon(Icons.image_not_supported_outlined, color: AppColors.iconGhost),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryViewer extends StatelessWidget {
  final List<String> imageUrls;
  final int initialIndex;
  const _GalleryViewer({required this.imageUrls, required this.initialIndex});

  @override
  Widget build(BuildContext context) {
    // Deliberately black rather than the app gradient: a lightbox should put
    // nothing but the photo on screen.
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: imageUrls.length,
        itemBuilder: (context, i) => Center(
          child: InteractiveViewer(
            child: Image.network(
              imageUrls[i],
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.broken_image_outlined, color: AppColors.iconGhost, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  final String? description;
  final List<String> amenities;
  final Color themeColor;
  const _AboutSection({required this.description, required this.amenities, required this.themeColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('About'),
        if (description != null && description!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(description!, style: AppTextStyles.body.copyWith(fontSize: 13, height: 1.5)),
        ],
        if (amenities.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: amenities
                .map((a) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: themeColor.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        a,
                        style: AppTextStyles.caption.copyWith(color: themeColor, fontWeight: FontWeight.w600),
                      ),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _ContactAndHoursSection extends StatelessWidget {
  final TenantProfile profile;
  final DateTime now;
  final Color themeColor;
  const _ContactAndHoursSection({required this.profile, required this.now, required this.themeColor});

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final hasContact = [profile.contactPhone, profile.contactEmail, profile.website].any((v) => v != null && v.trim().isNotEmpty) ||
        profile.socialLinks.isNotEmpty;
    final today = profile.todaysHours(now);
    final isOpen = profile.isOpenNow(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Contact & Hours'),
        if (hasContact)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (profile.contactPhone != null && profile.contactPhone!.trim().isNotEmpty)
                _ContactChip(icon: Icons.call_outlined, label: 'Call', color: themeColor, onTap: () => _launch('tel:${profile.contactPhone}')),
              if (profile.contactEmail != null && profile.contactEmail!.trim().isNotEmpty)
                _ContactChip(icon: Icons.email_outlined, label: 'Email', color: themeColor, onTap: () => _launch('mailto:${profile.contactEmail}')),
              if (profile.website != null && profile.website!.trim().isNotEmpty)
                _ContactChip(icon: Icons.language, label: 'Website', color: themeColor, onTap: () => _launch(profile.website!)),
              ...profile.socialLinks.entries
                  .where((e) => e.value.trim().isNotEmpty)
                  .map((e) => _ContactChip(icon: Icons.share_outlined, label: e.key, color: themeColor, onTap: () => _launch(e.value))),
            ],
          ),
        if (profile.businessHours.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.access_time_rounded, size: 15, color: isOpen ? AppColors.success : AppColors.iconDisabled),
              const SizedBox(width: 6),
              Text(
                today == null ? 'Hours not set for today' : (isOpen ? 'Open now' : 'Closed now'),
                style: AppTextStyles.subtitle.copyWith(
                  fontSize: 13,
                  color: isOpen ? AppColors.success : AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...profile.businessHours.map((h) => _HourRow(entry: h, isToday: today != null && h.dayOfWeek == today.dayOfWeek)),
        ],
      ],
    );
  }
}

class _ContactChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ContactChip({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: color.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: AppTextStyles.caption.copyWith(fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _HourRow extends StatelessWidget {
  final BusinessHourEntry entry;
  final bool isToday;
  const _HourRow({required this.entry, required this.isToday});

  @override
  Widget build(BuildContext context) {
    final label = entry.isClosed ? 'Closed' : '${entry.openTime ?? '--:--'} – ${entry.closeTime ?? '--:--'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              entry.dayOfWeek,
              style: AppTextStyles.body.copyWith(
                fontSize: 12.5,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                color: isToday ? AppColors.textPrimary : AppColors.textBody,
              ),
            ),
          ),
          Text(
            label,
            style: AppTextStyles.body.copyWith(
              fontSize: 12.5,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
              color: isToday ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonState extends StatelessWidget {
  final Color themeColor;
  const _SkeletonState({required this.themeColor});

  @override
  Widget build(BuildContext context) {
    Widget box(double height, {double? width}) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.hairline),
          ),
        );

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box(160),
          box(20, width: 200),
          box(14, width: 140),
          Row(children: [box(60, width: 60), const SizedBox(width: 8), box(60, width: 60), const SizedBox(width: 8), box(60, width: 60)]),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback? onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.iconGhost),
            const SizedBox(height: 12),
            Text(
              'Could not load this business\'s profile.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              GhostButton(
                label: 'Retry',
                icon: Icons.refresh,
                height: 42,
                expand: false,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
