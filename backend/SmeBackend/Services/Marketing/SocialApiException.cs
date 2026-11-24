namespace SmeBackend.Services.Marketing;

/// A provider said no. <see cref="TokenInvalid"/> means retrying is pointless
/// until the business reconnects the account; <see cref="Transient"/> means
/// retrying later may well work (rate limit, 5xx, timeout).
public sealed class SocialApiException : Exception
{
    public bool TokenInvalid { get; }
    public bool Transient { get; }
    public int? ProviderCode { get; }

    public SocialApiException(string message, bool transient = false, bool tokenInvalid = false, int? providerCode = null, Exception? inner = null)
        : base(message, inner)
    {
        Transient = transient;
        TokenInvalid = tokenInvalid;
        ProviderCode = providerCode;
    }
}

/// The outcome of one publishing step for one destination.
public sealed record PublishStep
{
    public bool IsDone { get; init; }
    public bool IsProcessing { get; init; }
    public string? ExternalPostId { get; init; }
    public string? PermalinkUrl { get; init; }
    public string? ContainerId { get; init; }

    public static PublishStep Done(string externalId, string? permalink) =>
        new() { IsDone = true, ExternalPostId = externalId, PermalinkUrl = permalink };

    public static PublishStep Processing(string containerId) =>
        new() { IsProcessing = true, ContainerId = containerId };
}

/// The bit of a post a provider needs, decoupled from the EF entity.
public sealed record PublishRequest(string Caption, string MediaType, string? MediaUrl, string? LinkUrl);
