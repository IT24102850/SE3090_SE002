import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/owner_models.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

class RecurringSeriesScreen extends ConsumerWidget {
  const RecurringSeriesScreen({super.key});

  Future<void> _cancel(
      BuildContext context, WidgetRef ref, RecurringSeries series) async {
    if (series.remaining == 0) {
      AppSnackBar.info(context, 'Nothing left to cancel.');
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Cancel future occurrences?'),
              content: Text(
                  'Cancel ${series.remaining} future occurrence(s) of "${series.title}"? Past bookings stay unchanged.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Cancel series'))
              ],
            ));
    if (confirmed != true) return;
    try {
      final result = await ref
          .read(ownerRepositoryProvider)
          .cancelRecurringSeries(series.patternId);
      ref.invalidate(ownerRecurringSeriesProvider);
      if (context.mounted) {
        AppSnackBar.success(
            context, 'Cancelled ${result['cancelled'] ?? 0} occurrences.');
      }
    } catch (_) {
      if (context.mounted) {
        AppSnackBar.error(context, 'Could not cancel this series.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seriesAsync = ref.watch(ownerRecurringSeriesProvider);
    return OwnerScaffold(
      title: 'Recurring Series',
      subtitle: 'Repeating bookings in one view',
      body: seriesAsync.when(
        loading: () => const AppLoader(),
        error: (_, __) => ErrorState(
            message: 'Could not load recurring series.',
            onRetry: () => ref.invalidate(ownerRecurringSeriesProvider)),
        data: (series) {
          final active = series.where((item) => item.isActive).toList();
          final upcoming =
              active.fold<int>(0, (sum, item) => sum + item.remaining);
          return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                StatGrid(tiles: [
                  StatTile(
                      label: 'Running',
                      value: '${active.length}',
                      sub: 'active series'),
                  StatTile(
                      label: 'Ahead',
                      value: '$upcoming',
                      sub: 'future occurrences',
                      accent: AppColors.success),
                  StatTile(
                      label: 'Bookings',
                      value:
                          '${series.fold<int>(0, (sum, item) => sum + item.total)}',
                      sub: 'created occurrences'),
                ]),
                const SizedBox(height: 18),
                const SectionHeader('Every series'),
                if (series.isEmpty)
                  const EmptyState(
                      icon: Icons.repeat,
                      message: 'No recurring bookings yet.'),
                for (final item in [...series]..sort((a, b) =>
                    (b.isActive ? 1 : 0).compareTo(a.isActive ? 1 : 0)))
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Expanded(
                                  child: Text(item.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium)),
                              Chip(
                                  label: Text(
                                      item.isActive ? 'Running' : 'Finished'))
                            ]),
                            const SizedBox(height: 6),
                            Text(
                                '${item.resourceName} · ${item.startTime} · ${item.frequency}',
                                style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(
                                  child: Text(
                                      '${item.total} total · ${item.remaining} ahead · ${item.cancelled} cancelled')),
                              if (item.isActive)
                                IconButton(
                                    tooltip: 'Cancel remaining',
                                    onPressed: () =>
                                        _cancel(context, ref, item),
                                    icon: const Icon(Icons.cancel_outlined,
                                        color: AppColors.error))
                            ]),
                          ]))),
              ]);
        },
      ),
    );
  }
}
