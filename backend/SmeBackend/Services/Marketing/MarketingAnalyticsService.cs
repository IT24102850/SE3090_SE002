using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Models.Marketing;

namespace SmeBackend.Services.Marketing;

public sealed record ChannelRow(string Channel, int Bookings, int Converted, int Lost, decimal Revenue, decimal RevenueShare);
public sealed record DailyChannelRow(string Date, string Channel, int Bookings);
public sealed record AttributionReport(
    DateTime From, DateTime To,
    int TotalBookings, decimal TotalRevenue,
    int SocialBookings, decimal SocialRevenue,
    IReadOnlyList<ChannelRow> Channels,
    IReadOnlyList<DailyChannelRow> Daily);

public sealed record CampaignRow(
    string Platform, string? CampaignId, string Campaign,
    decimal? Spend, long? Impressions, long? Clicks,
    decimal? Ctr, decimal? Cpc,
    int Bookings, int Converted, decimal Revenue,
    decimal? CostPerBooking, decimal? Roas,
    bool MatchedToAdAccount);

public sealed record CampaignReport(
    DateTime From, DateTime To,
    decimal TotalSpend, int AttributedBookings, decimal AttributedRevenue, decimal? BlendedRoas,
    IReadOnlyList<CampaignRow> Campaigns,
    IReadOnlyList<string> Warnings);

public interface IMarketingAnalyticsService
{
    Task<AttributionReport> GetAttributionAsync(Guid tenantId, DateTime from, DateTime to, CancellationToken ct);
    Task<CampaignReport> GetCampaignsAsync(Guid tenantId, DateTime from, DateTime to, CancellationToken ct);
}

