using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace SmeBackend.Services;

public sealed record SmsResult(bool Delivered, bool Simulated, string? ProviderMessageId, string? Error);

public interface ISmsGateway
{
    Task<SmsResult> SendAsync(string toPhone, string message, CancellationToken ct = default);
}

/// SMS through text.lk.
///
/// Chosen over Twilio for SMS because the customers here are Sri Lankan: a
/// Twilio trial can only text numbers verified in its console, which makes a
/// live demo to a real guest impossible, and its per-message cost to Sri Lanka
/// is high. text.lk sends to any local number and bills locally. WhatsApp
/// stays on Twilio and email on SendGrid, so each channel uses the provider
/// that actually suits it.
///
/// Without a token the message is logged and reported as simulated, never as
/// sent - the same rule the rest of the reminder path follows.
public sealed class TextLkSmsGateway : ISmsGateway
{
    public const string ClientName = "text-lk";
    private const string SendUrl = "https://app.text.lk/api/v3/sms/send";

    private readonly IHttpClientFactory _http;
    private readonly IConfiguration _config;
    private readonly ILogger<TextLkSmsGateway> _logger;

    public TextLkSmsGateway(IHttpClientFactory http, IConfiguration config, ILogger<TextLkSmsGateway> logger)
    {
        _http = http;
        _config = config;
        _logger = logger;
    }

    public async Task<SmsResult> SendAsync(string toPhone, string message, CancellationToken ct = default)
    {
        var token = _config["Integrations:TextLk:ApiToken"];
        var senderId = _config["Integrations:TextLk:SenderId"];

        var recipient = NormaliseSriLankanNumber(toPhone);
        if (recipient is null)
            return new SmsResult(false, false, null, $"'{toPhone}' is not a usable Sri Lankan mobile number.");

        if (string.IsNullOrWhiteSpace(token) || string.IsNullOrWhiteSpace(senderId))
        {
            _logger.LogInformation("[SIMULATED SMS via text.lk] to {To}: {Message}", recipient, message);
            return new SmsResult(false, true, null,
                "text.lk is not configured on this server; the SMS was logged, not sent.");
        }

        var payload = JsonSerializer.Serialize(new
        {
            recipient,
            sender_id = senderId,
            type = "plain",
            message,
        });

        using var request = new HttpRequestMessage(HttpMethod.Post, SendUrl)
        {
            Content = new StringContent(payload, Encoding.UTF8, "application/json"),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        try
        {
            using var response = await _http.CreateClient(ClientName).SendAsync(request, ct);
            var body = await response.Content.ReadAsStringAsync(ct);

            // text.lk answers 200 with {"status":"error"} for a rejected
            // message, so the HTTP code alone is not the outcome.
            string? status = null, providerMessage = null, id = null;
            try
            {
                using var doc = JsonDocument.Parse(body);
                var root = doc.RootElement;
                status = root.TryGetProperty("status", out var s) ? s.GetString() : null;
                providerMessage = root.TryGetProperty("message", out var m) ? m.GetString() : null;
                if (root.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Object
                    && data.TryGetProperty("uid", out var uid))
                {
                    id = uid.GetString();
                }
            }
            catch (JsonException) { /* fall through to the status-code check */ }

            if (response.IsSuccessStatusCode && !string.Equals(status, "error", StringComparison.OrdinalIgnoreCase))
                return new SmsResult(true, false, id, null);

            _logger.LogWarning("text.lk rejected an SMS to {To}: {Status} {Message}",
                recipient, (int)response.StatusCode, providerMessage ?? body);
            return new SmsResult(false, false, null,
                providerMessage ?? $"text.lk returned {(int)response.StatusCode}.");
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            _logger.LogWarning(ex, "text.lk could not be reached.");
            return new SmsResult(false, false, null, "text.lk could not be reached.");
        }
    }

    /// text.lk wants a bare international number: 94 then the nine-digit
    /// mobile, no plus and no leading zero. Guests type all of
    /// "+94 77 123 4567", "0771234567" and "94771234567", so all three have to
    /// arrive at the same place.
    internal static string? NormaliseSriLankanNumber(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;

        var digits = new string(raw.Where(char.IsDigit).ToArray());
        if (digits.Length == 0) return null;

        if (digits.StartsWith("94") && digits.Length == 11) return digits;          // 94771234567
        if (digits.StartsWith("0") && digits.Length == 10) return "94" + digits[1..]; // 0771234567
        if (digits.Length == 9 && digits[0] == '7') return "94" + digits;            // 771234567

        // Anything else is either another country or a typo. Sending it
        // anyway would be billed and silently undelivered.
        return null;
    }
}
