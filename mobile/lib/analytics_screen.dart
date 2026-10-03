import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'auth/authenticated_api_client.dart';
import 'auth/app_notifications.dart';

class RevenuePoint {
  const RevenuePoint(this.label, this.date, this.revenue);
  final String label;
  final String date;
  final double revenue;
}

class UsagePoint {
  const UsagePoint(this.name, this.sku, this.received, this.issued, this.net);
  final String name;
  final String sku;
  final int received;
  final int issued;
  final int net;
}

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

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, this.client});
  final AuthenticatedApiClient? client;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  bool _loading = false;
  bool _usedFallback = true;
  int _selectedTimeframe = 0; // 0: 7 Days, 1: 30 Days

  List<RevenuePoint> _revenue = const [
    RevenuePoint('Aug 09', '2026-08-09', 98000),
    RevenuePoint('Aug 10', '2026-08-10', 116000),
    RevenuePoint('Aug 11', '2026-08-11', 127500),
    RevenuePoint('Aug 12', '2026-08-12', 143000),
    RevenuePoint('Aug 13', '2026-08-13', 131000),
    RevenuePoint('Aug 14', '2026-08-14', 156500),
    RevenuePoint('Aug 15', '2026-08-15', 120000),
  ];

  List<UsagePoint> _usage = const [
    UsagePoint('Coffee', 'SKU-00132', 120, 92, 28),
    UsagePoint('Cups', 'SKU-00612', 180, 126, 54),
    UsagePoint('Milk', 'SKU-00811', 160, 143, 17),
    UsagePoint('Boxes', 'SKU-00598', 82, 44, 38),
    UsagePoint('Syrup', 'SKU-00324', 50, 22, 28),
  ];

  List<LowStockPoint> _lowStock = const [
    LowStockPoint('Premium Coffee Beans', 'SKU-00132', 6, 40, 'LowStock'),
    LowStockPoint('Vanilla Syrup 750ml', 'SKU-00324', 0, 25, 'OutOfStock'),
    LowStockPoint('Packaging Boxes Medium', 'SKU-00598', 11, 60, 'LowStock'),
    LowStockPoint('Whole Milk 1L Small', 'SKU-00811', 18, 80, 'LowStock'),
  ];

  final List<CategoryBreakdown> _categories = const [
    CategoryBreakdown('Raw Materials', 1842200, 0.44, Color(0xFF6366F1)),
    CategoryBreakdown('Dairy & Milks', 1264400, 0.28, Color(0xFF06B6D4)),
    CategoryBreakdown('Ingredients', 1105800, 0.18, Color(0xFF10B981)),
    CategoryBreakdown('Packaging', 884600, 0.10, Color(0xFFF59E0B)),
  ];

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  Future<void> _fetchAnalytics() async {
    if (widget.client == null) return;
    // Once an authenticated API client is present, never keep showing the
    // seeded demo series as if it were live data.
    setState(() {
      _revenue = [];
      _usage = [];
      _lowStock = [];
      _usedFallback = false;
    });
    setState(() => _loading = true);
    var failedReports = 0;
    try {
      final revRes = await widget.client!.get('/api/reports/revenue');
      if (revRes.statusCode == 200) {
        final data = jsonDecode(revRes.body) as Map<String, dynamic>;
        final buckets = (data['buckets'] as List?) ?? [];
        _revenue = buckets
            .whereType<Map<String, dynamic>>()
            .map((b) => RevenuePoint(
                  b['label'] as String? ?? '',
                  b['date'] as String? ?? '',
                  (b['revenue'] as num?)?.toDouble() ?? 0,
                ))
            .toList();
      }
    } catch (_) {
      failedReports++;
    }

    try {
      final usageRes = await widget.client!.get('/api/reports/inventory-usage');
      if (usageRes.statusCode == 200) {
        final data = jsonDecode(usageRes.body) as Map<String, dynamic>;
        final items = (data['items'] as List?) ?? [];
        _usage = items
            .whereType<Map<String, dynamic>>()
            .take(5)
            .map((u) => UsagePoint(
                  u['itemName'] as String? ?? 'Item',
                  u['sku'] as String? ?? '',
                  (u['receivedQuantity'] as num?)?.toInt() ?? 0,
                  (u['issuedQuantity'] as num?)?.toInt() ?? 0,
                  (u['netQuantity'] as num?)?.toInt() ?? 0,
                ))
            .toList();
      }
    } catch (_) {
      failedReports++;
    }

    try {
      final lowStockRes =
          await widget.client!.get('/api/inventory/low-stock?pageSize=6');
      if (lowStockRes.statusCode == 200) {
        final data = jsonDecode(lowStockRes.body) as Map<String, dynamic>;
        final items = (data['items'] as List?) ?? [];
        _lowStock = items
            .whereType<Map<String, dynamic>>()
            .map((i) => LowStockPoint(
                  i['name'] as String? ?? 'Item',
                  i['sku'] as String? ?? '',
                  (i['quantity'] as num?)?.toDouble() ?? 0,
                  (i['reorderLevel'] as num?)?.toDouble() ?? 10,
                  i['status'] as String? ?? 'LowStock',
                ))
            .toList();
      }
    } catch (_) {
      failedReports++;
    }

    if (mounted) {
      setState(() => _loading = false);
      if (failedReports > 0) {
        showAppNotification(
            '$failedReports analytics report${failedReports == 1 ? '' : 's'} could not be loaded.',
            tone: AppNotificationTone.warning);
      }
    }
  }

  double get _totalRevenue =>
      _revenue.fold(0, (sum, item) => sum + item.revenue);
  int get _totalReceived => _usage.fold(0, (sum, item) => sum + item.received);
  int get _totalIssued => _usage.fold(0, (sum, item) => sum + item.issued);
  int get _netQuantity => _totalReceived - _totalIssued;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _fetchAnalytics,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            // Top Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OPERATIONS / ANALYTICS',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Analytics Dashboard',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (_usedFallback
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF10B981))
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (_usedFallback
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF10B981))
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _usedFallback
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _usedFallback ? 'Live data unavailable' : 'Live sync',
                        style: TextStyle(
                          color: _usedFallback
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Revenue trends, stock pressure, inventory movement & category breakdown in one view.',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),

            // Timeframe Selector
            Row(
              children: [
                _TimeframePill(
                  label: '7 Days',
                  selected: _selectedTimeframe == 0,
                  onTap: () => setState(() => _selectedTimeframe = 0),
                ),
                const SizedBox(width: 8),
                _TimeframePill(
                  label: '30 Days',
                  selected: _selectedTimeframe == 1,
                  onTap: () => setState(() => _selectedTimeframe = 1),
                ),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    onPressed: _fetchAnalytics,
                    tooltip: 'Refresh analytics',
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // 4 High-Impact KPI Cards
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                return GridView.count(
                  crossAxisCount: wide ? 4 : 2,
                  childAspectRatio: wide ? 2.45 : 1.28,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    _KpiMetricCard(
                      title: 'Revenue',
                      value: 'LKR ${_formatCompact(_totalRevenue)}',
                      detail: '+14.2% vs last',
                      icon: Icons.payments_outlined,
                      color: const Color(0xFF6366F1),
                      isPositive: true,
                    ),
                    _KpiMetricCard(
                      title: 'Stock Received',
                      value: '$_totalReceived units',
                      detail: '30-day window',
                      icon: Icons.move_to_inbox_outlined,
                      color: const Color(0xFF06B6D4),
                    ),
                    _KpiMetricCard(
                      title: 'Stock Issued',
                      value: '$_totalIssued units',
                      detail: '+$_netQuantity net',
                      icon: Icons.outbox_rounded,
                      color: const Color(0xFF10B981),
                    ),
                    _KpiMetricCard(
                      title: 'Low Stock Alert',
                      value: '${_lowStock.length} items',
                      detail: 'Needs attention',
                      icon: Icons.warning_amber_rounded,
                      color: const Color(0xFFEF4444),
                      isAlert: true,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 22),

            // GRAPH 1: REVENUE TRENDS AREA CHART
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Revenue Trends',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Daily revenue (LKR) over selected window',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF6366F1).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Total: LKR ${_formatCompact(_totalRevenue)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF818CF8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Custom Painted Interactive Area Chart
                    SizedBox(
                      height: 190,
                      child: _RevenueAreaChart(
                        points: _revenue,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // GRAPH 2: INVENTORY MOVEMENT (RECEIVED VS ISSUED) DUAL BAR CHART
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Inventory Movement',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Received vs Issued units by top item',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        // Legend
                        Row(
                          children: [
                            _ChartLegendDot(
                                color: const Color(0xFF10B981),
                                label: 'Received'),
                            const SizedBox(width: 10),
                            _ChartLegendDot(
                                color: const Color(0xFFF59E0B),
                                label: 'Issued'),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Custom Painted Dual Bar Chart
                    SizedBox(
                      height: 185,
                      child: _InventoryDualBarChart(
                        usage: _usage,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // GRAPH 3: STOCK HEALTH & CATEGORY DONUT CHART
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stock Valuation & Slices',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Portfolio distribution across 4 main categories',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        // Donut Wheel
                        SizedBox(
                          width: 120,
                          height: 120,
                          child: _DonutChart(
                            slices: _categories,
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 18),
                        // Slices Legend List
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _categories.map((c) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: c.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        c.label,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${(c.pct * 100).toInt()}%',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
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
              ),
            ),
            const SizedBox(height: 18),

            // SECTION 4: LOW-STOCK PRESSURE & FILL RATE LIST
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Low-Stock Pressure & Fill Rate',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFEF4444).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_lowStock.length} Critical',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFF87171),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Items operating below safety reorder threshold',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._lowStock.map((item) {
                      final fillPct = item.reorderLevel > 0
                          ? (item.quantity / item.reorderLevel).clamp(0.0, 1.0)
                          : 0.0;
                      final isOut = item.quantity <= 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (isOut
                                            ? const Color(0xFFEF4444)
                                            : const Color(0xFFF59E0B))
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isOut
                                        ? '0% • OUT OF STOCK'
                                        : '${(fillPct * 100).toInt()}% • LOW',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: isOut
                                          ? const Color(0xFFEF4444)
                                          : const Color(0xFFF59E0B),
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
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  '${item.quantity.toInt()} / ${item.reorderLevel.toInt()} units',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: fillPct,
                                minHeight: 6,
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isOut
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFFF59E0B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatCompact(double number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(0)}K';
    }
    return number.toStringAsFixed(0);
  }
}

// -------------------------------------------------------------
// CUSTOM PAINTED REVENUE AREA CHART
// -------------------------------------------------------------
class _RevenueAreaChart extends StatefulWidget {
  const _RevenueAreaChart({required this.points, required this.isDark});
  final List<RevenuePoint> points;
  final bool isDark;

  @override
  State<_RevenueAreaChart> createState() => _RevenueAreaChartState();
}

class _RevenueAreaChartState extends State<_RevenueAreaChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return const Center(child: Text('No revenue data recorded'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _updateTouch(details.localPosition.dx, width),
          onHorizontalDragUpdate: (details) =>
              _updateTouch(details.localPosition.dx, width),
          onHorizontalDragEnd: (_) => setState(() => _hoveredIndex = null),
          onTapUp: (_) => setState(() => _hoveredIndex = null),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: Size(width, height),
                painter: _RevenueChartPainter(
                  points: widget.points,
                  selectedIndex: _hoveredIndex,
                  isDark: widget.isDark,
                ),
              ),
              if (_hoveredIndex != null &&
                  _hoveredIndex! < widget.points.length)
                Positioned(
                  top: 0,
                  left: math.max(
                      0,
                      math.min(
                          width - 120,
                          _getXForIndex(
                                  _hoveredIndex!, width, widget.points.length) -
                              60)),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1B4B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF6366F1)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black38, blurRadius: 8)
                      ],
                    ),
                    child: Text(
                      '${widget.points[_hoveredIndex!].label}: LKR ${widget.points[_hoveredIndex!].revenue.toInt()}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _updateTouch(double localX, double totalWidth) {
    final leftPadding = 38.0;
    final rightPadding = 16.0;
    final chartWidth = totalWidth - leftPadding - rightPadding;
    final count = widget.points.length;
    if (count <= 1) return;
    final step = chartWidth / (count - 1);
    final relativeX = localX - leftPadding;
    final index = (relativeX / step).round().clamp(0, count - 1);
    if (_hoveredIndex != index) {
      setState(() => _hoveredIndex = index);
    }
  }

  double _getXForIndex(int i, double totalWidth, int count) {
    const leftPadding = 38.0;
    const rightPadding = 16.0;
    final chartWidth = totalWidth - leftPadding - rightPadding;
    final step = chartWidth / (count - 1);
    return leftPadding + i * step;
  }
}

class _RevenueChartPainter extends CustomPainter {
  _RevenueChartPainter({
    required this.points,
    required this.selectedIndex,
    required this.isDark,
  });

  final List<RevenuePoint> points;
  final int? selectedIndex;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const leftPad = 38.0;
    const rightPad = 16.0;
    const topPad = 24.0;
    const bottomPad = 24.0;

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    final maxVal = points.map((p) => p.revenue).reduce(math.max);
    final ceiling = math.max(maxVal * 1.15, 1000.0);

    // Draw horizontal grid lines & Y labels
    final gridLinePaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)
      ..strokeWidth = 1.0;

    final labelStyle = TextStyle(
      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.45),
      fontSize: 9.5,
      fontWeight: FontWeight.w600,
    );

    for (int i = 0; i <= 3; i++) {
      final yRatio = i / 3.0;
      final y = topPad + chartH * (1.0 - yRatio);
      final valueAtY = ceiling * yRatio;

      canvas.drawLine(
          Offset(leftPad, y), Offset(size.width - rightPad, y), gridLinePaint);

      final label = '${(valueAtY / 1000).toStringAsFixed(0)}k';
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 6, y - tp.height / 2));
    }

    // Calculate (x, y) coordinates
    final stepX = chartW / (points.length - 1);
    final coords = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final x = leftPad + i * stepX;
      final ratio = (points[i].revenue / ceiling).clamp(0.0, 1.0);
      final y = topPad + chartH * (1.0 - ratio);
      coords.add(Offset(x, y));
    }

    // Build smooth cubic bezier curve
    final path = Path()..moveTo(coords.first.dx, coords.first.dy);
    for (int i = 0; i < coords.length - 1; i++) {
      final p0 = coords[i];
      final p1 = coords[i + 1];
      final cx1 = p0.dx + (p1.dx - p0.dx) / 2;
      final cy1 = p0.dy;
      final cx2 = p0.dx + (p1.dx - p0.dx) / 2;
      final cy2 = p1.dy;
      path.cubicTo(cx1, cy1, cx2, cy2, p1.dx, p1.dy);
    }

    // Area Fill
    final areaPath = Path.from(path)
      ..lineTo(coords.last.dx, topPad + chartH)
      ..lineTo(coords.first.dx, topPad + chartH)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF6366F1).withValues(alpha: 0.38),
          const Color(0xFF6366F1).withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH))
      ..style = PaintingStyle.fill;
    canvas.drawPath(areaPath, fillPaint);

    // Stroke Line
    final linePaint = Paint()
      ..color = const Color(0xFF6366F1)
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);

    // Draw Points & X-Labels
    for (int i = 0; i < coords.length; i++) {
      final pt = coords[i];
      final isSel = selectedIndex == i;

      // X-Axis Date Label
      if (i % 2 == 0 || i == coords.length - 1) {
        final tp = TextPainter(
          text: TextSpan(text: points[i].label, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(pt.dx - tp.width / 2, size.height - 14));
      }

      if (isSel) {
        // Vertical dashed guideline
        final guidePaint = Paint()
          ..color = const Color(0xFF6366F1).withValues(alpha: 0.6)
          ..strokeWidth = 1.2;
        canvas.drawLine(
            Offset(pt.dx, topPad), Offset(pt.dx, topPad + chartH), guidePaint);

        // Highlight ring
        canvas.drawCircle(
            pt,
            8.0,
            Paint()
              ..color = const Color(0xFF6366F1).withValues(alpha: 0.25)
              ..style = PaintingStyle.fill);
      }

      // Point circle
      canvas.drawCircle(
          pt,
          isSel ? 5.5 : 3.8,
          Paint()
            ..color = const Color(0xFF6366F1)
            ..style = PaintingStyle.fill);
      canvas.drawCircle(
          pt,
          isSel ? 3.0 : 2.0,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant _RevenueChartPainter oldDelegate) =>
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.points != points ||
      oldDelegate.isDark != isDark;
}

// -------------------------------------------------------------
// CUSTOM PAINTED INVENTORY MOVEMENT DUAL BAR CHART
// -------------------------------------------------------------
class _InventoryDualBarChart extends StatelessWidget {
  const _InventoryDualBarChart({required this.usage, required this.isDark});
  final List<UsagePoint> usage;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (usage.isEmpty) {
      return const Center(child: Text('No inventory movement data'));
    }

    return CustomPaint(
      size: Size.infinite,
      painter: _InventoryDualBarPainter(usage: usage, isDark: isDark),
    );
  }
}

