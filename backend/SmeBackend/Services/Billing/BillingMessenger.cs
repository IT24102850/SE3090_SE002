using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using SmeBackend.DTOs;

namespace SmeBackend.Services.Billing;

public sealed record EmailAttachment(string FileName, string ContentType, byte[] Content);

public static class MessageChannels
{
    public const string Email = "Email";
    public const string Sms = "Sms";
    public const string WhatsApp = "WhatsApp";

    public static string? Normalize(string? channel) =>
        new[] { Email, Sms, WhatsApp }.FirstOrDefault(c => c.Equals(channel?.Trim(), StringComparison.OrdinalIgnoreCase));
}

/// Invoice/receipt email (SendGrid) and payment-reminder SMS/WhatsApp
/// (Twilio). Same contract as IReminderChannelSender's stub: when the
/// provider's credentials are not configured nothing is sent, the message
/// is logged, and the result says Simulated = true - the UI shows that
/// honestly instead of claiming a delivery that never happened.
public interface IBillingMessenger
{
    Task<MessageDeliveryResponse> SendEmailAsync(string to, string subject, string html,
        EmailAttachment? attachment = null, CancellationToken ct = default);

    Task<MessageDeliveryResponse> SendTextAsync(string channel, string to, string body, CancellationToken ct = default);
}

public sealed class BillingMessenger : IBillingMessenger
{
    private readonly IHttpClientFactory _http;
    private readonly IConfiguration _config;
    private readonly ILogger<BillingMessenger> _logger;

    public BillingMessenger(IHttpClientFactory http, IConfiguration config, ILogger<BillingMessenger> logger)
    {
        _http = http;
        _config = config;
        _logger = logger;
    }

    public async Task<MessageDeliveryResponse> SendEmailAsync(string to, string subject, string html,
        EmailAttachment? attachment = null, CancellationToken ct = default)
    {
        var apiKey = _config["Integrations:SendGrid:ApiKey"];
        var from = _config["Integrations:SendGrid:FromEmail"];
        if (string.IsNullOrWhiteSpace(apiKey) || string.IsNullOrWhiteSpace(from))
        {
            _logger.LogInformation("[STUB SendGrid] Would email {To}: {Subject} (attachment: {Attachment})",
                to, subject, attachment?.FileName ?? "none");
            return new MessageDeliveryResponse(MessageChannels.Email, to, false, true, null,
                "SendGrid is not configured on this server; the email was logged, not sent.");
        }

        var payload = new Dictionary<string, object?>
        {
            ["personalizations"] = new[] { new { to = new[] { new { email = to } } } },
            ["from"] = new { email = from, name = _config["Integrations:SendGrid:FromName"] ?? "Unify Billing" },
            ["subject"] = subject,
            ["content"] = new[] { new { type = "text/html", value = html } },
        };
        if (attachment is not null)
        {
            payload["attachments"] = new[]
            {
                new
                {
                    content = Convert.ToBase64String(attachment.Content),
                    filename = attachment.FileName,
                    type = attachment.ContentType,
                    disposition = "attachment",
                },
            };
        }

        using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.sendgrid.com/v3/mail/send");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

        try
        {
            using var response = await _http.CreateClient(BillingHttp.ClientName).SendAsync(request, ct);
            if (response.IsSuccessStatusCode)
            {
                var id = response.Headers.TryGetValues("X-Message-Id", out var values) ? values.FirstOrDefault() : null;
                return new MessageDeliveryResponse(MessageChannels.Email, to, true, false, id, null);
            }
            var error = await response.Content.ReadAsStringAsync(ct);
            _logger.LogWarning("SendGrid rejected email to {To}: {Status} {Error}", to, (int)response.StatusCode, error);
            return new MessageDeliveryResponse(MessageChannels.Email, to, false, false, null, $"SendGrid returned {(int)response.StatusCode}.");
        }
        catch (HttpRequestException ex)
        {
            _logger.LogWarning(ex, "SendGrid unreachable");
            return new MessageDeliveryResponse(MessageChannels.Email, to, false, false, null, "SendGrid could not be reached.");
        }
    }

    public async Task<MessageDeliveryResponse> SendTextAsync(string channel, string to, string body, CancellationToken ct = default)
    {
        var sid = _config["Integrations:Twilio:AccountSid"];
        var token = _config["Integrations:Twilio:AuthToken"];
        var from = channel == MessageChannels.WhatsApp
            ? _config["Integrations:Twilio:WhatsAppFrom"]
            : _config["Integrations:Twilio:FromNumber"];

        if (string.IsNullOrWhiteSpace(sid) || string.IsNullOrWhiteSpace(token) || string.IsNullOrWhiteSpace(from))
        {
            _logger.LogInformation("[STUB Twilio {Channel}] Would message {To}: {Body}", channel, to, body);
            return new MessageDeliveryResponse(channel, to, false, true, null,
                $"Twilio {channel} is not configured on this server; the message was logged, not sent.");
        }

        var prefix = channel == MessageChannels.WhatsApp ? "whatsapp:" : "";
        using var request = new HttpRequestMessage(HttpMethod.Post,
            $"https://api.twilio.com/2010-04-01/Accounts/{Uri.EscapeDataString(sid)}/Messages.json");
        request.Headers.Authorization = new AuthenticationHeaderValue("Basic",
            Convert.ToBase64String(Encoding.UTF8.GetBytes($"{sid}:{token}")));
        request.Content = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["To"] = prefix + to,
            ["From"] = from.StartsWith(prefix) ? from : prefix + from,
            ["Body"] = body,
        });

        try
        {
            using var response = await _http.CreateClient(BillingHttp.ClientName).SendAsync(request, ct);
            var text = await response.Content.ReadAsStringAsync(ct);
            if (response.IsSuccessStatusCode)
            {
                using var doc = JsonDocument.Parse(text);
                var messageSid = doc.RootElement.TryGetProperty("sid", out var s) ? s.GetString() : null;
                return new MessageDeliveryResponse(channel, to, true, false, messageSid, null);
            }
            _logger.LogWarning("Twilio rejected {Channel} to {To}: {Status} {Error}", channel, to, (int)response.StatusCode, text);
            return new MessageDeliveryResponse(channel, to, false, false, null, $"Twilio returned {(int)response.StatusCode}.");
        }
        catch (HttpRequestException ex)
        {
            _logger.LogWarning(ex, "Twilio unreachable");
            return new MessageDeliveryResponse(channel, to, false, false, null, "Twilio could not be reached.");
        }
    }
}
