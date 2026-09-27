using System.Diagnostics;
using SmeBackend.DTOs;

namespace SmeBackend.Services.Billing;

/// A read-only picture of the tenant's billing data the agent reasons over.
/// Built by BillingAgentService from the database; built by hand in tests.
public sealed class BillingSnapshot
{
    public List<InvoiceFact> Invoices { get; init; } = new();
    /// Invoices from the equal-length period just before DataRange, for trends.
    public List<InvoiceFact> PreviousInvoices { get; init; } = new();
    public List<ClaimFact> Claims { get; init; } = new();
    public List<CommissionRuleFact> CommissionRules { get; init; } = new();
}

public sealed record InvoiceLineFact(string Description, string Category, int Quantity, decimal UnitPrice, decimal Amount);

public sealed record PaymentFact(decimal Amount, string Method, string Status, DateTime? PaidAt);

public sealed record InvoiceFact(
    Guid Id,
    string InvoiceNumber,
    Guid CustomerId,
    string Status,
    string Currency,
    decimal TotalAmount,
    decimal Discount,
    decimal Tax,
    decimal FinalAmount,
    DateTime CreatedAt,
    DateTime DueDate,
    IReadOnlyList<InvoiceLineFact> Lines,
    IReadOnlyList<PaymentFact> Payments)
{
    public decimal Collected => Payments.Where(p => p.Status == "Succeeded").Sum(p => p.Amount);
}

public sealed record ClaimFact(
    Guid Id,
    Guid InvoiceId,
    string InvoiceNumber,
    string Status,
    string Provider,
    string PolicyNumber,
    decimal ClaimAmount,
    decimal InvoiceFinalAmount,
    string InvoiceStatus,
    decimal OtherClaimsTotal,
    string? CustomerInsuranceProvider,
    string? CustomerInsuranceNumber);

public sealed record CommissionRuleFact(
    Guid Id,
    string Name,
    string? Role,
    string RuleType,
    decimal Rate,
    decimal? FixedAmount,
    decimal? MinAmount,
    decimal? MaxAmount);

public sealed class ToolNotAllowedException : Exception
{
    public ToolNotAllowedException(string tool)
        : base($"Tool '{tool}' is not on the billing agent's allow-list.") { }
}

public sealed record BillingAgentResult(
    IReadOnlyList<Anomaly> Anomalies,
    IReadOnlyList<Insight> Insights,
    IReadOnlyList<RecommendedAction> RecommendedActions,
    double ConfidenceScore,
    IReadOnlyList<AgentToolCall> ToolCalls);

/// Student 2's Domain Analysis Agent: monitor financial data -> detect
/// anomalies -> validate against business rules -> flag -> generate
/// insights -> recommend actions (high-value ones gated on approval).
///
/// Deterministic on purpose, like the booking planner: every flag it raises
/// can be traced to one rule and one piece of evidence, which is what an
/// auditor (and the golden-case tests) need. It only ever calls tools on
/// its allow-list, through one dispatcher.
public sealed class BillingDomainAnalysisAgent
{
    public const string QueryRevenueTrends = "query_revenue_trends";
    public const string DetectBillingAnomalies = "detect_billing_anomalies";
    public const string ValidateInsuranceClaim = "validate_insurance_claim";
    public const string ComparePricingBenchmarks = "compare_pricing_benchmarks";
    public const string CalculateCommissionSplit = "calculate_commission_split";

    public static readonly IReadOnlySet<string> AllowedTools = new HashSet<string>
    {
        QueryRevenueTrends,
        DetectBillingAnomalies,
        ValidateInsuranceClaim,
        ComparePricingBenchmarks,
        CalculateCommissionSplit,
    };

    private sealed class RunState
    {
        public required BillingSnapshot Snapshot { get; init; }
        public required ThresholdConfig Thresholds { get; init; }
        public required DateRangeDto Range { get; init; }
        public decimal? DealAmount { get; init; }
        public List<Anomaly> Anomalies { get; } = new();
        public List<Insight> Insights { get; } = new();
        public List<RecommendedAction> Actions { get; } = new();
        public List<(string Tool, double Confidence)> Confidences { get; } = new();
        public int Seq;
        public string NextId(string prefix) => $"{prefix}-{++Seq:D3}";
    }

    private readonly Dictionary<string, Func<RunState, (string Summary, int Examined)>> _tools;

