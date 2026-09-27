using System.Security.Cryptography;
using System.Text;

namespace SmeBackend.Services;

/// RFC 6238 time-based one-time passwords (the codes Google Authenticator,
/// Authy, 1Password and the like produce). Implemented directly rather than
/// through a package: it is thirty lines of HMAC-SHA1 and the project has no
/// other reason to pull an OTP library in.
///
/// Every check reports the 30-second step it matched so the caller can
/// refuse a second use of the same code (PlatformAdmin.LastAcceptedTotpStep).
public static class TotpService
{
    public const int Digits = 6;
    public const int StepSeconds = 30;
    private const string Base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

    /// 160-bit secret, Base32 encoded - the size every authenticator app
    /// expects and the size the RFC recommends for HMAC-SHA1.
    public static string GenerateSecret()
    {
        var bytes = RandomNumberGenerator.GetBytes(20);
        return Base32Encode(bytes);
    }

    public static string BuildProvisioningUri(string secret, string accountEmail, string issuer)
    {
        var label = Uri.EscapeDataString($"{issuer}:{accountEmail}");
        return $"otpauth://totp/{label}?secret={secret}&issuer={Uri.EscapeDataString(issuer)}&algorithm=SHA1&digits={Digits}&period={StepSeconds}";
    }

    public static long CurrentStep(DateTime utcNow) =>
        (long)Math.Floor((utcNow - DateTime.UnixEpoch).TotalSeconds / StepSeconds);

    /// Accepts the current step and one either side (clock drift on the
    /// phone), returning the step that matched so it can be burned.
    public static bool TryVerify(string secret, string code, DateTime utcNow, long lastAcceptedStep, out long matchedStep)
    {
        matchedStep = 0;
        code = new string((code ?? string.Empty).Where(char.IsDigit).ToArray());
        if (code.Length != Digits) return false;

        var key = Base32Decode(secret);
        var now = CurrentStep(utcNow);
        for (var offset = -1; offset <= 1; offset++)
        {
            var step = now + offset;
            if (step <= lastAcceptedStep) continue;
            var expected = Compute(key, step);
            if (CryptographicOperations.FixedTimeEquals(
                    Encoding.ASCII.GetBytes(expected), Encoding.ASCII.GetBytes(code)))
            {
                matchedStep = step;
                return true;
            }
        }
        return false;
    }

    private static string Compute(byte[] key, long step)
    {
        var counter = BitConverter.GetBytes(step);
        if (BitConverter.IsLittleEndian) Array.Reverse(counter);
        using var hmac = new HMACSHA1(key);
        var hash = hmac.ComputeHash(counter);
        var offset = hash[^1] & 0x0F;
        var binary = ((hash[offset] & 0x7F) << 24)
                   | ((hash[offset + 1] & 0xFF) << 16)
                   | ((hash[offset + 2] & 0xFF) << 8)
                   | (hash[offset + 3] & 0xFF);
        var otp = binary % (int)Math.Pow(10, Digits);
        return otp.ToString().PadLeft(Digits, '0');
    }

    public static string Base32Encode(byte[] data)
    {
        var sb = new StringBuilder((data.Length + 4) / 5 * 8);
        int bitBuffer = 0, bitCount = 0;
        foreach (var b in data)
        {
            bitBuffer = (bitBuffer << 8) | b;
            bitCount += 8;
            while (bitCount >= 5)
            {
                sb.Append(Base32Alphabet[(bitBuffer >> (bitCount - 5)) & 31]);
                bitCount -= 5;
            }
        }
        if (bitCount > 0) sb.Append(Base32Alphabet[(bitBuffer << (5 - bitCount)) & 31]);
        return sb.ToString();
    }

    public static byte[] Base32Decode(string text)
    {
        text = text.Trim().TrimEnd('=').ToUpperInvariant();
        var output = new List<byte>(text.Length * 5 / 8);
        int bitBuffer = 0, bitCount = 0;
        foreach (var c in text)
        {
            var value = Base32Alphabet.IndexOf(c);
            if (value < 0) throw new FormatException("Invalid Base32 character.");
            bitBuffer = (bitBuffer << 5) | value;
            bitCount += 5;
            if (bitCount >= 8)
            {
                output.Add((byte)((bitBuffer >> (bitCount - 8)) & 0xFF));
                bitCount -= 8;
            }
        }
        return output.ToArray();
    }
}
