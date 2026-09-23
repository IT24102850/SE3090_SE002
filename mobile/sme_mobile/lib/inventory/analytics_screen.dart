import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';
import 'authenticated_api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, this.client});
  final AuthenticatedApiClient? client;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  bool _loading = false;
  bool _usedFallback = true;
  final _scrollController = ScrollController();
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
    CategoryBreakdown('Raw Materials', 1842200, 0.44, Color(0xFF7A4DFF)),
    CategoryBreakdown('Dairy & Milks', 1264400, 0.28, Color(0xFF00E5FF)),
    CategoryBreakdown('Ingredients', 1105800, 0.18, Color(0xFF10B981)),
    CategoryBreakdown('Packaging', 884600, 0.10, Color(0xFFF59E0B)),
  ];

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchAnalytics({bool showSuccess = false}) async {
    if (widget.client == null) return;
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
        AppSnackBar.info(
          context,
          '$failedReports analytics report${failedReports == 1 ? '' : 's'} could not be loaded.',
        );
      } else if (showSuccess) {
        AppSnackBar.success(
          context,
          'Analytics refreshed successfully. Your latest insights are ready.',
        );
      }
    }
  }

  double get _totalRevenue =>
      _revenue.fold(0, (sum, item) => sum + item.revenue);
  int get _totalReceived => _usage.fold(0, (sum, item) => sum + item.received);
  int get _totalIssued => _usage.fold(0, (sum, item) => sum + item.issued);
  int get _netQuantity => _totalReceived - _totalIssued;

  // ──────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppBackgroundScaffold(
      showParticles: true,
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
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: _buildHeroBanner(),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _fetchAnalytics(showSuccess: true),
              color: AppColors.cyan,
              backgroundColor: AppColors.bgMid,
              child: ListView(
                controller: _scrollController,
                primary: false,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  if (_loading)
                    const LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation(AppColors.cyan),
                    ),
                  if (_loading) const SizedBox(height: 10),
                  // ── Timeframe Pills ──────────────────────────
                  _buildTimeframeRow(),
                  const SizedBox(height: 14),

                  // ── KPI Cards ───────────────────────────────
                  const SectionHeader('KEY METRICS'),
                  const SizedBox(height: 10),
                  _buildKpiGrid(),
                  const SizedBox(height: 18),

                  // ── Revenue Chart ────────────────────────────
                  const SectionHeader('REVENUE TRENDS'),
                  const SizedBox(height: 10),
                  _buildRevenueChart(),
                  const SizedBox(height: 20),

                  // ── Inventory Movement ───────────────────────
                  const SectionHeader('INVENTORY MOVEMENT'),
                  const SizedBox(height: 10),
                  _buildMovementChart(),
                  const SizedBox(height: 20),

                  // ── Category Donut ───────────────────────────
                  const SectionHeader('PORTFOLIO BREAKDOWN'),
                  const SizedBox(height: 10),
                  _buildDonutSection(),
                  const SizedBox(height: 20),

                  // ── Low-Stock Fill Rate ──────────────────────
                  SectionHeader(
                    'LOW-STOCK PRESSURE',
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        '${_lowStock.length} Critical',
                        style: AppTextStyles.caption.copyWith(
                          color: const Color(0xFFF87171),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildLowStockList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // HERO BANNER
  // ──────────────────────────────────────────────────────────────
  Widget _buildHeroBanner() {
    return GlassCard(
      borderColor: AppColors.violet.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          // Icon badge
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7A4DFF), Color(0xFF4C6FFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                    color: AppColors.violet.withValues(alpha: 0.45),
                    blurRadius: 14,
                    spreadRadius: 1),
              ],
            ),
            child: const Icon(Icons.analytics_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Analytics Dashboard',
                    style: AppTextStyles.title
                        .copyWith(fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 1),
                Text(
                  'Revenue trends · Stock pressure · Category breakdown',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted, fontSize: 10.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Live/Demo badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: (_usedFallback ? const Color(0xFFF59E0B) : AppColors.cyan)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color:
                    (_usedFallback ? const Color(0xFFF59E0B) : AppColors.cyan)
                        .withValues(alpha: 0.4),
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
                        : AppColors.cyan,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _usedFallback ? 'Demo' : 'Live',
                  style: AppTextStyles.caption.copyWith(
                    color: _usedFallback
                        ? const Color(0xFFFBBF24)
                        : AppColors.cyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // TIMEFRAME ROW
  // ──────────────────────────────────────────────────────────────
  Widget _buildTimeframeRow() {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderColor: AppColors.violet.withValues(alpha: 0.28),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.violet.withValues(alpha: 0.35),
              ),
            ),
            child: const Icon(
              Icons.date_range_rounded,
              color: AppColors.violet,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reporting window',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _selectedTimeframe == 0
                      ? 'A focused view of the last 7 days'
                      : 'A broader view of the last 30 days',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          _buildTimeframePill('7D', 0),
          const SizedBox(width: 6),
          _buildTimeframePill('30D', 1),
        ],
      ),
    );
  }

  Widget _buildTimeframePill(String label, int index) {
    final selected = _selectedTimeframe == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTimeframe = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF7A4DFF), Color(0xFF4C6FFF)],
                )
              : null,
          color: selected ? null : AppColors.glassFill,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? AppColors.violet.withValues(alpha: 0.6)
                : AppColors.glassBorder,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: AppColors.violet.withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: 0),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppTextStyles.label.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // KPI GRID
  // ──────────────────────────────────────────────────────────────
  Widget _buildKpiGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: wide ? 4 : 2,
            mainAxisExtent: wide ? 132 : 162,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, index) {
            final cards = [
              _KpiMetricCard(
                title: 'Revenue',
                value: 'LKR ${_formatCompact(_totalRevenue)}',
                detail: '+14.2% vs last period',
                icon: Icons.payments_outlined,
                color: AppColors.violet,
                isPositive: true,
              ),
              _KpiMetricCard(
                title: 'Stock Received',
                value: '$_totalReceived units',
                detail: '30-day window',
                icon: Icons.move_to_inbox_outlined,
                color: AppColors.cyan,
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
                color: AppColors.danger,
                isAlert: true,
              ),
            ];
            return cards[index];
          },
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────
  // REVENUE CHART
  // ──────────────────────────────────────────────────────────────
  Widget _buildRevenueChart() {
    return GlassCard(
      borderColor: AppColors.violet.withValues(alpha: 0.35),
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
                  Text('Revenue Trends',
                      style: AppTextStyles.subtitle
                          .copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('Daily revenue (LKR) over selected window',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textMuted)),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.violet.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.violet.withValues(alpha: 0.35)),
                ),
                child: Text(
                  'Total: LKR ${_formatCompact(_totalRevenue)}',
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFA78BFA),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_revenue.isEmpty)
            _buildEmptyChart(Icons.show_chart_rounded,
                'No revenue data recorded', 'Data will appear once API syncs')
          else
            SizedBox(
              height: 190,
              child: _RevenueAreaChart(
                points: _revenue,
                isDark: true,
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // MOVEMENT CHART
  // ──────────────────────────────────────────────────────────────
  Widget _buildMovementChart() {
    return GlassCard(
      borderColor: AppColors.cyan.withValues(alpha: 0.3),
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
                  Text('Inventory Movement',
                      style: AppTextStyles.subtitle
                          .copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('Received vs Issued units by top item',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textMuted)),
                ],
              ),
              const Row(
                children: [
                  _ChartLegendDot(color: Color(0xFF10B981), label: 'Received'),
                  SizedBox(width: 10),
                  _ChartLegendDot(color: Color(0xFFF59E0B), label: 'Issued'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_usage.isEmpty)
            _buildEmptyChart(Icons.bar_chart_rounded, 'No movement data',
                'Inventory usage will appear here')
          else
            SizedBox(
              height: 185,
              child: _InventoryDualBarChart(
                usage: _usage,
                isDark: true,
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // DONUT SECTION
  // ──────────────────────────────────────────────────────────────
  Widget _buildDonutSection() {
    return GlassCard(
      borderColor: const Color(0xFF10B981).withValues(alpha: 0.3),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stock Valuation & Slices',
              style:
                  AppTextStyles.subtitle.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('Portfolio distribution across 4 main categories',
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 128,
                height: 128,
                child: _DonutChart(
                  slices: _categories,
                  isDark: true,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _categories.map((c) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: c.color,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: c.color.withValues(alpha: 0.5),
                                    blurRadius: 6),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.label,
                              style: AppTextStyles.caption
                                  .copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(c.pct * 100).toInt()}%',
                            style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.w800,
                              color: c.color,
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
      return GlassCard(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF10B981), size: 40),
            const SizedBox(height: 10),
            Text('All stock levels healthy!',
                style: AppTextStyles.subtitle
                    .copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('No items are below reorder threshold.',
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          ],
        ),
      );
    }

    return GlassCard(
      borderColor: AppColors.danger.withValues(alpha: 0.3),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Items below safety threshold',
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 16),
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
                      ? '0% • OUT OF STOCK'
                      : '${(fillPct * 100).toInt()}% • LOW',
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
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(0)}K';
    }
    return number.toStringAsFixed(0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTED REVENUE AREA CHART (unchanged logic)
// ─────────────────────────────────────────────────────────────────────────────
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF0D0F2B).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.violet.withValues(alpha: 0.6)),
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.violet.withValues(alpha: 0.25),
                                blurRadius: 12),
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
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _updateTouch(double localX, double totalWidth) {
    const leftPadding = 38.0;
    const rightPadding = 16.0;
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

    final gridLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;

    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.45),
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

    final stepX = chartW / (points.length - 1);
    final coords = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final x = leftPad + i * stepX;
      final ratio = (points[i].revenue / ceiling).clamp(0.0, 1.0);
      final y = topPad + chartH * (1.0 - ratio);
      coords.add(Offset(x, y));
    }

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

    final areaPath = Path.from(path)
      ..lineTo(coords.last.dx, topPad + chartH)
      ..lineTo(coords.first.dx, topPad + chartH)
      ..close();

    // Neon violet gradient fill
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF7A4DFF).withValues(alpha: 0.42),
          const Color(0xFF7A4DFF).withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH))
      ..style = PaintingStyle.fill;
    canvas.drawPath(areaPath, fillPaint);

    // Neon violet stroke
    final linePaint = Paint()
      ..color = const Color(0xFF9D71FF)
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);

    for (int i = 0; i < coords.length; i++) {
      final pt = coords[i];
      final isSel = selectedIndex == i;

      if (i % 2 == 0 || i == coords.length - 1) {
        final tp = TextPainter(
          text: TextSpan(text: points[i].label, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(pt.dx - tp.width / 2, size.height - 14));
      }

      if (isSel) {
        final guidePaint = Paint()
          ..color = const Color(0xFF7A4DFF).withValues(alpha: 0.6)
          ..strokeWidth = 1.2;
        canvas.drawLine(
            Offset(pt.dx, topPad), Offset(pt.dx, topPad + chartH), guidePaint);
        canvas.drawCircle(
            pt,
            9.0,
            Paint()
              ..color = const Color(0xFF7A4DFF).withValues(alpha: 0.22)
              ..style = PaintingStyle.fill);
      }

      canvas.drawCircle(
          pt,
          isSel ? 5.5 : 3.8,
          Paint()
            ..color = const Color(0xFF9D71FF)
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

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTED INVENTORY MOVEMENT DUAL BAR CHART (unchanged logic)
// ─────────────────────────────────────────────────────────────────────────────
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

    final gridLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;

    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.5),
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

    final slotW = chartW / usage.length;
    final barW = math.min(slotW * 0.32, 14.0);
    const gap = 3.0;

    // Neon teal for received, amber for issued
    final recPaint = Paint()..color = const Color(0xFF00E5FF);
    final issPaint = Paint()..color = const Color(0xFFF59E0B);

    final valueStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.75),
      fontSize: 9.0,
      fontWeight: FontWeight.w800,
    );

    for (int i = 0; i < usage.length; i++) {
      final u = usage[i];
      final slotCenterX = leftPad + i * slotW + slotW / 2;

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

      final recTp = TextPainter(
        text: TextSpan(text: '${u.received}', style: valueStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      recTp.paint(
          canvas, Offset(recLeft + (barW - recTp.width) / 2, recTop - 13));

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

      final issTp = TextPainter(
        text: TextSpan(text: '${u.issued}', style: valueStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      issTp.paint(
          canvas, Offset(issLeft + (barW - issTp.width) / 2, issTop - 13));

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

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTED DONUT CHART (unchanged logic, neon colors)
// ─────────────────────────────────────────────────────────────────────────────
class _DonutChart extends StatelessWidget {
  const _DonutChart({required this.slices, required this.isDark});
  final List<CategoryBreakdown> slices;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(128, 128),
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
      fontSize: 17,
      fontWeight: FontWeight.w900,
      color: Colors.white,
    );
    final subStyle = TextStyle(
      fontSize: 9.5,
      fontWeight: FontWeight.w700,
      color: Colors.white.withValues(alpha: 0.5),
    );

    final tp1 = TextPainter(
      text: const TextSpan(text: '318', style: numStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp1.paint(canvas, Offset(center.dx - tp1.width / 2, center.dy - 13));

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

// ─────────────────────────────────────────────────────────────────────────────
// KPI METRIC CARD — Glassmorphic
// ─────────────────────────────────────────────────────────────────────────────
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
    return GlassCard(
      padding: EdgeInsets.zero,
      borderColor: color.withValues(alpha: 0.36),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.15)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(13),
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
                          style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: color.withValues(alpha: 0.35)),
                          boxShadow: [
                            BoxShadow(
                                color: color.withValues(alpha: 0.3),
                                blurRadius: 8,
                                spreadRadius: 0),
                          ],
                        ),
                        child: Icon(icon, color: color, size: 16),
                      ),
                    ],
                  ),
                  Text(
                    value,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    detail,
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isAlert == true
                          ? AppColors.danger
                          : isPositive == true
                              ? const Color(0xFF10B981)
                              : AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHART LEGEND DOT
// ─────────────────────────────────────────────────────────────────────────────
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
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
