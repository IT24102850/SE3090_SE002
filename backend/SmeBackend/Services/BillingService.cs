using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;

namespace SmeBackend.Services;

public class BillingService : IBillingService
{
    private readonly AppDbContext _db;
    private const int MaxPageSize = 100;

    private static readonly HashSet<string> AllowedBillingCycles = new(StringComparer.OrdinalIgnoreCase)
    {
        "Weekly", "Monthly", "Quarterly", "Yearly"
    };

    private static readonly HashSet<string> AllowedClaimStatuses = new(StringComparer.OrdinalIgnoreCase)
    {
        "Submitted", "Pending", "Approved", "Rejected"
    };

    public BillingService(AppDbContext db)
    {
        _db = db;
    }

    // ==========================================
    // INVOICES
    // ==========================================

    public async Task<InvoiceListResponse> GetInvoicesAsync(
        Guid tenantId,
        int page,
        int pageSize,
        string? status = null,
        Guid? customerId = null,
        CancellationToken cancellationToken = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);

        var query = _db.Invoices
            .Include(i => i.Items)
            .Include(i => i.Payments)
            .AsNoTracking()
            .Where(i => i.TenantId == tenantId);

        if (!string.IsNullOrWhiteSpace(status))
        {
            var trimmed = status.Trim();
            query = query.Where(i => EF.Functions.ILike(i.Status, trimmed));
        }

        if (customerId.HasValue && customerId.Value != Guid.Empty)
        {
            query = query.Where(i => i.CustomerId == customerId.Value);
        }

        var totalCount = await query.CountAsync(cancellationToken);
        var items = await query
            .OrderByDescending(i => i.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(cancellationToken);

        var totalPages = (int)Math.Ceiling(totalCount / (double)pageSize);

        return new InvoiceListResponse(
            items.Select(MapToInvoiceResponse).ToList(),
            page,
            pageSize,
            totalCount,
            totalPages
        );
    }

    public async Task<(bool Success, string? Error, InvoiceResponse? Invoice)> CreateInvoiceAsync(
        Guid tenantId,
        CreateInvoiceRequest request,
        CancellationToken cancellationToken = default)
    {
        if (request.Items == null || request.Items.Count == 0)
        {
            return (false, "Invoice must contain at least one item.", null);
        }

        if (request.CustomerId == Guid.Empty)
        {
            return (false, "Valid CustomerId is required.", null);
        }

        // Generate or validate InvoiceNumber
        string invoiceNumber;
        if (!string.IsNullOrWhiteSpace(request.InvoiceNumber))
        {
            invoiceNumber = request.InvoiceNumber.Trim();
            var exists = await _db.Invoices.AnyAsync(
                i => i.TenantId == tenantId && i.InvoiceNumber == invoiceNumber,
                cancellationToken);

            if (exists)
            {
                return (false, $"Invoice number '{invoiceNumber}' already exists for this tenant.", null);
            }
        }
        else
        {
            invoiceNumber = $"INV-{DateTime.UtcNow:yyyyMMdd}-{Guid.NewGuid().ToString("N")[..6].ToUpper()}";
        }

        // Secure server-side calculation of financial amounts
        var invoiceItems = new List<InvoiceItem>();
        decimal calculatedTotal = 0;

        foreach (var itemDto in request.Items)
        {
            if (string.IsNullOrWhiteSpace(itemDto.Description))
            {
                return (false, "Item description cannot be empty.", null);
            }

            if (itemDto.Quantity <= 0)
            {
                return (false, "Item quantity must be greater than 0.", null);
            }

            if (itemDto.UnitPrice < 0)
            {
                return (false, "Item unit price cannot be negative.", null);
            }

            var itemAmount = Math.Round(itemDto.Quantity * itemDto.UnitPrice, 2, MidpointRounding.AwayFromZero);
            calculatedTotal += itemAmount;

            invoiceItems.Add(new InvoiceItem
            {
                Description = itemDto.Description.Trim(),
                Quantity = itemDto.Quantity,
                UnitPrice = Math.Round(itemDto.UnitPrice, 2, MidpointRounding.AwayFromZero),
                Amount = itemAmount,
                Category = string.IsNullOrWhiteSpace(itemDto.Category) ? "General" : itemDto.Category.Trim()
            });
        }

        var discount = Math.Max(0, Math.Round(request.Discount, 2, MidpointRounding.AwayFromZero));
        var tax = Math.Max(0, Math.Round(request.Tax, 2, MidpointRounding.AwayFromZero));
        var finalAmount = Math.Max(0, calculatedTotal + tax - discount);

        var invoice = new Invoice
        {
            TenantId = tenantId,
            CustomerId = request.CustomerId,
            BookingId = request.BookingId,
            InvoiceNumber = invoiceNumber,
            TotalAmount = calculatedTotal,
            Discount = discount,
            Tax = tax,
            FinalAmount = finalAmount,
            Status = "Issued",
            DueDate = DateTime.SpecifyKind(request.DueDate, DateTimeKind.Utc),
            Currency = string.IsNullOrWhiteSpace(request.Currency) ? "LKR" : request.Currency.Trim().ToUpper(),
            Items = invoiceItems
        };

        _db.Invoices.Add(invoice);
        await _db.SaveChangesAsync(cancellationToken);

        return (true, null, MapToInvoiceResponse(invoice));
    }

