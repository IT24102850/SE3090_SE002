using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/notifications")]
[Produces("application/json")]
public sealed class NotificationsController(
    AppDbContext db,
    IAuthorizationService authorizationService) : ControllerBase
{
    private const int MaxPageSize = 100;

    [HttpGet]
    [ProducesResponseType(typeof(NotificationListResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<NotificationListResponse>> GetNotifications(
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool unreadOnly = false,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
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

        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);

        var query = db.Notifications.AsNoTracking();

        if (branchId.HasValue)
        {
            query = query.Where(notification => notification.BranchId == branchId.Value);
        }

        if (unreadOnly)
        {
            query = query.Where(notification => !notification.IsRead);
        }

        var totalCount = await query.CountAsync(cancellationToken);
        var unreadCount = await db.Notifications
            .AsNoTracking()
            .Where(notification => !notification.IsRead &&
                (!branchId.HasValue || notification.BranchId == branchId.Value))
            .CountAsync(cancellationToken);

        var notifications = await query
            .OrderBy(notification => notification.IsRead)
            .ThenByDescending(notification => notification.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(notification => new NotificationResponse(
                notification.Id,
                notification.BranchId,
                notification.Type,
                notification.Title,
                notification.Message,
                notification.IsRead,
                notification.CreatedAt,
                notification.UpdatedAt))
            .ToListAsync(cancellationToken);

        var totalPages = (int)Math.Ceiling(totalCount / (double)pageSize);

        return Ok(new NotificationListResponse(
            notifications,
            page,
            pageSize,
            totalCount,
            totalPages,
            unreadCount));
    }

    [HttpPut]
    [Consumes("application/json")]
    [ProducesResponseType(typeof(NotificationUpdateResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<NotificationUpdateResponse>> UpdateNotifications(
        UpdateNotificationsRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        var notificationIds = request.NotificationIds?
            .Where(id => id != Guid.Empty)
            .Distinct()
            .ToList() ?? [];

        var query = db.Notifications.AsQueryable();

        if (notificationIds.Count > 0)
        {
            query = query.Where(notification => notificationIds.Contains(notification.Id));
        }
        else if (request.BranchId.HasValue)
        {
            query = query.Where(notification => notification.BranchId == request.BranchId.Value);
        }
        else
        {
            ModelState.AddModelError("notificationIds", "Provide notificationIds or branchId before updating notifications.");
            return ValidationProblem(ModelState);
        }

        var notifications = await query.ToListAsync(cancellationToken);
        var branchIds = notifications
            .Select(notification => notification.BranchId)
            .Append(request.BranchId)
            .Distinct()
            .ToList();

        foreach (var branchId in branchIds)
        {
            if (!await this.IsInventoryOperationAuthorizedAsync(
                    authorizationService,
                    InventoryAuthorizationPolicies.InventoryWrite,
                    tenantId,
                    branchId))
            {
                return Forbid();
            }
        }

        var now = DateTime.UtcNow;
        foreach (var notification in notifications)
        {
            notification.IsRead = request.IsRead;
            notification.UpdatedAt = now;
        }

        await db.SaveChangesAsync(cancellationToken);

        return Ok(new NotificationUpdateResponse(notifications.Count, request.IsRead));
    }

    private bool TryGetTenantId(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out tenantId);
}

public sealed record NotificationListResponse(
    IReadOnlyList<NotificationResponse> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages,
    int UnreadCount);

public sealed record NotificationResponse(
    Guid Id,
    Guid? BranchId,
    string Type,
    string Title,
    string Message,
    bool IsRead,
    DateTime CreatedAt,
    DateTime UpdatedAt);

public sealed record UpdateNotificationsRequest(
    IReadOnlyList<Guid>? NotificationIds,
    Guid? BranchId = null,
    bool IsRead = true);

public sealed record NotificationUpdateResponse(
    int UpdatedCount,
    bool IsRead);
