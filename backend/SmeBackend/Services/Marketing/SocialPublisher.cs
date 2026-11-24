using SmeBackend.Models.Marketing;

namespace SmeBackend.Services.Marketing;

public interface ISocialPublisher
{
    /// Moves one destination one step forward: start the publish, poll a
    /// processing upload, or finish. Never throws for provider errors - the
    /// outcome is written onto the target (and the account, when its token
    /// is dead). The caller saves.
    Task ProcessAsync(SocialPostTarget target, SocialPost post, SocialAccount account, DateTime now, CancellationToken ct);
}

public sealed class SocialPublisher(
    IMetaGraphClient meta,
    ITikTokClient tikTok,
    ISocialTokenService tokens,
    ILogger<SocialPublisher> logger) : ISocialPublisher
{
    public const int MaxAttempts = 5;
    public static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(30);
    public static readonly TimeSpan ProcessingTimeout = TimeSpan.FromMinutes(30);

    /// 1, 5, 15, 60 minutes: quick enough for a blip, slow enough not to
    /// burn a rate limit that is already exhausted.
    private static readonly TimeSpan[] Backoff =
    {
        TimeSpan.FromMinutes(1), TimeSpan.FromMinutes(5), TimeSpan.FromMinutes(15), TimeSpan.FromMinutes(60),
    };

    public async Task ProcessAsync(SocialPostTarget target, SocialPost post, SocialAccount account, DateTime now, CancellationToken ct)
    {
        if (SocialTargetStatus.IsTerminal(target.Status)) return;
        target.UpdatedAt = now;

        if (account.Status == SocialAccountStatus.Disconnected)
        {
            Fail(target, "The account was disconnected before this post went out.");
            return;
        }

        if (account.IsSandbox)
        {
            target.Status = SocialTargetStatus.Simulated;
            target.ExternalPostId = "sandbox-" + target.Id.ToString("N")[..12];
            target.PermalinkUrl = null;
            target.PublishedAt = now;
            target.NextAttemptAt = null;
            target.Error = null;
            return;
        }

        var problem = SocialPostRules.Validate(account.Platform, post.Caption, post.MediaType, post.MediaUrl);
        if (problem != null)
        {
            Fail(target, problem);
            return;
        }

        if (target.Status == SocialTargetStatus.Processing && target.ProcessingSince is { } since && now - since > ProcessingTimeout)
        {
            Fail(target, $"{account.Platform} was still processing the media after {ProcessingTimeout.TotalMinutes:0} minutes. Try a smaller file.");
            return;
        }

        try
        {
            var token = await tokens.GetAccessTokenAsync(account, ct);
            var request = new PublishRequest(post.Caption, post.MediaType, post.MediaUrl, post.LinkUrl);
            var container = target.Status == SocialTargetStatus.Processing ? target.ProviderContainerId : null;

            var step = (account.Platform, container) switch
            {
                (SocialPlatform.Facebook, _) => await meta.PublishFacebookAsync(account.ExternalId, token, request, ct),
                (SocialPlatform.Instagram, null) => await meta.StartInstagramAsync(account.ExternalId, token, request, ct),
                (SocialPlatform.Instagram, { } c) => await meta.ContinueInstagramAsync(account.ExternalId, token, c, ct),
                (SocialPlatform.TikTok, null) => await tikTok.StartPublishAsync(token, request, account.DefaultPrivacy, ct),
                (SocialPlatform.TikTok, { } c) => await tikTok.ContinuePublishAsync(token, c, account.Handle, ct),
                _ => throw new SocialApiException($"Publishing to {account.Platform} is not supported."),
            };

            if (step.IsDone)
            {
                target.Status = SocialTargetStatus.Published;
                target.ExternalPostId = step.ExternalPostId;
                target.PermalinkUrl = step.PermalinkUrl;
                target.PublishedAt = now;
                target.NextAttemptAt = null;
                target.Error = null;
            }
            else
            {
                if (target.Status != SocialTargetStatus.Processing) target.ProcessingSince = now;
                target.Status = SocialTargetStatus.Processing;
                target.ProviderContainerId = step.ContainerId;
                target.NextAttemptAt = now + PollInterval;
                target.Error = null;
            }
        }
        catch (SocialApiException e) when (e.TokenInvalid)
        {
            tokens.MarkNeedsReconnect(account, e.Message);
            Fail(target, e.Message);
        }
        catch (SocialApiException e) when (e.Transient)
        {
            Retry(target, e.Message, now);
        }
        catch (SocialApiException e)
        {
            Fail(target, e.Message);
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            logger.LogError(e, "Unexpected error publishing social post target {TargetId}", target.Id);
            Retry(target, "Unexpected error: " + e.Message, now);
        }
    }

    private static void Retry(SocialPostTarget target, string error, DateTime now)
    {
        target.Attempts++;
        target.Error = SocialTokenService.Clip(error, 1000);
        if (target.Attempts >= MaxAttempts)
        {
            target.Status = SocialTargetStatus.Failed;
            target.NextAttemptAt = null;
            return;
        }
        // A processing upload keeps polling the same container; anything
        // else starts over.
        if (target.Status != SocialTargetStatus.Processing) target.Status = SocialTargetStatus.Pending;
        target.NextAttemptAt = now + Backoff[Math.Min(target.Attempts - 1, Backoff.Length - 1)];
    }

    private static void Fail(SocialPostTarget target, string error)
    {
        target.Status = SocialTargetStatus.Failed;
        target.Error = SocialTokenService.Clip(error, 1000);
        target.NextAttemptAt = null;
    }
}

