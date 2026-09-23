using SmeBackend.DTOs;
using SmeBackend.Services.Billing;

namespace SmeBackend.Services;

public interface IBillingService
{
    // Invoices
    Task<InvoiceListResponse> GetInvoicesAsync(BillingActor actor, InvoiceQuery query, CancellationToken ct = default);
    Task<BillingResult<InvoiceResponse>> GetInvoiceAsync(BillingActor actor, Guid invoiceId, CancellationToken ct = default);
    Task<BillingResult<InvoiceResponse>> CreateInvoiceAsync(BillingActor actor, CreateInvoiceRequest request, CancellationToken ct = default);
    Task<BillingResult<AdjustInvoiceResult>> AdjustInvoiceAsync(BillingActor actor, Guid invoiceId, AdjustInvoiceRequest request, CancellationToken ct = default);
    Task<BillingResult<InvoiceResponse>> CancelInvoiceAsync(BillingActor actor, Guid invoiceId, CancelInvoiceRequest request, CancellationToken ct = default);
    Task<BillingResult<PaymentScheduleResponse>> CreatePaymentScheduleAsync(BillingActor actor, CreatePaymentScheduleRequest request, CancellationToken ct = default);

    // Payments
    Task<BillingResult<(PaymentResponse Payment, InvoiceResponse Invoice)>> PayInvoiceAsync(BillingActor actor, Guid invoiceId, PayInvoiceRequest request, CancellationToken ct = default);
    Task<BillingResult<InvoiceResponse>> SplitPayInvoiceAsync(BillingActor actor, Guid invoiceId, SplitPaymentRequest request, CancellationToken ct = default);

    // Receipts & delivery
    Task<BillingResult<ReceiptResponse>> GetReceiptAsync(BillingActor actor, Guid invoiceId, CancellationToken ct = default);
    Task<BillingResult<(byte[] Content, string FileName)>> GetReceiptPdfAsync(BillingActor actor, Guid invoiceId, CancellationToken ct = default);
    Task<BillingResult<MessageDeliveryResponse>> SendInvoiceAsync(BillingActor actor, Guid invoiceId, SendInvoiceRequest request, bool asReminder, CancellationToken ct = default);

    // Subscriptions
    Task<SubscriptionListResponse> GetSubscriptionsAsync(BillingActor actor, int page, int pageSize, string? status = null, Guid? customerId = null, CancellationToken ct = default);
    Task<BillingResult<SubscriptionResponse>> GetSubscriptionAsync(BillingActor actor, Guid subscriptionId, CancellationToken ct = default);
    Task<BillingResult<SubscriptionResponse>> CreateSubscriptionAsync(BillingActor actor, CreateSubscriptionRequest request, CancellationToken ct = default);
    Task<BillingResult<CancelSubscriptionResult>> CancelSubscriptionAsync(BillingActor actor, Guid subscriptionId, CancelSubscriptionRequest request, CancellationToken ct = default);
    Task<BillingResult<SubscriptionResponse>> ChangePlanAsync(BillingActor actor, Guid subscriptionId, ChangePlanRequest request, CancellationToken ct = default);
    Task<IReadOnlyList<SubscriptionPlanOption>> GetPlanOptionsAsync(BillingActor actor, CancellationToken ct = default);
    Task<IReadOnlyList<RenewalCalendarEntry>> GetRenewalCalendarAsync(BillingActor actor, DateTime from, DateTime to, CancellationToken ct = default);
    Task<BillingResult<InvoiceListResponse>> GetSubscriptionInvoicesAsync(BillingActor actor, Guid subscriptionId, CancellationToken ct = default);

    // Insurance claims
    Task<InsuranceClaimListResponse> GetInsuranceClaimsAsync(BillingActor actor, int page, int pageSize, string? status = null, CancellationToken ct = default);
    Task<BillingResult<InsuranceClaimResponse>> GetInsuranceClaimAsync(BillingActor actor, Guid claimId, CancellationToken ct = default);
    Task<BillingResult<InsuranceClaimResponse>> CreateInsuranceClaimAsync(BillingActor actor, CreateInsuranceClaimRequest request, CancellationToken ct = default);
    Task<BillingResult<UpdateClaimStatusResult>> UpdateInsuranceClaimStatusAsync(BillingActor actor, Guid claimId, UpdateInsuranceClaimStatusRequest request, CancellationToken ct = default);
    Task<BillingResult<InsuranceClaimResponse>> AddClaimDocumentAsync(BillingActor actor, Guid claimId, string url, string fileName, CancellationToken ct = default);
}
