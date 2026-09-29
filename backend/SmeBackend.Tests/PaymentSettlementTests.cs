using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Tests;

/// Charging a gateway in a currency it will actually take.
///
/// Stripe rejects LKR outright, but the operator prices and invoices in
/// rupees. These pin the arithmetic and, more importantly, the guard rails:
/// a misconfigured rate must fall back to no conversion rather than charge
/// someone a wrong amount.
public class PaymentSettlementTests
{
    private static PaymentGateway Gateway(string? configurationJson) =>
        new() { Provider = "Stripe", ConfigurationJson = configurationJson };

    private const string UsdAt302 = """{"settlement":{"currency":"USD","rates":{"LKR":302.50}}}""";

    [Fact]
    public void An_lkr_invoice_is_charged_in_dollars_at_the_configured_rate()
    {
        var settlement = PaymentSettlement.For(Gateway(UsdAt302), "LKR");

        Assert.NotNull(settlement);
        Assert.Equal("USD", settlement!.Currency);
        Assert.Equal(302.50m, settlement.Rate);
        // The 25% deposit on a LKR 15,000 sailing.
        Assert.Equal(12.40m, settlement.Convert(3750m));
    }

    [Fact]
    public void A_part_cent_is_rounded_up_not_down()
    {
        // Rounding a charge down leaves an invoice that can never be
        // settled in full; the fraction is the operator's to absorb.
        var settlement = PaymentSettlement.For(Gateway(UsdAt302), "LKR")!;

        Assert.Equal(3.31m, settlement.Convert(1000m));   // 3.3057…
    }

    [Fact]
    public void A_gateway_with_no_settlement_block_charges_the_invoice_currency()
    {
        // The guard for every tenant already taking payments: nothing is
        // converted unless it has been configured.
        Assert.Null(PaymentSettlement.For(Gateway("""{"other":true}"""), "LKR"));
        Assert.Null(PaymentSettlement.For(Gateway(null), "LKR"));
    }

    [Fact]
    public void An_invoice_already_in_the_gateways_currency_is_not_converted()
    {
        Assert.Null(PaymentSettlement.For(Gateway(UsdAt302), "USD"));
        Assert.Null(PaymentSettlement.For(Gateway(UsdAt302), "usd"));
    }

    [Fact]
    public void A_currency_with_no_rate_is_not_converted_at_a_guess()
    {
        // Charging at an assumed rate would be inventing a price.
        Assert.Null(PaymentSettlement.For(Gateway(UsdAt302), "EUR"));
    }

    [Theory]
    [InlineData("0")]
    [InlineData("-302.5")]
    public void A_nonsense_rate_is_refused(string rate)
    {
        // A zero rate divides by zero; a negative one refunds the customer
        // at checkout. Both fall back to no conversion.
        var gateway = Gateway("{\"settlement\":{\"currency\":\"USD\",\"rates\":{\"LKR\":" + rate + "}}}");

        Assert.Null(PaymentSettlement.For(gateway, "LKR"));
    }

    [Theory]
    [InlineData("US")]
    [InlineData("DOLLAR")]
    [InlineData("")]
    public void A_currency_code_that_is_not_three_letters_is_refused(string currency)
    {
        var gateway = Gateway("{\"settlement\":{\"currency\":\"" + currency + "\",\"rates\":{\"LKR\":302.5}}}");

        Assert.Null(PaymentSettlement.For(gateway, "LKR"));
    }
}
