import 'package:flutter/material.dart';
import '../models/subtype_dashboard_config.dart';

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
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: config.themeColor.withValues(alpha: 0.1),
                  child: Icon(config.icon, color: config.themeColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    resource['name'] as String? ?? config.resourceTermSingular,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
                if (config.showWeatherBadge) _buildWeatherBadge(),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: config.cardFields
                  .where((f) => resource[f.key] != null)
                  .map((f) => _buildFieldChip(f, resource[f.key]))
                  .toList(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onBook,
                style: ElevatedButton.styleFrom(backgroundColor: config.themeColor),
                child: Text('Book ${config.resourceTermSingular}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldChip(ResourceCardField field, dynamic value) {
    final label = field.labelTemplate.replaceAll('{value}', '$value');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(field.icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      ],
    );
  }

  Widget _buildWeatherBadge() {
    // Weather-dependent sub-types (diving, safari, whale watching) show this;
    // accommodation/vehicle rental don't (config.showWeatherBadge = false).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wb_sunny, size: 12, color: Colors.amber),
          SizedBox(width: 4),
          Text('Weather dependent', style: TextStyle(fontSize: 11, color: Colors.black87)),
        ],
      ),
    );
  }
}
