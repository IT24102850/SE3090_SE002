import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/billing_models.dart' show formatMoney;
import '../../../models/social_models.dart';
import '../../../providers/social_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';
import 'social_widgets.dart';

/// Where the last 30 days of bookings came from and what the ads cost — the
/// mobile twin of the web Ads & Attribution page. Tracking setup (pixels,
/// Conversions/Events API tokens) stays on the web, where pasting long
/// tokens is practical.
class AdsAttributionScreen extends ConsumerWidget {
  const AdsAttributionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attribution = ref.watch(marketingAttributionProvider);
    final campaigns = ref.watch(marketingCampaignsProvider);

    Future<void> refresh() async {
      ref.invalidate(marketingAttributionProvider);
      ref.invalidate(marketingCampaignsProvider);
    }

    return OwnerScaffold(
      title: 'Ads & Attribution',
      subtitle: 'Last 30 days',
      body: RefreshIndicator(
        color: AppColors.cyan,
        backgroundColor: AppColors.overlaySurface,
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            attribution.when(
              loading: () => const Padding(padding: EdgeInsets.all(40), child: AppLoader()),
              error: (e, _) => ErrorState(message: serverMessage(e, 'Could not load attribution.'), onRetry: refresh),
              data: (a) => _Attribution(report: a),
            ),
            const SizedBox(height: 18),
            campaigns.when(
              loading: () => const Padding(padding: EdgeInsets.all(40), child: AppLoader()),
              error: (e, _) => ErrorState(message: serverMessage(e, 'Could not load campaigns.'), onRetry: refresh),
              data: (c) => _Campaigns(report: c),
            ),
            const SizedBox(height: 14),
            Text('Conversion tracking settings and the event log are on the web app under Ads & Attribution.',
                style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  final AttributionReport report;
  const _Attribution({required this.report});

  @override
  Widget build(BuildContext context) {
    final share = report.totalBookings == 0 ? 0 : (report.socialBookings * 100 / report.totalBookings).round();
    final maxBookings = report.channels.fold<int>(0, (m, c) => c.bookings > m ? c.bookings : m).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatGrid(tiles: [
          StatTile(label: 'Bookings', value: '${report.totalBookings}', sub: 'all channels'),
          StatTile(label: 'From social', value: '${report.socialBookings}', sub: '$share% of bookings', accent: AppColors.cyan),
          StatTile(label: 'Revenue', value: formatMoney(report.totalRevenue), sub: 'completed or paid'),
          StatTile(label: 'Social revenue', value: formatMoney(report.socialRevenue), sub: 'Facebook, Instagram, TikTok', accent: AppColors.success),
        ]),
        const SizedBox(height: 16),
        const SectionHeader('Bookings by channel'),
        if (report.channels.isEmpty)
          Text('No bookings in this period.', style: AppTextStyles.caption)
        else
          GlassCard(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Column(
              children: [
                for (final c in report.channels)
                  RankedBar(
                    label: c.channel,
                    trailing: '${c.bookings} · ${formatMoney(c.revenue)}',
                    value: c.bookings.toDouble(),
                    max: maxBookings,
                    color: platformStyle(c.channel).color,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Campaigns extends StatelessWidget {
  final CampaignReport report;
  const _Campaigns({required this.report});

  String _money(double? v) => v == null ? '—' : formatMoney(v);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Campaigns'),
        for (final w in report.warnings) SocialNotice(w),
        StatGrid(tiles: [
          StatTile(label: 'Ad spend', value: formatMoney(report.totalSpend), sub: 'from the ad accounts'),
          StatTile(label: 'Attributed', value: '${report.attributedBookings}', sub: 'bookings from campaigns'),
          StatTile(label: 'Revenue', value: formatMoney(report.attributedRevenue), sub: 'from those bookings'),
          StatTile(
            label: 'ROAS',
            value: report.blendedRoas == null ? '—' : '${report.blendedRoas!.toStringAsFixed(2)}×',
            sub: 'revenue ÷ spend',
            accent: report.blendedRoas == null
                ? null
                : report.blendedRoas! >= 1
                    ? AppColors.success
                    : AppColors.error,
          ),
        ]),
        const SizedBox(height: 12),
        if (report.campaigns.isEmpty)
          Text('No campaign has spend or tagged bookings in this period. Add the URL parameters from Social Accounts to your ads.',
              style: AppTextStyles.caption),
        for (final c in report.campaigns)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      PlatformMark(platform: c.platform, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(c.campaign, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  DetailRow(label: 'Spend', value: _money(c.spend)),
                  if (c.clicks != null)
                    DetailRow(label: 'Clicks', value: '${c.clicks}${c.ctr == null ? '' : ' · ${(c.ctr! * 100).toStringAsFixed(2)}% CTR'}'),
                  DetailRow(label: 'Bookings', value: '${c.bookings}'),
                  DetailRow(label: 'Revenue', value: formatMoney(c.revenue)),
                  DetailRow(label: 'Cost per booking', value: _money(c.costPerBooking)),
                  DetailRow(
                    label: 'ROAS',
                    value: c.roas == null ? '—' : '${c.roas!.toStringAsFixed(2)}×',
                    valueColor: c.roas == null ? null : (c.roas! >= 1 ? AppColors.success : AppColors.error),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
