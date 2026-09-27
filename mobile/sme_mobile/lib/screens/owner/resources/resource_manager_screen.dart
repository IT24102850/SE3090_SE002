import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/resource_model.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// Rooms, chairs, vessels, machines — whatever this business books people
/// into. The mobile twin of the web Resource Manager, including the weekly
/// opening pattern each resource keeps.
class ResourceManagerScreen extends ConsumerStatefulWidget {
  const ResourceManagerScreen({super.key});

  @override
  ConsumerState<ResourceManagerScreen> createState() => _ResourceManagerScreenState();
}

class _ResourceManagerScreenState extends ConsumerState<ResourceManagerScreen> {
  String _search = '';
  String? _category;

  @override
  Widget build(BuildContext context) {
    final resourcesAsync = ref.watch(ownerResourcesProvider);

    return OwnerScaffold(
      title: 'Resource Manager',
      subtitle: 'What people are booked into',
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.onPrimary,
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New resource'),
      ),
      body: resourcesAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(
          message: 'Could not load the resources.',
          onRetry: () => ref.invalidate(ownerResourcesProvider),
        ),
        data: (all) {
          final categories = all.map((r) => r.category).toSet().toList()..sort();
          final rows = all.where((r) {
            if (_category != null && r.category != _category) return false;
            if (_search.isEmpty) return true;
            return '${r.name} ${r.code ?? ''} ${r.specialty ?? ''}'.toLowerCase().contains(_search.toLowerCase());
          }).toList();

          return RefreshIndicator(
            color: AppColors.cyan,
            backgroundColor: AppColors.overlaySurface,
            onRefresh: () async => ref.invalidate(ownerResourcesProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                StatGrid(tiles: [
                  StatTile(label: 'Resources', value: '${all.length}', sub: 'on the register'),
                  StatTile(
                    label: 'Available',
                    value: '${all.where((r) => r.status == 'Available').length}',
                    sub: 'ready to book',
                    accent: AppColors.success,
                  ),
                  StatTile(label: 'Categories', value: '${categories.length}', sub: 'kinds of resource'),
                  StatTile(
                    label: 'Total capacity',
                    value: '${all.fold<int>(0, (sum, r) => sum + (r.capacity ?? 0))}',
                    sub: 'seats across all',
                  ),
                ]),
                const SizedBox(height: 14),
                NeonInputField(
                  hintText: 'Search name, code or specialty',
                  icon: Icons.search_rounded,
                  clearable: true,
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 10),
                FilterChips<String>(
                  options: [
                    (value: null, label: 'All categories'),
                    for (final c in categories) (value: c, label: c),
                  ],
                  selected: _category,
                  onSelected: (v) => setState(() => _category = v),
                ),
                const SizedBox(height: 14),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(icon: Icons.meeting_room_outlined, message: 'No resources match this filter.'),
                  )
                else
                  ...rows.map((r) => _ResourceCard(resource: r)),
              ],
            ),
          );
        },
      ),
    );
  }

  static Future<void> _edit(BuildContext context, WidgetRef ref, Resource? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _ResourceForm(existing: existing),
      ),
    );
    if (saved == true) ref.invalidate(ownerResourcesProvider);
  }
}

