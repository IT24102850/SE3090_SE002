using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace SmeBackend.Services;

public interface IInventoryAgentService
{
    Task<InventoryAgentResponse> PlanAsync(InventoryAgentRequest request, CancellationToken cancellationToken = default);
}

public sealed class InventoryAgentService(HttpClient http, IConfiguration configuration) : IInventoryAgentService
{
    private readonly string? _baseUrl = configuration["AgentService:BaseUrl"];
    private readonly string? _internalToken = configuration["AgentService:InternalToken"];

    public async Task<InventoryAgentResponse> PlanAsync(InventoryAgentRequest request, CancellationToken cancellationToken = default)
    {
        if (!Uri.TryCreate(_baseUrl, UriKind.Absolute, out var baseUri))
            return InventoryAgentResponse.Error(503, "AgentService:BaseUrl is not configured.");
        if (string.IsNullOrWhiteSpace(_internalToken))
            return InventoryAgentResponse.Error(503, "AgentService:InternalToken is not configured.");

        http.Timeout = TimeSpan.FromSeconds(configuration.GetValue("AgentService:TimeoutSeconds", 60));
        var endpoints = new List<Uri>
        {
            new(baseUri.ToString().TrimEnd('/') + "/inventory/plan"),
        };

        // The local agent service is documented to run on port 8001. If a
        // stale IDE/environment override points loopback to another port,
        // retry the documented local port after the configured address refuses
        // the connection. Never redirect remote or deployed service URLs.
        if (baseUri.IsLoopback && baseUri.Port != 8001)
        {
            var fallback = new UriBuilder(baseUri) { Port = 8001 };
            var fallbackUri = new Uri(fallback.Uri.ToString().TrimEnd('/') + "/inventory/plan");
            if (!endpoints.Contains(fallbackUri)) endpoints.Add(fallbackUri);
        }

        HttpRequestException? connectionError = null;
        foreach (var endpoint in endpoints)
        {
            using var message = new HttpRequestMessage(HttpMethod.Post, endpoint)
            {
                Content = JsonContent.Create(new
                {
                    objective = request.Objective,
                    tenant_id = request.TenantId,
                    branch_id = request.BranchId,
                    auth_token = request.AuthToken,
                }),
            };
            message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _internalToken);
            try
            {
                using var response = await http.SendAsync(message, cancellationToken);
                var body = await response.Content.ReadAsStringAsync(cancellationToken);
                if (string.IsNullOrWhiteSpace(body))
                    return InventoryAgentResponse.Error(502, $"The AI service returned an empty response (HTTP {(int)response.StatusCode}). Check the agent service logs and deployment.");
                try
                {
                    using var _ = JsonDocument.Parse(body);
                }
                catch (JsonException)
                {
                    return InventoryAgentResponse.Error(502, "The AI service returned an invalid response. Check the agent service logs.");
                }
                return new InventoryAgentResponse((int)response.StatusCode, body, "application/json");
            }
            catch (HttpRequestException ex)
            {
                connectionError = ex;
            }
            catch (TaskCanceledException ex)
            {
                return InventoryAgentResponse.Error(503, $"The inventory planning service timed out at {endpoint.Authority}. Confirm the service is running and try again. {ex.Message}");
            }
        }

        return InventoryAgentResponse.Error(
            503,
            $"Could not reach the inventory planning service at {string.Join(" or ", endpoints.Select(endpoint => endpoint.Authority))}. Start the agent service with `uvicorn main:app --port 8001 --reload`, then retry. {connectionError?.Message}");
    }
}

public sealed record InventoryAgentRequest(string Objective, Guid TenantId, Guid? BranchId, string AuthToken);
public sealed record InventoryAgentResponse(int StatusCode, string Body, string ContentType)
{
    public static InventoryAgentResponse Error(int statusCode, string message) =>
        new(statusCode, JsonSerializer.Serialize(new { status = "Failed", message }), "application/json");
}
