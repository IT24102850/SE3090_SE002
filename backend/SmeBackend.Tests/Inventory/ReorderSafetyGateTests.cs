using SmeBackend.Services.Inventory;
using static SmeBackend.Services.Inventory.ReorderSafetyGate;

namespace SmeBackend.Tests.Inventory;

/// <summary>
/// Golden cases for StockSense's deterministic safety gate. The two from the
/// task-assignment plan are here by name: stock below reorder level with a
/// small order from a known supplier is placed; a purchase order over the
/// limit must wait for approval.
/// </summary>
public sealed class ReorderSafetyGateTests
{
    private static readonly Guid Branch = Guid.NewGuid();
    private static readonly Thresholds Limits = new(MaxAutoApproveValue: 150_000m, MaxAutoApproveUnits: 100m, MaxLineQuantity: 10_000m);
    private static readonly SupplierFacts Known = new(Guid.NewGuid(), "MediSupply", IsActive: true, ReceivedOrderCount: 3);

    private static Line Gloves(decimal qty, decimal? cost = 800m, Guid? branch = null) =>
        new(Guid.NewGuid(), "Latex gloves", branch ?? Branch, qty, cost);

    [Fact]
    public void Golden_SmallFullyPricedOrderFromKnownSupplier_IsPlacedAutomatically()
    {
        var result = Evaluate([Gloves(20)], Branch, Known, Limits);

        Assert.Equal(Decision.AutoApproved, result.Decision);
        Assert.Equal(16_000m, result.TotalValue);
        Assert.All(result.Checks, c => Assert.True(c.Passed, c.Detail));
    }

    [Fact]
    public void Golden_OrderOverTheValueLimit_WaitsForApproval()
    {
        var result = Evaluate([Gloves(100, cost: 2_000m)], Branch, Known, Limits); // 200,000

        Assert.Equal(Decision.NeedsApproval, result.Decision);
        Assert.Contains(result.ApprovalReasons, r => r.Contains("exceeds the 150,000"));
    }

    [Fact]
    public void BulkOrderOver100Units_WaitsForApproval()
    {
        var result = Evaluate([Gloves(60, cost: 10m), Gloves(50, cost: 10m)], Branch, Known, Limits);

        Assert.Equal(Decision.NeedsApproval, result.Decision);
        Assert.Contains(result.Checks, c => c.Rule == "units_within_auto_limit" && !c.Passed);
    }

    [Fact]
    public void NewSupplier_WaitsForApproval_EvenForASmallOrder()
    {
        var newcomer = Known with { ReceivedOrderCount = 0, Name = "Fresh Traders" };

        var result = Evaluate([Gloves(2)], Branch, newcomer, Limits);

        Assert.Equal(Decision.NeedsApproval, result.Decision);
        Assert.Contains(result.ApprovalReasons, r => r.Contains("Fresh Traders has never delivered"));
    }

    [Fact]
    public void ItemWithoutUnitCost_WaitsForApproval_BecauseTheValueIsUnknown()
    {
        var result = Evaluate([Gloves(2, cost: null)], Branch, Known, Limits);

        Assert.Equal(Decision.NeedsApproval, result.Decision);
        Assert.Contains(result.Checks, c => c.Rule == "fully_priced" && !c.Passed);
    }

    [Fact]
    public void InactiveSupplier_IsRejected_AndNoApprovalCanOverrideIt()
    {
        var closed = Known with { IsActive = false };

        var result = Evaluate([Gloves(2)], Branch, closed, Limits);

        Assert.Equal(Decision.Rejected, result.Decision);
        Assert.True(IsBlocking("supplier_active"));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-5)]
    public void NonPositiveQuantity_IsRejected(decimal qty)
    {
        Assert.Equal(Decision.Rejected, Evaluate([Gloves(qty)], Branch, Known, Limits).Decision);
    }

    [Fact]
    public void AbsurdQuantityOnOneLine_IsRejected()
    {
        Assert.Equal(Decision.Rejected, Evaluate([Gloves(50_000, cost: 0.01m)], Branch, Known, Limits).Decision);
    }

    [Fact]
    public void ItemFromAnotherBranch_IsRejected()
    {
        var result = Evaluate([Gloves(2, branch: Guid.NewGuid())], Branch, Known, Limits);

        Assert.Equal(Decision.Rejected, result.Decision);
        Assert.Contains(result.RejectionReasons, r => r.Contains("another branch"));
    }

    [Fact]
    public void EmptyProposal_IsRejected()
    {
        Assert.Equal(Decision.Rejected, Evaluate([], Branch, Known, Limits).Decision);
    }

    [Fact]
    public void Rejection_WinsOverApproval_WhenBothApply()
    {
        var closed = Known with { IsActive = false, ReceivedOrderCount = 0 };

        var result = Evaluate([Gloves(500, cost: 1_000m)], Branch, closed, Limits);

        Assert.Equal(Decision.Rejected, result.Decision);
    }

    [Fact]
    public void ExactlyAtBothLimits_IsStillAutomatic()
    {
        var result = Evaluate([Gloves(100, cost: 1_500m)], Branch, Known, Limits); // 150,000 and 100 units

        Assert.Equal(Decision.AutoApproved, result.Decision);
    }

    [Fact]
    public void EveryRuleIsReportedOnEveryRun_ForTheAuditTrail()
    {
        var rules = Evaluate([Gloves(1)], Branch, Known, Limits).Checks.Select(c => c.Rule).ToHashSet();

        Assert.Equal(
            new HashSet<string> { "has_lines", "positive_quantities", "quantity_ceiling", "single_branch", "supplier_active",
                "non_negative_cost", "fully_priced", "value_within_auto_limit", "units_within_auto_limit", "known_supplier" },
            rules);
    }

    [Theory]
    [InlineData(20, 19, 20, true)]   // crosses the line
    [InlineData(19, 18, 20, false)]  // already below - no second alert
    [InlineData(25, 21, 20, false)]  // still above
    [InlineData(5, 0, 0, false)]     // no reorder level configured
    public void LowStockAlert_FiresOnlyOnTheCrossing(decimal before, decimal after, decimal level, bool expected)
    {
        Assert.Equal(expected, LowStockAlerts.Crossed(before, after, level));
    }
}
