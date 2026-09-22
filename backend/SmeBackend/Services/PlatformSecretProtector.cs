using System.Security.Cryptography;
using System.Text;

namespace SmeBackend.Services;

public interface IPlatformSecretProtector
{
    string Protect(string plaintext);
    string Unprotect(string ciphertext);
    /// SHA-256 of an opaque token - what gets stored so a database read never
    /// yields something that can be presented back to the server.
    string Hash(string token);
}

/// AES-256-GCM at rest for the platform owner's TOTP secret.
///
/// The key is derived from Platform:SecretKey, or from Jwt:Key when that is
/// not set, so a fresh deployment works without extra configuration while a
/// dedicated key can be dropped in later without code changes. It lives in
/// configuration, not the database, which is the point: a copy of the
/// database cannot mint MFA codes.
///
/// Not the ASP.NET Data Protection API on purpose - its default key ring
/// lives on the container's disk and is lost on every redeploy of a
/// stateless host, which would permanently lock the owner out.
public sealed class PlatformSecretProtector : IPlatformSecretProtector
{
    private const int NonceSize = 12;
    private const int TagSize = 16;
    private readonly byte[] _key;

    public PlatformSecretProtector(IConfiguration config)
    {
        var material = config["Platform:SecretKey"];
        if (string.IsNullOrWhiteSpace(material)) material = config["Jwt:Key"];
        if (string.IsNullOrWhiteSpace(material))
            throw new InvalidOperationException("Platform:SecretKey or Jwt:Key must be configured.");
        _key = SHA256.HashData(Encoding.UTF8.GetBytes("unify-platform-mfa:" + material));
    }

    public string Protect(string plaintext)
    {
        var nonce = RandomNumberGenerator.GetBytes(NonceSize);
        var plain = Encoding.UTF8.GetBytes(plaintext);
        var cipher = new byte[plain.Length];
        var tag = new byte[TagSize];
        using var aes = new AesGcm(_key, TagSize);
        aes.Encrypt(nonce, plain, cipher, tag);

        var packed = new byte[NonceSize + TagSize + cipher.Length];
        Buffer.BlockCopy(nonce, 0, packed, 0, NonceSize);
        Buffer.BlockCopy(tag, 0, packed, NonceSize, TagSize);
        Buffer.BlockCopy(cipher, 0, packed, NonceSize + TagSize, cipher.Length);
        return Convert.ToBase64String(packed);
    }

    public string Unprotect(string ciphertext)
    {
        var packed = Convert.FromBase64String(ciphertext);
        var nonce = packed.AsSpan(0, NonceSize);
        var tag = packed.AsSpan(NonceSize, TagSize);
        var cipher = packed.AsSpan(NonceSize + TagSize);
        var plain = new byte[cipher.Length];
        using var aes = new AesGcm(_key, TagSize);
        aes.Decrypt(nonce, cipher, tag, plain);
        return Encoding.UTF8.GetString(plain);
    }

    public string Hash(string token) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));
}
