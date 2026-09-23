using System.Globalization;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using SmeBackend.Models;

namespace SmeBackend.Services.Billing;

public static class PaymentProviders
{
    public const string Stripe = "Stripe";
    public const string PayPal = "PayPal";
    /// The built-in sandbox: no external call, the payment screen confirms
    /// (or fails) the payment itself. Used when a tenant has no gateway.
    public const string Manual = "Manual";

    public static readonly string[] All = { Stripe, PayPal, Manual };

    public static string? Normalize(string? provider) =>
        All.FirstOrDefault(p => p.Equals(provider?.Trim(), StringComparison.OrdinalIgnoreCase));
}

public sealed record GatewayCredentials(
    string Provider,
    string? SecretKey,
    string? PublicKey,
    string? WebhookSecret,
    bool IsTestMode);

public sealed record CheckoutIntent(
    Guid PaymentId,
    Guid InvoiceId,
    string InvoiceNumber,
    decimal Amount,
    string Currency,
    string Method,
    string? ReturnUrl);

public sealed record ProcessorCheckout(
    string ExternalId,
    string Status,
    string? ClientSecret,
    string? RedirectUrl,
    string RawResponse,
    bool Simulated);

public sealed record WebhookEvent(string ExternalId, string Status, string EventType);

public sealed class PaymentProviderException : Exception
{
    public PaymentProviderException(string message) : base(message) { }
}

public sealed class WebhookSignatureException : Exception
{
    public WebhookSignatureException(string message) : base(message) { }
}

public interface IPaymentProcessor
{
    string Provider { get; }
    Task<ProcessorCheckout> CreateCheckoutAsync(GatewayCredentials credentials, CheckoutIntent intent, CancellationToken ct = default);
    /// Reads the payment's current state back from the provider (and, for
    /// PayPal, captures an approved order). Returns a PaymentStatuses value.
    Task<string> RefreshStatusAsync(GatewayCredentials credentials, string externalId, CancellationToken ct = default);
    /// Verifies the webhook's signature and extracts the payment it is about.
    /// Returns null for event types that do not change a payment.
    Task<WebhookEvent?> ParseWebhookAsync(GatewayCredentials credentials, string body, IReadOnlyDictionary<string, string> headers, CancellationToken ct = default);
    Task<(bool Ok, string Message)> TestConnectionAsync(GatewayCredentials credentials, CancellationToken ct = default);
}

public interface IPaymentProcessorFactory
{
    IPaymentProcessor Get(string provider);
}

public sealed class PaymentProcessorFactory : IPaymentProcessorFactory
{
    private readonly IReadOnlyDictionary<string, IPaymentProcessor> _processors;

    public PaymentProcessorFactory(IEnumerable<IPaymentProcessor> processors) =>
        _processors = processors.ToDictionary(p => p.Provider, StringComparer.OrdinalIgnoreCase);

    public IPaymentProcessor Get(string provider) =>
        _processors.TryGetValue(provider, out var p)
            ? p
            : throw new PaymentProviderException($"Unsupported payment provider '{provider}'.");
}

/// Stripe PaymentIntents over the REST API (no SDK): the app confirms the
/// intent client-side with the client_secret, Stripe tells us the outcome by
/// webhook, and RefreshStatusAsync is the polling fallback.
public sealed class StripePaymentProcessor : IPaymentProcessor
{
    private const string BaseUrl = "https://api.stripe.com/v1/";
    private static readonly HashSet<string> ZeroDecimal = new(StringComparer.OrdinalIgnoreCase)
    {
        "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF",
    };
    private static readonly TimeSpan SignatureTolerance = TimeSpan.FromMinutes(5);

    private readonly IHttpClientFactory _http;
    public StripePaymentProcessor(IHttpClientFactory http) => _http = http;
    public string Provider => PaymentProviders.Stripe;

