import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/booking_type_model.dart';
import '../../providers/api_service_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/booking_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/route_transitions.dart';
import '../../widgets/ui/ui.dart';
import 'my_ai_requests_screen.dart';
import 'my_bookings_screen.dart';

/// Customer-facing front door onto the Gemini-powered agent pipeline
/// (Planner -> Domain Analysis -> Action/Tool -> Validation/Safety) behind
/// POST /api/agent/find-and-book. The customer states an objective in plain
/// English against a booking type they already offer; the Validation/Safety
/// agent either books it outright, sends it for manager approval (high
/// booking count / revenue impact), or rejects it - see findAndBook() in
/// booking_providers.dart for how those three outcomes map to this screen.
class AiPlannerScreen extends ConsumerStatefulWidget {
  const AiPlannerScreen({super.key});

  @override
  ConsumerState<AiPlannerScreen> createState() => _AiPlannerScreenState();
}

class _AiPlannerScreenState extends ConsumerState<AiPlannerScreen> {
  final _objectiveController = TextEditingController(text: 'Book me the best available option this week');
  String? _bookingTypeId;
  int _withinDays = 7;
  bool _submitting = false;
  AiPlanOutcome? _result;

  @override
  void dispose() {
    _objectiveController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final bookingTypeId = _bookingTypeId;
    if (bookingTypeId == null) {
      AppSnackBar.info(context, 'Choose what you\'d like to book first.');
      return;
    }
    if (_objectiveController.text.trim().isEmpty) {
      AppSnackBar.info(context, 'Describe what you\'re looking for.');
      return;
    }

    setState(() {
      _submitting = true;
      _result = null;
    });

    final now = DateTime.now();
    final outcome = await findAndBook(
      ref.read(apiServiceProvider),
      objective: _objectiveController.text.trim(),
      bookingTypeId: bookingTypeId,
      dateFrom: now,
      dateTo: now.add(Duration(days: _withinDays)),
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _result = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tenantId = ref.watch(authProvider).user?.tenantId ?? '';
    final bookingTypesAsync = ref.watch(bookingTypesProvider(tenantId));

    return AppBackgroundScaffold(
      appBar: GlassAppBar(
        title: 'Ask AI to book for you',
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'My AI requests',
            onPressed: () => Navigator.of(context).push(slideFadeRoute(const MyAiRequestsScreen())),
          ),
        ],
      ),
      child: SafeArea(
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.heroGradientFor(AppColors.violet),
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                children: [
                  const IconWell(icon: Icons.auto_awesome, color: AppColors.violet, size: 44),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Describe what you want in plain English. A 4-agent AI pipeline finds the best match, checks availability, and books it — or asks the business to approve it first.',
                      style: AppTextStyles.body.copyWith(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const SectionHeader('What do you want to book?'),
            bookingTypesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(
                  color: AppColors.cyan,
                  backgroundColor: AppColors.inputFill,
                ),
              ),
              error: (err, stack) => Text(
                'Could not load this business\'s services.',
                style: AppTextStyles.body.copyWith(color: AppColors.danger),
              ),
              data: (types) => _BookingTypeSelector(
                types: types,
                selectedId: _bookingTypeId,
                onSelected: (id) => setState(() => _bookingTypeId = id),
              ),
            ),
            const SizedBox(height: 24),

            NeonInputField(
              label: 'Tell the AI what you\'re looking for',
              controller: _objectiveController,
              maxLines: 3,
              hintText: 'e.g. "Find me the earliest beginner-friendly slot this week"',
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Text('Within', style: AppTextStyles.bodyMuted),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: _withinDays,
                  dropdownColor: AppColors.overlaySurface,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  underline: const SizedBox.shrink(),
                  style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
                  icon: const Icon(Icons.expand_more_rounded, color: AppColors.iconSecondary),
                  items: const [3, 7, 14, 30]
                      .map((d) => DropdownMenuItem(value: d, child: Text('$d days')))
                      .toList(),
                  onChanged: (v) => setState(() => _withinDays = v ?? 7),
                ),
              ],
            ),
            const SizedBox(height: 24),

            NeonButton(
              label: _submitting ? 'Asking the AI planner…' : 'Find and book',
              icon: Icons.auto_awesome,
              isLoading: _submitting,
              onPressed: _submitting ? null : _submit,
            ),

            if (_result != null) ...[
              const SizedBox(height: 24),
              _ResultCard(result: _result!),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

class _BookingTypeSelector extends StatelessWidget {
  final List<BookingType> types;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const _BookingTypeSelector({required this.types, required this.selectedId, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) {
      return Text('No bookable services yet.', style: AppTextStyles.bodyMuted);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: types.map((t) {
        final selected = t.id == selectedId;
        return ChoiceChip(
          label: Text(t.name),
          selected: selected,
          onSelected: (_) => onSelected(t.id),
          backgroundColor: AppColors.iconWell,
          selectedColor: AppColors.violet.withValues(alpha: 0.20),
          labelStyle: AppTextStyles.body.copyWith(
            fontSize: 13,
            color: selected ? AppColors.textPrimary : AppColors.textBody,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          side: BorderSide(color: selected ? AppColors.violet : AppColors.glassBorder),
        );
      }).toList(),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final AiPlanOutcome result;
  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final (color, icon, title) = switch (result.status) {
      'Completed' => (AppColors.success, Icons.check_circle_rounded, 'Booked!'),
      'AwaitingApproval' => (AppColors.warning, Icons.hourglass_top_rounded, 'Sent for approval'),
      _ => (AppColors.danger, Icons.error_outline_rounded, 'Could not book that'),
    };

    return GlassCard(
      borderRadius: AppRadii.row,
      padding: const EdgeInsets.all(16),
      borderColor: color.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Text(title, style: AppTextStyles.subtitle.copyWith(color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Text(result.message, style: AppTextStyles.body.copyWith(fontSize: 13.5)),
          if (result.workflowId != null) ...[
            const SizedBox(height: 6),
            Text('Workflow ${result.workflowId}', style: AppTextStyles.caption.copyWith(fontSize: 11)),
          ],
          if (result.isBooked) ...[
            const SizedBox(height: 14),
            GhostButton(
              label: 'View my bookings',
              icon: Icons.event_available_outlined,
              onPressed: () => Navigator.of(context).push(slideFadeRoute(const MyBookingsScreen())),
            ),
          ],
        ],
      ),
    );
  }
}
