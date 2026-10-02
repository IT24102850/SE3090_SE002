import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'inventory_scaffold.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';
import 'app_notifications.dart';
import 'authenticated_api_client.dart';
import 'inventory_panel.dart';
import 'inventory_loading_state.dart';
import 'equipment_maintenance_screen.dart';
import 'inventory_models.dart';
import 'purchase_order_approval_screen.dart';
import 'stock_activity_history_screen.dart';
import 'stock_count_screen.dart';

String _formatQuantity(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

String _compactLkr(double value) {
  if (value >= 1000000000) {
    return 'LKR ${(value / 1000000000).toStringAsFixed(1)}B';
  }
  if (value >= 1000000) {
    return 'LKR ${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 10000) {
    return 'LKR ${(value / 1000).toStringAsFixed(1)}K';
  }
  return 'LKR ${value.toStringAsFixed(0)}';
}

class InventoryDashboard extends StatefulWidget {
  const InventoryDashboard({
    super.key,
    required this.client,
    required this.canApprove,
    this.role,
    this.canReceive = false,
    this.assignedBranchId,
  });

  final AuthenticatedApiClient client;
  final bool canApprove;
  final String? role;
  final bool canReceive;
  final String? assignedBranchId;

  @override
  State<InventoryDashboard> createState() => _InventoryDashboardState();
}

class _InventoryDashboardState extends State<InventoryDashboard>
    with SingleTickerProviderStateMixin {
  static const _previewLimit = 100;
  late final _repository = InventoryDashboardRepository(widget.client);
  DashboardSummary? _summary;
  List<InventoryItem> _allItems = const [];
  List<InventoryItem> _filteredItems = const [];
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey _ledgerSectionKey = GlobalKey();
  String? _error;
  bool _loading = true;
  bool _requestInFlight = false;
  String _searchQuery = '';
  String _selectedFilter = 'All';
  String _sortMode = 'Stock health';

  late final AnimationController _enterCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final CurvedAnimation _enterAnim = CurvedAnimation(
    parent: _enterCtrl,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    _load();
    _enterCtrl.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _enterCtrl.dispose();
    _enterAnim.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSuccess = false}) async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dashboard =
          await _repository.loadDashboard(previewLimit: _previewLimit);
      if (mounted) {
        setState(() {
          _summary = dashboard.summary;
          _allItems = dashboard.previewItems;
          _filteredItems = _filterItems();
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
      _requestInFlight = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    setState(() => _filteredItems = _filterItems());
  }

  void _selectDashboardFilter(String filter) {
    setState(() {
      _selectedFilter = filter;
      _filteredItems = _filterItems();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ledgerContext = _ledgerSectionKey.currentContext;
      if (!mounted || ledgerContext == null) return;
      Scrollable.ensureVisible(
        ledgerContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  List<InventoryItem> _filterItems() {
    var list = List<InventoryItem>.of(_allItems);
    switch (_selectedFilter) {
      case 'Needs attention':
        list = list.where((item) => item.isLowStock).toList();
        break;
      case 'Low stock':
        list =
            list.where((item) => item.isLowStock && item.quantity > 0).toList();
        break;
      case 'Out of stock':
        list = list.where((item) => item.quantity <= 0).toList();
        break;
      case 'In stock':
        list = list.where((item) => !item.isLowStock).toList();
        break;
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list
          .where((item) =>
              '${item.name} ${item.sku} ${item.category} ${item.branch}'
                  .toLowerCase()
                  .contains(query))
          .toList();
    }

    int rank(InventoryItem item) => item.quantity <= 0
        ? 0
        : item.isLowStock
            ? 1
            : 2;
    switch (_sortMode) {
      case 'Name A–Z':
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 'Quantity low to high':
        list.sort((a, b) => a.quantity.compareTo(b.quantity));
        break;
      case 'Quantity high to low':
        list.sort((a, b) => b.quantity.compareTo(a.quantity));
        break;
      default:
        list.sort((a, b) {
          final health = rank(a).compareTo(rank(b));
          return health != 0
              ? health
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    }
    return list;
  }

  List<List<InventoryItem>> get _visibleStockGroups {
    final groups = <List<InventoryItem>>[];
    final seen = <String>{};
    for (final item in _filteredItems) {
      final key = _stockGroupKey(item);
      if (!seen.add(key)) continue;
      final group = _allItems
          .where((candidate) => _stockGroupKey(candidate) == key)
          .toList()
        ..sort(
            (a, b) => a.branch.toLowerCase().compareTo(b.branch.toLowerCase()));
      groups.add(group);
    }
    return groups;
  }

  String _stockGroupKey(InventoryItem item) {
    final sku = item.sku.trim().toLowerCase();
    return sku.isNotEmpty
        ? 'sku:$sku'
        : 'name:${item.name.trim().toLowerCase()}|${item.category.trim().toLowerCase()}';
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
                child: InventoryPanel(
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
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            return RegExp(r'^\d*\.?\d{0,3}$')
                                    .hasMatch(newValue.text)
                                ? newValue
                                : oldValue;
                          }),
                        ],
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

    final enteredQuantity = qtyController.text.trim();
    qtyController.dispose();
    if (confirmed != true || !mounted) return;
    final qty = double.tryParse(enteredQuantity);
    if (qty == null || qty <= 0) {
      showAppNotification('Please enter a valid positive quantity',
          tone: AppNotificationTone.warning);
      return;
    }
    if (!isAdd && qty > item.quantity) {
      showAppNotification(
        'You can issue up to ${_formatQuantity(item.quantity)} ${item.unit}.',
        tone: AppNotificationTone.warning,
      );
      return;
    }

    try {
      final endpoint = isAdd
          ? '/api/inventory/${item.id}/receive'
          : '/api/inventory/${item.id}/issue';
      final body = isAdd
          ? {
              'quantity': qty,
              'reference': 'DASHBOARD-QUICK-RECEIVE',
              'notes': 'Recorded via SME Mobile Dashboard'
            }
          : {
              'quantity': qty,
              'reference': 'DASHBOARD-QUICK-ISSUE',
              'notes': 'Issued via SME Mobile Dashboard'
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
    return InventoryScaffold(
      showParticles: false,
      appBar: GlassAppBar(
        title: 'Inventory Operations',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: _requestInFlight
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.cyan,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, color: AppColors.cyan),
            onPressed: _requestInFlight ? null : () => _load(showSuccess: true),
          ),
        ],
      ),
      child: SafeArea(
        child: RefreshIndicator(
          color: AppColors.cyan,
          backgroundColor: AppColors.overlaySurface,
          onRefresh: () => _load(showSuccess: true),
          child: _loading && _summary == null
              ? const InventoryLoadingState(
                  message: 'Loading inventory hub',
                  detail: 'Preparing your inventory overview',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 360),
                      reverseDuration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final slide = Tween<Offset>(
                          begin: const Offset(0, .035),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ));
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: slide,
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        key: const ValueKey('inventory-home-page'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_loading)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 10),
                              child: LinearProgressIndicator(
                                minHeight: 2,
                                color: AppColors.cyan,
                                backgroundColor: AppColors.glassBorder,
                              ),
                            ),
                          // High-tech Hero Banner
                          FadeTransition(
                            opacity: CurvedAnimation(
                              parent: _enterCtrl,
                              curve: const Interval(0.0, 0.6,
                                  curve: Curves.easeOut),
                            ),
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, .06),
                                end: Offset.zero,
                              ).animate(CurvedAnimation(
                                parent: _enterCtrl,
                                curve: const Interval(0.0, 0.6,
                                    curve: Curves.easeOutCubic),
                              )),
                              child: _buildHeroBanner(),
                            ),
                          ),
                          const SizedBox(height: 18),

                          if (_error != null) ...[
                            ErrorState(message: _error!, onRetry: _load),
                            const SizedBox(height: 18),
                          ],

                          // Inventory health at a glance.
                          if (_summary != null) ...[
                            FadeTransition(
                              opacity: CurvedAnimation(
                                parent: _enterCtrl,
                                curve: const Interval(0.2, 0.75,
                                    curve: Curves.easeOut),
                              ),
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, .05),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(
                                  parent: _enterCtrl,
                                  curve: const Interval(0.2, 0.75,
                                      curve: Curves.easeOutCubic),
                                )),
                                child: _buildMetricCards(_summary!),
                              ),
                            ),
                            const SizedBox(height: 22),
                          ],

                          // Quick Action Launchpad
                          SectionHeader(
                            'OPERATIONAL ACTIONS',
                            trailing: Text('Shortcuts',
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.cyan)),
                          ),
                          const SizedBox(height: 12),
                          FadeTransition(
                            opacity: CurvedAnimation(
                              parent: _enterCtrl,
                              curve: const Interval(0.4, 0.85,
                                  curve: Curves.easeOut),
                            ),
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, .04),
                                end: Offset.zero,
                              ).animate(CurvedAnimation(
                                parent: _enterCtrl,
                                curve: const Interval(0.4, 0.85,
                                    curve: Curves.easeOutCubic),
                              )),
                              child: _buildQuickActionGrid(),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Stock Health Overview & Search
                          KeyedSubtree(
                            key: _ledgerSectionKey,
                            child: SectionHeader(
                              'STOCK LEDGER',
                              trailing: Text(
                                  '${_filteredItems.length} shown · ${_summary?.totalItems ?? _allItems.length} total',
                                  style: AppTextStyles.caption
                                      .copyWith(color: AppColors.cyan)),
                            ),
                          ),
                          const SizedBox(height: 12),

                          if ((_summary?.totalItems ?? _allItems.length) >
                              _allItems.length) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                color: AppColors.cyan.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                    color:
                                        AppColors.cyan.withValues(alpha: .2)),
                              ),
                              child: Row(children: [
                                const Icon(Icons.info_outline_rounded,
                                    size: 16, color: AppColors.cyan),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Showing the first ${_allItems.length} of ${_summary!.totalItems} items. Search and filters apply to this preview.',
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textSecondary,
                                        height: 1.35),
                                  ),
                                ),
                              ]),
                            ),
                          ],

                          // Search and Filter Bar
                          _buildSearchAndFilterBar(),
                          const SizedBox(height: 14),

                          // Items List
                          if (_filteredItems.isEmpty && _error == null)
                            _allItems.isEmpty
                                ? const EmptyState(
                                    icon: Icons.inventory_2_outlined,
                                    title: 'Your inventory is ready to begin',
                                    message:
                                        'Items will appear here once your catalog has stock records.',
                                  )
                                : InventoryPanel(
                                    child: Column(
                                      children: [
                                        const Icon(Icons.filter_alt_off_rounded,
                                            color: AppColors.textMuted,
                                            size: 30),
                                        const SizedBox(height: 9),
                                        Text('No items match this view',
                                            style: AppTextStyles.subtitle
                                                .copyWith(
                                                    fontWeight:
                                                        FontWeight.w800)),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Try another filter or clear your search.',
                                          textAlign: TextAlign.center,
                                          style: AppTextStyles.caption.copyWith(
                                              color: AppColors.textSecondary),
                                        ),
                                        const SizedBox(height: 11),
                                        TextButton.icon(
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {
                                              _searchQuery = '';
                                              _selectedFilter = 'All';
                                              _filteredItems = _filterItems();
                                            });
                                          },
                                          icon: const Icon(
                                              Icons.restart_alt_rounded),
                                          label: const Text('Reset filters'),
                                        ),
                                      ],
                                    ),
                                  )
                          else
                            ..._visibleStockGroups
                                .map((items) => _buildItemCard(items)),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHeroBanner() {
    return _AnimatedHeroBanner(
      summary: _summary,
      allItemsLength: _allItems.length,
      loading: _loading,
      role: widget.role,
    );
  }

  Widget _buildMetricCards(DashboardSummary summary) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _CyberStatCard(
                key: const Key('dashboard-metric-valuation'),
                label: 'TOTAL VALUATION',
                value: _compactLkr(summary.totalValue),
                icon: Icons.account_balance_wallet_rounded,
                accentColor: const Color(0xFF8AE8C7),
                subLabel: 'Tap to review all inventory',
                onTap: () => _selectDashboardFilter('All'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CyberStatCard(
                key: const Key('dashboard-metric-low-stock'),
                label: 'LOW STOCK',
                value: '${summary.lowStock}',
                icon: Icons.warning_amber_rounded,
                accentColor: summary.lowStock > 0
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF55D6C2),
                subLabel: summary.lowStock > 0
                    ? 'Tap to review low stock'
                    : 'Reorder levels healthy',
                onTap: () => _selectDashboardFilter('Low stock'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _CyberStatCard(
                key: const Key('dashboard-metric-out-of-stock'),
                label: 'OUT OF STOCK',
                value: '${summary.outOfStock}',
                icon: Icons.remove_shopping_cart_rounded,
                accentColor: summary.outOfStock > 0
                    ? const Color(0xFFF16D83)
                    : const Color(0xFF55D6C2),
                subLabel: summary.outOfStock > 0
                    ? 'Tap to review empty items'
                    : 'Nothing empty',
                onTap: () => _selectDashboardFilter('Out of stock'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CyberStatCard(
                key: const Key('dashboard-metric-pending-orders'),
                label: 'PENDING PO QUEUE',
                value: '${summary.pendingOrders}',
                icon: Icons.assignment_late_rounded,
                accentColor: const Color(0xFFB28CFF),
                subLabel: 'Tap to review orders',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PurchaseOrderApprovalScreen(
                      client: widget.client,
                      canApprove: widget.canApprove,
                      canCreate: widget.canApprove || widget.role == 'Staff',
                      canCreateMultiBranch: widget.role == 'Admin',
                      canReceive: widget.canReceive,
                      assignedBranchId: widget.assignedBranchId,
                      requiresAssignedBranch: widget.role != 'Admin',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: compactWidth,
              child: _ActionTile(
                key: const Key('dashboard-action-stock-activity'),
                icon: Icons.history_rounded,
                title: 'Stock Activity',
                subtitle: 'Review or record stock movements',
                color: AppColors.cyan,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        StockActivityHistoryScreen(client: widget.client),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: compactWidth,
              child: _ActionTile(
                key: const Key('dashboard-action-stock-audit'),
                compact: true,
                icon: Icons.fact_check_rounded,
                title: 'Stock Audit',
                subtitle: 'Record a physical count',
                color: const Color(0xFF38BDF8),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StockCountScreen(client: widget.client),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: compactWidth,
              child: _ActionTile(
                key: const Key('dashboard-action-purchase-orders'),
                compact: true,
                icon: Icons.receipt_long_rounded,
                title: 'Purchase Orders',
                subtitle: widget.canApprove
                    ? 'Review & place'
                    : widget.role == 'Staff'
                        ? 'Create a branch request'
                        : widget.canReceive
                            ? 'View & receive'
                            : 'View queue',
                color: const Color(0xFF10B981),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PurchaseOrderApprovalScreen(
                      client: widget.client,
                      canApprove: widget.canApprove,
                      canCreate: widget.canApprove || widget.role == 'Staff',
                      canCreateMultiBranch: widget.role == 'Admin',
                      canReceive: widget.canReceive,
                      assignedBranchId: widget.assignedBranchId,
                      requiresAssignedBranch: widget.role != 'Admin',
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: compactWidth,
              child: _ActionTile(
                key: const Key('dashboard-action-maintenance'),
                compact: true,
                icon: Icons.build_circle_outlined,
                title: 'Maintenance',
                subtitle: 'Inspections & service records',
                color: const Color(0xFFF59E0B),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        EquipmentMaintenanceScreen(client: widget.client),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchAndFilterBar() {
    final filters = <(String, int)>[
      ('All', _allItems.length),
      ('Needs attention', _allItems.where((item) => item.isLowStock).length),
      (
        'Low stock',
        _allItems.where((item) => item.isLowStock && item.quantity > 0).length
      ),
      ('Out of stock', _allItems.where((item) => item.quantity <= 0).length),
      ('In stock', _allItems.where((item) => !item.isLowStock).length),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (val) {
            _searchQuery = val;
            _applyFilter();
          },
          textInputAction: TextInputAction.search,
          style: AppTextStyles.body.copyWith(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search name, SKU, category or branch',
            hintStyle: AppTextStyles.bodyMuted.copyWith(fontSize: 13),
            prefixIcon: const Icon(Icons.search_rounded,
                color: AppColors.textSecondary, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.clear_rounded,
                        size: 18, color: AppColors.textSecondary),
                    onPressed: () {
                      _searchController.clear();
                      _searchQuery = '';
                      _applyFilter();
                    },
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFF141D2C),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: AppColors.glassBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: AppColors.glassBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: AppColors.cyan, width: 1.4),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: filters
                .map((filter) => Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: _buildFilterPill(filter.$1, filter.$2),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 9),
        Row(children: [
          Text('Sort',
              style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _sortMode,
              isExpanded: true,
              dropdownColor: const Color(0xFF172235),
              style: AppTextStyles.caption.copyWith(color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: const Color(0xFF141D2C),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.glassBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.glassBorder)),
              ),
              items: const [
                'Stock health',
                'Name A–Z',
                'Quantity low to high',
                'Quantity high to low',
              ]
                  .map((mode) =>
                      DropdownMenuItem(value: mode, child: Text(mode)))
                  .toList(),
              onChanged: (mode) {
                if (mode == null) return;
                setState(() {
                  _sortMode = mode;
                  _filteredItems = _filterItems();
                });
              },
            ),
          ),
          if (_searchQuery.isNotEmpty ||
              _selectedFilter != 'All' ||
              _sortMode != 'Stock health')
            TextButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _selectedFilter = 'All';
                  _sortMode = 'Stock health';
                  _filteredItems = _filterItems();
                });
              },
              child: const Text('Reset'),
            ),
        ]),
      ],
    );
  }

  Widget _buildFilterPill(String label, int count) {
    final isSelected = _selectedFilter == label;
    return InkWell(
      key: Key('dashboard-filter-${label.toLowerCase().replaceAll(' ', '-')}'),
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        setState(() {
          _selectedFilter = label;
          _filteredItems = _filterItems();
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
                      color: AppColors.onPrimary,
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
                    'Scan this QR from Physical Stock Count.',
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

  Widget _buildItemCard(List<InventoryItem> items) {
    final item = items.first;
    final outOfStockBranches =
        items.where((stock) => stock.quantity <= 0).length;
    final lowStockBranches =
        items.where((stock) => stock.quantity > 0 && stock.isLowStock).length;
    final totalQuantity =
        items.fold<double>(0, (total, stock) => total + stock.quantity);
    final totalReorderLevel =
        items.fold<double>(0, (total, stock) => total + stock.reorderLevel);
    final statusColor = outOfStockBranches > 0
        ? const Color(0xFFF16D83)
        : lowStockBranches > 0
            ? const Color(0xFFF3B64D)
            : const Color(0xFF55D6C2);
    final statusText = outOfStockBranches > 0
        ? 'OUT AT $outOfStockBranches'
        : lowStockBranches > 0
            ? 'LOW AT $lowStockBranches'
            : '${items.length} ${items.length == 1 ? 'BRANCH' : 'BRANCHES'}';
    final progress = totalReorderLevel > 0
        ? (totalQuantity / totalReorderLevel).clamp(0.0, 1.0)
        : (totalQuantity > 0 ? 1.0 : 0.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      child: InventoryPanel(
        padding: const EdgeInsets.all(15),
        borderColor: statusColor.withValues(alpha: .3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.subtitle.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _InventoryStatusBadge(
                key: ValueKey('${item.sku}:$statusText'),
                label: statusText,
                color: statusColor,
                icon: outOfStockBranches > 0
                    ? Icons.remove_shopping_cart_rounded
                    : lowStockBranches > 0
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline_rounded,
              ),
            ]),
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 6,
              children: [
                _ItemInfoChip(label: item.sku, icon: Icons.qr_code_2_rounded),
                _ItemInfoChip(
                    label: item.category, icon: Icons.category_outlined),
              ],
            ),
            const SizedBox(height: 15),
            Row(children: [
              const Icon(Icons.inventory_2_outlined,
                  color: AppColors.textMuted, size: 16),
              const SizedBox(width: 6),
              Text('ON HAND',
                  style: AppTextStyles.label.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 9,
                      letterSpacing: .7)),
              const Spacer(),
              Text(
                '${_formatQuantity(totalQuantity)} ${item.unit}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.subtitle
                    .copyWith(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ]),
            const SizedBox(height: 8),
            ...items.map((stock) => _buildBranchStockRow(stock)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: Colors.white.withValues(alpha: .08),
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${item.unitCost == null ? 'Unit cost not set' : 'LKR ${item.unitCost!.toStringAsFixed(2)}'} / ${item.unit}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textMuted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchStockRow(InventoryItem item) {
    final outOfStock = item.quantity <= 0;
    final lowStock = item.isLowStock;
    final statusColor = outOfStock
        ? const Color(0xFFF16D83)
        : lowStock
            ? const Color(0xFFF3B64D)
            : const Color(0xFF55D6C2);
    final statusLabel = outOfStock
        ? 'OUT'
        : lowStock
            ? 'LOW'
            : 'OK';

    return Container(
      key: ValueKey('dashboard-branch-stock-${item.id}'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront_outlined,
              color: AppColors.cyan, size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.branch.isEmpty ? 'Unassigned branch' : item.branch,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Reorder at ${_formatQuantity(item.reorderLevel)} ${item.unit}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${_formatQuantity(item.quantity)} ${item.unit}',
            style: AppTextStyles.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            statusLabel,
            style: AppTextStyles.caption.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w800,
              fontSize: 9,
            ),
          ),
          IconButton(
            tooltip: 'Adjust stock at ${item.branch}',
            onPressed: () => _quickAdjustItem(item),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: EdgeInsets.zero,
            icon:
                const Icon(Icons.tune_rounded, color: AppColors.cyan, size: 17),
          ),
          IconButton(
            tooltip: 'Item label for ${item.branch}',
            onPressed: () => _showItemQrLabel(item),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.qr_code_2_rounded,
                color: AppColors.textSecondary, size: 17),
          ),
        ],
      ),
    );
  }
}

class _InventoryStatusBadge extends StatefulWidget {
  const _InventoryStatusBadge({
    super.key,
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse = Curves.easeInOut.transform(_controller.value);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.color.withValues(alpha: .22 + (.2 * pulse)),
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: .08 + (.12 * pulse)),
                blurRadius: 4 + (5 * pulse),
                spreadRadius: pulse,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Transform.scale(
                    scale: .9 + (.15 * pulse),
                    child: Icon(widget.icon, size: 13, color: widget.color),
                  ),
                  const SizedBox(width: 5),
                  Text(widget.label,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: widget.color,
                          letterSpacing: .35)),
                ]),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment(-1.5 + (4 * _controller.value), 0),
                      child: FractionallySizedBox(
                        widthFactor: .38,
                        heightFactor: 1.8,
                        child: Transform.rotate(
                          angle: -.28,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  widget.color.withValues(alpha: .28),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.violet.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.violet.withValues(alpha: .35)),
        ),
        child: Text(label,
            style: AppTextStyles.label.copyWith(
                color: const Color(0xFFC3AEFF),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: .5)),
      );
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: .09)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: const Color(0xFF9FE8F2)),
          const SizedBox(width: 6),
          Text(label,
              style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 10)),
        ]),
      );
}

