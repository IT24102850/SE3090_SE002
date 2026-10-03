import 'package:flutter/material.dart';

import '../widgets/ui/workflow_loading_state.dart';
import 'inventory_panel.dart';

class InventoryLoadingState extends StatelessWidget {
  const InventoryLoadingState({
    super.key,
    this.message = 'Loading inventory',
    this.detail = 'Preparing your stock workspace',
  });

  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: InventoryPanel(
            padding: const EdgeInsets.all(8),
            child: WorkflowLoadingState(
              message: message,
              detail: detail,
              icon: Icons.inventory_2_rounded,
            ),
          ),
        ),
      );
}
