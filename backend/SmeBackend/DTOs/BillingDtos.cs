using System.ComponentModel.DataAnnotations;
using System.Text.Json;

namespace SmeBackend.DTOs;

// ==========================================
// INVOICE DTOs
// ==========================================

public record CreateInvoiceItemRequest(
    [Required(ErrorMessage = "Description is required.")]
    [MaxLength(500)]
    string Description,

    [Range(1, int.MaxValue, ErrorMessage = "Quantity must be greater than 0.")]
    int Quantity,

    [Range(0, double.MaxValue, ErrorMessage = "UnitPrice must not be negative.")]
    decimal UnitPrice,

    [MaxLength(100)]
    string Category = "General"
);

public record CreateInvoiceRequest(
    [Required(ErrorMessage = "CustomerId is required.")]
    Guid CustomerId,

    [MaxLength(50)]
    string? InvoiceNumber,

    Guid? BookingId,

    [Required(ErrorMessage = "DueDate is required.")]
    DateTime DueDate,

    [Required(ErrorMessage = "Currency is required.")]
    [MaxLength(3)]
    string Currency = "LKR",

    [Range(0, double.MaxValue, ErrorMessage = "Discount must not be negative.")]
    decimal Discount = 0,

    [Range(0, double.MaxValue, ErrorMessage = "Tax must not be negative.")]
    decimal Tax = 0,

    [Required(ErrorMessage = "At least one invoice item is required.")]
    [MinLength(1, ErrorMessage = "Invoice must contain at least one item.")]
    List<CreateInvoiceItemRequest> Items = null!
);

public record InvoiceItemResponse(
    Guid Id,
    string Description,
    int Quantity,
    decimal UnitPrice,
    decimal Amount,
    string Category
);

public record InvoiceResponse(
    Guid Id,
    Guid TenantId,
    Guid CustomerId,
    Guid? BookingId,
    string InvoiceNumber,
    decimal TotalAmount,
    decimal Discount,
    decimal Tax,
    decimal FinalAmount,
    string Status,
    DateTime DueDate,
    string Currency,
    DateTime CreatedAt,
    IReadOnlyList<InvoiceItemResponse> Items,
    IReadOnlyList<PaymentResponse> Payments
);

public record InvoiceListResponse(
    IReadOnlyList<InvoiceResponse> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages
);

// ==========================================
// PAYMENT DTOs
// ==========================================

public record PayInvoiceRequest(
    [Range(0.01, double.MaxValue, ErrorMessage = "Payment amount must be greater than 0.")]
    decimal Amount,

    [Required(ErrorMessage = "Payment method is required.")]
    [MaxLength(50)]
    string Method,

    [MaxLength(200)]
    string? TransactionRef = null,

    string? GatewayResponse = null
);

public record PaymentResponse(
    Guid Id,
    Guid? InvoiceId,
    decimal Amount,
    string Method,
    string? TransactionRef,
    string? GatewayResponse,
    DateTime? PaidAt,
    DateTime CreatedAt
);

public record ReceiptResponse(
    string ReceiptNumber,
    Guid InvoiceId,
    string InvoiceNumber,
    Guid CustomerId,
    Guid? BookingId,
    DateTime DueDate,
    string Currency,
    decimal TotalAmount,
    decimal Discount,
    decimal Tax,
    decimal FinalAmount,
    decimal TotalPaid,
    decimal BalanceDue,
    string PaymentStatus,
    DateTime IssuedAt,
    IReadOnlyList<InvoiceItemResponse> Items,
    IReadOnlyList<PaymentResponse> Payments
);

// ==========================================
// SUBSCRIPTION DTOs
// ==========================================

public record CreateSubscriptionRequest(
    [Required(ErrorMessage = "CustomerId is required.")]
    Guid CustomerId,

    [Required(ErrorMessage = "PlanName is required.")]
    [MaxLength(150)]
    string PlanName,

    [Range(0, double.MaxValue, ErrorMessage = "Amount must not be negative.")]
    decimal Amount,

    [Required(ErrorMessage = "BillingCycle is required.")]
    [MaxLength(30)]
    string BillingCycle,

    [Required(ErrorMessage = "StartDate is required.")]
    DateTime StartDate,

    [Required(ErrorMessage = "EndDate is required.")]
    DateTime EndDate,

    bool AutoRenew = true
);

public record SubscriptionResponse(
    Guid Id,
    Guid TenantId,
    Guid CustomerId,
    string PlanName,
    decimal Amount,
    string BillingCycle,
    DateTime StartDate,
    DateTime EndDate,
    bool AutoRenew,
    string Status,
    DateTime CreatedAt
);

public record SubscriptionListResponse(
    IReadOnlyList<SubscriptionResponse> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages
);

// ==========================================
// INSURANCE CLAIM DTOs
// ==========================================

public record CreateInsuranceClaimRequest(
    [Required(ErrorMessage = "InvoiceId is required.")]
    Guid InvoiceId,

    [Required(ErrorMessage = "Provider is required.")]
    [MaxLength(150)]
    string Provider,

    [Required(ErrorMessage = "PolicyNumber is required.")]
    [MaxLength(100)]
    string PolicyNumber,

    [Range(0.01, double.MaxValue, ErrorMessage = "ClaimAmount must be greater than 0.")]
    decimal ClaimAmount
);

public record UpdateInsuranceClaimStatusRequest(
    [Required(ErrorMessage = "Status is required.")]
    [MaxLength(30)]
    string Status,

    string? RejectionReason = null
);

public record InsuranceClaimResponse(
    Guid Id,
    Guid? InvoiceId,
    string? InvoiceNumber,
    string Provider,
    string PolicyNumber,
    decimal ClaimAmount,
    string Status,
    DateTime? SubmittedAt,
    DateTime? ApprovedAt,
    string? RejectionReason,
    DateTime CreatedAt
);

public record InsuranceClaimListResponse(
    IReadOnlyList<InsuranceClaimResponse> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages
);

// ==========================================
// DYNAMIC FORM DTOs
// ==========================================

public record DynamicFormValidationError(
    string Field,
    string Message
);

public record DynamicFormValidationResponse(
    bool IsValid,
    IReadOnlyList<DynamicFormValidationError> Errors
);

public record DynamicFormSubmitRequest(
    [Required(ErrorMessage = "EntityId is required.")]
    Guid EntityId,

    JsonElement Data
);

public record FormSubmissionResponse(
    Guid Id,
    Guid? DynamicFormId,
    string FormType,
    Guid EntityId,
    JsonElement Data,
    DateTime SubmittedAt,
    DateTime CreatedAt
);
