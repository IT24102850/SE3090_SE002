using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Services.Billing;

public sealed record AutomationRunResult(int MarkedOverdue, int Renewed, int Expired, int RemindersSent);

/// The recurring billing engine: on a timer it
///   1. marks invoices past their due date Overdue,
///   2. renews auto-renew subscriptions whose period has ended (raising the
///      next period's invoice) and expires the ones that do not renew,
///   3. chases overdue invoices by email, at most once every few days.
public sealed class BillingAutomationService : BackgroundService
{
    public static readonly TimeSpan Interval = TimeSpan.FromHours(1);
    public static readonly TimeSpan ReminderSpacing = TimeSpan.FromDays(3);
    private const int BatchSize = 200;

    private readonly IServiceScopeFactory _scopes;
    private readonly ILogger<BillingAutomationService> _logger;

    public BillingAutomationService(IServiceScopeFactory scopes, ILogger<BillingAutomationService> logger)
    {
        _scopes = scopes;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Let the app finish starting (and migrating) first.
        try { await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken); }
        catch (TaskCanceledException) { return; }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = _scopes.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var messenger = scope.ServiceProvider.GetRequiredService<IBillingMessenger>();
                var result = await RunOnceAsync(db, messenger, DateTime.UtcNow, stoppingToken);
                if (result != new AutomationRunResult(0, 0, 0, 0))
                    _logger.LogInformation("Billing automation: {Result}", result);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "Billing automation run failed");
            }

            try { await Task.Delay(Interval, stoppingToken); }
            catch (TaskCanceledException) { return; }
        }
    }

    public static async Task<AutomationRunResult> RunOnceAsync(AppDbContext db, IBillingMessenger messenger, DateTime now, CancellationToken ct = default)
    {
        // 1. Overdue
        var overdue = await db.Invoices
            .Where(i => (i.Status == InvoiceStatuses.Issued || i.Status == InvoiceStatuses.PartiallyPaid) && i.DueDate < now)
            .Take(BatchSize * 5)
            .ToListAsync(ct);
        foreach (var invoice in overdue)
        {
            invoice.Status = InvoiceStatuses.Overdue;
            invoice.UpdatedAt = now;
        }
        await db.SaveChangesAsync(ct);

        // 2. Renewals and expiries
        var due = await db.Subscriptions.IgnoreQueryFilters()
            .Where(s => s.Status == SubscriptionStatuses.Active && (s.NextBillingAt ?? s.EndDate) <= now)
            .Take(BatchSize)
            .ToListAsync(ct);

        int renewed = 0, expired = 0;
        foreach (var sub in due)
        {
            if (!sub.AutoRenew || sub.BillingCycle.Equals("OneOff", StringComparison.OrdinalIgnoreCase))
            {
                sub.Status = SubscriptionStatuses.Expired;
                sub.NextBillingAt = null;
                sub.UpdatedAt = now;
                expired++;
                continue;
            }

            // Catch up at most one period per run: a server that was down for
            // a month raises one invoice now and the next on the following run.
            var periodStart = sub.EndDate;
            var periodEnd = NextPeriodEnd(periodStart, sub.BillingCycle);
            var currency = await db.Invoices
                .Where(i => i.TenantId == sub.TenantId && i.SubscriptionId == sub.Id)
                .OrderByDescending(i => i.CreatedAt).Select(i => i.Currency).FirstOrDefaultAsync(ct) ?? "LKR";

            if (sub.Amount > 0)
            {
                db.Invoices.Add(new Invoice
                {
                    TenantId = sub.TenantId,
                    BranchId = sub.BranchId,
                    CustomerId = sub.CustomerId,
                    SubscriptionId = sub.Id,
                    InvoiceNumber = BillingService.NewInvoiceNumber(),
                    TotalAmount = sub.Amount,
                    FinalAmount = sub.Amount,
                    Status = InvoiceStatuses.Issued,
                    DueDate = periodStart.AddDays(7),
                    Currency = currency,
                    Notes = "Raised automatically by the renewal engine.",
                    Items = new List<InvoiceItem>
                    {
                        new()
                        {
                            Description = $"{sub.PlanName} renewal ({periodStart:dd MMM} - {periodEnd:dd MMM yyyy})",
                            Quantity = 1,
                            UnitPrice = sub.Amount,
                            Amount = sub.Amount,
                            Category = "Membership",
                        },
                    },
                });
                sub.PaymentStatus = "Pending";
            }

            sub.StartDate = periodStart;
            sub.EndDate = periodEnd;
            sub.NextBillingAt = periodEnd;
            sub.UpdatedAt = now;
            renewed++;

            NotificationHelper.Queue(db, sub.TenantId, sub.CustomerId, "SubscriptionRenewed", "Membership renewed",
                $"Your {sub.PlanName} membership renewed until {periodEnd:dd MMM yyyy}." +
                (sub.Amount > 0 ? $" An invoice for {currency} {sub.Amount:N2} is ready." : ""));
        }
        await db.SaveChangesAsync(ct);

        // 3. Reminders for overdue invoices, spaced out.
        var remindBefore = now - ReminderSpacing;
        var toRemind = await db.Invoices
            .Where(i => i.Status == InvoiceStatuses.Overdue && (i.LastReminderAt == null || i.LastReminderAt < remindBefore))
            .OrderBy(i => i.DueDate)
            .Take(BatchSize)
            .ToListAsync(ct);

        var customerIds = toRemind.Select(i => i.CustomerId).Distinct().ToList();
        var emails = await db.Users.IgnoreQueryFilters().AsNoTracking()
            .Where(u => customerIds.Contains(u.Id))
            .Select(u => new { u.Id, u.Email })
            .ToDictionaryAsync(u => u.Id, u => u.Email, ct);

        var sent = 0;
        foreach (var invoice in toRemind)
        {
            invoice.LastReminderAt = now;
            NotificationHelper.Queue(db, invoice.TenantId, invoice.CustomerId, "PaymentReminder", "Payment overdue",
                $"Invoice {invoice.InvoiceNumber} ({invoice.Currency} {invoice.FinalAmount:N2}) was due on {invoice.DueDate:dd MMM yyyy}.");

            if (emails.TryGetValue(invoice.CustomerId, out var email) && !string.IsNullOrWhiteSpace(email))
            {
                var result = await messenger.SendEmailAsync(email, $"Payment reminder: {invoice.InvoiceNumber}",
                    $"<p>Invoice <b>{invoice.InvoiceNumber}</b> for {invoice.Currency} {invoice.FinalAmount:N2} was due on {invoice.DueDate:dd MMM yyyy}. " +
                    "You can pay it from the Unify app.</p>", null, ct);
                if (result.Delivered || result.Simulated) sent++;
            }
        }
        await db.SaveChangesAsync(ct);

        return new AutomationRunResult(overdue.Count, renewed, expired, sent);
    }

    public static DateTime NextPeriodEnd(DateTime start, string cycle) => cycle.Trim().ToLowerInvariant() switch
    {
        "weekly" => start.AddDays(7),
        "quarterly" => start.AddMonths(3),
        "yearly" => start.AddYears(1),
        _ => start.AddMonths(1),
    };
}
