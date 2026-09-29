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
import 'inventory_panel.dart';
import 'equipment_maintenance_screen.dart';
import 'inventory_models.dart';
import 'purchase_order_approval_screen.dart';
import 'stock_check_screen.dart';
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
    this.onOpenStockOperations,
  });

  final AuthenticatedApiClient client;
  final bool canApprove;
  final VoidCallback? onOpenStockOperations;

  @override
  State<InventoryDashboard> createState() => _InventoryDashboardState();
}

class _InventoryDashboardState extends State<InventoryDashboard>
    with TickerProviderStateMixin {
  static const _previewLimit = 100;
  late final _repository = InventoryDashboardRepository(widget.client);
  DashboardSummary? _summary;
  List<InventoryItem> _allItems = const [];
  List<InventoryItem> _filteredItems = const [];
  final TextEditingController _searchController = TextEditingController();
  String? _error;
  Map<String, dynamic>? _inventoryAiPlan;
  String? _inventoryAiError;
  bool _inventoryAiLoading = false;
  int _inventoryAiStep = 0;
  Timer? _inventoryAiStepTimer;
  bool _loading = true;
  bool _requestInFlight = false;
  bool _showInventoryAiPage = false;
  late final AnimationController _aiGlowController;
  late final AnimationController _aiSweepController;
  late final AnimationController _aiPageEntryController;
  late final Animation<double> _aiSweep;
  bool _aiMotionDisabled = false;
  String _searchQuery = '';
  String _selectedFilter = 'All';
  String _sortMode = 'Stock health';

  @override
  void initState() {
    super.initState();
    _aiGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _aiPageEntryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _aiSweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
    _aiSweep = TweenSequence<double>([
      TweenSequenceItem(
        tween: ConstantTween(-1.5),
        weight: 68,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -1.5, end: 2.5)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 32,
      ),
    ]).animate(_aiSweepController);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableMotion = MediaQuery.of(context).disableAnimations;
    if (disableMotion == _aiMotionDisabled) return;
    _aiMotionDisabled = disableMotion;
    if (disableMotion) {
      _aiGlowController.stop();
      _aiSweepController.stop();
      _aiPageEntryController
        ..stop()
        ..value = 1;
    } else {
      _aiGlowController.repeat(reverse: true);
      _aiSweepController.repeat();
    }
  }

  @override
  void dispose() {
    _aiGlowController.dispose();
    _aiSweepController.dispose();
    _aiPageEntryController.dispose();
    _inventoryAiStepTimer?.cancel();
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
    return PopScope<Object?>(
      canPop: !_showInventoryAiPage,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _showInventoryAiPage) {
          setState(() => _showInventoryAiPage = false);
        }
      },
      child: AppBackgroundScaffold(
        showParticles: false,
        appBar: GlassAppBar(
          title:
              _showInventoryAiPage ? 'StockSense AI' : 'Inventory Operations',
          automaticallyImplyLeading: !_showInventoryAiPage,
          leading: _showInventoryAiPage
              ? IconButton(
                  tooltip: 'Back to inventory',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => setState(() => _showInventoryAiPage = false),
                )
              : null,
          actions: [
            if (!_showInventoryAiPage)
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
                onPressed:
                    _requestInFlight ? null : () => _load(showSuccess: true),
              ),
          ],
        ),
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.cyan,
            backgroundColor: AppColors.overlaySurface,
            onRefresh: () => _load(showSuccess: true),
            child: _loading && _summary == null
                ? const AppLoader(message: 'Loading inventory hub...')
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      AnimatedSwitcher(
                        duration: _aiMotionDisabled
                            ? Duration.zero
                            : const Duration(milliseconds: 520),
                        reverseDuration: _aiMotionDisabled
                            ? Duration.zero
                            : const Duration(milliseconds: 360),
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
                        child: _showInventoryAiPage
                            ? Column(
                                key: const ValueKey('stocksense-page'),
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildAiPageEntrance(
                                    _buildInventoryAiCard(),
                                    start: 0,
                                    end: .9,
                                  ),
                                  if (!_inventoryAiLoading &&
                                      _inventoryAiPlan == null &&
                                      _inventoryAiError == null) ...[
                                    const SizedBox(height: 18),
                                    _buildAiReviewSteps(),
                                  ],
                                ],
                              )
                            : Column(
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
                                    ErrorState(
                                        message: _error!, onRetry: _load),
                                    const SizedBox(height: 18),
                                  ],

                                  // Inventory health at a glance.
                                  if (_summary != null) ...[
                                    _buildMetricCards(_summary!),
                                    const SizedBox(height: 22),
                                  ],

                                  _buildInventoryAiTeaser(),
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
                                        '${_filteredItems.length} shown · ${_summary?.totalItems ?? _allItems.length} total',
                                        style: AppTextStyles.caption
                                            .copyWith(color: AppColors.cyan)),
                                  ),
                                  const SizedBox(height: 12),

                                  if ((_summary?.totalItems ??
                                          _allItems.length) >
                                      _allItems.length) ...[
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 9),
                                      decoration: BoxDecoration(
                                        color: AppColors.cyan
                                            .withValues(alpha: .08),
                                        borderRadius: BorderRadius.circular(11),
                                        border: Border.all(
                                            color: AppColors.cyan
                                                .withValues(alpha: .2)),
                                      ),
                                      child: Row(children: [
                                        const Icon(Icons.info_outline_rounded,
                                            size: 16, color: AppColors.cyan),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Showing the first ${_allItems.length} of ${_summary!.totalItems} items. Search and filters apply to this preview.',
                                            style: AppTextStyles.caption
                                                .copyWith(
                                                    color:
                                                        AppColors.textSecondary,
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
                                            title:
                                                'Your inventory is ready to begin',
                                            message:
                                                'Items will appear here once your catalog has stock records.',
                                          )
                                        : InventoryPanel(
                                            child: Column(
                                              children: [
                                                const Icon(
                                                    Icons
                                                        .filter_alt_off_rounded,
                                                    color: AppColors.textMuted,
                                                    size: 30),
                                                const SizedBox(height: 9),
                                                Text('No items match this view',
                                                    style: AppTextStyles
                                                        .subtitle
                                                        .copyWith(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w800)),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Try another filter or clear your search.',
                                                  textAlign: TextAlign.center,
                                                  style: AppTextStyles.caption
                                                      .copyWith(
                                                          color: AppColors
                                                              .textSecondary),
                                                ),
                                                const SizedBox(height: 11),
                                                TextButton.icon(
                                                  onPressed: () {
                                                    _searchController.clear();
                                                    setState(() {
                                                      _searchQuery = '';
                                                      _selectedFilter = 'All';
                                                      _filteredItems =
                                                          _filterItems();
                                                    });
                                                  },
                                                  icon: const Icon(Icons
                                                      .restart_alt_rounded),
                                                  label: const Text(
                                                      'Reset filters'),
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
      ),
    );
  }

  Widget _buildAiPageEntrance(
    Widget child, {
    required double start,
    required double end,
  }) {
    if (_aiMotionDisabled) return child;
    final animation = CurvedAnimation(
      parent: _aiPageEntryController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final progress = animation.value;
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - progress)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildAiReviewSteps() {
    const steps = [
      (
        icon: Icons.inventory_2_outlined,
        title: 'Stock levels',
        detail: 'On hand & reorder points',
        color: AppColors.cyan,
      ),
      (
        icon: Icons.swap_vert_rounded,
        title: 'Movement',
        detail: 'Recorded usage history',
        color: AppColors.violet,
      ),
      (
        icon: Icons.delete_sweep_outlined,
        title: 'Waste',
        detail: 'Losses & data gaps',
        color: AppColors.warning,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'WHAT THE REVIEW COVERS',
                style: AppTextStyles.label.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 9,
                  letterSpacing: .9,
                ),
              ),
            ),
            const Icon(Icons.auto_awesome_rounded,
                size: 15, color: AppColors.cyan),
          ],
        ),
        const SizedBox(height: 10),
        ...steps.indexed.map((entry) {
          final index = entry.$1;
          final step = entry.$2;
          return Padding(
            padding: EdgeInsets.only(bottom: index == steps.length - 1 ? 0 : 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF101D34).withValues(alpha: .82),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: step.color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(step.icon, size: 17, color: step.color),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      step.title,
                      style: AppTextStyles.subtitle.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    step.detail,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.check_rounded,
                      size: 15, color: AppColors.success),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  void _openInventoryAiPage() {
    setState(() => _showInventoryAiPage = true);
    if (_aiMotionDisabled) {
      _aiPageEntryController.value = 1;
    } else {
      _aiPageEntryController.forward(from: 0);
    }
  }

  Widget _buildInventoryAiTeaser() {
    final atRisk = _summary?.lowStock;
    final outOfStock = _summary?.outOfStock;
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _AiPulseMark(size: 46),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MEET YOUR INVENTORY CO-PILOT',
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.cyan,
                        fontSize: 9,
                        letterSpacing: .8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'StockSense AI',
                      style: AppTextStyles.title.copyWith(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: AppColors.cyan, size: 16),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Turn stock, usage and waste data into clear next steps.',
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 7,
            children: [
              _AiMetricPill(
                icon: Icons.warning_amber_rounded,
                label: atRisk == null ? 'Stock health' : '$atRisk low',
                color: AppColors.warning,
              ),
              _AiMetricPill(
                icon: Icons.remove_shopping_cart_outlined,
                label: outOfStock == null ? 'Coverage' : '$outOfStock out',
                color: AppColors.danger,
              ),
              const _AiMetricPill(
                icon: Icons.lock_outline_rounded,
                label: 'Read-only',
                color: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openInventoryAiPage,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Explore AI stock insights'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.cyan,
                foregroundColor: AppColors.onPrimary,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
    return AnimatedBuilder(
      animation: Listenable.merge([_aiGlowController, _aiSweepController]),
      builder: (context, child) {
        final pulse = _aiMotionDisabled ? .5 : _aiGlowController.value;
        return InventoryPanel(
          padding: EdgeInsets.zero,
          fill: const Color(0xFF13283A),
          borderColor: AppColors.cyan.withValues(alpha: .24 + (.28 * pulse)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Positioned(
                  right: -38 - (pulse * 14),
                  top: -52 + (pulse * 12),
                  child: Container(
                    width: 145,
                    height: 145,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.violet
                          .withValues(alpha: .08 + (.08 * pulse)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.cyan
                              .withValues(alpha: .08 + (.12 * pulse)),
                          blurRadius: 30 + (18 * pulse),
                          spreadRadius: 10 + (10 * pulse),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_aiMotionDisabled)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment(_aiSweep.value, 0),
                        child: FractionallySizedBox(
                          widthFactor: .24,
                          heightFactor: 1.8,
                          child: Transform.rotate(
                            angle: -.28,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    AppColors.cyan.withValues(alpha: .13),
                                    Colors.white.withValues(alpha: .07),
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
                child!,
              ],
            ),
          ),
        );
      },
      child: content,
    );
  }

  Future<void> _analyzeInventory() async {
    setState(() {
      _inventoryAiLoading = true;
      _inventoryAiError = null;
      _inventoryAiPlan = null;
      _inventoryAiStep = 0;
    });
    _inventoryAiStepTimer?.cancel();
    _inventoryAiStepTimer =
        Timer.periodic(const Duration(milliseconds: 2300), (_) {
      if (mounted) {
        setState(() => _inventoryAiStep = (_inventoryAiStep + 1) % 5);
      }
    });
    try {
      final response = await widget.client.post(
        '/api/inventory/agent/plan',
        body: {
          'objective':
              'Review overall inventory health, not only low stock. Identify stock coverage risks from recorded issue/sale/consumption, summarize items without recorded outflow and recent waste movements, and explain uncertainty. Do not infer demand from missing history.',
        },
      );
      if (response.body.trim().isEmpty) {
        if (response.statusCode == 401) {
          throw Exception(
              'Your session has expired. Sign in again and retry inventory analysis.');
        }
        if (response.statusCode == 403) {
          throw Exception(
              'Your account does not have permission to read inventory for this branch.');
        }
        if (response.statusCode == 404) {
          throw Exception(
              'The backend does not have the inventory AI endpoint yet. Restart the ASP.NET backend and retry.');
        }
        throw Exception(
          'Inventory AI API returned an empty response (${response.statusCode}). Check the backend endpoint and agent service configuration.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = decoded is Map ? decoded : const <String, dynamic>{};
        final warnings = body['warnings'];
        throw Exception(body['message'] ??
            (warnings is List && warnings.isNotEmpty
                ? warnings.first
                : 'Inventory AI could not complete the analysis.'));
      }
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected inventory plan response.');
      }
      if (mounted) {
        setState(() => _inventoryAiPlan = decoded);
        if (_aiMotionDisabled) {
          _aiPageEntryController.value = 1;
        } else {
          _aiPageEntryController.forward(from: 0);
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _inventoryAiError =
            error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      _inventoryAiStepTimer?.cancel();
      _inventoryAiStepTimer = null;
      if (mounted) setState(() => _inventoryAiLoading = false);
    }
  }

  Widget _buildInventoryAiCard() {
    final recommendations = _inventoryAiPlan?['recommendations'];
    final lowStock = _summary?.lowStock;
    final outOfStock = _summary?.outOfStock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InventoryPanel(
          padding: EdgeInsets.zero,
          fill: const Color(0xFF101D34),
          borderColor: AppColors.cyan.withValues(alpha: .3),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Stack(
              children: [
                AnimatedBuilder(
                  animation: _aiGlowController,
                  builder: (context, child) {
                    final pulse =
                        _aiMotionDisabled ? .5 : _aiGlowController.value;
                    return Positioned(
                      top: -78 + (pulse * 10),
                      right: -35 - (pulse * 12),
                      child: Container(
                        width: 230,
                        height: 230,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.cyan
                              .withValues(alpha: .05 + (.04 * pulse)),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.violet
                                  .withValues(alpha: .08 + (.1 * pulse)),
                              blurRadius: 58 + (24 * pulse),
                              spreadRadius: 12 + (12 * pulse),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (!_aiMotionDisabled)
                  AnimatedBuilder(
                    animation: _aiSweepController,
                    builder: (context, child) => Positioned.fill(
                      child: IgnorePointer(
                        child: Align(
                          alignment: Alignment(_aiSweep.value, 0),
                          child: FractionallySizedBox(
                            widthFactor: .22,
                            heightFactor: 1.7,
                            child: Transform.rotate(
                              angle: -.28,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      AppColors.cyan.withValues(alpha: .1),
                                      Colors.white.withValues(alpha: .045),
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
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const _AiPulseMark(size: 52),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'STOCKSENSE  /  AI',
                                  style: AppTextStyles.label.copyWith(
                                    color: AppColors.cyan,
                                    fontSize: 9,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Inventory intelligence',
                                  style: AppTextStyles.title.copyWith(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_inventoryAiPlan != null)
                            IconButton(
                              tooltip: 'Run analysis again',
                              onPressed: _inventoryAiLoading
                                  ? null
                                  : _analyzeInventory,
                              icon: const Icon(Icons.refresh_rounded,
                                  color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Know what needs attention.',
                        style: AppTextStyles.title.copyWith(
                          fontSize: 24,
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.45,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Get a clear view of stock coverage, recorded usage and waste—then decide what to do.',
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'STOCK AT A GLANCE',
                        style: AppTextStyles.label.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 9,
                          letterSpacing: .8,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Expanded(
                            child: _AiScopeTile(
                              icon: Icons.inventory_2_outlined,
                              label: 'LOW STOCK',
                              value: lowStock?.toString() ?? '—',
                              accent: AppColors.warning,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: _AiScopeTile(
                              icon: Icons.remove_shopping_cart_outlined,
                              label: 'OUT OF STOCK',
                              value: outOfStock?.toString() ?? '—',
                              accent: AppColors.danger,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton.icon(
                          onPressed:
                              _inventoryAiLoading ? null : _analyzeInventory,
                          icon: _inventoryAiLoading
                              ? const SizedBox(
                                  width: 19,
                                  height: 19,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_rounded,
                                  size: 19),
                          label: Text(
                            _inventoryAiLoading
                                ? 'Reviewing your stock…'
                                : _inventoryAiPlan == null
                                    ? 'Generate stock review'
                                    : 'Run analysis again',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            foregroundColor: AppColors.onPrimary,
                            disabledBackgroundColor: const Color(0xFF355061),
                            disabledForegroundColor: AppColors.textSecondary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 11),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_outline_rounded,
                              size: 13, color: AppColors.success),
                          const SizedBox(width: 6),
                          Text(
                            'READ-ONLY REVIEW  ·  YOU STAY IN CONTROL',
                            style: AppTextStyles.label.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 8,
                              letterSpacing: .55,
                            ),
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
        if (_inventoryAiLoading) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFF19283A),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.cyan,
                        backgroundColor: AppColors.glassBorder)),
                const SizedBox(width: 11),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('STOCKSENSE IS THINKING',
                          style: AppTextStyles.label
                              .copyWith(color: AppColors.cyan, fontSize: 10)),
                      const SizedBox(height: 4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 450),
                        transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                                position: Tween<Offset>(
                                        begin: const Offset(0, 0.18),
                                        end: Offset.zero)
                                    .animate(animation),
                                child: child)),
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
                Text('${_inventoryAiStep + 1}/5',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textMuted)),
              ]),
              const SizedBox(height: 11),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: const LinearProgressIndicator(
                    minHeight: 4,
                    color: AppColors.cyan,
                    backgroundColor: AppColors.glassBorder),
              ),
              const SizedBox(height: 6),
              Text(
                  'Analysis can take a little while. Your stock remains unchanged.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted)),
            ]),
          ),
        ],
        if (_inventoryAiError != null) ...[
          const SizedBox(height: 14),
          _AiResultNote(
            icon: Icons.error_outline_rounded,
            title: 'Could not complete the review',
            detail: _inventoryAiError!,
            color: AppColors.error,
          ),
        ],
        if (_inventoryAiPlan != null) ...[
          const SizedBox(height: 16),
          InventoryPanel(
            padding: const EdgeInsets.all(16),
            fill: const Color(0xFF0E192D),
            borderColor: AppColors.glassBorder,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded,
                          color: AppColors.cyan, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI STOCK REVIEW',
                            style: AppTextStyles.label.copyWith(
                              color: AppColors.cyan,
                              fontSize: 9,
                              letterSpacing: .8,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Key findings',
                            style: AppTextStyles.subtitle.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const _AiMetricPill(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'READY',
                      color: AppColors.success,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: .055),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                        color: AppColors.cyan.withValues(alpha: .18)),
                  ),
                  child: Text(
                    '${_inventoryAiPlan!['planner_summary'] ?? ''}',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textBody,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_inventoryAiPlan!['insights'] is List &&
                    (_inventoryAiPlan!['insights'] as List).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildAiPageEntrance(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('INVENTORY HEALTH INSIGHTS',
                            style: AppTextStyles.label
                                .copyWith(color: AppColors.cyan)),
                        ...(_inventoryAiPlan!['insights'] as List).map((entry) {
                          if (entry is! Map) return const SizedBox.shrink();
                          final insight = Map<String, dynamic>.from(entry);
                          final affected = insight['affected_items'];
                          final category =
                              '${insight['category'] ?? 'overview'}';
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
                                border:
                                    Border.all(color: const Color(0xFF2A4058)),
                              ),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                              color: insightColor.withValues(
                                                  alpha: 0.14),
                                              borderRadius:
                                                  BorderRadius.circular(10)),
                                          child: Icon(insightIcon,
                                              size: 18, color: insightColor)),
                                      const SizedBox(width: 9),
                                      Expanded(
                                          child: Text(
                                              category
                                                  .replaceAll('_', ' ')
                                                  .toUpperCase(),
                                              style: AppTextStyles.label
                                                  .copyWith(
                                                      color: insightColor,
                                                      fontSize: 10))),
                                    ]),
                                    const SizedBox(height: 8),
                                    Text(
                                        '${insight['title'] ?? 'Inventory insight'}',
                                        style: AppTextStyles.subtitle),
                                    const SizedBox(height: 4),
                                    Text('${insight['detail'] ?? ''}',
                                        style: AppTextStyles.bodyMuted
                                            .copyWith(fontSize: 12)),
                                    if (affected is List &&
                                        affected.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: affected
                                              .take(5)
                                              .map((name) => Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                    decoration: BoxDecoration(
                                                        color: insightColor
                                                            .withValues(
                                                                alpha: 0.1),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20),
                                                        border: Border.all(
                                                            color: const Color(
                                                                0xFF2A4058))),
                                                    child: Text('$name',
                                                        style: AppTextStyles
                                                            .caption
                                                            .copyWith(
                                                                color: AppColors
                                                                    .textBody)),
                                                  ))
                                              .toList()),
                                    ],
                                  ]),
                            ),
                          );
                        }),
                      ],
                    ),
                    start: .12,
                    end: .72,
                  ),
                ],
                if (recommendations is List && recommendations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: _AiResultNote(
                      icon: Icons.inventory_2_outlined,
                      title: 'No replenishment recommendations',
                      detail:
                          'No replenishment recommendations from the available stock data.',
                      color: AppColors.cyan,
                    ),
                  ),
                if (recommendations is List && recommendations.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('REPLENISHMENT RECOMMENDATIONS',
                      style:
                          AppTextStyles.label.copyWith(color: AppColors.cyan)),
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
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${item['item_name']}  ·  Reorder ${item['recommended_quantity']}',
                                  style: AppTextStyles.subtitle),
                              const SizedBox(height: 4),
                              Text(
                                  'On hand ${item['on_hand']} / reorder at ${item['reorder_level']}  ·  ${daily == null ? 'No usage history' : '$daily per day'}',
                                  style: AppTextStyles.caption),
                              const SizedBox(height: 4),
                              Text('${item['reason']}',
                                  style: AppTextStyles.bodyMuted
                                      .copyWith(fontSize: 12)),
                            ]),
                      ),
                    );
                  }),
                ],
                if (_inventoryAiPlan!['warnings'] is List)
                  ...(_inventoryAiPlan!['warnings'] as List)
                      .where((warning) => warning.toString().trim().isNotEmpty)
                      .map((warning) => Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _AiResultNote(
                              icon: Icons.info_outline_rounded,
                              title: 'Estimation note',
                              detail: '$warning',
                              color: AppColors.warning,
                            ),
                          )),
              ],
            ),
          ),
        ],
      ],
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
                    if (widget.canApprove) const _RoleBadge(label: 'MANAGER'),
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
                label: 'TOTAL VALUATION',
                value: _compactLkr(summary.totalValue),
                icon: Icons.account_balance_wallet_rounded,
                accentColor: const Color(0xFF7C8CFF),
                subLabel:
                    'LKR ${summary.totalValue.toStringAsFixed(2)} on hand',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CyberStatCard(
                label: 'LOW STOCK',
                value: '${summary.lowStock}',
                icon: Icons.warning_amber_rounded,
                accentColor: summary.lowStock > 0
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF55D6C2),
                subLabel: summary.lowStock > 0
                    ? 'At or below reorder level'
                    : 'Reorder levels healthy',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _CyberStatCard(
                label: 'OUT OF STOCK',
                value: '${summary.outOfStock}',
                icon: Icons.remove_shopping_cart_rounded,
                accentColor: summary.outOfStock > 0
                    ? const Color(0xFFF16D83)
                    : const Color(0xFF55D6C2),
                subLabel: summary.outOfStock > 0
                    ? 'Needs replenishment'
                    : 'Nothing empty',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CyberStatCard(
                label: 'PENDING PO QUEUE',
                value: '${summary.pendingOrders}',
                icon: Icons.assignment_late_rounded,
                accentColor: const Color(0xFFB28CFF),
                subLabel: 'Open orders',
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
    return InventoryPanel(
      padding: const EdgeInsets.all(14),
      borderColor: const Color(0xFF29394D),
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
    return InventoryPanel(
      padding: const EdgeInsets.all(14),
      borderColor: const Color(0xFF29394D),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(12),
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
              size: 12, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _AiResultNote extends StatelessWidget {
  const _AiResultNote({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .24)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.subtitle.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: AppTextStyles.bodyMuted.copyWith(
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _AiMetricPill extends StatelessWidget {
  const _AiMetricPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .24)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ]),
      );
}

class _AiScopeTile extends StatelessWidget {
  const _AiScopeTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF0E192D).withValues(alpha: .72),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: accent.withValues(alpha: .2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: accent),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: AppTextStyles.subtitle.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 1,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 7,
                  letterSpacing: .35,
                ),
              ),
            ),
          ],
        ),
      );
}

