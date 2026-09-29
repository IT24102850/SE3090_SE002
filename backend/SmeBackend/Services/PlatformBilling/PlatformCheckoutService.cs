using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Services.Billing;

namespace SmeBackend.Services.PlatformBilling;

/// Taking money for a Unify subscription.
///
/// The rule the whole file exists to enforce: a plan is granted by
/// ActivateAsync, and ActivateAsync is only ever reached from a payment the
/// *gateway* says succeeded - a webhook, or a status read back from the
/// provider. The browser can ask us to check; it can never assert.
public interface IPlatformCheckoutService
{
    Task<BillingResult<PlatformCheckoutResponse>> StartSubscriptionAsync(
        Guid tenantId, string? actorEmail, SubscriptionCheckoutRequest request, CancellationToken ct = default);

    Task<BillingResult<PlatformCheckoutResponse>> StartAddOnAsync(
        Guid tenantId, string? actorEmail, AddOnCheckoutRequest request, CancellationToken ct = default);

    Task<BillingResult<PlatformInvoiceResponse>> ConfirmAsync(
        Guid tenantId, ConfirmPlatformPaymentRequest request, CancellationToken ct = default);

    /// Platform-wide: there is no tenant in the URL because the payment row
    /// is what says which tenant a webhook is about.
    Task<BillingResult<string>> HandleWebhookAsync(
        string provider, string body, IReadOnlyDictionary<string, string> headers, CancellationToken ct = default);

    /// Raises the renewal bill for a term that is ending, for the renewal
    /// worker. Returns the invoice, or null when there is nothing to charge.
    Task<PlatformInvoice?> RaiseRenewalInvoiceAsync(PlatformSubscription subscription, CancellationToken ct = default);

    /// Sends the tenant to a gateway for an invoice that is already open -
    /// the renewal path, and the retry after a card was declined.
    Task<BillingResult<PlatformCheckoutResponse>> StartInvoicePaymentAsync(
        Guid tenantId, Guid invoiceId, string? provider, string? returnUrl, CancellationToken ct = default);
}

public sealed class PlatformCheckoutService : IPlatformCheckoutService
{
    private readonly AppDbContext _db;
    private readonly IPlatformSubscriptionService _subscriptions;
    private readonly IPlatformGatewayProvider _gateways;
    private readonly IPaymentProcessorFactory _processors;
    private readonly IEntitlementService _entitlements;
    private readonly IConfiguration _config;
    private readonly ILogger<PlatformCheckoutService> _logger;

    public PlatformCheckoutService(AppDbContext db, IPlatformSubscriptionService subscriptions,
        IPlatformGatewayProvider gateways, IPaymentProcessorFactory processors, IEntitlementService entitlements,
        IConfiguration config, ILogger<PlatformCheckoutService> logger)
    {
        _db = db;
        _subscriptions = subscriptions;
        _gateways = gateways;
        _processors = processors;
        _entitlements = entitlements;
        _config = config;
        _logger = logger;
    }

    /// Everything the webhook needs to finish the job without any session
    /// state, stored on the payment itself.
    private sealed record CheckoutIntentRecord(
        string Kind, string? PlanCode, string? Period, string? PromotionCode,
        string? AddOnCode, int Quantity, Guid? PromotionId, string? ActorEmail);

    // ── Subscription checkout ────────────────────────────────────────────

