import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Status chip for bills, payments, subscriptions and insurance claims.
class BillingStatusChip extends StatelessWidget {
  final String status;
  const BillingStatusChip({super.key, required this.status});

  static (Color, IconData, String) visualFor(String status) => switch (status) {
        'Paid' || 'Succeeded' || 'Approved' || 'Active' => (AppColors.success, Icons.check_circle_outline_rounded, status == 'Succeeded' ? 'Paid' : status),
        'Pending' || 'Issued' || 'PartiallyPaid' || 'Submitted' => (
            AppColors.warning,
            Icons.hourglass_top_rounded,
            status == 'PartiallyPaid' ? 'Part paid' : status == 'Issued' ? 'Pending' : status
          ),
        'UnderReview' || 'PendingCancel' => (AppColors.violet, Icons.manage_search_rounded, status == 'UnderReview' ? 'Under review' : 'Cancel requested'),
        'Overdue' || 'Failed' || 'Rejected' => (AppColors.danger, Icons.error_outline_rounded, status),
        _ => (AppColors.textMuted, Icons.remove_circle_outline_rounded, status),
      };

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = visualFor(status);
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
