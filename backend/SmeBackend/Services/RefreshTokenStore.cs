using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Services;

/// <summary>
/// Issues, rotates and revokes refresh tokens for the tenant apps (React and
/// Flutter). The platform console does not use them: its sessions are
/// server-side and deliberately short (PlatformAuthController).
///
/// - Issue: 64 random bytes, returned once; only the SHA-256 hash is stored.
/// - Rotate: a valid token is redeemed exactly once for a new access token
///   and a new refresh token, and the old one is revoked.
/// - Reuse detection: presenting a token that was already rotated means two
///   parties hold it - the legitimate client and a thief. Every token the user
///   has is revoked, so both must sign in again.
/// </summary>
public static class RefreshTokenStore
{
    public static readonly TimeSpan Lifetime = TimeSpan.FromDays(14);

    public static async Task<string> IssueAsync(AppDbContext db, Guid userId, CancellationToken ct = default)
    {
        var raw = Convert.ToBase64String(RandomNumberGenerator.GetBytes(64));
        db.RefreshTokens.Add(new RefreshToken
        {
            UserId = userId,
            TokenHash = Hash(raw),
            ExpiresAt = DateTime.UtcNow.Add(Lifetime),
        });
        await db.SaveChangesAsync(ct);
        return raw;
    }

    public sealed record Rotation(User User, string RefreshToken);

    /// <summary>Redeems <paramref name="raw"/>; null when it is unknown, expired, revoked or its user can no longer sign in.</summary>
    public static async Task<Rotation?> RotateAsync(AppDbContext db, string raw, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;

        var hash = Hash(raw);
        var stored = await db.RefreshTokens.IgnoreQueryFilters()
            .Include(t => t.User).ThenInclude(u => u.Tenant)
            .FirstOrDefaultAsync(t => t.TokenHash == hash, ct);
        if (stored is null) return null;

        if (stored.RevokedAt is not null)
        {
            if (stored.ReplacedByTokenHash is not null)
                await RevokeAllForUserAsync(db, stored.UserId, ct);
            return null;
        }

        var user = stored.User;
        if (stored.ExpiresAt <= DateTime.UtcNow || !user.IsActive || !user.Tenant.IsActive
            || user.Role == UserRole.SuperAdmin)
        {
            stored.RevokedAt = DateTime.UtcNow;
            await db.SaveChangesAsync(ct);
            return null;
        }

        var next = Convert.ToBase64String(RandomNumberGenerator.GetBytes(64));
        stored.RevokedAt = DateTime.UtcNow;
        stored.ReplacedByTokenHash = Hash(next);
        db.RefreshTokens.Add(new RefreshToken
        {
            UserId = user.Id,
            TokenHash = stored.ReplacedByTokenHash,
            ExpiresAt = DateTime.UtcNow.Add(Lifetime),
        });
        await db.SaveChangesAsync(ct);
        return new Rotation(user, next);
    }

    /// <summary>Sign-out: revokes this one token. Unknown tokens are ignored, so the call is idempotent.</summary>
    public static async Task RevokeAsync(AppDbContext db, string raw, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(raw)) return;
        var hash = Hash(raw);
        var stored = await db.RefreshTokens.IgnoreQueryFilters().FirstOrDefaultAsync(t => t.TokenHash == hash, ct);
        if (stored is { RevokedAt: null })
        {
            stored.RevokedAt = DateTime.UtcNow;
            await db.SaveChangesAsync(ct);
        }
    }

    /// <summary>Ends every session of a user - on password change, and on detected token reuse.</summary>
    public static async Task RevokeAllForUserAsync(AppDbContext db, Guid userId, CancellationToken ct = default)
    {
        var live = await db.RefreshTokens.IgnoreQueryFilters()
            .Where(t => t.UserId == userId && t.RevokedAt == null)
            .ToListAsync(ct);
        foreach (var token in live) token.RevokedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
    }

    internal static string Hash(string raw) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(raw)));
}