    public BillingDomainAnalysisAgent()
    {
        _tools = new()
        {
            [QueryRevenueTrends] = RunRevenueTrends,
            [DetectBillingAnomalies] = RunAnomalyDetection,
            [ValidateInsuranceClaim] = RunClaimValidation,
            [ComparePricingBenchmarks] = RunPricingBenchmarks,
            [CalculateCommissionSplit] = RunCommissionSplit,
        };
    }

    /// Which tools an analysis type runs, in order.
    public static IReadOnlyList<string> PlanFor(string analysisType) => analysisType.ToLowerInvariant() switch
    {
        BillingAnalysisTypes.Anomalies => new[] { DetectBillingAnomalies },
        BillingAnalysisTypes.Revenue => new[] { QueryRevenueTrends },
        BillingAnalysisTypes.Insurance => new[] { ValidateInsuranceClaim },
        BillingAnalysisTypes.Pricing => new[] { ComparePricingBenchmarks },
        BillingAnalysisTypes.Commission => new[] { CalculateCommissionSplit },
        _ => new[] { QueryRevenueTrends, DetectBillingAnomalies, ValidateInsuranceClaim, ComparePricingBenchmarks },
    };

    public BillingAgentResult Run(
        string analysisType,
        DateRangeDto range,
        BillingSnapshot snapshot,
        ThresholdConfig? thresholds = null,
        decimal? dealAmount = null,
        IReadOnlyList<string>? toolsOverride = null)
    {
        var state = new RunState
        {
            Snapshot = snapshot,
            Thresholds = thresholds ?? ThresholdConfig.Default,
            Range = range,
            DealAmount = dealAmount,
        };

        var calls = new List<AgentToolCall>();
        foreach (var tool in toolsOverride ?? PlanFor(analysisType))
        {
            calls.Add(Invoke(tool, state));
        }

        var confidence = state.Confidences.Count == 0
            ? 0
            : Math.Round(state.Confidences.Average(c => c.Confidence), 2);

        return new BillingAgentResult(state.Anomalies, state.Insights, state.Actions, confidence, calls);
    }

    /// The single entry point for tool execution - nothing else can run one.
    private AgentToolCall Invoke(string tool, RunState state)
    {
        if (!AllowedTools.Contains(tool) || !_tools.TryGetValue(tool, out var run))
            throw new ToolNotAllowedException(tool);

        var watch = Stopwatch.StartNew();
        var (summary, examined) = run(state);
        return new AgentToolCall(tool, summary, examined, watch.ElapsedMilliseconds);
    }

    // ---------------------------------------------------------------
    // query_revenue_trends
    // ---------------------------------------------------------------
    private static (string, int) RunRevenueTrends(RunState s)
    {
        var current = s.Snapshot.Invoices.Where(i => !IsCancelled(i)).ToList();
        var previous = s.Snapshot.PreviousInvoices.Where(i => !IsCancelled(i)).ToList();

        var invoiced = current.Sum(i => i.FinalAmount);
        var collected = current.Sum(i => i.Collected);
        var prevInvoiced = previous.Sum(i => i.FinalAmount);
        var outstanding = current.Sum(i => Math.Max(0, i.FinalAmount - i.Collected));

        s.Insights.Add(new Insight("revenue", "Invoiced in period",
            $"{current.Count} invoices worth {invoiced:N2}, {collected:N2} collected.", BillingRules.Round(invoiced)));

        if (invoiced > 0)
        {
            var rate = BillingRules.Round(collected / invoiced * 100m);
            s.Insights.Add(new Insight("collection_rate", "Collection rate",
                $"{rate:0.#}% of the amount invoiced in this period has been collected.", rate));
        }

        if (outstanding > 0)
        {
            s.Insights.Add(new Insight("outstanding", "Outstanding balance",
                $"{outstanding:N2} is still owed on invoices from this period.", BillingRules.Round(outstanding)));
        }

        if (prevInvoiced > 0)
        {
            var change = BillingRules.Round((invoiced - prevInvoiced) / prevInvoiced * 100m);
            s.Insights.Add(new Insight("revenue_trend", "Change vs previous period",
                $"Invoiced revenue is {(change >= 0 ? "up" : "down")} {Math.Abs(change):0.#}% on the previous period ({prevInvoiced:N2}).", change));

            if (-change >= s.Thresholds.RevenueDropPercent)
            {
                s.Anomalies.Add(new Anomaly(s.NextId("ANM"), "revenue_drop", -change >= 70 ? "high" : "medium",
                    "Tenant", null, null,
                    $"Invoiced revenue fell {Math.Abs(change):0.#}% versus the previous period.",
                    BillingRules.Round(prevInvoiced - invoiced),
                    new Dictionary<string, object?>
                    {
                        ["currentPeriod"] = BillingRules.Round(invoiced),
                        ["previousPeriod"] = BillingRules.Round(prevInvoiced),
                        ["thresholdPercent"] = s.Thresholds.RevenueDropPercent,
                    }));
            }
        }

        // Trend confidence grows with the amount of history available.
        var dataPoints = current.Count + previous.Count;
        s.Confidences.Add((QueryRevenueTrends, dataPoints >= 20 ? 0.9 : dataPoints >= 5 ? 0.75 : 0.5));
        return ($"Compared {current.Count} invoices with {previous.Count} from the previous period.", dataPoints);
    }

