using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Models.Marketing;

namespace SmeBackend.Services.Marketing;

/// Server-side conversion tracking for Meta (Facebook + Instagram ads) and
/// TikTok, in two halves:
///
/// 1. Sweep - looks at recent bookings that came through a public booking
///    link (they have a BookingAttribution) and queues one outbox row per
///    platform per milestone: "booking made", and "booking paid or
///    delivered". Done by looking rather than by hooking every place a
///    booking changes status (check-in, the clinic flow, payment webhooks,
///    the hold sweeper...), so none of that code has to know about ads, and
///    the unique (booking, platform, event) index makes it idempotent.
/// 2. Dispatch - sends due outbox rows with retries and records the result,
///    which is what the Ads screen's event log shows.
public sealed class ConversionWorker(IServiceScopeFactory scopes, ILogger<ConversionWorker> logger) : BackgroundService
{
    private static readonly TimeSpan Tick = TimeSpan.FromMinutes(1);

    /// Meta rejects events older than 7 days; TikTok's window is similar.
    public static readonly TimeSpan MaxEventAge = TimeSpan.FromDays(7);
    public const int MaxAttempts = 5;
    private const int BatchSize = 50;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try { await Task.Delay(TimeSpan.FromSeconds(20), stoppingToken); }
        catch (OperationCanceledException) { return; }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = scopes.CreateScope();
                var sp = scope.ServiceProvider;
                await RunOnceAsync(
                    sp.GetRequiredService<AppDbContext>(),
                    sp.GetRequiredService<IMetaGraphClient>(),
                    sp.GetRequiredService<ITikTokClient>(),
                    sp.GetRequiredService<IPlatformSecretProtector>(),
                    DateTime.UtcNow, logger, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception e)
            {
                logger.LogError(e, "Conversion tracking tick failed");
            }