    public async Task<BillingResult<PlatformCheckoutResponse>> StartSubscriptionAsync(
        Guid tenantId, string? actorEmail, SubscriptionCheckoutRequest request, CancellationToken ct = default)
    {
        var quote = await _subscriptions.QuoteAsync(tenantId, request, ct);
        if (!quote.Success)
            return BillingResult<PlatformCheckoutResponse>.BadRequest(quote.Error ?? "That plan cannot be bought.");

        var q = quote.Value!;
        var promo = await _subscriptions.ResolvePromotionAsync(tenantId, request.PromotionCode, q.PlanCode, q.Period, q.Currency, q.ListAmount, ct);

        var invoice = await CreateInvoiceAsync(
            tenantId, PlatformInvoiceKinds.Subscription, q.Currency, q.Lines,
            q.ListAmount, q.ListAmount - q.Total, q.Total, q.PlanCode, q.Period, q.PromotionCode,
            q.PeriodStart, q.PeriodEnd, ct);

        // A promotion or a proration credit can cover the whole term. There
        // is nothing to charge, so the plan starts now rather than sending
        // the tenant to a gateway for a zero-value payment it would reject.
        if (q.Total <= 0m)
        {
            invoice.Status = PlatformInvoiceStatuses.Paid;
            invoice.PaidAt = DateTime.UtcNow;
            await _db.SaveChangesAsync(ct);
            await RedeemPromotionAsync(promo, tenantId, invoice.Id, q.Currency, ct);
            await _subscriptions.ActivateAsync(tenantId, q.PlanCode, q.Period, q.Currency, 0m, q.PromotionCode, invoice.Id, actorEmail, ct);

            return BillingResult<PlatformCheckoutResponse>.Ok(new PlatformCheckoutResponse(
                Guid.Empty, invoice.Id, invoice.Number, PaymentProviders.Manual, PaymentStatuses.Succeeded,
                0m, q.Currency, null, null, null, true, null, null, null, Completed: true));
        }

        var intent = new CheckoutIntentRecord(
            PlatformInvoiceKinds.Subscription, q.PlanCode, q.Period, q.PromotionCode,
            null, 1, promo?.Promotion.Id, actorEmail);

        return await StartGatewayAsync(tenantId, invoice, q.Total, q.Currency, request.Provider, request.ReturnUrl, intent,
            $"Unify {q.PlanName} - {q.PeriodLabel}", ct);
    }

    // ── Add-on checkout ──────────────────────────────────────────────────

    public async Task<BillingResult<PlatformCheckoutResponse>> StartAddOnAsync(
        Guid tenantId, string? actorEmail, AddOnCheckoutRequest request, CancellationToken ct = default)
    {
        var addOn = await _db.PlatformAddOns.AsNoTracking()
            .FirstOrDefaultAsync(a => a.Code == request.AddOnCode && a.IsPublic, ct);
        if (addOn is null) return BillingResult<PlatformCheckoutResponse>.NotFound("That add-on is not on sale.");

        var snapshot = await _entitlements.GetAsync(tenantId, ct);
        if (snapshot.Tier < addOn.MinimumTier)
            return BillingResult<PlatformCheckoutResponse>.BadRequest($"{addOn.Name} needs a paid plan.");

        var currency = _subscriptions is PlatformSubscriptionService s
            ? s.NormalizeCurrency(request.Currency)
            : _gateways.DefaultCurrency;

        var prices = PlatformAddOnCatalog.ParsePrices(addOn.PricesJson);
        if (!prices.TryGetValue(currency, out var unit) || unit <= 0)
            return BillingResult<PlatformCheckoutResponse>.BadRequest($"{addOn.Name} is not sold in {currency}.");

        var quantity = Math.Clamp(request.Quantity, 1, 20);
        var total = BillingRules.Round(unit * quantity);
        var lines = new List<PlatformInvoiceLine> { new(addOn.Name, quantity, unit, total) };

        var invoice = await CreateInvoiceAsync(
            tenantId, PlatformInvoiceKinds.AddOn, currency, lines,
            total, 0m, total, null, null, null, null, null, ct);

        var intent = new CheckoutIntentRecord(
            PlatformInvoiceKinds.AddOn, null, null, null, addOn.Code, quantity, null, actorEmail);

        return await StartGatewayAsync(tenantId, invoice, total, currency, request.Provider, request.ReturnUrl, intent,
            $"Unify - {addOn.Name}", ct);
    }

    // ── Shared gateway leg ───────────────────────────────────────────────

