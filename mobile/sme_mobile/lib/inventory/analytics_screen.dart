import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';
import '../widgets/unify_auth/unify_logo_mark.dart';
import 'authenticated_api_client.dart';
import 'inventory_panel.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

class LowStockPoint {
  const LowStockPoint(
      this.name, this.sku, this.quantity, this.reorderLevel, this.status);
  final String name;
  final String sku;
  final double quantity;
  final double reorderLevel;
  final String status;
}

class CategoryBreakdown {
  const CategoryBreakdown(this.label, this.amount, this.pct, this.color);
  final String label;
  final double amount;
  final double pct;
  final Color color;
}

class _InventorySessionExpiredException implements Exception {
  const _InventorySessionExpiredException();
}

String _formatQuantity(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, this.client});
  final AuthenticatedApiClient? client;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  final _scrollController = ScrollController();
  late final AnimationController _heroGlowController;
  bool? _motionDisabled;
  int _selectedTimeframe = 0; // 0: 7 Days, 1: 30 Days
  static const _categoryColors = [
    AppColors.violet,
    AppColors.cyan,
    AppColors.success,
    AppColors.warning,
    AppColors.magenta,
    AppColors.electricBlue,
  ];
  List<LowStockPoint> _lowStock = const [];
  List<CategoryBreakdown> _categories = const [];
  List<String> _reportErrors = const [];
  bool _hasLiveData = false;
  bool _hasInventorySnapshot = false;
  bool _hasMovementReport = false;
  bool _sessionExpired = false;
  int _totalSkus = 0;
  int _lowStockCount = 0;
  int _outOfStockCount = 0;
  int _itemsWithoutUnitCost = 0;
  double _totalStockValue = 0;
  double _totalStockUnits = 0;
  double _totalReceived = 0;
  double _totalIssued = 0;

  @override
  void initState() {
    super.initState();
    _heroGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _fetchAnalytics();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableMotion = MediaQuery.of(context).disableAnimations;
    if (disableMotion == _motionDisabled) return;
    _motionDisabled = disableMotion;
    if (disableMotion) {
      _heroGlowController
        ..stop()
        ..value = .45;
    } else {
      _heroGlowController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _heroGlowController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchAnalytics({bool showSuccess = false}) async {
    if (_loading) return;
    final client = widget.client;
    if (client == null) {
      setState(() {
        _reportErrors = const [
          'No authenticated inventory connection is available.'
        ];
        _hasLiveData = false;
        _hasInventorySnapshot = false;
        _hasMovementReport = false;
        _sessionExpired = false;
      });
      return;
    }
    final today = DateTime.now().toUtc();
    final to = DateTime.utc(today.year, today.month, today.day);
    final from = to.subtract(Duration(
      days: _selectedTimeframe == 0 ? 6 : 29,
    ));
    final rangeQuery =
        '?from=${Uri.encodeQueryComponent(from.toIso8601String())}'
        '&to=${Uri.encodeQueryComponent(to.toIso8601String())}';
    setState(() {
      _loading = true;
      _lowStock = const [];
      _categories = const [];
      _reportErrors = const [];
      _hasLiveData = false;
      _hasInventorySnapshot = false;
      _hasMovementReport = false;
      _sessionExpired = false;
      _totalSkus = 0;
      _outOfStockCount = 0;
      _lowStockCount = 0;
      _totalStockValue = 0;
      _totalStockUnits = 0;
      _itemsWithoutUnitCost = 0;
      _totalReceived = 0;
      _totalIssued = 0;
    });
    final errors = <String>[];

    if (!_sessionExpired) {
      try {
        final data =
            await _getReport(client, '/api/reports/inventory-usage$rangeQuery');
        _totalReceived =
            (data['totalReceivedQuantity'] as num?)?.toDouble() ?? 0;
        _totalIssued = (data['totalIssuedQuantity'] as num?)?.toDouble() ?? 0;
        _hasMovementReport = true;
        _hasLiveData = true;
      } catch (error) {
        if (error is _InventorySessionExpiredException) {
          _sessionExpired = true;
        } else if (!_sessionExpired) {
          errors.add('Stock movement: ${_friendlyError(error)}');
        }
      }
    }

    if (!_sessionExpired) {
      try {
        final inventory = <Map<String, dynamic>>[];
        final inventoryIds = <String>{};
        int? expectedInventoryCount;
        var page = 1;
        var totalPages = 1;
        do {
          final data = await _getReport(
            client,
            '/api/inventory?page=$page&pageSize=100',
          );
          final items = data['items'];
          if (items is! List) {
            throw const FormatException('Inventory response has no item list.');
          }
          final pageItems = items.whereType<Map<String, dynamic>>().toList();
          if (pageItems.length != items.length) {
            throw const FormatException(
                'Inventory response contains invalid items.');
          }
          final rawTotalCount = data['totalCount'];
          if (rawTotalCount is! num ||
              !rawTotalCount.isFinite ||
              rawTotalCount < 0 ||
              rawTotalCount != rawTotalCount.toInt()) {
            throw const FormatException(
                'Inventory response has no valid total item count.');
          }
          final pageTotalCount = rawTotalCount.toInt();
          if (expectedInventoryCount != null &&
              expectedInventoryCount != pageTotalCount) {
            throw const FormatException(
                'Inventory changed while loading. Refresh to capture a complete snapshot.');
          }
          expectedInventoryCount ??= pageTotalCount;
          for (final item in pageItems) {
            final id = item['id'];
            if (id is String && !inventoryIds.add(id)) {
              throw const FormatException(
                  'Inventory pages contain duplicate items. Refresh to capture a complete snapshot.');
            }
          }
          inventory.addAll(pageItems);
          final pageCount = data['totalPages'];
          if (pageCount is! num ||
              !pageCount.isFinite ||
              pageCount < 0 ||
              pageCount != pageCount.toInt()) {
            throw const FormatException(
                'Inventory response has no valid page count.');
          }
          totalPages = pageCount.toInt();
          page++;
        } while (page <= totalPages);
        if (inventory.length != expectedInventoryCount) {
          throw FormatException(
            'Loaded ${inventory.length} of $expectedInventoryCount inventory items. Refresh to capture the complete snapshot.',
          );
        }

        var categoryNames = <String, String>{};
        try {
          categoryNames = await _getInventoryCategoryNames(client);
        } on _InventorySessionExpiredException {
          rethrow;
        } catch (error) {
          errors.add('Category names: ${_friendlyError(error)}');
        }
        final categoryValues = <String, double>{};
        var totalValue = 0.0;
        var totalUnits = 0.0;
        var lowStockCount = 0;
        var outOfStockCount = 0;
        var itemsWithoutUnitCost = 0;
        final lowStockItems = <LowStockPoint>[];
        for (final item in inventory) {
          final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
          final reorderLevel = (item['reorderLevel'] as num?)?.toDouble() ?? 0;
          final rawUnitCost = item['unitCost'];
          if (rawUnitCost is! num) itemsWithoutUnitCost++;
          final unitCost = (rawUnitCost as num?)?.toDouble() ?? 0;
          final value = quantity * unitCost;
          final category = _inventoryCategoryName(item, categoryNames);
          totalValue += value;
          totalUnits += quantity;
          categoryValues.update(category, (existing) => existing + value,
              ifAbsent: () => value);
          final out = quantity <= 0;
          final low = out || quantity <= reorderLevel;
          if (out) outOfStockCount++;
          if (low) {
            lowStockCount++;
            lowStockItems.add(LowStockPoint(
              item['name'] as String? ?? 'Item',
              item['sku'] as String? ?? '',
              quantity,
              reorderLevel,
              out ? 'OutOfStock' : 'LowStock',
            ));
          }
        }
        lowStockItems.sort((a, b) {
          if (a.quantity <= 0 && b.quantity > 0) return -1;
          if (b.quantity <= 0 && a.quantity > 0) return 1;
          final aRatio = a.reorderLevel > 0 ? a.quantity / a.reorderLevel : 1.0;
          final bRatio = b.reorderLevel > 0 ? b.quantity / b.reorderLevel : 1.0;
          return aRatio.compareTo(bRatio);
        });
        final categories = categoryValues.entries
            .where((entry) => entry.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        _totalSkus = inventory.length;
        _outOfStockCount = outOfStockCount;
        _lowStockCount = lowStockCount;
        _totalStockValue = totalValue;
        _totalStockUnits = totalUnits;
        _itemsWithoutUnitCost = itemsWithoutUnitCost;
        _lowStock = lowStockItems.take(6).toList();
        _categories = totalValue <= 0
            ? const []
            : categories.indexed
                .map((entry) => CategoryBreakdown(
                      entry.$2.key,
                      entry.$2.value,
                      entry.$2.value / totalValue,
                      _categoryColors[entry.$1 % _categoryColors.length],
                    ))
                .toList();
        _hasInventorySnapshot = true;
        _hasLiveData = true;
      } catch (error) {
        if (error is _InventorySessionExpiredException) {
          _sessionExpired = true;
        } else if (!_sessionExpired) {
          errors.add('Current inventory: ${_friendlyError(error)}');
        }
      }
    }

    if (mounted) {
      setState(() {
        _loading = false;
        _reportErrors = _sessionExpired
            ? const [
                'Your session expired or is no longer valid. Sign in again to load inventory analytics.'
              ]
            : errors;
      });
      if (_sessionExpired) {
        return;
      } else if (errors.isNotEmpty) {
        AppSnackBar.info(
          context,
          '${errors.length} inventory section${errors.length == 1 ? '' : 's'} could not be loaded.',
        );
      } else if (showSuccess) {
        AppSnackBar.success(
          context,
          'Analytics refreshed successfully. Your latest insights are ready.',
        );
      }
    }
  }

  Future<Map<String, dynamic>> _getReport(
    AuthenticatedApiClient client,
    String path,
  ) async {
    final response = await client.get(path);
    if (response.statusCode == 401) {
      throw const _InventorySessionExpiredException();
    }
    if (response.statusCode != 200) {
      throw Exception('Request failed (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
          'Unexpected response from the inventory API.');
    }
    return decoded;
  }

  Future<Map<String, String>> _getInventoryCategoryNames(
    AuthenticatedApiClient client,
  ) async {
    final response = await client.get('/api/inventory/categories');
    if (response.statusCode == 401) {
      throw const _InventorySessionExpiredException();
    }
    if (response.statusCode != 200) {
      throw Exception('Request failed (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Inventory categories response is invalid.');
    }

    final names = <String, String>{};
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) continue;
      final id = entry['id'];
      final name = entry['name'];
      if (id is String && name is String && name.trim().isNotEmpty) {
        names[id.toLowerCase()] = name.trim();
      }
    }
    return names;
  }

  String _inventoryCategoryName(
    Map<String, dynamic> item,
    Map<String, String> categoryNames,
  ) {
    final rawCategory = item['category'];
    if (rawCategory is String && rawCategory.trim().isNotEmpty) {
      return rawCategory.trim();
    }
    if (rawCategory is Map) {
      final nestedName = rawCategory['name'] ?? rawCategory['Name'];
      if (nestedName is String && nestedName.trim().isNotEmpty) {
        return nestedName.trim();
      }
    }

    final rawCategoryName = item['categoryName'] ?? item['CategoryName'];
    if (rawCategoryName is String && rawCategoryName.trim().isNotEmpty) {
      return rawCategoryName.trim();
    }

    final rawCategoryId = item['categoryId'] ?? item['CategoryId'];
    if (rawCategoryId is String && rawCategoryId.trim().isNotEmpty) {
      return categoryNames[rawCategoryId.toLowerCase()] ?? 'Unmapped category';
    }

    final rawDescription = item['description'] ?? item['Description'];
    if (rawDescription is String) {
      final description = rawDescription.trim().toLowerCase();
      for (final categoryName in categoryNames.values) {
        final normalizedName = categoryName.toLowerCase();
        if (description == normalizedName ||
            (description.startsWith('$normalizedName (') &&
                description.endsWith(')'))) {
          return categoryName;
        }
      }
    }
    return 'Uncategorised';
  }

  String _friendlyError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    return message.length > 140 ? '${message.substring(0, 137)}…' : message;
  }

  String get _selectedPeriodLabel =>
      _selectedTimeframe == 0 ? '7-day period' : '30-day period';

  Future<void> _selectTimeframe(int index) async {
    if (index == _selectedTimeframe || _loading) return;
    setState(() => _selectedTimeframe = index);
    await _fetchAnalytics();
  }

  // ──────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppBackgroundScaffold(
      showParticles: false,
      extendBodyBehindAppBar: false,
      appBar: GlassAppBar(
        title: 'Analytics',
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.cyan,
                ),
              ),
            )
          else
            IconButton(
              onPressed: () => _fetchAnalytics(showSuccess: true),
              tooltip: 'Refresh analytics',
              icon: const Icon(Icons.refresh_rounded,
                  color: AppColors.cyan, size: 20),
            ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: () => _fetchAnalytics(showSuccess: true),
        color: AppColors.cyan,
        backgroundColor: AppColors.bgMid,
        child: ListView(
          controller: _scrollController,
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _buildHeroBanner(),
            const SizedBox(height: 16),
            if (_loading)
              const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(AppColors.cyan),
              ),
            if (_loading) const SizedBox(height: 10),
            _buildTimeframeRow(),
            const SizedBox(height: 14),

            if (_reportErrors.isNotEmpty) ...[
              _buildReportErrorPanel(),
              const SizedBox(height: 16),
            ],

            // ── Whole inventory snapshot ─────────────────
            _buildAnalyticsSectionHeading(
              icon: Icons.inventory_2_rounded,
              title: 'Whole inventory',
              subtitle:
                  'All accessible items · date range only filters activity',
            ),
            const SizedBox(height: 11),
            _buildInventorySnapshot(),
            const SizedBox(height: 25),

            // ── Revenue Chart ────────────────────────────
            _buildAnalyticsSectionHeading(
              icon: Icons.inventory_2_rounded,
              title: 'Inventory activity',
              subtitle: 'Stock received and issued in the selected period',
              color: AppColors.success,
            ),
            const SizedBox(height: 11),
            _buildInventoryActivitySummary(),
            const SizedBox(height: 25),

            // ── Inventory Movement ───────────────────────
            // ── Live category valuation ──────────────────
            _buildAnalyticsSectionHeading(
              icon: Icons.donut_large_rounded,
              title: 'Stock value by category',
              subtitle: 'Current on-hand value · quantity × unit cost',
              color: AppColors.cyan,
            ),
            const SizedBox(height: 11),
            _buildDonutSection(),
            const SizedBox(height: 25),

            // ── Reorder risk ─────────────────────────────
            _buildAnalyticsSectionHeading(
              icon: Icons.warning_amber_rounded,
              title: 'Reorder watch',
              subtitle: 'Most urgent items from the complete stock list',
              color: AppColors.warning,
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '$_lowStockCount items',
                  style: AppTextStyles.caption.copyWith(
                    color: const Color(0xFFF87171),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 11),
            _buildLowStockList(),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // SECTION HEADINGS
  // ──────────────────────────────────────────────────────────────
  Widget _buildAnalyticsSectionHeading({
    required IconData icon,
    required String title,
    required String subtitle,
    Color color = AppColors.cyan,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: color.withValues(alpha: .2)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.subtitle.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────
  // HERO BANNER
  // ──────────────────────────────────────────────────────────────
  Widget _buildHeroBanner() {
    final sourceColor = _reportErrors.isNotEmpty
        ? AppColors.warning
        : _hasLiveData
            ? AppColors.success
            : AppColors.textMuted;
    final sourceLabel = _loading && !_hasLiveData
        ? 'SYNCING'
        : _reportErrors.isNotEmpty
            ? 'PARTIAL'
            : _hasLiveData
                ? 'LIVE DATA'
                : 'NO DATA';
    return InventoryPanel(
      padding: EdgeInsets.zero,
      borderColor: AppColors.cyan.withValues(alpha: .24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF172B43),
                      Color(0xFF10243A),
                      Color(0xFF122D38),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _heroGlowController,
              builder: (context, child) {
                final pulse =
                    _motionDisabled == true ? .45 : _heroGlowController.value;
                return Positioned(
                  right: -48 - (pulse * 12),
                  top: -72 + (pulse * 10),
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.cyan
                          .withValues(alpha: .035 + (pulse * .035)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.violet
                              .withValues(alpha: .08 + (pulse * .08)),
                          blurRadius: 45 + (pulse * 20),
                          spreadRadius: 10 + (pulse * 8),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const UnifyLogoMark(size: 42, glow: false),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Unify',
                              style: AppTextStyles.subtitle.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Innovate · Adapt · Operate',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textMuted,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 6),
                        decoration: BoxDecoration(
                          color: sourceColor.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: sourceColor.withValues(alpha: .28)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: sourceColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color: sourceColor.withValues(alpha: .5),
                                      blurRadius: 5),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              sourceLabel,
                              style: AppTextStyles.caption.copyWith(
                                color: sourceColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 9,
                                letterSpacing: .35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 17),
                  Text(
                    'Your stock, in focus',
                    style: AppTextStyles.headlineSmall.copyWith(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.45,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'One complete view of stock on hand, value, movement and items needing attention.',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _AnalyticsTopicPill(
                          icon: Icons.show_chart_rounded, label: 'REVENUE'),
                      _AnalyticsTopicPill(
                          icon: Icons.swap_vert_rounded, label: 'MOVEMENT'),
                      _AnalyticsTopicPill(
                          icon: Icons.notifications_active_outlined,
                          label: 'REORDER'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // TIMEFRAME ROW
  // ──────────────────────────────────────────────────────────────
  Widget _buildTimeframeRow() {
    return InventoryPanel(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.date_range_rounded,
                color: AppColors.cyan, size: 17),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DATE RANGE',
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 8,
                    letterSpacing: .8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Analytics period',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1728),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTimeframePill('7 days', 0),
                _buildTimeframePill('30 days', 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeframePill(String label, int index) {
    final selected = _selectedTimeframe == index;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: _loading ? null : () => _selectTimeframe(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.cyan.withValues(alpha: .16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected
                    ? AppColors.cyan.withValues(alpha: .42)
                    : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: selected ? AppColors.cyan : AppColors.textSecondary,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // COMPLETE STOCK SNAPSHOT
  // ──────────────────────────────────────────────────────────────
  Widget _buildInventorySnapshot() {
    final hasSnapshot = _hasInventorySnapshot;
    final healthyItems = math.max(0, _totalSkus - _lowStockCount);
    final healthRatio = _totalSkus == 0 ? 0.0 : healthyItems / _totalSkus;
    return InventoryPanel(
      padding: EdgeInsets.zero,
      fill: const Color(0xFF111F34),
      borderColor: AppColors.cyan.withValues(alpha: .24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF142941), Color(0xFF101B30)],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -24,
              top: -30,
              child: Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.cyan.withValues(alpha: .04),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan.withValues(alpha: .08),
                      blurRadius: 35,
                      spreadRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'VALUED STOCK ON HAND',
                          style: AppTextStyles.label.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 9,
                            letterSpacing: .9,
                          ),
                        ),
                      ),
                      Icon(Icons.account_balance_wallet_outlined,
                          color: AppColors.cyan.withValues(alpha: .85),
                          size: 19),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    hasSnapshot
                        ? 'LKR ${_formatCompact(_totalStockValue)}'
                        : _loading
                            ? 'Syncing…'
                            : 'Unavailable',
                    style: AppTextStyles.headlineSmall.copyWith(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    hasSnapshot
                        ? _itemsWithoutUnitCost == 0
                            ? 'Quantity × unit cost across all inventory items'
                            : '$_itemsWithoutUnitCost items missing cost are excluded'
                        : 'Could not load the complete stock snapshot',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(
                      height: 1,
                      color: AppColors.glassBorder.withValues(alpha: .8)),
                  const SizedBox(height: 13),
                  Row(
                    children: [
                      Expanded(
                        child: _SnapshotStat(
                          icon: Icons.qr_code_2_rounded,
                          label: 'ITEMS',
                          value: hasSnapshot ? '$_totalSkus' : '—',
                          color: AppColors.cyan,
                        ),
                      ),
                      Expanded(
                        child: _SnapshotStat(
                          icon: Icons.inventory_2_outlined,
                          label: 'UNITS ON HAND',
                          value: hasSnapshot
                              ? _formatQuantity(_totalStockUnits)
                              : '—',
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _SnapshotStat(
                          icon: Icons.warning_amber_rounded,
                          label: 'LOW / REORDER',
                          value: hasSnapshot ? '$_lowStockCount' : '—',
                          color: AppColors.warning,
                        ),
                      ),
                      Expanded(
                        child: _SnapshotStat(
                          icon: Icons.remove_shopping_cart_outlined,
                          label: 'OUT OF STOCK',
                          value: hasSnapshot ? '$_outOfStockCount' : '—',
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: .18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'HEALTHY STOCK',
                                    style: AppTextStyles.label.copyWith(
                                      color: AppColors.success,
                                      fontSize: 8,
                                      letterSpacing: .6,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Above reorder level',
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.textMuted,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              hasSnapshot ? '$healthyItems / $_totalSkus' : '—',
                              style: AppTextStyles.subtitle.copyWith(
                                color: AppColors.success,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: hasSnapshot ? healthRatio : 0,
                            minHeight: 6,
                            backgroundColor:
                                AppColors.success.withValues(alpha: .12),
                            valueColor: const AlwaysStoppedAnimation(
                              AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportErrorPanel() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.warning.withValues(alpha: .28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                color: AppColors.warning, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _sessionExpired
                        ? 'Sign-in required'
                        : 'Some data could not be loaded',
                    style: AppTextStyles.subtitle.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ..._reportErrors.map((error) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          error,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      )),
                ],
              ),
            ),
            if (!_sessionExpired)
              IconButton(
                onPressed:
                    _loading ? null : () => _fetchAnalytics(showSuccess: true),
                tooltip: 'Retry analytics',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh_rounded,
                    color: AppColors.warning, size: 18),
              ),
          ],
        ),
      );

  // ──────────────────────────────────────────────────────────────
  // REVENUE CHART
  // ──────────────────────────────────────────────────────────────
  Widget _buildInventoryActivitySummary() {
    return InventoryPanel(
      borderColor: const Color(0xFF29394D),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Expanded(
          child: _PeriodMovementMetric(
            label: 'RECEIVED Â· $_selectedPeriodLabel',
            value: _hasMovementReport ? _formatQuantity(_totalReceived) : 'â€”',
            color: AppColors.success,
            icon: Icons.south_west_rounded,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _PeriodMovementMetric(
            label: 'ISSUED Â· $_selectedPeriodLabel',
            value: _hasMovementReport ? _formatQuantity(_totalIssued) : 'â€”',
            color: AppColors.warning,
            icon: Icons.north_east_rounded,
          ),
        ),
      ]),
    );
  }

  Widget _buildDonutSection() {
    return InventoryPanel(
      borderColor: const Color(0xFF29394D),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Category value breakdown',
              style:
                  AppTextStyles.subtitle.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            _itemsWithoutUnitCost == 0
                ? 'Current on-hand value by category'
                : 'Current value by category · items missing cost excluded',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textMuted,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 16),
          if (!_hasInventorySnapshot)
            _buildEmptyChart(
              Icons.inventory_2_outlined,
              'Inventory valuation unavailable',
              'Refresh to try loading the complete inventory',
            )
          else if (_categories.isEmpty)
            _buildEmptyChart(
              Icons.donut_large_rounded,
              'No category value recorded',
              _itemsWithoutUnitCost == 0
                  ? 'Current inventory has no positive on-hand value'
                  : 'Add unit costs to inventory items to see their value share',
            )
          else
            Row(
              children: [
                SizedBox(
                  width: 124,
                  height: 124,
                  child: _DonutChart(
                    slices: _categories,
                    centerValue: _formatCompact(_totalStockValue),
                    isDark: true,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _categories.map((category) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: category.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    category.label,
                                    style: AppTextStyles.caption.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${(category.pct * 100).toStringAsFixed(0)}%',
                                  style: AppTextStyles.caption.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: category.color,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Padding(
                              padding: const EdgeInsets.only(left: 15),
                              child: Text(
                                'LKR ${_formatCompact(category.amount)}',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textMuted,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // LOW-STOCK LIST
  // ──────────────────────────────────────────────────────────────
  Widget _buildLowStockList() {
    if (_lowStock.isEmpty) {
      final title = !_hasInventorySnapshot
          ? (_loading ? 'Checking current stock…' : 'Stock levels unavailable')
          : 'All stock levels healthy';
      final detail = !_hasInventorySnapshot
          ? 'Refresh to load stock for your accessible branches.'
          : 'No items are at or below their reorder level.';
      return InventoryPanel(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(
              _hasInventorySnapshot
                  ? Icons.check_circle_rounded
                  : Icons.inventory_2_outlined,
              color: _hasInventorySnapshot
                  ? AppColors.success
                  : AppColors.textMuted,
              size: 40,
            ),
            const SizedBox(height: 10),
            Text(title,
                style: AppTextStyles.subtitle
                    .copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(detail,
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          ],
        ),
      );
    }

    return InventoryPanel(
      borderColor: const Color(0xFF29394D),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Showing ${_lowStock.length} most urgent of $_lowStockCount items',
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 13),
          for (var i = 0; i < _lowStock.length; i++) ...[
            _buildLowStockRow(_lowStock[i]),
            if (i < _lowStock.length - 1)
              Divider(
                height: 1,
                color: AppColors.hairline.withValues(alpha: 0.7),
              ),
            if (i < _lowStock.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildLowStockRow(LowStockPoint item) {
    final fillPct = item.reorderLevel > 0
        ? (item.quantity / item.reorderLevel).clamp(0.0, 1.0)
        : 0.0;
    final isOut = item.quantity <= 0;
    final accentColor = isOut ? AppColors.danger : const Color(0xFFF59E0B);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style:
                      AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: accentColor.withValues(alpha: 0.35)),
                ),
                child: Text(
                  isOut
                      ? 'OUT OF STOCK'
                      : '${(fillPct * 100).toInt()}% TO REORDER',
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SKU: ${item.sku}',
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.textMuted),
              ),
              Text(
                '${item.quantity.toInt()} / ${item.reorderLevel.toInt()} units',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fillPct,
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // EMPTY CHART PLACEHOLDER
  // ──────────────────────────────────────────────────────────────
  Widget _buildEmptyChart(IconData icon, String title, String subtitle) {
    return SizedBox(
      height: 160,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: AppColors.textMuted.withValues(alpha: 0.5), size: 38),
            const SizedBox(height: 10),
            Text(title,
                style:
                    AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(subtitle,
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  static String _formatCompact(double number) {
    if (number >= 1000000000) {
      return '${(number / 1000000000).toStringAsFixed(1)}B';
    }
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toStringAsFixed(0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTED REVENUE AREA CHART (unchanged logic)
// ─────────────────────────────────────────────────────────────────────────────
class _DonutChart extends StatelessWidget {
  const _DonutChart({
    required this.slices,
    required this.centerValue,
    required this.isDark,
  });
  final List<CategoryBreakdown> slices;
  final String centerValue;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(128, 128),
      painter: _DonutChartPainter(
        slices: slices,
        centerValue: centerValue,
        isDark: isDark,
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter({
    required this.slices,
    required this.centerValue,
    required this.isDark,
  });
  final List<CategoryBreakdown> slices;
  final String centerValue;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const strokeW = 18.0;

    double startAngle = -math.pi / 2;
    const gapAngle = 0.05;

    for (final s in slices) {
      final sweepAngle = (s.pct * 2 * math.pi) - gapAngle;
      if (sweepAngle <= 0) continue;

      // Glow pass
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..color = s.color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW + 6
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round,
      );

      startAngle += sweepAngle + gapAngle;
    }

    // Center text
    const numStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w900,
      color: Colors.white,
    );
    final subStyle = TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w700,
      color: Colors.white.withValues(alpha: 0.5),
    );

    final tp1 = TextPainter(
      text: TextSpan(text: centerValue, style: numStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp1.paint(canvas, Offset(center.dx - tp1.width / 2, center.dy - 13));

    final tp2 = TextPainter(
      text: TextSpan(text: 'ON HAND', style: subStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(center.dx - tp2.width / 2, center.dy + 4));
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.slices != slices ||
      oldDelegate.centerValue != centerValue ||
      oldDelegate.isDark != isDark;
}

class _SnapshotStat extends StatelessWidget {
  const _SnapshotStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 7,
                    letterSpacing: .45,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.subtitle.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _PeriodMovementMetric extends StatelessWidget {
  const _PeriodMovementMetric({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 7,
                      letterSpacing: .1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: AppTextStyles.subtitle.copyWith(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL TOPIC PILLS
// ─────────────────────────────────────────────────────────────────────────────
class _AnalyticsTopicPill extends StatelessWidget {
  const _AnalyticsTopicPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.cyan),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTextStyles.label.copyWith(
                fontSize: 8,
                letterSpacing: .45,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// CHART LEGEND DOT
// ─────────────────────────────────────────────────────────────────────────────