            try { await Task.Delay(Tick, stoppingToken); }
            catch (OperationCanceledException) { return; }
        }
    }

    public static async Task<(int Queued, int Sent)> RunOnceAsync(
        AppDbContext db, IMetaGraphClient meta, ITikTokClient tikTok, IPlatformSecretProtector protector,
        DateTime now, ILogger logger, CancellationToken ct)
    {
        var queued = await SweepAsync(db, now, logger, ct);
        var sent = await DispatchAsync(db, meta, tikTok, protector, now, ct);
        return (queued, sent);
    }

    public static List<string> ConfiguredPlatforms(MarketingSettings s)
    {
        var list = new List<string>();
        if (!s.ConversionTrackingEnabled) return list;
        if (!string.IsNullOrWhiteSpace(s.MetaPixelId) && !string.IsNullOrEmpty(s.MetaCapiTokenEncrypted)) list.Add(SocialPlatform.Facebook);
        if (!string.IsNullOrWhiteSpace(s.TikTokPixelCode) && !string.IsNullOrEmpty(s.TikTokEventsTokenEncrypted)) list.Add(SocialPlatform.TikTok);
        return list;
    }

    // ── Sweep ──────────────────────────────────────────────────────────────

    public static async Task<int> SweepAsync(AppDbContext db, DateTime now, ILogger logger, CancellationToken ct)
    {
        var tenants = await db.MarketingSettings.IgnoreQueryFilters().AsNoTracking()
            .Where(s => s.ConversionTrackingEnabled
                && ((s.MetaPixelId != null && s.MetaCapiTokenEncrypted != null)
                    || (s.TikTokPixelCode != null && s.TikTokEventsTokenEncrypted != null)))
            .ToListAsync(ct);

        var windowStart = now - MaxEventAge;
        var attributionStart = now.AddDays(-60);
        var added = 0;

        foreach (var settings in tenants)
        {
            var platforms = ConfiguredPlatforms(settings);
            if (platforms.Count == 0) continue;
            var tenantId = settings.TenantId;
            var isTest = !string.IsNullOrWhiteSpace(settings.MetaTestEventCode) || !string.IsNullOrWhiteSpace(settings.TikTokTestEventCode);

            var candidates = new List<(Guid BookingId, string Event, DateTime At, decimal? Value, string? Currency)>();

            var created = await db.BookingAttributions.IgnoreQueryFilters().AsNoTracking()
                .Where(a => a.TenantId == tenantId && a.CreatedAt >= windowStart)
                .Select(a => new { a.BookingId, a.CreatedAt, a.Value, a.Currency })
                .ToListAsync(ct);
            candidates.AddRange(created.Select(c => (c.BookingId, ConversionEventName.BookingCreated, c.CreatedAt, c.Value, c.Currency)));

            var delivered = await (
                from a in db.BookingAttributions.IgnoreQueryFilters()
                join b in db.Bookings.IgnoreQueryFilters() on a.BookingId equals b.Id
                where a.TenantId == tenantId && a.CreatedAt >= attributionStart && b.DeletedAt == null
                    && (b.Status == BookingStatus.Completed || b.Status == BookingStatus.CheckedIn || b.Status == BookingStatus.InProgress)
                    && b.UpdatedAt >= windowStart
                select new { b.Id, b.UpdatedAt, b.TotalCost, a.Currency }).AsNoTracking().ToListAsync(ct);
            candidates.AddRange(delivered.Select(d => (d.Id, ConversionEventName.BookingCompleted, d.UpdatedAt, d.TotalCost, d.Currency)));

            var paid = await (
                from a in db.BookingAttributions.IgnoreQueryFilters()
                join i in db.Invoices.IgnoreQueryFilters() on a.BookingId equals i.BookingId
                where a.TenantId == tenantId && a.CreatedAt >= attributionStart
                    && i.Status == InvoiceStatuses.Paid && i.UpdatedAt >= windowStart
                select new { a.BookingId, i.UpdatedAt, i.FinalAmount, i.Currency }).AsNoTracking().ToListAsync(ct);
            // Paid wins over delivered for the value: it is what actually changed hands.
            candidates.AddRange(paid.Select(p => (p.BookingId, ConversionEventName.BookingCompleted, p.UpdatedAt, (decimal?)p.FinalAmount, (string?)p.Currency)));

            if (candidates.Count == 0) continue;

            var ids = candidates.Select(c => c.BookingId).Distinct().ToList();
            var existing = (await db.ConversionEvents.IgnoreQueryFilters().AsNoTracking()
                    .Where(e => ids.Contains(e.BookingId))
                    .Select(e => new { e.BookingId, e.Platform, e.EventName })
                    .ToListAsync(ct))
                .Select(e => (e.BookingId, e.Platform, e.EventName))
                .ToHashSet();

            // Paid rows were appended last; walk in reverse so they win.
            for (var i = candidates.Count - 1; i >= 0; i--)
            {
                var c = candidates[i];
                foreach (var platform in platforms)
                {
                    if (!existing.Add((c.BookingId, platform, c.Event))) continue;
                    db.ConversionEvents.Add(new ConversionEvent
                    {
                        TenantId = tenantId,
                        BookingId = c.BookingId,
                        Platform = platform,
                        EventName = c.Event,
                        EventTime = c.At,
                        Value = c.Value,
                        Currency = string.IsNullOrWhiteSpace(c.Currency) ? "LKR" : c.Currency!.ToUpperInvariant(),
                        IsTest = isTest,
                        Status = ConversionEventStatus.Pending,
                    });
                    added++;
                }
            }
        }

        if (added == 0) return 0;
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException e)
        {
            // Another instance queued the same rows first. Nothing is lost:
            // whichever got there is the one that will be sent.
            logger.LogWarning(e, "Conversion sweep hit a duplicate; dropping this batch");
            foreach (var entry in db.ChangeTracker.Entries<ConversionEvent>().Where(x => x.State == EntityState.Added).ToList())
                entry.State = EntityState.Detached;
            return 0;
        }
        return added;
    }

    // ── Dispatch ───────────────────────────────────────────────────────────

    public static async Task<int> DispatchAsync(
        AppDbContext db, IMetaGraphClient meta, ITikTokClient tikTok, IPlatformSecretProtector protector, DateTime now, CancellationToken ct)
    {
        var due = await db.ConversionEvents.IgnoreQueryFilters()
            .Where(e => e.Status == ConversionEventStatus.Pending && (e.NextAttemptAt == null || e.NextAttemptAt <= now))
            .OrderBy(e => e.CreatedAt)
            .Take(BatchSize)
            .ToListAsync(ct);
        if (due.Count == 0) return 0;

        var tenantIds = due.Select(e => e.TenantId).Distinct().ToList();
        var settingsByTenant = await db.MarketingSettings.IgnoreQueryFilters().AsNoTracking()
            .Where(s => tenantIds.Contains(s.TenantId))
            .ToDictionaryAsync(s => s.TenantId, ct);

        var sent = 0;
        foreach (var e in due)
        {
            e.UpdatedAt = now;
            settingsByTenant.TryGetValue(e.TenantId, out var settings);

            if (now - e.EventTime > MaxEventAge)
            {
                Finish(e, ConversionEventStatus.Skipped, "Older than 7 days; the platforms no longer accept it.");
                continue;
            }
            if (settings == null || !ConfiguredPlatforms(settings).Contains(e.Platform))
            {
                Finish(e, ConversionEventStatus.Skipped, $"{e.Platform} conversion tracking was turned off before this event was sent.");
                continue;
            }

            try
            {
                var context = await LoadContextAsync(db, e, ct);
                if (context == null)
                {
                    Finish(e, ConversionEventStatus.Skipped, "The booking no longer exists.");
                    continue;
                }

                if (e.Platform == SocialPlatform.Facebook)
                    await meta.SendConversionAsync(settings.MetaPixelId!, protector.Unprotect(settings.MetaCapiTokenEncrypted!),
                        settings.MetaTestEventCode, ConversionPayloads.Meta(context), ct);
                else
                    await tikTok.SendEventAsync(settings.TikTokPixelCode!, protector.Unprotect(settings.TikTokEventsTokenEncrypted!),
                        settings.TikTokTestEventCode, ConversionPayloads.TikTok(context), ct);

                e.Attempts++;
                e.SentAt = now;
                Finish(e, ConversionEventStatus.Sent, null);
                sent++;
            }
            catch (SocialApiException ex) when (ex.Transient && e.Attempts + 1 < MaxAttempts)
            {
                e.Attempts++;
                e.LastError = SocialTokenService.Clip(ex.Message, 1000);
                e.NextAttemptAt = now.AddMinutes(Math.Pow(4, e.Attempts)); // 4, 16, 64, 256 min
            }
            catch (Exception ex) when (ex is SocialApiException or System.Security.Cryptography.CryptographicException or FormatException)
            {
                e.Attempts++;
                Finish(e, ConversionEventStatus.Failed, ex is SocialApiException
                    ? ex.Message
                    : "The stored access token can no longer be read. Enter it again in Ads settings.");
            }
        }

        await db.SaveChangesAsync(ct);
        return sent;
    }

    private static void Finish(ConversionEvent e, string status, string? error)
    {
        e.Status = status;
        e.LastError = error == null ? null : SocialTokenService.Clip(error, 1000);
        e.NextAttemptAt = null;
    }

    private static async Task<ConversionContext?> LoadContextAsync(AppDbContext db, ConversionEvent e, CancellationToken ct)
    {
        var booking = await db.Bookings.IgnoreQueryFilters().AsNoTracking()
            .Where(b => b.Id == e.BookingId && b.TenantId == e.TenantId)
            .Select(b => new { b.Id, b.BookedFor, b.BookedBy, b.BookingTypeId, b.AttendeeCount, b.DeletedAt })
            .FirstOrDefaultAsync(ct);
        if (booking == null || booking.DeletedAt != null) return null;

        var customerId = booking.BookedFor ?? booking.BookedBy;
        var person = await db.Users.IgnoreQueryFilters().AsNoTracking()
            .Where(u => u.Id == customerId)
            .Select(u => new { u.Email, u.Phone, u.FullName })
            .FirstOrDefaultAsync(ct);
        var typeName = await db.BookingTypes.IgnoreQueryFilters().AsNoTracking()
            .Where(t => t.Id == booking.BookingTypeId)
            .Select(t => t.Name)
            .FirstOrDefaultAsync(ct);
        var attribution = await db.BookingAttributions.IgnoreQueryFilters().AsNoTracking()
            .FirstOrDefaultAsync(a => a.BookingId == e.BookingId, ct);

        return new ConversionContext(e, attribution, person?.Email, person?.Phone, person?.FullName, customerId,
            typeName, booking.BookingTypeId, booking.AttendeeCount ?? 1);
    }
}
