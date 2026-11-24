using System.ComponentModel.DataAnnotations;

namespace SmeBackend.Models.Marketing;

public static class SocialMediaType
{
    public const string None = "None";
    public const string Image = "Image";
    public const string Video = "Video";

    public static readonly string[] All = { None, Image, Video };
}

public static class SocialPostStatus
{
    public const string Draft = "Draft";
    /// Waiting for its time, or for the worker's next tick.
    public const string Scheduled = "Scheduled";
    /// At least one target is still in flight.
    public const string Publishing = "Publishing";
    public const string Published = "Published";
    /// Some targets went out, some failed for good.
    public const string PartiallyPublished = "PartiallyPublished";
    public const string Failed = "Failed";
    public const string Cancelled = "Cancelled";
}

public static class SocialTargetStatus
{
    public const string Pending = "Pending";
    /// The provider accepted an upload container (Instagram) or publish id
    /// (TikTok) and is still processing the media; the worker polls it.
    public const string Processing = "Processing";
    public const string Published = "Published";
    /// Sandbox account: nothing was sent.
    public const string Simulated = "Simulated";
    public const string Failed = "Failed";
    public const string Cancelled = "Cancelled";

    public static bool IsTerminal(string status) =>
        status is Published or Simulated or Failed or Cancelled;
}

/// A piece of content written once and sent to one or more connected
/// accounts. Each destination is a <see cref="SocialPostTarget"/> with its
/// own status, because Facebook can accept a post that Instagram rejects.
public class SocialPost : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }

    /// Instagram and TikTok stop at 2,200 characters (checked per
    /// destination); a Facebook-only post may be longer.
    public const int MaxCaptionLength = 10000;

    [MaxLength(MaxCaptionLength)]
    public string Caption { get; set; } = string.Empty;

    /// None | Image | Video
    [MaxLength(10)]
    public string MediaType { get; set; } = SocialMediaType.None;

    /// Publicly reachable media URL. Instagram and TikTok fetch the file
    /// themselves, so it must be https and not behind a login.
    [MaxLength(2048)]
    public string? MediaUrl { get; set; }

    /// Optional link (normally the tracked booking link). Facebook renders it
    /// as a link card; Instagram/TikTok captions are not clickable, so it is
    /// appended to the caption text there.
    [MaxLength(2048)]
    public string? LinkUrl { get; set; }

    /// UTC. Null for "publish now".
    public DateTime? ScheduledAt { get; set; }

    [MaxLength(30)]
    public string Status { get; set; } = SocialPostStatus.Scheduled;

    public Guid? CreatedByUserId { get; set; }

    public List<SocialPostTarget> Targets { get; set; } = new();
}

public class SocialPostTarget : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }

    public Guid SocialPostId { get; set; }
    public SocialPost? Post { get; set; }

    public Guid SocialAccountId { get; set; }
    public SocialAccount? Account { get; set; }

    [MaxLength(20)]
    public string Status { get; set; } = SocialTargetStatus.Pending;

    /// Instagram media container id / TikTok publish_id while processing.
    [MaxLength(200)]
    public string? ProviderContainerId { get; set; }

    [MaxLength(200)]
    public string? ExternalPostId { get; set; }

    [MaxLength(2048)]
    public string? PermalinkUrl { get; set; }

    [MaxLength(1000)]
    public string? Error { get; set; }

    public int Attempts { get; set; }
    public DateTime? NextAttemptAt { get; set; }

    /// When the provider first said "processing". A container that is still
    /// not ready after SocialPublisher.ProcessingTimeout is given up on.
    public DateTime? ProcessingSince { get; set; }

    public DateTime? PublishedAt { get; set; }
}
