using System.Text.Json;
using SmeBackend.Services.Inventory;

namespace SmeBackend.Tests.Inventory;

/// <summary>Every StockSense analysis run - including a failed one - becomes an auditable workflow record.</summary>
public sealed class StockSenseAnalysisRecordTests
{
    private static readonly Guid Tenant = Guid.NewGuid();
    private static readonly Guid User = Guid.NewGuid();

    private const string Trace = """
    {
      "workflow_id": "agent-run-1",
      "status": "NeedsReview",
      "planner_summary": "Check coverage for the Weligama branch.",
      "data_sources": ["Authorized inventory snapshot", "Recent stock movements"],
      "recommendations": [{ "inventory_item_id": "a", "item_name": "Latex gloves", "recommended_quantity": 100 }],
      "insights": [{ "category": "coverage", "title": "Gloves run out in 3 days" }],
      "warnings": ["No supplier lead-time data is available"]
    }
    """;

    [Fact]
    public void SuccessfulRun_IsRecordedWithPlanFindingsAndWarnings()
    {
        var workflow = StockSenseAnalysisRecord.From(Tenant, User, "Check gloves", 200, Trace);

        Assert.StartsWith(StockSenseWorkflows.AnalysisPrefix, workflow.Objective);
        Assert.Equal("Completed", workflow.Status);
        Assert.Equal("NotRequired", workflow.ApprovalStatus);
        Assert.Equal(User, workflow.RequestedByUserId);
        Assert.Contains("Weligama", workflow.PlanJson);
        Assert.Contains("Latex gloves", workflow.ToolResultsJson);
        Assert.Contains("lead-time", workflow.ValidationResults);
        Assert.Contains("1 replenishment recommendation", workflow.FinalOutcome);
    }

    [Fact]
    public void FailedRun_IsRecordedAsASafeFailure()
    {
        var workflow = StockSenseAnalysisRecord.From(Tenant, User, "Check gloves", 503,
            """{"message":"The inventory planning service timed out."}""");

        Assert.Equal("Failed", workflow.Status);
        Assert.Equal("The inventory planning service timed out.", workflow.ErrorLog);
        Assert.Contains("nothing was changed", workflow.FinalOutcome);
    }

    [Fact]
    public void NonJsonBody_IsStillRecorded()
    {
        var workflow = StockSenseAnalysisRecord.From(Tenant, User, "Check gloves", 502, "<html>Bad gateway</html>");

        Assert.Equal("Failed", workflow.Status);
        Assert.Contains("502", workflow.ErrorLog);
    }

    [Fact]
    public void TheAccessTokenIsNeverStored()
    {
        var withToken = Trace.Replace("\"workflow_id\"", "\"auth_token\": \"eyJ.secret.jwt\", \"workflow_id\"");

        var workflow = StockSenseAnalysisRecord.From(Tenant, User, "Check gloves", 200, withToken);

        Assert.DoesNotContain("eyJ.secret.jwt", workflow.PlanJson + workflow.ToolResultsJson + workflow.ValidationResults);
    }

    [Fact]
    public void ResponseGainsThePersistedWorkflowId()
    {
        var id = Guid.NewGuid();

        var body = StockSenseAnalysisRecord.WithWorkflowId(Trace, id);

        using var doc = JsonDocument.Parse(body);
        Assert.Equal(id.ToString(), doc.RootElement.GetProperty("persisted_workflow_id").GetString());
        Assert.Equal("NeedsReview", doc.RootElement.GetProperty("status").GetString());
    }
}