    public static long ToMinorUnits(decimal amount, string currency) =>
        ZeroDecimal.Contains(currency)
            ? (long)Math.Round(amount, 0, MidpointRounding.AwayFromZero)
            : (long)Math.Round(amount * 100m, 0, MidpointRounding.AwayFromZero);

    public async Task<ProcessorCheckout> CreateCheckoutAsync(GatewayCredentials c, CheckoutIntent intent, CancellationToken ct = default)
    {
        var form = new Dictionary<string, string>
        {
            ["amount"] = ToMinorUnits(intent.Amount, intent.Currency).ToString(CultureInfo.InvariantCulture),
            ["currency"] = intent.Currency.ToLowerInvariant(),
            ["description"] = $"Invoice {intent.InvoiceNumber}",
            ["metadata[invoice_id]"] = intent.InvoiceId.ToString(),
            ["metadata[payment_id]"] = intent.PaymentId.ToString(),
            ["automatic_payment_methods[enabled]"] = "true",
        };
        using var doc = await SendAsync(c, HttpMethod.Post, "payment_intents", form, intent.PaymentId.ToString(), ct);
        var root = doc.RootElement;
        return new ProcessorCheckout(
            root.GetProperty("id").GetString()!,
            MapStatus(root.GetProperty("status").GetString()),
            root.TryGetProperty("client_secret", out var secret) ? secret.GetString() : null,
            null,
            root.GetRawText(),
            false);
    }

    public async Task<string> RefreshStatusAsync(GatewayCredentials c, string externalId, CancellationToken ct = default)
    {
        using var doc = await SendAsync(c, HttpMethod.Get, $"payment_intents/{Uri.EscapeDataString(externalId)}", null, null, ct);
        return MapStatus(doc.RootElement.GetProperty("status").GetString());
    }

    public Task<WebhookEvent?> ParseWebhookAsync(GatewayCredentials c, string body, IReadOnlyDictionary<string, string> headers, CancellationToken ct = default)
    {
        if (string.IsNullOrEmpty(c.WebhookSecret))
            throw new WebhookSignatureException("No Stripe webhook signing secret is configured.");
        headers.TryGetValue("Stripe-Signature", out var signature);
        VerifySignature(body, signature, c.WebhookSecret, DateTimeOffset.UtcNow);

        using var doc = JsonDocument.Parse(body);
        var type = doc.RootElement.GetProperty("type").GetString() ?? "";
        var obj = doc.RootElement.GetProperty("data").GetProperty("object");
        var id = obj.TryGetProperty("id", out var idProp) ? idProp.GetString() : null;

        WebhookEvent? evt = type switch
        {
            "payment_intent.succeeded" when id is not null => new(id, PaymentStatuses.Succeeded, type),
            "payment_intent.payment_failed" when id is not null => new(id, PaymentStatuses.Failed, type),
            "payment_intent.canceled" when id is not null => new(id, PaymentStatuses.Failed, type),
            _ => null,
        };
        return Task.FromResult(evt);
    }

    public async Task<(bool Ok, string Message)> TestConnectionAsync(GatewayCredentials c, CancellationToken ct = default)
    {
        using var doc = await SendAsync(c, HttpMethod.Get, "balance", null, null, ct);
        var live = doc.RootElement.TryGetProperty("livemode", out var lm) && lm.GetBoolean();
        return (true, $"Connected to Stripe ({(live ? "live" : "test")} mode).");
    }