    private async Task<BillingResult<PlatformCheckoutResponse>> StartGatewayAsync(
        Guid tenantId, PlatformInvoice invoice, decimal amount, string currency,
        string? requestedProvider, string? returnUrl, CheckoutIntentRecord intent, string description, CancellationToken ct)
    {
        var wanted = requestedProvider is null ? null : PaymentProviders.Normalize(requestedProvider);
        if (requestedProvider is not null && wanted is null)
            return BillingResult<PlatformCheckoutResponse>.BadRequest($"Provider must be one of: {string.Join(", ", PaymentProviders.All)}.");

        var provider = wanted ?? _gateways.Default;
        if (!_gateways.IsLive(provider))
            return BillingResult<PlatformCheckoutResponse>.BadRequest($"{provider} is not configured for Unify subscriptions.");

        var credentials = _gateways.Credentials(provider);
        var settlement = PlatformSettlement.For(_config, provider, currency);
        var chargeAmount = settlement?.Convert(amount) ?? amount;
        var chargeCurrency = settlement?.Currency ?? currency;

        var payment = new PlatformPayment
        {
            InvoiceId = invoice.Id,
            TenantId = tenantId,
            Amount = amount,
            Currency = currency,
            Method = "Card",
            Provider = provider,
            Status = PaymentStatuses.Pending,
            SettlementCurrency = settlement?.Currency,
            SettlementAmount = settlement is null ? null : chargeAmount,
            ExchangeRate = settlement?.Rate,
            IntentJson = JsonSerializer.Serialize(intent),
        };
        _db.PlatformPayments.Add(payment);
        await _db.SaveChangesAsync(ct);

        ProcessorCheckout session;
        try
        {
            // HostedPage: the tenant admin is on a laptop, and a hosted
            // page is the only leg of this that never touches card data.
            session = await _processors.Get(provider).CreateCheckoutAsync(credentials,
                new CheckoutIntent(payment.Id, invoice.Id, description, chargeAmount, chargeCurrency, payment.Method,
                    returnUrl, HostedPage: true), ct);
        }
        catch (Exception ex) when (ex is PaymentProviderException or HttpRequestException)
        {
            payment.Status = PaymentStatuses.Failed;
            payment.GatewayResponse = ex.Message;
            invoice.Status = PlatformInvoiceStatuses.Failed;
            await _db.SaveChangesAsync(ct);
            _logger.LogWarning(ex, "{Provider} checkout failed for platform invoice {Invoice}", provider, invoice.Number);
            return BillingResult<PlatformCheckoutResponse>.BadGateway($"{provider} could not start the payment: {ex.Message}");
        }

        payment.ExternalId = session.ExternalId;
        payment.GatewayResponse = Truncate(session.RawResponse, 4000);
        payment.Status = session.Status;
        if (session.Status == PaymentStatuses.Succeeded) payment.PaidAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        if (payment.Status == PaymentStatuses.Succeeded)
            await FulfilAsync(payment, ct);

        return BillingResult<PlatformCheckoutResponse>.Created(new PlatformCheckoutResponse(
            payment.Id, invoice.Id, invoice.Number, provider, payment.Status, amount, currency,
            session.RedirectUrl, session.ClientSecret, credentials.PublicKey, session.Simulated,
            settlement?.Currency, settlement is null ? null : chargeAmount, settlement?.Rate,
            Completed: payment.Status == PaymentStatuses.Succeeded));
    }

    // ── Confirmation and webhooks ────────────────────────────────────────

    public async Task<BillingResult<PlatformInvoiceResponse>> ConfirmAsync(
        Guid tenantId, ConfirmPlatformPaymentRequest request, CancellationToken ct = default)
    {
        var payment = await _db.PlatformPayments.Include(p => p.Invoice)
            .FirstOrDefaultAsync(p => p.Id == request.PaymentId && p.TenantId == tenantId, ct);
        if (payment is null) return BillingResult<PlatformInvoiceResponse>.NotFound("Payment not found.");

        if (payment.Status == PaymentStatuses.Pending)
        {
            string status;
            if (payment.Provider == PaymentProviders.Manual)
            {
                status = request.SimulateFailure ? PaymentStatuses.Failed : PaymentStatuses.Succeeded;
            }
            else
            {
                try
                {
                    status = await _processors.Get(payment.Provider)
                        .RefreshStatusAsync(_gateways.Credentials(payment.Provider), payment.ExternalId ?? "", ct);
                }
                catch (Exception ex) when (ex is PaymentProviderException or HttpRequestException)
                {
                    return BillingResult<PlatformInvoiceResponse>.BadGateway($"{payment.Provider} could not be reached: {ex.Message}");
                }
            }

            await ApplyStatusAsync(payment, status, ct);
        }

        return BillingResult<PlatformInvoiceResponse>.Ok(PlatformSubscriptionService.MapInvoice(payment.Invoice));
    }

