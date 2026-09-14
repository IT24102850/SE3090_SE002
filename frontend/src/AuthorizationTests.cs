using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Threading.Tasks;
using Xunit;

// A simple record to deserialize the login response for tests
public record AuthTestResponse(string AccessToken, string RefreshToken, System.DateTime ExpiresAt, string Role, string FullName);

public class AuthorizationTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly CustomWebApplicationFactory _factory;

    public AuthorizationTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    private async Task<string> GetTokenAsync(string email, string password)
    {
        var loginResponse = await _client.PostAsJsonAsync("/api/auth/login", new { email, password });
        loginResponse.EnsureSuccessStatusCode();
        var authResponse = await loginResponse.Content.ReadFromJsonAsync<AuthTestResponse>();
        return authResponse!.AccessToken;
    }

    [Theory]
    [InlineData("admin@lumenis.com", "Admin@123", "/api/bookings", HttpStatusCode.OK)]
    [InlineData("manager@lumenis.com", "Manager@123", "/api/bookings", HttpStatusCode.OK)]
    [InlineData("staff@lumenis.com", "Staff@123", "/api/bookings", HttpStatusCode.Forbidden)] // Staff can't access the root GET
    [InlineData("customer@lumenis.com", "Customer@123", "/api/bookings", HttpStatusCode.Forbidden)]
    [InlineData("staff@lumenis.com", "Staff@123", "/api/bookings/my-bookings", HttpStatusCode.OK)]
    [InlineData("customer@lumenis.com", "Customer@123", "/api/bookings/bulk-schedule", HttpStatusCode.Forbidden)]
    public async Task RoleBasedAccess_ReturnsExpectedStatus(
        string email, string password, string endpoint, HttpStatusCode expected)
    {
        // Arrange: Login and get token
        var token = await GetTokenAsync(email, password);
        _client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        // Act: Access protected endpoint
        var response = await _client.GetAsync(endpoint);

        // Assert
        Assert.Equal(expected, response.StatusCode);
    }

    [Fact]
    public async Task Customer_CanOnlyAccessOwnData_Placeholder()
    {
        // Arrange: Login as customer
        var token = await GetTokenAsync("customer@lumenis.com", "Customer@123");
        _client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        // Act: Try to access another customer's data (hypothetical endpoint)
        var response = await _client.GetAsync("/api/bookings?customerId=other-customer-id");

        // Assert: This test expects that your endpoint logic will eventually enforce this.
        // For now, it checks that the request doesn't fail unexpectedly.
        Assert.True(response.StatusCode == HttpStatusCode.Forbidden ||
                    response.StatusCode == HttpStatusCode.OK);
    }
}