    public async Task<(bool Success, string? Error, PaymentResponse? Payment, InvoiceResponse? Invoice)> PayInvoiceAsync(
        Guid tenantId,
        Guid invoiceId,
        PayInvoiceRequest request,
        CancellationToken cancellationToken = default)
    {
        if (request.Amount <= 0)
        {
            return (false, "Payment amount must be greater than 0.", null, null);
        }

        if (string.IsNullOrWhiteSpace(request.Method))
        {
            return (false, "Payment method is required.", null, null);
        }

        var invoice = await _db.Invoices
            .Include(i => i.Items)
            .Include(i => i.Payments)
            .FirstOrDefaultAsync(i => i.Id == invoiceId && i.TenantId == tenantId, cancellationToken);

        if (invoice == null)
        {
            return (false, "Invoice not found.", null, null);
        }

        if (invoice.Status.Equals("Cancelled", StringComparison.OrdinalIgnoreCase))
        {
            return (false, "Cannot record payment on a cancelled invoice.", null, null);
        }

        var paidSoFar = invoice.Payments.Sum(p => p.Amount);
        var remainingBalance = invoice.FinalAmount - paidSoFar;

        if (remainingBalance <= 0 || invoice.Status.Equals("Paid", StringComparison.OrdinalIgnoreCase))
        {
            return (false, "Invoice is already fully paid.", null, null);
        }

        var paymentAmount = Math.Round(request.Amount, 2, MidpointRounding.AwayFromZero);
        if (paymentAmount > remainingBalance)
        {
            return (false, $"Payment amount ({paymentAmount:N2}) exceeds outstanding balance ({remainingBalance:N2}).", null, null);
        }

        var payment = new Payment
        {
            InvoiceId = invoice.Id,
            Amount = paymentAmount,
            Method = request.Method.Trim(),
            TransactionRef = request.TransactionRef?.Trim(),
            GatewayResponse = request.GatewayResponse,
            PaidAt = DateTime.UtcNow
        };

        _db.Payments.Add(payment);

        var newTotalPaid = paidSoFar + paymentAmount;
        invoice.Status = newTotalPaid >= invoice.FinalAmount ? "Paid" : "PartiallyPaid";

        await _db.SaveChangesAsync(cancellationToken);

        var paymentResponse = new PaymentResponse(
            payment.Id,
            payment.InvoiceId,
            payment.Amount,
            payment.Method,
            payment.TransactionRef,
            payment.GatewayResponse,
            payment.PaidAt,
            payment.CreatedAt
        );

        return (true, null, paymentResponse, MapToInvoiceResponse(invoice));
    }

