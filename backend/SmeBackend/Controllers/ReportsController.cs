using System.Globalization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/reports")]
public sealed class ReportsController(
    AppDbContext db,
    IAuthorizationService authorizationService) : ControllerBase
{
    [HttpGet("inventory-usage")]
    public async Task<ActionResult<InventoryUsageReportResponse>> GetInventoryUsage(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] Guid? branchId = null,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryRead,
                tenantId,
                branchId))
        {
            return Forbid();
        }

        var range = NormalizeRange(from, to);
        if (range is null)
        {
            AddDateRangeValidationError();
            return ValidationProblem(ModelState);
        }

        var query = db.StockMovements
            .AsNoTracking()
            .Where(movement =>
                movement.OccurredAt >= range.Value.From &&
                movement.OccurredAt < range.Value.ToExclusive);

        if (branchId.HasValue)
        {
            query = query.Where(movement => movement.BranchId == branchId.Value);
        }

        var movements = await query
            .OrderBy(movement => movement.OccurredAt)
            .ToListAsync(cancellationToken);

        var itemIds = movements
            .Select(movement => movement.InventoryItemId)
            .Distinct()
            .ToList();

        var items = await db.InventoryItems
            .AsNoTracking()
            .Where(item => itemIds.Contains(item.Id))
            .ToDictionaryAsync(item => item.Id, item => new { item.Name, item.Sku }, cancellationToken);

        var rows = movements
            .GroupBy(movement => movement.InventoryItemId)
            .Select(group =>
            {
                items.TryGetValue(group.Key, out var item);
                var received = group
                    .Where(movement => movement.Quantity > 0)
                    .Sum(movement => movement.Quantity);
                var issued = group
                    .Where(movement => movement.Quantity < 0)
                    .Sum(movement => Math.Abs(movement.Quantity));

                return new InventoryUsageItemResponse(
                    group.Key,
                    item?.Name,
                    item?.Sku,
                    received,
                    issued,
                    received - issued,
                    group.Count());
            })
            .OrderByDescending(row => row.IssuedQuantity)
            .ThenBy(row => row.ItemName)
            .ToList();

        return Ok(new InventoryUsageReportResponse(
            range.Value.From,
            range.Value.ToInclusive,
            branchId,
            rows.Sum(row => row.ReceivedQuantity),
            rows.Sum(row => row.IssuedQuantity),
            rows.Sum(row => row.NetQuantity),
            rows));
    }

    [HttpGet("revenue")]
    public async Task<ActionResult<RevenueReportResponse>> GetRevenue(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] Guid? branchId = null,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryRead,
                tenantId,
                branchId))
        {
            return Forbid();
        }

        var range = NormalizeRange(from, to);
        if (range is null)
        {
            AddDateRangeValidationError();
            return ValidationProblem(ModelState);
        }

        var buckets = CreateDailyBuckets(range.Value)
            .Select(day => new RevenueBucketResponse(day, FormatDay(day), 0m))
            .ToList();

        return Ok(new RevenueReportResponse(
            range.Value.From,
            range.Value.ToInclusive,
            branchId,
            0m,
            buckets,
            "Revenue tables are not available yet; this report returns zero-valued buckets until sales data is added."));
    }

    [HttpGet("patient-count")]
    public async Task<ActionResult<PatientCountReportResponse>> GetPatientCount(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] Guid? branchId = null,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryRead,
                tenantId,
                branchId))
        {
            return Forbid();
        }

        var range = NormalizeRange(from, to);
        if (range is null)
        {
            AddDateRangeValidationError();
            return ValidationProblem(ModelState);
        }

        var usersQuery = db.Users
            .AsNoTracking()
            .Where(user => user.TenantId == tenantId && user.Role == UserRole.Customer);

        if (branchId.HasValue)
        {
            usersQuery = usersQuery.Where(user => user.BranchId == branchId.Value);
        }

        var totalPatients = await usersQuery.CountAsync(cancellationToken);
        var newPatientDates = await usersQuery
            .Where(user => user.CreatedAt >= range.Value.From && user.CreatedAt < range.Value.ToExclusive)
            .Select(user => user.CreatedAt)
            .ToListAsync(cancellationToken);

        var newPatientsByDay = newPatientDates
            .GroupBy(createdAt => createdAt.Date)
            .ToDictionary(group => group.Key, group => group.Count());

        var buckets = CreateDailyBuckets(range.Value)
            .Select(day => new PatientCountBucketResponse(
                day,
                FormatDay(day),
                newPatientsByDay.GetValueOrDefault(day)))
            .ToList();

        return Ok(new PatientCountReportResponse(
            range.Value.From,
            range.Value.ToInclusive,
            branchId,
            totalPatients,
            buckets.Sum(bucket => bucket.NewPatients),
            buckets));
    }

    private bool TryGetTenantId(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out tenantId);

    private static ReportDateRange? NormalizeRange(DateTime? from, DateTime? to)
    {
        var today = DateTime.UtcNow.Date;
        var fromDate = ToUtcDate(from ?? today.AddDays(-29));
        var toDate = ToUtcDate(to ?? today);

        if (fromDate > toDate)
        {
            return null;
        }

        return new ReportDateRange(fromDate, toDate, toDate.AddDays(1));
    }

    private static DateTime ToUtcDate(DateTime value)
    {
        var utc = value.Kind switch
        {
            DateTimeKind.Local => value.ToUniversalTime(),
            DateTimeKind.Unspecified => DateTime.SpecifyKind(value, DateTimeKind.Utc),
            _ => value,
        };

        return utc.Date;
    }

    private static IEnumerable<DateTime> CreateDailyBuckets(ReportDateRange range)
    {
        for (var day = range.From; day <= range.ToInclusive; day = day.AddDays(1))
        {
            yield return day;
        }
    }

    private static string FormatDay(DateTime day) =>
        day.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    private void AddDateRangeValidationError() =>
        ModelState.AddModelError("dateRange", "The from date must be earlier than or equal to the to date.");
}

internal readonly record struct ReportDateRange(
    DateTime From,
    DateTime ToInclusive,
    DateTime ToExclusive);

public sealed record InventoryUsageReportResponse(
    DateTime From,
    DateTime To,
    Guid? BranchId,
    decimal TotalReceivedQuantity,
    decimal TotalIssuedQuantity,
    decimal NetQuantity,
    IReadOnlyList<InventoryUsageItemResponse> Items);

public sealed record InventoryUsageItemResponse(
    Guid InventoryItemId,
    string? ItemName,
    string? Sku,
    decimal ReceivedQuantity,
    decimal IssuedQuantity,
    decimal NetQuantity,
    int MovementCount);

public sealed record RevenueReportResponse(
    DateTime From,
    DateTime To,
    Guid? BranchId,
    decimal TotalRevenue,
    IReadOnlyList<RevenueBucketResponse> Buckets,
    string DataSourceNote);

public sealed record RevenueBucketResponse(
    DateTime Date,
    string Label,
    decimal Revenue);

public sealed record PatientCountReportResponse(
    DateTime From,
    DateTime To,
    Guid? BranchId,
    int TotalPatients,
    int NewPatients,
    IReadOnlyList<PatientCountBucketResponse> Buckets);

public sealed record PatientCountBucketResponse(
    DateTime Date,
    string Label,
    int NewPatients);