class _ItemInfoChip extends StatelessWidget {
  const _ItemInfoChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 190),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: AppColors.cyan),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

class _CyberStatCard extends StatefulWidget {
  const _CyberStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.subLabel,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final String subLabel;
  final VoidCallback? onTap;

  @override
  State<_CyberStatCard> createState() => _CyberStatCardState();
}

class _CyberStatCardState extends State<_CyberStatCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  bool _pressed = false;

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (context, _) {
        final pulse = Curves.easeInOut.transform(_glowCtrl.value);
        return GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap?.call();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1A3540),
                    Color.lerp(
                        const Color(0xFF122630), widget.accentColor, 0.09)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color:
                      widget.accentColor.withValues(alpha: 0.2 + 0.15 * pulse),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.accentColor
                        .withValues(alpha: 0.08 + 0.1 * pulse),
                    blurRadius: 16 + 10 * pulse,
                    spreadRadius: pulse,
                    offset: const Offset(0, 4),
                  ),
                  const BoxShadow(
                    color: Color(0x30000000),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Animated top accent bar
                  Container(
                    height: 3,
                    width: 38 + 10 * pulse,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      gradient: LinearGradient(colors: [
                        widget.accentColor,
                        widget.accentColor.withValues(alpha: .3),
                      ]),
                      boxShadow: [
                        BoxShadow(
                          color: widget.accentColor.withValues(alpha: 0.5),
                          blurRadius: 6 + 4 * pulse,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Glowing icon box
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: RadialGradient(colors: [
                            widget.accentColor
                                .withValues(alpha: 0.22 + 0.1 * pulse),
                            widget.accentColor.withValues(alpha: 0.06),
                          ]),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: widget.accentColor
                                .withValues(alpha: 0.25 + 0.1 * pulse),
                          ),
                        ),
                        child: Icon(widget.icon,
                            size: 18, color: widget.accentColor),
                      ),
                      const Spacer(),
                      if (widget.onTap != null)
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: widget.accentColor.withValues(alpha: 0.5),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.label.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.headlineSmall.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.subLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 10,
                      color: AppColors.textSecondary,
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

class _ActionTile extends StatefulWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.all(widget.compact ? 13 : 15),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A3540),
                Color.lerp(const Color(0xFF122630), widget.color, 0.1)!,
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _pressed
                  ? widget.color.withValues(alpha: 0.55)
                  : widget.color.withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _pressed
                    ? widget.color.withValues(alpha: 0.22)
                    : widget.color.withValues(alpha: 0.08),
                blurRadius: _pressed ? 20 : 10,
                offset: const Offset(0, 5),
              ),
              const BoxShadow(
                color: Color(0x30000000),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: widget.compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildIcon(size: 40),
                        const Spacer(),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: widget.color.withValues(alpha: 0.55),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.subtitle.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        height: 1.35,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    _buildIcon(),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: AppTextStyles.subtitle.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              letterSpacing: -.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: widget.color.withValues(alpha: 0.55),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildIcon({double size = 44}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: RadialGradient(colors: [
          widget.color.withValues(alpha: 0.22),
          widget.color.withValues(alpha: 0.06),
        ]),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: widget.color.withValues(alpha: 0.28)),
      ),
      child: Icon(widget.icon, color: widget.color, size: size * .48),
    );
  }
}