    public async Task<BillingResult<string>> HandleWebhookAsync(
        string provider, string body, IReadOnlyDictionary<string, string> headers, CancellationToken ct = default)
    {
        var normalized = PaymentProviders.Normalize(provider);
        if (normalized is null or PaymentProviders.Manual)
            return BillingResult<string>.NotFound("Unknown payment provider.");
        if (!_gateways.IsLive(normalized))
            return BillingResult<string>.NotFound("That provider is not configured for Unify subscriptions.");

        WebhookEvent? evt;
        try
        {
            evt = await _processors.Get(normalized).ParseWebhookAsync(_gateways.Credentials(normalized), body, headers, ct);
        }
        catch (WebhookSignatureException ex)
        {
            _logger.LogWarning("Rejected platform {Provider} webhook: {Reason}", normalized, ex.Message);
            return BillingResult<string>.BadRequest(ex.Message);
        }
        catch (JsonException)
        {
            return BillingResult<string>.BadRequest("Malformed webhook body.");
        }

        if (evt is null) return BillingResult<string>.Ok("ignored");

        var payment = await _db.PlatformPayments.Include(p => p.Invoice)
            .FirstOrDefaultAsync(p => p.ExternalId == evt.ExternalId && p.Provider == normalized, ct);
        if (payment is null)
        {
            // Almost always a tenant-facing payment arriving on the platform
            // endpoint, or a replay from before this row existed.
            _logger.LogInformation("Platform {Provider} webhook {Event} for unknown payment {ExternalId}", normalized, evt.EventType, evt.ExternalId);
            return BillingResult<string>.Ok("unknown payment");
        }

        // Webhooks retry and arrive out of order: only ever move forward.
        if (payment.Status == PaymentStatuses.Pending ||
            (payment.Status == PaymentStatuses.Succeeded && evt.Status == PaymentStatuses.Refunded))
            await ApplyStatusAsync(payment, evt.Status, ct);

        return BillingResult<string>.Ok(payment.Status);
    }

    private async Task ApplyStatusAsync(PlatformPayment payment, string status, CancellationToken ct)
    {
        if (payment.Status == status) return;

        payment.Status = status;
        payment.UpdatedAt = DateTime.UtcNow;
        if (status == PaymentStatuses.Succeeded) payment.PaidAt = DateTime.UtcNow;

        var invoice = payment.Invoice;
        invoice.Status = status switch
        {
            PaymentStatuses.Succeeded => PlatformInvoiceStatuses.Paid,
            PaymentStatuses.Failed => PlatformInvoiceStatuses.Failed,
            PaymentStatuses.Refunded => PlatformInvoiceStatuses.Refunded,
            _ => invoice.Status,
        };
        if (status == PaymentStatuses.Succeeded) invoice.PaidAt = payment.PaidAt;
        invoice.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        if (status == PaymentStatuses.Succeeded)
        {
            await FulfilAsync(payment, ct);
        }
        else if (status == PaymentStatuses.Failed)
        {
            Shared.NotificationHelper.Queue(_db, payment.TenantId, null, "PlatformPaymentFailed",
                "Your Unify payment did not go through",
                $"We could not take {payment.Currency} {payment.Amount:N2} for {invoice.Number}. Nothing has changed on your plan - try again from the Subscription screen.");
            await _db.SaveChangesAsync(ct);
        }
    }

    /// Hands over what the payment bought. Idempotent by way of the invoice:
    /// a webhook replay finds the term already applied and does nothing.
    private async Task FulfilAsync(PlatformPayment payment, CancellationToken ct)
    {
        if (payment.IntentJson is null) return;

        CheckoutIntentRecord? intent;
        try
        {
            intent = JsonSerializer.Deserialize<CheckoutIntentRecord>(payment.IntentJson);
        }
        catch (JsonException)
        {
            _logger.LogError("Platform payment {PaymentId} succeeded with an unreadable intent.", payment.Id);
            return;
        }
        if (intent is null) return;

        var already = await _db.PlatformSubscriptionEvents
            .AnyAsync(e => e.TenantId == payment.TenantId && e.Detail == $"invoice:{payment.InvoiceId}", ct);
        if (already) return;

        if (intent.Kind == PlatformInvoiceKinds.Subscription && intent.PlanCode is { } planCode && intent.Period is { } period)
        {
            if (intent.PromotionId is { } promotionId)
            {
                var promotion = await _db.PlatformPromotions.FirstOrDefaultAsync(p => p.Id == promotionId, ct);
                if (promotion is not null)
                    await RedeemPromotionAsync((promotion, payment.Invoice.Discount), payment.TenantId, payment.InvoiceId, payment.Currency, ct);
            }

            await _subscriptions.ActivateAsync(payment.TenantId, planCode, period, payment.Currency,
                payment.Amount, intent.PromotionCode, payment.InvoiceId, intent.ActorEmail, ct);
        }
        else if (intent.Kind == PlatformInvoiceKinds.AddOn && intent.AddOnCode is { } addOnCode)
        {
            var addOn = await _db.PlatformAddOns.AsNoTracking().FirstOrDefaultAsync(a => a.Code == addOnCode, ct);
            if (addOn is not null)
                await _subscriptions.GrantAddOnAsync(payment.TenantId, addOn, intent.Quantity, payment.InvoiceId, ct);
        }
    }

