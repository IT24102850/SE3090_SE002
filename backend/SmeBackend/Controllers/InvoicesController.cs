using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.DTOs;
using SmeBackend.Services;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/invoices")]
[Authorize]
[Produces("application/json")]
public class InvoicesController : ControllerBase
{
    private readonly IBillingService _billingService;

    public InvoicesController(IBillingService billingService)
    {
        _billingService = billingService;
    }

    /// <summary>
    /// Retrieves a paginated list of invoices for the authenticated tenant.
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(InvoiceListResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<InvoiceListResponse>> GetInvoices(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? status = null,
        [FromQuery] Guid? customerId = null,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized(new { message = "Unauthorized: Missing tenant context in token." });
        }

        var result = await _billingService.GetInvoicesAsync(
            tenantId,
            page,
            pageSize,
            status,
            customerId,
            cancellationToken);

        return Ok(result);
    }

    /// <summary>
    /// Creates a new invoice with secure server-side total and tax calculation.
    /// </summary>
    [HttpPost]
    [ProducesResponseType(typeof(InvoiceResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<InvoiceResponse>> CreateInvoice(
        [FromBody] CreateInvoiceRequest request,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized(new { message = "Unauthorized: Missing tenant context in token." });
        }

        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var (success, error, invoice) = await _billingService.CreateInvoiceAsync(
            tenantId,
            request,
            cancellationToken);

        if (!success)
        {
            return BadRequest(new { message = error });
        }

        return StatusCode(StatusCodes.Status201Created, invoice);
    }

    /// <summary>
    /// Records a payment against an invoice and updates its payment status.
    /// </summary>
    [HttpPut("{id:guid}/pay")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> PayInvoice(
        [FromRoute] Guid id,
        [FromBody] PayInvoiceRequest request,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized(new { message = "Unauthorized: Missing tenant context in token." });
        }

        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var (success, error, payment, invoice) = await _billingService.PayInvoiceAsync(
            tenantId,
            id,
            request,
            cancellationToken);

        if (!success)
        {
            if (error == "Invoice not found.")
            {
                return NotFound(new { message = error });
            }

            return BadRequest(new { message = error });
        }

        return Ok(new
        {
            message = "Payment recorded successfully.",
            payment,
            invoice
        });
    }

    /// <summary>
    /// Generates and retrieves the receipt breakdown for a given invoice.
    /// </summary>
    [HttpGet("{id:guid}/receipt")]
    [ProducesResponseType(typeof(ReceiptResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<ReceiptResponse>> GetReceipt(
        [FromRoute] Guid id,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized(new { message = "Unauthorized: Missing tenant context in token." });
        }

        var (success, error, receipt) = await _billingService.GetReceiptAsync(
            tenantId,
            id,
            cancellationToken);

        if (!success)
        {
            return NotFound(new { message = error });
        }

        return Ok(receipt);
    }

    private bool TryGetTenantId(out Guid tenantId)
    {
        var tenantClaim = User.FindFirst("tenantId")?.Value;
        return Guid.TryParse(tenantClaim, out tenantId);
    }
}
