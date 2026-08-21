using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using SmeBackend.Data;

namespace SmeBackend.Services;

/// Real FCM HTTP v1 sender, gated entirely by config. No Firebase project
/// exists in this environment yet (see plan discussion), so with
/// Fcm:ProjectId / Fcm:ServiceAccountJson unset this cleanly no-ops and
/// logs - same honesty pattern as the reminder channel stubs. Once a real
/// service account JSON is supplied via user-secrets/env, no code changes
/// are needed for this to start sending real pushes.
public class FcmPushNotificationSender : IPushNotificationSender
{
    private readonly HttpClient _http;
    private readonly IConfiguration _config;
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<FcmPushNotificationSender> _logger;

    private static string? _cachedAccessToken;
    private static DateTime _cachedAccessTokenExpiry = DateTime.MinValue;

    public FcmPushNotificationSender(
        HttpClient http, IConfiguration config, IServiceScopeFactory scopeFactory, ILogger<FcmPushNotificationSender> logger)
    {
        _http = http;
        _config = config;
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    public async Task SendAsync(Guid tenantId, Guid userId, string title, string message)
    {
        var projectId = _config["Fcm:ProjectId"];
        var serviceAccountJson = _config["Fcm:ServiceAccountJson"];

        if (string.IsNullOrWhiteSpace(projectId) || string.IsNullOrWhiteSpace(serviceAccountJson))
        {
            _logger.LogInformation("FCM not configured - skipping push for user {UserId}: {Title}", userId, title);
            return;
        }

        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var tokens = await db.DeviceTokens.AsNoTracking()
            .Where(t => t.TenantId == tenantId && t.UserId == userId)
            .Select(t => t.Token)
            .ToListAsync();

        if (tokens.Count == 0) return;

        string accessToken;
        try
        {
            accessToken = await GetAccessTokenAsync(serviceAccountJson);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Could not obtain an FCM access token - skipping push for user {UserId}.", userId);
            return;
        }

        foreach (var token in tokens)
        {
            try
            {
                var request = new HttpRequestMessage(HttpMethod.Post,
                    $"https://fcm.googleapis.com/v1/projects/{projectId}/messages:send");
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
                request.Content = JsonContent.Create(new
                {
                    message = new
                    {
                        token,
                        notification = new { title, body = message }
                    }
                });
                var response = await _http.SendAsync(request);
                if (!response.IsSuccessStatusCode)
                {
                    _logger.LogWarning("FCM send failed ({Status}) for a device token belonging to user {UserId}.",
                        response.StatusCode, userId);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "FCM send threw for a device token belonging to user {UserId}.", userId);
            }
        }
    }

    // Exchanges the service account's private key for a short-lived OAuth2
    // access token via a self-signed JWT (RFC 7523), avoiding a dependency
    // on Google.Apis.Auth for what is otherwise a one-shot HTTP call.
    private async Task<string> GetAccessTokenAsync(string serviceAccountJson)
    {
        if (_cachedAccessToken != null && DateTime.UtcNow < _cachedAccessTokenExpiry)
            return _cachedAccessToken;

        using var doc = JsonDocument.Parse(serviceAccountJson);
        var root = doc.RootElement;
        var clientEmail = root.GetProperty("client_email").GetString()!;
        var privateKeyPem = root.GetProperty("private_key").GetString()!;
        var tokenUri = root.TryGetProperty("token_uri", out var t) ? t.GetString()! : "https://oauth2.googleapis.com/token";

        var rsa = System.Security.Cryptography.RSA.Create();
        rsa.ImportFromPem(privateKeyPem);
        var signingKey = new RsaSecurityKey(rsa);
        var now = DateTime.UtcNow;

        var jwt = new JwtSecurityToken(
            issuer: clientEmail,
            audience: tokenUri,
            claims: new[] { new Claim("scope", "https://www.googleapis.com/auth/firebase.messaging") },
            notBefore: now,
            expires: now.AddMinutes(55),
            signingCredentials: new SigningCredentials(signingKey, SecurityAlgorithms.RsaSha256));
        var assertion = new JwtSecurityTokenHandler().WriteToken(jwt);

        var tokenResponse = await _http.PostAsync(tokenUri, new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "urn:ietf:params:oauth:grant-type:jwt-bearer",
            ["assertion"] = assertion
        }));
        tokenResponse.EnsureSuccessStatusCode();

        var payload = await tokenResponse.Content.ReadFromJsonAsync<JsonElement>();
        var accessToken = payload.GetProperty("access_token").GetString()!;
        var expiresIn = payload.TryGetProperty("expires_in", out var e) ? e.GetInt32() : 3600;

        _cachedAccessToken = accessToken;
        _cachedAccessTokenExpiry = now.AddSeconds(expiresIn - 60);
        return accessToken;
    }
}
