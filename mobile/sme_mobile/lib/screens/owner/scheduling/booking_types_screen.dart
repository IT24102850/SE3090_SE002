import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/booking_type_model.dart';
import '../../../providers/owner_providers.dart';
import '../../../shared/color_utils.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';
import 'scheduling_kit.dart';

/// The service catalogue.
///
/// Each row is shown the way a customer meets the service — its colour, how
/// long it takes, what it costs, how many fit — rather than as a row of
/// database fields. Retired services are kept visible but faded instead of
/// hidden behind a filter, because "why can nobody book this?" is the
/// question this screen exists to answer.
class BookingTypesScreen extends ConsumerStatefulWidget {
  const BookingTypesScreen({super.key});

  @override
  ConsumerState<BookingTypesScreen> createState() => _BookingTypesScreenState();
}

class _BookingTypesScreenState extends ConsumerState<BookingTypesScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final typesAsync = ref.watch(ownerBookingTypesProvider);

    return OwnerScaffold(
      title: 'Booking Types',
      subtitle: 'What people can book',
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.onPrimary,
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New service'),
      ),
      body: typesAsync.when(
        loading: () => const ScheduleSkeleton(),
        error: (error, _) => ErrorState(
          message: 'Could not load the catalogue.',
          onRetry: () => ref.invalidate(ownerBookingTypesProvider),
        ),
        data: (all) {
          final rows = _search.isEmpty
              ? all
              : all.where((t) => t.name.toLowerCase().contains(_search.toLowerCase())).toList();
          final live = all.where((t) => t.status == 'Active').toList();
          final approvals = live.where((t) => t.requiresApproval).length;
          final averageMinutes =
              live.isEmpty ? 0 : live.fold<int>(0, (sum, t) => sum + t.defaultDurationMinutes) ~/ live.length;

          return RefreshIndicator(
            color: AppColors.cyan,
            backgroundColor: AppColors.overlaySurface,
            onRefresh: () async => ref.invalidate(ownerBookingTypesProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                ScheduleHero(
                  eyebrow: 'Catalogue',
                  headline: live.isEmpty
                      ? 'Nothing bookable yet'
                      : '${live.length} service${live.length == 1 ? '' : 's'} on sale',
                  support: all.length == live.length
                      ? 'Everything in the catalogue is bookable.'
                      : '${all.length - live.length} retired and not taking bookings.',
                  accent: AppColors.violet,
                  chips: [
                    if (averageMinutes > 0)
                      HeroMetric(icon: Icons.timer_outlined, value: '$averageMinutes', label: 'min average'),
                    if (approvals > 0)
                      HeroMetric(
                        icon: Icons.gavel_rounded,
                        value: '$approvals',
                        label: 'need approving',
                        color: AppColors.warning,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (all.length > 5) ...[
                  NeonInputField(
                    hintText: 'Search the catalogue',
                    icon: Icons.search_rounded,
                    clearable: true,
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 14),
                ],
                if (rows.isEmpty)
                  ScheduleEmpty(
                    icon: Icons.sell_outlined,
                    title: all.isEmpty ? 'Nothing to book' : 'No match',
                    detail: all.isEmpty
                        ? 'A booking type is the thing a customer picks — a class, a table, a consultation. Add the first one.'
                        : 'Nothing in the catalogue matches that.',
                    actionLabel: all.isEmpty ? 'Add a service' : null,
                    onAction: all.isEmpty ? () => _edit(context, ref, null) : null,
                  )
                else
                  for (final type in rows) _TypeCard(type: type),
              ],
            ),
          );
        },
      ),
    );
  }

  static Future<void> _edit(BuildContext context, WidgetRef ref, BookingType? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.pill)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _BookingTypeForm(existing: existing),
      ),
    );
    if (saved == true) ref.invalidate(ownerBookingTypesProvider);
  }
}

