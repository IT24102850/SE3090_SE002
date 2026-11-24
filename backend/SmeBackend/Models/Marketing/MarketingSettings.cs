using System.ComponentModel.DataAnnotations;

namespace SmeBackend.Models.Marketing;

/// One row per tenant: conversion tracking and ad-account credentials.
/// Every *Encrypted column is IPlatformSecretProtector ciphertext and is
/// never returned by the API - the settings screen sees "set / not set" and
/// a masked hint.
public class MarketingSettings : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }

    // ── Meta (Facebook + Instagram ads) ─────────────────────────────────
    [MaxLength(50)]
    public string? MetaPixelId { get; set; }

    /// Conversions API access token (Events Manager → Settings → Generate).
    public string? MetaCapiTokenEncrypted { get; set; }

    /// Events Manager "Test events" code. While set, every event is sent as a
    /// test event and does not count toward campaign optimisation.
    [MaxLength(50)]
    public string? MetaTestEventCode { get; set; }

    /// act_123... - the account whose spend the campaign report reads.
    [MaxLength(50)]
    public string? MetaAdAccountId { get; set; }

    /// User token with ads_read, from the Meta connect flow or pasted.
    public string? MetaAdsTokenEncrypted { get; set; }
    public DateTime? MetaAdsTokenExpiresAt { get; set; }

    // ── TikTok ──────────────────────────────────────────────────────────
    [MaxLength(50)]
    public string? TikTokPixelCode { get; set; }

    /// Events API access token (Events Manager → pixel → Settings).
    public string? TikTokEventsTokenEncrypted { get; set; }

    [MaxLength(50)]
    public string? TikTokTestEventCode { get; set; }

    [MaxLength(50)]
    public string? TikTokAdvertiserId { get; set; }

    /// TikTok Marketing API long-term access token.
    public string? TikTokAdsTokenEncrypted { get; set; }

    /// Master switch: when false nothing is queued for either platform.
    public bool ConversionTrackingEnabled { get; set; } = true;
}
