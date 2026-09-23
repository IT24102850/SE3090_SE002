using System.Globalization;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;

namespace SmeBackend.Services.Billing;

public interface IBillingReportService
{
    Task<DailyRevenueResponse> GetDailyRevenueAsync(Guid tenantId, DateTime date, Guid? branchId, CancellationToken ct = default);
    Task<OutstandingPaymentsResponse> GetOutstandingPaymentsAsync(Guid tenantId, int agingDays, Guid? branchId, CancellationToken ct = default);
    Task<BillingDashboardResponse> GetDashboardAsync(Guid tenantId, DateTime from, DateTime to, Guid? branchId, CancellationToken ct = default);
}

/// Revenue here means money that moved: Succeeded payments in, Refunded
/// payments out. Invoiced amounts are reported alongside, never mixed in.
public sealed class BillingReportService : IBillingReportService
{
    private readonly AppDbContext _db;

    public BillingReportService(AppDbContext db) => _db = db;

    public async Task<DailyRevenueResponse> GetDailyRevenueAsync(Guid tenantId, DateTime date, Guid? branchId, CancellationToken ct = default)
    {
        var day = DateTime.SpecifyKind(date.Date, DateTimeKind.Utc);
        var next = day.AddDays(1);

        var payments = await PaymentsQuery(tenantId, branchId)
            .Where(p => p.PaidAt >= day && p.PaidAt < next)
            .Select(p => new { p.Amount, p.Method, p.Status, PaidAt = p.PaidAt!.Value, p.Invoice!.Currency })
            .ToListAsync(ct);

        var invoices = await InvoicesQuery(tenantId, branchId)
            .Where(i => i.CreatedAt >= day && i.CreatedAt < next && i.Status != InvoiceStatuses.Cancelled)
            .Select(i => i.FinalAmount)
            .ToListAsync(ct);

        static decimal Signed(string status, decimal amount) => status == PaymentStatuses.Refunded ? -amount : amount;
        var succeeded = payments.Where(p => p.Status == PaymentStatuses.Succeeded).ToList();
        var total = payments.Sum(p => Signed(p.Status, p.Amount));

        return new DailyRevenueResponse(
            day,
            branchId,
            BillingRules.Round(total),
            succeeded.Count,
            BillingRules.Round(invoices.Sum()),
            invoices.Count,
            succeeded.Count == 0 ? 0 : BillingRules.Round(succeeded.Average(p => p.Amount)),
            payments.GroupBy(p => p.Method)
                .Select(g => new AmountByLabel(g.Key, BillingRules.Round(g.Sum(p => Signed(p.Status, p.Amount))), g.Count()))
                .OrderByDescending(x => x.Amount).ToList(),
            Enumerable.Range(0, 24)
                .Select(h => new AmountByLabel($"{h:00}:00",
                    BillingRules.Round(payments.Where(p => p.PaidAt.Hour == h).Sum(p => Signed(p.Status, p.Amount))),
                    payments.Count(p => p.PaidAt.Hour == h)))
                .ToList(),
            payments.GroupBy(p => p.Currency)
                .Select(g => new AmountByLabel(g.Key, BillingRules.Round(g.Sum(p => Signed(p.Status, p.Amount))), g.Count()))
                .ToList());
    }

    public async Task<OutstandingPaymentsResponse> GetOutstandingPaymentsAsync(Guid tenantId, int agingDays, Guid? branchId, CancellationToken ct = default)
    {
        // agingDays = 0: every open invoice, due or not. Above 0: only those
        // at least that many days past their due date.
        agingDays = Math.Max(0, agingDays);
        var now = DateTime.UtcNow;
        var query = InvoicesQuery(tenantId, branchId)
            .Where(i => i.Status == InvoiceStatuses.Issued || i.Status == InvoiceStatuses.PartiallyPaid || i.Status == InvoiceStatuses.Overdue);
        if (agingDays > 0)
        {
            var cutoff = now.AddDays(-agingDays);
            query = query.Where(i => i.DueDate <= cutoff);
        }

        var open = await query
            .Select(i => new
            {
                i.Id, i.InvoiceNumber, i.CustomerId, i.DueDate, i.FinalAmount, i.Currency, i.Status,
                Paid = i.Payments.Where(p => p.Status == PaymentStatuses.Succeeded).Sum(p => (decimal?)p.Amount) ?? 0,
            })
            .ToListAsync(ct);

        var names = await NamesAsync(tenantId, open.Select(o => o.CustomerId), ct);
        var rows = open
            .Select(o => new OutstandingInvoiceRow(o.Id, o.InvoiceNumber, o.CustomerId,
                names.TryGetValue(o.CustomerId, out var n) ? n : null, o.DueDate,
                Math.Max(0, (int)Math.Floor((now - o.DueDate).TotalDays)), o.FinalAmount,
                BillingRules.Round(Math.Max(0, o.FinalAmount - o.Paid)), o.Currency,
                o.DueDate < now ? InvoiceStatuses.Overdue : o.Status))
            .Where(r => r.BalanceDue > 0)
            .OrderByDescending(r => r.DaysOverdue)
            .ToList();

        return new OutstandingPaymentsResponse(
            agingDays,
            BillingRules.Round(rows.Sum(r => r.BalanceDue)),
            rows.Count,
            AgingBuckets.Select(b =>
            {
                var inBucket = rows.Where(r => AgingBucketOf(r.DueDate, now) == b.Label).ToList();
                return new AgingBucket(b.Label, b.Min, b.Max, BillingRules.Round(inBucket.Sum(r => r.BalanceDue)), inBucket.Count);
            }).ToList(),
            rows);
    }

