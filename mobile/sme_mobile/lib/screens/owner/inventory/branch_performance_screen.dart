import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';
import '../../../models/billing_models.dart' show formatMoney;
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

final _branchCommerce = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final to = DateTime.now().toUtc();
  final response = await ApiService.dio.get('/reports/branch-commerce', queryParameters: {
    'from': to.subtract(const Duration(days: 30)).toIso8601String(),
    'to': to.toIso8601String(),
  });
  return Map<String, dynamic>.from(response.data as Map);
});

class BranchPerformanceScreen extends ConsumerWidget {
  const BranchPerformanceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(_branchCommerce);
    return OwnerScaffold(title: 'Branch Performance', subtitle: 'Sales and customer orders over the last 30 days',
      body: report.when(
        loading: () => const AppLoader(),
        error: (error, stack) => ErrorState(message: 'Could not load branch performance.', onRetry: () => ref.invalidate(_branchCommerce)),
        data: (data) {
          final branches = (data['branches'] as List? ?? []).cast<Map>();
          if (branches.isEmpty) return const EmptyState(icon: Icons.bar_chart_outlined, message: 'No branch activity in this period.');
          return RefreshIndicator(onRefresh: () async { ref.invalidate(_branchCommerce); await ref.read(_branchCommerce.future); },
            child: ListView(padding: const EdgeInsets.all(16), children: branches.map((branch) {
              final revenue = ((branch['manualSalesRevenue'] as num?) ?? 0) + ((branch['customerOrderSalesRevenue'] as num?) ?? 0);
              return Card(child: ListTile(
                title: Text('${branch['branchName'] ?? branch['branchId']}'),
                subtitle: Text('${branch['manualSalesCount'] ?? 0} manual sales ? ${branch['customerOrderCount'] ?? 0} customer orders'),
                trailing: Text(formatMoney(revenue.toDouble())),
              ));
            }).toList()));
        },
      ));
  }
}
