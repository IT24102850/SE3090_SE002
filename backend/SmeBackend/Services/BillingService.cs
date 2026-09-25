using System.Globalization;
using System.Net;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Services.Billing;

namespace SmeBackend.Services;

public class BillingService : IBillingService
{
    private readonly AppDbContext _db;
    private readonly IBillingApprovalService _approvals;
    private readonly IBillingMessenger _messenger;
    private const int MaxPageSize = 100;

    public static readonly string[] BillingCycles = { "Weekly", "Monthly", "Quarterly", "Yearly", "OneOff" };

    private static readonly HashSet<string> AllowedBillingCycles = new(BillingCycles, StringComparer.OrdinalIgnoreCase);

    public static readonly string[] ClaimStatuses = { "Submitted", "UnderReview", "Approved", "Rejected" };

    public BillingService(AppDbContext db, IBillingApprovalService approvals, IBillingMessenger messenger)
    {
        _db = db;
        _approvals = approvals;
        _messenger = messenger;
    }

    // ==========================================
    // INVOICES
    // ==========================================

    public async Task<InvoiceListResponse> GetInvoicesAsync(BillingActor actor, InvoiceQuery q, CancellationToken ct = default)
    {
        var page = Math.Max(1, q.Page);
        var pageSize = Math.Clamp(q.PageSize, 1, MaxPageSize);
        var now = DateTime.UtcNow;

        var query = InvoicesFor(actor).AsNoTracking();

        if (!string.IsNullOrWhiteSpace(q.Status))
        {
            var status = q.Status.Trim();
            query = status.Equals(InvoiceStatuses.Overdue, StringComparison.OrdinalIgnoreCase)
                ? query.Where(i => (i.Status == InvoiceStatuses.Issued || i.Status == InvoiceStatuses.PartiallyPaid || i.Status == InvoiceStatuses.Overdue) && i.DueDate < now)
                : query.Where(i => i.Status.ToLower() == status.ToLower());
        }

        if (!actor.IsCustomer && q.CustomerId is { } customerId && customerId != Guid.Empty)
            query = query.Where(i => i.CustomerId == customerId);
        if (q.BranchId is { } branchId && branchId != Guid.Empty)
            query = query.Where(i => i.BranchId == branchId);
        if (q.From is { } from)
            query = query.Where(i => i.CreatedAt >= Utc(from));
        if (q.To is { } to)
            query = query.Where(i => i.CreatedAt < Utc(to).Date.AddDays(1));
        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            var term = q.Search.Trim().ToLower();
            query = query.Where(i => i.InvoiceNumber.ToLower().Contains(term));
        }

        var totalCount = await query.CountAsync(ct);
        var items = await query
            .Include(i => i.Items)
            .Include(i => i.Payments)
            .OrderByDescending(i => i.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);

        var people = await LoadPeopleAsync(actor.TenantId, items.Select(i => i.CustomerId), ct);
        var totalPages = (int)Math.Ceiling(totalCount / (double)pageSize);

