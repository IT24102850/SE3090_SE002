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
    List<CreateInvoiceItemRequest> Items = null!,

    Guid? BranchId = null,

    Guid? SubscriptionId = null,

    Guid? TemplateId = null,

    // When set, overrides Discount: a percentage of the item subtotal.
    [Range(0, 100, ErrorMessage = "DiscountPercent must be between 0 and 100.")]
    decimal? DiscountPercent = null,

    // When set, overrides Tax: a percentage of (subtotal - discount).
    [Range(0, 100, ErrorMessage = "TaxRatePercent must be between 0 and 100.")]
    decimal? TaxRatePercent = null,

    [MaxLength(50)]
    string? DiscountCode = null,

    [MaxLength(2000)]
    string? Notes = null
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
    IReadOnlyList<PaymentResponse> Payments,
    Guid? BranchId = null,
    Guid? SubscriptionId = null,
    Guid? TemplateId = null,
    string? DiscountCode = null,
    string? Notes = null,
    string? ScheduleGroup = null,
    string? ScheduleLabel = null,
    decimal AmountPaid = 0,
    decimal BalanceDue = 0,
    bool IsOverdue = false,
    string? CustomerName = null,
    // Returned on create only: the agent's business-rule check of the new
    // invoice. Warnings mean it was issued but flagged for review.
    IReadOnlyList<InvoiceValidationIssue>? ValidationIssues = null
);

public record InvoiceListResponse(
    IReadOnlyList<InvoiceResponse> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages
);

public record InvoiceQuery(
    int Page = 1,
    int PageSize = 20,
    string? Status = null,
    Guid? CustomerId = null,
    DateTime? From = null,
    DateTime? To = null,
    Guid? BranchId = null,
    string? Search = null
);

/// A correction to an issued invoice's discount and/or tax. When the change
/// moves the payable amount by more than the approval threshold it becomes
/// an approval request instead of being applied.
public record AdjustInvoiceRequest(
    [Range(0, double.MaxValue, ErrorMessage = "Discount must not be negative.")]
    decimal? Discount,

    [Range(0, double.MaxValue, ErrorMessage = "Tax must not be negative.")]
    decimal? Tax,

    [Required(ErrorMessage = "A reason is required for an invoice adjustment.")]
    [MaxLength(500)]
    string Reason
);

public record AdjustInvoiceResult(
    bool Applied,
    bool RequiresApproval,
    Guid? ApprovalWorkflowId,
    InvoiceResponse Invoice,
    string Message
);

public record CancelInvoiceRequest(
    [MaxLength(500)]
    string? Reason
);

public record PaymentSchedulePart(
    [Required]
    [MaxLength(100)]
    string Label,

    decimal? Amount,

    [Range(0, 100)]
    decimal? Percent,

    DateTime DueDate
);

/// Installments (tuition), milestones (real estate) and deposit + balance
/// (tourism) are all one shape: a total split into dated parts, each its
/// own invoice so each can be paid, chased and receipted on its own.
public record CreatePaymentScheduleRequest(
    [Required] Guid CustomerId,

    [Required]
    [MaxLength(500)]
    string Description,

    [Range(0.01, double.MaxValue, ErrorMessage = "TotalAmount must be greater than 0.")]
    decimal TotalAmount,

    [Required]
    [MinLength(1)]
    List<PaymentSchedulePart> Parts,

    [MaxLength(3)]
    string Currency = "LKR",

    [MaxLength(100)]
    string Category = "General",

    Guid? BranchId = null,

    Guid? BookingId = null,

    [Range(0, 100)]
    decimal? TaxRatePercent = null
);

public record PaymentScheduleResponse(
    string ScheduleGroup,
    decimal TotalAmount,
    string Currency,
    IReadOnlyList<InvoiceResponse> Invoices
);

public record SendInvoiceRequest(
    // Email | Sms | WhatsApp
    [Required]
    [MaxLength(20)]
    string Channel,

    // Overrides the customer's own email / phone.
    [MaxLength(200)]
    string? To = null
);