    // ── Renewals ─────────────────────────────────────────────────────────

    /// Unify does not vault cards - there is no stored payment method to
    /// charge off-session - so a renewal raises the bill and asks the tenant
    /// to pay it. The grace window in the renewal worker is what makes that a
    /// workable flow rather than an outage: they keep every feature while the
    /// invoice sits there, and get chased rather than switched off.
    public async Task<PlatformInvoice?> RaiseRenewalInvoiceAsync(PlatformSubscription subscription, CancellationToken ct = default)
    {
        if (subscription.Amount <= 0 || subscription.IsComplimentary) return null;

        var months = BillingPeriods.Months(subscription.Period);
        var start = subscription.CurrentPeriodEnd ?? DateTime.UtcNow;

        // One renewal bill per term, however many times the worker runs.
        var existing = await _db.PlatformInvoices.FirstOrDefaultAsync(i =>
            i.TenantId == subscription.TenantId
            && i.Kind == PlatformInvoiceKinds.Subscription
            && i.PeriodStart == start
            && i.Status != PlatformInvoiceStatuses.Cancelled, ct);
        if (existing is not null) return existing;

        var lines = new List<PlatformInvoiceLine>
        {
            new($"{subscription.PlanCode} - {BillingPeriods.Label(subscription.Period)} renewal", 1, subscription.Amount, subscription.Amount),
        };

        var invoice = await CreateInvoiceAsync(
            subscription.TenantId, PlatformInvoiceKinds.Subscription, subscription.Currency, lines,
            subscription.Amount, 0m, subscription.Amount, subscription.PlanCode, subscription.Period, null,
            start, start.AddMonths(months), ct);

        Shared.NotificationHelper.Queue(_db, subscription.TenantId, null, "PlatformRenewalDue",
            "Your Unify subscription is due for renewal",
            $"{invoice.Number} for {subscription.Currency} {subscription.Amount:N2} is ready. Pay it from the Subscription screen to keep {subscription.PlanCode} running.");
        await _db.SaveChangesAsync(ct);

        return invoice;
    }

