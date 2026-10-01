namespace SmeBackend.Services.Inventory;

/// <summary>
/// StockSense rows in the shared agent_workflows table are told apart by the
/// objective's prefix - the same convention the Billing Copilot uses - so the
/// booking Agent Workflow Monitor never tries to apply one, and the inventory
/// screens list only their own.
/// </summary>
public static class StockSenseWorkflows
{
    public const string Marker = "[StockSense";
    public const string AnalysisPrefix = "[StockSense analysis] ";
    public const string ReorderPrefix = "[StockSense reorder] ";

    public static bool IsStockSense(string? objective) =>
        objective is not null && objective.StartsWith(Marker, StringComparison.Ordinal);
}
