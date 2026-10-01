namespace SmeBackend.Services.Inventory;

/// <summary>
/// StockSense's Validation/Safety step for a proposed purchase order: pure,
/// deterministic, no model. It decides one of three things.
///
/// - Rejected: something is wrong that no approval can fix (an inactive
///   supplier, a non-positive or absurd quantity, an item from another
///   branch). The proposal is recorded and goes no further.
/// - NeedsApproval: the order is valid but high-impact - over the value or
///   unit threshold, from a supplier never received from before, or priced
///   from items with no unit cost. It pauses until a Manager or Admin
///   approves, rejects or asks for a revision.
/// - AutoApproved: small, fully priced, from a known supplier. The purchase
///   order is placed straight away, and the workflow record says so.
///
/// The thresholds come from configuration (Inventory:ReorderApproval), never
/// from the request, so neither a user nor the agent can loosen them.
/// </summary>
public static class ReorderSafetyGate
{
    public enum Decision { AutoApproved, NeedsApproval, Rejected }

    public sealed record Line(Guid InventoryItemId, string Name, Guid? BranchId, decimal Quantity, decimal? UnitCost);

    public sealed record SupplierFacts(Guid Id, string Name, bool IsActive, int ReceivedOrderCount);

    public sealed record Thresholds(decimal MaxAutoApproveValue, decimal MaxAutoApproveUnits, decimal MaxLineQuantity)
    {
        /// <summary>
        /// The plan's "$500" and "100 units", in the tenant's inventory
        /// currency (LKR): 150,000 LKR at the platform's 300 LKR/USD rate.
        /// </summary>
        public static Thresholds Default { get; } = new(150_000m, 100m, 10_000m);
    }

    public sealed record Check(string Rule, bool Passed, string Detail);

    public sealed record Result(Decision Decision, decimal TotalValue, decimal TotalUnits, IReadOnlyList<Check> Checks)
    {
        public IEnumerable<string> RejectionReasons => Checks.Where(c => !c.Passed && IsBlocking(c.Rule)).Select(c => c.Detail);
        public IEnumerable<string> ApprovalReasons => Checks.Where(c => !c.Passed && !IsBlocking(c.Rule)).Select(c => c.Detail);
    }

    // Rules no approval can override.
    private static readonly HashSet<string> Blocking = new(StringComparer.Ordinal)
    {
        "has_lines", "positive_quantities", "quantity_ceiling", "single_branch", "supplier_active", "non_negative_cost",
    };

    public static bool IsBlocking(string rule) => Blocking.Contains(rule);

    public static Result Evaluate(IReadOnlyList<Line> lines, Guid branchId, SupplierFacts supplier, Thresholds limits)
    {
        var checks = new List<Check>();
        var totalUnits = lines.Sum(l => l.Quantity);
        var totalValue = lines.Sum(l => l.Quantity * (l.UnitCost ?? 0m));

        checks.Add(new("has_lines", lines.Count > 0,
            lines.Count > 0 ? $"{lines.Count} line(s) proposed." : "The proposal has no lines."));

        var nonPositive = lines.Where(l => l.Quantity <= 0).Select(l => l.Name).ToList();
        checks.Add(new("positive_quantities", nonPositive.Count == 0,
            nonPositive.Count == 0 ? "Every quantity is positive." : $"Quantity must be positive: {string.Join(", ", nonPositive)}."));

        var huge = lines.Where(l => l.Quantity > limits.MaxLineQuantity).Select(l => l.Name).ToList();
        checks.Add(new("quantity_ceiling", huge.Count == 0,
            huge.Count == 0 ? $"No line exceeds {limits.MaxLineQuantity:0} units." : $"Over {limits.MaxLineQuantity:0} units on one line: {string.Join(", ", huge)}."));

        var otherBranch = lines.Where(l => l.BranchId is { } b && b != branchId).Select(l => l.Name).ToList();
        checks.Add(new("single_branch", otherBranch.Count == 0,
            otherBranch.Count == 0 ? "All items belong to the ordering branch." : $"Items from another branch: {string.Join(", ", otherBranch)}."));

        checks.Add(new("supplier_active", supplier.IsActive,
            supplier.IsActive ? $"{supplier.Name} is an active supplier." : $"{supplier.Name} is inactive and cannot receive orders."));

        var negative = lines.Where(l => l.UnitCost < 0).Select(l => l.Name).ToList();
        checks.Add(new("non_negative_cost", negative.Count == 0,
            negative.Count == 0 ? "No negative unit costs." : $"Negative unit cost: {string.Join(", ", negative)}."));

        var unpriced = lines.Where(l => l.UnitCost is null).Select(l => l.Name).ToList();
        checks.Add(new("fully_priced", unpriced.Count == 0,
            unpriced.Count == 0 ? "Every item has a unit cost." : $"No unit cost, so the order value is unknown: {string.Join(", ", unpriced)}."));

        checks.Add(new("value_within_auto_limit", totalValue <= limits.MaxAutoApproveValue,
            totalValue <= limits.MaxAutoApproveValue
                ? $"Order value {totalValue:N2} is within the {limits.MaxAutoApproveValue:N0} auto-approval limit."
                : $"Order value {totalValue:N2} exceeds the {limits.MaxAutoApproveValue:N0} auto-approval limit."));

        checks.Add(new("units_within_auto_limit", totalUnits <= limits.MaxAutoApproveUnits,
            totalUnits <= limits.MaxAutoApproveUnits
                ? $"{totalUnits:0.###} units is within the {limits.MaxAutoApproveUnits:0} unit bulk limit."
                : $"{totalUnits:0.###} units exceeds the {limits.MaxAutoApproveUnits:0} unit bulk limit."));

        checks.Add(new("known_supplier", supplier.ReceivedOrderCount > 0,
            supplier.ReceivedOrderCount > 0
                ? $"{supplier.Name} has delivered {supplier.ReceivedOrderCount} order(s) before."
                : $"{supplier.Name} has never delivered to this business - a new supplier needs approval."));

        var decision = checks.Any(c => !c.Passed && IsBlocking(c.Rule)) ? Decision.Rejected
            : checks.Any(c => !c.Passed) ? Decision.NeedsApproval
            : Decision.AutoApproved;

        return new Result(decision, totalValue, totalUnits, checks);
    }
}