    public async Task<(bool Success, string? Error, ReceiptResponse? Receipt)> GetReceiptAsync(
        Guid tenantId,
        Guid invoiceId,
        CancellationToken cancellationToken = default)
    {
        var invoice = await _db.Invoices
            .Include(i => i.Items)
            .Include(i => i.Payments)
            .AsNoTracking()
            .FirstOrDefaultAsync(i => i.Id == invoiceId && i.TenantId == tenantId, cancellationToken);

        if (invoice == null)
        {
            return (false, "Invoice not found.", null);
        }

        var totalPaid = invoice.Payments.Sum(p => p.Amount);
        var balanceDue = Math.Max(0, invoice.FinalAmount - totalPaid);

        var items = invoice.Items.Select(i => new InvoiceItemResponse(
            i.Id,
            i.Description,
            i.Quantity,
            i.UnitPrice,
            i.Amount,
            i.Category
        )).ToList();

        var payments = invoice.Payments.OrderByDescending(p => p.PaidAt ?? p.CreatedAt)
            .Select(p => new PaymentResponse(
                p.Id,
                p.InvoiceId,
                p.Amount,
                p.Method,
                p.TransactionRef,
                p.GatewayResponse,
                p.PaidAt,
                p.CreatedAt
            )).ToList();

        var receipt = new ReceiptResponse(
            $"REC-{invoice.InvoiceNumber}",
            invoice.Id,
            invoice.InvoiceNumber,
            invoice.CustomerId,
            invoice.BookingId,
            invoice.DueDate,
            invoice.Currency,
            invoice.TotalAmount,
            invoice.Discount,
            invoice.Tax,
            invoice.FinalAmount,
            totalPaid,
            balanceDue,
            invoice.Status,
            DateTime.UtcNow,
            items,
            payments
        );

        return (true, null, receipt);
    }

    // ==========================================
    // SUBSCRIPTIONS
    // ==========================================

    public async Task<SubscriptionListResponse> GetSubscriptionsAsync(
        Guid tenantId,
        int page,
        int pageSize,
        string? status = null,
        Guid? customerId = null,
        CancellationToken cancellationToken = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);

        var query = _db.Subscriptions
            .AsNoTracking()
            .Where(s => s.TenantId == tenantId);

        if (!string.IsNullOrWhiteSpace(status))
        {
            var trimmed = status.Trim();
            query = query.Where(s => EF.Functions.ILike(s.Status, trimmed));
        }

        if (customerId.HasValue && customerId.Value != Guid.Empty)
        {
            query = query.Where(s => s.CustomerId == customerId.Value);
        }

        var totalCount = await query.CountAsync(cancellationToken);
        var items = await query
            .OrderByDescending(s => s.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(cancellationToken);

        var totalPages = (int)Math.Ceiling(totalCount / (double)pageSize);

        var responses = items.Select(s => new SubscriptionResponse(
            s.Id,
            s.TenantId,
            s.CustomerId,
            s.PlanName,
            s.Amount,
            s.BillingCycle,
            s.StartDate,
            s.EndDate,
            s.AutoRenew,
            s.Status,
            s.CreatedAt
        )).ToList();

        return new SubscriptionListResponse(responses, page, pageSize, totalCount, totalPages);
    }

    public async Task<(bool Success, string? Error, SubscriptionResponse? Subscription)> CreateSubscriptionAsync(
        Guid tenantId,
        CreateSubscriptionRequest request,
        CancellationToken cancellationToken = default)
    {
        if (request.CustomerId == Guid.Empty)
        {
            return (false, "Valid CustomerId is required.", null);
        }

        if (string.IsNullOrWhiteSpace(request.PlanName))
        {
            return (false, "PlanName is required.", null);
        }

        if (request.Amount < 0)
        {
            return (false, "Amount cannot be negative.", null);
        }

        var normalizedCycle = request.BillingCycle?.Trim();
        if (string.IsNullOrEmpty(normalizedCycle) || !AllowedBillingCycles.Contains(normalizedCycle))
        {
            return (false, "BillingCycle must be one of: Weekly, Monthly, Quarterly, Yearly.", null);
        }

        var startDate = DateTime.SpecifyKind(request.StartDate, DateTimeKind.Utc);
        var endDate = DateTime.SpecifyKind(request.EndDate, DateTimeKind.Utc);

        if (endDate <= startDate)
        {
            return (false, "EndDate must be later than StartDate.", null);
        }

        var subscription = new Subscription
        {
            TenantId = tenantId,
            CustomerId = request.CustomerId,
            PlanName = request.PlanName.Trim(),
            Amount = Math.Round(request.Amount, 2, MidpointRounding.AwayFromZero),
            BillingCycle = normalizedCycle,
            StartDate = startDate,
            EndDate = endDate,
            AutoRenew = request.AutoRenew,
            Status = "Active"
        };

        _db.Subscriptions.Add(subscription);
        await _db.SaveChangesAsync(cancellationToken);

        var response = new SubscriptionResponse(
            subscription.Id,
            subscription.TenantId,
            subscription.CustomerId,
            subscription.PlanName,
            subscription.Amount,
            subscription.BillingCycle,
            subscription.StartDate,
            subscription.EndDate,
            subscription.AutoRenew,
            subscription.Status,
            subscription.CreatedAt
        );

        return (true, null, response);
    }

