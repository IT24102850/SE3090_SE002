using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models.Marketing;
using SmeBackend.Services;
using SmeBackend.Services.Marketing;

namespace SmeBackend.Controllers.Marketing;

/// Digital advertising: conversion tracking settings, the conversion event
/// log, and the attribution / campaign reports.
[ApiController]
[Route("api/marketing")]
[Authorize(Roles = "Admin,Manager")]
public class MarketingController(
    AppDbContext db,
    IPlatformSecretProtector protector,
    IMetaGraphClient meta,
    ITikTokClient tikTok,
    IMarketingAnalyticsService analytics) : MarketingControllerBase
{
    private const int MaxReportDays = 366;

    // ── Settings ───────────────────────────────────────────────────────────

    [HttpGet("settings")]
    public async Task<IActionResult> GetSettings()
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var s = await db.MarketingSettings.AsNoTracking().FirstOrDefaultAsync(x => x.TenantId == tenantId)
                ?? new MarketingSettings { TenantId = tenantId };
        return Ok(SettingsDto(s));
    }

    /// For each token: null leaves it as it is, "" clears it, anything else replaces it.
    public sealed class UpdateSettingsRequest
    {
        public bool? ConversionTrackingEnabled { get; set; }

        [MaxLength(50)] public string? MetaPixelId { get; set; }
        [MaxLength(1000)] public string? MetaCapiToken { get; set; }
        [MaxLength(50)] public string? MetaTestEventCode { get; set; }
        [MaxLength(50)] public string? MetaAdAccountId { get; set; }
        [MaxLength(1000)] public string? MetaAdsToken { get; set; }

        [MaxLength(50)] public string? TikTokPixelCode { get; set; }
        [MaxLength(1000)] public string? TikTokEventsToken { get; set; }
        [MaxLength(50)] public string? TikTokTestEventCode { get; set; }
        [MaxLength(50)] public string? TikTokAdvertiserId { get; set; }
        [MaxLength(1000)] public string? TikTokAdsToken { get; set; }
    }

    [HttpPut("settings")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> UpdateSettings([FromBody] UpdateSettingsRequest body)
    {
        if (TenantId is not { } tenantId) return MissingTenant();

        foreach (var (label, value) in new[] { ("Meta pixel id", body.MetaPixelId), ("TikTok advertiser id", body.TikTokAdvertiserId) })
            if (!string.IsNullOrWhiteSpace(value) && !value.Trim().All(char.IsDigit))
                return BadRequest(new { message = $"{label} should be digits only." });
        if (!string.IsNullOrWhiteSpace(body.MetaAdAccountId))
        {
            var acct = body.MetaAdAccountId.Trim();
            if (!(acct.StartsWith("act_") ? acct[4..] : acct).All(char.IsDigit))
                return BadRequest(new { message = "Meta ad account id should look like act_1234567890." });
        }

        var s = await db.MarketingSettings.FirstOrDefaultAsync(x => x.TenantId == tenantId);
        if (s == null)
        {
            s = new MarketingSettings { TenantId = tenantId };
            db.MarketingSettings.Add(s);
        }

        if (body.ConversionTrackingEnabled is { } enabled) s.ConversionTrackingEnabled = enabled;
        s.MetaPixelId = Plain(body.MetaPixelId, s.MetaPixelId);
        s.MetaTestEventCode = Plain(body.MetaTestEventCode, s.MetaTestEventCode);
        s.MetaAdAccountId = Plain(body.MetaAdAccountId, s.MetaAdAccountId) is { } a ? (a.StartsWith("act_") ? a : "act_" + a) : null;
        s.MetaCapiTokenEncrypted = Secret(body.MetaCapiToken, s.MetaCapiTokenEncrypted);
        if (body.MetaAdsToken != null)
        {
            s.MetaAdsTokenEncrypted = Secret(body.MetaAdsToken, s.MetaAdsTokenEncrypted);
            s.MetaAdsTokenExpiresAt = null; // a pasted token's expiry is not known
        }

        s.TikTokPixelCode = Plain(body.TikTokPixelCode, s.TikTokPixelCode);
        s.TikTokTestEventCode = Plain(body.TikTokTestEventCode, s.TikTokTestEventCode);
        s.TikTokAdvertiserId = Plain(body.TikTokAdvertiserId, s.TikTokAdvertiserId);
        s.TikTokEventsTokenEncrypted = Secret(body.TikTokEventsToken, s.TikTokEventsTokenEncrypted);
        s.TikTokAdsTokenEncrypted = Secret(body.TikTokAdsToken, s.TikTokAdsTokenEncrypted);

        s.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return Ok(SettingsDto(s));
    }

    /// <summary>The Meta ad accounts the connected Facebook login can read, for the ad-account picker.</summary>
    [HttpGet("meta/ad-accounts")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> MetaAdAccounts(CancellationToken ct)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var s = await db.MarketingSettings.AsNoTracking().FirstOrDefaultAsync(x => x.TenantId == tenantId, ct);
        if (s?.MetaAdsTokenEncrypted == null)
            return Conflict(new { message = "Connect Facebook (Social accounts → Connect Facebook & Instagram) or paste an ads token first." });
        try
        {
            return Ok(await meta.GetAdAccountsAsync(protector.Unprotect(s.MetaAdsTokenEncrypted), ct));
        }
        catch (SocialApiException e)
        {
            return StatusCode(StatusCodes.Status502BadGateway, new { message = e.Message });
        }
    }

    /// <summary>Sends one clearly-marked test conversion, to prove the pixel and token work.</summary>
    [HttpPost("settings/test/{platform}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> SendTestEvent(string platform, CancellationToken ct)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var s = await db.MarketingSettings.AsNoTracking().FirstOrDefaultAsync(x => x.TenantId == tenantId, ct);
        var target = platform.ToLowerInvariant() switch
        {
            "meta" or "facebook" or "instagram" => SocialPlatform.Facebook,
            "tiktok" => SocialPlatform.TikTok,
            _ => null,
        };
        if (target == null) return BadRequest(new { message = "platform must be meta or tiktok." });
        if (s == null) return BadRequest(new { message = "Enter the pixel id and access token first." });

        // Without a test code the event would count as a real conversion
        // and train the ad algorithm on a fake customer.
        var testCode = target == SocialPlatform.Facebook ? s.MetaTestEventCode : s.TikTokTestEventCode;
        if (string.IsNullOrWhiteSpace(testCode))
            return BadRequest(new { message = "Add a test event code from Events Manager first, so the test does not count as a real booking." });
        if (!ConversionWorker.ConfiguredPlatforms(new MarketingSettings
            {
                ConversionTrackingEnabled = true,
                MetaPixelId = s.MetaPixelId, MetaCapiTokenEncrypted = s.MetaCapiTokenEncrypted,
                TikTokPixelCode = s.TikTokPixelCode, TikTokEventsTokenEncrypted = s.TikTokEventsTokenEncrypted,
            }).Contains(target))
            return BadRequest(new { message = "Enter the pixel id and access token first." });

        var now = DateTime.UtcNow;
        var fake = new ConversionEvent
        {
            TenantId = tenantId, BookingId = Guid.NewGuid(), Platform = target,
            EventName = ConversionEventName.BookingCreated, EventTime = now, Value = 1m, Currency = "LKR", IsTest = true,
        };
        var context = new ConversionContext(fake,
            new BookingAttribution { LandingUrl = "https://example.com/book?utm_source=test", UserAgent = Request.Headers.UserAgent.ToString(), ClientIp = HttpContext.Connection.RemoteIpAddress?.ToString() },
            "test@example.com", null, "Test Customer", Guid.NewGuid(), "Test booking", Guid.NewGuid(), 1);
        try
        {
            if (target == SocialPlatform.Facebook)
                await meta.SendConversionAsync(s.MetaPixelId!, protector.Unprotect(s.MetaCapiTokenEncrypted!), testCode, ConversionPayloads.Meta(context), ct);
            else
                await tikTok.SendEventAsync(s.TikTokPixelCode!, protector.Unprotect(s.TikTokEventsTokenEncrypted!), testCode, ConversionPayloads.TikTok(context), ct);
            return Ok(new { ok = true, message = $"Test event sent. It should appear under Test events in {(target == SocialPlatform.Facebook ? "Meta" : "TikTok")} Events Manager within a minute." });
        }
        catch (SocialApiException e)
        {
            return Ok(new { ok = false, message = e.Message });
        }
    }

    // ── Conversion event log ───────────────────────────────────────────────

    [HttpGet("events")]
    public async Task<IActionResult> Events([FromQuery] string? status, [FromQuery] string? platform, [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var q = db.ConversionEvents.AsNoTracking().Where(e => e.TenantId == tenantId);
        var since = DateTime.UtcNow.AddDays(-30);
        var summary = await q.Where(e => e.CreatedAt >= since)
            .GroupBy(e => new { e.Platform, e.Status })
            .Select(g => new { g.Key.Platform, g.Key.Status, Count = g.Count() })
            .ToListAsync();

        if (!string.IsNullOrWhiteSpace(status)) q = q.Where(e => e.Status == status);
        if (!string.IsNullOrWhiteSpace(platform)) q = q.Where(e => e.Platform == platform);

        var total = await q.CountAsync();
        var items = await q.OrderByDescending(e => e.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync();
        return Ok(new
        {
            summary,
            total, page, pageSize,
            items = items.Select(e => new
            {
                id = e.Id,
                bookingId = e.BookingId,
                platform = e.Platform,
                eventName = e.EventName,
                platformEventName = e.Platform == SocialPlatform.TikTok ? ConversionPayloads.TikTokEventName(e.EventName) : ConversionPayloads.MetaEventName(e.EventName),
                status = e.Status,
                eventTime = e.EventTime,
                value = e.Value,
                currency = e.Currency,
                attempts = e.Attempts,
                sentAt = e.SentAt,
                nextAttemptAt = e.NextAttemptAt,
                lastError = e.LastError,
                isTest = e.IsTest,
                createdAt = e.CreatedAt,
            }),
        });
    }

    [HttpPost("events/{id:guid}/retry")]
    public async Task<IActionResult> RetryEvent(Guid id)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var e = await db.ConversionEvents.FirstOrDefaultAsync(x => x.Id == id && x.TenantId == tenantId);
        if (e == null) return NotFound(new { message = "Event not found." });
        if (e.Status != ConversionEventStatus.Failed) return Conflict(new { message = "Only failed events can be retried." });
        if (DateTime.UtcNow - e.EventTime > ConversionWorker.MaxEventAge)
            return Conflict(new { message = "This event is older than 7 days and the platforms will no longer accept it." });

        e.Status = ConversionEventStatus.Pending;
        e.Attempts = 0;
        e.NextAttemptAt = null;
        e.LastError = null;
        e.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return NoContent();
    }

    // ── Reports ────────────────────────────────────────────────────────────

    [HttpGet("attribution")]
    public async Task<IActionResult> Attribution([FromQuery] DateTime? from, [FromQuery] DateTime? to, CancellationToken ct)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        if (Range(from, to) is not { } range) return BadRequest(new { message = $"Choose a range of at most {MaxReportDays} days with from before to." });
        return Ok(await analytics.GetAttributionAsync(tenantId, range.From, range.To, ct));
    }

    [HttpGet("campaigns")]
    public async Task<IActionResult> Campaigns([FromQuery] DateTime? from, [FromQuery] DateTime? to, CancellationToken ct)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        if (Range(from, to) is not { } range) return BadRequest(new { message = $"Choose a range of at most {MaxReportDays} days with from before to." });
        return Ok(await analytics.GetCampaignsAsync(tenantId, range.From, range.To, ct));
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    /// Defaults to the last 30 days, whole days in UTC, end exclusive.
    internal static (DateTime From, DateTime To)? Range(DateTime? from, DateTime? to)
    {
        var end = (to?.ToUniversalTime().Date ?? DateTime.UtcNow.Date).AddDays(1);
        var start = from?.ToUniversalTime().Date ?? end.AddDays(-30);
        if (start >= end || (end - start).TotalDays > MaxReportDays) return null;
        return (DateTime.SpecifyKind(start, DateTimeKind.Utc), DateTime.SpecifyKind(end, DateTimeKind.Utc));
    }

    private static string? Plain(string? incoming, string? current) =>
        incoming == null ? current : string.IsNullOrWhiteSpace(incoming) ? null : incoming.Trim();

    private string? Secret(string? incoming, string? current) =>
        incoming == null ? current : string.IsNullOrWhiteSpace(incoming) ? null : protector.Protect(incoming.Trim());

    private string? Hint(string? cipher)
    {
        if (cipher == null) return null;
        try { return Mask(protector.Unprotect(cipher)); }
        catch (Exception e) when (e is FormatException or System.Security.Cryptography.CryptographicException) { return "unreadable - enter it again"; }
    }

    private object SettingsDto(MarketingSettings s) => new
    {
        conversionTrackingEnabled = s.ConversionTrackingEnabled,
        metaPixelId = s.MetaPixelId,
        hasMetaCapiToken = s.MetaCapiTokenEncrypted != null,
        metaCapiTokenHint = Hint(s.MetaCapiTokenEncrypted),
        metaTestEventCode = s.MetaTestEventCode,
        metaAdAccountId = s.MetaAdAccountId,
        hasMetaAdsToken = s.MetaAdsTokenEncrypted != null,
        metaAdsTokenExpiresAt = s.MetaAdsTokenExpiresAt,
        tikTokPixelCode = s.TikTokPixelCode,
        hasTikTokEventsToken = s.TikTokEventsTokenEncrypted != null,
        tikTokEventsTokenHint = Hint(s.TikTokEventsTokenEncrypted),
        tikTokTestEventCode = s.TikTokTestEventCode,
        tikTokAdvertiserId = s.TikTokAdvertiserId,
        hasTikTokAdsToken = s.TikTokAdsTokenEncrypted != null,
        metaTrackingActive = ConversionWorker.ConfiguredPlatforms(s).Contains(SocialPlatform.Facebook),
        tikTokTrackingActive = ConversionWorker.ConfiguredPlatforms(s).Contains(SocialPlatform.TikTok),
    };
}
