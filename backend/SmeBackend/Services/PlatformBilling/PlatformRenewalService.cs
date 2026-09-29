using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Services.PlatformBilling;

/// The clock behind the subscription: trials that end, terms that renew,
/// renewals nobody paid, and the grace window between a failed renewal and
/// the drop back to Starter.
///
/// Nothing here suspends a tenant. A business that stops paying loses the
/// paid features and keeps every row of its data, because the cheapest
/// customer to win is the one who never had to leave. That is the same reason
/// the free tier is a real product rather than a locked screen.
public sealed class PlatformRenewalService : BackgroundService
{
    /// Long enough that this is not a busy loop, short enough that a trial
    /// ending at 2am is handled before the owner opens the app.
    private static readonly TimeSpan Interval = TimeSpan.FromHours(1);

    /// How long a tenant keeps everything after a renewal goes unpaid. Two
    /// weeks is long enough to survive a holiday and an expired card.
    public static readonly TimeSpan GracePeriod = TimeSpan.FromDays(14);

    /// How far ahead a renewal bill is raised, so it is sitting in the app
    /// before the term actually lapses.
    public static readonly TimeSpan RenewalLead = TimeSpan.FromDays(3);

    private readonly IServiceScopeFactory _scopes;
    private readonly ILogger<PlatformRenewalService> _logger;

    public PlatformRenewalService(IServiceScopeFactory scopes, ILogger<PlatformRenewalService> logger)
    {
        _scopes = scopes;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Let the app finish starting - migrations and the catalogue sync run
        // on the same startup path this depends on.
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
        }
        catch (OperationCanceledException)
        {
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await RunOnceAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                // A bad row must not take the loop down; the next pass retries.
                _logger.LogError(ex, "Platform subscription sweep failed.");
            }

            try
            {
                await Task.Delay(Interval, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }

    public async Task RunOnceAsync(CancellationToken ct)
    {
        using var scope = _scopes.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var subscriptions = scope.ServiceProvider.GetRequiredService<IPlatformSubscriptionService>();
        var checkout = scope.ServiceProvider.GetRequiredService<IPlatformCheckoutService>();
        var entitlements = scope.ServiceProvider.GetRequiredService<IEntitlementService>();

        var now = DateTime.UtcNow;

        // Only paid subscriptions have a clock. Starter has no period end and
        // is skipped by the same condition.
        var due = await db.PlatformSubscriptions
            .Where(s => s.Tier > 0 && s.CurrentPeriodEnd != null
                        && s.CurrentPeriodEnd <= now.Add(RenewalLead))
            .ToListAsync(ct);

        foreach (var subscription in due)
        {
            var end = subscription.CurrentPeriodEnd!.Value;

            // ── A trial running out ─────────────────────────────────────
            if (subscription.Status == PlatformSubscriptionStatuses.Trialing)
            {
                if (end > now)
                {
                    await NudgeTrialAsync(db, subscription, end, now, ct);
                    continue;
                }

                await ((PlatformSubscriptionService)subscriptions)
                    .DropToStarterAsync(subscription, "trial.expire", null, ct);
                continue;
            }

            // ── A term the tenant asked to be their last ────────────────
            if (subscription.CancelAtPeriodEnd || !subscription.AutoRenew)
            {
                if (end <= now)
                    await ((PlatformSubscriptionService)subscriptions)
                        .DropToStarterAsync(subscription, "expire", null, ct);
                continue;
            }

            // ── A comped account renews itself, free ────────────────────
            if (subscription.IsComplimentary)
            {
                if (end <= now)
                {
                    subscription.CurrentPeriodStart = end;
                    subscription.CurrentPeriodEnd = end.AddMonths(BillingPeriods.Months(subscription.Period));
                    subscription.UpdatedAt = now;
                    db.PlatformSubscriptionEvents.Add(new PlatformSubscriptionEvent
                    {
                        TenantId = subscription.TenantId,
                        SubscriptionId = subscription.Id,
                        EventType = "renew",
                        ToPlanCode = subscription.PlanCode,
                        Amount = 0m,
                        Detail = "complimentary",
                    });
                    await db.SaveChangesAsync(ct);
                    entitlements.Invalidate(subscription.TenantId);
                }
                continue;
            }

            // ── A renewal that needs paying ─────────────────────────────
            var invoice = await checkout.RaiseRenewalInvoiceAsync(subscription, ct);
            if (invoice is null) continue;

            if (invoice.Status == PlatformInvoiceStatuses.Paid)
            {
                // The tenant paid the bill between two sweeps; the checkout
                // service already applied the term.
                continue;
            }

            if (end > now) continue; // billed ahead of time, still inside the paid term

            if (subscription.Status != PlatformSubscriptionStatuses.PastDue)
            {
                subscription.Status = PlatformSubscriptionStatuses.PastDue;
                subscription.GraceEndsAt = now.Add(GracePeriod);
                subscription.FailedRenewalAttempts++;
                subscription.UpdatedAt = now;

                db.PlatformSubscriptionEvents.Add(new PlatformSubscriptionEvent
                {
                    TenantId = subscription.TenantId,
                    SubscriptionId = subscription.Id,
                    EventType = "renew.failed",
                    FromPlanCode = subscription.PlanCode,
                    Currency = subscription.Currency,
                    Amount = subscription.Amount,
                    Detail = $"invoice:{invoice.Id}",
                });

                NotificationHelper.Queue(db, subscription.TenantId, null, "PlatformSubscriptionPastDue",
                    "Your Unify renewal is unpaid",
                    $"Nothing has switched off. {invoice.Number} is still open - pay it before {subscription.GraceEndsAt:d MMM yyyy} and your {subscription.PlanCode} plan carries on as normal.");

                await db.SaveChangesAsync(ct);
                entitlements.Invalidate(subscription.TenantId);
                continue;
            }

            if (subscription.GraceEndsAt is { } grace && grace <= now)
            {
                await ((PlatformSubscriptionService)subscriptions)
                    .DropToStarterAsync(subscription, "expire", null, ct);
            }
        }

    }

    /// One nudge at three days out and one on the last day. Any more than
    /// that and it reads as pressure rather than a reminder.
    private static async Task NudgeTrialAsync(AppDbContext db, PlatformSubscription subscription, DateTime end, DateTime now, CancellationToken ct)
    {
        var daysLeft = (int)Math.Ceiling((end - now).TotalDays);
        if (daysLeft is not (3 or 1)) return;

        var alreadySent = await db.Notifications.IgnoreQueryFilters().AnyAsync(n =>
            n.TenantId == subscription.TenantId
            && n.Type == "TrialEnding"
            && n.CreatedAt >= now.AddHours(-23), ct);
        if (alreadySent) return;

        NotificationHelper.Queue(db, subscription.TenantId, null, "TrialEnding",
            daysLeft == 1 ? "Your trial ends tomorrow" : $"Your trial ends in {daysLeft} days",
            $"Your {subscription.PlanCode} trial ends on {end:d MMM yyyy}. Pick a plan to keep the copilots, the extra branches and everything else switched on.");
        await db.SaveChangesAsync(ct);
    }

}
