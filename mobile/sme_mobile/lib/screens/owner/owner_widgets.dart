import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ui/ui.dart';
import 'owner_nav.dart';

/// The shell every owner screen sits in: the app background, a glass app
/// bar and the workspace drawer, so the whole owner side is one navigation
/// away from itself exactly as the web sidebar is.
class OwnerScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? bottom;

  const OwnerScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return AppBackgroundScaffold(
      appBar: GlassAppBar(
        titleWidget: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: AppTextStyles.title),
            if (subtitle != null)
              Text(subtitle!, style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          ],
        ),
        actions: actions,
        bottom: bottom,
      ),
      drawer: const OwnerDrawer(),
      floatingActionButton: floatingActionButton,
      child: SafeArea(child: body),
    );
  }
}

/// One headline number. Deliberately plain: an owner reading these on a
/// phone wants the figure and what it counts, not a sparkline.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color? accent;
  final VoidCallback? onTap;

  const StatTile({super.key, required this.label, required this.value, this.sub, this.accent, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(), style: AppTextStyles.label.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.stat.copyWith(color: accent ?? AppColors.textPrimary),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption),
          ],
        ],
      ),
    );
  }
}

/// A responsive grid of [StatTile]s — two across on a phone, more when the
/// app is run on a tablet or in a desktop/web window.
class StatGrid extends StatelessWidget {
  final List<Widget> tiles;
  const StatGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth ~/ 190;
      final count = columns.clamp(2, 4);
      return GridView.count(
        crossAxisCount: count,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.55,
        children: tiles,
      );
    });
  }
}

/// A single-choice filter strip. `null` in [options] is the "all" chip, so
/// a screen never has to special-case its own clear button.
class FilterChips<T> extends StatelessWidget {
  final List<({T? value, String label})> options;
  final T? selected;
  final ValueChanged<T?> onSelected;

  const FilterChips({super.key, required this.options, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(option.label),
                selected: option.value == selected,
                onSelected: (_) => onSelected(option.value),
                showCheckmark: false,
                labelStyle: AppTextStyles.caption.copyWith(
                  color: option.value == selected ? AppColors.onPrimary : AppColors.textBody,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: AppColors.glassFill,
                selectedColor: AppColors.cyan,
                side: BorderSide(color: option.value == selected ? AppColors.cyan : AppColors.glassBorder),
              ),
            ),
        ],
      ),
    );
  }
}

/// Renders an [AsyncValue] with the app's own loading, error and empty
/// states, and wires pull-to-refresh to invalidating the provider — which
/// is the behaviour every owner list wants and none of them should have to
/// re-implement.
class AsyncList<T> extends ConsumerWidget {
  final ProviderListenable<AsyncValue<List<T>>> provider;
  final void Function(WidgetRef ref) onRefresh;
  final Widget Function(List<T> items) builder;
  final String emptyMessage;
  final IconData emptyIcon;
  final String errorMessage;

  const AsyncList({
    super.key,
    required this.provider,
    required this.onRefresh,
    required this.builder,
    required this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
    this.errorMessage = 'Could not load this list.',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return RefreshIndicator(
      color: AppColors.cyan,
      backgroundColor: AppColors.overlaySurface,
      onRefresh: () async => onRefresh(ref),
      child: async.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(message: errorMessage, onRetry: () => onRefresh(ref)),
        data: (items) => items.isEmpty
            ? ListView(children: [const SizedBox(height: 80), EmptyState(icon: emptyIcon, message: emptyMessage)])
            : builder(items),
      ),
    );
  }
}

/// A labelled row inside a detail card.
class DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const DetailRow({super.key, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 132, child: Text(label, style: AppTextStyles.caption)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTextStyles.body.copyWith(color: valueColor ?? AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A horizontal bar for one row of a ranked list (top items by usage, by
/// revenue…). Proportional to [max] so the bars in a list compare.
class RankedBar extends StatelessWidget {
  final String label;
  final String trailing;
  final double value;
  final double max;
  final Color color;

  const RankedBar({
    super.key,
    required this.label,
    required this.trailing,
    required this.value,
    required this.max,
    this.color = AppColors.cyan,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body)),
              const SizedBox(width: 10),
              Text(trailing, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: AppColors.glassFill,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact two-series column chart (invoiced vs collected, received vs
/// issued…). Drawn with plain boxes rather than a charting package: the
/// app has none, and a phone-width trend only needs relative heights.
class MiniSeriesChart extends StatelessWidget {
  final List<({String label, double primary, double secondary})> points;
  final Color primaryColor;
  final Color secondaryColor;
  final String primaryLabel;
  final String secondaryLabel;

  const MiniSeriesChart({
    super.key,
    required this.points,
    required this.primaryLabel,
    required this.secondaryLabel,
    this.primaryColor = AppColors.cyan,
    this.secondaryColor = AppColors.success,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Text('Nothing to chart for this period.', style: AppTextStyles.caption);
    }
    final max = points
        .map((p) => p.primary > p.secondary ? p.primary : p.secondary)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Key(color: primaryColor, label: primaryLabel),
            const SizedBox(width: 14),
            _Key(color: secondaryColor, label: secondaryLabel),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final point in points)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _Bar(value: point.primary, max: max, color: primaryColor),
                        const SizedBox(height: 2),
                        _Bar(value: point.secondary, max: max, color: secondaryColor),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(points.first.label, style: AppTextStyles.caption),
            Text(points.last.label, style: AppTextStyles.caption),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double value;
  final double max;
  final Color color;
  const _Bar({required this.value, required this.max, required this.color});

  @override
  Widget build(BuildContext context) {
    final height = max <= 0 ? 1.0 : (value / max * 42).clamp(1.0, 42.0);
    return Container(
      height: height,
      decoration: BoxDecoration(color: color.withValues(alpha: .85), borderRadius: BorderRadius.circular(2)),
    );
  }
}

class _Key extends StatelessWidget {
  final Color color;
  final String label;
  const _Key({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}

/// Coloured pill for a status word. One place for the mapping, so Paid,
/// Active and Completed read the same on every owner screen.
class OwnerStatusChip extends StatelessWidget {
  final String status;
  const OwnerStatusChip({super.key, required this.status});

  static Color colorOf(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'active':
      case 'completed':
      case 'approved':
      case 'received':
      case 'instock':
      case 'available':
        return AppColors.success;
      case 'overdue':
      case 'failed':
      case 'rejected':
      case 'cancelled':
      case 'outofstock':
      case 'noshow':
        return AppColors.error;
      case 'pending':
      case 'issued':
      case 'awaitingapproval':
      case 'partiallypaid':
      case 'submitted':
      case 'underreview':
      case 'lowstock':
      case 'draft':
        return AppColors.warning;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorOf(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .5)),
      ),
      child: Text(status, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

/// The API explains its refusals ("Cannot cancel within 1 hour(s)…", "Item
/// still has stock on hand…"); those read far better than a generic apology,
/// so a screen shows the server's own words whenever there are any.
String serverMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    if (data is Map && data['errors'] is Map) {
      final first = (data['errors'] as Map).values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
    }
  }
  return fallback;
}