public record MessageDeliveryResponse(
    string Channel,
    string Recipient,
    bool Delivered,
    bool Simulated,
    string? ProviderMessageId,
    string? Error
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

    string? GatewayResponse = null,

    [MaxLength(100)]
    string? PayerLabel = null
);

public record SplitPaymentShare(
    [Range(0.01, double.MaxValue, ErrorMessage = "Each share must be greater than 0.")]
    decimal Amount,

    [Required]
    [MaxLength(50)]
    string Method,

    [MaxLength(100)]
    string? PayerLabel = null,

    [MaxLength(200)]
    string? TransactionRef = null
);

/// A restaurant table bill paid by several people: every share is recorded
/// in one transaction, or none are.
public record SplitPaymentRequest(
    [Required]
    [MinLength(1)]
    List<SplitPaymentShare> Shares
);

public record PaymentResponse(
    Guid Id,
    Guid? InvoiceId,
    decimal Amount,
    string Method,
    string? TransactionRef,
    string? GatewayResponse,
    DateTime? PaidAt,
    DateTime CreatedAt,
    string Status = "Succeeded",
    string? Provider = null,
    string? PayerLabel = null
);

public record CheckoutRequest(
    // Stripe | PayPal | Manual. Omitted: the tenant's first active gateway,
    // or the sandbox simulator when none is configured.
    [MaxLength(30)]
    string? Provider = null,

    // Card | QR | Wallet - what the customer picked on the payment screen.
    [MaxLength(50)]
    string Method = "Card",

    // Pay less than the balance (a deposit, one share of a split bill).
    decimal? Amount = null,

    [MaxLength(500)]
    string? ReturnUrl = null
);

public record CheckoutResponse(
    Guid PaymentId,
    Guid InvoiceId,
    string Provider,
    string Status,
    decimal Amount,
    string Currency,
    string? ClientSecret,
    string? RedirectUrl,
    string? PublicKey,
    string? ExternalReference,
    bool Simulated
);

public record ConfirmCheckoutRequest(
    [Required] Guid PaymentId,

    // Sandbox only: the outcome to simulate. Ignored for real providers,
    // whose status is always read back from the provider.
    bool SimulateFailure = false
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
    IReadOnlyList<PaymentResponse> Payments,
    string? BusinessName = null,
    string? CustomerName = null,
    string? CustomerEmail = null,
    string? Notes = null,
    InvoiceTemplateResponse? Template = null
);

// ==========================================
// SUBSCRIPTION DTOs
// ==========================================

public record CreateSubscriptionRequest(
    [Required(ErrorMessage = "CustomerId is required.")]
    Guid CustomerId,

    [Required(ErrorMessage = "PlanName is required.")]
    [MaxLength(100)]
    string PlanName,

    [Range(0, double.MaxValue, ErrorMessage = "Amount must not be negative.")]
    decimal Amount,

    [Required(ErrorMessage = "BillingCycle is required.")]
    [MaxLength(20)]
    string BillingCycle,

    [Required(ErrorMessage = "StartDate is required.")]
    DateTime StartDate,

    [Required(ErrorMessage = "EndDate is required.")]
    DateTime EndDate,

    bool AutoRenew = true,

    Guid? BranchId = null,

    [MaxLength(500)]
    string? Notes = null,

    // Raise the first period's invoice straight away.
    bool GenerateInvoice = false,

    [MaxLength(3)]
    string Currency = "LKR"
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
    DateTime CreatedAt,
    Guid? BranchId = null,
    string PaymentStatus = "Paid",
    DateTime? NextBillingAt = null,
    DateTime? LastPaymentAt = null,
    string? Notes = null,
    string? CustomerName = null
);

public record SubscriptionListResponse(
    IReadOnlyList<SubscriptionResponse> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages
);

public record CancelSubscriptionRequest(
    [MaxLength(500)]
    string? Reason = null,

    [Range(0, double.MaxValue, ErrorMessage = "RefundAmount must not be negative.")]
    decimal RefundAmount = 0
);