class _TypeCard extends ConsumerWidget {
  final BookingType type;
  const _TypeCard({required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = parseHexColor(type.colorHex) ?? AppColors.cyan;
    final isLive = type.status == 'Active';
    final price = type.adultPrice;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: isLive ? 1 : .6,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _BookingTypesScreenState._edit(context, ref, type),
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: accent.withValues(alpha: isLive ? .35 : .15)),
                gradient: LinearGradient(
                  colors: [accent.withValues(alpha: .16), AppColors.glassFill],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 14, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: .2),
                            borderRadius: BorderRadius.circular(AppRadii.image),
                            border: Border.all(color: accent.withValues(alpha: .5)),
                          ),
                          child: Center(
                            child: Text(
                              type.icon ?? _initial(type.name),
                              style: AppTextStyles.body.copyWith(color: accent, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(type.name, style: AppTextStyles.title.copyWith(fontSize: 16)),
                              if (type.description?.isNotEmpty == true) ...[
                                const SizedBox(height: 3),
                                Text(
                                  type.description!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!isLive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.textMuted.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('Retired', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
                          ),
                      ],
                    ),
                  ),
                  // The specification strip: duration, price, capacity,
                  // approval. Four facts, evenly weighted, easy to compare
                  // down a column of cards.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .16),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadii.card)),
                    ),
                    child: Row(
                      children: [
                        _Spec(icon: Icons.schedule_rounded, value: '${type.defaultDurationMinutes}m'),
                        if (price != null)
                          _Spec(icon: Icons.payments_outlined, value: '${type.currency} ${price.toStringAsFixed(0)}'),
                        _Spec(
                          icon: Icons.groups_rounded,
                          value: type.maxParticipants == null ? 'Any' : '${type.maxParticipants}',
                        ),
                        _Spec(
                          icon: type.requiresApproval ? Icons.gavel_rounded : Icons.bolt_rounded,
                          value: type.requiresApproval ? 'Approve' : 'Instant',
                          color: type.requiresApproval ? AppColors.warning : AppColors.success,
                        ),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                          onPressed: () => _confirmDelete(context, ref),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _initial(String name) => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.overlaySurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.card)),
        title: Text('Delete "${type.name}"?', style: AppTextStyles.title),
        content: Text(
          'Bookings already made keep their history. If you only want to stop new ones, retire it instead.',
          style: AppTextStyles.caption,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep it', style: AppTextStyles.caption.copyWith(color: AppColors.textBody)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: AppTextStyles.caption.copyWith(color: AppColors.error, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(ownerRepositoryProvider).deleteBookingType(type.id);
      ref.invalidate(ownerBookingTypesProvider);
      if (context.mounted) AppSnackBar.success(context, 'Service deleted.');
    } catch (error) {
      if (context.mounted) AppSnackBar.error(context, serverMessage(error, 'Could not delete this service.'));
    }
  }
}

