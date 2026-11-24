using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models.Marketing;
using SmeBackend.Shared;

namespace SmeBackend.Services.Marketing;

/// Sends scheduled social posts when they fall due and polls uploads the
/// providers are still processing. A post is never published from inside
/// the HTTP request that created it - even "publish now" goes through here -
/// so one slow TikTok upload cannot hold a browser tab open, and every
/// attempt is retried and recorded the same way.
///
/// Assumes a single API instance (the Render deployment). Each batch is
/// leased before any provider call, so a slow call is not picked up again
/// by the next tick; two instances could still race on the same row.
public sealed class SocialPublishingWorker(IServiceScopeFactory scopes, ILogger<SocialPublishingWorker> logger) : BackgroundService
{
    private static readonly TimeSpan Tick = TimeSpan.FromSeconds(20);
    private static readonly TimeSpan Lease = TimeSpan.FromMinutes(5);
    private const int BatchSize = 20;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Let startup migrations finish before the first query.
        try { await Task.Delay(TimeSpan.FromSeconds(15), stoppingToken); }
        catch (OperationCanceledException) { return; }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = scopes.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var publisher = scope.ServiceProvider.GetRequiredService<ISocialPublisher>();
                await RunOnceAsync(db, publisher, DateTime.UtcNow, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception e)
            {
                logger.LogError(e, "Social publishing tick failed");
            }

            try { await Task.Delay(Tick, stoppingToken); }
            catch (OperationCanceledException) { return; }
        }
    }

    public static async Task<int> RunOnceAsync(AppDbContext db, ISocialPublisher publisher, DateTime now, CancellationToken ct)
    {
        var due = await db.SocialPostTargets
            .IgnoreQueryFilters()
            .Include(t => t.Account)
            .Include(t => t.Post!).ThenInclude(p => p.Targets)
            .Where(t => (t.Status == SocialTargetStatus.Pending || t.Status == SocialTargetStatus.Processing)
                && (t.NextAttemptAt == null || t.NextAttemptAt <= now)
                && t.Post!.Status != SocialPostStatus.Draft
                && t.Post.Status != SocialPostStatus.Cancelled
                && (t.Post.ScheduledAt == null || t.Post.ScheduledAt <= now))
            .OrderBy(t => t.NextAttemptAt ?? t.Post!.ScheduledAt ?? t.CreatedAt)
            .Take(BatchSize)
            .ToListAsync(ct);
        if (due.Count == 0) return 0;

        foreach (var target in due) target.NextAttemptAt = now + Lease;
        await db.SaveChangesAsync(ct);

        foreach (var target in due)
        {
            var post = target.Post!;
            var before = post.Status;

            await publisher.ProcessAsync(target, post, target.Account!, now, ct);

            post.Status = SocialPostRules.Rollup(post);
            post.UpdatedAt = now;

            if (before != post.Status && post.Status is SocialPostStatus.Failed or SocialPostStatus.PartiallyPublished)
            {
                var failed = post.Targets.Where(t => t.Status == SocialTargetStatus.Failed).Select(t => t.Account?.Platform ?? "?").Distinct();
                NotificationHelper.Queue(db, post.TenantId, post.CreatedByUserId, "SocialPostFailed",
                    post.Status == SocialPostStatus.Failed ? "A social post failed" : "A social post partly failed",
                    $"\"{Preview(post.Caption)}\" could not be published to {string.Join(", ", failed)}. Open the publisher to see why.");
            }

            await db.SaveChangesAsync(ct);
        }
        return due.Count;
    }

    private static string Preview(string caption)
    {
        var s = caption.ReplaceLineEndings(" ").Trim();
        return s.Length <= 60 ? (s.Length == 0 ? "(media post)" : s) : s[..57] + "...";
    }
}
