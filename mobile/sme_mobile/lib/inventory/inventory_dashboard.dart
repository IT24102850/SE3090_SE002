import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
  });

  final AuthenticatedApiClient client;
  final bool canApprove;
  final String? role;
  final bool canReceive;

  @override
  State<InventoryDashboard> createState() => _InventoryDashboardState();
}

class _InventoryDashboardState extends State<InventoryDashboard> {
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
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
    return AppBackgroundScaffold(
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
                          _buildHeroBanner(),
                          const SizedBox(height: 18),

                          if (_error != null) ...[
                            ErrorState(message: _error!, onRetry: _load),
                            const SizedBox(height: 18),
                          ],

                          // Inventory health at a glance.
                          if (_summary != null) ...[
                            _buildMetricCards(_summary!),
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
                          _buildQuickActionGrid(),
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
                            ..._filteredItems
                                .map((item) => _buildItemCard(item)),
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
    return InventoryPanel(
      padding: EdgeInsets.zero,
      borderColor: const Color(0xFF344A70),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1C2B4A), Color(0xFF17233A), Color(0xFF142C3A)],
            ),
          ),
          child: Stack(children: [
            Positioned(
              right: -45,
              top: -68,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .06)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.violet.withValues(alpha: .1),
                      blurRadius: 45,
                      spreadRadius: 24,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          AppColors.cyan.withValues(alpha: .24),
                          AppColors.violet.withValues(alpha: .18),
                        ]),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.cyan.withValues(alpha: .24)),
                      ),
                      child: const Icon(Icons.inventory_2_rounded,
                          color: AppColors.cyan, size: 23),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('INVENTORY CONTROL CENTER',
                              style: AppTextStyles.label.copyWith(
                                color: const Color(0xFF9FE8F2),
                                fontSize: 9,
                                letterSpacing: 1.05,
                              )),
                          const SizedBox(height: 4),
                          Text('Stock, made simple',
                              style: AppTextStyles.title.copyWith(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.3,
                              )),
                        ],
                      ),
                    ),
                    if (widget.role case final role?)
                      _RoleBadge(label: role.trim().toUpperCase()),
                  ]),
                  const SizedBox(height: 14),
                  Text(
                    'Keep products, counts, orders and equipment moving from one clear workspace.',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _HeroPill(
                      icon: Icons.inventory_2_outlined,
                      label: '${_summary?.totalItems ?? _allItems.length} SKUs',
                    ),
                    _HeroPill(
                      icon: Icons.schedule_rounded,
                      label: _loading ? 'Updating stock' : 'Live stock view',
                    ),
                  ]),
                ],
              ),
            ),
          ]),
        ),
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
                key: const Key('dashboard-metric-valuation'),
                label: 'TOTAL VALUATION',
                value: _compactLkr(summary.totalValue),
                icon: Icons.account_balance_wallet_rounded,
                accentColor: const Color(0xFF7C8CFF),
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
                      canReceive: widget.canReceive,
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
                      canReceive: widget.canReceive,
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

  Widget _buildItemCard(InventoryItem item) {
    final isOutOfStock = item.quantity <= 0;
    final isLow = item.isLowStock;
    final statusColor = isOutOfStock
        ? const Color(0xFFF16D83)
        : isLow
            ? const Color(0xFFF3B64D)
            : const Color(0xFF55D6C2);
    final statusText = isOutOfStock
        ? 'OUT OF STOCK'
        : isLow
            ? 'LOW STOCK'
            : 'IN STOCK';
    final progress = item.reorderLevel > 0
        ? (item.quantity / item.reorderLevel).clamp(0.0, 1.0)
        : (item.quantity > 0 ? 1.0 : 0.0);

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
                key: ValueKey('${item.id}:$statusText'),
                label: statusText,
                color: statusColor,
                icon: isOutOfStock
                    ? Icons.remove_shopping_cart_rounded
                    : isLow
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
                if (item.branch.isNotEmpty)
                  _ItemInfoChip(
                      label: item.branch, icon: Icons.storefront_outlined),
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
                '${_formatQuantity(item.quantity)} ${item.unit}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.subtitle
                    .copyWith(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ]),
            const SizedBox(height: 8),
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
            Row(children: [
              Expanded(
                child: Text(
                  item.reorderLevel > 0
                      ? 'Reorder at ${_formatQuantity(item.reorderLevel)} ${item.unit}'
                      : 'No reorder level set',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${item.unitCost == null ? 'Unit cost not set' : 'LKR ${item.unitCost!.toStringAsFixed(2)}'} / ${item.unit}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textMuted, fontSize: 10),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showItemQrLabel(item),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 17),
                  label: const Text('Item label'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    minimumSize: const Size(0, 40),
                    side: const BorderSide(color: AppColors.glassBorder),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _quickAdjustItem(item),
                  icon: const Icon(Icons.tune_rounded, size: 17),
                  label: const Text('Adjust stock'),
                  style: FilledButton.styleFrom(
                    foregroundColor: AppColors.cyan,
                    backgroundColor: AppColors.cyan.withValues(alpha: .12),
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                  ),
                ),
              ),
            ]),
          ],
        ),
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

class _CyberStatCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return InventoryPanel(
      padding: const EdgeInsets.all(14),
      borderColor: const Color(0xFF29394D),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 3,
            width: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: LinearGradient(colors: [
                accentColor,
                accentColor.withValues(alpha: .28),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.label.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(icon, size: 17, color: accentColor),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: AppColors.textMuted,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.headlineSmall.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
  Widget build(BuildContext context) {
    return InventoryPanel(
      padding: EdgeInsets.all(compact ? 12 : 14),
      borderColor: const Color(0xFF29394D),
      onTap: onTap,
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildIcon(size: 40),
                    const Spacer(),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 15,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.subtitle.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                _buildIcon(),
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
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 12,
                  color: AppColors.textMuted,
                ),
              ],
            ),
    );
  }

  Widget _buildIcon({double size = 44}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: size * .5),
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