    // ---------------------------------------------------------------
    // detect_billing_anomalies
    // ---------------------------------------------------------------
    private static (string, int) RunAnomalyDetection(RunState s)
    {
        var t = s.Thresholds;
        var invoices = s.Snapshot.Invoices.Where(i => !IsCancelled(i)).ToList();
        var before = s.Anomalies.Count;

        foreach (var inv in invoices)
        {
            var lines = inv.Lines.Select(l => new BillingRules.DraftLine(l.Quantity, l.UnitPrice)).ToList();
            var check = BillingRules.ValidateInvoice(lines, inv.Discount, inv.Tax, t);

            foreach (var issue in check.Issues)
            {
                switch (issue.Code)
                {
                    case "excessive_discount":
                    case "discount_exceeds_subtotal":
                    {
                        var allowed = BillingRules.Round(check.Subtotal * t.MaxDiscountPercent / 100m);
                        var excess = BillingRules.Round(inv.Discount - allowed);
                        s.Anomalies.Add(new Anomaly(s.NextId("ANM"), "excessive_discount",
                            check.DiscountPercent >= 75 ? "high" : "medium",
                            "Invoice", inv.Id, inv.InvoiceNumber, issue.Message, inv.Discount,
                            new Dictionary<string, object?>
                            {
                                ["subtotal"] = check.Subtotal,
                                ["discount"] = inv.Discount,
                                ["discountPercent"] = check.DiscountPercent,
                                ["capPercent"] = t.MaxDiscountPercent,
                            }));

                        // Only an unpaid invoice can still be corrected.
                        if (inv.Collected < inv.FinalAmount && excess > 0)
                        {
                            AddAction(s, "adjust_invoice", "Invoice", inv.Id,
                                $"Reduce the discount on {inv.InvoiceNumber} from {inv.Discount:N2} to the {t.MaxDiscountPercent:0.##}% cap ({allowed:N2}).",
                                excess,
                                BillingRules.AdjustmentRequiresApproval(excess, t)
                                    ? $"Changes the payable amount by {excess:N2}, above the {t.AdjustmentApprovalAmount:N2} approval threshold."
                                    : null,
                                new Dictionary<string, object?>
                                {
                                    ["discount"] = allowed,
                                    ["tax"] = inv.Tax,
                                    ["previousDiscount"] = inv.Discount,
                                    ["invoiceNumber"] = inv.InvoiceNumber,
                                });
                        }
                        else
                        {
                            AddAction(s, "review_invoice", "Invoice", inv.Id,
                                $"Review the discount granted on {inv.InvoiceNumber}; it is already paid and cannot be adjusted.",
                                inv.Discount, null, new Dictionary<string, object?> { ["invoiceNumber"] = inv.InvoiceNumber });
                        }
                        break;
                    }
                    case "tax_out_of_range":
                    case "missing_tax":
                        s.Anomalies.Add(new Anomaly(s.NextId("ANM"), "tax_out_of_range", "medium",
                            "Invoice", inv.Id, inv.InvoiceNumber, issue.Message, inv.Tax,
                            new Dictionary<string, object?>
                            {
                                ["taxPercent"] = check.TaxPercent,
                                ["minPercent"] = t.MinTaxPercent,
                                ["maxPercent"] = t.MaxTaxPercent,
                            }));
                        break;
                    case "high_value_invoice":
                        s.Anomalies.Add(new Anomaly(s.NextId("ANM"), "high_value_invoice", "low",
                            "Invoice", inv.Id, inv.InvoiceNumber, issue.Message, inv.FinalAmount,
                            new Dictionary<string, object?> { ["threshold"] = t.HighValueInvoiceAmount }));
                        break;
                }
            }

            // Stored totals must agree with their own lines - a mismatch means
            // the numbers were edited outside the billing service.
            var expectedFinal = Math.Max(0, BillingRules.Round(inv.TotalAmount - inv.Discount + inv.Tax));
            if (Math.Abs(check.Subtotal - inv.TotalAmount) > 0.01m || Math.Abs(expectedFinal - inv.FinalAmount) > 0.01m)
            {
                s.Anomalies.Add(new Anomaly(s.NextId("ANM"), "amount_mismatch", "critical",
                    "Invoice", inv.Id, inv.InvoiceNumber,
                    $"{inv.InvoiceNumber}'s stored totals do not match its line items.",
                    inv.FinalAmount,
                    new Dictionary<string, object?>
                    {
                        ["lineSubtotal"] = check.Subtotal,
                        ["storedTotal"] = inv.TotalAmount,
                        ["expectedFinal"] = expectedFinal,
                        ["storedFinal"] = inv.FinalAmount,
                    }));
                AddAction(s, "review_invoice", "Invoice", inv.Id,
                    $"Investigate how {inv.InvoiceNumber}'s totals diverged from its items.", inv.FinalAmount, null,
                    new Dictionary<string, object?> { ["invoiceNumber"] = inv.InvoiceNumber });
            }

            if (inv.Collected > inv.FinalAmount + 0.01m)
            {
                var over = BillingRules.Round(inv.Collected - inv.FinalAmount);
                s.Anomalies.Add(new Anomaly(s.NextId("ANM"), "overpayment", "high",
                    "Invoice", inv.Id, inv.InvoiceNumber,
                    $"{inv.InvoiceNumber} has been paid {over:N2} more than it is worth.", over,
                    new Dictionary<string, object?> { ["collected"] = inv.Collected, ["finalAmount"] = inv.FinalAmount }));
            }

            if (inv.Collected < inv.FinalAmount && inv.DueDate < s.Range.To && !inv.Status.Equals("Paid", StringComparison.OrdinalIgnoreCase))
            {
                var balance = BillingRules.Round(inv.FinalAmount - inv.Collected);
                var daysOverdue = (int)(s.Range.To - inv.DueDate).TotalDays;
                if (daysOverdue >= 1)
                {
                    AddAction(s, "chase_payment", "Invoice", inv.Id,
                        $"Send a payment reminder for {inv.InvoiceNumber} ({balance:N2} overdue by {daysOverdue} days).",
                        balance, null,
                        new Dictionary<string, object?> { ["invoiceNumber"] = inv.InvoiceNumber, ["daysOverdue"] = daysOverdue });
                }
            }
        }

        // Duplicates: same customer, same payable amount, raised within the window.
        var window = TimeSpan.FromMinutes(s.Thresholds.DuplicateWindowMinutes);
        foreach (var group in invoices.GroupBy(i => (i.CustomerId, i.FinalAmount, i.Currency)))
        {
            var ordered = group.OrderBy(i => i.CreatedAt).ToList();
            for (var k = 1; k < ordered.Count; k++)
            {
                if (ordered[k].CreatedAt - ordered[k - 1].CreatedAt <= window)
                {
                    s.Anomalies.Add(new Anomaly(s.NextId("ANM"), "duplicate_invoice", "high",
                        "Invoice", ordered[k].Id, ordered[k].InvoiceNumber,
                        $"{ordered[k].InvoiceNumber} repeats {ordered[k - 1].InvoiceNumber} for the same customer and amount within {s.Thresholds.DuplicateWindowMinutes} minutes.",
                        ordered[k].FinalAmount,
                        new Dictionary<string, object?>
                        {
                            ["originalInvoice"] = ordered[k - 1].InvoiceNumber,
                            ["minutesApart"] = Math.Round((ordered[k].CreatedAt - ordered[k - 1].CreatedAt).TotalMinutes, 1),
                        }));
                    AddAction(s, "review_invoice", "Invoice", ordered[k].Id,
                        $"Confirm {ordered[k].InvoiceNumber} is not a duplicate of {ordered[k - 1].InvoiceNumber}; cancel it if it is.",
                        ordered[k].FinalAmount, null,
                        new Dictionary<string, object?> { ["invoiceNumber"] = ordered[k].InvoiceNumber });
                }
            }
        }

        var found = s.Anomalies.Count - before;
        s.Insights.Add(new Insight("anomalies", "Anomaly scan",
            found == 0 ? $"No billing anomalies in {invoices.Count} invoices." : $"{found} anomalies found across {invoices.Count} invoices.",
            found));

        // Rule checks are deterministic - high confidence regardless of volume.
        s.Confidences.Add((DetectBillingAnomalies, 0.95));
        return ($"Checked {invoices.Count} invoices against discount, tax, total, payment and duplicate rules; {found} anomalies.", invoices.Count);
    }