        return new InvoiceListResponse(
            items.Select(i => MapInvoice(i, people)).ToList(), page, pageSize, totalCount, totalPages);
    }

    public async Task<BillingResult<InvoiceResponse>> GetInvoiceAsync(BillingActor actor, Guid invoiceId, CancellationToken ct = default)
    {
        var invoice = await LoadInvoiceAsync(actor, invoiceId, tracking: false, ct);
        if (invoice is null) return BillingResult<InvoiceResponse>.NotFound("Invoice not found.");
        var people = await LoadPeopleAsync(actor.TenantId, new[] { invoice.CustomerId }, ct);
        return BillingResult<InvoiceResponse>.Ok(MapInvoice(invoice, people));
    }

    public async Task<BillingResult<InvoiceResponse>> CreateInvoiceAsync(BillingActor actor, CreateInvoiceRequest request, CancellationToken ct = default)
    {
        if (request.Items == null || request.Items.Count == 0)
            return BillingResult<InvoiceResponse>.BadRequest("Invoice must contain at least one item.");
        if (request.CustomerId == Guid.Empty)
            return BillingResult<InvoiceResponse>.BadRequest("Valid CustomerId is required.");

        var tenantId = actor.TenantId;
        var reference = await ValidateReferencesAsync(tenantId, request.CustomerId, request.BookingId,
            request.SubscriptionId, request.TemplateId, request.BranchId, ct);
        if (reference is not null) return BillingResult<InvoiceResponse>.BadRequest(reference);

        string invoiceNumber;
        if (!string.IsNullOrWhiteSpace(request.InvoiceNumber))
        {
            invoiceNumber = request.InvoiceNumber.Trim();
            var exists = await _db.Invoices.AnyAsync(i => i.TenantId == tenantId && i.InvoiceNumber == invoiceNumber, ct);
            if (exists)
                return BillingResult<InvoiceResponse>.BadRequest($"Invoice number '{invoiceNumber}' already exists for this tenant.");
        }
        else
        {
            invoiceNumber = NewInvoiceNumber();
        }

        // Server-side calculation: the client never decides what anything costs.
        var items = new List<InvoiceItem>();
        foreach (var dto in request.Items)
        {
            if (string.IsNullOrWhiteSpace(dto.Description))
                return BillingResult<InvoiceResponse>.BadRequest("Item description cannot be empty.");
            if (dto.Quantity <= 0)
                return BillingResult<InvoiceResponse>.BadRequest("Item quantity must be greater than 0.");
            if (dto.UnitPrice < 0)
                return BillingResult<InvoiceResponse>.BadRequest("Item unit price cannot be negative.");

            var unitPrice = BillingRules.Round(dto.UnitPrice);
            items.Add(new InvoiceItem
            {
                Description = dto.Description.Trim(),
                Quantity = dto.Quantity,
                UnitPrice = unitPrice,
                Amount = BillingRules.Round(dto.Quantity * unitPrice),
                Category = string.IsNullOrWhiteSpace(dto.Category) ? "General" : dto.Category.Trim(),
            });
        }

        var subtotal = items.Sum(i => i.Amount);
        var discount = request.DiscountPercent is { } dp
            ? BillingRules.Round(subtotal * dp / 100m)
            : Math.Max(0, BillingRules.Round(request.Discount));
        var tax = request.TaxRatePercent is { } tr
            ? BillingRules.Round(Math.Max(0, subtotal - discount) * tr / 100m)
            : Math.Max(0, BillingRules.Round(request.Tax));

        var validation = BillingRules.ValidateInvoice(
            items.Select(i => new BillingRules.DraftLine(i.Quantity, i.UnitPrice)).ToList(), discount, tax);
        if (!validation.IsValid)
        {
            return BillingResult<InvoiceResponse>.BadRequest(
                string.Join(" ", validation.Issues.Where(i => i.Severity == "error").Select(i => i.Message)));
        }

        var invoice = new Invoice
        {
            TenantId = tenantId,
            BranchId = request.BranchId,
            CustomerId = request.CustomerId,
            BookingId = request.BookingId,
            SubscriptionId = request.SubscriptionId,
            TemplateId = request.TemplateId,
            InvoiceNumber = invoiceNumber,
            TotalAmount = subtotal,
            Discount = discount,
            DiscountCode = string.IsNullOrWhiteSpace(request.DiscountCode) ? null : request.DiscountCode.Trim().ToUpperInvariant(),
            Tax = tax,
            FinalAmount = validation.FinalAmount,
            Status = InvoiceStatuses.Issued,
            DueDate = Utc(request.DueDate),
            Currency = NormalizeCurrency(request.Currency),
            Notes = string.IsNullOrWhiteSpace(request.Notes) ? null : request.Notes.Trim(),
            Items = items,
        };

        _db.Invoices.Add(invoice);
        await _db.SaveChangesAsync(ct);

        // Rule warnings do not block the invoice, but the agent flags it for
        // a human to look at (e.g. a discount above the cap).
        var warnings = validation.Issues.Where(i => i.Severity == "warning").ToList();
        if (warnings.Count > 0)
        {
            await _approvals.RequestApprovalAsync(
                tenantId, BillingActionTypes.ReviewInvoice, "Invoice", invoice.Id,
                $"Review {invoice.InvoiceNumber}: {warnings[0].Message}",
                invoice.FinalAmount, requiresAdmin: false,
                reason: string.Join(" ", warnings.Select(w => w.Message)),
                new Dictionary<string, object?>
                {
                    ["invoiceNumber"] = invoice.InvoiceNumber,
                    ["issues"] = warnings.Select(w => w.Code).ToList(),
                    ["discountPercent"] = validation.DiscountPercent,
                    ["taxPercent"] = validation.TaxPercent,
                },
                source: "agent", requestedBy: actor.UserId, ct);
        }

        var people = await LoadPeopleAsync(tenantId, new[] { invoice.CustomerId }, ct);
        return BillingResult<InvoiceResponse>.Created(MapInvoice(invoice, people) with { ValidationIssues = validation.Issues });
    }

    public async Task<BillingResult<AdjustInvoiceResult>> AdjustInvoiceAsync(BillingActor actor, Guid invoiceId, AdjustInvoiceRequest request, CancellationToken ct = default)
    {
        if (request.Discount is null && request.Tax is null)
            return BillingResult<AdjustInvoiceResult>.BadRequest("Provide a new discount and/or tax.");

        var invoice = await LoadInvoiceAsync(actor, invoiceId, tracking: true, ct);
        if (invoice is null) return BillingResult<AdjustInvoiceResult>.NotFound("Invoice not found.");
        if (invoice.Status == InvoiceStatuses.Cancelled)
            return BillingResult<AdjustInvoiceResult>.BadRequest("A cancelled invoice cannot be adjusted.");

        if (await _approvals.FindPendingApprovalAsync(actor.TenantId, BillingActionTypes.AdjustInvoice, invoice.Id, ct) is { })
            return BillingResult<AdjustInvoiceResult>.Conflict("An adjustment to this invoice is already waiting for approval.");

        var discount = BillingRules.Round(request.Discount ?? invoice.Discount);
        var tax = BillingRules.Round(request.Tax ?? invoice.Tax);
        var check = BillingRules.ValidateInvoice(
            invoice.Items.Select(i => new BillingRules.DraftLine(i.Quantity, i.UnitPrice)).ToList(), discount, tax);
        if (!check.IsValid)
            return BillingResult<AdjustInvoiceResult>.BadRequest(string.Join(" ", check.Issues.Where(i => i.Severity == "error").Select(i => i.Message)));

        var newFinal = Math.Max(0, BillingRules.Round(invoice.TotalAmount - discount + tax));
        var paid = PaidAmount(invoice);
        if (newFinal < paid)
            return BillingResult<AdjustInvoiceResult>.BadRequest($"The adjusted total ({newFinal:N2}) would be below what has already been paid ({paid:N2}).");

        var delta = newFinal - invoice.FinalAmount;
        var parameters = new Dictionary<string, object?>
        {
            ["discount"] = discount,
            ["tax"] = tax,
            ["previousDiscount"] = invoice.Discount,
            ["previousTax"] = invoice.Tax,
            ["previousFinal"] = invoice.FinalAmount,
            ["newFinal"] = newFinal,
            ["invoiceNumber"] = invoice.InvoiceNumber,
        };
        var people = await LoadPeopleAsync(actor.TenantId, new[] { invoice.CustomerId }, ct);

        if (BillingRules.AdjustmentRequiresApproval(delta) && !actor.IsAdmin)
        {
            var wf = await _approvals.RequestApprovalAsync(
                actor.TenantId, BillingActionTypes.AdjustInvoice, "Invoice", invoice.Id,
                $"Adjust {invoice.InvoiceNumber} ({invoice.FinalAmount:N2} -> {newFinal:N2})",
                Math.Abs(delta), requiresAdmin: true, request.Reason.Trim(), parameters, "user", actor.UserId, ct);

            return BillingResult<AdjustInvoiceResult>.Accepted(new AdjustInvoiceResult(false, true, wf.Id, MapInvoice(invoice, people),
                $"The change of {Math.Abs(delta):N2} is above the approval threshold - sent to an Admin for approval."));
        }

        var before = invoice.FinalAmount;
        invoice.Discount = discount;
        invoice.Tax = tax;
        invoice.FinalAmount = newFinal;
        invoice.Status = InvoiceStatuses.FromBalance(newFinal, paid, invoice.Status);
        invoice.Notes = AppendNote(invoice.Notes, $"Adjusted {before:N2} -> {newFinal:N2}: {request.Reason.Trim()}");
        invoice.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        Guid? auditId = null;
        if (BillingRules.AdjustmentRequiresApproval(delta) && actor.UserId is { } adminId)
        {
            var audit = await _approvals.RecordApprovedActionAsync(
                actor.TenantId, BillingActionTypes.AdjustInvoice, "Invoice", invoice.Id,
                $"Adjust {invoice.InvoiceNumber} ({before:N2} -> {newFinal:N2})", Math.Abs(delta),
                request.Reason.Trim(), parameters, adminId, "Applied directly by an Admin.", ct);
            auditId = audit.Id;
        }

        return BillingResult<AdjustInvoiceResult>.Ok(new AdjustInvoiceResult(true, false, auditId, MapInvoice(invoice, people),
            $"{invoice.InvoiceNumber} adjusted: payable {before:N2} -> {newFinal:N2}."));
    }

    public async Task<BillingResult<InvoiceResponse>> CancelInvoiceAsync(BillingActor actor, Guid invoiceId, CancelInvoiceRequest request, CancellationToken ct = default)
    {
        var invoice = await LoadInvoiceAsync(actor, invoiceId, tracking: true, ct);
        if (invoice is null) return BillingResult<InvoiceResponse>.NotFound("Invoice not found.");
        if (invoice.Status == InvoiceStatuses.Cancelled)
            return BillingResult<InvoiceResponse>.BadRequest("The invoice is already cancelled.");
        if (PaidAmount(invoice) > 0)
            return BillingResult<InvoiceResponse>.BadRequest("An invoice with payments cannot be cancelled; refund the payments first.");

        invoice.Status = InvoiceStatuses.Cancelled;
        if (!string.IsNullOrWhiteSpace(request.Reason))
            invoice.Notes = AppendNote(invoice.Notes, $"Cancelled: {request.Reason.Trim()}");
        invoice.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        var people = await LoadPeopleAsync(actor.TenantId, new[] { invoice.CustomerId }, ct);
        return BillingResult<InvoiceResponse>.Ok(MapInvoice(invoice, people));
    }

    public async Task<BillingResult<PaymentScheduleResponse>> CreatePaymentScheduleAsync(BillingActor actor, CreatePaymentScheduleRequest request, CancellationToken ct = default)
    {
        if (request.Parts is null || request.Parts.Count == 0)
            return BillingResult<PaymentScheduleResponse>.BadRequest("A schedule needs at least one part.");
        if (request.Parts.Count > 36)
            return BillingResult<PaymentScheduleResponse>.BadRequest("A schedule can have at most 36 parts.");

        var reference = await ValidateReferencesAsync(actor.TenantId, request.CustomerId, request.BookingId, null, null, request.BranchId, ct);
        if (reference is not null) return BillingResult<PaymentScheduleResponse>.BadRequest(reference);

        var total = BillingRules.Round(request.TotalAmount);
        var amounts = new List<decimal>();
        foreach (var part in request.Parts)
        {
            if (part.Amount is null && part.Percent is null)
                return BillingResult<PaymentScheduleResponse>.BadRequest($"Part '{part.Label}' needs an amount or a percentage.");
            var amount = part.Amount ?? BillingRules.Round(total * part.Percent!.Value / 100m);
            if (amount <= 0)
                return BillingResult<PaymentScheduleResponse>.BadRequest($"Part '{part.Label}' must be greater than 0.");
            amounts.Add(BillingRules.Round(amount));
        }

        // Percentages rarely divide evenly - the last part absorbs the cents.
        var diff = total - amounts.Sum();
        if (Math.Abs(diff) > 0.05m * request.Parts.Count)
            return BillingResult<PaymentScheduleResponse>.BadRequest($"The parts add up to {amounts.Sum():N2}, not the total of {total:N2}.");
        amounts[^1] = BillingRules.Round(amounts[^1] + diff);

        var group = $"SCH-{DateTime.UtcNow:yyyyMMdd}-{Guid.NewGuid().ToString("N")[..6].ToUpperInvariant()}";
        var currency = NormalizeCurrency(request.Currency);
        var invoices = new List<Invoice>();

        for (var k = 0; k < request.Parts.Count; k++)
        {
            var part = request.Parts[k];
            var amount = amounts[k];
            var tax = request.TaxRatePercent is { } tr ? BillingRules.Round(amount * tr / 100m) : 0;
            var invoice = new Invoice
            {
                TenantId = actor.TenantId,
                BranchId = request.BranchId,
                CustomerId = request.CustomerId,
                BookingId = request.BookingId,
                InvoiceNumber = $"{NewInvoiceNumber()}-{k + 1}",
                TotalAmount = amount,
                Tax = tax,
                FinalAmount = amount + tax,
                Status = InvoiceStatuses.Issued,
                DueDate = Utc(part.DueDate),
                Currency = currency,
                ScheduleGroup = group,
                ScheduleLabel = part.Label.Trim(),
                Items = new List<InvoiceItem>
                {
                    new()
                    {
                        Description = $"{request.Description.Trim()} - {part.Label.Trim()}",
                        Quantity = 1,
                        UnitPrice = amount,
                        Amount = amount,
                        Category = string.IsNullOrWhiteSpace(request.Category) ? "General" : request.Category.Trim(),
                    },
                },
            };
            invoices.Add(invoice);
            _db.Invoices.Add(invoice);
        }

        await _db.SaveChangesAsync(ct);
        var people = await LoadPeopleAsync(actor.TenantId, new[] { request.CustomerId }, ct);
        return BillingResult<PaymentScheduleResponse>.Created(new PaymentScheduleResponse(
            group, total, currency, invoices.Select(i => MapInvoice(i, people)).ToList()));
    }

    // ==========================================
    // PAYMENTS
    // ==========================================

    public async Task<BillingResult<(PaymentResponse Payment, InvoiceResponse Invoice)>> PayInvoiceAsync(
        BillingActor actor, Guid invoiceId, PayInvoiceRequest request, CancellationToken ct = default)
    {
        if (request.Amount <= 0)
            return BillingResult<(PaymentResponse, InvoiceResponse)>.BadRequest("Payment amount must be greater than 0.");
        if (string.IsNullOrWhiteSpace(request.Method))
            return BillingResult<(PaymentResponse, InvoiceResponse)>.BadRequest("Payment method is required.");

        var invoice = await LoadInvoiceAsync(actor, invoiceId, tracking: true, ct);
        if (invoice is null) return BillingResult<(PaymentResponse, InvoiceResponse)>.NotFound("Invoice not found.");

        var error = CheckPayable(invoice, BillingRules.Round(request.Amount));
        if (error is not null) return BillingResult<(PaymentResponse, InvoiceResponse)>.BadRequest(error);

        var payment = new Payment
        {
            InvoiceId = invoice.Id,
            Amount = BillingRules.Round(request.Amount),
            Method = request.Method.Trim(),
            Provider = PaymentProviders.Manual,
            Status = PaymentStatuses.Succeeded,
            PayerLabel = string.IsNullOrWhiteSpace(request.PayerLabel) ? null : request.PayerLabel.Trim(),
            TransactionRef = request.TransactionRef?.Trim(),
            GatewayResponse = request.GatewayResponse,
            PaidAt = DateTime.UtcNow,
        };
        invoice.Payments.Add(payment);
        _db.Payments.Add(payment);
        await ApplyPaymentEffectsAsync(invoice, ct);
        await _db.SaveChangesAsync(ct);

        var people = await LoadPeopleAsync(actor.TenantId, new[] { invoice.CustomerId }, ct);
        return BillingResult<(PaymentResponse, InvoiceResponse)>.Ok((MapPayment(payment), MapInvoice(invoice, people)));
    }

    public async Task<BillingResult<InvoiceResponse>> SplitPayInvoiceAsync(BillingActor actor, Guid invoiceId, SplitPaymentRequest request, CancellationToken ct = default)
    {
        if (request.Shares is null || request.Shares.Count == 0)
            return BillingResult<InvoiceResponse>.BadRequest("A split payment needs at least one share.");
        if (request.Shares.Count > 20)
            return BillingResult<InvoiceResponse>.BadRequest("A bill can be split at most 20 ways.");
        if (request.Shares.Any(s => s.Amount <= 0 || string.IsNullOrWhiteSpace(s.Method)))
            return BillingResult<InvoiceResponse>.BadRequest("Every share needs an amount above 0 and a payment method.");

        var invoice = await LoadInvoiceAsync(actor, invoiceId, tracking: true, ct);
        if (invoice is null) return BillingResult<InvoiceResponse>.NotFound("Invoice not found.");

        var total = BillingRules.Round(request.Shares.Sum(s => s.Amount));
        var error = CheckPayable(invoice, total);
        if (error is not null) return BillingResult<InvoiceResponse>.BadRequest(error);

        var now = DateTime.UtcNow;
        var index = 0;
        foreach (var share in request.Shares)
        {
            index++;
            var payment = new Payment
            {
                InvoiceId = invoice.Id,
                Amount = BillingRules.Round(share.Amount),
                Method = share.Method.Trim(),
                Provider = PaymentProviders.Manual,
                Status = PaymentStatuses.Succeeded,
                PayerLabel = string.IsNullOrWhiteSpace(share.PayerLabel) ? $"Share {index} of {request.Shares.Count}" : share.PayerLabel.Trim(),
                TransactionRef = share.TransactionRef?.Trim(),
                PaidAt = now,
            };
            invoice.Payments.Add(payment);
            _db.Payments.Add(payment);
        }

        await ApplyPaymentEffectsAsync(invoice, ct);
        await _db.SaveChangesAsync(ct);

        var people = await LoadPeopleAsync(actor.TenantId, new[] { invoice.CustomerId }, ct);
        return BillingResult<InvoiceResponse>.Ok(MapInvoice(invoice, people));
    }

    /// Re-derives the invoice (and its subscription's) payment status after
    /// a payment changed. Shared with the gateway checkout/webhook path.
    public static async Task ApplyPaymentEffectsAsync(AppDbContext db, Invoice invoice, CancellationToken ct)
    {
        var paid = PaidAmount(invoice);
        invoice.Status = InvoiceStatuses.FromBalance(invoice.FinalAmount, paid, invoice.Status);
        invoice.UpdatedAt = DateTime.UtcNow;

        if (invoice.SubscriptionId is { } subId)
        {
            var sub = await db.Subscriptions.IgnoreQueryFilters()
                .FirstOrDefaultAsync(s => s.Id == subId && s.TenantId == invoice.TenantId, ct);
            if (sub is not null)
            {
                sub.PaymentStatus = invoice.Status == InvoiceStatuses.Paid ? "Paid" : paid > 0 ? "Pending" : sub.PaymentStatus;
                if (invoice.Status == InvoiceStatuses.Paid) sub.LastPaymentAt = DateTime.UtcNow;
                sub.UpdatedAt = DateTime.UtcNow;
            }
        }
    }

    private Task ApplyPaymentEffectsAsync(Invoice invoice, CancellationToken ct) => ApplyPaymentEffectsAsync(_db, invoice, ct);

    private static string? CheckPayable(Invoice invoice, decimal amount)
    {
        if (invoice.Status == InvoiceStatuses.Cancelled) return "Cannot record payment on a cancelled invoice.";
        if (invoice.Status == InvoiceStatuses.Draft) return "Issue the invoice before taking payment.";
        var balance = invoice.FinalAmount - PaidAmount(invoice);
        if (balance <= 0 || invoice.Status == InvoiceStatuses.Paid) return "Invoice is already fully paid.";
        if (amount > balance) return $"Payment amount ({amount:N2}) exceeds outstanding balance ({balance:N2}).";
        return null;
    }

    // ==========================================
    // RECEIPTS & DELIVERY
    // ==========================================

    public async Task<BillingResult<ReceiptResponse>> GetReceiptAsync(BillingActor actor, Guid invoiceId, CancellationToken ct = default)
    {
        var invoice = await LoadInvoiceAsync(actor, invoiceId, tracking: false, ct);
        if (invoice is null) return BillingResult<ReceiptResponse>.NotFound("Invoice not found.");
        return BillingResult<ReceiptResponse>.Ok(await BuildReceiptAsync(invoice, ct));
    }

    public async Task<BillingResult<(byte[] Content, string FileName)>> GetReceiptPdfAsync(BillingActor actor, Guid invoiceId, CancellationToken ct = default)
    {
        var invoice = await LoadInvoiceAsync(actor, invoiceId, tracking: false, ct);
        if (invoice is null) return BillingResult<(byte[], string)>.NotFound("Invoice not found.");
        var receipt = await BuildReceiptAsync(invoice, ct);
        var pdf = ReceiptPdfBuilder.Build(receipt, asReceipt: receipt.TotalPaid > 0);
        return BillingResult<(byte[], string)>.Ok((pdf, $"{receipt.ReceiptNumber}.pdf"));
    }

    public async Task<BillingResult<MessageDeliveryResponse>> SendInvoiceAsync(BillingActor actor, Guid invoiceId, SendInvoiceRequest request, bool asReminder, CancellationToken ct = default)
    {
        var channel = MessageChannels.Normalize(request.Channel);
        if (channel is null) return BillingResult<MessageDeliveryResponse>.BadRequest("Channel must be Email, Sms or WhatsApp.");

        var invoice = await LoadInvoiceAsync(actor, invoiceId, tracking: false, ct);
        if (invoice is null) return BillingResult<MessageDeliveryResponse>.NotFound("Invoice not found.");
        if (asReminder && (invoice.Status is InvoiceStatuses.Paid or InvoiceStatuses.Cancelled))
            return BillingResult<MessageDeliveryResponse>.BadRequest("Only unpaid invoices need a payment reminder.");

        var receipt = await BuildReceiptAsync(invoice, ct);
        var people = await LoadPeopleAsync(actor.TenantId, new[] { invoice.CustomerId }, ct);
        people.TryGetValue(invoice.CustomerId, out var person);

        var to = !string.IsNullOrWhiteSpace(request.To)
            ? request.To.Trim()
            : channel == MessageChannels.Email ? person?.Email : person?.Phone;
        if (string.IsNullOrWhiteSpace(to))
            return BillingResult<MessageDeliveryResponse>.BadRequest(
                channel == MessageChannels.Email ? "The customer has no email address on file." : "The customer has no phone number on file.");

        var business = receipt.BusinessName ?? "Your provider";
        MessageDeliveryResponse delivery;
        if (channel == MessageChannels.Email)
        {
            var subject = asReminder
                ? $"Payment reminder: {invoice.InvoiceNumber} ({invoice.Currency} {receipt.BalanceDue:N2} due)"
                : receipt.TotalPaid > 0 ? $"Your receipt {receipt.ReceiptNumber} from {business}" : $"Invoice {invoice.InvoiceNumber} from {business}";
            var pdf = ReceiptPdfBuilder.Build(receipt, asReceipt: receipt.TotalPaid > 0);
            delivery = await _messenger.SendEmailAsync(to, subject, BuildEmailHtml(receipt, asReminder),
                new EmailAttachment($"{(receipt.TotalPaid > 0 ? receipt.ReceiptNumber : invoice.InvoiceNumber)}.pdf", "application/pdf", pdf), ct);
        }
        else
        {
            var body = asReminder
                ? $"{business}: reminder that invoice {invoice.InvoiceNumber} has {invoice.Currency} {receipt.BalanceDue:N2} due on {invoice.DueDate:dd MMM yyyy}. Pay in the Unify app."
                : $"{business}: invoice {invoice.InvoiceNumber} for {invoice.Currency} {invoice.FinalAmount:N2}, due {invoice.DueDate:dd MMM yyyy}. Balance: {invoice.Currency} {receipt.BalanceDue:N2}.";
            delivery = await _messenger.SendTextAsync(channel, to, body, ct);
        }

        return BillingResult<MessageDeliveryResponse>.Ok(delivery);
    }

    private async Task<ReceiptResponse> BuildReceiptAsync(Invoice invoice, CancellationToken ct)
    {
        var businessName = await _db.Tenants.IgnoreQueryFilters().AsNoTracking()
            .Where(t => t.Id == invoice.TenantId).Select(t => t.Name).FirstOrDefaultAsync(ct);
        var people = await LoadPeopleAsync(invoice.TenantId, new[] { invoice.CustomerId }, ct);
        people.TryGetValue(invoice.CustomerId, out var person);

        var template = await _db.InvoiceTemplates.AsNoTracking()
            .Where(t => t.TenantId == invoice.TenantId && (t.Id == invoice.TemplateId || t.IsDefault))
            .OrderByDescending(t => t.Id == invoice.TemplateId)
            .FirstOrDefaultAsync(ct);

        var paid = PaidAmount(invoice);
        var items = invoice.Items.Select(MapItem).ToList();
        var payments = invoice.Payments.OrderByDescending(p => p.PaidAt ?? p.CreatedAt).Select(MapPayment).ToList();

        return new ReceiptResponse(
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
            paid,
            Math.Max(0, invoice.FinalAmount - paid),
            EffectiveStatus(invoice, paid),
            DateTime.UtcNow,
            items,
            payments,
            businessName,
            person?.Name,
            person?.Email,
            invoice.Notes,
            template is null ? null : BillingSettingsService.MapTemplate(template));
    }

    private static string BuildEmailHtml(ReceiptResponse r, bool reminder)
    {
        static string E(string? s) => WebUtility.HtmlEncode(s ?? "");
        var rows = string.Join("", r.Items.Select(i =>
            $"<tr><td style=\"padding:6px 0\">{E(i.Description)}</td><td align=\"right\">{i.Quantity}</td><td align=\"right\">{i.Amount:N2}</td></tr>"));
        var intro = reminder
            ? $"This is a friendly reminder that <b>{r.Currency} {r.BalanceDue:N2}</b> is due on invoice {E(r.InvoiceNumber)} (due {r.DueDate:dd MMM yyyy})."
            : r.TotalPaid > 0
                ? $"Thank you for your payment. Your receipt <b>{E(r.ReceiptNumber)}</b> is attached."
                : $"Please find invoice <b>{E(r.InvoiceNumber)}</b> attached, due {r.DueDate:dd MMM yyyy}.";

        return $"""
            <div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;color:#1f2328">
              <h2 style="margin-bottom:4px">{E(r.BusinessName)}</h2>
              <p>Hi {E(r.CustomerName)},</p>
              <p>{intro}</p>
              <table width="100%" style="border-collapse:collapse;font-size:14px">
                <tr style="color:#6b7280"><th align="left">Item</th><th align="right">Qty</th><th align="right">Amount</th></tr>
                {rows}
              </table>
              <p style="text-align:right;font-size:15px">Total: <b>{r.Currency} {r.FinalAmount:N2}</b><br/>Paid: {r.TotalPaid:N2}<br/>Balance: <b>{r.BalanceDue:N2}</b></p>
              <p style="color:#6b7280;font-size:12px">{E(r.Template?.FooterText ?? "Thank you for your business.")}</p>
            </div>
            """;
    }

    // ==========================================
    // SUBSCRIPTIONS
    // ==========================================

    public async Task<SubscriptionListResponse> GetSubscriptionsAsync(BillingActor actor, int page, int pageSize, string? status = null, Guid? customerId = null, CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);

        var query = SubscriptionsFor(actor).AsNoTracking();
        if (!string.IsNullOrWhiteSpace(status))
        {
            var s = status.Trim().ToLower();
            query = query.Where(x => x.Status.ToLower() == s);
        }
        if (!actor.IsCustomer && customerId is { } cid && cid != Guid.Empty)
            query = query.Where(x => x.CustomerId == cid);

        var totalCount = await query.CountAsync(ct);
        var items = await query.OrderByDescending(x => x.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var people = await LoadPeopleAsync(actor.TenantId, items.Select(i => i.CustomerId), ct);

        return new SubscriptionListResponse(items.Select(s => MapSubscription(s, people)).ToList(),
            page, pageSize, totalCount, (int)Math.Ceiling(totalCount / (double)pageSize));
    }

    public async Task<BillingResult<SubscriptionResponse>> GetSubscriptionAsync(BillingActor actor, Guid subscriptionId, CancellationToken ct = default)
    {
        var sub = await SubscriptionsFor(actor).AsNoTracking().FirstOrDefaultAsync(s => s.Id == subscriptionId, ct);
        if (sub is null) return BillingResult<SubscriptionResponse>.NotFound("Subscription not found.");
        var people = await LoadPeopleAsync(actor.TenantId, new[] { sub.CustomerId }, ct);
        return BillingResult<SubscriptionResponse>.Ok(MapSubscription(sub, people));
    }

    public async Task<BillingResult<SubscriptionResponse>> CreateSubscriptionAsync(BillingActor actor, CreateSubscriptionRequest request, CancellationToken ct = default)
    {
        if (request.CustomerId == Guid.Empty)
            return BillingResult<SubscriptionResponse>.BadRequest("Valid CustomerId is required.");
        if (string.IsNullOrWhiteSpace(request.PlanName))
            return BillingResult<SubscriptionResponse>.BadRequest("PlanName is required.");
        if (request.Amount < 0)
            return BillingResult<SubscriptionResponse>.BadRequest("Amount cannot be negative.");

        var cycle = NormalizeCycle(request.BillingCycle);
        if (cycle is null)
            return BillingResult<SubscriptionResponse>.BadRequest($"BillingCycle must be one of: {string.Join(", ", BillingCycles)}.");

        var start = Utc(request.StartDate);
        var end = Utc(request.EndDate);
        if (end <= start)
            return BillingResult<SubscriptionResponse>.BadRequest("EndDate must be later than StartDate.");

        var reference = await ValidateReferencesAsync(actor.TenantId, request.CustomerId, null, null, null, request.BranchId, ct);
        if (reference is not null) return BillingResult<SubscriptionResponse>.BadRequest(reference);

        var subscription = new Subscription
        {
            TenantId = actor.TenantId,
            BranchId = request.BranchId,
            CustomerId = request.CustomerId,
            PlanName = request.PlanName.Trim(),
            Amount = BillingRules.Round(request.Amount),
            BillingCycle = cycle,
            StartDate = start,
            EndDate = end,
            AutoRenew = request.AutoRenew && cycle != "OneOff",
            Status = SubscriptionStatuses.Active,
            PaymentStatus = request.GenerateInvoice && request.Amount > 0 ? "Pending" : "Paid",
            NextBillingAt = request.AutoRenew && cycle != "OneOff" ? end : null,
            Notes = string.IsNullOrWhiteSpace(request.Notes) ? null : request.Notes.Trim(),
        };
        _db.Subscriptions.Add(subscription);

        if (request.GenerateInvoice && subscription.Amount > 0)
        {
            _db.Invoices.Add(NewSubscriptionInvoice(subscription, NormalizeCurrency(request.Currency),
                $"{subscription.PlanName} membership ({start:dd MMM} - {end:dd MMM yyyy})", subscription.Amount, start.AddDays(7)));
        }

        await _db.SaveChangesAsync(ct);
        var people = await LoadPeopleAsync(actor.TenantId, new[] { subscription.CustomerId }, ct);
        return BillingResult<SubscriptionResponse>.Created(MapSubscription(subscription, people));
    }

    public async Task<BillingResult<CancelSubscriptionResult>> CancelSubscriptionAsync(BillingActor actor, Guid subscriptionId, CancelSubscriptionRequest request, CancellationToken ct = default)
    {
        var sub = await SubscriptionsFor(actor).FirstOrDefaultAsync(s => s.Id == subscriptionId, ct);
        if (sub is null) return BillingResult<CancelSubscriptionResult>.NotFound("Subscription not found.");
        if (sub.Status == SubscriptionStatuses.Cancelled)
            return BillingResult<CancelSubscriptionResult>.BadRequest("Subscription is already cancelled.");
        if (sub.Status == SubscriptionStatuses.PendingCancel)
            return BillingResult<CancelSubscriptionResult>.Conflict("A cancellation for this subscription is already waiting for approval.");

        var refund = BillingRules.Round(Math.Max(0, request.RefundAmount));
        if (refund > 0)
        {
            var paid = await _db.Invoices.Where(i => i.TenantId == actor.TenantId && i.SubscriptionId == sub.Id)
                .SelectMany(i => i.Payments).Where(p => p.Status == PaymentStatuses.Succeeded).SumAsync(p => (decimal?)p.Amount, ct) ?? 0;
            var ceiling = Math.Max(paid, sub.Amount);
            if (refund > ceiling)
                return BillingResult<CancelSubscriptionResult>.BadRequest($"The refund ({refund:N2}) cannot exceed what was paid ({ceiling:N2}).");
        }

        var people = await LoadPeopleAsync(actor.TenantId, new[] { sub.CustomerId }, ct);
        var reason = string.IsNullOrWhiteSpace(request.Reason) ? null : request.Reason.Trim();
        var parameters = new Dictionary<string, object?>
        {
            ["refundAmount"] = refund,
            ["previousStatus"] = sub.Status,
            ["planName"] = sub.PlanName,
            ["customerName"] = people.TryGetValue(sub.CustomerId, out var p) ? p.Name : null,
        };

        // Spec 3.7: a cancellation with a refund needs an Admin's approval.
        if (BillingRules.CancellationRequiresApproval(refund) && !actor.IsAdmin)
        {
            var wf = await _approvals.RequestApprovalAsync(
                actor.TenantId, BillingActionTypes.CancelSubscriptionWithRefund, "Subscription", sub.Id,
                $"Cancel {sub.PlanName} membership with a {refund:N2} refund", refund, requiresAdmin: true,
                reason ?? "Cancellation with refund requested.", parameters, "user", actor.UserId, ct);

            sub.Status = SubscriptionStatuses.PendingCancel;
            sub.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync(ct);

            return BillingResult<CancelSubscriptionResult>.Accepted(new CancelSubscriptionResult(false, true, wf.Id,
                MapSubscription(sub, people), "Cancellation with refund sent to an Admin for approval."));
        }

        sub.Status = SubscriptionStatuses.Cancelled;
        sub.AutoRenew = false;
        sub.NextBillingAt = null;
        if (reason is not null) sub.Notes = AppendNote(sub.Notes, $"Cancelled: {reason}", 500);
        sub.UpdatedAt = DateTime.UtcNow;

        Guid? auditId = null;
        if (refund > 0 && actor.UserId is { } adminId)
        {
            var invoice = await _db.Invoices.Where(i => i.TenantId == actor.TenantId && i.SubscriptionId == sub.Id)
                .OrderByDescending(i => i.CreatedAt).FirstOrDefaultAsync(ct);
            _db.Payments.Add(new Payment
            {
                InvoiceId = invoice?.Id,
                Amount = refund,
                Method = "Refund",
                Provider = PaymentProviders.Manual,
                Status = PaymentStatuses.Refunded,
                TransactionRef = $"REFUND-{sub.Id.ToString("N")[..8].ToUpperInvariant()}",
                PaidAt = DateTime.UtcNow,
            });
            await _db.SaveChangesAsync(ct);
            var audit = await _approvals.RecordApprovedActionAsync(actor.TenantId, BillingActionTypes.CancelSubscriptionWithRefund,
                "Subscription", sub.Id, $"Cancel {sub.PlanName} membership with a {refund:N2} refund", refund,
                reason, parameters, adminId, "Applied directly by an Admin.", ct);
            auditId = audit.Id;
        }
        else
        {
            await _db.SaveChangesAsync(ct);
        }

        return BillingResult<CancelSubscriptionResult>.Ok(new CancelSubscriptionResult(true, false, auditId,
            MapSubscription(sub, people), refund > 0 ? $"Cancelled with a {refund:N2} refund." : "Subscription cancelled."));
    }

    public async Task<BillingResult<SubscriptionResponse>> ChangePlanAsync(BillingActor actor, Guid subscriptionId, ChangePlanRequest request, CancellationToken ct = default)
    {
        var sub = await SubscriptionsFor(actor).FirstOrDefaultAsync(s => s.Id == subscriptionId, ct);
        if (sub is null) return BillingResult<SubscriptionResponse>.NotFound("Subscription not found.");
        if (sub.Status != SubscriptionStatuses.Active)
            return BillingResult<SubscriptionResponse>.BadRequest("Only an active subscription can change plan.");
        if (string.IsNullOrWhiteSpace(request.PlanName))
            return BillingResult<SubscriptionResponse>.BadRequest("PlanName is required.");

        var cycle = request.BillingCycle is null ? sub.BillingCycle : NormalizeCycle(request.BillingCycle);
        if (cycle is null)
            return BillingResult<SubscriptionResponse>.BadRequest($"BillingCycle must be one of: {string.Join(", ", BillingCycles)}.");

        var newAmount = BillingRules.Round(request.Amount);
        var oldAmount = sub.Amount;
        var now = DateTime.UtcNow;

        // An upgrade is charged pro rata for the rest of the current period;
        // a downgrade simply applies from the next renewal.
        if (newAmount > oldAmount && sub.EndDate > now && cycle == sub.BillingCycle)
        {
            var periodDays = Math.Max(1, (sub.EndDate - sub.StartDate).TotalDays);
            var remaining = Math.Max(0, (sub.EndDate - now).TotalDays);
            var proration = BillingRules.Round((newAmount - oldAmount) * (decimal)(remaining / periodDays));
            if (proration > 0)
            {
                var currency = await _db.Invoices.Where(i => i.TenantId == actor.TenantId && i.SubscriptionId == sub.Id)
                    .OrderByDescending(i => i.CreatedAt).Select(i => i.Currency).FirstOrDefaultAsync(ct) ?? "LKR";
                _db.Invoices.Add(NewSubscriptionInvoice(sub, currency,
                    $"Upgrade {sub.PlanName} -> {request.PlanName.Trim()} (pro rata, {remaining:0} days)", proration, now.AddDays(7)));
                sub.PaymentStatus = "Pending";
            }
        }

        sub.Notes = AppendNote(sub.Notes, $"Plan changed {sub.PlanName} ({oldAmount:N2}) -> {request.PlanName.Trim()} ({newAmount:N2}) on {now:dd MMM yyyy}", 500);
        sub.PlanName = request.PlanName.Trim();
        sub.Amount = newAmount;
        sub.BillingCycle = cycle;
        sub.UpdatedAt = now;
        await _db.SaveChangesAsync(ct);

        var people = await LoadPeopleAsync(actor.TenantId, new[] { sub.CustomerId }, ct);
        return BillingResult<SubscriptionResponse>.Ok(MapSubscription(sub, people));
    }

    public async Task<IReadOnlyList<SubscriptionPlanOption>> GetPlanOptionsAsync(BillingActor actor, CancellationToken ct = default)
    {
        var rows = await _db.Subscriptions.IgnoreQueryFilters().AsNoTracking()
            .Where(s => s.TenantId == actor.TenantId && s.Status != SubscriptionStatuses.Cancelled)
            .Select(s => new { s.PlanName, s.Amount, s.BillingCycle, s.Status })
            .ToListAsync(ct);

        return rows
            .GroupBy(r => (r.PlanName, r.Amount, r.BillingCycle))
            .Select(g => new SubscriptionPlanOption(g.Key.PlanName, g.Key.Amount, g.Key.BillingCycle,
                g.Count(r => r.Status == SubscriptionStatuses.Active)))
            .OrderBy(o => o.BillingCycle).ThenBy(o => o.Amount)
            .ToList();
    }

    public async Task<IReadOnlyList<RenewalCalendarEntry>> GetRenewalCalendarAsync(BillingActor actor, DateTime from, DateTime to, CancellationToken ct = default)
    {
        var start = Utc(from).Date;
        var end = Utc(to).Date.AddDays(1);
        var subs = await SubscriptionsFor(actor).AsNoTracking()
            .Where(s => s.Status != SubscriptionStatuses.Cancelled && s.Status != SubscriptionStatuses.Expired)
            .Where(s => (s.NextBillingAt ?? s.EndDate) >= start && (s.NextBillingAt ?? s.EndDate) < end)
            .ToListAsync(ct);
        var people = await LoadPeopleAsync(actor.TenantId, subs.Select(s => s.CustomerId), ct);

        return subs
            .Select(s => new RenewalCalendarEntry(s.Id, s.CustomerId,
                people.TryGetValue(s.CustomerId, out var p) ? p.Name : null,
                s.PlanName, s.Amount, s.BillingCycle, s.NextBillingAt ?? s.EndDate, s.AutoRenew, s.Status, s.PaymentStatus))
            .OrderBy(e => e.RenewalDate)
            .ToList();
    }

    public async Task<BillingResult<InvoiceListResponse>> GetSubscriptionInvoicesAsync(BillingActor actor, Guid subscriptionId, CancellationToken ct = default)
    {
        var exists = await SubscriptionsFor(actor).AnyAsync(s => s.Id == subscriptionId, ct);
        if (!exists) return BillingResult<InvoiceListResponse>.NotFound("Subscription not found.");

        var invoices = await InvoicesFor(actor).AsNoTracking()
            .Include(i => i.Items).Include(i => i.Payments)
            .Where(i => i.SubscriptionId == subscriptionId)
            .OrderByDescending(i => i.CreatedAt)
            .Take(MaxPageSize)
            .ToListAsync(ct);
        var people = await LoadPeopleAsync(actor.TenantId, invoices.Select(i => i.CustomerId), ct);
        return BillingResult<InvoiceListResponse>.Ok(new InvoiceListResponse(
            invoices.Select(i => MapInvoice(i, people)).ToList(), 1, MaxPageSize, invoices.Count, 1));
    }

    // ==========================================
    // INSURANCE CLAIMS
    // ==========================================

    public async Task<InsuranceClaimListResponse> GetInsuranceClaimsAsync(BillingActor actor, int page, int pageSize, string? status = null, CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);

        var query = ClaimsFor(actor).AsNoTracking();
        if (!string.IsNullOrWhiteSpace(status))
        {
            var s = NormalizeClaimStatus(status) ?? status.Trim();
            query = query.Where(c => c.Status == s);
        }

        var totalCount = await query.CountAsync(ct);
        var items = await query.OrderByDescending(c => c.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);

        return new InsuranceClaimListResponse(items.Select(c => MapClaim(c)).ToList(),
            page, pageSize, totalCount, (int)Math.Ceiling(totalCount / (double)pageSize));
    }

    public async Task<BillingResult<InsuranceClaimResponse>> GetInsuranceClaimAsync(BillingActor actor, Guid claimId, CancellationToken ct = default)
    {
        var claim = await ClaimsFor(actor).AsNoTracking().FirstOrDefaultAsync(c => c.Id == claimId, ct);
        if (claim is null) return BillingResult<InsuranceClaimResponse>.NotFound("Insurance claim not found.");
        var pending = await _approvals.FindPendingApprovalAsync(actor.TenantId, BillingActionTypes.ApproveInsuranceClaim, claim.Id, ct);
        return BillingResult<InsuranceClaimResponse>.Ok(MapClaim(claim, pending));
    }

    public async Task<BillingResult<InsuranceClaimResponse>> CreateInsuranceClaimAsync(BillingActor actor, CreateInsuranceClaimRequest request, CancellationToken ct = default)
    {
        var invoice = await InvoicesFor(actor).AsNoTracking()
            .FirstOrDefaultAsync(i => i.Id == request.InvoiceId, ct);
        if (invoice is null) return BillingResult<InsuranceClaimResponse>.BadRequest("Invoice not found for the current tenant.");

        var otherClaims = await _db.InsuranceClaims
            .Where(c => c.InvoiceId == invoice.Id && c.Status != "Rejected")
            .SumAsync(c => (decimal?)c.ClaimAmount, ct) ?? 0;
        var people = await LoadPeopleAsync(actor.TenantId, new[] { invoice.CustomerId }, ct);
        people.TryGetValue(invoice.CustomerId, out var person);

        var check = BillingRules.ValidateClaim(new BillingRules.ClaimContext(
            BillingRules.Round(request.ClaimAmount), request.Provider ?? "", request.PolicyNumber ?? "",
            invoice.FinalAmount, invoice.Status, otherClaims, person?.InsuranceProvider, person?.InsuranceNumber));
        if (!check.IsValid)
            return BillingResult<InsuranceClaimResponse>.BadRequest(string.Join(" ", check.Issues.Where(i => i.Severity == "error").Select(i => i.Message)));

        var warnings = check.Issues.Where(i => i.Severity == "warning").Select(i => i.Message).ToList();
        var notes = string.IsNullOrWhiteSpace(request.Notes) ? null : request.Notes.Trim();
        if (warnings.Count > 0) notes = AppendNote(notes, "Agent check: " + string.Join(" ", warnings));

        var claim = new InsuranceClaim
        {
            InvoiceId = invoice.Id,
            Provider = request.Provider!.Trim(),
            PolicyNumber = request.PolicyNumber!.Trim(),
            ClaimAmount = BillingRules.Round(request.ClaimAmount),
            Status = "Submitted",
            SubmittedAt = DateTime.UtcNow,
            Notes = notes,
        };
        _db.InsuranceClaims.Add(claim);
        await _db.SaveChangesAsync(ct);

        // Never hang the untracked invoice on the tracked claim: a later
        // SaveChanges would try to attach (or insert) it.
        return BillingResult<InsuranceClaimResponse>.Created(MapClaim(claim) with
        {
            InvoiceNumber = invoice.InvoiceNumber,
            CustomerId = invoice.CustomerId,
            Currency = invoice.Currency,
        });
    }

    public async Task<BillingResult<UpdateClaimStatusResult>> UpdateInsuranceClaimStatusAsync(BillingActor actor, Guid claimId, UpdateInsuranceClaimStatusRequest request, CancellationToken ct = default)
    {
        var target = NormalizeClaimStatus(request.Status);
        if (target is null)
            return BillingResult<UpdateClaimStatusResult>.BadRequest($"Status must be one of: {string.Join(", ", ClaimStatuses)}.");

        var claim = await ClaimsFor(actor).FirstOrDefaultAsync(c => c.Id == claimId, ct);
        if (claim is null) return BillingResult<UpdateClaimStatusResult>.NotFound("Insurance claim not found.");

        if (claim.Status is "Approved" or "Rejected")
            return BillingResult<UpdateClaimStatusResult>.BadRequest($"The claim is already {claim.Status.ToLowerInvariant()} and cannot change.");
        if (target == claim.Status)
            return BillingResult<UpdateClaimStatusResult>.BadRequest($"The claim is already {target}.");
        if (target == "Submitted")
            return BillingResult<UpdateClaimStatusResult>.BadRequest("A claim cannot move back to Submitted.");
        if (target == "Rejected" && string.IsNullOrWhiteSpace(request.RejectionReason))
            return BillingResult<UpdateClaimStatusResult>.BadRequest("A rejection reason is required.");

        if (!string.IsNullOrWhiteSpace(request.Notes))
            claim.Notes = AppendNote(claim.Notes, request.Notes.Trim());

        if (target == "Approved")
        {
            var otherClaims = await _db.InsuranceClaims
                .Where(c => c.InvoiceId == claim.InvoiceId && c.Id != claim.Id && c.Status != "Rejected")
                .SumAsync(c => (decimal?)c.ClaimAmount, ct) ?? 0;
            var check = BillingRules.ValidateClaim(new BillingRules.ClaimContext(claim.ClaimAmount, claim.Provider,
                claim.PolicyNumber, claim.Invoice!.FinalAmount, claim.Invoice.Status, otherClaims, null, null));
            if (!check.IsValid)
                return BillingResult<UpdateClaimStatusResult>.BadRequest("The claim fails policy rules: " +
                    string.Join(" ", check.Issues.Where(i => i.Severity == "error").Select(i => i.Message)));

            // Spec 3.7: a claim above the threshold needs an Admin.
            if (check.RequiresApproval && !actor.IsAdmin)
            {
                if (await _approvals.FindPendingApprovalAsync(actor.TenantId, BillingActionTypes.ApproveInsuranceClaim, claim.Id, ct) is { } existing)
                    return BillingResult<UpdateClaimStatusResult>.Conflict($"Approval for this claim is already pending (request {existing}).");

                claim.Status = "UnderReview";
                claim.ReviewStartedAt ??= DateTime.UtcNow;
                claim.UpdatedAt = DateTime.UtcNow;
                await _db.SaveChangesAsync(ct);

                var wf = await _approvals.RequestApprovalAsync(actor.TenantId, BillingActionTypes.ApproveInsuranceClaim,
                    "InsuranceClaim", claim.Id, $"Approve {claim.Provider} claim of {claim.ClaimAmount:N2} on {claim.Invoice.InvoiceNumber}",
                    claim.ClaimAmount, requiresAdmin: true,
                    $"Claim is above the {ThresholdConfig.Default.ClaimApprovalAmount:N2} approval threshold.",
                    new Dictionary<string, object?> { ["invoiceNumber"] = claim.Invoice.InvoiceNumber, ["provider"] = claim.Provider },
                    "user", actor.UserId, ct);

                return BillingResult<UpdateClaimStatusResult>.Accepted(new UpdateClaimStatusResult(false, true, wf.Id,
                    MapClaim(claim, wf.Id), "The claim is above the approval threshold - sent to an Admin for approval."));
            }

            claim.Status = "Approved";
            claim.ApprovedAt = DateTime.UtcNow;
            claim.RejectionReason = null;
            claim.ReviewStartedAt ??= DateTime.UtcNow;
            claim.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync(ct);

            Guid? auditId = null;
            if (check.RequiresApproval && actor.UserId is { } adminId)
            {
                var audit = await _approvals.RecordApprovedActionAsync(actor.TenantId, BillingActionTypes.ApproveInsuranceClaim,
                    "InsuranceClaim", claim.Id, $"Approve {claim.Provider} claim of {claim.ClaimAmount:N2} on {claim.Invoice.InvoiceNumber}",
                    claim.ClaimAmount, request.Notes, new Dictionary<string, object?> { ["invoiceNumber"] = claim.Invoice.InvoiceNumber },
                    adminId, "Approved directly by an Admin.", ct);
                auditId = audit.Id;
            }
            return BillingResult<UpdateClaimStatusResult>.Ok(new UpdateClaimStatusResult(true, false, auditId, MapClaim(claim), "Claim approved."));
        }

        claim.Status = target;
        if (target == "UnderReview") claim.ReviewStartedAt ??= DateTime.UtcNow;
        if (target == "Rejected")
        {
            claim.RejectionReason = request.RejectionReason!.Trim();
            claim.ReviewStartedAt ??= DateTime.UtcNow;
        }
        claim.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        return BillingResult<UpdateClaimStatusResult>.Ok(new UpdateClaimStatusResult(true, false, null, MapClaim(claim),
            target == "Rejected" ? "Claim rejected." : "Claim moved to review."));
    }

    public async Task<BillingResult<InsuranceClaimResponse>> AddClaimDocumentAsync(BillingActor actor, Guid claimId, string url, string fileName, CancellationToken ct = default)
    {
        var claim = await ClaimsFor(actor).FirstOrDefaultAsync(c => c.Id == claimId, ct);
        if (claim is null) return BillingResult<InsuranceClaimResponse>.NotFound("Insurance claim not found.");
        if (claim.Status is "Approved" or "Rejected")
            return BillingResult<InsuranceClaimResponse>.BadRequest("Documents cannot be added to a closed claim.");

        var docs = ParseDocuments(claim.DocumentsJson).ToList();
        if (docs.Count >= 10) return BillingResult<InsuranceClaimResponse>.BadRequest("A claim can have at most 10 documents.");
        docs.Add(new ClaimDocument(url, fileName, DateTime.UtcNow));
        claim.DocumentsJson = JsonSerializer.Serialize(docs, BillingWorkflowPlan.Json);
        claim.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);
        return BillingResult<InsuranceClaimResponse>.Ok(MapClaim(claim));
    }

    // ==========================================
    // SCOPING
    // ==========================================

    private IQueryable<Invoice> InvoicesFor(BillingActor actor)
    {
        var q = _db.Invoices.Where(i => i.TenantId == actor.TenantId);
        return actor.IsCustomer ? q.Where(i => i.CustomerId == actor.UserId) : q;
    }

    private IQueryable<Subscription> SubscriptionsFor(BillingActor actor)
    {
        var q = _db.Subscriptions.IgnoreQueryFilters().Where(s => s.TenantId == actor.TenantId);
        return actor.IsCustomer ? q.Where(s => s.CustomerId == actor.UserId) : q;
    }

    private IQueryable<InsuranceClaim> ClaimsFor(BillingActor actor)
    {
        var q = _db.InsuranceClaims.Include(c => c.Invoice).Where(c => c.Invoice != null && c.Invoice.TenantId == actor.TenantId);
        return actor.IsCustomer ? q.Where(c => c.Invoice!.CustomerId == actor.UserId) : q;
    }

    private Task<Invoice?> LoadInvoiceAsync(BillingActor actor, Guid id, bool tracking, CancellationToken ct)
    {
        var q = InvoicesFor(actor).Include(i => i.Items).Include(i => i.Payments);
        return (tracking ? q : q.AsNoTracking()).FirstOrDefaultAsync(i => i.Id == id, ct);
    }

    private async Task<string?> ValidateReferencesAsync(Guid tenantId, Guid customerId, Guid? bookingId, Guid? subscriptionId,
        Guid? templateId, Guid? branchId, CancellationToken ct)
    {
        if (!await _db.Users.IgnoreQueryFilters().AnyAsync(u => u.Id == customerId && u.TenantId == tenantId, ct))
            return "Customer not found in this business.";
        if (bookingId is { } b && !await _db.Bookings.IgnoreQueryFilters().AnyAsync(x => x.Id == b && x.TenantId == tenantId, ct))
            return "Booking not found in this business.";
        if (subscriptionId is { } s && !await _db.Subscriptions.IgnoreQueryFilters().AnyAsync(x => x.Id == s && x.TenantId == tenantId, ct))
            return "Subscription not found in this business.";
        if (templateId is { } t && !await _db.InvoiceTemplates.AnyAsync(x => x.Id == t && x.TenantId == tenantId, ct))
            return "Invoice template not found.";
        if (branchId is { } br && !await _db.Branches.IgnoreQueryFilters().AnyAsync(x => x.Id == br && x.TenantId == tenantId, ct))
            return "Branch not found in this business.";
        return null;
    }

    // ==========================================
    // MAPPING & HELPERS
    // ==========================================

    public sealed record Person(string Name, string Email, string Phone, string? InsuranceProvider, string? InsuranceNumber);

    private async Task<Dictionary<Guid, Person>> LoadPeopleAsync(Guid tenantId, IEnumerable<Guid> ids, CancellationToken ct)
    {
        var set = ids.Distinct().ToList();
        if (set.Count == 0) return new Dictionary<Guid, Person>();
        return await _db.Users.IgnoreQueryFilters().AsNoTracking()
            .Where(u => u.TenantId == tenantId && set.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => new Person(u.FullName, u.Email, u.Phone, u.InsuranceProvider, u.InsuranceNumber), ct);
    }

    public static decimal PaidAmount(Invoice invoice) =>
        invoice.Payments.Where(p => p.Status == PaymentStatuses.Succeeded).Sum(p => p.Amount);

    public static string EffectiveStatus(Invoice invoice, decimal paid)
    {
        if (invoice.Status is InvoiceStatuses.Issued or InvoiceStatuses.PartiallyPaid &&
            invoice.DueDate < DateTime.UtcNow && paid < invoice.FinalAmount)
            return InvoiceStatuses.Overdue;
        return invoice.Status;
    }

    public static InvoiceItemResponse MapItem(InvoiceItem i) =>
        new(i.Id, i.Description, i.Quantity, i.UnitPrice, i.Amount, i.Category);

    public static PaymentResponse MapPayment(Payment p) =>
        new(p.Id, p.InvoiceId, p.Amount, p.Method, p.TransactionRef, p.GatewayResponse, p.PaidAt, p.CreatedAt,
            p.Status, p.Provider, p.PayerLabel);

    private static InvoiceResponse MapInvoice(Invoice invoice, IReadOnlyDictionary<Guid, Person> people)
    {
        var paid = PaidAmount(invoice);
        var status = EffectiveStatus(invoice, paid);
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
            status,
            invoice.DueDate,
            invoice.Currency,
            invoice.CreatedAt,
            invoice.Items.Select(MapItem).ToList(),
            invoice.Payments.OrderByDescending(p => p.PaidAt ?? p.CreatedAt).Select(MapPayment).ToList(),
            invoice.BranchId,
            invoice.SubscriptionId,
            invoice.TemplateId,
            invoice.DiscountCode,
            invoice.Notes,
            invoice.ScheduleGroup,
            invoice.ScheduleLabel,
            paid,
            Math.Max(0, invoice.FinalAmount - paid),
            status == InvoiceStatuses.Overdue,
            people.TryGetValue(invoice.CustomerId, out var person) ? person.Name : null);
    }

    private static SubscriptionResponse MapSubscription(Subscription s, IReadOnlyDictionary<Guid, Person> people) =>
        new(s.Id, s.TenantId, s.CustomerId, s.PlanName, s.Amount, s.BillingCycle, s.StartDate, s.EndDate, s.AutoRenew,
            s.Status, s.CreatedAt, s.BranchId, s.PaymentStatus, s.NextBillingAt, s.LastPaymentAt, s.Notes,
            people.TryGetValue(s.CustomerId, out var p) ? p.Name : null);

    private static InsuranceClaimResponse MapClaim(InsuranceClaim c, Guid? pendingApproval = null) =>
        new(c.Id, c.InvoiceId, c.Invoice?.InvoiceNumber, c.Provider, c.PolicyNumber, c.ClaimAmount, c.Status,
            c.SubmittedAt, c.ApprovedAt, c.RejectionReason, c.CreatedAt, c.ReviewStartedAt, c.Notes,
            ParseDocuments(c.DocumentsJson), c.Invoice?.CustomerId, c.Invoice?.Currency,
            BillingRules.ClaimRequiresApproval(c.ClaimAmount), pendingApproval);

    private static IReadOnlyList<ClaimDocument> ParseDocuments(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return Array.Empty<ClaimDocument>();
        try
        {
            return JsonSerializer.Deserialize<List<ClaimDocument>>(json, BillingWorkflowPlan.Json) ?? new List<ClaimDocument>();
        }
        catch (JsonException)
        {
            return Array.Empty<ClaimDocument>();
        }
    }

    private static Invoice NewSubscriptionInvoice(Subscription sub, string currency, string description, decimal amount, DateTime dueDate) => new()
    {
        TenantId = sub.TenantId,
        BranchId = sub.BranchId,
        CustomerId = sub.CustomerId,
        SubscriptionId = sub.Id,
        InvoiceNumber = NewInvoiceNumber(),
        TotalAmount = amount,
        FinalAmount = amount,
        Status = InvoiceStatuses.Issued,
        DueDate = dueDate,
        Currency = currency,
        Items = new List<InvoiceItem>
        {
            new() { Description = description, Quantity = 1, UnitPrice = amount, Amount = amount, Category = "Membership" },
        },
    };

    public static string NewInvoiceNumber() =>
        $"INV-{DateTime.UtcNow:yyyyMMdd}-{Guid.NewGuid().ToString("N")[..6].ToUpperInvariant()}";

    public static string? NormalizeCycle(string? cycle) =>
        BillingCycles.FirstOrDefault(c => c.Equals(cycle?.Trim(), StringComparison.OrdinalIgnoreCase));

    public static string? NormalizeClaimStatus(string? status)
    {
        var s = status?.Trim();
        if (string.Equals(s, "Pending", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(s, "Under Review", StringComparison.OrdinalIgnoreCase))
            return "UnderReview";
        return ClaimStatuses.FirstOrDefault(c => c.Equals(s, StringComparison.OrdinalIgnoreCase));
    }

    private static string NormalizeCurrency(string? currency) =>
        string.IsNullOrWhiteSpace(currency) ? "LKR" : currency.Trim().ToUpperInvariant();

    private static DateTime Utc(DateTime value) => value.Kind switch
    {
        DateTimeKind.Utc => value,
        DateTimeKind.Local => value.ToUniversalTime(),
        _ => DateTime.SpecifyKind(value, DateTimeKind.Utc),
    };

    private static string AppendNote(string? existing, string note, int max = 2000)
    {
        var combined = string.IsNullOrWhiteSpace(existing) ? note : $"{existing}\n{note}";
        return combined.Length <= max ? combined : combined[^max..];
    }
}