    public async Task<(bool Success, string? Error, SubscriptionResponse? Subscription)> CancelSubscriptionAsync(
        Guid tenantId,
        Guid subscriptionId,
        CancellationToken cancellationToken = default)
    {
        var subscription = await _db.Subscriptions
            .FirstOrDefaultAsync(s => s.Id == subscriptionId && s.TenantId == tenantId, cancellationToken);

        if (subscription == null)
        {
            return (false, "Subscription not found.", null);
        }

        if (subscription.Status.Equals("Cancelled", StringComparison.OrdinalIgnoreCase))
        {
            return (false, "Subscription is already cancelled.", null);
        }

        subscription.Status = "Cancelled";
        subscription.AutoRenew = false;

        await _db.SaveChangesAsync(cancellationToken);

        var response = new SubscriptionResponse(
            subscription.Id,
            subscription.TenantId,
            subscription.CustomerId,
            subscription.PlanName,
            subscription.Amount,
            subscription.BillingCycle,
            subscription.StartDate,
            subscription.EndDate,
            subscription.AutoRenew,
            subscription.Status,
            subscription.CreatedAt
        );

        return (true, null, response);
    }

    // ==========================================
    // INSURANCE CLAIMS
    // ==========================================

    public async Task<InsuranceClaimListResponse> GetInsuranceClaimsAsync(
        Guid tenantId,
        int page,
        int pageSize,
        string? status = null,
        CancellationToken cancellationToken = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);

        var query = _db.InsuranceClaims
            .Include(c => c.Invoice)
            .AsNoTracking()
            .Where(c => c.Invoice != null && c.Invoice.TenantId == tenantId);

        if (!string.IsNullOrWhiteSpace(status))
        {
            var trimmed = status.Trim();
            query = query.Where(c => EF.Functions.ILike(c.Status, trimmed));
        }

        var totalCount = await query.CountAsync(cancellationToken);
        var items = await query
            .OrderByDescending(c => c.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(cancellationToken);

        var totalPages = (int)Math.Ceiling(totalCount / (double)pageSize);

        var responses = items.Select(c => new InsuranceClaimResponse(
            c.Id,
            c.InvoiceId,
            c.Invoice?.InvoiceNumber,
            c.Provider,
            c.PolicyNumber,
            c.ClaimAmount,
            c.Status,
            c.SubmittedAt,
            c.ApprovedAt,
            c.RejectionReason,
            c.CreatedAt
        )).ToList();

        return new InsuranceClaimListResponse(responses, page, pageSize, totalCount, totalPages);
    }

