using SmeBackend.Models;

namespace SmeBackend.Shared;

/// What a gateway is actually charged in, when that differs from what the
/// invoice is written in.
///
/// Stripe will not take LKR - Sri Lanka is not a supported country and the
/// currency is rejected outright - but a Sri Lankan operator still prices,
/// invoices and reports in rupees. So the invoice stays LKR and the card is
/// charged the equivalent in a currency the gateway accepts, at a rate the
/// operator sets and can be held to.
///
/// The rate is configuration, not a live feed, on purpose: a demo cannot
/// depend on an FX provider, and an operator who sets their own rate knows
/// exactly what a guest will be charged. What is charged, in which
/// currency, and at what rate is written onto the payment, so a receipt can
/// say "LKR 3,750 (USD 12.40 at 302.50)" and a reconciliation against a
/// Stripe payout can be done by hand.
///
/// Configured on the gateway's ConfigurationJson:
///
///   { "settlement": { "currency": "USD", "rates": { "LKR": 302.50 } } }
///
/// Rates read as "units of the invoice currency per one unit of the
/// settlement currency" - 302.50 rupees to the dollar - which is the way
/// the rate is quoted locally. No settlement block, or no rate for this
/// invoice's currency, means no conversion and today's behaviour exactly.
public sealed record PaymentSettlement(string Currency, decimal Rate)
{
    /// The amount to charge the gateway, rounded to the minor unit. Always
    /// rounded up: a fraction of a cent lost on every booking is the
    /// operator's loss, and rounding a charge down leaves an invoice that
    /// can never be settled in full.
    public decimal Convert(decimal invoiceAmount) =>
        Math.Round(invoiceAmount / Rate, 2, MidpointRounding.AwayFromZero);

    public static PaymentSettlement? For(PaymentGateway? gateway, string invoiceCurrency)
    {
        if (gateway is null) return null;

        var settlement = JsonAttributes.Path(JsonAttributes.Root(gateway.ConfigurationJson), "settlement");
        if (settlement is null) return null;

        var currency = JsonAttributes.String(settlement, "currency")?.Trim().ToUpperInvariant();
        if (string.IsNullOrWhiteSpace(currency) || currency.Length != 3) return null;

        // Already in the gateway's currency - nothing to convert, and
        // converting at a rate of 1 would only add noise to the receipt.
        if (string.Equals(currency, invoiceCurrency, StringComparison.OrdinalIgnoreCase)) return null;

        var rate = JsonAttributes.Decimal(settlement, $"rates.{invoiceCurrency.ToUpperInvariant()}");
        if (rate is not > 0) return null;

        return new PaymentSettlement(currency, rate.Value);
    }
}
