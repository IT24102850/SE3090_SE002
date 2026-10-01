using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using SmeBackend.Models;

namespace SmeBackend.Tests.Api;

/// <summary>
/// HTTP-level API integration tests: authentication, role-based
/// authorization, validation, the agent-approval permission boundary, error
/// responses and CORS, all through the real middleware pipeline.
/// </summary>
public sealed class AuthAndRoleApiTests(ApiWebApplicationFactory factory) : IClassFixture<ApiWebApplicationFactory>
{
    private async Task<HttpClient> SignedInAs(UserRole role)
    {
        var client = factory.CreateClient();
        var response = await client.PostAsJsonAsync("/api/auth/login",
            new { email = ApiWebApplicationFactory.EmailFor(role), password = ApiWebApplicationFactory.Password });
        response.EnsureSuccessStatusCode();
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", body.RootElement.GetProperty("accessToken").GetString());
        return client;
    }

    [Fact]
    public async Task Login_WithValidCredentials_ReturnsJwtAndRole()
    {
        var client = factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/auth/login",
            new { email = ApiWebApplicationFactory.EmailFor(UserRole.Manager), password = ApiWebApplicationFactory.Password });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var token = body.RootElement.GetProperty("accessToken").GetString();
        Assert.False(string.IsNullOrEmpty(token));
        Assert.Equal(3, token!.Split('.').Length); // header.payload.signature
        Assert.Equal("Manager", body.RootElement.GetProperty("user").GetProperty("role").GetString());
    }

    [Fact]
    public async Task Login_WithWrongPassword_Returns401()
    {
        var response = await factory.CreateClient().PostAsJsonAsync("/api/auth/login",
            new { email = ApiWebApplicationFactory.EmailFor(UserRole.Admin), password = "wrong-password" });

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Login_WithMalformedEmail_Returns400ValidationProblem()
    {
        var response = await factory.CreateClient().PostAsJsonAsync("/api/auth/login",
            new { email = "not-an-email", password = "" });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var errors = body.RootElement.GetProperty("errors");
        Assert.True(errors.TryGetProperty("Email", out _));
        Assert.True(errors.TryGetProperty("Password", out _));
    }

    [Fact]
    public async Task ProtectedEndpoint_WithoutToken_Returns401()
    {
        var response = await factory.CreateClient().GetAsync("/api/auth/me");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task ProtectedEndpoint_WithTamperedToken_Returns401()
    {
        var client = await SignedInAs(UserRole.Admin);
        var token = client.DefaultRequestHeaders.Authorization!.Parameter!;
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", token[..^4] + (token.EndsWith("AAAA") ? "BBBB" : "AAAA"));

        var response = await client.GetAsync("/api/auth/me");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Me_WithToken_ReturnsTheSignedInUser()
    {
        var client = await SignedInAs(UserRole.Staff);

        var response = await client.GetAsync("/api/auth/me");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(ApiWebApplicationFactory.EmailFor(UserRole.Staff), body.RootElement.GetProperty("email").GetString());
    }

    [Theory]
    [InlineData(UserRole.Admin, HttpStatusCode.OK)]
    [InlineData(UserRole.Manager, HttpStatusCode.Forbidden)]
    [InlineData(UserRole.Staff, HttpStatusCode.Forbidden)]
    [InlineData(UserRole.Customer, HttpStatusCode.Forbidden)]
    public async Task UserManagement_IsAdminOnly(UserRole role, HttpStatusCode expected)
    {
        var client = await SignedInAs(role);

        var response = await client.GetAsync("/api/users");

        Assert.Equal(expected, response.StatusCode);
    }

    [Theory]
    [InlineData(UserRole.Customer)]
    [InlineData(UserRole.Staff)]
    public async Task AgentWorkflowApproval_IsRefusedBelowManager(UserRole role)
    {
        var client = await SignedInAs(role);

        var response = await client.PostAsJsonAsync($"/api/agent/workflow/{Guid.NewGuid()}/approve", new { });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task AgentWorkflowApproval_WithoutToken_Returns401()
    {
        var response = await factory.CreateClient()
            .PostAsJsonAsync($"/api/agent/workflow/{Guid.NewGuid()}/approve", new { });

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task BookingHistory_RequiresAuthentication()
    {
        var response = await factory.CreateClient().GetAsync($"/api/bookings/{Guid.NewGuid()}/history");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task BookingHistory_ForAnUnknownBooking_Returns404()
    {
        var client = await SignedInAs(UserRole.Manager);

        var response = await client.GetAsync($"/api/bookings/{Guid.NewGuid()}/history");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task UnknownRoute_Returns404ProblemDetails()
    {
        var response = await factory.CreateClient().GetAsync("/api/does-not-exist");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
    }

    [Fact]
    public async Task LivenessProbe_IsAnonymousAndHealthy()
    {
        var response = await factory.CreateClient().GetAsync("/health/live");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Theory]
    [InlineData("https://se-3090-se-002.vercel.app", true)]
    [InlineData("http://localhost:5173", true)]
    [InlineData("https://evil.example.com", false)]
    public async Task Cors_AllowsOnlyTheWebAppAndLocalDev(string origin, bool allowed)
    {
        var request = new HttpRequestMessage(HttpMethod.Options, "/api/auth/login");
        request.Headers.Add("Origin", origin);
        request.Headers.Add("Access-Control-Request-Method", "POST");

        var response = await factory.CreateClient().SendAsync(request);

        Assert.Equal(allowed, response.Headers.Contains("Access-Control-Allow-Origin"));
    }
}
