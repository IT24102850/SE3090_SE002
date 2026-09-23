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
        using var message = new HttpRequestMessage(HttpMethod.Post, new Uri(baseUri.ToString().TrimEnd('/') + "/inventory/plan"))
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
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            return InventoryAgentResponse.Error(503, $"Could not reach the inventory planning service: {ex.Message}");
        }
    }
}

public sealed record InventoryAgentRequest(string Objective, Guid TenantId, Guid? BranchId, string AuthToken);
public sealed record InventoryAgentResponse(int StatusCode, string Body, string ContentType)
{
    public static InventoryAgentResponse Error(int statusCode, string message) =>
        new(statusCode, JsonSerializer.Serialize(new { status = "Failed", message }), "application/json");
}
