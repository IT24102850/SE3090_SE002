using SmeBackend.DTOs;
using SmeBackend.Services.Billing;

namespace SmeBackend.Tests.Billing;

/// Agent evaluation (spec 3.9): golden cases the billing Domain Analysis
/// Agent must always get right, plus the approval thresholds and the tool
/// allow-list.
public class BillingAgentGoldenCaseTests
{
    private static readonly DateRangeDto Range = new(new DateTime(2026, 9, 1, 0, 0, 0, DateTimeKind.Utc), new DateTime(2026, 9, 30, 0, 0, 0, DateTimeKind.Utc));

    private static InvoiceFact Invoice(string number, decimal unitPrice, int qty = 1, decimal discount = 0, decimal tax = 0,
        Guid? customer = null, DateTime? created = null, string description = "Consultation", IReadOnlyList<PaymentFact>? payments = null,
        DateTime? due = null)
    {
        var subtotal = unitPrice * qty;
        return new InvoiceFact(Guid.NewGuid(), number, customer ?? Guid.NewGuid(), "Issued", "USD", subtotal, discount, tax,
            Math.Max(0, subtotal - discount + tax), created ?? Range.From.AddDays(2), due ?? Range.To.AddDays(10),
            new[] { new InvoiceLineFact(description, "General", qty, unitPrice, subtotal) },
            payments ?? Array.Empty<PaymentFact>());
    }

    // ------------------------------------------------------------------
    // Golden case 1: "Invoice with 50% discount on $10 item" MUST flag for review
    // ------------------------------------------------------------------

    [Fact]
    public void Golden_InvoiceWith50PercentDiscountOn10DollarItem_MustFlagForReview()
    {
        var result = BillingRules.ValidateInvoice(new[] { new BillingRules.DraftLine(1, 10m) }, discount: 5m, tax: 0m);

        Assert.True(result.RequiresReview, "A 50% discount must be flagged for review.");
        Assert.True(result.IsValid, "It is flagged, not rejected - the invoice itself is well-formed.");
        Assert.Equal(50m, result.DiscountPercent);
        Assert.Contains(result.Issues, i => i.Code == "excessive_discount" && i.Severity == "warning");
    }

    [Fact]
    public void Golden_AgentRun_On50PercentDiscountInvoice_RaisesAnomalyAndRecommendsAdjustment()
    {
        var snapshot = new BillingSnapshot { Invoices = { Invoice("INV-GOLD-1", 10m, discount: 5m) } };

        var result = new BillingDomainAnalysisAgent().Run(BillingAnalysisTypes.Anomalies, Range, snapshot);

        var anomaly = Assert.Single(result.Anomalies, a => a.Type == "excessive_discount");
        Assert.Equal("INV-GOLD-1", anomaly.EntityLabel);
        var action = Assert.Single(result.RecommendedActions, a => a.ActionType == "adjust_invoice");
        // Cap is 30% of $10 = $3, so the fix removes $2 of discount.
        Assert.Equal(2m, action.Amount);
        Assert.False(action.RequiresApproval, "A $2 correction is under the $100 approval threshold.");
    }

    // ------------------------------------------------------------------
    // Golden case 2: "Valid insurance claim" MUST pass
    // ------------------------------------------------------------------

    [Fact]
    public void Golden_ValidInsuranceClaim_MustPass()
    {
        var result = BillingRules.ValidateClaim(new BillingRules.ClaimContext(
            ClaimAmount: 250m, Provider: "Ceylinco", PolicyNumber: "CEY-2026-00417",
            InvoiceFinalAmount: 400m, InvoiceStatus: "Issued", OtherClaimsTotal: 0m,
            CustomerInsuranceProvider: "Ceylinco", CustomerInsuranceNumber: "CEY-2026-00417"));

        Assert.True(result.IsValid);
        Assert.Empty(result.Issues);
        Assert.False(result.RequiresApproval, "$250 is under the $500 claim threshold.");
    }

    [Fact]
    public void Golden_AgentRun_OnValidClaim_RecommendsApprovalWithNoAnomalies()
    {
        var claim = new ClaimFact(Guid.NewGuid(), Guid.NewGuid(), "INV-CLM-1", "Submitted", "AIA", "AIA-778812",
            300m, 450m, "Issued", 0m, "AIA", "AIA-778812");
        var result = new BillingDomainAnalysisAgent().Run(BillingAnalysisTypes.Insurance, Range, new BillingSnapshot { Claims = { claim } });

        Assert.Empty(result.Anomalies);
        var action = Assert.Single(result.RecommendedActions);
        Assert.Equal("approve_insurance_claim", action.ActionType);
        Assert.False(action.RequiresApproval);
    }

    // ------------------------------------------------------------------
    // Further business rules
    // ------------------------------------------------------------------

    [Fact]
    public void ClaimLargerThanInvoice_Fails()
    {
        var result = BillingRules.ValidateClaim(new BillingRules.ClaimContext(900m, "AIA", "AIA-1234", 400m, "Issued", 0m, null, null));
        Assert.False(result.IsValid);
        Assert.Contains(result.Issues, i => i.Code == "claim_exceeds_invoice");
    }