class _ResourceCard extends ConsumerWidget {
  final Resource resource;
  const _ResourceCard({required this.resource});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: () => _ResourceManagerScreenState._edit(context, ref, resource),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconWell(icon: Icons.meeting_room_outlined, color: AppColors.cyan),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(resource.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        '${resource.category}'
                        '${resource.code != null ? ' · ${resource.code}' : ''}'
                        '${resource.capacity != null ? ' · seats ${resource.capacity}' : ''}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                OwnerStatusChip(status: resource.status),
              ],
            ),
            if (resource.description?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(resource.description!, style: AppTextStyles.caption),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: 'Opening hours',
                    icon: Icons.schedule_outlined,
                    height: 40,
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: AppColors.overlaySurface,
                      isScrollControlled: true,
                      builder: (_) => _ScheduleSheet(resource: resource),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GhostButton(
                    label: 'Delete',
                    icon: Icons.delete_outline_rounded,
                    height: 40,
                    color: AppColors.error,
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: AppColors.overlaySurface,
                          title: Text('Delete "${resource.name}"?', style: AppTextStyles.title),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete', style: TextStyle(color: AppColors.error)),
                            ),
                          ],
                        ),
                      );
                      if (ok != true || !context.mounted) return;
                      try {
                        await ref.read(ownerRepositoryProvider).deleteResource(resource.id);
                        ref.invalidate(ownerResourcesProvider);
                        if (context.mounted) AppSnackBar.success(context, 'Resource deleted.');
                      } catch (_) {
                        if (context.mounted) {
                          AppSnackBar.error(context, 'Could not delete it — it may still have bookings.');
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceForm extends ConsumerStatefulWidget {
  final Resource? existing;
  const _ResourceForm({this.existing});

  @override
  ConsumerState<_ResourceForm> createState() => _ResourceFormState();
}

class _ResourceFormState extends ConsumerState<_ResourceForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _category;
  late final TextEditingController _description;
  late final TextEditingController _capacity;
  late final TextEditingController _hourlyRate;
  late final TextEditingController _specialty;
  late String _status;
  String? _branchId;
  bool _saving = false;

  static const _statuses = ['Available', 'Unavailable', 'Maintenance'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _code = TextEditingController(text: e?.code ?? '');
    _category = TextEditingController(text: e?.category ?? 'Room');
    _description = TextEditingController(text: e?.description ?? '');
    _capacity = TextEditingController(text: e?.capacity?.toString() ?? '');
    _hourlyRate = TextEditingController(text: e?.hourlyRate?.toString() ?? '');
    _specialty = TextEditingController(text: e?.specialty ?? '');
    _status = e?.status ?? 'Available';
    _branchId = e?.branchId;
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _category, _description, _capacity, _hourlyRate, _specialty]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(ownerRepositoryProvider).saveResource(
            id: widget.existing?.id,
            tenantId: ref.read(ownerTenantIdProvider),
            branchId: _branchId,
            name: _name.text.trim(),
            code: _code.text.trim().isEmpty ? null : _code.text.trim(),
            category: _category.text.trim(),
            status: _status,
            description: _description.text.trim().isEmpty ? null : _description.text.trim(),
            capacity: int.tryParse(_capacity.text),
            hourlyRate: double.tryParse(_hourlyRate.text),
            specialty: _specialty.text.trim().isEmpty ? null : _specialty.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) AppSnackBar.error(context, serverMessage(error, 'Could not save this resource.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(ownerBranchesProvider).valueOrNull ?? const [];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing == null ? 'New resource' : 'Edit resource', style: AppTextStyles.title),
              const SizedBox(height: 14),
              NeonInputField(
                label: 'Name',
                controller: _name,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Give it a name.' : null,
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: NeonInputField(label: 'Code', controller: _code)),
                const SizedBox(width: 10),
                Expanded(child: NeonInputField(label: 'Category', controller: _category)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: NeonInputField(label: 'Capacity', controller: _capacity, keyboardType: TextInputType.number),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NeonInputField(
                    label: 'Hourly rate',
                    controller: _hourlyRate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              NeonInputField(label: 'Specialty', controller: _specialty),
              const SizedBox(height: 10),
              NeonInputField(label: 'Description', controller: _description, maxLines: 2),
              const SizedBox(height: 14),
              Text('Status', style: AppTextStyles.label),
              const SizedBox(height: 8),
              FilterChips<String>(
                options: [for (final s in _statuses) (value: s, label: s)],
                selected: _status,
                onSelected: (v) => setState(() => _status = v ?? 'Available'),
              ),
              if (branches.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Branch', style: AppTextStyles.label),
                const SizedBox(height: 8),
                FilterChips<String>(
                  options: [
                    (value: null, label: 'Unassigned'),
                    for (final b in branches) (value: b.id, label: b.name),
                  ],
                  selected: _branchId,
                  onSelected: (v) => setState(() => _branchId = v),
                ),
              ],
              const SizedBox(height: 16),
              NeonButton(label: 'Save', isLoading: _saving, onPressed: _saving ? null : _save),
            ],
          ),
        ),
      ),
    );
  }
}