    public async Task<(bool Success, string? Error, InsuranceClaimResponse? Claim)> CreateInsuranceClaimAsync(
        Guid tenantId,
        CreateInsuranceClaimRequest request,
        CancellationToken cancellationToken = default)
    {
        if (request.ClaimAmount <= 0)
        {
            return (false, "ClaimAmount must be greater than 0.", null);
        }

        if (string.IsNullOrWhiteSpace(request.Provider))
        {
            return (false, "Provider is required.", null);
        }

        if (string.IsNullOrWhiteSpace(request.PolicyNumber))
        {
            return (false, "PolicyNumber is required.", null);
        }

        var invoice = await _db.Invoices
            .AsNoTracking()
            .FirstOrDefaultAsync(i => i.Id == request.InvoiceId && i.TenantId == tenantId, cancellationToken);

        if (invoice == null)
        {
            return (false, "Invoice not found for the current tenant.", null);
        }

        var claim = new InsuranceClaim
        {
            InvoiceId = invoice.Id,
            Provider = request.Provider.Trim(),
            PolicyNumber = request.PolicyNumber.Trim(),
            ClaimAmount = Math.Round(request.ClaimAmount, 2, MidpointRounding.AwayFromZero),
            Status = "Submitted",
            SubmittedAt = DateTime.UtcNow
        };

        _db.InsuranceClaims.Add(claim);
        await _db.SaveChangesAsync(cancellationToken);

        var response = new InsuranceClaimResponse(
            claim.Id,
            claim.InvoiceId,
            invoice.InvoiceNumber,
            claim.Provider,
            claim.PolicyNumber,
            claim.ClaimAmount,
            claim.Status,
            claim.SubmittedAt,
            claim.ApprovedAt,
            claim.RejectionReason,
            claim.CreatedAt
        );

        return (true, null, response);
    }

    public async Task<(bool Success, string? Error, InsuranceClaimResponse? Claim)> UpdateInsuranceClaimStatusAsync(
        Guid tenantId,
        Guid claimId,
        UpdateInsuranceClaimStatusRequest request,
        CancellationToken cancellationToken = default)
    {
        var normalizedStatus = request.Status?.Trim();
        if (string.IsNullOrEmpty(normalizedStatus) || !AllowedClaimStatuses.Contains(normalizedStatus))
        {
            return (false, "Status must be one of: Submitted, Pending, Approved, Rejected.", null);
        }

        var claim = await _db.InsuranceClaims
            .Include(c => c.Invoice)
            .FirstOrDefaultAsync(c => c.Id == claimId && c.Invoice != null && c.Invoice.TenantId == tenantId, cancellationToken);

        if (claim == null)
        {
            return (false, "Insurance claim not found.", null);
        }

        claim.Status = normalizedStatus;

        if (normalizedStatus.Equals("Approved", StringComparison.OrdinalIgnoreCase))
        {
            claim.ApprovedAt = DateTime.UtcNow;
            claim.RejectionReason = null;
        }
        else if (normalizedStatus.Equals("Rejected", StringComparison.OrdinalIgnoreCase))
        {
            claim.RejectionReason = request.RejectionReason?.Trim();
        }

        await _db.SaveChangesAsync(cancellationToken);

        var response = new InsuranceClaimResponse(
            claim.Id,
            claim.InvoiceId,
            claim.Invoice?.InvoiceNumber,
            claim.Provider,
            claim.PolicyNumber,
            claim.ClaimAmount,
            claim.Status,
            claim.SubmittedAt,
            claim.ApprovedAt,
            claim.RejectionReason,
            claim.CreatedAt
        );

        return (true, null, response);
    }

    // ==========================================
    // HELPERS
    // ==========================================

    private static InvoiceResponse MapToInvoiceResponse(Invoice invoice)
    {
        var items = invoice.Items?.Select(i => new InvoiceItemResponse(
            i.Id,
            i.Description,
            i.Quantity,
            i.UnitPrice,
            i.Amount,
            i.Category
        )).ToList() ?? new List<InvoiceItemResponse>();

        var payments = invoice.Payments?.Select(p => new PaymentResponse(
            p.Id,
            p.InvoiceId,
            p.Amount,
            p.Method,
            p.TransactionRef,
            p.GatewayResponse,
            p.PaidAt,
            p.CreatedAt
        )).ToList() ?? new List<PaymentResponse>();

        return new InvoiceResponse(
            invoice.Id,
            invoice.TenantId,
            invoice.CustomerId,
            invoice.BookingId,
            invoice.InvoiceNumber,
            invoice.TotalAmount,
            invoice.Discount,
            invoice.Tax,
            invoice.FinalAmount,
            invoice.Status,
            invoice.DueDate,
            invoice.Currency,
            invoice.CreatedAt,
            items,
            payments
        );
    }
}
