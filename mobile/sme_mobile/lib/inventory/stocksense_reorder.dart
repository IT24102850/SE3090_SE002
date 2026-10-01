import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'authenticated_api_client.dart';

/// StockSense reorders from the phone: turn the analysis's recommendations
/// into a reorder request, then follow it. The server prices the order from
/// inventory records and runs the deterministic safety gate
/// (StockSenseReordersController); orders over the limits wait for a manager
/// in the web app, and the answer arrives here as a device notification and in
/// "My reorder requests".

class ReorderCheck {
  const ReorderCheck(this.rule, this.passed, this.detail);
  final String rule;
  final bool passed;
  final String detail;

  factory ReorderCheck.fromJson(Map<String, dynamic> j) =>
      ReorderCheck('${j['rule']}', j['passed'] == true, '${j['detail']}');
}

class ReorderWorkflow {
  const ReorderWorkflow({
    required this.id,
    required this.status,
    required this.supplierName,
    required this.totalValue,
    required this.totalUnits,
    required this.lineCount,
    required this.checks,
    this.finalOutcome,
    this.error,
    this.purchaseOrderNumber,
    required this.createdAt,
  });

  final String id;
  final String status;
  final String supplierName;
  final double totalValue;
  final double totalUnits;
  final int lineCount;
  final List<ReorderCheck> checks;
  final String? finalOutcome;
  final String? error;
  final String? purchaseOrderNumber;
  final DateTime createdAt;

  factory ReorderWorkflow.fromJson(Map<String, dynamic> j) => ReorderWorkflow(
        id: '${j['id']}',
        status: '${j['status']}',
        supplierName: '${j['supplierName'] ?? ''}',
        totalValue: (j['totalValue'] as num?)?.toDouble() ?? 0,
        totalUnits: (j['totalUnits'] as num?)?.toDouble() ?? 0,
        lineCount: (j['lines'] as List?)?.length ?? 0,
        checks: ((j['checks'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ReorderCheck.fromJson)
            .toList(),
        finalOutcome: j['finalOutcome'] as String?,
        error: j['error'] as String?,
        purchaseOrderNumber: j['purchaseOrderNumber'] as String?,
        createdAt: DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? DateTime.now(),
      );

  String get statusLabel => switch (status) {
        'AwaitingApproval' => 'Awaiting approval',
        'Completed' => 'Ordered',
        'Rejected' => 'Rejected',
        'RevisionRequested' => 'Revision requested',
        _ => status,
      };
}

class SupplierOption {
  const SupplierOption(this.id, this.name);
  final String id;
  final String name;
}

class ReorderLineDraft {
  ReorderLineDraft({
    required this.inventoryItemId,
    required this.name,
    required this.branchId,
    required this.quantity,
    this.selected = true,
  });

  final String inventoryItemId;
  final String name;
  final String branchId;
  int quantity;
  bool selected;

  /// From one entry of StockSense's `recommendations`; null when it has no branch.
  static ReorderLineDraft? fromRecommendation(Map<String, dynamic> r) {
    final branch = r['branch_id'];
    if (branch is! String || branch.isEmpty) return null;
    return ReorderLineDraft(
      inventoryItemId: '${r['inventory_item_id']}',
      name: '${r['item_name']}',
      branchId: branch,
      quantity: ((r['recommended_quantity'] as num?) ?? 0).ceil(),
    );
  }
}

class StockSenseReorderRepository {
  StockSenseReorderRepository(this._client);
  final AuthenticatedApiClient _client;

  Future<List<SupplierOption>> suppliers() async {
    final response = await _client.get('/api/purchase-orders/options');
    if (response.statusCode != 200) throw Exception('Suppliers could not be loaded.');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ((data['suppliers'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((s) => SupplierOption('${s['id']}', '${s['name']}'))
        .toList();
  }

  Future<ReorderWorkflow> request({
    required String branchId,
    required String supplierId,
    required List<ReorderLineDraft> lines,
    String? analysisWorkflowId,
  }) async {
    final response = await _client.post('/api/inventory/agent/reorders', body: {
      'branchId': branchId,
      'supplierId': supplierId,
      if (analysisWorkflowId != null) 'analysisWorkflowId': analysisWorkflowId,
      'lines': [
        for (final line in lines) {'inventoryItemId': line.inventoryItemId, 'quantity': line.quantity},
      ],
    });
    final body = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (response.statusCode != 201 || body is! Map<String, dynamic>) {
      throw Exception(_errorText(body) ?? 'The reorder request could not be sent (${response.statusCode}).');
    }
    return ReorderWorkflow.fromJson(body);
  }

  Future<List<ReorderWorkflow>> mine() async {
    final response = await _client.get('/api/inventory/agent/reorders?mine=true');
    if (response.statusCode != 200) {
      throw Exception('Your reorder requests could not be loaded (${response.statusCode}).');
    }
    return ((jsonDecode(response.body) as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ReorderWorkflow.fromJson)
        .toList();
  }

  static String? _errorText(Object? body) {
    if (body is! Map) return null;
    if (body['message'] is String) return body['message'] as String;
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return '${first.first}';
    }
    return body['title'] as String?;
  }
}

/// Bottom sheet: pick a supplier and the lines, send, see the gate's decision.
class StockSenseReorderSheet extends StatefulWidget {
  const StockSenseReorderSheet({
    super.key,
    required this.repository,
    required this.recommendations,
    this.analysisWorkflowId,
  });

  final StockSenseReorderRepository repository;
  final List<Map<String, dynamic>> recommendations;
  final String? analysisWorkflowId;

  @override
  State<StockSenseReorderSheet> createState() => _StockSenseReorderSheetState();
}

class _StockSenseReorderSheetState extends State<StockSenseReorderSheet> {
  late final List<ReorderLineDraft> _lines = widget.recommendations
      .map(ReorderLineDraft.fromRecommendation)
      .whereType<ReorderLineDraft>()
      .toList();
  List<SupplierOption> _suppliers = const [];
  String? _supplierId;
  bool _loadingSuppliers = true;
  bool _sending = false;
  String? _error;
  ReorderWorkflow? _result;

  String? get _branchId => _lines.isEmpty ? null : _lines.first.branchId;

  @override
  void initState() {
    super.initState();
    widget.repository.suppliers().then((s) {
      if (mounted) setState(() => _suppliers = s);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = 'Suppliers could not be loaded.');
    }).whenComplete(() {
      if (mounted) setState(() => _loadingSuppliers = false);
    });
  }

  Future<void> _send() async {
    final chosen = _lines.where((l) => l.selected && l.quantity > 0 && l.branchId == _branchId).toList();
    if (_supplierId == null) {
      setState(() => _error = 'Choose a supplier.');
      return;
    }
    if (chosen.isEmpty) {
      setState(() => _error = 'Select at least one item with a quantity above zero.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await widget.repository.request(
        branchId: _branchId!,
        supplierId: _supplierId!,
        lines: chosen,
        analysisWorkflowId: widget.analysisWorkflowId,
      );
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Request a reorder', style: text.titleLarge),
            const SizedBox(height: 4),
            Text('Prices come from your inventory records. Orders over the limits wait for a manager.',
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            if (_loadingSuppliers)
              const LinearProgressIndicator()
            else
              DropdownButtonFormField<String>(
                key: const Key('reorder-supplier'),
                value: _supplierId,
                decoration: const InputDecoration(labelText: 'Supplier'),
                items: [
                  for (final s in _suppliers) DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: _result == null ? (v) => setState(() => _supplierId = v) : null,
              ),
            const SizedBox(height: 12),
            for (final line in _lines.where((l) => l.branchId == _branchId))
              Row(children: [
                Checkbox(
                  key: Key('reorder-select-${line.inventoryItemId}'),
                  value: line.selected,
                  onChanged: _result == null ? (v) => setState(() => line.selected = v ?? false) : null,
                ),
                Expanded(child: Text(line.name)),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    key: Key('reorder-qty-${line.inventoryItemId}'),
                    initialValue: '${line.quantity}',
                    enabled: _result == null,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.end,
                    decoration: const InputDecoration(isDense: true, labelText: 'Qty'),
                    onChanged: (v) => line.quantity = int.tryParse(v) ?? 0,
                  ),
                ),
              ]),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: text.bodyMedium?.copyWith(color: AppColors.magenta)),
              ),
            if (_result == null)
              FilledButton(
                onPressed: _sending ? null : _send,
                child: Text(_sending ? 'Checking against the limits…' : 'Request reorder'),
              )
            else
              _ResultCard(result: _result!),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final ReorderWorkflow result;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(result.statusLabel, style: text.titleMedium),
        if (result.finalOutcome != null) ...[
          const SizedBox(height: 4),
          Text(result.finalOutcome!, style: text.bodyMedium),
        ],
        if (result.status == 'Rejected' && result.error != null) ...[
          const SizedBox(height: 4),
          Text(result.error!, style: text.bodyMedium?.copyWith(color: AppColors.magenta)),
        ],
        if (result.status == 'AwaitingApproval') ...[
          const SizedBox(height: 4),
          Text("You'll get a notification when a manager decides.", style: text.bodySmall),
        ],
      ]),
    );
  }
}