    public async Task<BillingResult<PlatformCheckoutResponse>> StartInvoicePaymentAsync(
        Guid tenantId, Guid invoiceId, string? provider, string? returnUrl, CancellationToken ct = default)
    {
        var invoice = await _db.PlatformInvoices.FirstOrDefaultAsync(i => i.Id == invoiceId && i.TenantId == tenantId, ct);
        if (invoice is null) return BillingResult<PlatformCheckoutResponse>.NotFound("Invoice not found.");
        if (invoice.Status == PlatformInvoiceStatuses.Paid)
            return BillingResult<PlatformCheckoutResponse>.BadRequest("That invoice is already paid.");
        if (invoice.Status == PlatformInvoiceStatuses.Cancelled)
            return BillingResult<PlatformCheckoutResponse>.BadRequest("That invoice was cancelled.");
        if (invoice.Total <= 0)
            return BillingResult<PlatformCheckoutResponse>.BadRequest("There is nothing to pay on that invoice.");

        var intent = invoice.Kind == PlatformInvoiceKinds.Subscription
            ? new CheckoutIntentRecord(PlatformInvoiceKinds.Subscription, invoice.PlanCode, invoice.Period,
                invoice.PromotionCode, null, 1, null, null)
            : new CheckoutIntentRecord(PlatformInvoiceKinds.AddOn, null, null, null, null, 1, null, null);

        if (invoice.Kind == PlatformInvoiceKinds.AddOn)
            return BillingResult<PlatformCheckoutResponse>.BadRequest("Buy the add-on again rather than retrying its invoice.");

        // Reissue: a stale gateway session cannot be reused, so the previous
        // pending attempt is abandoned and a fresh one is created.
        await _db.PlatformPayments
            .Where(p => p.InvoiceId == invoice.Id && p.Status == PaymentStatuses.Pending)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.Status, PaymentStatuses.Failed)
                .SetProperty(p => p.GatewayResponse, "Superseded by a new checkout.")
                .SetProperty(p => p.UpdatedAt, DateTime.UtcNow), ct);

        invoice.Status = PlatformInvoiceStatuses.Issued;
        await _db.SaveChangesAsync(ct);

        return await StartGatewayAsync(tenantId, invoice, invoice.Total, invoice.Currency, provider, returnUrl, intent,
            $"Unify {invoice.PlanCode} - {invoice.Number}", ct);
    }

    // ── Invoice plumbing ─────────────────────────────────────────────────

    private async Task<PlatformInvoice> CreateInvoiceAsync(
        Guid tenantId, string kind, string currency, IReadOnlyList<PlatformInvoiceLine> lines,
        decimal subtotal, decimal discount, decimal total, string? planCode, string? period, string? promotionCode,
        DateTime? periodStart, DateTime? periodEnd, CancellationToken ct)
    {
        var invoice = new PlatformInvoice
        {
            TenantId = tenantId,
            Number = await NextNumberAsync(ct),
            Kind = kind,
            PlanCode = planCode,
            Period = period,
            Currency = currency,
            Subtotal = BillingRules.Round(subtotal),
            Discount = BillingRules.Round(discount),
            Tax = 0m,
            Total = BillingRules.Round(total),
            Status = PlatformInvoiceStatuses.Issued,
            LinesJson = JsonSerializer.Serialize(lines),
            PromotionCode = promotionCode,
            IssuedAt = DateTime.UtcNow,
            DueAt = DateTime.UtcNow.AddDays(7),
            PeriodStart = periodStart,
            PeriodEnd = periodEnd,
        };
        _db.PlatformInvoices.Add(invoice);
        await _db.SaveChangesAsync(ct);
        return invoice;
    }

    /// UNF-2026-000123. Derived from the year's count rather than a sequence
    /// object; the unique index is what settles a race, and a retry with a
    /// recount is cheaper than a sequence nobody else needs.
    private async Task<string> NextNumberAsync(CancellationToken ct)
    {
        var year = DateTime.UtcNow.Year;
        var prefix = $"UNF-{year}-";
        for (var attempt = 0; attempt < 5; attempt++)
        {
            var count = await _db.PlatformInvoices.CountAsync(i => i.Number.StartsWith(prefix), ct);
            var candidate = $"{prefix}{(count + 1 + attempt):D6}";
            if (!await _db.PlatformInvoices.AnyAsync(i => i.Number == candidate, ct))
                return candidate;
        }
        return $"{prefix}{Guid.NewGuid().ToString("N")[..6].ToUpperInvariant()}";
    }

    private async Task RedeemPromotionAsync((PlatformPromotion Promotion, decimal Discount)? promo,
        Guid tenantId, Guid invoiceId, string currency, CancellationToken ct)
    {
        if (promo is not { } p) return;

        var tracked = await _db.PlatformPromotions.FirstOrDefaultAsync(x => x.Id == p.Promotion.Id, ct);
        if (tracked is null) return;

        if (await _db.PlatformPromotionRedemptions.AnyAsync(r => r.TenantId == tenantId && r.InvoiceId == invoiceId, ct))
            return;

        tracked.Redemptions++;
        tracked.UpdatedAt = DateTime.UtcNow;
        _db.PlatformPromotionRedemptions.Add(new PlatformPromotionRedemption
        {
            PromotionId = tracked.Id,
            TenantId = tenantId,
            InvoiceId = invoiceId,
            Code = tracked.Code,
            DiscountAmount = p.Discount,
            Currency = currency,
        });
        await _db.SaveChangesAsync(ct);
    }

    private static string Truncate(string s, int max) => s.Length <= max ? s : s[..max];
}
