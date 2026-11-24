using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models.Marketing;
using SmeBackend.Services.Marketing;

namespace SmeBackend.Controllers.Marketing;

/// Write once, publish to many. Creating a post only records it - the
/// SocialPublishingWorker sends it when it falls due, so "publish now" and
/// "publish next Friday" take the same path and get the same retries.
[ApiController]
[Route("api/social/posts")]
[Authorize(Roles = "Admin,Manager")]
public class SocialPostsController(AppDbContext db) : MarketingControllerBase
{
    private static readonly TimeSpan MaxScheduleAhead = TimeSpan.FromDays(180);

    public sealed class UpsertPostRequest
    {
        [MaxLength(SocialPost.MaxCaptionLength)]
        public string Caption { get; set; } = string.Empty;

        /// None | Image | Video
        public string MediaType { get; set; } = SocialMediaType.None;

        [MaxLength(2048)]
        public string? MediaUrl { get; set; }

        [MaxLength(2048)]
        public string? LinkUrl { get; set; }

        /// UTC. Null = as soon as possible.
        public DateTime? ScheduledAt { get; set; }

        [MinLength(1)]
        public List<Guid> AccountIds { get; set; } = new();

        /// Save without scheduling.
        public bool AsDraft { get; set; }
    }

    /// <summary>Posts, newest first, with each destination's status.</summary>
    [HttpGet]
    public async Task<IActionResult> List([FromQuery] string? status, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 25)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);

        var q = db.SocialPosts.AsNoTracking().Where(p => p.TenantId == tenantId);
        if (!string.IsNullOrWhiteSpace(status)) q = q.Where(p => p.Status == status);
        if (from.HasValue) q = q.Where(p => (p.ScheduledAt ?? p.CreatedAt) >= from.Value);
        if (to.HasValue) q = q.Where(p => (p.ScheduledAt ?? p.CreatedAt) < to.Value);

        var total = await q.CountAsync();
        var items = await q
            .OrderByDescending(p => p.ScheduledAt ?? p.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Include(p => p.Targets).ThenInclude(t => t.Account)
            .ToListAsync();

        return Ok(new { items = items.Select(ToDto), total, page, pageSize });
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var post = await Load(tenantId, id, tracking: false);
        return post == null ? NotFound(new { message = "Post not found." }) : Ok(ToDto(post));
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] UpsertPostRequest body)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var (accounts, error) = await Validate(tenantId, body);
        if (error != null) return BadRequest(new { message = error });

        var now = DateTime.UtcNow;
        var post = new SocialPost
        {
            TenantId = tenantId,
            CreatedByUserId = UserId,
        };
        Apply(post, body, accounts!, now);
        db.SocialPosts.Add(post);
        await db.SaveChangesAsync();

        post = await Load(tenantId, post.Id, tracking: false);
        return CreatedAtAction(nameof(Get), new { id = post!.Id }, ToDto(post));
    }

    /// <summary>Edits a post that has not started publishing yet.</summary>
    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpsertPostRequest body)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var post = await Load(tenantId, id, tracking: true);
        if (post == null) return NotFound(new { message = "Post not found." });
        if (!IsEditable(post))
            return Conflict(new { message = "This post has already started publishing and can no longer be edited. Duplicate it instead." });

        var (accounts, error) = await Validate(tenantId, body);
        if (error != null) return BadRequest(new { message = error });

        db.SocialPostTargets.RemoveRange(post.Targets);
        post.Targets.Clear();
        Apply(post, body, accounts!, DateTime.UtcNow);
        await db.SaveChangesAsync();

        post = await Load(tenantId, id, tracking: false);
        return Ok(ToDto(post!));
    }

    /// <summary>Stops every destination that has not gone out yet.</summary>
    [HttpPost("{id:guid}/cancel")]
    public async Task<IActionResult> Cancel(Guid id)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var post = await Load(tenantId, id, tracking: true);
        if (post == null) return NotFound(new { message = "Post not found." });

        var now = DateTime.UtcNow;
        var cancelled = 0;
        foreach (var t in post.Targets.Where(t => !SocialTargetStatus.IsTerminal(t.Status)))
        {
            // An upload the provider is already processing may still go
            // live; say so rather than pretend it was stopped.
            if (t.Status == SocialTargetStatus.Processing) continue;
            t.Status = SocialTargetStatus.Cancelled;
            t.NextAttemptAt = null;
            t.UpdatedAt = now;
            cancelled++;
        }
        if (cancelled == 0 && post.Status != SocialPostStatus.Draft)
            return Conflict(new { message = "Nothing left to cancel - every destination has already been sent or is being processed by the platform." });

        post.Status = post.Status == SocialPostStatus.Draft || post.Targets.All(t => t.Status == SocialTargetStatus.Cancelled)
            ? SocialPostStatus.Cancelled
            : SocialPostRules.Rollup(post);
        post.UpdatedAt = now;
        await db.SaveChangesAsync();
        return Ok(ToDto(post));
    }

    /// <summary>Tries the failed destinations again.</summary>
    [HttpPost("{id:guid}/retry")]
    public async Task<IActionResult> Retry(Guid id)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var post = await Load(tenantId, id, tracking: true);
        if (post == null) return NotFound(new { message = "Post not found." });

        var failed = post.Targets.Where(t => t.Status == SocialTargetStatus.Failed).ToList();
        if (failed.Count == 0) return Conflict(new { message = "No failed destinations to retry." });

        var blocked = failed.Where(t => t.Account?.Status != SocialAccountStatus.Connected).Select(t => t.Account?.DisplayName).ToList();
        if (blocked.Count > 0)
            return Conflict(new { message = $"Reconnect {string.Join(", ", blocked)} first - the platform rejected its login." });

        var now = DateTime.UtcNow;
        foreach (var t in failed)
        {
            t.Status = SocialTargetStatus.Pending;
            t.Attempts = 0;
            t.Error = null;
            t.ProviderContainerId = null;
            t.ProcessingSince = null;
            t.NextAttemptAt = null;
            t.UpdatedAt = now;
        }
        if (post.ScheduledAt > now) post.ScheduledAt = null;
        post.Status = SocialPostRules.Rollup(post);
        post.UpdatedAt = now;
        await db.SaveChangesAsync();
        return Ok(ToDto(post));
    }

    /// <summary>Removes a post from Unify. Already-published content stays on the platforms.</summary>
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var post = await Load(tenantId, id, tracking: true);
        if (post == null) return NotFound(new { message = "Post not found." });
        if (post.Targets.Any(t => t.Status == SocialTargetStatus.Processing))
            return Conflict(new { message = "A platform is still processing this post. Try again in a few minutes." });

        db.SocialPosts.Remove(post);
        await db.SaveChangesAsync();
        return NoContent();
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private async Task<SocialPost?> Load(Guid tenantId, Guid id, bool tracking)
    {
        var q = db.SocialPosts.Include(p => p.Targets).ThenInclude(t => t.Account).Where(p => p.Id == id && p.TenantId == tenantId);
        return await (tracking ? q : q.AsNoTracking()).FirstOrDefaultAsync();
    }

    private static bool IsEditable(SocialPost post) =>
        post.Status is SocialPostStatus.Draft or SocialPostStatus.Scheduled or SocialPostStatus.Cancelled
        && post.Targets.All(t => t.Status is SocialTargetStatus.Pending or SocialTargetStatus.Cancelled && t.Attempts == 0);

    private async Task<(List<SocialAccount>? Accounts, string? Error)> Validate(Guid tenantId, UpsertPostRequest body)
    {
        if (!SocialMediaType.All.Contains(body.MediaType))
            return (null, "mediaType must be None, Image or Video.");
        if (body.MediaType == SocialMediaType.None && !string.IsNullOrWhiteSpace(body.MediaUrl))
            return (null, "Choose Image or Video for the attached media.");
        if (body.MediaType != SocialMediaType.None && string.IsNullOrWhiteSpace(body.MediaUrl))
            return (null, "Add the image or video URL.");
        // Checked even for drafts: the URL is rendered back into <img>/<video>.
        if (!string.IsNullOrWhiteSpace(body.MediaUrl) && !SocialPostRules.IsPublicHttps(body.MediaUrl))
            return (null, "The media must be a public https:// URL.");
        if (!string.IsNullOrWhiteSpace(body.LinkUrl)
            && !(Uri.TryCreate(body.LinkUrl, UriKind.Absolute, out var link) && (link.Scheme == Uri.UriSchemeHttps || link.Scheme == Uri.UriSchemeHttp)))
            return (null, "The link must be a full http(s) URL.");

        var ids = body.AccountIds.Distinct().ToList();
        if (ids.Count == 0) return (null, "Choose at least one account to publish to.");
        if (ids.Count > 20) return (null, "A post can go to at most 20 accounts.");

        var accounts = await db.SocialAccounts
            .Where(a => a.TenantId == tenantId && ids.Contains(a.Id) && a.Status != SocialAccountStatus.Disconnected)
            .ToListAsync();
        if (accounts.Count != ids.Count) return (null, "One of the chosen accounts is not connected to this business.");

        if (!body.AsDraft)
        {
            var broken = accounts.Where(a => a.Status != SocialAccountStatus.Connected).Select(a => a.DisplayName).ToList();
            if (broken.Count > 0) return (null, $"Reconnect {string.Join(", ", broken)} before scheduling to it.");

            var now = DateTime.UtcNow;
            if (body.ScheduledAt is { } at)
            {
                var utc = DateTime.SpecifyKind(at, at.Kind == DateTimeKind.Unspecified ? DateTimeKind.Utc : at.Kind).ToUniversalTime();
                if (utc < now.AddMinutes(-1)) return (null, "The scheduled time is in the past.");
                if (utc > now + MaxScheduleAhead) return (null, "Posts can be scheduled at most 180 days ahead.");
            }

            foreach (var a in accounts)
            {
                // Sandbox accounts still get the rules: what fails here would
                // fail for real.
                var problem = SocialPostRules.Validate(a.Platform, body.Caption ?? "", body.MediaType, body.MediaUrl);
                if (problem != null) return (null, $"{a.Platform} ({a.DisplayName}): {problem}");
            }
        }
        return (accounts, null);
    }

    private static void Apply(SocialPost post, UpsertPostRequest body, List<SocialAccount> accounts, DateTime now)
    {
        post.Caption = (body.Caption ?? "").Trim();
        post.MediaType = body.MediaType;
        post.MediaUrl = string.IsNullOrWhiteSpace(body.MediaUrl) ? null : body.MediaUrl.Trim();
        post.LinkUrl = string.IsNullOrWhiteSpace(body.LinkUrl) ? null : body.LinkUrl.Trim();
        post.ScheduledAt = body.ScheduledAt is { } at
            ? DateTime.SpecifyKind(at, at.Kind == DateTimeKind.Unspecified ? DateTimeKind.Utc : at.Kind).ToUniversalTime()
            : null;
        post.Status = body.AsDraft ? SocialPostStatus.Draft : SocialPostStatus.Scheduled;
        post.UpdatedAt = now;

        foreach (var a in accounts)
            post.Targets.Add(new SocialPostTarget
            {
                TenantId = post.TenantId,
                SocialPostId = post.Id,
                SocialAccountId = a.Id,
                Status = SocialTargetStatus.Pending,
            });
    }

    internal static object ToDto(SocialPost p) => new
    {
        id = p.Id,
        caption = p.Caption,
        mediaType = p.MediaType,
        mediaUrl = p.MediaUrl,
        linkUrl = p.LinkUrl,
        scheduledAt = p.ScheduledAt,
        status = p.Status,
        createdAt = p.CreatedAt,
        updatedAt = p.UpdatedAt,
        editable = IsEditable(p),
        targets = p.Targets.OrderBy(t => t.Account?.Platform).Select(t => new
        {
            id = t.Id,
            accountId = t.SocialAccountId,
            platform = t.Account?.Platform,
            accountName = t.Account?.DisplayName,
            isSandbox = t.Account?.IsSandbox ?? false,
            status = t.Status,
            permalinkUrl = t.PermalinkUrl,
            error = t.Error,
            attempts = t.Attempts,
            publishedAt = t.PublishedAt,
            nextAttemptAt = t.NextAttemptAt,
        }),
    };
}