    /// Stripe-Signature: t=timestamp,v1=hex(HMAC_SHA256(secret, "t.body")).
    public static void VerifySignature(string body, string? header, string secret, DateTimeOffset now)
    {
        if (string.IsNullOrWhiteSpace(header))
            throw new WebhookSignatureException("Missing Stripe-Signature header.");

        string? timestamp = null;
        var signatures = new List<string>();
        foreach (var part in header.Split(','))
        {
            var kv = part.Split('=', 2);
            if (kv.Length != 2) continue;
            if (kv[0] == "t") timestamp = kv[1];
            else if (kv[0] == "v1") signatures.Add(kv[1]);
        }

        if (timestamp is null || signatures.Count == 0 || !long.TryParse(timestamp, out var unix))
            throw new WebhookSignatureException("Malformed Stripe-Signature header.");
        if ((now - DateTimeOffset.FromUnixTimeSeconds(unix)).Duration() > SignatureTolerance)
            throw new WebhookSignatureException("Stripe webhook timestamp is outside the tolerance window.");

        var expected = ComputeSignature(timestamp, body, secret);
        var expectedBytes = Encoding.ASCII.GetBytes(expected);
        if (!signatures.Any(s => CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(s), expectedBytes)))
            throw new WebhookSignatureException("Stripe webhook signature does not match.");
    }

    public static string ComputeSignature(string timestamp, string body, string secret)
    {
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
        return Convert.ToHexString(hmac.ComputeHash(Encoding.UTF8.GetBytes($"{timestamp}.{body}"))).ToLowerInvariant();
    }

    public static string MapStatus(string? stripeStatus) => stripeStatus switch
    {
        "succeeded" => PaymentStatuses.Succeeded,
        "canceled" => PaymentStatuses.Failed,
        _ => PaymentStatuses.Pending,
    };

    private async Task<JsonDocument> SendAsync(GatewayCredentials c, HttpMethod method, string path,
        Dictionary<string, string>? form, string? idempotencyKey, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(c.SecretKey))
            throw new PaymentProviderException("The Stripe secret key is not configured.");

        using var request = new HttpRequestMessage(method, BaseUrl + path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", c.SecretKey);
        if (idempotencyKey is not null) request.Headers.Add("Idempotency-Key", idempotencyKey);
        if (form is not null) request.Content = new FormUrlEncodedContent(form);

        using var response = await _http.CreateClient(BillingHttp.ClientName).SendAsync(request, ct);
        var text = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
            throw new PaymentProviderException($"Stripe returned {(int)response.StatusCode}: {ExtractError(text)}");
        return JsonDocument.Parse(text);
    }

    private static string ExtractError(string text)
    {
        try
        {
            using var doc = JsonDocument.Parse(text);
            return doc.RootElement.GetProperty("error").GetProperty("message").GetString() ?? text;
        }
        catch
        {
            return text.Length > 200 ? text[..200] : text;
        }
    }
}

/// PayPal Orders v2: create an order, send the customer to its approve link,
/// capture once approved (on return, by webhook, or by polling).
public sealed class PayPalPaymentProcessor : IPaymentProcessor
{
    private readonly IHttpClientFactory _http;
    public PayPalPaymentProcessor(IHttpClientFactory http) => _http = http;
    public string Provider => PaymentProviders.PayPal;

    private static string BaseUrl(GatewayCredentials c) =>
        c.IsTestMode ? "https://api-m.sandbox.paypal.com/" : "https://api-m.paypal.com/";

    public async Task<ProcessorCheckout> CreateCheckoutAsync(GatewayCredentials c, CheckoutIntent intent, CancellationToken ct = default)
    {
        var token = await GetAccessTokenAsync(c, ct);
        var body = new
        {
            intent = "CAPTURE",
            purchase_units = new[]
            {
                new
                {
                    reference_id = intent.PaymentId.ToString(),
                    custom_id = intent.InvoiceId.ToString(),
                    description = $"Invoice {intent.InvoiceNumber}",
                    amount = new
                    {
                        currency_code = intent.Currency.ToUpperInvariant(),
                        value = intent.Amount.ToString("0.00", CultureInfo.InvariantCulture),
                    },
                },
            },
            application_context = new
            {
                return_url = intent.ReturnUrl ?? "https://example.invalid/paypal/return",
                cancel_url = intent.ReturnUrl ?? "https://example.invalid/paypal/cancel",
                user_action = "PAY_NOW",
            },
        };

        using var doc = await SendJsonAsync(c, token, HttpMethod.Post, "v2/checkout/orders", body, intent.PaymentId.ToString(), ct);
        var root = doc.RootElement;
        string? approve = null;
        if (root.TryGetProperty("links", out var links))
        {
            foreach (var link in links.EnumerateArray())
            {
                var rel = link.GetProperty("rel").GetString();
                if (rel is "approve" or "payer-action") approve = link.GetProperty("href").GetString();
            }
        }

        return new ProcessorCheckout(root.GetProperty("id").GetString()!, PaymentStatuses.Pending, null, approve, root.GetRawText(), false);
    }

