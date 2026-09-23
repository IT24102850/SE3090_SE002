using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Services.Billing;

public interface IPaymentCheckoutService
{
    Task<BillingResult<CheckoutResponse>> StartCheckoutAsync(BillingActor actor, Guid invoiceId, CheckoutRequest request, CancellationToken ct = default);
    Task<BillingResult<(PaymentResponse Payment, InvoiceResponse Invoice)>> ConfirmCheckoutAsync(BillingActor actor, ConfirmCheckoutRequest request, CancellationToken ct = default);
    Task<BillingResult<string>> HandleWebhookAsync(string provider, Guid tenantId, string body, IReadOnlyDictionary<string, string> headers, CancellationToken ct = default);
}

/// Card / QR / wallet payments through the tenant's gateway. A checkout
/// creates a Pending payment; only the provider (webhook or read-back) or,
/// for the sandbox, the confirm call can turn it into Succeeded - the
/// client never gets to say "it's paid".
public sealed class PaymentCheckoutService : IPaymentCheckoutService
{
    private readonly AppDbContext _db;
    private readonly IPaymentProcessorFactory _processors;
    private readonly BillingSettingsService _settings;
    private readonly IBillingService _billing;
    private readonly ILogger<PaymentCheckoutService> _logger;

    public PaymentCheckoutService(AppDbContext db, IPaymentProcessorFactory processors, BillingSettingsService settings,
        IBillingService billing, ILogger<PaymentCheckoutService> logger)
    {
        _db = db;
        _processors = processors;
        _settings = settings;
        _billing = billing;
        _logger = logger;
    }

    public async Task<BillingResult<CheckoutResponse>> StartCheckoutAsync(BillingActor actor, Guid invoiceId, CheckoutRequest request, CancellationToken ct = default)
    {
        var invoice = await InvoicesFor(actor).Include(i => i.Payments).FirstOrDefaultAsync(i => i.Id == invoiceId, ct);
        if (invoice is null) return BillingResult<CheckoutResponse>.NotFound("Invoice not found.");
        if (invoice.Status is InvoiceStatuses.Cancelled or InvoiceStatuses.Draft)
            return BillingResult<CheckoutResponse>.BadRequest("This invoice cannot be paid.");

        var balance = invoice.FinalAmount - BillingService.PaidAmount(invoice);
        if (balance <= 0) return BillingResult<CheckoutResponse>.BadRequest("Invoice is already fully paid.");
        var amount = BillingRules.Round(request.Amount ?? balance);
        if (amount <= 0) return BillingResult<CheckoutResponse>.BadRequest("The amount must be greater than 0.");
        if (amount > balance) return BillingResult<CheckoutResponse>.BadRequest($"The amount ({amount:N2}) exceeds the balance ({balance:N2}).");

        // Pick the gateway: the one asked for, else the first active real
        // one, else the sandbox.
        PaymentGateway? gateway = null;
        var wanted = request.Provider is null ? null : PaymentProviders.Normalize(request.Provider);
        if (request.Provider is not null && wanted is null)
            return BillingResult<CheckoutResponse>.BadRequest($"Provider must be one of: {string.Join(", ", PaymentProviders.All)}.");

        if (wanted != PaymentProviders.Manual)
        {
            var active = _db.PaymentGateways.AsNoTracking()
                .Where(g => g.TenantId == actor.TenantId && g.IsActive && g.Provider != PaymentProviders.Manual);
            gateway = wanted is null
                ? await active.OrderBy(g => g.CreatedAt).FirstOrDefaultAsync(ct)
                : await active.Where(g => g.Provider == wanted).OrderBy(g => g.CreatedAt).FirstOrDefaultAsync(ct);
            if (wanted is not null && gateway is null)
                return BillingResult<CheckoutResponse>.BadRequest($"{wanted} is not configured for this business.");
        }

        var provider = gateway?.Provider ?? PaymentProviders.Manual;
        var credentials = gateway is null
            ? new GatewayCredentials(PaymentProviders.Manual, null, null, null, true)
            : _settings.Credentials(gateway);

        var payment = new Payment
        {
            InvoiceId = invoice.Id,
            Amount = amount,
            Method = string.IsNullOrWhiteSpace(request.Method) ? "Card" : request.Method.Trim(),
            Provider = provider,
            Status = PaymentStatuses.Pending,
        };
        _db.Payments.Add(payment);
        await _db.SaveChangesAsync(ct);

        ProcessorCheckout session;
        try
        {
            session = await _processors.Get(provider).CreateCheckoutAsync(credentials,
                new CheckoutIntent(payment.Id, invoice.Id, invoice.InvoiceNumber, amount, invoice.Currency, payment.Method, request.ReturnUrl), ct);
        }
        catch (Exception ex) when (ex is PaymentProviderException or HttpRequestException)
        {
            payment.Status = PaymentStatuses.Failed;
            payment.GatewayResponse = ex.Message;
            await _db.SaveChangesAsync(ct);
            _logger.LogWarning(ex, "{Provider} checkout failed for invoice {InvoiceId}", provider, invoice.Id);
            return BillingResult<CheckoutResponse>.BadGateway($"{provider} could not start the payment: {ex.Message}");
        }

        payment.TransactionRef = session.ExternalId;
        payment.GatewayResponse = Truncate(session.RawResponse, 4000);
        payment.Status = session.Status;
        if (session.Status == PaymentStatuses.Succeeded) payment.PaidAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        return BillingResult<CheckoutResponse>.Created(new CheckoutResponse(payment.Id, invoice.Id, provider, payment.Status, amount,
            invoice.Currency, session.ClientSecret, session.RedirectUrl, credentials.PublicKey, session.ExternalId, session.Simulated));
    }

