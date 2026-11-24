using SmeBackend.Models.Marketing;

namespace SmeBackend.Services.Marketing;

public interface ISocialTokenService
{
    /// A usable access token for the account, refreshing it first when the
    /// provider issues short-lived tokens (TikTok: 24h). Mutates the account
    /// when it refreshes; the caller saves. Throws a TokenInvalid
    /// SocialApiException when the account has to be reconnected.
    Task<string> GetAccessTokenAsync(SocialAccount account, CancellationToken ct);

    void MarkNeedsReconnect(SocialAccount account, string reason);
}

public sealed class SocialTokenService(IPlatformSecretProtector protector, ITikTokClient tikTok) : ISocialTokenService
{
    private static readonly TimeSpan RefreshMargin = TimeSpan.FromMinutes(10);

    public async Task<string> GetAccessTokenAsync(SocialAccount account, CancellationToken ct)
    {
        if (account.Status != SocialAccountStatus.Connected || string.IsNullOrEmpty(account.AccessTokenEncrypted))
            throw new SocialApiException($"{account.Platform} account \"{account.DisplayName}\" needs to be reconnected.", tokenInvalid: true);

        var token = Decrypt(account.AccessTokenEncrypted);

        if (account.Platform == SocialPlatform.TikTok
            && account.AccessTokenExpiresAt is { } expires
            && expires - RefreshMargin <= DateTime.UtcNow)
        {
            if (string.IsNullOrEmpty(account.RefreshTokenEncrypted)
                || (account.RefreshTokenExpiresAt is { } rexp && rexp <= DateTime.UtcNow))
                throw new SocialApiException("The TikTok session has expired. Reconnect the account.", tokenInvalid: true);

            var refreshed = await tikTok.RefreshAsync(Decrypt(account.RefreshTokenEncrypted!), ct);
            account.AccessTokenEncrypted = protector.Protect(refreshed.AccessToken);
            account.AccessTokenExpiresAt = refreshed.ExpiresAt;
            if (!string.IsNullOrEmpty(refreshed.RefreshToken))
            {
                account.RefreshTokenEncrypted = protector.Protect(refreshed.RefreshToken!);
                account.RefreshTokenExpiresAt = refreshed.RefreshExpiresAt;
            }
            account.UpdatedAt = DateTime.UtcNow;
            token = refreshed.AccessToken;
        }

        return token;
    }

    public void MarkNeedsReconnect(SocialAccount account, string reason)
    {
        account.Status = SocialAccountStatus.NeedsReconnect;
        account.LastError = Clip(reason, 1000);
        account.UpdatedAt = DateTime.UtcNow;
    }

    private string Decrypt(string cipher)
    {
        try
        {
            return protector.Unprotect(cipher);
        }
        catch (Exception e) when (e is FormatException or System.Security.Cryptography.CryptographicException)
        {
            // The server's secret key changed since the token was stored.
            throw new SocialApiException("The stored token can no longer be read (the server key changed). Reconnect the account.", tokenInvalid: true, inner: e);
        }
    }

    internal static string Clip(string value, int max) => value.Length <= max ? value : value[..max];
}
