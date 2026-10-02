using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services.Billing;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

[ApiController]
[Authorize(Roles = "Admin,Manager,Staff")]
[Route("api/customer-orders/manage")]
[Produces("application/json")]
public sealed class CustomerOrderManagementController(AppDbContext db, IBillingMessenger messenger) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<ManagedCustomerOrderResponse>>> GetOrders(
        [FromQuery] Guid? branchId,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId)) return Unauthorized();
        var query = db.CustomerOrders.AsNoTracking().Where(order => order.TenantId == tenantId);
        if (User.IsInRole(nameof(UserRole.Staff)))
        {
            if (!TryGetBranchId(out var staffBranchId)) return Forbid();
            if (branchId.HasValue && branchId.Value != staffBranchId) return Forbid();
            query = query.Where(order => order.BranchId == staffBranchId);
        }
        else if (branchId.HasValue)
        {
            query = query.Where(order => order.BranchId == branchId.Value);
        }

        var orders = await query
            .OrderByDescending(order => order.CreatedAt)
            .Include(order => order.Items)
            .Include(order => order.StatusUpdates)
            .ToListAsync(cancellationToken);
        var customerIds = orders.Select(order => order.CustomerId).Distinct().ToArray();
        var customers = await db.Users.AsNoTracking()
            .Where(user => user.TenantId == tenantId && customerIds.Contains(user.Id))
            .ToDictionaryAsync(user => user.Id, user => user.FullName, cancellationToken);
        var branchIds = orders.Select(order => order.BranchId).Distinct().ToArray();
        var branches = await db.Branches.AsNoTracking()
            .Where(branch => branch.TenantId == tenantId && branchIds.Contains(branch.Id))
            .ToDictionaryAsync(branch => branch.Id, branch => branch.Name, cancellationToken);

        return Ok(orders.Select(order => new ManagedCustomerOrderResponse(
            CustomerOrdersController.ToResponse(order),
            customers.GetValueOrDefault(order.CustomerId, "Customer"),
            branches.GetValueOrDefault(order.BranchId, "Store"))).ToList());
    }

    [HttpPut("{orderId:guid}/status")]
    public async Task<IActionResult> UpdateStatus(
        Guid orderId,
        [FromBody] UpdateCustomerOrderStatusRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId)) return Unauthorized();
        var order = await db.CustomerOrders
            .Include(candidate => candidate.Items)
            .FirstOrDefaultAsync(candidate => candidate.Id == orderId && candidate.TenantId == tenantId, cancellationToken);
        if (order is null) return NotFound(new { message = "Order not found." });
        if (!CanManageBranch(order.BranchId)) return Forbid();

        var nextStatus = request.Status?.Trim();
        if (!IsAllowedTransition(order, nextStatus))
        {
            return Conflict(new { message = $"The order cannot move from {order.Status} to {nextStatus ?? "that status"}." });
        }
        if (request.Message?.Length > 500)
        {
            return BadRequest(new { message = "The update note cannot exceed 500 characters." });
        }

        List<InventoryItem> inventory = [];
        if (nextStatus == "Cancelled")
        {
            var orderItemIds = order.Items.Select(line => line.InventoryItemId).Distinct().ToArray();
            inventory = await db.InventoryItems.IgnoreQueryFilters()
                .Where(item => item.TenantId == tenantId &&
                               item.BranchId == order.BranchId &&
                               orderItemIds.Contains(item.Id))
                .ToListAsync(cancellationToken);
        }
        if (nextStatus == "Cancelled" && inventory.Count != order.Items.Select(line => line.InventoryItemId).Distinct().Count())
        {
            return Conflict(new { message = "Reserved stock could not be found, so the order was not cancelled." });
        }

        await using var transaction = db.Database.IsRelational()
            ? await db.Database.BeginTransactionAsync(cancellationToken)
            : null;
        var previousStatus = order.Status;
        if (db.Database.IsRelational())
        {
            var updated = await db.CustomerOrders
                .Where(candidate => candidate.Id == order.Id &&
                                    candidate.TenantId == tenantId &&
                                    candidate.Status == previousStatus)
                .ExecuteUpdateAsync(update => update
                    .SetProperty(candidate => candidate.Status, nextStatus!)
                    .SetProperty(candidate => candidate.UpdatedAt, DateTime.UtcNow), cancellationToken);
            if (updated != 1)
            {
                return Conflict(new { message = "This order changed just now. Refresh it before making another update." });
            }
            order.Status = nextStatus!;
        }
        else
        {
            order.Status = nextStatus!;
            order.UpdatedAt = DateTime.UtcNow;
        }

        if (nextStatus == "Completed")
        {
            db.Sales.Add(new Sale
            {
                TenantId = tenantId,
                BranchId = order.BranchId,
                OccurredAt = DateTime.UtcNow,
                Amount = order.Total,
                Reference = order.Number,
            });
        }

        if (nextStatus == "Cancelled")
        {
            foreach (var line in order.Items)
            {
                var item = inventory.Single(candidate => candidate.Id == line.InventoryItemId);
                if (db.Database.IsRelational())
                {
                    var restored = await db.InventoryItems.IgnoreQueryFilters()
                        .Where(candidate => candidate.Id == item.Id &&
                                            candidate.TenantId == tenantId &&
                                            candidate.BranchId == order.BranchId)
                        .ExecuteUpdateAsync(update => update
                            .SetProperty(candidate => candidate.Quantity, candidate => candidate.Quantity + line.Quantity)
                            .SetProperty(candidate => candidate.UpdatedAt, DateTime.UtcNow), cancellationToken);
                    if (restored != 1)
                    {
                        return Conflict(new { message = "Reserved stock could not be restored, so the order was not cancelled." });
                    }
                }
                else
                {
                    item.Quantity += line.Quantity;
                }
                db.StockMovements.Add(new StockMovement
                {
                    TenantId = tenantId,
                    BranchId = order.BranchId,
                    InventoryItemId = item.Id,
                    MovementType = "CustomerOrderCancellation",
                    Quantity = line.Quantity,
                    UnitCost = item.UnitCost,
                    Reference = order.Number,
                    Notes = "Reserved stock released after order cancellation.",
                    PerformedBy = User.FindFirst("fullName")?.Value ?? "Business staff",
                });
            }
        }

        var changedBy = Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId)
            ? userId
            : (Guid?)null;
        var message = string.IsNullOrWhiteSpace(request.Message)
            ? DefaultMessage(nextStatus!, order.FulfillmentMethod)
            : request.Message.Trim();
        db.CustomerOrderStatusUpdates.Add(new CustomerOrderStatusUpdate
        {
            TenantId = tenantId,
            CustomerOrderId = order.Id,
            Status = nextStatus!,
            Message = message,
            ChangedByUserId = changedBy,
        });
        NotificationHelper.Queue(
            db,
            tenantId,
            order.CustomerId,
            "CustomerOrder",
            $"Order {order.Number}: {nextStatus}",
            message);

        await db.SaveChangesAsync(cancellationToken);
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);

        var customerEmail = await db.Users.IgnoreQueryFilters().AsNoTracking()
            .Where(user => user.Id == order.CustomerId && user.TenantId == tenantId && user.IsActive)
            .Select(user => user.Email)
            .FirstOrDefaultAsync(cancellationToken);
        if (!string.IsNullOrWhiteSpace(customerEmail))
        {
            var safeNumber = HtmlEncoder.Default.Encode(order.Number);
            var safeStatus = HtmlEncoder.Default.Encode(nextStatus!);
            var safeMessage = HtmlEncoder.Default.Encode(message);
            await messenger.SendEmailAsync(
                customerEmail,
                $"Order {order.Number} update",
                $"<p>Order <strong>{safeNumber}</strong> is now <strong>{safeStatus}</strong>.</p><p>{safeMessage}</p>",
                ct: cancellationToken);
        }

        return Ok(new { orderId = order.Id, order.Number, status = order.Status, message });
    }

    private bool CanManageBranch(Guid branchId)
    {
        if (User.IsInRole(nameof(UserRole.Admin)) || User.IsInRole(nameof(UserRole.Manager))) return true;
        return TryGetBranchId(out var staffBranchId) && staffBranchId == branchId;
    }

    private bool TryGetTenantId(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst("tenantId")?.Value, out tenantId);

    private bool TryGetBranchId(out Guid branchId) =>
        Guid.TryParse(User.FindFirst("branchId")?.Value, out branchId);

    private static bool IsAllowedTransition(CustomerOrder order, string? next) =>
        order.Status switch
        {
            "Pending" => next is "Confirmed" or "Cancelled",
            "Confirmed" => next is "Preparing" or "Cancelled",
            "Preparing" => next == "Cancelled" ||
                           (order.FulfillmentMethod == "Pickup" && next == "ReadyForPickup") ||
                           (order.FulfillmentMethod == "Delivery" && next == "OutForDelivery"),
            "ReadyForPickup" => next == "Completed",
            "OutForDelivery" => next == "Completed",
            _ => false,
        };

    private static string DefaultMessage(string status, string fulfillmentMethod) =>
        status switch
        {
            "Confirmed" => "The business confirmed your order.",
            "Preparing" => "Your items are being prepared.",
            "ReadyForPickup" => "Your order is ready for pickup.",
            "OutForDelivery" => "Your order is on its way.",
            "Completed" => fulfillmentMethod == "Delivery"
                ? "Your order has been delivered."
                : "Your order has been picked up.",
            "Cancelled" => "Your order was cancelled and reserved stock has been released.",
            _ => $"Your order status changed to {status}.",
        };
}

public sealed record UpdateCustomerOrderStatusRequest(string Status, string? Message);
public sealed record ManagedCustomerOrderResponse(CustomerOrderResponse Order, string CustomerName, string BranchName);