    // ---------------------------------------------------------------
    // validate_insurance_claim
    // ---------------------------------------------------------------
    private static (string, int) RunClaimValidation(RunState s)
    {
        var open = s.Snapshot.Claims
            .Where(c => c.Status is "Submitted" or "UnderReview" or "Pending")
            .ToList();
        var passed = 0;

        foreach (var claim in open)
        {
            var result = BillingRules.ValidateClaim(new BillingRules.ClaimContext(
                claim.ClaimAmount, claim.Provider, claim.PolicyNumber, claim.InvoiceFinalAmount,
                claim.InvoiceStatus, claim.OtherClaimsTotal, claim.CustomerInsuranceProvider,
                claim.CustomerInsuranceNumber), s.Thresholds);

            var approvalReason = result.RequiresApproval
                ? $"Claim of {claim.ClaimAmount:N2} is above the {s.Thresholds.ClaimApprovalAmount:N2} approval threshold."
                : null;

            if (result.IsValid)
            {
                passed++;
                AddAction(s, "approve_insurance_claim", "InsuranceClaim", claim.Id,
                    $"Approve the {claim.Provider} claim on {claim.InvoiceNumber} ({claim.ClaimAmount:N2}); it passes every policy rule.",
                    claim.ClaimAmount, approvalReason,
                    new Dictionary<string, object?> { ["invoiceNumber"] = claim.InvoiceNumber, ["warnings"] = result.Issues.Select(i => i.Message).ToList() });
            }
            else
            {
                var reasons = string.Join(" ", result.Issues.Where(i => i.Severity == "error").Select(i => i.Message));
                foreach (var issue in result.Issues.Where(i => i.Severity == "error"))
                {
                    s.Anomalies.Add(new Anomaly(s.NextId("ANM"),
                        issue.Code.StartsWith("claim") ? "claim_exceeds_invoice" : "claim_policy_mismatch",
                        "high", "InsuranceClaim", claim.Id, claim.InvoiceNumber, issue.Message, claim.ClaimAmount,
                        new Dictionary<string, object?> { ["rule"] = issue.Code, ["invoiceAmount"] = claim.InvoiceFinalAmount }));
                }
                AddAction(s, "reject_insurance_claim", "InsuranceClaim", claim.Id,
                    $"Reject the {claim.Provider} claim on {claim.InvoiceNumber}: {reasons}",
                    claim.ClaimAmount, null,
                    new Dictionary<string, object?> { ["invoiceNumber"] = claim.InvoiceNumber, ["reason"] = reasons });
            }
        }

        if (open.Count > 0)
        {
            s.Insights.Add(new Insight("claims", "Open insurance claims",
                $"{passed} of {open.Count} open claims pass every policy rule.", open.Count));
        }

        s.Confidences.Add((ValidateInsuranceClaim, 0.9));
        return ($"Validated {open.Count} open claims; {passed} passed, {open.Count - passed} failed.", open.Count);
    }

