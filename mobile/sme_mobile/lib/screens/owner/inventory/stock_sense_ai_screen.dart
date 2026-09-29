import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../inventory/authenticated_api_client.dart';
import '../../../inventory/inventory_dashboard.dart';
import '../../../providers/auth_provider.dart';

/// Exposes the existing StockSense AI inventory workspace through the owner
/// drawer, using the shared authenticated API client and the signed-in role.
class StockSenseAiScreen extends ConsumerWidget {
  const StockSenseAiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authProvider).user?.role ?? 'Staff';
    return InventoryDashboard(
      client: AuthenticatedApiClient(),
      canApprove: role == 'Admin' || role == 'Manager',
    );
  }
}