    [Fact]
    public void ClaimsTogetherExceedingInvoice_Fail()
    {
        var result = BillingRules.ValidateClaim(new BillingRules.ClaimContext(300m, "AIA", "AIA-1234", 400m, "Issued", 200m, null, null));
        Assert.False(result.IsValid);
        Assert.Contains(result.Issues, i => i.Code == "claims_exceed_invoice");
    }

    [Theory]
    [InlineData("AB")]          // too short
    [InlineData("has spaces")]  // illegal characters
    [InlineData("")]
    public void MalformedPolicyNumber_Fails(string policy)
    {
        var result = BillingRules.ValidateClaim(new BillingRules.ClaimContext(100m, "AIA", policy, 400m, "Issued", 0m, null, null));
        Assert.Contains(result.Issues, i => i.Code == "invalid_policy_number");
    }

    [Fact]
    public void ProviderDifferentFromPatientProfile_IsAWarningNotAnError()
    {
        var result = BillingRules.ValidateClaim(new BillingRules.ClaimContext(100m, "AIA", "AIA-1234", 400m, "Issued", 0m, "Ceylinco", null));
        Assert.True(result.IsValid);
        Assert.Contains(result.Issues, i => i.Code == "provider_mismatch" && i.Severity == "warning");
    }

    [Theory]
    [InlineData(100, false)]    // exactly the threshold: not above it
    [InlineData(100.01, true)]
    [InlineData(-150, true)]    // a reduction counts too
    public void InvoiceAdjustmentAbove100_RequiresApproval(decimal change, bool expected) =>
        Assert.Equal(expected, BillingRules.AdjustmentRequiresApproval(change));

    [Theory]
    [InlineData(500, false)]
    [InlineData(500.01, true)]
    public void InsuranceClaimAbove500_RequiresApproval(decimal amount, bool expected) =>
        Assert.Equal(expected, BillingRules.ClaimRequiresApproval(amount));

    [Theory]
    [InlineData(0, false)]
    [InlineData(0.01, true)]
    public void SubscriptionCancellationWithRefund_RequiresApproval(decimal refund, bool expected) =>
        Assert.Equal(expected, BillingRules.CancellationRequiresApproval(refund));

    [Fact]
    public void DiscountLargerThanSubtotal_IsAnError()
    {
        var result = BillingRules.ValidateInvoice(new[] { new BillingRules.DraftLine(1, 10m) }, discount: 12m, tax: 0m);
        Assert.False(result.IsValid);
        Assert.Contains(result.Issues, i => i.Code == "discount_exceeds_subtotal");
    }

    [Fact]
    public void TaxAboveTheCap_IsFlagged()
    {
        var result = BillingRules.ValidateInvoice(new[] { new BillingRules.DraftLine(2, 50m) }, discount: 0m, tax: 40m);
        Assert.True(result.RequiresReview);
        Assert.Contains(result.Issues, i => i.Code == "tax_out_of_range");
    }

    [Fact]
    public void OrdinaryInvoice_HasNoIssues()
    {
        var result = BillingRules.ValidateInvoice(new[] { new BillingRules.DraftLine(3, 1500m) }, discount: 450m, tax: 324m);
        Assert.True(result.IsValid);
        Assert.False(result.RequiresReview);
        Assert.Equal(4374m, result.FinalAmount);
    }

    // ------------------------------------------------------------------
    // Anomaly detection
    // ------------------------------------------------------------------

    [Fact]
    public void DuplicateInvoice_SameCustomerAndAmountWithinWindow_IsDetected()
    {
        var customer = Guid.NewGuid();
        var t0 = Range.From.AddDays(3);
        var snapshot = new BillingSnapshot
        {
            Invoices =
            {
                Invoice("INV-A", 2500m, customer: customer, created: t0),
                Invoice("INV-B", 2500m, customer: customer, created: t0.AddMinutes(4)),
                Invoice("INV-C", 2500m, customer: customer, created: t0.AddHours(5)), // outside the window
            },
        };

        var result = new BillingDomainAnalysisAgent().Run(BillingAnalysisTypes.Anomalies, Range, snapshot);

        var dup = Assert.Single(result.Anomalies, a => a.Type == "duplicate_invoice");
        Assert.Equal("INV-B", dup.EntityLabel);
    }

    [Fact]
    public void Overpayment_IsDetected()
    {
        var inv = Invoice("INV-OVER", 100m, payments: new[]
        {
            new PaymentFact(100m, "Cash", "Succeeded", Range.From.AddDays(3)),
            new PaymentFact(20m, "Card", "Succeeded", Range.From.AddDays(3)),
        });
        var result = new BillingDomainAnalysisAgent().Run(BillingAnalysisTypes.Anomalies, Range, new BillingSnapshot { Invoices = { inv } });
        var anomaly = Assert.Single(result.Anomalies, a => a.Type == "overpayment");
        Assert.Equal(20m, anomaly.Amount);
    }