    public async Task<string> RefreshStatusAsync(GatewayCredentials c, string externalId, CancellationToken ct = default)
    {
        var token = await GetAccessTokenAsync(c, ct);
        using var doc = await SendJsonAsync(c, token, HttpMethod.Get, $"v2/checkout/orders/{Uri.EscapeDataString(externalId)}", null, null, ct);
        var status = doc.RootElement.GetProperty("status").GetString();
        if (status == "APPROVED")
        {
            using var captured = await SendJsonAsync(c, token, HttpMethod.Post,
                $"v2/checkout/orders/{Uri.EscapeDataString(externalId)}/capture", new { }, $"capture-{externalId}", ct);
            status = captured.RootElement.GetProperty("status").GetString();
        }
        return MapStatus(status);
    }

    public async Task<WebhookEvent?> ParseWebhookAsync(GatewayCredentials c, string body, IReadOnlyDictionary<string, string> headers, CancellationToken ct = default)
    {
        if (string.IsNullOrEmpty(c.WebhookSecret))
            throw new WebhookSignatureException("No PayPal webhook id is configured.");

        string H(string name) => headers.TryGetValue(name, out var v) ? v : throw new WebhookSignatureException($"Missing {name} header.");

        var token = await GetAccessTokenAsync(c, ct);
        using var eventDoc = JsonDocument.Parse(body);
        var verification = new
        {
            auth_algo = H("PAYPAL-AUTH-ALGO"),
            cert_url = H("PAYPAL-CERT-URL"),
            transmission_id = H("PAYPAL-TRANSMISSION-ID"),
            transmission_sig = H("PAYPAL-TRANSMISSION-SIG"),
            transmission_time = H("PAYPAL-TRANSMISSION-TIME"),
            webhook_id = c.WebhookSecret,
            webhook_event = eventDoc.RootElement,
        };
        using var verified = await SendJsonAsync(c, token, HttpMethod.Post, "v1/notifications/verify-webhook-signature", verification, null, ct);
        if (verified.RootElement.GetProperty("verification_status").GetString() != "SUCCESS")
            throw new WebhookSignatureException("PayPal could not verify the webhook signature.");

        var type = eventDoc.RootElement.GetProperty("event_type").GetString() ?? "";
        var resource = eventDoc.RootElement.GetProperty("resource");
        string? orderId = type.StartsWith("CHECKOUT.ORDER")
            ? resource.GetProperty("id").GetString()
            : resource.TryGetProperty("supplementary_data", out var sd) &&
              sd.TryGetProperty("related_ids", out var rel) &&
              rel.TryGetProperty("order_id", out var oid)
                ? oid.GetString()
                : null;
        if (orderId is null) return null;

        return type switch
        {
            // Approved but not captured yet: capture now so the money moves.
            "CHECKOUT.ORDER.APPROVED" => new WebhookEvent(orderId, await RefreshStatusAsync(c, orderId, ct), type),
            "PAYMENT.CAPTURE.COMPLETED" => new WebhookEvent(orderId, PaymentStatuses.Succeeded, type),
            "PAYMENT.CAPTURE.DENIED" or "PAYMENT.CAPTURE.DECLINED" => new WebhookEvent(orderId, PaymentStatuses.Failed, type),
            "PAYMENT.CAPTURE.REFUNDED" => new WebhookEvent(orderId, PaymentStatuses.Refunded, type),
            _ => null,
        };
    }