class _InventoryDualBarPainter extends CustomPainter {
  _InventoryDualBarPainter({required this.usage, required this.isDark});
  final List<UsagePoint> usage;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (usage.isEmpty) return;

    const leftPad = 32.0;
    const rightPad = 12.0;
    const topPad = 22.0;
    const bottomPad = 24.0;

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    int maxVal = 1;
    for (final u in usage) {
      maxVal = math.max(maxVal, math.max(u.received, u.issued));
    }
    final ceiling = (maxVal * 1.18).toDouble();

    // Horizontal grid lines
    final gridLinePaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)
      ..strokeWidth = 1.0;

    final labelStyle = TextStyle(
      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.5),
      fontSize: 9.5,
      fontWeight: FontWeight.w600,
    );

    for (int i = 0; i <= 3; i++) {
      final yRatio = i / 3.0;
      final y = topPad + chartH * (1.0 - yRatio);
      canvas.drawLine(
          Offset(leftPad, y), Offset(size.width - rightPad, y), gridLinePaint);

      final val = (ceiling * yRatio).toInt();
      final tp = TextPainter(
        text: TextSpan(text: '$val', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 5, y - tp.height / 2));
    }

    // Draw Dual Bars
    final slotW = chartW / usage.length;
    final barW = math.min(slotW * 0.32, 14.0);
    const gap = 3.0;

    final recPaint = Paint()..color = const Color(0xFF10B981);
    final issPaint = Paint()..color = const Color(0xFFF59E0B);

    final valueStyle = TextStyle(
      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.75),
      fontSize: 9.0,
      fontWeight: FontWeight.w800,
    );

    for (int i = 0; i < usage.length; i++) {
      final u = usage[i];
      final slotCenterX = leftPad + i * slotW + slotW / 2;

      // Bar 1: Received
      final recRatio = (u.received / ceiling).clamp(0.0, 1.0);
      final recH = chartH * recRatio;
      final recLeft = slotCenterX - barW - gap / 2;
      final recTop = topPad + chartH - recH;
      final recRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(recLeft, recTop, barW, recH),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(recRect, recPaint);

      // Value above Bar 1
      final recTp = TextPainter(
        text: TextSpan(text: '${u.received}', style: valueStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      recTp.paint(
          canvas, Offset(recLeft + (barW - recTp.width) / 2, recTop - 13));

      // Bar 2: Issued
      final issRatio = (u.issued / ceiling).clamp(0.0, 1.0);
      final issH = chartH * issRatio;
      final issLeft = slotCenterX + gap / 2;
      final issTop = topPad + chartH - issH;
      final issRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(issLeft, issTop, barW, issH),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(issRect, issPaint);

      // Value above Bar 2
      final issTp = TextPainter(
        text: TextSpan(text: '${u.issued}', style: valueStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      issTp.paint(
          canvas, Offset(issLeft + (barW - issTp.width) / 2, issTop - 13));

      // Item Name Label below
      final nameTp = TextPainter(
        text: TextSpan(text: u.name, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      nameTp.paint(
          canvas, Offset(slotCenterX - nameTp.width / 2, size.height - 16));
    }
  }

  @override
  bool shouldRepaint(covariant _InventoryDualBarPainter oldDelegate) =>
      oldDelegate.usage != usage || oldDelegate.isDark != isDark;
}

// -------------------------------------------------------------
// CUSTOM PAINTED DONUT CHART
// -------------------------------------------------------------
class _DonutChart extends StatelessWidget {
  const _DonutChart({required this.slices, required this.isDark});
  final List<CategoryBreakdown> slices;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(120, 120),
      painter: _DonutChartPainter(slices: slices, isDark: isDark),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter({required this.slices, required this.isDark});
  final List<CategoryBreakdown> slices;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const strokeW = 16.0;

    double startAngle = -math.pi / 2;
    const gapAngle = 0.05; // rad gap between slices

    for (final s in slices) {
      final sweepAngle = (s.pct * 2 * math.pi) - gapAngle;
      if (sweepAngle <= 0) continue;

      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );

      startAngle += sweepAngle + gapAngle;
    }

    // Center text
    final numStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w900,
      color: isDark ? Colors.white : Colors.black,
    );
    final subStyle = TextStyle(
      fontSize: 9.5,
      fontWeight: FontWeight.w700,
      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.5),
    );

    final tp1 = TextPainter(
      text: TextSpan(text: '318', style: numStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp1.paint(canvas, Offset(center.dx - tp1.width / 2, center.dy - 12));

    final tp2 = TextPainter(
      text: TextSpan(text: 'Total SKUs', style: subStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(center.dx - tp2.width / 2, center.dy + 4));
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.isDark != isDark;
}

// -------------------------------------------------------------
// HELPER SUBWIDGETS
// -------------------------------------------------------------
class _KpiMetricCard extends StatelessWidget {
  const _KpiMetricCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    this.isPositive,
    this.isAlert,
  });

  final String title, value, detail;
  final IconData icon;
  final Color color;
  final bool? isPositive;
  final bool? isAlert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
              ],
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              detail,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: isAlert == true
                    ? const Color(0xFFEF4444)
                    : isPositive == true
                        ? const Color(0xFF10B981)
                        : theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeframePill extends StatelessWidget {
  const _TimeframePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF6366F1)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _ChartLegendDot extends StatelessWidget {
  const _ChartLegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
