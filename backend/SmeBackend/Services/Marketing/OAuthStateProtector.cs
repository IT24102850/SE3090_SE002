using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Caching.Memory;

namespace SmeBackend.Services.Marketing;

/// What the OAuth round trip carries through the provider and back: who
/// started it, for which business, and where to send the browser after.
public sealed record OAuthState(Guid TenantId, Guid UserId, string Platform, string ReturnOrigin, string Nonce, long ExpiresAtUnix);

public interface IOAuthStateProtector
{
    string Create(Guid tenantId, Guid userId, string platform, string returnOrigin);

    /// Null when the state is forged, expired, for a different platform, or
    /// already used.
    OAuthState? Consume(string? state, string platform);
}

/// The provider callback is anonymous - the browser arrives from facebook.com
/// or tiktok.com with no bearer token - so the tenant it belongs to has to
/// travel inside `state`, and `state` therefore has to be unforgeable.
/// HMAC-SHA256 over the payload with a key derived from configuration, a
/// ten-minute expiry, and a single-use nonce so a leaked callback URL cannot
/// be replayed to attach someone's page to another business.
public sealed class OAuthStateProtector : IOAuthStateProtector
{
    private static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(10);
    private readonly byte[] _key;
    private readonly IMemoryCache _used;

    public OAuthStateProtector(IConfiguration config, IMemoryCache cache)
    {
        var material = config["Social:StateKey"];
        if (string.IsNullOrWhiteSpace(material)) material = config["Jwt:Key"];
        if (string.IsNullOrWhiteSpace(material))
            throw new InvalidOperationException("Social:StateKey or Jwt:Key must be configured.");
        _key = SHA256.HashData(Encoding.UTF8.GetBytes("unify-social-oauth-state:" + material));
        _used = cache;
    }

    public string Create(Guid tenantId, Guid userId, string platform, string returnOrigin)
    {
        var state = new OAuthState(
            tenantId, userId, platform, returnOrigin,
            Convert.ToHexString(RandomNumberGenerator.GetBytes(16)),
            DateTimeOffset.UtcNow.Add(Lifetime).ToUnixTimeSeconds());
        var payload = Base64Url(JsonSerializer.SerializeToUtf8Bytes(state));
        return payload + "." + Base64Url(Sign(payload));
    }

    public OAuthState? Consume(string? state, string platform)
    {
        if (string.IsNullOrWhiteSpace(state) || state.Length > 2048) return null;
        var dot = state.IndexOf('.');
        if (dot <= 0 || dot == state.Length - 1) return null;

        var payload = state[..dot];
        byte[] signature;
        try { signature = FromBase64Url(state[(dot + 1)..]); }
        catch (FormatException) { return null; }
        if (!CryptographicOperations.FixedTimeEquals(signature, Sign(payload))) return null;

        OAuthState? parsed;
        try { parsed = JsonSerializer.Deserialize<OAuthState>(FromBase64Url(payload)); }
        catch (Exception e) when (e is JsonException or FormatException) { return null; }
        if (parsed == null) return null;
        if (!string.Equals(parsed.Platform, platform, StringComparison.Ordinal)) return null;
        if (DateTimeOffset.UtcNow.ToUnixTimeSeconds() > parsed.ExpiresAtUnix) return null;

        var key = "social-oauth-nonce:" + parsed.Nonce;
        lock (_used)
        {
            if (_used.TryGetValue(key, out _)) return null;
            _used.Set(key, true, Lifetime + TimeSpan.FromMinutes(1));
        }
        return parsed;
    }

    private byte[] Sign(string payload) => HMACSHA256.HashData(_key, Encoding.ASCII.GetBytes(payload));

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static byte[] FromBase64Url(string value)
    {
        var s = value.Replace('-', '+').Replace('_', '/');
        s += (s.Length % 4) switch { 2 => "==", 3 => "=", 0 => "", _ => throw new FormatException() };
        return Convert.FromBase64String(s);
    }
}
