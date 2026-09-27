using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.DTOs;
using SmeBackend.Services.Billing;

namespace SmeBackend.Controllers;

/// Billing reports. Shares the /api/reports prefix with ReportsController
/// (inventory/booking reports); the paths do not overlap.
[ApiController]
[Authorize(Policy = "ManagerPlus")]
[Produces("application/json")]
public class BillingReportsController : BillingControllerBase
{
    private readonly IBillingReportService _reports;

    public BillingReportsController(IBillingReportService reports) => _reports = reports;

    /// <summary>Money collected on one day, by method, hour and currency.</summary>
    /// <remarks>GET /api/reports/daily-revenue?tenantId=&amp;branchId=&amp;date=</remarks>
    [HttpGet("api/reports/daily-revenue")]
    [ProducesResponseType(typeof(DailyRevenueResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<DailyRevenueResponse>> DailyRevenue(
        [FromQuery] Guid? tenantId = null, [FromQuery] Guid? branchId = null, [FromQuery] DateTime? date = null, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (RejectForeignTenant(actor, tenantId) is { } forbidden) return forbidden;
        return Ok(await _reports.GetDailyRevenueAsync(actor.TenantId, date ?? DateTime.UtcNow.Date, branchId, ct));
    }

    /// <summary>Unpaid invoices with an aging breakdown.</summary>
    /// <remarks>GET /api/reports/outstanding-payments?tenantId=&amp;agingDays= (0 = every open invoice)</remarks>
    [HttpGet("api/reports/outstanding-payments")]
    [ProducesResponseType(typeof(OutstandingPaymentsResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<OutstandingPaymentsResponse>> OutstandingPayments(
        [FromQuery] Guid? tenantId = null, [FromQuery] int agingDays = 0, [FromQuery] Guid? branchId = null, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (RejectForeignTenant(actor, tenantId) is { } forbidden) return forbidden;
        return Ok(await _reports.GetOutstandingPaymentsAsync(actor.TenantId, agingDays, branchId, ct));
    }

    /// <summary>Everything the Billing Dashboard shows, in one call.</summary>
    [HttpGet("api/billing/dashboard")]
    [ProducesResponseType(typeof(BillingDashboardResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<BillingDashboardResponse>> Dashboard(
        [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null, [FromQuery] Guid? branchId = null, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        var end = to ?? DateTime.UtcNow.Date;
        var start = from ?? end.AddDays(-29);
        return Ok(await _reports.GetDashboardAsync(actor.TenantId, start, end, branchId, ct));
    }
}