/// Per-platform content rules, checked when a post is created (so the user
/// hears about it at once) and again before sending.
public static class SocialPostRules
{
    public const int FacebookMaxCaption = 63206;
    public const int InstagramMaxCaption = 2200;
    public const int TikTokMaxCaption = 2200;

    public static string? Validate(string platform, string caption, string mediaType, string? mediaUrl)
    {
        var hasMedia = mediaType is SocialMediaType.Image or SocialMediaType.Video;
        if (hasMedia && !IsPublicHttps(mediaUrl))
            return "The media must be a public https:// URL - the platform downloads it itself.";

        switch (platform)
        {
            case SocialPlatform.Facebook:
                if (!hasMedia && string.IsNullOrWhiteSpace(caption))
                    return "A Facebook post needs text or media.";
                if (caption.Length > FacebookMaxCaption)
                    return $"Facebook posts are limited to {FacebookMaxCaption} characters.";
                return null;
            case SocialPlatform.Instagram:
                if (!hasMedia) return "Instagram posts need an image or a video.";
                if (caption.Length > InstagramMaxCaption)
                    return $"Instagram captions are limited to {InstagramMaxCaption} characters.";
                if (CountHashtags(caption) > 30) return "Instagram allows at most 30 hashtags.";
                return null;
            case SocialPlatform.TikTok:
                if (!hasMedia) return "TikTok posts need a video or a photo.";
                if (caption.Length > TikTokMaxCaption)
                    return $"TikTok captions are limited to {TikTokMaxCaption} characters.";
                return null;
            default:
                return $"Unknown platform {platform}.";
        }
    }

    public static bool IsPublicHttps(string? url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var u)
        && u.Scheme == Uri.UriSchemeHttps
        && !u.IsLoopback
        && !string.Equals(u.Host, "localhost", StringComparison.OrdinalIgnoreCase);

    private static int CountHashtags(string caption) =>
        caption.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Count(w => w.StartsWith('#') && w.Length > 1);

    /// The post's overall status from its destinations'.
    public static string Rollup(SocialPost post)
    {
        if (post.Status is SocialPostStatus.Draft or SocialPostStatus.Cancelled) return post.Status;
        var targets = post.Targets;
        if (targets.Count == 0) return SocialPostStatus.Failed;

        if (targets.Any(t => !SocialTargetStatus.IsTerminal(t.Status)))
            return targets.Any(t => t.Attempts > 0 || t.Status == SocialTargetStatus.Processing || SocialTargetStatus.IsTerminal(t.Status))
                ? SocialPostStatus.Publishing
                : SocialPostStatus.Scheduled;

        var ok = targets.Count(t => t.Status is SocialTargetStatus.Published or SocialTargetStatus.Simulated);
        if (ok == targets.Count) return SocialPostStatus.Published;
        if (ok > 0) return SocialPostStatus.PartiallyPublished;
        return targets.All(t => t.Status == SocialTargetStatus.Cancelled) ? SocialPostStatus.Cancelled : SocialPostStatus.Failed;
    }
}
