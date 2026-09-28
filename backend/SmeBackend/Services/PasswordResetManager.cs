using System.Collections.Concurrent;
using System.Net;
using System.Net.Mail;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace SmeBackend.Services;

public interface IPasswordResetManager
{
    Task<bool> GenerateResetCodeAsync(string email);
    bool VerifyAndConsumeCode(string email, string code);
}

public class PasswordResetManager : IPasswordResetManager
{
    private readonly IConfiguration _config;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<PasswordResetManager> _logger;
    private readonly ConcurrentDictionary<string, ResetEntry> _entries = new(StringComparer.OrdinalIgnoreCase);

    public PasswordResetManager(
        IConfiguration config,
        IHttpClientFactory httpClientFactory,
        ILogger<PasswordResetManager> logger)
    {
        _config = config;
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    private record ResetEntry(string Code, DateTime ExpiresAt, int AttemptsRemaining);

    public async Task<bool> GenerateResetCodeAsync(string email)
    {
        var cleanEmail = email.Trim();
        // 6-digit cryptographically sound verification code
        var code = RandomNumberGenerator.GetInt32(100000, 1000000).ToString("D6");
        var expiresAt = DateTime.UtcNow.AddMinutes(15);

        // Do not make an undelivered code usable. A reset starts only after
        // the mail provider has accepted the message.
        var sent = await SendRealEmailAsync(cleanEmail, code);

        if (!sent)
        {
            _logger.LogWarning(
                "Password reset email could not be delivered to {Email}; check SMTP/SendGrid configuration and provider logs.",
                cleanEmail);
            return false;
        }

        _entries[cleanEmail] = new ResetEntry(code, expiresAt, 5);
        return true;
    }

    public bool VerifyAndConsumeCode(string email, string code)
    {
        var cleanEmail = email.Trim();
        var cleanCode = code.Trim();

        if (!_entries.TryGetValue(cleanEmail, out var entry))
        {
            return false;
        }

        if (DateTime.UtcNow > entry.ExpiresAt)
        {
            _entries.TryRemove(cleanEmail, out _);
            return false;
        }

        if (entry.AttemptsRemaining <= 0)
        {
            _entries.TryRemove(cleanEmail, out _);
            return false;
        }

        if (string.Equals(entry.Code, cleanCode, StringComparison.Ordinal))
        {
            _entries.TryRemove(cleanEmail, out _);
            return true;
        }

        // Decrement remaining attempts on wrong code to prevent brute force
        _entries[cleanEmail] = entry with { AttemptsRemaining = entry.AttemptsRemaining - 1 };
        return false;
    }

    private async Task<bool> SendRealEmailAsync(string toEmail, string code)
    {
        var htmlBody = BuildResetEmailHtml(code);
        var subject = $"Your Unify Password Reset Code: {code}";

        // 1. Try SendGrid if configured
        var sendGridKey = GetConfiguredValue("Integrations:SendGrid:ApiKey", "SENDGRID_API_KEY");
        var sendGridFrom = GetConfiguredValue("Integrations:SendGrid:FromEmail", "SENDGRID_FROM_EMAIL");
        if (!string.IsNullOrWhiteSpace(sendGridKey) && !string.IsNullOrWhiteSpace(sendGridFrom))
        {
            try
            {
                var success = await SendViaSendGridAsync(sendGridKey, sendGridFrom, toEmail, subject, htmlBody);
                if (success)
                {
                    _logger.LogInformation("[SENDGRID EMAIL SENT] Verification code successfully sent to {Email}", toEmail);
                    return true;
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "[SENDGRID FAILED] Attempting SMTP fallback for {Email}", toEmail);
            }
        }

        // 2. Try Standard SMTP (e.g. Gmail, Brevo, Outlook, etc.)
        var smtpHost = GetConfiguredValue("Smtp:Host", "SMTP_HOST") ?? "smtp.gmail.com";
        var smtpPortStr = GetConfiguredValue("Smtp:Port", "SMTP_PORT") ?? "587";
        _ = int.TryParse(smtpPortStr, out var smtpPort);
        if (smtpPort == 0) smtpPort = 587;

        var smtpUser = GetConfiguredValue("Smtp:User", "SMTP_USER");
        var smtpPass = GetConfiguredValue("Smtp:Password", "SMTP_PASSWORD", "SMTP_PASS");
        var fromEmail = GetConfiguredValue("Smtp:FromEmail", "SMTP_FROM") ?? smtpUser;
        var fromName = GetConfiguredValue("Smtp:FromName") ?? "Unify Workspace";

        if (!string.IsNullOrWhiteSpace(smtpHost) && !string.IsNullOrWhiteSpace(smtpUser) && !string.IsNullOrWhiteSpace(smtpPass))
        {
            try
            {
                using var client = new SmtpClient(smtpHost, smtpPort)
                {
                    EnableSsl = true,
                    UseDefaultCredentials = false,
                    Credentials = new NetworkCredential(smtpUser, smtpPass),
                    DeliveryMethod = SmtpDeliveryMethod.Network,
                    Timeout = 15000
                };

                using var mail = new MailMessage
                {
                    From = new MailAddress(fromEmail ?? smtpUser!, fromName),
                    Subject = subject,
                    Body = htmlBody,
                    IsBodyHtml = true
                };
                mail.To.Add(toEmail);

                await client.SendMailAsync(mail);
                _logger.LogInformation("[SMTP EMAIL SENT] Successfully sent verification email to {Email} via {Host}:{Port}", toEmail, smtpHost, smtpPort);
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[SMTP SEND ERROR] Failed sending reset email to {Email} via {Host}:{Port}", toEmail, smtpHost, smtpPort);
                return false;
            }
        }

        _logger.LogWarning(
            "[NO EMAIL PROVIDER CONFIGURED] No SMTP or SendGrid sender credentials were found in configuration or environment variables. " +
            "Configure SMTP_USER and SMTP_PASSWORD (or the corresponding Smtp settings) to send reset emails to {Email}.",
            toEmail);
        return false;
    }

    private async Task<bool> SendViaSendGridAsync(string apiKey, string fromEmail, string toEmail, string subject, string html)
    {
        var payload = new Dictionary<string, object?>
        {
            ["personalizations"] = new[] { new { to = new[] { new { email = toEmail } } } },
            ["from"] = new { email = fromEmail, name = _config["Integrations:SendGrid:FromName"] ?? "Unify Workspace" },
            ["subject"] = subject,
            ["content"] = new[] { new { type = "text/html", value = html } },
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.sendgrid.com/v3/mail/send");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

        var client = _httpClientFactory.CreateClient();
        using var response = await client.SendAsync(request);
        return response.IsSuccessStatusCode;
    }

    private string? GetConfiguredValue(string key, params string[] environmentVariableNames)
    {
        var configuredValue = _config[key];
        if (!string.IsNullOrWhiteSpace(configuredValue))
        {
            return configuredValue;
        }

        foreach (var variableName in environmentVariableNames)
        {
            var environmentValue = Environment.GetEnvironmentVariable(variableName);
            if (!string.IsNullOrWhiteSpace(environmentValue))
            {
                return environmentValue;
            }
        }

        return null;
    }

    private static string BuildResetEmailHtml(string code) =>
        $@"<!DOCTYPE html>
<html lang=""en"">
<head>
  <meta charset=""utf-8"" />
  <meta name=""viewport"" content=""width=device-width, initial-scale=1.0"" />
  <title>Password Reset Code</title>
  <style>
    body {{
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background-color: #f0f4f9;
      margin: 0;
      padding: 32px 16px;
      color: #0f172a;
    }}
    .container {{
      max-width: 520px;
      margin: 0 auto;
      background: #ffffff;
      border-radius: 20px;
      padding: 40px 32px;
      border: 1px solid #e2e8f0;
      box-shadow: 0 10px 30px -10px rgba(0, 0, 0, 0.08);
    }}
    .brand {{
      display: flex;
      align-items: center;
      gap: 10px;
      margin-bottom: 28px;
    }}
    .brand-name {{
      font-size: 24px;
      font-weight: 800;
      letter-spacing: -0.04em;
      color: #2563eb;
    }}
    .badge {{
      font-size: 10px;
      font-weight: 800;
      letter-spacing: 0.12em;
      padding: 3px 8px;
      border-radius: 999px;
      background: rgba(37, 99, 235, 0.1);
      color: #2563eb;
    }}
    h1 {{
      font-size: 22px;
      font-weight: 800;
      letter-spacing: -0.03em;
      color: #0f172a;
      margin: 0 0 12px;
    }}
    p {{
      font-size: 15px;
      line-height: 1.6;
      color: #475569;
      margin: 0 0 16px;
    }}
    .code-container {{
      background: linear-gradient(135deg, #f0fdf4 0%, #ecfdf5 100%);
      border: 2px dashed #10b981;
      border-radius: 16px;
      padding: 24px;
      text-align: center;
      margin: 28px 0;
    }}
    .code-label {{
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.14em;
      text-transform: uppercase;
      color: #059669;
      margin-bottom: 8px;
    }}
    .code-value {{
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 38px;
      font-weight: 900;
      letter-spacing: 8px;
      color: #047857;
      margin: 0;
      user-select: all;
    }}
    .security-note {{
      font-size: 13px;
      color: #64748b;
      line-height: 1.55;
      background: #f8fafc;
      border-radius: 10px;
      padding: 14px;
      border-left: 3px solid #2563eb;
    }}
    .footer {{
      margin-top: 36px;
      padding-top: 24px;
      border-top: 1px solid #f1f5f9;
      font-size: 12px;
      color: #94a3b8;
      text-align: center;
      line-height: 1.6;
    }}
  </style>
</head>
<body>
  <div class=""container"">
    <div class=""brand"">
      <span class=""brand-name"">unify</span>
      <span class=""badge"">WORKSPACE</span>
    </div>
    <h1>Reset your password</h1>
    <p>Hello,</p>
    <p>We received a request to reset your password for your Unify account. Use the verification code below to verify your identity and set a new password:</p>

    <div class=""code-container"">
      <div class=""code-label"">Your 6-Digit Code</div>
      <div class=""code-value"">{code}</div>
    </div>

    <div class=""security-note"">
      <strong>Security notice:</strong> This code is valid for <strong>15 minutes</strong>. Never share this code with anyone. Unify support will never ask for your verification code.
    </div>

    <p style=""margin-top: 20px; font-size: 14px;"">If you didn't request a password reset, you can safely ignore this email. Your current password remains unchanged.</p>

    <div class=""footer"">
      &copy; {DateTime.UtcNow.Year} Unify Systems Ltd. All rights reserved.<br />
      Bank-grade encryption &bull; Real-time operations platform
    </div>
  </div>
</body>
</html>";
}
