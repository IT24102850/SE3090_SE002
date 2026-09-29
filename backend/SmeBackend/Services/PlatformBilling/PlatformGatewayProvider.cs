using SmeBackend.Models;
using SmeBackend.Services.Billing;

namespace SmeBackend.Services.PlatformBilling;

/// Unify's own merchant accounts - the ones tenants pay *us* through.
///
/// Kept strictly apart from Models/PaymentGateway.cs, which holds a tenant's
/// credentials for charging their own customers. Mixing the two would let a
/// subscription payment land in the tenant's Stripe account, which is the
/// single worst bug this feature could have. These credentials never come
/// from the database: they are configuration, so no tenant-facing code path
/// can read or rewrite them.
///
///   Platform:Billing:Currency        default currency for new subscriptions
///   Platform:Billing:TestMode        true unless explicitly set to false
///   Platform:Billing:Stripe:SecretKey / PublicKey / WebhookSecret
///   Platform:Billing:PayPal:ClientId / ClientSecret / WebhookId
///
/// With nothing configured the sandbox provider is used, exactly as the
/// tenant-facing billing engine does: the flow runs end to end and says
/// plainly that it was simulated, rather than pretending a card was charged.
public interface IPlatformGatewayProvider
{
    /// Providers that are usable right now, cheapest path first. Always
    /// contains at least Manual.
    IReadOnlyList<string> Available { get; }

    bool IsLive(string provider);

    GatewayCredentials Credentials(string provider);

    /// The provider to use when the caller did not choose one.
    string Default { get; }

    string DefaultCurrency { get; }
}

public sealed class PlatformGatewayProvider : IPlatformGatewayProvider
{
    private readonly IConfiguration _config;

    public PlatformGatewayProvider(IConfiguration config) => _config = config;

    private IConfigurationSection Section => _config.GetSection("Platform:Billing");

    public string DefaultCurrency
    {
        get
        {
            var configured = Section["Currency"];
            return string.IsNullOrWhiteSpace(configured) ? Data.PlatformPlanCatalog.DefaultCurrency : configured.Trim().ToUpperInvariant();
        }
    }

    private bool TestMode => !string.Equals(Section["TestMode"], "false", StringComparison.OrdinalIgnoreCase);

    public bool IsLive(string provider) => provider switch
    {
        PaymentProviders.Stripe => !string.IsNullOrWhiteSpace(Section["Stripe:SecretKey"]),
        PaymentProviders.PayPal => !string.IsNullOrWhiteSpace(Section["PayPal:ClientId"])
                                   && !string.IsNullOrWhiteSpace(Section["PayPal:ClientSecret"]),
        PaymentProviders.Manual => true,
        _ => false,
    };

    public IReadOnlyList<string> Available
    {
        get
        {
            var list = new List<string>();
            if (IsLive(PaymentProviders.Stripe)) list.Add(PaymentProviders.Stripe);
            if (IsLive(PaymentProviders.PayPal)) list.Add(PaymentProviders.PayPal);
            list.Add(PaymentProviders.Manual);
            return list;
        }
    }

    public string Default => Available[0];

    public GatewayCredentials Credentials(string provider) => provider switch
    {
        PaymentProviders.Stripe => new GatewayCredentials(
            PaymentProviders.Stripe,
            Section["Stripe:SecretKey"],
            Section["Stripe:PublicKey"],
            Section["Stripe:WebhookSecret"],
            TestMode),

        PaymentProviders.PayPal => new GatewayCredentials(
            PaymentProviders.PayPal,
            Section["PayPal:ClientSecret"],
            Section["PayPal:ClientId"],
            Section["PayPal:WebhookId"],
            TestMode),

        _ => new GatewayCredentials(PaymentProviders.Manual, null, null, null, true),
    };
}

/// Stripe will not take LKR, and most of the platform price list is in LKR.
/// The same trick the tenant-facing engine uses (Shared/PaymentSettlement)
/// applies here: the invoice stays in its own currency and settles on its
/// own Amount, while the card is charged the equivalent in a currency the
/// gateway accepts, at a rate that is recorded on the payment.
///
/// The rate is configuration, not a live feed, for the same reason the rest
/// of this codebase keeps it there: a subscription price that moves with the
/// market between the pricing page and the checkout is a support ticket.
///
///   Platform:Billing:SettlementCurrency   e.g. USD
///   Platform:Billing:Rates:LKR            units of LKR per 1 settlement unit
public sealed record PlatformSettlement(string Currency, decimal Rate)
{
    public decimal Convert(decimal amount) =>
        Math.Round(amount / Rate, 2, MidpointRounding.AwayFromZero);

    /// Null when the gateway can take the invoice currency as it stands.
    public static PlatformSettlement? For(IConfiguration config, string provider, string invoiceCurrency)
    {
        if (provider == PaymentProviders.Manual) return null;

        var section = config.GetSection("Platform:Billing");
        var settlementCurrency = section["SettlementCurrency"];
        if (string.IsNullOrWhiteSpace(settlementCurrency)) return null;
        settlementCurrency = settlementCurrency.Trim().ToUpperInvariant();
        if (string.Equals(settlementCurrency, invoiceCurrency, StringComparison.OrdinalIgnoreCase)) return null;

        if (!decimal.TryParse(section[$"Rates:{invoiceCurrency.ToUpperInvariant()}"],
                System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture, out var rate) || rate <= 0)
            return null;

        return new PlatformSettlement(settlementCurrency, rate);
    }
}