    // ---------------------------------------------------------------
    // compare_pricing_benchmarks
    // ---------------------------------------------------------------
    private static (string, int) RunPricingBenchmarks(RunState s)
    {
        var lines = s.Snapshot.Invoices
            .Where(i => !IsCancelled(i))
            .SelectMany(i => i.Lines.Select(l => (Invoice: i, Line: l)))
            .Where(x => x.Line.UnitPrice > 0)
            .ToList();

        var outliers = 0;
        var benchmarked = 0;
        foreach (var group in lines.GroupBy(x => Normalize(x.Line.Description)))
        {
            var prices = group.Select(x => x.Line.UnitPrice).OrderBy(p => p).ToList();
            if (prices.Count < 3) continue;
            benchmarked++;

            var median = Median(prices);
            foreach (var (invoice, line) in group)
            {
                var deviation = BillingRules.Round(Math.Abs(line.UnitPrice - median) / median * 100m);
                if (deviation <= s.Thresholds.PriceDeviationPercent) continue;

                outliers++;
                s.Anomalies.Add(new Anomaly(s.NextId("ANM"), "price_outlier", deviation >= 200 ? "high" : "medium",
                    "Invoice", invoice.Id, invoice.InvoiceNumber,
                    $"'{line.Description}' was charged {line.UnitPrice:N2} on {invoice.InvoiceNumber}, {deviation:0.#}% from the usual {median:N2}.",
                    line.UnitPrice,
                    new Dictionary<string, object?>
                    {
                        ["item"] = line.Description,
                        ["benchmarkMedian"] = median,
                        ["deviationPercent"] = deviation,
                        ["samples"] = prices.Count,
                    }));
                AddAction(s, "review_pricing", "Invoice", invoice.Id,
                    $"Check the price of '{line.Description}' on {invoice.InvoiceNumber}.", line.UnitPrice, null,
                    new Dictionary<string, object?> { ["invoiceNumber"] = invoice.InvoiceNumber, ["benchmarkMedian"] = median });
            }
        }

        s.Insights.Add(new Insight("pricing", "Pricing benchmarks",
            benchmarked == 0
                ? "Not enough repeat sales yet to benchmark prices (3+ sales of an item needed)."
                : $"{benchmarked} items benchmarked; {outliers} charges deviate by more than {s.Thresholds.PriceDeviationPercent:0.#}%.",
            outliers));

        // Statistical, and weaker with few samples per item.
        s.Confidences.Add((ComparePricingBenchmarks, benchmarked >= 5 ? 0.8 : benchmarked >= 1 ? 0.65 : 0.4));
        return ($"Benchmarked {benchmarked} items across {lines.Count} line items; {outliers} outliers.", lines.Count);
    }

