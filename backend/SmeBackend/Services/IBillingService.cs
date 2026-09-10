using SmeBackend.DTOs;

namespace SmeBackend.Services;

public interface IBillingService
{
    // Invoices
    Task<InvoiceListResponse> GetInvoicesAsync(
        Guid tenantId,
        int page,
        int pageSize,
        string? status = null,
        Guid? customerId = null,
        CancellationToken cancellationToken = default);

    Task<(bool Success, string? Error, InvoiceResponse? Invoice)> CreateInvoiceAsync(
        Guid tenantId,
        CreateInvoiceRequest request,
        CancellationToken cancellationToken = default);

    Task<(bool Success, string? Error, PaymentResponse? Payment, InvoiceResponse? Invoice)> PayInvoiceAsync(
        Guid tenantId,
        Guid invoiceId,
        PayInvoiceRequest request,
        CancellationToken cancellationToken = default);

    Task<(bool Success, string? Error, ReceiptResponse? Receipt)> GetReceiptAsync(
        Guid tenantId,
        Guid invoiceId,
        CancellationToken cancellationToken = default);

    // Subscriptions
    Task<SubscriptionListResponse> GetSubscriptionsAsync(
        Guid tenantId,
        int page,
        int pageSize,
        string? status = null,
        Guid? customerId = null,
        CancellationToken cancellationToken = default);

    Task<(bool Success, string? Error, SubscriptionResponse? Subscription)> CreateSubscriptionAsync(
        Guid tenantId,
        CreateSubscriptionRequest request,
        CancellationToken cancellationToken = default);

    Task<(bool Success, string? Error, SubscriptionResponse? Subscription)> CancelSubscriptionAsync(
        Guid tenantId,
        Guid subscriptionId,
        CancellationToken cancellationToken = default);

    // Insurance Claims
    Task<InsuranceClaimListResponse> GetInsuranceClaimsAsync(
        Guid tenantId,
        int page,
        int pageSize,
        string? status = null,
        CancellationToken cancellationToken = default);

    Task<(bool Success, string? Error, InsuranceClaimResponse? Claim)> CreateInsuranceClaimAsync(
        Guid tenantId,
        CreateInsuranceClaimRequest request,
        CancellationToken cancellationToken = default);

    Task<(bool Success, string? Error, InsuranceClaimResponse? Claim)> UpdateInsuranceClaimStatusAsync(
        Guid tenantId,
        Guid claimId,
        UpdateInsuranceClaimStatusRequest request,
        CancellationToken cancellationToken = default);
}