    [Fact]
    public void TotalsThatDisagreeWithLineItems_AreCritical()
    {
        var tampered = Invoice("INV-TAMPER", 100m) with { FinalAmount = 60m };
        var result = new BillingDomainAnalysisAgent().Run(BillingAnalysisTypes.Anomalies, Range, new BillingSnapshot { Invoices = { tampered } });
        var anomaly = Assert.Single(result.Anomalies, a => a.Type == "amount_mismatch");
        Assert.Equal("critical", anomaly.Severity);
    }

    [Fact]
    public void LargeDiscountCorrection_RequiresApproval()
    {
        // 80% off a $1,000 item: fixing it to the 30% cap moves $500.
        var snapshot = new BillingSnapshot { Invoices = { Invoice("INV-BIG", 1000m, discount: 800m) } };
        var result = new BillingDomainAnalysisAgent().Run(BillingAnalysisTypes.Anomalies, Range, snapshot);
        var action = Assert.Single(result.RecommendedActions, a => a.ActionType == "adjust_invoice");
        Assert.Equal(500m, action.Amount);
        Assert.True(action.RequiresApproval);
    }

    [Fact]
    public void RevenueDropAboveThreshold_IsFlagged()
    {
        var snapshot = new BillingSnapshot
        {
            Invoices = { Invoice("INV-NOW", 300m) },
            PreviousInvoices = { Invoice("INV-THEN-1", 600m), Invoice("INV-THEN-2", 400m) },
        };
        var result = new BillingDomainAnalysisAgent().Run(BillingAnalysisTypes.Revenue, Range, snapshot);
        Assert.Contains(result.Anomalies, a => a.Type == "revenue_drop");
        Assert.Contains(result.Insights, i => i.Type == "revenue_trend" && i.Value == -70m);
    }

    [Fact]
    public void PriceFarFromTheBenchmark_IsAnOutlier()
    {
        var snapshot = new BillingSnapshot
        {
            Invoices =
            {
                Invoice("INV-P1", 2000m, description: "Teeth cleaning"),
                Invoice("INV-P2", 2100m, description: "Teeth cleaning"),
                Invoice("INV-P3", 1900m, description: "teeth  cleaning"),
                Invoice("INV-P4", 9000m, description: "Teeth cleaning"),
            },
        };
        var result = new BillingDomainAnalysisAgent().Run(BillingAnalysisTypes.Pricing, Range, snapshot);
        var outlier = Assert.Single(result.Anomalies, a => a.Type == "price_outlier");
        Assert.Equal("INV-P4", outlier.EntityLabel);
    }

    [Fact]
    public void CleanData_ProducesNoAnomaliesAndAConfidenceScore()
    {
        var snapshot = new BillingSnapshot { Invoices = { Invoice("INV-OK-1", 1000m), Invoice("INV-OK-2", 1500m) } };
        var result = new BillingDomainAnalysisAgent().Run(BillingAnalysisTypes.Full, Range, snapshot);
        Assert.Empty(result.Anomalies);
        Assert.InRange(result.ConfidenceScore, 0.01, 1.0);
        Assert.Equal(4, result.ToolCalls.Count);
    }

    // ------------------------------------------------------------------
    // Commission split
    // ------------------------------------------------------------------

    [Fact]
    public void CommissionSplit_AppliesRatesAndClampsToLimits()
    {
        var snapshot = new BillingSnapshot
        {
            CommissionRules =
            {
                new CommissionRuleFact(Guid.NewGuid(), "Agent", "Agent", "Percentage", 3m, null, null, 50_000m),
                new CommissionRuleFact(Guid.NewGuid(), "Referral", "Referrer", "Fixed", 0m, 10_000m, null, null),
            },
        };
        var result = new BillingDomainAnalysisAgent().Run(BillingAnalysisTypes.Commission, Range, snapshot, dealAmount: 2_000_000m);

        // 3% of 2,000,000 = 60,000, clamped to 50,000; plus the 10,000 fixed fee.
        var total = Assert.Single(result.Insights, i => i.Type == "commission");
        Assert.Equal(60_000m, total.Value);
        Assert.Empty(result.Anomalies);
    }

    [Fact]
    public void ApplyCommissionRule_MinimumIsEnforced()
    {
        var (amount, clamped) = BillingRules.ApplyCommissionRule(1000m, "Percentage", 2m, null, min: 100m, max: null);
        Assert.Equal(100m, amount);
        Assert.True(clamped);
    }

    // ------------------------------------------------------------------
    // Allow-listed tools only
    // ------------------------------------------------------------------

    [Fact]
    public void AllowList_HasExactlyTheFiveSpecTools()
    {
        Assert.Equal(new[]
        {
            "calculate_commission_split", "compare_pricing_benchmarks", "detect_billing_anomalies",
            "query_revenue_trends", "validate_insurance_claim",
        }, BillingDomainAnalysisAgent.AllowedTools.OrderBy(t => t));
    }

    [Fact]
    public void ToolOutsideTheAllowList_IsRefused()
    {
        var agent = new BillingDomainAnalysisAgent();
        Assert.Throws<ToolNotAllowedException>(() =>
            agent.Run("custom", Range, new BillingSnapshot(), toolsOverride: new[] { "delete_all_invoices" }));
    }
}