    // ---------------------------------------------------------------
    // calculate_commission_split
    // ---------------------------------------------------------------
    private static (string, int) RunCommissionSplit(RunState s)
    {
        var deal = s.DealAmount ?? 0;
        var rules = s.Snapshot.CommissionRules;
        if (deal <= 0 || rules.Count == 0)
        {
            s.Insights.Add(new Insight("commission", "Commission split",
                deal <= 0 ? "No deal amount was given to split." : "No active commission rules are configured.", 0));
            s.Confidences.Add((CalculateCommissionSplit, 0.5));
            return ("Nothing to split.", rules.Count);
        }

        decimal total = 0;
        foreach (var rule in rules)
        {
            var (amount, clamped) = BillingRules.ApplyCommissionRule(deal, rule.RuleType, rule.Rate, rule.FixedAmount, rule.MinAmount, rule.MaxAmount);
            total += amount;
            s.Insights.Add(new Insight("commission_line", $"{rule.Name}{(rule.Role is null ? "" : $" ({rule.Role})")}",
                $"{(rule.RuleType == "Fixed" ? "Fixed" : $"{rule.Rate:0.##}%")} of {deal:N2} = {amount:N2}{(clamped ? " (clamped to rule limits)" : "")}.",
                amount));
        }

        if (total > deal)
        {
            s.Anomalies.Add(new Anomaly(s.NextId("ANM"), "commission_exceeds_deal", "critical", "Deal", null, null,
                $"Commissions ({total:N2}) add up to more than the deal itself ({deal:N2}).", total,
                new Dictionary<string, object?> { ["dealAmount"] = deal, ["totalCommission"] = total }));
        }

        s.Insights.Add(new Insight("commission", "Commission split",
            $"Total commission {total:N2}; {BillingRules.Round(deal - total):N2} remains with the business.", BillingRules.Round(total)));
        s.Confidences.Add((CalculateCommissionSplit, 1.0));
        return ($"Applied {rules.Count} commission rules to a deal of {deal:N2}.", rules.Count);
    }

    // ---------------------------------------------------------------
    private static void AddAction(RunState s, string type, string entityType, Guid? entityId, string description,
        decimal? amount, string? approvalReason, Dictionary<string, object?> parameters)
    {
        // One recommendation per action + entity: several rules can point at
        // the same fix.
        if (s.Actions.Any(a => a.ActionType == type && a.EntityId == entityId)) return;
        s.Actions.Add(new RecommendedAction(s.NextId("ACT"), type, entityType, entityId, description,
            amount.HasValue ? BillingRules.Round(amount.Value) : null,
            approvalReason is not null, approvalReason, parameters));
    }

    private static bool IsCancelled(InvoiceFact i) => i.Status.Equals("Cancelled", StringComparison.OrdinalIgnoreCase);

    private static string Normalize(string description) =>
        string.Join(' ', description.Trim().ToLowerInvariant().Split(' ', StringSplitOptions.RemoveEmptyEntries));

    private static decimal Median(IReadOnlyList<decimal> sorted)
    {
        var mid = sorted.Count / 2;
        return sorted.Count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2m : sorted[mid];
    }
}