    private static readonly (string Label, int Min, int? Max)[] AgingBuckets =
    {
        ("Not yet due", 0, 0),
        ("1-30 days", 1, 30),
        ("31-60 days", 31, 60),
        ("61-90 days", 61, 90),
        ("90+ days", 91, null),
    };

    /// Anything past its due date, even by an hour, is in "1-30 days".
    public static string AgingBucketOf(DateTime dueDate, DateTime now)
    {
        if (dueDate >= now) return "Not yet due";
        var days = (now - dueDate).TotalDays;
        return days <= 30 ? "1-30 days" : days <= 60 ? "31-60 days" : days <= 90 ? "61-90 days" : "90+ days";
    }

    public async Task<BillingDashboardResponse> GetDashboardAsync(Guid tenantId, DateTime from, DateTime to, Guid? branchId, CancellationToken ct = default)
    {
        var start = DateTime.SpecifyKind(from.Date, DateTimeKind.Utc);
        var end = DateTime.SpecifyKind(to.Date, DateTimeKind.Utc).AddDays(1);
        if (end <= start) end = start.AddDays(1);
        if ((end - start).TotalDays > 366) start = end.AddDays(-366);
        var now = DateTime.UtcNow;

        var invoices = await InvoicesQuery(tenantId, branchId)
            .Where(i => i.CreatedAt >= start && i.CreatedAt < end)
            .Select(i => new
            {
                i.CreatedAt, i.FinalAmount, i.Status, i.Currency, i.DueDate,
                Paid = i.Payments.Where(p => p.Status == PaymentStatuses.Succeeded).Sum(p => (decimal?)p.Amount) ?? 0,
            })
            .ToListAsync(ct);

        var payments = await PaymentsQuery(tenantId, branchId)
            .Where(p => p.PaidAt >= start && p.PaidAt < end)
            .Select(p => new { p.Amount, p.Method, p.Status, PaidAt = p.PaidAt!.Value })
            .ToListAsync(ct);

        // Outstanding and overdue are as of now, across every open invoice.
        var open = await InvoicesQuery(tenantId, branchId)
            .Where(i => i.Status == InvoiceStatuses.Issued || i.Status == InvoiceStatuses.PartiallyPaid || i.Status == InvoiceStatuses.Overdue)
            .Select(i => new
            {
                i.DueDate, i.FinalAmount,
                Paid = i.Payments.Where(p => p.Status == PaymentStatuses.Succeeded).Sum(p => (decimal?)p.Amount) ?? 0,
            })
            .ToListAsync(ct);

        var subs = await _db.Subscriptions.IgnoreQueryFilters().AsNoTracking()
            .Where(s => s.TenantId == tenantId && s.Status == SubscriptionStatuses.Active)
            .Where(s => branchId == null || s.BranchId == branchId)
            .Select(s => new { s.Amount, s.BillingCycle })
            .ToListAsync(ct);

        var claims = await _db.InsuranceClaims.AsNoTracking()
            .Where(c => c.Invoice != null && c.Invoice.TenantId == tenantId && (c.Status == "Submitted" || c.Status == "UnderReview"))
            .Select(c => c.ClaimAmount)
            .ToListAsync(ct);

        var pendingApprovals = await _db.AgentWorkflows.AsNoTracking()
            .CountAsync(w => w.TenantId == tenantId && w.ApprovalStatus == "Pending" && w.Objective.StartsWith(BillingWorkflowPlan.ObjectivePrefix), ct);

        var currency = invoices.GroupBy(i => i.Currency).OrderByDescending(g => g.Count()).Select(g => g.Key).FirstOrDefault() ?? "LKR";
        static decimal Signed(string status, decimal amount) => status == PaymentStatuses.Refunded ? -amount : amount;

        // Daily points for ranges up to ~3 months, weekly beyond that.
        var weekly = (end - start).TotalDays > 92;
        string Bucket(DateTime d) => weekly
            ? ISOWeek.GetYear(d) + "-W" + ISOWeek.GetWeekOfYear(d).ToString("00")
            : d.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

        var series = new List<RevenuePoint>();
        for (var d = start; d < end; d = d.AddDays(weekly ? 7 : 1))
        {
            var key = Bucket(d);
            if (series.Any(p => p.Date == key)) continue;
            series.Add(new RevenuePoint(key,
                BillingRules.Round(invoices.Where(i => Bucket(i.CreatedAt) == key && i.Status != InvoiceStatuses.Cancelled).Sum(i => i.FinalAmount)),
                BillingRules.Round(payments.Where(p => Bucket(p.PaidAt) == key).Sum(p => Signed(p.Status, p.Amount)))));
        }

        string Effective(string status, DateTime due, decimal final, decimal paid) =>
            status is InvoiceStatuses.Issued or InvoiceStatuses.PartiallyPaid && due < now && paid < final ? InvoiceStatuses.Overdue : status;

        var statusBreakdown = invoices
            .GroupBy(i => Effective(i.Status, i.DueDate, i.FinalAmount, i.Paid))
            .Select(g => new AmountByLabel(g.Key, BillingRules.Round(g.Sum(i => i.FinalAmount)), g.Count()))
            .OrderByDescending(x => x.Count)
            .ToList();

        var overdue = open.Where(o => o.DueDate < now && o.Paid < o.FinalAmount).ToList();

        return new BillingDashboardResponse(
            start,
            end.AddDays(-1),
            currency,
            BillingRules.Round(invoices.Where(i => i.Status != InvoiceStatuses.Cancelled).Sum(i => i.FinalAmount)),
            BillingRules.Round(payments.Sum(p => Signed(p.Status, p.Amount))),
            BillingRules.Round(open.Sum(o => Math.Max(0, o.FinalAmount - o.Paid))),
            BillingRules.Round(overdue.Sum(o => o.FinalAmount - o.Paid)),
            overdue.Count,
            subs.Count,
            BillingRules.Round(subs.Sum(s => MonthlyValue(s.Amount, s.BillingCycle))),
            claims.Count,
            BillingRules.Round(claims.Sum()),
            pendingApprovals,
            series,
            statusBreakdown,
            payments.Where(p => p.Status == PaymentStatuses.Succeeded)
                .GroupBy(p => p.Method)
                .Select(g => new AmountByLabel(g.Key, BillingRules.Round(g.Sum(p => p.Amount)), g.Count()))
                .OrderByDescending(x => x.Amount)
                .ToList());
    }

