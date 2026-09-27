import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/owner_models.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

class AvailabilitySlotsScreen extends ConsumerStatefulWidget {
  const AvailabilitySlotsScreen({super.key});

  @override
  ConsumerState<AvailabilitySlotsScreen> createState() =>
      _AvailabilitySlotsScreenState();
}

class _AvailabilitySlotsScreenState
    extends ConsumerState<AvailabilitySlotsScreen> {
  String? _resourceId;
  int _slotMinutes = 60;
  final DateTime _from = DateTime.now();
  final DateTime _to = DateTime.now().add(const Duration(days: 13));
  AvailabilityLedger? _ledger;
  bool _loading = false;
  bool _working = false;
  String? _error;

  Future<void> _load() async {
    if (_resourceId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(ownerRepositoryProvider)
          .availabilitySlots(resourceId: _resourceId!, from: _from, to: _to);
      if (mounted) setState(() => _ledger = result);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load published slots.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    if (_resourceId == null) return;
    setState(() => _working = true);
    try {
      final result = await ref
          .read(ownerRepositoryProvider)
          .generateAvailabilitySlots(
              resourceId: _resourceId!,
              from: _from,
              to: _to,
              slotMinutes: _slotMinutes);
      if (mounted) {
        AppSnackBar.success(
            context, 'Published ${result['created'] ?? 0} slots.');
      }
      await _load();
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not publish these slots.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _clear() async {
    if (_resourceId == null) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Withdraw unbooked slots?'),
              content: const Text('Booked slots will be kept.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Withdraw'))
              ],
            ));
    if (confirmed != true) return;
    setState(() => _working = true);
    try {
      final result = await ref
          .read(ownerRepositoryProvider)
          .clearAvailabilitySlots(
              resourceId: _resourceId!, from: _from, to: _to);
      if (mounted) {
        AppSnackBar.success(
            context, 'Withdrew ${result['removed'] ?? 0} slots.');
      }
      await _load();
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not withdraw slots.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resourcesAsync = ref.watch(ownerResourcesProvider);
    return OwnerScaffold(
      title: 'Availability Slots',
      subtitle: 'Publish capacity you want to sell',
      body: resourcesAsync.when(
        loading: () => const AppLoader(),
        error: (_, __) => ErrorState(
            message: 'Could not load resources.',
            onRetry: () => ref.invalidate(ownerResourcesProvider)),
        data: (resources) {
          if (resources.isNotEmpty && _resourceId == null) {
            _resourceId = resources.first.id;
            WidgetsBinding.instance.addPostFrameCallback((_) => _load());
          }
          final ledger = _ledger;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              StatGrid(tiles: [
                StatTile(
                    label: 'Published',
                    value: '${ledger?.total ?? 0}',
                    sub: 'slots in range'),
                StatTile(
                    label: 'Sold',
                    value: '${ledger?.booked ?? 0}',
                    sub: 'held by bookings',
                    accent: AppColors.success),
                StatTile(
                    label: 'Open',
                    value: '${ledger?.free ?? 0}',
                    sub: 'available to book',
                    accent: AppColors.warning),
                StatTile(
                    label: 'Utilisation',
                    value:
                        '${ledger?.utilisationPercent.toStringAsFixed(0) ?? 0}%',
                    sub: 'of published capacity'),
              ]),
              const SizedBox(height: 16),
              GlassCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    DropdownButtonFormField<String>(
                        value: _resourceId,
                        decoration:
                            const InputDecoration(labelText: 'Resource'),
                        items: [
                          for (final resource in resources)
                            DropdownMenuItem(
                                value: resource.id, child: Text(resource.name))
                        ],
                        onChanged: (value) {
                          setState(() {
                            _resourceId = value;
                            _ledger = null;
                          });
                          _load();
                        }),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                        value: _slotMinutes,
                        decoration:
                            const InputDecoration(labelText: 'Slot length'),
                        items: [15, 30, 45, 60, 90, 120]
                            .map((value) => DropdownMenuItem(
                                value: value, child: Text('$value minutes')))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _slotMinutes = value ?? 60)),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                          child: NeonButton(
                              label: 'Publish slots',
                              isLoading: _working,
                              onPressed: _working || _resourceId == null
                                  ? null
                                  : _generate)),
                      const SizedBox(width: 10),
                      IconButton(
                          tooltip: 'Withdraw unbooked',
                          onPressed:
                              _working || _resourceId == null ? null : _clear,
                          icon: const Icon(Icons.remove_circle_outline))
                    ]),
                  ])),
              const SizedBox(height: 16),
              if (_loading) const AppLoader(),
              if (_error != null) ErrorState(message: _error!, onRetry: _load),
              if (!_loading && _error == null && ledger != null) ...[
                const SectionHeader('Published days'),
                for (final day in ledger.days)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GlassCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(day.date,
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Wrap(spacing: 6, runSpacing: 6, children: [
                              for (final slot in day.slots)
                                Chip(
                                    label: Text(slot.startTime.length >= 5
                                        ? slot.startTime.substring(0, 5)
                                        : slot.startTime),
                                    backgroundColor: slot.isBooked
                                        ? AppColors.cyan.withValues(alpha: .2)
                                        : AppColors.glassFill)
                            ]),
                            Text('${day.booked}/${day.total} sold',
                                style: Theme.of(context).textTheme.bodySmall)
                          ]))),
              ],
              if (resources.isEmpty)
                const EmptyState(
                    icon: Icons.hourglass_empty,
                    message: 'Add a resource before publishing availability.'),
            ],
          );
        },
      ),
    );
  }
}