public record CancelSubscriptionResult(
    bool Applied,
    bool RequiresApproval,
    Guid? ApprovalWorkflowId,
    SubscriptionResponse Subscription,
    string Message
);

public record ChangePlanRequest(
    [Required]
    [MaxLength(100)]
    string PlanName,

    [Range(0, double.MaxValue)]
    decimal Amount,

    [MaxLength(20)]
    string? BillingCycle = null
);

public record SubscriptionPlanOption(
    string PlanName,
    decimal Amount,
    string BillingCycle,
    int ActiveMembers
);

public record RenewalCalendarEntry(
    Guid SubscriptionId,
    Guid CustomerId,
    string? CustomerName,
    string PlanName,
    decimal Amount,
    string BillingCycle,
    DateTime RenewalDate,
    bool AutoRenew,
    string Status,
    string PaymentStatus
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
    decimal ClaimAmount,

    [MaxLength(2000)]
    string? Notes = null
);

public record UpdateInsuranceClaimStatusRequest(
    [Required(ErrorMessage = "Status is required.")]
    [MaxLength(30)]
    string Status,

    string? RejectionReason = null,

    [MaxLength(2000)]
    string? Notes = null
);

public record ClaimDocument(
    string Url,
    string FileName,
    DateTime UploadedAt
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
    DateTime CreatedAt,
    DateTime? ReviewStartedAt = null,
    string? Notes = null,
    IReadOnlyList<ClaimDocument>? Documents = null,
    Guid? CustomerId = null,
    string? Currency = null,
    bool RequiresAdminApproval = false,
    Guid? PendingApprovalWorkflowId = null
);

public record InsuranceClaimListResponse(
    IReadOnlyList<InsuranceClaimResponse> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages
);

public record UpdateClaimStatusResult(
    bool Applied,
    bool RequiresApproval,
    Guid? ApprovalWorkflowId,
    InsuranceClaimResponse Claim,
    string Message
);

// ==========================================
// REPORT DTOs
// ==========================================

public record AmountByLabel(string Label, decimal Amount, int Count);

public record DailyRevenueResponse(
    DateTime Date,
    Guid? BranchId,
    decimal TotalCollected,
    int PaymentCount,
    decimal TotalInvoiced,
    int InvoiceCount,
    decimal AveragePayment,
    IReadOnlyList<AmountByLabel> ByMethod,
    IReadOnlyList<AmountByLabel> ByHour,
    IReadOnlyList<AmountByLabel> ByCurrency
);

public record AgingBucket(string Label, int MinDays, int? MaxDays, decimal Amount, int Count);

public record OutstandingInvoiceRow(
    Guid InvoiceId,
    string InvoiceNumber,
    Guid CustomerId,
    string? CustomerName,
    DateTime DueDate,
    int DaysOverdue,
    decimal FinalAmount,
    decimal BalanceDue,
    string Currency,
    string Status
);

public record OutstandingPaymentsResponse(
    int AgingDays,
    decimal TotalOutstanding,
    int Count,
    IReadOnlyList<AgingBucket> Buckets,
    IReadOnlyList<OutstandingInvoiceRow> Items
);

public record RevenuePoint(string Date, decimal Invoiced, decimal Collected);

