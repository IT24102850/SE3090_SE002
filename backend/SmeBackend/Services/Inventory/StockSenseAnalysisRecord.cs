using System.Text.Json;
using System.Text.Json.Nodes;
using SmeBackend.Models;

namespace SmeBackend.Services.Inventory;

/// <summary>
/// Turns one StockSense analysis run (the agent service's trace, or its
/// failure) into the AgentWorkflow row that records it: the plan, what the
/// agents found, the safety review's warnings, and the outcome. Only the
/// structured trace is stored - never the access token that was passed to
/// the agent's read-only tools.
/// </summary>
public static class StockSenseAnalysisRecord
{
    private const int MaxObjective = 400;

    public static AgentWorkflow From(Guid tenantId, Guid userId, string objective, int statusCode, string body)
    {
        var workflow = new AgentWorkflow
        {
            TenantId = tenantId,
            RequestedByUserId = userId,
            Objective = StockSenseWorkflows.AnalysisPrefix + Truncate(objective, MaxObjective),
            ApprovalStatus = "NotRequired",
            CompletedAt = DateTime.UtcNow,
            CurrentStep = 4,
        };

        JsonNode? trace = null;
        try { trace = JsonNode.Parse(body); } catch (JsonException) { }

        if (trace is not JsonObject root || statusCode >= 400)
        {
            workflow.Status = "Failed";
            workflow.ErrorLog = trace?["message"]?.GetValue<string>()
                ?? (trace?["warnings"] as JsonArray)?.LastOrDefault()?.GetValue<string>()
                ?? $"The inventory agent returned HTTP {statusCode}.";
            workflow.FinalOutcome = "Failed safely: no recommendation was produced and nothing was changed.";
            return workflow;
        }

        var recommendations = root["recommendations"] as JsonArray ?? new JsonArray();
        var insights = root["insights"] as JsonArray ?? new JsonArray();
        var agentStatus = root["status"]?.GetValue<string>() ?? "Completed";

        workflow.Status = agentStatus == "Failed" ? "Failed" : "Completed";
        workflow.PlanJson = new JsonObject
        {
            ["plannerSummary"] = root["planner_summary"]?.DeepClone(),
            ["dataSources"] = root["data_sources"]?.DeepClone(),
            ["agentWorkflowId"] = root["workflow_id"]?.DeepClone(),
        }.ToJsonString();
        workflow.ToolResultsJson = new JsonObject
        {
            ["recommendations"] = recommendations.DeepClone(),
            ["insights"] = insights.DeepClone(),
        }.ToJsonString();
        workflow.ValidationResults = (root["warnings"] as JsonArray ?? new JsonArray()).ToJsonString();
        workflow.FinalOutcome = agentStatus switch
        {
            "NeedsReview" => $"{recommendations.Count} replenishment recommendation(s) drafted for review; nothing ordered.",
            "NoAction" => "No replenishment needed.",
            _ => $"{insights.Count} insight(s), {recommendations.Count} recommendation(s).",
        };
        return workflow;
    }

    /// <summary>Adds <c>persisted_workflow_id</c> to the agent's JSON; returns the body unchanged if it is not a JSON object.</summary>
    public static string WithWorkflowId(string body, Guid workflowId)
    {
        try
        {
            if (JsonNode.Parse(body) is JsonObject root)
            {
                root["persisted_workflow_id"] = workflowId.ToString();
                return root.ToJsonString();
            }
        }
        catch (JsonException) { }
        return body;
    }

    private static string Truncate(string value, int max) => value.Length <= max ? value : value[..max];
}
