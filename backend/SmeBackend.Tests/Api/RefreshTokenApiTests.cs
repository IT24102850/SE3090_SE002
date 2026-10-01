using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Tests.Api;

/// <summary>
/// The refresh-token lifecycle through HTTP: issue on login, rotate on
/// refresh, refuse a used token and treat its replay as theft, revoke on
/// sign-out and on password change, and never store the raw token.
/// </summary>
public sealed class RefreshTokenApiTests(ApiWebApplicationFactory factory) : IClassFixture<ApiWebApplicationFactory>
{
    private sealed record Tokens(string Access, string Refresh);

    private static async Task<Tokens> ReadTokens(HttpResponseMessage response)
    {
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return new Tokens(
            body.RootElement.GetProperty("accessToken").GetString()!,
            body.RootElement.GetProperty("refreshToken").GetString()!);
    }

    private async Task<Tokens> Login(UserRole role = UserRole.Manager) =>
        await ReadTokens(await factory.CreateClient().PostAsJsonAsync("/api/auth/login",
            new { email = ApiWebApplicationFactory.EmailFor(role), password = ApiWebApplicationFactory.Password }));

    private Task<HttpResponseMessage> Refresh(string refreshToken) =>
        factory.CreateClient().PostAsJsonAsync("/api/auth/refresh", new { refreshToken });

    [Fact]
    public async Task Refresh_WithTheLoginToken_ReturnsANewWorkingAccessTokenAndARotatedRefreshToken()
    {
        var login = await Login();

        var refreshed = await ReadTokens(await Refresh(login.Refresh));

        Assert.NotEqual(login.Refresh, refreshed.Refresh);
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", refreshed.Access);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/auth/me")).StatusCode);
    }

    [Fact]
    public async Task Refresh_WithAnAlreadyUsedToken_Returns401_AndRevokesTheWholeFamily()
    {
        var login = await Login();
        var rotated = await ReadTokens(await Refresh(login.Refresh));

        // Replay of the first token: someone else holds it.
        Assert.Equal(HttpStatusCode.Unauthorized, (await Refresh(login.Refresh)).StatusCode);

        // ...so the legitimate client's newer token is dead too.
        Assert.Equal(HttpStatusCode.Unauthorized, (await Refresh(rotated.Refresh)).StatusCode);
    }

    [Fact]
    public async Task Refresh_WithAnUnknownToken_Returns401()
    {
        var response = await Refresh(Convert.ToBase64String(new byte[64]));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Refresh_WithAnEmptyToken_Returns400()
    {
        var response = await Refresh("");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Logout_RevokesTheRefreshToken()
    {
        var login = await Login();

        var logout = await factory.CreateClient().PostAsJsonAsync("/api/auth/logout", new { refreshToken = login.Refresh });

        Assert.Equal(HttpStatusCode.NoContent, logout.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Refresh(login.Refresh)).StatusCode);
    }

    [Fact]
    public async Task OnlyTheHashIsStored_NeverTheToken()
    {
        var login = await Login(UserRole.Staff);

        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var stored = await db.RefreshTokens.IgnoreQueryFilters().ToListAsync();

        Assert.DoesNotContain(stored, t => t.TokenHash == login.Refresh);
        Assert.Contains(stored, t => t.TokenHash == RefreshTokenStore.Hash(login.Refresh));
    }

    [Fact]
    public async Task RevokeAllForUser_EndsEverySessionOfThatUser()
    {
        var first = await Login(UserRole.Customer);
        var second = await Login(UserRole.Customer);

        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var userId = (await db.Users.IgnoreQueryFilters()
                .FirstAsync(u => u.Email == ApiWebApplicationFactory.EmailFor(UserRole.Customer))).Id;
            await RefreshTokenStore.RevokeAllForUserAsync(db, userId);
        }

        Assert.Equal(HttpStatusCode.Unauthorized, (await Refresh(first.Refresh)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Refresh(second.Refresh)).StatusCode);
    }
}