    public async Task<BillingResult<(PaymentResponse Payment, InvoiceResponse Invoice)>> ConfirmCheckoutAsync(BillingActor actor, ConfirmCheckoutRequest request, CancellationToken ct = default)
    {
        var payment = await _db.Payments.Include(p => p.Invoice).ThenInclude(i => i!.Payments)
            .FirstOrDefaultAsync(p => p.Id == request.PaymentId && p.Invoice != null && p.Invoice.TenantId == actor.TenantId, ct);
        if (payment?.Invoice is null || (actor.IsCustomer && payment.Invoice.CustomerId != actor.UserId))
            return BillingResult<(PaymentResponse, InvoiceResponse)>.NotFound("Payment not found.");

        if (payment.Status == PaymentStatuses.Pending)
        {
            string status;
            if (payment.Provider == PaymentProviders.Manual)
            {
                status = request.SimulateFailure ? PaymentStatuses.Failed : PaymentStatuses.Succeeded;
            }
            else
            {
                var gateway = await _db.PaymentGateways.AsNoTracking()
                    .FirstOrDefaultAsync(g => g.TenantId == actor.TenantId && g.Provider == payment.Provider && g.IsActive, ct);
                if (gateway is null || payment.TransactionRef is null)
                    return BillingResult<(PaymentResponse, InvoiceResponse)>.BadRequest("The gateway for this payment is no longer configured.");
                try
                {
                    status = await _processors.Get(gateway.Provider).RefreshStatusAsync(_settings.Credentials(gateway), payment.TransactionRef, ct);
                }
                catch (Exception ex) when (ex is PaymentProviderException or HttpRequestException)
                {
                    return BillingResult<(PaymentResponse, InvoiceResponse)>.BadGateway($"{gateway.Provider} could not be reached: {ex.Message}");
                }
            }

            await ApplyStatusAsync(payment, status, ct);
        }

        var invoice = await _billing.GetInvoiceAsync(actor, payment.Invoice.Id, ct);
        return BillingResult<(PaymentResponse, InvoiceResponse)>.Ok((BillingService.MapPayment(payment), invoice.Value!));
    }

    public async Task<BillingResult<string>> HandleWebhookAsync(string provider, Guid tenantId, string body, IReadOnlyDictionary<string, string> headers, CancellationToken ct = default)
    {
        var normalized = PaymentProviders.Normalize(provider);
        if (normalized is null or PaymentProviders.Manual)
            return BillingResult<string>.NotFound("Unknown payment provider.");

        var gateway = await _db.PaymentGateways.AsNoTracking()
            .FirstOrDefaultAsync(g => g.TenantId == tenantId && g.Provider == normalized && g.IsActive, ct);
        if (gateway is null) return BillingResult<string>.NotFound("No active gateway for this business.");

        WebhookEvent? evt;
        try
        {
            evt = await _processors.Get(normalized).ParseWebhookAsync(_settings.Credentials(gateway), body, headers, ct);
        }
        catch (WebhookSignatureException ex)
        {
            _logger.LogWarning("Rejected {Provider} webhook for tenant {TenantId}: {Reason}", normalized, tenantId, ex.Message);
            return BillingResult<string>.BadRequest(ex.Message);
        }
        catch (System.Text.Json.JsonException)
        {
            return BillingResult<string>.BadRequest("Malformed webhook body.");
        }

        if (evt is null) return BillingResult<string>.Ok("ignored");

        var payment = await _db.Payments.Include(p => p.Invoice).ThenInclude(i => i!.Payments)
            .FirstOrDefaultAsync(p => p.TransactionRef == evt.ExternalId && p.Provider == normalized &&
                                      p.Invoice != null && p.Invoice.TenantId == tenantId, ct);
        if (payment is null)
        {
            _logger.LogInformation("{Provider} webhook {Event} for unknown payment {ExternalId}", normalized, evt.EventType, evt.ExternalId);
            return BillingResult<string>.Ok("unknown payment");
        }

        // Webhooks are retried and can arrive out of order: only move forward.
        if (payment.Status == PaymentStatuses.Pending || (payment.Status == PaymentStatuses.Succeeded && evt.Status == PaymentStatuses.Refunded))
            await ApplyStatusAsync(payment, evt.Status, ct);

        return BillingResult<string>.Ok(payment.Status);
    }

    private async Task ApplyStatusAsync(Payment payment, string status, CancellationToken ct)
    {
        if (payment.Status == status) return;
        payment.Status = status;
        payment.UpdatedAt = DateTime.UtcNow;
        if (status == PaymentStatuses.Succeeded) payment.PaidAt = DateTime.UtcNow;

        var invoice = payment.Invoice!;
        await BillingService.ApplyPaymentEffectsAsync(_db, invoice, ct);

        if (status == PaymentStatuses.Succeeded)
        {
            NotificationHelper.Queue(_db, invoice.TenantId, invoice.CustomerId, "PaymentReceived", "Payment received",
                $"We received {invoice.Currency} {payment.Amount:N2} for invoice {invoice.InvoiceNumber}. Your receipt is ready.");
        }
        else if (status == PaymentStatuses.Failed)
        {
            NotificationHelper.Queue(_db, invoice.TenantId, invoice.CustomerId, "PaymentFailed", "Payment failed",
                $"Your payment of {invoice.Currency} {payment.Amount:N2} for invoice {invoice.InvoiceNumber} did not go through.");
        }

        await _db.SaveChangesAsync(ct);
    }

    private IQueryable<Invoice> InvoicesFor(BillingActor actor)
    {
        var q = _db.Invoices.Where(i => i.TenantId == actor.TenantId);
        return actor.IsCustomer ? q.Where(i => i.CustomerId == actor.UserId) : q;
    }

    private static string Truncate(string s, int max) => s.Length <= max ? s : s[..max];
}