    /// Normalises a plan's price to a monthly figure for MRR.
    public static decimal MonthlyValue(decimal amount, string cycle) => cycle.Trim().ToLowerInvariant() switch
    {
        "weekly" => amount * 52m / 12m,
        "monthly" => amount,
        "quarterly" => amount / 3m,
        "yearly" or "annual" or "annually" => amount / 12m,
        _ => 0m, // one-off passes are not recurring revenue
    };

    private IQueryable<Invoice> InvoicesQuery(Guid tenantId, Guid? branchId) =>
        _db.Invoices.AsNoTracking().Where(i => i.TenantId == tenantId && (branchId == null || i.BranchId == branchId));

    private IQueryable<Payment> PaymentsQuery(Guid tenantId, Guid? branchId) =>
        _db.Payments.AsNoTracking()
            .Where(p => p.Invoice != null && p.Invoice.TenantId == tenantId && (branchId == null || p.Invoice.BranchId == branchId))
            .Where(p => p.PaidAt != null && (p.Status == PaymentStatuses.Succeeded || p.Status == PaymentStatuses.Refunded));

    private async Task<Dictionary<Guid, string>> NamesAsync(Guid tenantId, IEnumerable<Guid> ids, CancellationToken ct)
    {
        var set = ids.Distinct().ToList();
        return await _db.Users.IgnoreQueryFilters().AsNoTracking()
            .Where(u => u.TenantId == tenantId && set.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.FullName, ct);
    }
}