/// The signed-in user's reorder requests and where each one stands.
class MyReordersScreen extends StatefulWidget {
  const MyReordersScreen({super.key, required this.repository});
  final StockSenseReorderRepository repository;

  @override
  State<MyReordersScreen> createState() => _MyReordersScreenState();
}

class _MyReordersScreenState extends State<MyReordersScreen> {
  late Future<List<ReorderWorkflow>> _future = widget.repository.mine();

  Future<void> _refresh() async {
    final next = widget.repository.mine();
    setState(() => _future = next);
    await next.catchError((_) => <ReorderWorkflow>[]);
  }

  Color _tone(String status) => switch (status) {
        'Completed' => Colors.greenAccent,
        'Rejected' => AppColors.magenta,
        'RevisionRequested' => AppColors.violet,
        _ => Colors.amberAccent,
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('My reorder requests')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<ReorderWorkflow>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(snapshot.error.toString().replaceFirst('Exception: ', '')),
                ),
              ]);
            }
            final reorders = snapshot.data ?? const [];
            if (reorders.isEmpty) {
              return ListView(children: const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No reorder requests yet. Run StockSense and request a reorder from its recommendations.'),
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: reorders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final r = reorders[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(r.supplierName, style: text.titleMedium)),
                        Chip(
                          label: Text(r.statusLabel),
                          side: BorderSide(color: _tone(r.status)),
                        ),
                      ]),
                      Text('${r.lineCount} item(s) · ${r.totalUnits.toStringAsFixed(0)} units · LKR ${r.totalValue.toStringAsFixed(2)}',
                          style: text.bodySmall),
                      if (r.purchaseOrderNumber != null)
                        Text('Purchase order ${r.purchaseOrderNumber}', style: text.bodyMedium),
                      if (r.finalOutcome != null) Text(r.finalOutcome!, style: text.bodySmall),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