/// The weekly opening pattern. Days the resource is closed simply have no
/// row, which is how the API stores it too.
class _ScheduleSheet extends ConsumerStatefulWidget {
  final Resource resource;
  const _ScheduleSheet({required this.resource});

  @override
  ConsumerState<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends ConsumerState<_ScheduleSheet> {
  static const _days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  List<Map<String, dynamic>>? _rows;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await ref.read(ownerRepositoryProvider).resourceSchedule(widget.resource.id);
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the opening hours.');
    }
  }

  ({bool open, String from, String to}) _forDay(int day) {
    final row = (_rows ?? const []).where((r) => (r['dayOfWeek'] as num?)?.toInt() == day).toList();
    if (row.isEmpty) return (open: false, from: '09:00', to: '17:00');
    final r = row.first;
    return (
      open: r['isAvailable'] != false,
      from: (r['startTime'] ?? '09:00').toString().substring(0, 5),
      to: (r['endTime'] ?? '17:00').toString().substring(0, 5),
    );
  }

  void _set(int day, {bool? open, String? from, String? to}) {
    final rows = [...(_rows ?? const <Map<String, dynamic>>[])];
    final index = rows.indexWhere((r) => (r['dayOfWeek'] as num?)?.toInt() == day);
    final current = _forDay(day);
    final next = {
      'dayOfWeek': day,
      'startTime': '${from ?? current.from}:00',
      'endTime': '${to ?? current.to}:00',
      'isAvailable': open ?? current.open,
    };
    if (index >= 0) {
      rows[index] = next;
    } else {
      rows.add(next);
    }
    setState(() => _rows = rows);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(ownerRepositoryProvider).setResourceSchedule(widget.resource.id, _rows ?? const []);
      if (mounted) {
        Navigator.pop(context);
        AppSnackBar.success(context, 'Opening hours saved.');
      }
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not save the opening hours.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: _error != null
            ? ErrorState(message: _error!, onRetry: _load)
            : _rows == null
                ? const SizedBox(height: 180, child: AppLoader())
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${widget.resource.name} · opening hours', style: AppTextStyles.title),
                      const SizedBox(height: 4),
                      Text('A day that is switched off takes no bookings.', style: AppTextStyles.caption),
                      const SizedBox(height: 10),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: 7,
                          itemBuilder: (context, day) {
                            final value = _forDay(day);
                            return Row(
                              children: [
                                SizedBox(
                                  width: 96,
                                  child: Text(_days[day], style: AppTextStyles.body),
                                ),
                                Switch(
                                  value: value.open,
                                  activeColor: AppColors.cyan,
                                  onChanged: (v) => _set(day, open: v),
                                ),
                                if (value.open) ...[
                                  _TimeButton(label: value.from, onPicked: (t) => _set(day, from: t)),
                                  const Text(' – '),
                                  _TimeButton(label: value.to, onPicked: (t) => _set(day, to: t)),
                                ] else
                                  Text('Closed', style: AppTextStyles.caption),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      NeonButton(label: 'Save hours', isLoading: _saving, onPressed: _saving ? null : _save),
                    ],
                  ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final ValueChanged<String> onPicked;
  const _TimeButton({required this.label, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () async {
        final parts = label.split(':');
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 9, minute: int.tryParse(parts.last) ?? 0),
        );
        if (picked != null) {
          onPicked('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
        }
      },
      child: Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.cyan)),
    );
  }
}