class InventoryDashboardRepository {
  InventoryDashboardRepository(this._client);
  final AuthenticatedApiClient _client;

  Future<({DashboardSummary summary, List<InventoryItem> previewItems})>
      loadDashboard({int previewLimit = 100}) async {
    final results = await Future.wait<Object>([
      _loadInventory(),
      _loadPendingOrders(),
    ]);
    final items = results[0] as List<InventoryItem>;
    final pendingOrders = results[1] as int;
    final outOfStock = items.where((item) => item.quantity <= 0).length;
    final lowStock =
        items.where((item) => item.quantity > 0 && item.isLowStock).length;
    final value =
        items.fold<double>(0, (total, item) => total + item.totalValue);

    return (
      summary: DashboardSummary(
        totalItems: items.length,
        totalValue: value,
        lowStock: lowStock,
        outOfStock: outOfStock,
        pendingOrders: pendingOrders,
      ),
      previewItems: items.take(previewLimit).toList(growable: false),
    );
  }

  Future<List<InventoryItem>> _loadInventory() async {
    final items = <InventoryItem>[];
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
          .map(InventoryItem.fromJson));
      page++;
    }
    return items;
  }

  Future<int> _loadPendingOrders() async {
    var page = 1;
    var totalPages = 1;
    var pending = 0;
    const terminal = {'received', 'cancelled'};
    do {
      final response =
          await _client.get('/api/purchase-orders?page=$page&pageSize=100');
      if (response.statusCode != 200) {
        throw Exception('Purchase order request failed');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (data['items'] as List?) ?? const [];
      pending += items.where((order) {
        final status =
            (order is Map ? order['status'] : null)?.toString().toLowerCase() ??
                '';
        return !terminal.contains(status);
      }).length;
      if (page == 1) {
        totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
      }
      page++;
    } while (page <= totalPages);
    return pending;
  }
}