/// "Which channel and which ad actually produced bookings and money?"
///
/// Spend, impressions and clicks come from the ad platforms; bookings and
/// revenue come from our own database, attributed by the utm_campaign the
/// booking link carried. A campaign is matched by id first and by name
/// second, so both utm_campaign={{campaign.id}} (Meta) / __CAMPAIGN_ID__
/// (TikTok) and a hand-typed campaign name work.
public sealed class MarketingAnalyticsService(
    AppDbContext db,
    IMetaGraphClient meta,
    ITikTokClient tikTok,
    IPlatformSecretProtector protector,
    IMemoryCache cache) : IMarketingAnalyticsService
{
    public const string DirectChannel = "Direct / in-app";
    private static readonly TimeSpan SpendCacheFor = TimeSpan.FromMinutes(10);

    /// Statuses where the business did not get the money.
    public static readonly BookingStatus[] LostStatuses =
    {
        BookingStatus.Cancelled, BookingStatus.Rejected, BookingStatus.NoShow,
        BookingStatus.WeatherCancelled, BookingStatus.Expired,
    };

    public static readonly BookingStatus[] ConvertedStatuses =
    {
        BookingStatus.Confirmed, BookingStatus.CheckedIn, BookingStatus.InProgress, BookingStatus.Completed,
    };

    public async Task<AttributionReport> GetAttributionAsync(Guid tenantId, DateTime from, DateTime to, CancellationToken ct)
    {
        // Booking has only a soft-delete filter, not a tenant one; the tenant
        // condition is written out here on purpose.
        var rows = await db.Bookings.AsNoTracking()
            .Where(b => b.TenantId == tenantId && b.CreatedAt >= from && b.CreatedAt < to)
            .Select(b => new { b.Source, b.Status, b.TotalCost, b.CreatedAt })
            .ToListAsync(ct);

        var channels = rows
            .GroupBy(r => string.IsNullOrWhiteSpace(r.Source) ? DirectChannel : r.Source!)
            .Select(g =>
            {
                var lost = g.Count(r => LostStatuses.Contains(r.Status));
                var converted = g.Count(r => ConvertedStatuses.Contains(r.Status));
                var revenue = g.Where(r => !LostStatuses.Contains(r.Status)).Sum(r => r.TotalCost ?? 0m);
                return (Channel: g.Key, Bookings: g.Count(), Converted: converted, Lost: lost, Revenue: revenue);
            })
            .OrderByDescending(c => c.Bookings)
            .ToList();

        var totalRevenue = channels.Sum(c => c.Revenue);
        var social = channels.Where(c => SocialPlatform.All.Contains(c.Channel)).ToList();

        var daily = rows
            .GroupBy(r => (Date: r.CreatedAt.Date, Channel: string.IsNullOrWhiteSpace(r.Source) ? DirectChannel : r.Source!))
            .OrderBy(g => g.Key.Date)
            .Select(g => new DailyChannelRow(g.Key.Date.ToString("yyyy-MM-dd"), g.Key.Channel, g.Count()))
            .ToList();

        return new AttributionReport(
            from, to,
            rows.Count, totalRevenue,
            social.Sum(c => c.Bookings), social.Sum(c => c.Revenue),
            channels.Select(c => new ChannelRow(c.Channel, c.Bookings, c.Converted, c.Lost, c.Revenue,
                totalRevenue > 0 ? Math.Round(c.Revenue / totalRevenue, 4) : 0m)).ToList(),
            daily);
    }

    public async Task<CampaignReport> GetCampaignsAsync(Guid tenantId, DateTime from, DateTime to, CancellationToken ct)
    {
        var warnings = new List<string>();

        var (rangeStart, rangeEnd) = (from, to);
        var attributed = await (
            from a in db.BookingAttributions.IgnoreQueryFilters().AsNoTracking()
            join b in db.Bookings.AsNoTracking() on a.BookingId equals b.Id
            where a.TenantId == tenantId && b.TenantId == tenantId && a.CreatedAt >= rangeStart && a.CreatedAt < rangeEnd
            select new { a.Channel, a.UtmCampaign, b.Status, b.TotalCost }).ToListAsync(ct);

        var settings = await db.MarketingSettings.IgnoreQueryFilters().AsNoTracking()
            .FirstOrDefaultAsync(s => s.TenantId == tenantId, ct);

        var since = DateOnly.FromDateTime(from);
        var until = DateOnly.FromDateTime(to.AddTicks(-1));

        var metaSpend = await SpendAsync("meta", tenantId, since, until, warnings, ct, async () =>
        {
            if (settings?.MetaAdAccountId is not { Length: > 0 } account || settings.MetaAdsTokenEncrypted == null) return null;
            return await meta.GetCampaignSpendAsync(account, protector.Unprotect(settings.MetaAdsTokenEncrypted), since, until, ct);
        });
        var tikTokSpend = await SpendAsync("tiktok", tenantId, since, until, warnings, ct, async () =>
        {
            if (settings?.TikTokAdvertiserId is not { Length: > 0 } adv || settings.TikTokAdsTokenEncrypted == null) return null;
            return await tikTok.GetCampaignSpendAsync(adv, protector.Unprotect(settings.TikTokAdsTokenEncrypted), since, until, ct);
        });

        // Which attributed bookings belong to which ad platform.
        static string AdPlatformOf(string channel) => channel switch
        {
            SocialPlatform.Facebook or SocialPlatform.Instagram => "Meta",
            SocialPlatform.TikTok => "TikTok",
            _ => channel,
        };

        var bookingGroups = attributed
            .Where(a => !string.IsNullOrWhiteSpace(a.UtmCampaign))
            .GroupBy(a => (Platform: AdPlatformOf(a.Channel), Campaign: a.UtmCampaign!.Trim()))
            .ToDictionary(
                g => g.Key,
                g => (Bookings: g.Count(),
                      Converted: g.Count(x => ConvertedStatuses.Contains(x.Status)),
                      Revenue: g.Where(x => !LostStatuses.Contains(x.Status)).Sum(x => x.TotalCost ?? 0m)));

        var used = new HashSet<(string, string)>();
        var rows = new List<CampaignRow>();

        void AddSpendRows(string platform, IReadOnlyList<CampaignSpend>? spend)
        {
            if (spend == null) return;
            foreach (var c in spend)
            {
                var key = bookingGroups.Keys.FirstOrDefault(k => k.Platform == platform && !used.Contains(k)
                              && (string.Equals(k.Campaign, c.CampaignId, StringComparison.OrdinalIgnoreCase)
                                  || string.Equals(k.Campaign, c.CampaignName.Trim(), StringComparison.OrdinalIgnoreCase)));
                var stats = key != default && bookingGroups.TryGetValue(key, out var s) ? s : (Bookings: 0, Converted: 0, Revenue: 0m);
                if (key != default) used.Add(key);
                rows.Add(Row(platform, c.CampaignId, c.CampaignName, c.Spend, c.Impressions, c.Clicks, stats.Bookings, stats.Converted, stats.Revenue, true));
            }
        }

        AddSpendRows("Meta", metaSpend);
        AddSpendRows("TikTok", tikTokSpend);

        // Campaign-tagged bookings with no ad-account row: organic UTM
        // campaigns, a disconnected ad account, or a typo in the tag.
        foreach (var (key, s) in bookingGroups.Where(kv => !used.Contains(kv.Key)))
            rows.Add(Row(key.Platform, null, key.Campaign, null, null, null, s.Bookings, s.Converted, s.Revenue, false));

        var ordered = rows.OrderByDescending(r => r.Spend ?? 0).ThenByDescending(r => r.Bookings).ToList();
        var totalSpend = ordered.Sum(r => r.Spend ?? 0m);
        var paidRevenue = ordered.Where(r => r.Spend > 0).Sum(r => r.Revenue);

        if (settings?.MetaAdAccountId == null && settings?.TikTokAdvertiserId == null)
            warnings.Add("No ad account is connected, so spend, CPA and ROAS are not available. Bookings per campaign still are.");

        return new CampaignReport(
            from, to,
            totalSpend,
            attributed.Count,
            attributed.Where(a => !LostStatuses.Contains(a.Status)).Sum(a => a.TotalCost ?? 0m),
            totalSpend > 0 ? Math.Round(paidRevenue / totalSpend, 2) : null,
            ordered,
            warnings);
    }

    private static CampaignRow Row(string platform, string? id, string name, decimal? spend, long? impressions, long? clicks,
        int bookings, int converted, decimal revenue, bool matched) =>
        new(platform, id, name, spend, impressions, clicks,
            impressions > 0 && clicks.HasValue ? Math.Round((decimal)clicks.Value / impressions.Value, 4) : null,
            clicks > 0 && spend.HasValue ? Math.Round(spend.Value / clicks.Value, 2) : null,
            bookings, converted, revenue,
            bookings > 0 && spend.HasValue ? Math.Round(spend.Value / bookings, 2) : null,
            spend > 0 ? Math.Round(revenue / spend.Value, 2) : null,
            matched);

    private async Task<IReadOnlyList<CampaignSpend>?> SpendAsync(
        string platform, Guid tenantId, DateOnly since, DateOnly until, List<string> warnings, CancellationToken ct,
        Func<Task<IReadOnlyList<CampaignSpend>?>> load)
    {
        var key = $"ads-spend:{platform}:{tenantId:N}:{since:yyyyMMdd}:{until:yyyyMMdd}";
        if (cache.TryGetValue(key, out IReadOnlyList<CampaignSpend>? hit)) return hit;
        try
        {
            var result = await load();
            if (result != null) cache.Set(key, result, SpendCacheFor);
            return result;
        }
        catch (SocialApiException e)
        {
            warnings.Add($"{(platform == "meta" ? "Meta" : "TikTok")} ad spend could not be loaded: {e.Message}");
            return null;
        }
        catch (Exception e) when (e is System.Security.Cryptography.CryptographicException or FormatException)
        {
            warnings.Add($"The stored {(platform == "meta" ? "Meta" : "TikTok")} ads token can no longer be read. Enter it again in Ads settings.");
            return null;
        }
    }
}
