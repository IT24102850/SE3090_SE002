import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';
import 'analytics_screen.dart';
import 'app_notifications.dart';
import 'authenticated_api_client.dart';
import 'equipment_maintenance_screen.dart';
import 'inventory_models.dart';
import 'purchase_order_approval_screen.dart';
import 'stock_check_screen.dart';
import 'stock_count_screen.dart';

class InventoryDashboard extends StatefulWidget {
  const InventoryDashboard({
    super.key,
    required this.client,
    required this.canApprove,
    this.onOpenStockOperations,
  });

  final AuthenticatedApiClient client;
  final bool canApprove;
  final VoidCallback? onOpenStockOperations;

  @override
  State<InventoryDashboard> createState() => _InventoryDashboardState();
}

class _InventoryDashboardState extends State<InventoryDashboard> {
  late final _repository = InventoryDashboardRepository(widget.client);
  DashboardSummary? _summary;
  List<InventoryItem> _allItems = const [];
  List<InventoryItem> _filteredItems = const [];
  String? _error;
  Map<String, dynamic>? _inventoryAiPlan;
  String? _inventoryAiError;
  bool _inventoryAiLoading = false;
  int _inventoryAiStep = 0;
  Timer? _inventoryAiStepTimer;
  bool _loading = true;
  String _searchQuery = '';
  String _selectedFilter = 'All'; // 'All', 'Low Stock', 'Out of Stock'

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _inventoryAiStepTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool showSuccess = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _repository.loadSummary();
      final liveItems = await _repository.loadPreviewItems();
      if (mounted) {
        setState(() {
          _summary = summary;
          _allItems = liveItems;
          _applyFilter();
        });
        if (showSuccess) {
          showAppNotification(
            'Inventory dashboard refreshed. Your stock overview is up to date.',
            tone: AppNotificationTone.success,
            title: 'Dashboard updated',
          );
        }
      }
    } on DioException catch (_) {
      _fail('The inventory API cannot be reached. Check network connection.');
    } on TimeoutException catch (_) {
      _fail('The inventory request timed out. Pull to retry.');
    } catch (error) {
      _fail('Unable to load inventory data: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    var list = _allItems;
    if (_selectedFilter == 'Low Stock') {
      list = list.where((i) => i.isLowStock && i.quantity > 0).toList();
    } else if (_selectedFilter == 'Out of Stock') {
      list = list.where((i) => i.quantity <= 0).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((i) =>
              i.name.toLowerCase().contains(q) ||
              i.sku.toLowerCase().contains(q) ||
              i.category.toLowerCase().contains(q))
          .toList();
    }

    setState(() => _filteredItems = list);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _summary = null;
      _allItems = const [];
      _filteredItems = const [];
    });
    showAppNotification(message, tone: AppNotificationTone.error);
  }

  Future<void> _quickAdjustItem(InventoryItem item) async {
    final qtyController = TextEditingController(text: '1');
    var isAdd = true;

    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Adjust Stock',
      pageBuilder: (dialogCtx, _, __) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Material(
                type: MaterialType.transparency,
                child: GlassCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.cyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.tune_rounded,
                                color: AppColors.cyan, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Adjust Stock',
                                  style: AppTextStyles.title
                                      .copyWith(fontSize: 18),
                                ),
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption
                                      .copyWith(color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setDialogState(() => isAdd = true),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: isAdd
                                      ? AppColors.cyan.withValues(alpha: 0.25)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isAdd
                                        ? AppColors.cyan
                                        : AppColors.glassBorder,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '+ Receive / Add',
                                    style: AppTextStyles.subtitle.copyWith(
                                      color: isAdd
                                          ? AppColors.cyan
                                          : AppColors.textMuted,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setDialogState(() => isAdd = false),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: !isAdd
                                      ? const Color(0xFFF43F5E)
                                          .withValues(alpha: 0.25)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: !isAdd
                                        ? const Color(0xFFF43F5E)
                                        : AppColors.glassBorder,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '- Issue / Remove',
                                    style: AppTextStyles.subtitle.copyWith(
                                      color: !isAdd
                                          ? const Color(0xFFF43F5E)
                                          : AppColors.textMuted,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text('Quantity to ${isAdd ? 'receive' : 'deduct'}',
                          style: AppTextStyles.label),
                      const SizedBox(height: 6),
                      TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        style: AppTextStyles.body.copyWith(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Enter quantity',
                          hintStyle: AppTextStyles.bodyMuted,
                          filled: true,
                          fillColor: AppColors.inputFill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.glassBorder),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: GhostButton(
                              label: 'Cancel',
                              onPressed: () => Navigator.pop(dialogCtx, false),
                              height: 46,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: NeonButton(
                              label: 'Save Change',
                              height: 46,
                              onPressed: () => Navigator.pop(dialogCtx, true),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        });
      },
    );

    if (confirmed != true || !mounted) return;
    final qty = double.tryParse(qtyController.text);
    if (qty == null || qty <= 0) {
      showAppNotification('Please enter a valid positive quantity',
          tone: AppNotificationTone.warning);
      return;
    }

    try {
      final endpoint = isAdd
          ? '/api/inventory/${item.id}/receive'
          : '/api/inventory/${item.id}/adjust';
      final body = isAdd
          ? {
              'quantity': qty,
              'reference': 'DASHBOARD-QUICK-RECEIVE',
              'notes': 'Recorded via SME Mobile Dashboard'
            }
          : {
              'quantity': -qty,
              'reference': 'DASHBOARD-QUICK-ISSUE',
              'notes': 'Adjusted via SME Mobile Dashboard'
            };

      final res = await widget.client.post(endpoint, body: body);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        showAppNotification('Successfully updated ${item.name} stock level.',
            tone: AppNotificationTone.success);
        _load();
      } else {
        showAppNotification('Server rejected adjustment (${res.statusCode})',
            tone: AppNotificationTone.error);
      }
    } catch (e) {
      showAppNotification('Failed to update stock: $e',
          tone: AppNotificationTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackgroundScaffold(
      showParticles: true,
      appBar: GlassAppBar(
        title: 'Inventory Operations',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: AppColors.cyan),
            onPressed: () => _load(showSuccess: true),
          ),
        ],
      ),
      child: SafeArea(
        child: RefreshIndicator(
          color: AppColors.cyan,
          backgroundColor: AppColors.overlaySurface,
          onRefresh: () => _load(showSuccess: true),
          child: _loading
              ? const AppLoader(message: 'Loading inventory hub...')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    // High-tech Hero Banner
                    _buildHeroBanner(),
                    const SizedBox(height: 18),

                    if (_error != null) ...[
                      ErrorState(message: _error!, onRetry: _load),
                      const SizedBox(height: 18),
                    ],

                    // Top 4 Metrics Cards
                    if (_summary != null) ...[
                      _buildMetricCards(_summary!),
                      const SizedBox(height: 22),
                    ],

                    _buildInventoryAiCard(),
                    const SizedBox(height: 22),

                    // Quick Action Launchpad
                    SectionHeader(
                      'OPERATIONAL ACTIONS',
                      trailing: Text('Shortcuts',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.cyan)),
                    ),
                    const SizedBox(height: 12),
                    _buildQuickActionGrid(),
                    const SizedBox(height: 24),

                    // Stock Health Overview & Search
                    SectionHeader(
                      'STOCK LEDGER',
                      trailing: Text(
                          '${_filteredItems.length} of ${_allItems.length} SKUs',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.cyan)),
                    ),
                    const SizedBox(height: 12),

                    // Search and Filter Bar
                    _buildSearchAndFilterBar(),
                    const SizedBox(height: 14),

                    // Items List
                    if (_filteredItems.isEmpty && _error == null)
                      EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: 'No inventory items match',
                        message: _searchQuery.isNotEmpty
                            ? 'No products found matching "$_searchQuery"'
                            : 'No inventory items in this filter group.',
                      )
                    else
                      ..._filteredItems.map((item) => _buildItemCard(item)),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _analyzeInventory() async {
    setState(() {
      _inventoryAiLoading = true;
      _inventoryAiError = null;
      _inventoryAiStep = 0;
    });
    _inventoryAiStepTimer?.cancel();
    _inventoryAiStepTimer = Timer.periodic(const Duration(milliseconds: 2300), (_) {
      if (mounted) setState(() => _inventoryAiStep = (_inventoryAiStep + 1) % 5);
    });
    try {
      final response = await widget.client.post(
        '/api/inventory/agent/plan',
        body: {
          'objective': 'Review overall inventory health, not only low stock. Identify stock coverage risks from recorded issue/sale/consumption, summarize items without recorded outflow and recent waste movements, and explain uncertainty. Do not infer demand from missing history.',
        },
      );
      if (response.body.trim().isEmpty) {
        if (response.statusCode == 401) {
          throw Exception('Your session has expired. Sign in again and retry inventory analysis.');
        }
        if (response.statusCode == 403) {
          throw Exception('Your account does not have permission to read inventory for this branch.');
        }
        if (response.statusCode == 404) {
          throw Exception('The backend does not have the inventory AI endpoint yet. Restart the ASP.NET backend and retry.');
        }
        throw Exception(
          'Inventory AI API returned an empty response (${response.statusCode}). Check the backend endpoint and agent service configuration.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = decoded is Map ? decoded : const <String, dynamic>{};
        final warnings = body['warnings'];
        throw Exception(body['message'] ?? (warnings is List && warnings.isNotEmpty ? warnings.first : 'Inventory AI could not complete the analysis.'));
      }
      if (decoded is! Map<String, dynamic>) throw const FormatException('Unexpected inventory plan response.');
      if (mounted) setState(() => _inventoryAiPlan = decoded);
    } catch (error) {
      if (mounted) setState(() => _inventoryAiError = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      _inventoryAiStepTimer?.cancel();
      _inventoryAiStepTimer = null;
      if (mounted) setState(() => _inventoryAiLoading = false);
    }
  }

  Widget _buildInventoryAiCard() {
    final recommendations = _inventoryAiPlan?['recommendations'];
    return GlassCard(
      padding: const EdgeInsets.all(18),
      borderColor: AppColors.cyan.withValues(alpha: 0.42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: [BoxShadow(color: AppColors.violet.withValues(alpha: 0.16), blurRadius: 18, offset: const Offset(0, 7))],
            ),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: AppColors.glassFill, borderRadius: BorderRadius.circular(13), border: Border.all(color: AppColors.glassBorder)),
                child: Stack(alignment: Alignment.center, children: [
                  const Icon(Icons.inventory_2_rounded, color: AppColors.cyan, size: 23),
                  Positioned(right: 3, top: 3, child: Icon(Icons.auto_awesome_rounded, color: AppColors.magenta.withValues(alpha: 0.95), size: 12)),
                ]),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('STOCKSENSE AI', style: AppTextStyles.label.copyWith(color: AppColors.cyan)),
                const SizedBox(height: 3),
                Text('Inventory health assistant', style: AppTextStyles.caption.copyWith(color: AppColors.textBody)),
              ])),
              const SizedBox(width: 5),
              TextButton(
                onPressed: _inventoryAiLoading ? null : _analyzeInventory,
                child: Text(_inventoryAiLoading ? 'Analyzing…' : 'Analyze'),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Text(
            'Your inventory health assistant: reviews stock coverage, recent usage, and waste signals, then flags replenishment risks. It does not change stock or place orders.',
            style: AppTextStyles.bodyMuted.copyWith(fontSize: 12),
          ),
          if (_inventoryAiLoading) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.cyan, backgroundColor: AppColors.glassBorder)),
                  const SizedBox(width: 11),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('STOCKSENSE IS THINKING', style: AppTextStyles.label.copyWith(color: AppColors.cyan, fontSize: 10)),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero).animate(animation), child: child)),
                      child: Text(
                        const [
                          'Reading your stock snapshot…',
                          'Matching issues, sales and usage…',
                          'Calculating stock coverage…',
                          'Reviewing waste and movement gaps…',
                          'Preparing findings for your review…',
                        ][_inventoryAiStep],
                        key: ValueKey(_inventoryAiStep),
                        style: AppTextStyles.body.copyWith(fontSize: 12),
                      ),
                    ),
                  ])),
                  Text('${_inventoryAiStep + 1}/5', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
                ]),
                const SizedBox(height: 11),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: const LinearProgressIndicator(minHeight: 4, color: AppColors.cyan, backgroundColor: AppColors.glassBorder),
                ),
                const SizedBox(height: 6),
                Text('Analysis can take a little while. Your stock remains unchanged.', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
              ]),
            ),
          ],
          if (_inventoryAiError != null) ...[
            const SizedBox(height: 10),
            Text(_inventoryAiError!, style: AppTextStyles.body.copyWith(color: AppColors.danger)),
          ],
          if (_inventoryAiPlan != null) ...[
            const SizedBox(height: 12),
            Text('${_inventoryAiPlan!['planner_summary'] ?? ''}', style: AppTextStyles.body),
            if (_inventoryAiPlan!['insights'] is List && (_inventoryAiPlan!['insights'] as List).isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('INVENTORY HEALTH INSIGHTS', style: AppTextStyles.label.copyWith(color: AppColors.cyan)),
              ...(_inventoryAiPlan!['insights'] as List).map((entry) {
                if (entry is! Map) return const SizedBox.shrink();
                final insight = Map<String, dynamic>.from(entry);
                final affected = insight['affected_items'];
                final category = '${insight['category'] ?? 'overview'}';
                final insightColor = switch (category) {
                  'coverage' => AppColors.cyan,
                  'movement' => AppColors.magenta,
                  'data_quality' => AppColors.warning,
                  'cost' => AppColors.success,
                  _ => AppColors.violet,
                };
                final insightIcon = switch (category) {
                  'coverage' => Icons.speed_rounded,
                  'movement' => Icons.swap_vert_rounded,
                  'data_quality' => Icons.fact_check_rounded,
                  'cost' => Icons.account_balance_wallet_rounded,
                  _ => Icons.inventory_2_rounded,
                };
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.inputFill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: insightColor.withValues(alpha: 0.38)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(width: 32, height: 32, decoration: BoxDecoration(color: insightColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)), child: Icon(insightIcon, size: 18, color: insightColor)),
                        const SizedBox(width: 9),
                        Expanded(child: Text(category.replaceAll('_', ' ').toUpperCase(), style: AppTextStyles.label.copyWith(color: insightColor, fontSize: 10))),
                      ]),
                      const SizedBox(height: 8),
                      Text('${insight['title'] ?? 'Inventory insight'}', style: AppTextStyles.subtitle),
                      const SizedBox(height: 4),
                      Text('${insight['detail'] ?? ''}', style: AppTextStyles.bodyMuted.copyWith(fontSize: 12)),
                      if (affected is List && affected.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: affected.take(5).map((name) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: insightColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: insightColor.withValues(alpha: 0.22))),
                          child: Text('$name', style: AppTextStyles.caption.copyWith(color: AppColors.textBody)),
                        )).toList()),
                      ],
                    ]),
                  ),
                );
              }),
            ],
            if (recommendations is List && recommendations.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('No replenishment recommendations from the available stock data.', style: AppTextStyles.bodyMuted),
              ),
            if (recommendations is List && recommendations.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('REPLENISHMENT RECOMMENDATIONS', style: AppTextStyles.label.copyWith(color: AppColors.cyan)),
              ...recommendations.map((entry) {
                if (entry is! Map) return const SizedBox.shrink();
                final item = Map<String, dynamic>.from(entry);
                final daily = item['avg_daily_outflow'];
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.inputFill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${item['item_name']}  ·  Reorder ${item['recommended_quantity']}', style: AppTextStyles.subtitle),
                      const SizedBox(height: 4),
                      Text('On hand ${item['on_hand']} / reorder at ${item['reorder_level']}  ·  ${daily == null ? 'No usage history' : '$daily per day'}', style: AppTextStyles.caption),
                      const SizedBox(height: 4),
                      Text('${item['reason']}', style: AppTextStyles.bodyMuted.copyWith(fontSize: 12)),
                    ]),
                  ),
                );
              }),
            ],
            if (_inventoryAiPlan!['warnings'] is List)
              ...(_inventoryAiPlan!['warnings'] as List).map((warning) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('$warning', style: AppTextStyles.caption.copyWith(color: AppColors.warning)),
              )),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E1B4B),
            Color(0xFF0F172A),
            Color(0xFF064E3B),
          ],
        ),
        border: Border.all(
            color: AppColors.cyan.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -25,
            top: -25,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.cyan.withValues(alpha: 0.25),
                    Colors.transparent
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppColors.cyan.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.cyan,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'LIVE TELEMETRY',
                            style: AppTextStyles.label.copyWith(
                              color: AppColors.cyan,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.canApprove)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF10B981).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'MANAGER MODE',
                          style: AppTextStyles.caption.copyWith(
                            color: const Color(0xFF10B981),
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Inventory Command',
                  style: AppTextStyles.headlineSmall.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Unified stock levels, physical counts, PO pipelines & asset maintenance.',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCards(DashboardSummary summary) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _CyberStatCard(
                label: 'TOTAL VALUATION',
                value: 'LKR ${summary.totalValue.toStringAsFixed(2)}',
                icon: Icons.account_balance_wallet_rounded,
                accentColor: const Color(0xFF10B981),
                subLabel: 'Asset on-hand value',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CyberStatCard(
                label: 'LOW STOCK ALERTS',
                value: '${summary.lowStock}',
                icon: Icons.warning_amber_rounded,
                accentColor: summary.lowStock > 0
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF10B981),
                subLabel: summary.lowStock > 0
                    ? 'Requires attention'
                    : 'Optimal reserves',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _CyberStatCard(
                label: 'TOTAL CATALOG SKUS',
                value: '${summary.totalItems}',
                icon: Icons.category_rounded,
                accentColor: AppColors.cyan,
                subLabel: 'Tracked items',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CyberStatCard(
                label: 'PENDING PO QUEUE',
                value: '${summary.pendingOrders}',
                icon: Icons.assignment_late_rounded,
                accentColor: const Color(0xFF8B5CF6),
                subLabel: 'In-review orders',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Scan Movements',
                subtitle: 'Check in / check out',
                color: AppColors.cyan,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => StockCheckScreen(client: widget.client)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionTile(
                icon: Icons.fact_check_rounded,
                title: 'Stock Audit',
                subtitle: 'Physical count',
                color: const Color(0xFF38BDF8),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => StockCountScreen(client: widget.client)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.approval_rounded,
                title: 'PO Approvals',
                subtitle: widget.canApprove ? 'Review & place' : 'View queue',
                color: const Color(0xFF10B981),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PurchaseOrderApprovalScreen(
                      client: widget.client,
                      canApprove: widget.canApprove,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionTile(
                icon: Icons.insights_rounded,
                title: 'Analytics',
                subtitle: 'Trends & usage',
                color: const Color(0xFFA855F7),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => InsightsScreen(client: widget.client)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ActionTile(
          icon: Icons.build_circle_outlined,
          title: 'Equipment Maintenance',
          subtitle:
              'Schedule inspections, record service tasks & track photo logs',
          color: const Color(0xFFF59E0B),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    EquipmentMaintenanceScreen(client: widget.client)),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilterBar() {
    return Column(
      children: [
        // Search Input
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: TextField(
            onChanged: (val) {
              _searchQuery = val;
              _applyFilter();
            },
            style:
                AppTextStyles.body.copyWith(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search items by name, SKU or category...',
              hintStyle: AppTextStyles.bodyMuted.copyWith(fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppColors.textSecondary, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          size: 18, color: AppColors.textSecondary),
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                          _applyFilter();
                        });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterPill('All', _allItems.length),
              const SizedBox(width: 8),
              _buildFilterPill(
                  'Low Stock',
                  _allItems
                      .where((i) => i.isLowStock && i.quantity > 0)
                      .length),
              const SizedBox(width: 8),
              _buildFilterPill('Out of Stock',
                  _allItems.where((i) => i.quantity <= 0).length),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterPill(String label, int count) {
    final isSelected = _selectedFilter == label;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        setState(() {
          _selectedFilter = label;
          _applyFilter();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.cyan.withValues(alpha: 0.2)
              : AppColors.glassFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.cyan : AppColors.glassBorder,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: isSelected ? AppColors.cyan : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.cyan.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showItemQrLabel(InventoryItem item) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final qrSize = (MediaQuery.sizeOf(dialogContext).width - 112)
            .clamp(180.0, 240.0)
            .toDouble();
        return Dialog(
          backgroundColor: AppColors.overlaySurface,
          surfaceTintColor: Colors.transparent,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'QR label · ${item.name}',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.title.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      key: const ValueKey('inventory-item-qr'),
                      data: item.sku,
                      size: qrSize,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    item.sku,
                    style: AppTextStyles.title.copyWith(
                      color: AppColors.cyan,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan this QR from Stock Movements or Physical Stock Count.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Close'),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: item.sku),
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          if (mounted) {
                            showAppNotification(
                              'SKU copied.',
                              tone: AppNotificationTone.success,
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('Copy SKU'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemCard(InventoryItem item) {
    final isOutOfStock = item.quantity <= 0;
    final isLow = item.isLowStock;
    final statusColor = isOutOfStock
        ? const Color(0xFFF43F5E)
        : isLow
            ? const Color(0xFFF59E0B)
            : const Color(0xFF10B981);

    final statusText =
        isOutOfStock ? 'OUT OF STOCK' : (isLow ? 'LOW STOCK' : 'OPTIMAL');

    final progressRatio = item.reorderLevel > 0
        ? (item.quantity / (item.reorderLevel * 2)).clamp(0.02, 1.0)
        : 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderColor: statusColor.withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: AppTextStyles.subtitle.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.glassFill,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: Text(
                              item.sku,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.cyan,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.category,
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.textSecondary),
                          ),
                          if (item.branch.isNotEmpty) ...[
                            Text(' • ',
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.textMuted)),
                            Text(
                              item.branch,
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _InventoryStatusBadge(
                      label: statusText,
                      color: statusColor,
                      icon: isOutOfStock
                          ? Icons.error_outline_rounded
                          : isLow
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline_rounded,
                    ),
                    IconButton(
                      tooltip: 'Show item QR label',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _showItemQrLabel(item),
                      icon: const Icon(
                        Icons.qr_code_2_rounded,
                        color: AppColors.cyan,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Progress bar and stock count
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progressRatio,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  '${item.quantity.toInt()} / ${item.reorderLevel.toInt()} ${item.unit}',
                  style: AppTextStyles.subtitle.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Unit Cost: LKR ${item.unitCost.toStringAsFixed(2)}',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _quickAdjustItem(item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Tap to adjust',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.cyan,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            size: 16, color: AppColors.cyan),
                      ],
                    ),
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

class _InventoryStatusBadge extends StatefulWidget {
  const _InventoryStatusBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  State<_InventoryStatusBadge> createState() => _InventoryStatusBadgeState();
}

class _InventoryStatusBadgeState extends State<_InventoryStatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final pulse = 0.75 + (_animationController.value * 0.25);
        final sweep = -1.2 + (_animationController.value * 2.4);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.16 * pulse),
                blurRadius: 10 + (pulse * 4),
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.color.withValues(alpha: 0.45 * pulse),
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FractionalTranslation(
                      translation: Offset(sweep, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 22,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                widget.color.withValues(alpha: 0.22),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.icon, size: 12, color: widget.color),
                        const SizedBox(width: 4),
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: widget.color,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CyberStatCard extends StatelessWidget {
  const _CyberStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.subLabel,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final String subLabel;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderColor: accentColor.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: AppTextStyles.label.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.textMuted,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 15, color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.headlineSmall.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subLabel,
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderColor: color.withValues(alpha: 0.3),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.subtitle.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded,
              size: 13, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class InventoryDashboardRepository {
  InventoryDashboardRepository(this._client);
  final AuthenticatedApiClient _client;

  Future<DashboardSummary> loadSummary() async {
    final results = await Future.wait([_loadInventory(), _loadPendingOrders()]);
    final items = results[0] as List<_DashboardItem>;
    final pendingOrders = results[1] as int;
    final lowStock = items
        .where(
            (item) => item.quantity <= 0 || item.quantity <= item.reorderLevel)
        .length;
    final value = items.fold<double>(
        0, (total, item) => total + (item.quantity * item.unitCost));
    return DashboardSummary(
      totalItems: items.length,
      totalValue: value,
      lowStock: lowStock,
      pendingOrders: pendingOrders,
    );
  }

  Future<List<_DashboardItem>> _loadInventory() async {
    final items = <_DashboardItem>[];
    var page = 1;
    var totalPages = 1;
    while (page <= totalPages) {
      final response =
          await _client.get('/api/inventory?page=$page&pageSize=100');
      if (response.statusCode != 200) {
        throw Exception('Inventory request failed');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
      items.addAll(((data['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_DashboardItem.fromJson));
      page++;
    }
    return items;
  }

  Future<int> _loadPendingOrders() async {
    final response =
        await _client.get('/api/purchase-orders?status=InReview&pageSize=1');
    if (response.statusCode != 200) {
      throw Exception('Purchase order request failed');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['totalCount'] as num?)?.toInt() ?? 0;
  }

  Future<List<InventoryItem>> loadPreviewItems() async {
    final response = await _client.get('/api/inventory?page=1&pageSize=100');
    if (response.statusCode != 200) {
      throw Exception('Inventory preview request failed');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ((data['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(InventoryItem.fromJson)
        .toList();
  }
}

class _DashboardItem {
  const _DashboardItem({
    required this.quantity,
    required this.reorderLevel,
    required this.unitCost,
  });
  final double quantity, reorderLevel, unitCost;
  factory _DashboardItem.fromJson(Map<String, dynamic> json) => _DashboardItem(
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        reorderLevel: (json['reorderLevel'] as num?)?.toDouble() ?? 0,
        unitCost: (json['unitCost'] as num?)?.toDouble() ?? 0,
      );
}

class DashboardSummary {
  const DashboardSummary({
    required this.totalItems,
    required this.totalValue,
    required this.lowStock,
    required this.pendingOrders,
  });
  final int totalItems, lowStock, pendingOrders;
  final double totalValue;
}