class _Spec extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _Spec({required this.icon, required this.value, this.color = AppColors.textBody});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(value, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _BookingTypeForm extends ConsumerStatefulWidget {
  final BookingType? existing;
  const _BookingTypeForm({this.existing});

  @override
  ConsumerState<_BookingTypeForm> createState() => _BookingTypeFormState();
}

class _BookingTypeFormState extends ConsumerState<_BookingTypeForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _maxParticipants;
  late final TextEditingController _bufferBefore;
  late final TextEditingController _bufferAfter;
  late String _colorHex;
  late int _duration;
  late bool _requiresApproval;
  late String _status;
  bool _saving = false;
  bool _showBuffers = false;

  static const _palette = ['#2563EB', '#7C3AED', '#0EA5E9', '#16A34A', '#F59E0B', '#EF4444', '#EC4899'];
  static const _durations = [15, 30, 45, 60, 90, 120, 180];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _maxParticipants = TextEditingController(text: e?.maxParticipants?.toString() ?? '');
    _bufferBefore = TextEditingController(text: '${e?.bufferMinutesBefore ?? 0}');
    _bufferAfter = TextEditingController(text: '${e?.bufferMinutesAfter ?? 0}');
    _colorHex = e?.colorHex ?? _palette.first;
    _duration = e?.defaultDurationMinutes ?? 60;
    _requiresApproval = e?.requiresApproval ?? false;
    _status = e?.status ?? 'Active';
    _showBuffers = (e?.bufferMinutesBefore ?? 0) > 0 || (e?.bufferMinutesAfter ?? 0) > 0;
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _maxParticipants, _bufferBefore, _bufferAfter]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(ownerRepositoryProvider).saveBookingType(
            id: widget.existing?.id,
            tenantId: ref.read(ownerTenantIdProvider),
            name: _name.text.trim(),
            description: _description.text.trim().isEmpty ? null : _description.text.trim(),
            colorHex: _colorHex,
            defaultDurationMinutes: _duration,
            requiresApproval: _requiresApproval,
            maxParticipants: int.tryParse(_maxParticipants.text),
            bufferMinutesBefore: _showBuffers ? int.tryParse(_bufferBefore.text) ?? 0 : 0,
            bufferMinutesAfter: _showBuffers ? int.tryParse(_bufferAfter.text) ?? 0 : 0,
            status: _status,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) AppSnackBar.error(context, serverMessage(error, 'Could not save this service.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = parseHexColor(_colorHex) ?? AppColors.cyan;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetGrip(),
              const SizedBox(height: 14),
              Text(widget.existing == null ? 'New service' : 'Edit service', style: AppTextStyles.title),
              const SizedBox(height: 16),

              // A live preview of the card the customer will see. Editing
              // against the result rather than against field names is what
              // makes a form like this quick to get right.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.row),
                  border: Border.all(color: accent.withValues(alpha: .4)),
                  gradient: LinearGradient(
                    colors: [accent.withValues(alpha: .18), AppColors.glassFill],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(AppRadii.image),
                      ),
                      child: Center(
                        child: Text(
                          _name.text.trim().isEmpty ? '?' : _name.text.trim()[0].toUpperCase(),
                          style: AppTextStyles.body.copyWith(color: accent, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _name.text.trim().isEmpty ? 'Your service' : _name.text.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '$_duration min'
                            '${_maxParticipants.text.isNotEmpty ? ' · up to ${_maxParticipants.text}' : ''}'
                            '${_requiresApproval ? ' · needs approval' : ' · books instantly'}',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              NeonInputField(
                label: 'Name',
                controller: _name,
                onChanged: (_) => setState(() {}),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Give it a name.' : null,
              ),
              const SizedBox(height: 10),
              NeonInputField(label: 'Description', controller: _description, maxLines: 2),
              const SizedBox(height: 18),

              Text('How long', style: AppTextStyles.label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in _durations)
                    _Choice(
                      label: minutes >= 60 && minutes % 60 == 0 ? '${minutes ~/ 60}h' : '${minutes}m',
                      isSelected: _duration == minutes,
                      onTap: () => setState(() => _duration = minutes),
                    ),
                ],
              ),
              const SizedBox(height: 18),

              Text('Colour', style: AppTextStyles.label),
              const SizedBox(height: 4),
              Text('How it is picked out on the timeline.', style: AppTextStyles.caption),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  for (final hex in _palette)
                    GestureDetector(
                      onTap: () => setState(() => _colorHex = hex),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: parseHexColor(hex) ?? AppColors.cyan,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _colorHex == hex ? AppColors.textPrimary : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: _colorHex == hex
                            ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),

              NeonInputField(
                label: 'Maximum people',
                controller: _maxParticipants,
                keyboardType: TextInputType.number,
                helperText: 'Leave blank for no cap',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _requiresApproval,
                activeColor: AppColors.cyan,
                title: Text('Approve each booking', style: AppTextStyles.body),
                subtitle: Text('Bookings wait as Pending until staff confirm them.', style: AppTextStyles.caption),
                onChanged: (v) => setState(() => _requiresApproval = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _status == 'Active',
                activeColor: AppColors.cyan,
                title: Text('Bookable', style: AppTextStyles.body),
                subtitle: Text('Turn off to retire it without losing its history.', style: AppTextStyles.caption),
                onChanged: (v) => setState(() => _status = v ? 'Active' : 'Inactive'),
              ),

              // Buffers are rare, so they stay folded away rather than
              // taking space from the fields most services need.
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _showBuffers,
                activeColor: AppColors.cyan,
                title: Text('Gap either side', style: AppTextStyles.body),
                subtitle: Text('Turnaround time the next booking cannot use.', style: AppTextStyles.caption),
                onChanged: (v) => setState(() => _showBuffers = v),
              ),
              if (_showBuffers) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: NeonInputField(
                      label: 'Before (min)',
                      controller: _bufferBefore,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NeonInputField(
                      label: 'After (min)',
                      controller: _bufferAfter,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 20),
              NeonButton(
                label: widget.existing == null ? 'Add to the catalogue' : 'Save changes',
                height: 52,
                isLoading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _Choice({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 42,
        width: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.cyan : AppColors.glassFill,
          borderRadius: BorderRadius.circular(AppRadii.control),
          border: Border.all(color: isSelected ? AppColors.cyan : AppColors.glassBorder),
        ),
        child: Text(
          label,
          style: AppTextStyles.body.copyWith(
            color: isSelected ? AppColors.onPrimary : AppColors.textBody,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
