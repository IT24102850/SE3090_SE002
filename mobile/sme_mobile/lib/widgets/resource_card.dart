import 'package:flutter/material.dart';
import '../models/subtype_dashboard_config.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'ui/ui.dart';

/// One card representing a bookable resource (a dive trip, a room, a jeep...).
/// The fields it shows come entirely from `config.cardFields` - this widget
/// itself never changes when a new tourism sub-type is added.
class ResourceCard extends StatelessWidget {
  final Map<String, dynamic> resource;
  final SubtypeDashboardConfig config;
  final VoidCallback onBook;

  const ResourceCard({
    super.key,
    required this.resource,
    required this.config,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: AppRadii.row,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The sub-type hue survives on the dark canvas as a lit ring
              // around the icon well rather than as a pale filled circle.
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.iconWell,
                  shape: BoxShape.circle,
                  border: Border.all(color: config.themeColor.withValues(alpha: 0.55)),
                ),
                child: Icon(config.icon, color: config.themeColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  resource['name'] as String? ?? config.resourceTermSingular,
                  style: AppTextStyles.subtitle.copyWith(fontSize: 16),
                ),
              ),
              if (config.showWeatherBadge) const _WeatherBadge(),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: config.cardFields
                .where((f) => resource[f.key] != null)
                .map((f) => _buildFieldChip(f, resource[f.key]))
                .toList(),
          ),
          const SizedBox(height: 16),
          NeonButton(
            label: 'Book ${config.resourceTermSingular}',
            onPressed: onBook,
            height: 46,
          ),
        ],
      ),
    );
  }

  Widget _buildFieldChip(ResourceCardField field, dynamic value) {
    final label = field.labelTemplate.replaceAll('{value}', '$value');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(field.icon, size: 14, color: AppColors.iconDisabled),
        const SizedBox(width: 5),
        Text(label, style: AppTextStyles.caption.copyWith(fontSize: 13)),
      ],
    );
  }
}

/// Weather-dependent sub-types (diving, safari, whale watching) show this;
/// accommodation/vehicle rental don't (config.showWeatherBadge = false).
class _WeatherBadge extends StatelessWidget {
  const _WeatherBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wb_sunny, size: 12, color: AppColors.warning),
          const SizedBox(width: 4),
          Text(
            'Weather dependent',
            style: AppTextStyles.caption.copyWith(fontSize: 11, color: AppColors.warning),
          ),
        ],
      ),
    );
  }
}
