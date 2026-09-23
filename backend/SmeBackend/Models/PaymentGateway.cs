namespace SmeBackend.Models;

/// A tenant's credentials for one payment provider. Secrets are stored
/// encrypted (IPlatformSecretProtector) and never returned by the API - the
/// settings screen only ever sees a masked hint.
public class PaymentGateway : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }

    public string Name { get; set; } = string.Empty;

    /// Stripe | PayPal | Manual
    public string Provider { get; set; } = string.Empty;

    public string Currency { get; set; } = "LKR";

    public bool IsActive { get; set; } = true;

    public bool IsTestMode { get; set; } = true;

    /// Stripe publishable key / PayPal client id - safe to hand to a client.
    public string? PublicKey { get; set; }

    /// Stripe secret key / PayPal client secret, encrypted.
    public string? ApiKeyEncrypted { get; set; }

    /// Stripe webhook signing secret / PayPal webhook id, encrypted.
    public string? WebhookSecretEncrypted { get; set; }

    /// The URL the provider should call - shown on the settings screen so it
    /// can be pasted into the provider's dashboard.
    public string? WebhookUrl { get; set; }

    public string? ConfigurationJson { get; set; }
}