    public async Task<(bool Ok, string Message)> TestConnectionAsync(GatewayCredentials c, CancellationToken ct = default)
    {
        await GetAccessTokenAsync(c, ct);
        return (true, $"Connected to PayPal ({(c.IsTestMode ? "sandbox" : "live")}).");
    }

    public static string MapStatus(string? paypalStatus) => paypalStatus switch
    {
        "COMPLETED" => PaymentStatuses.Succeeded,
        "VOIDED" => PaymentStatuses.Failed,
        _ => PaymentStatuses.Pending,
    };

    private async Task<string> GetAccessTokenAsync(GatewayCredentials c, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(c.PublicKey) || string.IsNullOrWhiteSpace(c.SecretKey))
            throw new PaymentProviderException("The PayPal client id and secret are not configured.");

        using var request = new HttpRequestMessage(HttpMethod.Post, BaseUrl(c) + "v1/oauth2/token");
        request.Headers.Authorization = new AuthenticationHeaderValue("Basic",
            Convert.ToBase64String(Encoding.UTF8.GetBytes($"{c.PublicKey}:{c.SecretKey}")));
        request.Content = new FormUrlEncodedContent(new Dictionary<string, string> { ["grant_type"] = "client_credentials" });

        using var response = await _http.CreateClient(BillingHttp.ClientName).SendAsync(request, ct);
        var text = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
            throw new PaymentProviderException($"PayPal authentication failed ({(int)response.StatusCode}).");
        using var doc = JsonDocument.Parse(text);
        return doc.RootElement.GetProperty("access_token").GetString()!;
    }

    private async Task<JsonDocument> SendJsonAsync(GatewayCredentials c, string token, HttpMethod method, string path,
        object? body, string? requestId, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(method, BaseUrl(c) + path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (requestId is not null) request.Headers.Add("PayPal-Request-Id", requestId);
        if (body is not null)
            request.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

        using var response = await _http.CreateClient(BillingHttp.ClientName).SendAsync(request, ct);
        var text = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
            throw new PaymentProviderException($"PayPal returned {(int)response.StatusCode}: {(text.Length > 200 ? text[..200] : text)}");
        return JsonDocument.Parse(string.IsNullOrWhiteSpace(text) ? "{}" : text);
    }
}

/// The sandbox: no provider call at all. The payment stays Pending until
/// the payment screen confirms it, which is how the mobile Card/QR flow can
/// be demonstrated end to end without real credentials.
public sealed class ManualPaymentProcessor : IPaymentProcessor
{
    public string Provider => PaymentProviders.Manual;

    public Task<ProcessorCheckout> CreateCheckoutAsync(GatewayCredentials c, CheckoutIntent intent, CancellationToken ct = default)
    {
        var id = $"SIM-{intent.PaymentId.ToString("N")[..12].ToUpperInvariant()}";
        var raw = JsonSerializer.Serialize(new { id, simulated = true, intent.Method, intent.Amount, intent.Currency });
        return Task.FromResult(new ProcessorCheckout(id, PaymentStatuses.Pending, null, null, raw, true));
    }

    public Task<string> RefreshStatusAsync(GatewayCredentials c, string externalId, CancellationToken ct = default) =>
        Task.FromResult(PaymentStatuses.Pending);

    public Task<WebhookEvent?> ParseWebhookAsync(GatewayCredentials c, string body, IReadOnlyDictionary<string, string> headers, CancellationToken ct = default) =>
        throw new WebhookSignatureException("The sandbox provider does not receive webhooks.");

    public Task<(bool Ok, string Message)> TestConnectionAsync(GatewayCredentials c, CancellationToken ct = default) =>
        Task.FromResult((true, "The sandbox provider needs no connection."));
}

public static class BillingHttp
{
    public const string ClientName = "billing-integrations";
}