class _AiPulseMark extends StatefulWidget {
  const _AiPulseMark({required this.size});

  final double size;

  @override
  State<_AiPulseMark> createState() => _AiPulseMarkState();
}

class _AiPulseMarkState extends State<_AiPulseMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  bool? _motionDisabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableMotion = MediaQuery.of(context).disableAnimations;
    if (disableMotion == _motionDisabled) return;
    _motionDisabled = disableMotion;
    if (disableMotion) {
      _controller
        ..stop()
        ..value = .5;
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final pulse = Curves.easeInOut.transform(_controller.value);
          return Transform.translate(
            offset: Offset(0, -1.5 + (pulse * 3)),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.cyan.withValues(alpha: .24 + (.13 * pulse)),
                    AppColors.violet.withValues(alpha: .18 + (.12 * pulse)),
                  ],
                ),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: AppColors.cyan.withValues(alpha: .24 + (.2 * pulse)),
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        AppColors.cyan.withValues(alpha: .07 + (.11 * pulse)),
                    blurRadius: 8 + (8 * pulse),
                  ),
                ],
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: widget.size * .48,
                color: AppColors.cyan,
              ),
            ),
          );
        },
      );
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
    final response = await _client.get('/api/purchase-orders?pageSize=100');
    if (response.statusCode != 200) {
      throw Exception('Purchase order request failed');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['items'] as List?) ?? const [];
    const terminal = {'Received', 'Cancelled'};
    return items.where((o) {
      final status = (o is Map ? o['status'] : null)?.toString() ?? '';
      return !terminal.contains(status);
    }).length;
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
