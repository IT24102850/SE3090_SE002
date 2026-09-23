using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.DTOs;
using SmeBackend.Services;
using SmeBackend.Services.Billing;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/invoices")]
[Authorize]
[Produces("application/json")]
public class InvoicesController : BillingControllerBase
{
    private readonly IBillingService _billingService;
    private readonly IPaymentCheckoutService _checkout;
    private readonly IBillingAgentService _agent;

    public InvoicesController(IBillingService billingService, IPaymentCheckoutService checkout, IBillingAgentService agent)
    {
        _billingService = billingService;
        _checkout = checkout;
        _agent = agent;
    }

    /// <summary>
    /// Lists invoices for the caller's business. Customers only ever see their own.
    /// </summary>
    /// <remarks>GET /api/invoices?tenantId=&amp;customerId=&amp;status=&amp;from=&amp;to=&amp;page=&amp;pageSize=
    /// (status also accepts "Overdue").</remarks>
    [HttpGet]
    [ProducesResponseType(typeof(InvoiceListResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<InvoiceListResponse>> GetInvoices(
        [FromQuery] Guid? tenantId = null,
        [FromQuery] Guid? customerId = null,
        [FromQuery] string? status = null,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] string? search = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (RejectForeignTenant(actor, tenantId) is { } forbidden) return forbidden;

        return Ok(await _billingService.GetInvoicesAsync(actor,
            new InvoiceQuery(page, pageSize, status, customerId, from, to, branchId, search), ct));
    }

    /// <summary>The current customer's own bills (the mobile "My Bills" list).</summary>
    [HttpGet("mine")]
    [ProducesResponseType(typeof(InvoiceListResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<InvoiceListResponse>> GetMyInvoices(
        [FromQuery] string? status = null, [FromQuery] int page = 1, [FromQuery] int pageSize = 50, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        var mine = actor with { Role = SmeBackend.Shared.Roles.Customer };
        return Ok(await _billingService.GetInvoicesAsync(mine, new InvoiceQuery(page, pageSize, status), ct));
    }

    /// <summary>Gets one invoice with its items and payments.</summary>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(InvoiceResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<InvoiceResponse>> GetInvoice(Guid id, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return FromResult(await _billingService.GetInvoiceAsync(actor, id, ct));
    }

    /// <summary>
    /// Creates an invoice. Totals, discount and tax are calculated server-side;
    /// the billing agent validates it and flags rule warnings for review.
    /// </summary>
    [HttpPost]
    [Authorize(Policy = "StaffPlus")]
    [ProducesResponseType(typeof(InvoiceResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<InvoiceResponse>> CreateInvoice([FromBody] CreateInvoiceRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _billingService.CreateInvoiceAsync(actor, request, ct));
    }

    /// <summary>
    /// Checks a draft invoice against the business rules (discount cap, tax
    /// range, totals) without saving it.
    /// </summary>
    [HttpPost("validate")]
    [Authorize(Policy = "StaffPlus")]
    [ProducesResponseType(typeof(InvoiceValidationResult), StatusCodes.Status200OK)]
    public ActionResult<InvoiceValidationResult> ValidateDraft([FromBody] CreateInvoiceRequest request)
    {
        if (Actor is null) return MissingTenant();
        return Ok(_agent.ValidateInvoiceDraft(request));
    }

    /// <summary>
    /// Raises a payment schedule: installments, milestone payments or a
    /// deposit + balance, one invoice per part.
    /// </summary>
    [HttpPost("schedule")]
    [Authorize(Policy = "StaffPlus")]
    [ProducesResponseType(typeof(PaymentScheduleResponse), StatusCodes.Status201Created)]
    public async Task<ActionResult<PaymentScheduleResponse>> CreateSchedule([FromBody] CreatePaymentScheduleRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _billingService.CreatePaymentScheduleAsync(actor, request, ct));
    }

    /// <summary>
    /// Adjusts discount/tax. A change above the approval threshold becomes an
    /// approval request (202) unless an Admin makes it.
    /// </summary>
    [HttpPut("{id:guid}/adjust")]
    [Authorize(Policy = "StaffPlus")]
    [ProducesResponseType(typeof(AdjustInvoiceResult), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(AdjustInvoiceResult), StatusCodes.Status202Accepted)]
    public async Task<ActionResult<AdjustInvoiceResult>> AdjustInvoice(Guid id, [FromBody] AdjustInvoiceRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _billingService.AdjustInvoiceAsync(actor, id, request, ct));
    }

    /// <summary>Cancels an unpaid invoice.</summary>
    [HttpPut("{id:guid}/cancel")]
    [Authorize(Policy = "ManagerPlus")]
    [ProducesResponseType(typeof(InvoiceResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<InvoiceResponse>> CancelInvoice(Guid id, [FromBody] CancelInvoiceRequest? request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return FromResult(await _billingService.CancelInvoiceAsync(actor, id, request ?? new CancelInvoiceRequest(null), ct));
    }

    /// <summary>
    /// Records a payment taken at the desk (cash, card terminal, bank transfer).
    /// </summary>
    [HttpPut("{id:guid}/pay")]
    [Authorize(Policy = "StaffPlus")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> PayInvoice(Guid id, [FromBody] PayInvoiceRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        var result = await _billingService.PayInvoiceAsync(actor, id, request, ct);
        return FromResult(result, r => new { message = "Payment recorded successfully.", payment = r.Payment, invoice = r.Invoice });
    }

    /// <summary>Pays a bill in several shares at once (split table bill).</summary>
    [HttpPut("{id:guid}/split-pay")]
    [Authorize(Policy = "StaffPlus")]
    [ProducesResponseType(typeof(InvoiceResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<InvoiceResponse>> SplitPay(Guid id, [FromBody] SplitPaymentRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _billingService.SplitPayInvoiceAsync(actor, id, request, ct));
    }

    /// <summary>
    /// Starts an online payment (Stripe / PayPal, or the sandbox when the
    /// business has no gateway). Customers may pay their own invoices.
    /// </summary>
    [HttpPost("{id:guid}/checkout")]
    [ProducesResponseType(typeof(CheckoutResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status502BadGateway)]
    public async Task<ActionResult<CheckoutResponse>> Checkout(Guid id, [FromBody] CheckoutRequest? request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return FromResult(await _checkout.StartCheckoutAsync(actor, id, request ?? new CheckoutRequest(), ct));
    }

    /// <summary>Gets the receipt breakdown for an invoice.</summary>
    [HttpGet("{id:guid}/receipt")]
    [ProducesResponseType(typeof(ReceiptResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<ReceiptResponse>> GetReceipt(Guid id, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return FromResult(await _billingService.GetReceiptAsync(actor, id, ct));
    }

    /// <summary>Downloads the receipt (or unpaid invoice) as a PDF.</summary>
    [HttpGet("{id:guid}/receipt.pdf")]
    [Produces("application/pdf")]
    [ProducesResponseType(typeof(FileContentResult), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetReceiptPdf(Guid id, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        var result = await _billingService.GetReceiptPdfAsync(actor, id, ct);
        if (!result.Success) return StatusCode(result.StatusCode, new { message = result.Error });
        return File(result.Value.Content, "application/pdf", result.Value.FileName);
    }

    /// <summary>Sends the invoice/receipt by email (SendGrid) or SMS/WhatsApp (Twilio).</summary>
    [HttpPost("{id:guid}/send")]
    [Authorize(Policy = "StaffPlus")]
    [ProducesResponseType(typeof(MessageDeliveryResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<MessageDeliveryResponse>> Send(Guid id, [FromBody] SendInvoiceRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _billingService.SendInvoiceAsync(actor, id, request, asReminder: false, ct));
    }

    /// <summary>Sends a payment reminder for an unpaid invoice.</summary>
    [HttpPost("{id:guid}/remind")]
    [Authorize(Policy = "StaffPlus")]
    [ProducesResponseType(typeof(MessageDeliveryResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<MessageDeliveryResponse>> Remind(Guid id, [FromBody] SendInvoiceRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _billingService.SendInvoiceAsync(actor, id, request, asReminder: true, ct));
    }
}