public record BillingDashboardResponse(
    DateTime From,
    DateTime To,
    string Currency,
    decimal TotalInvoiced,
    decimal TotalCollected,
    decimal TotalOutstanding,
    decimal OverdueAmount,
    int OverdueCount,
    int ActiveSubscriptions,
    decimal MonthlyRecurringRevenue,
    int PendingClaims,
    decimal PendingClaimsAmount,
    int PendingApprovals,
    IReadOnlyList<RevenuePoint> RevenueSeries,
    IReadOnlyList<AmountByLabel> StatusBreakdown,
    IReadOnlyList<AmountByLabel> MethodBreakdown
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

public record DynamicFormResponse(
    Guid Id,
    string FormType,
    JsonElement Schema,
    JsonElement? UiSchema,
    JsonElement? ValidationRules,
    int SubmissionCount,
    DateTime CreatedAt,
    DateTime UpdatedAt
);

public record UpsertDynamicFormRequest(
    JsonElement Schema,
    JsonElement? UiSchema = null,
    JsonElement? ValidationRules = null
);

// ==========================================
// PAYMENT GATEWAY DTOs
// ==========================================

public record PaymentGatewayResponse(
    Guid Id,
    string Name,
    string Provider,
    string Currency,
    bool IsActive,
    bool IsTestMode,
    string? PublicKey,
    bool HasApiKey,
    string? ApiKeyHint,
    bool HasWebhookSecret,
    string? WebhookUrl,
    DateTime CreatedAt,
    DateTime UpdatedAt
);

public record UpsertPaymentGatewayRequest(
    [Required]
    [MaxLength(100)]
    string Name,

    // Stripe | PayPal | Manual
    [Required]
    [MaxLength(30)]
    string Provider,

    [MaxLength(3)]
    string Currency = "LKR",

    bool IsActive = true,

    bool IsTestMode = true,

    [MaxLength(300)]
    string? PublicKey = null,

    // Null on update keeps the stored key; an empty string clears it.
    [MaxLength(500)]
    string? ApiKey = null,

    [MaxLength(500)]
    string? WebhookSecret = null
);

public record GatewayTestResult(bool Ok, bool Simulated, string Message);

// ==========================================
// COMMISSION DTOs
// ==========================================

public record CommissionRuleResponse(
    Guid Id,
    string Name,
    string? Role,
    string RuleType,
    decimal Rate,
    decimal? FixedAmount,
    decimal? MinAmount,
    decimal? MaxAmount,
    string? Description,
    bool IsActive,
    DateTime? EffectiveFrom,
    DateTime? EffectiveTo
);

public record UpsertCommissionRuleRequest(
    [Required]
    [MaxLength(150)]
    string Name,

    // Percentage | Fixed
    [Required]
    [MaxLength(30)]
    string RuleType,

    [Range(0, 100)]
    decimal Rate = 0,

    [Range(0, double.MaxValue)]
    decimal? FixedAmount = null,

    [Range(0, double.MaxValue)]
    decimal? MinAmount = null,

    [Range(0, double.MaxValue)]
    decimal? MaxAmount = null,

    [MaxLength(50)]
    string? Role = null,

    [MaxLength(1000)]
    string? Description = null,

    bool IsActive = true,

    DateTime? EffectiveFrom = null,

    DateTime? EffectiveTo = null
);

public record CommissionSplitRequest(
    [Range(0.01, double.MaxValue, ErrorMessage = "DealAmount must be greater than 0.")]
    decimal DealAmount,

    // Only apply rules for these roles; empty means every active rule.
    List<string>? Roles = null,

    DateTime? AsOf = null
);

public record CommissionSplitLine(
    Guid RuleId,
    string RuleName,
    string? Role,
    string RuleType,
    decimal Rate,
    decimal Amount,
    bool Clamped
);

public record CommissionSplitResponse(
    decimal DealAmount,
    IReadOnlyList<CommissionSplitLine> Lines,
    decimal TotalCommission,
    decimal NetToBusiness
);

// ==========================================
// INVOICE TEMPLATE DTOs
// ==========================================

public record InvoiceTemplateResponse(
    Guid Id,
    string Name,
    bool IsDefault,
    JsonElement Layout,
    string AccentColor,
    string? HeaderText,
    string? FooterText,
    DateTime UpdatedAt
);

public record UpsertInvoiceTemplateRequest(
    [Required]
    [MaxLength(100)]
    string Name,

    JsonElement Layout,

    [MaxLength(20)]
    string AccentColor = "#2563eb",

    [MaxLength(500)]
    string? HeaderText = null,

    [MaxLength(1000)]
    string? FooterText = null,

    bool IsDefault = false
);
