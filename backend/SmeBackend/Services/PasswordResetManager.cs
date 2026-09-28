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
    bool VerifyCode(string email, string code);
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
        => CheckCode(email, code, consume: true);

    public bool VerifyCode(string email, string code)
        => CheckCode(email, code, consume: false);

    private bool CheckCode(string email, string code, bool consume)
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
            if (consume)
            {
                _entries.TryRemove(cleanEmail, out _);
            }
            return true;
        }

        // Decrement remaining attempts on wrong code to prevent brute force
        _entries[cleanEmail] = entry with { AttemptsRemaining = entry.AttemptsRemaining - 1 };
        return false;
    }

    private async Task<bool> SendRealEmailAsync(string toEmail, string code)
    {
        var htmlBody = BuildResetEmailHtml(code);
        var subject = "Your Unify password reset code";

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

                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(15));
                await client.SendMailAsync(mail, timeout.Token);
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
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        using var response = await client.SendAsync(request, timeout.Token);
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
  <meta name=""color-scheme"" content=""light"" />
  <title>Your Unify security code</title>
  <style>
    body {{ margin:0; padding:32px 14px; background:#eef3ff; color:#14213d; font-family:Arial,Helvetica,sans-serif; }}
    .shell {{ max-width:560px; margin:0 auto; background:#fff; border:1px solid #dce5f5; border-radius:24px; overflow:hidden; box-shadow:0 20px 60px rgba(29,62,122,.12); }}
    .top {{ padding:28px 36px; background:linear-gradient(125deg,#10234b,#1e4da2 68%,#2878e8); color:#fff; }}
    .brand {{ font-size:25px; font-weight:800; letter-spacing:-1.2px; }}
    .brand-mark {{ display:inline-block; margin-right:9px; width:28px; height:28px; line-height:28px; text-align:center; border-radius:9px; background:#fff; color:#2464d5; font-size:17px; }}
    .eyebrow {{ margin-top:23px; color:#b9d4ff; font-size:10px; font-weight:700; letter-spacing:2px; }}
    .content {{ padding:36px; }}
    h1 {{ margin:0 0 12px; font-size:27px; letter-spacing:-.8px; color:#14213d; }}
    p {{ margin:0 0 18px; color:#596b87; font-size:15px; line-height:1.7; }}
    .code-card {{ margin:26px 0; padding:22px; text-align:center; border:1px solid #dce8ff; border-radius:17px; background:linear-gradient(135deg,#f4f8ff,#edf4ff); }}
    .code-label {{ color:#63799e; font-size:10px; font-weight:700; letter-spacing:2px; text-transform:uppercase; }}
    .code-value {{ margin:10px 0 2px; color:#1e56c5; font-family:Consolas,monospace; font-size:39px; font-weight:800; letter-spacing:9px; }}
    .expiry {{ margin-top:8px; color:#687b99; font-size:12px; }}
    .notice {{ padding:14px 16px; border-left:3px solid #3b82f6; border-radius:8px; background:#f6f8fc; color:#586b87; font-size:13px; line-height:1.6; }}
    .footer {{ padding:20px 36px 25px; border-top:1px solid #edf1f7; color:#8794aa; font-size:11px; line-height:1.7; text-align:center; }}
    @media(max-width:480px) {{ body {{padding:16px 10px}} .top,.content {{padding:26px 22px}} .footer {{padding:18px 22px}} .code-value {{font-size:34px;letter-spacing:7px}} }}
  </style>
</head>
<body>
  <div class=""shell"">
    <div class=""top""><div class=""brand""><span class=""brand-mark"">u</span>unify</div><div class=""eyebrow"">ACCOUNT SECURITY · PASSWORD RESET</div></div>
    <div class=""content""><h1>Your reset code is ready</h1>
      <p>We received a request to change the password for your Unify account. Enter this one-time code in the recovery page to verify it’s you.</p>
      <div class=""code-card""><div class=""code-label"">Your verification code</div><div class=""code-value"">{code}</div><div class=""expiry"">Expires in 15 minutes</div></div>
      <div class=""notice""><strong>Keep this code private.</strong> Unify support will never ask you to share it. If you didn’t request a reset, ignore this message; your password has not changed.</div>
    </div>
    <div class=""footer"">Sent by Unify Workspace<br />Automated account security message · {DateTime.UtcNow.Year}</div>
  </div>
</body>
</html>";
}
