using System.Collections.Concurrent;
using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.IdentityModel.Tokens;

namespace SmeBackend.Services;

public sealed record ExternalIdentity(string Email, string DisplayName, string? PictureUrl);

public interface IMobileExternalAuthService
{
    Task<ExternalIdentity> GetVerifiedIdentityAsync(string provider, string? idToken, string? accessToken, CancellationToken cancellationToken);
}

/// <summary>
/// Validates provider identity server-side. The app never sends a trusted email
/// or profile name; those are read from a signed provider token or Microsoft Graph.
/// </summary>
public sealed class MobileExternalAuthService(
    IConfiguration configuration,
    IHttpClientFactory httpClientFactory,
    ILogger<MobileExternalAuthService> logger) : IMobileExternalAuthService
{
    private sealed record CachedKeys(IReadOnlyList<SecurityKey> Keys, DateTimeOffset ExpiresAt);
    private static readonly ConcurrentDictionary<string, CachedKeys> SigningKeys = new();

    public async Task<ExternalIdentity> GetVerifiedIdentityAsync(
        string provider,
        string? idToken,
        string? accessToken,
        CancellationToken cancellationToken)
    {
        var normalized = provider.Trim().ToLowerInvariant();
        if (normalized == "microsoft")
        {
            if (string.IsNullOrWhiteSpace(accessToken))
                throw new ExternalAuthException("Microsoft did not return an access token. Please try again.");
            return await GetMicrosoftIdentityAsync(accessToken, cancellationToken);
        }

        var (issuer, jwksUri, audience, expectedIssuers) = normalized switch
        {
            "google" => (
                "https://accounts.google.com",
                "https://www.googleapis.com/oauth2/v3/certs",
                configuration["Authentication:Google:ClientId"],
                new[] { "https://accounts.google.com", "accounts.google.com" }),
            "apple" => (
                "https://appleid.apple.com",
                "https://appleid.apple.com/auth/keys",
                configuration["Authentication:Apple:ClientId"],
                new[] { "https://appleid.apple.com" }),
            _ => throw new ExternalAuthException("This sign-in provider is not supported."),
        };

        if (string.IsNullOrWhiteSpace(audience))
            throw new ExternalAuthException($"{provider} sign-in has not been configured on the server yet.");
        if (string.IsNullOrWhiteSpace(idToken))
            throw new ExternalAuthException($"{provider} did not return an identity token. Please try again.");

        var keys = await GetSigningKeysAsync(issuer, jwksUri, cancellationToken);
        var handler = new JwtSecurityTokenHandler();
        ClaimsPrincipal principal;
        try
        {
            principal = handler.ValidateToken(idToken, new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidIssuers = expectedIssuers,
                ValidateAudience = true,
                ValidAudience = audience,
                ValidateIssuerSigningKey = true,
                IssuerSigningKeys = keys,
                RequireSignedTokens = true,
                ValidateLifetime = true,
                ClockSkew = TimeSpan.FromMinutes(2),
            }, out _);
        }
        catch (Exception ex) when (ex is SecurityTokenException or ArgumentException)
        {
            logger.LogInformation("Rejected invalid {Provider} mobile identity token: {Reason}", provider, ex.Message);
            throw new ExternalAuthException($"Could not verify your {provider} account. Please try again.");
        }

        var email = principal.FindFirst("email")?.Value;
        var verified = principal.FindFirst("email_verified")?.Value;
        if (string.IsNullOrWhiteSpace(email) || !string.Equals(verified, "true", StringComparison.OrdinalIgnoreCase))
            throw new ExternalAuthException($"Your {provider} account must provide a verified email address.");

        var name = principal.FindFirst("name")?.Value;
        var picture = principal.FindFirst("picture")?.Value;
        return new ExternalIdentity(email.Trim().ToLowerInvariant(), NormalizeName(name, email), picture);
    }

    private async Task<ExternalIdentity> GetMicrosoftIdentityAsync(string accessToken, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get,
            "https://graph.microsoft.com/v1.0/me?$select=id,displayName,mail,userPrincipalName");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        using var response = await httpClientFactory.CreateClient().SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            logger.LogInformation("Microsoft Graph rejected mobile profile lookup with status {StatusCode}", (int)response.StatusCode);
            throw new ExternalAuthException("Could not verify your Microsoft account. Please try again.");
        }

        await using var content = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var profile = await JsonDocument.ParseAsync(content, cancellationToken: cancellationToken);
        var root = profile.RootElement;
        var email = ReadString(root, "mail") ?? ReadString(root, "userPrincipalName");
        if (string.IsNullOrWhiteSpace(email) || !email.Contains('@'))
            throw new ExternalAuthException("Your Microsoft account does not have a usable email address.");
        var name = ReadString(root, "displayName");
        return new ExternalIdentity(email.Trim().ToLowerInvariant(), NormalizeName(name, email), null);
    }

    private async Task<IReadOnlyList<SecurityKey>> GetSigningKeysAsync(string issuer, string jwksUri, CancellationToken cancellationToken)
    {
        if (SigningKeys.TryGetValue(issuer, out var cached) && cached.ExpiresAt > DateTimeOffset.UtcNow)
            return cached.Keys;

        using var response = await httpClientFactory.CreateClient().GetAsync(jwksUri, cancellationToken);
        response.EnsureSuccessStatusCode();
        var json = await response.Content.ReadAsStringAsync(cancellationToken);
        var keys = new JsonWebKeySet(json).GetSigningKeys().ToList();
        if (keys.Count == 0)
            throw new ExternalAuthException("The sign-in provider returned no verification keys. Please try again later.");

        SigningKeys[issuer] = new CachedKeys(keys, DateTimeOffset.UtcNow.AddHours(6));
        return keys;
    }

    private static string? ReadString(JsonElement root, string property) =>
        root.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static string NormalizeName(string? name, string email)
    {
        var value = string.IsNullOrWhiteSpace(name) ? email.Split('@')[0] : name.Trim();
        return value.Length > 150 ? value[..150] : value;
    }
}

public sealed class ExternalAuthException(string message) : Exception(message);