class DashboardSummary {
  const DashboardSummary({
    required this.totalItems,
    required this.totalValue,
    required this.lowStock,
    required this.outOfStock,
    required this.pendingOrders,
  });
  final int totalItems, lowStock, outOfStock, pendingOrders;
  final double totalValue;
}

class _AnimatedHeroBanner extends StatefulWidget {
  const _AnimatedHeroBanner({
    required this.summary,
    required this.allItemsLength,
    required this.loading,
    this.role,
  });

  final DashboardSummary? summary;
  final int allItemsLength;
  final bool loading;
  final String? role;

  @override
  State<_AnimatedHeroBanner> createState() => _AnimatedHeroBannerState();
}

class _AnimatedHeroBannerState extends State<_AnimatedHeroBanner>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat(reverse: true);

  late final AnimationController _sheenCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  late final AnimationController _floatCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _sheenCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseCtrl, _sheenCtrl, _floatCtrl]),
      builder: (context, _) {
        final pulse = Curves.easeInOut.transform(_pulseCtrl.value);
        final floatY = -4.0 * Curves.easeInOut.transform(_floatCtrl.value);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Color.lerp(
                const Color(0xFF47776D),
                const Color(0xFF8AE8C7),
                pulse,
              )!
                  .withValues(alpha: 0.6 + 0.3 * pulse),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4F46E5)
                    .withValues(alpha: 0.15 + 0.12 * pulse),
                blurRadius: 28 + 12 * pulse,
                spreadRadius: 2 * pulse,
                offset: const Offset(0, 8),
              ),
              const BoxShadow(
                color: Color(0x40000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1.0 + 0.4 * pulse, -1.0),
                  end: Alignment(1.0, 1.0 - 0.4 * pulse),
                  colors: [
                    Color.lerp(const Color(0xFF174B4D), const Color(0xFF244B44),
                        pulse)!,
                    Color.lerp(const Color(0xFF17343E), const Color(0xFF203C45),
                        pulse)!,
                    const Color(0xFF122A35),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // Ambient glowing orb top right
                  Positioned(
                    right: -30,
                    top: -50,
                    child: Container(
                      width: 180 + 30 * pulse,
                      height: 180 + 30 * pulse,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF7C3AED)
                                .withValues(alpha: 0.22 + 0.12 * pulse),
                            const Color(0xFF06B6D4).withValues(alpha: 0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Ambient secondary glow bottom left
                  Positioned(
                    left: -20,
                    bottom: -30,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF00E5FF)
                                .withValues(alpha: 0.12 + 0.08 * pulse),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Shimmer sweep beam
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment(-2.0 + 4.0 * _sheenCtrl.value, 0),
                        child: Transform.rotate(
                          angle: -0.35,
                          child: Container(
                            width: 60,
                            height: 400,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.white.withValues(alpha: 0.05),
                                  Colors.white.withValues(alpha: 0.12),
                                  Colors.white.withValues(alpha: 0.05),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Main content
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // 3D Bobbing glowing icon container
                            Transform.translate(
                              offset: Offset(0, floatY),
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF312E81),
                                      Color(0xFF1E1B4B),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF6366F1)
                                        .withValues(alpha: 0.4 + 0.3 * pulse),
                                    width: 1.4,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF6366F1)
                                          .withValues(alpha: 0.3 + 0.2 * pulse),
                                      blurRadius: 14 + 6 * pulse,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.inventory_2_rounded,
                                  color: Color(0xFF67E8F9),
                                  size: 26,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFF22C55E),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF22C55E)
                                                  .withValues(alpha: 0.7),
                                              blurRadius: 6 + 4 * pulse,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'LIVE OPERATIONS',
                                        style: AppTextStyles.label.copyWith(
                                          color: const Color(0xFF67E8F9),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  ShaderMask(
                                    shaderCallback: (bounds) =>
                                        const LinearGradient(
                                      colors: [
                                        Colors.white,
                                        Color(0xFFE0E7FF),
                                        Color(0xFFC7D2FE),
                                      ],
                                    ).createShader(bounds),
                                    child: Text(
                                      'Inventory Hub',
                                      style: AppTextStyles.title.copyWith(
                                        fontSize: 23,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.6,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.role case final role?)
                              _RoleBadge(label: role.trim().toUpperCase()),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Real-time overview of products, stock movements, branch allocations, and reorder levels.',
                          style: AppTextStyles.body.copyWith(
                            color: const Color(0xFFCBD5E1),
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _HeroPill(
                              icon: Icons.inventory_2_outlined,
                              label:
                                  '${widget.summary?.totalItems ?? widget.allItemsLength} SKUs Monitored',
                            ),
                            _HeroPill(
                              icon: Icons.wifi_tethering_rounded,
                              label: widget.loading
                                  ? 'Synchronizing...'
                                  : 'Active Feed',
                            ),
                          ],
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
