import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/booking_type_model.dart';
import '../../providers/api_service_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/booking_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/route_transitions.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose what you\'d like to book first.')));
      return;
    }
    if (_objectiveController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Describe what you\'re looking for.')));
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask AI to book for you'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'My AI requests',
            onPressed: () => Navigator.of(context).push(slideFadeRoute(const MyAiRequestsScreen())),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.heroGradientFor(AppColors.purple),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.auto_awesome, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Describe what you want in plain English. A 4-agent AI pipeline finds the best match, checks availability, and books it — or asks the business to approve it first.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('What do you want to book?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            bookingTypesAsync.when(
              loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
              error: (err, stack) => const Text('Could not load this business\'s services.', style: TextStyle(color: AppColors.danger)),
              data: (types) => _BookingTypeSelector(
                types: types,
                selectedId: _bookingTypeId,
                onSelected: (id) => setState(() => _bookingTypeId = id),
              ),
            ),
            const SizedBox(height: 20),

            const Text('Tell the AI what you\'re looking for', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: _objectiveController,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'e.g. "Find me the earliest beginner-friendly slot this week"'),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                const Text('Within', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(width: 10),
                DropdownButton<int>(
                  value: _withinDays,
                  items: const [3, 7, 14, 30]
                      .map((d) => DropdownMenuItem(value: d, child: Text('$d days')))
                      .toList(),
                  onChanged: (v) => setState(() => _withinDays = v ?? 7),
                ),
              ],
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_submitting ? 'Asking the AI planner…' : 'Find and book'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.purple),
              ),
            ),

            if (_result != null) ...[
              const SizedBox(height: 24),
              _ResultCard(result: _result!),
            ],
          ],
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
      return Text('No bookable services yet.', style: TextStyle(color: Colors.grey.shade600));
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
          selectedColor: AppColors.purple.withValues(alpha: 0.15),
          labelStyle: TextStyle(color: selected ? AppColors.purple : null, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
          side: BorderSide(color: selected ? AppColors.purple : AppColors.border),
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
      'AwaitingApproval' => (AppColors.amber, Icons.hourglass_top_rounded, 'Sent for approval'),
      _ => (AppColors.danger, Icons.error_outline_rounded, 'Could not book that'),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 8),
          Text(result.message, style: const TextStyle(fontSize: 13.5, height: 1.4)),
          if (result.workflowId != null) ...[
            const SizedBox(height: 6),
            Text('Workflow ${result.workflowId}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
          if (result.isBooked) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(slideFadeRoute(const MyBookingsScreen())),
                icon: const Icon(Icons.event_available_outlined, size: 16),
                label: const Text('View my bookings'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
