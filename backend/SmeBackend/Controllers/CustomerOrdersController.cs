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
[Authorize(Roles = nameof(UserRole.Customer))]
[Route("api/customer-orders")]
[Produces("application/json")]
public sealed class CustomerOrdersController(AppDbContext db, IBillingMessenger messenger) : ControllerBase
{
    [HttpGet("branches")]
    public async Task<ActionResult<IReadOnlyList<CustomerOrderBranchResponse>>> GetBranches(
        CancellationToken cancellationToken)
    {
        if (!TryGetIdentity(out var tenantId, out _)) return Unauthorized();

        var branches = await db.Branches.AsNoTracking()
            .Where(branch => branch.TenantId == tenantId)
            .OrderBy(branch => branch.Name)
            .Select(branch => new CustomerOrderBranchResponse(branch.Id, branch.Name, branch.Address))
            .ToListAsync(cancellationToken);
        return Ok(branches);
    }

    [HttpGet("products")]
    public async Task<ActionResult<IReadOnlyList<CustomerProductResponse>>> GetProducts(
        [FromQuery] Guid branchId,
        CancellationToken cancellationToken)
    {
        if (!TryGetIdentity(out var tenantId, out _)) return Unauthorized();
        if (!await db.Branches.AnyAsync(
                branch => branch.Id == branchId && branch.TenantId == tenantId,
                cancellationToken))
        {
            return BadRequest(new { message = "Choose a valid business location." });
        }

        var products = await db.InventoryItems.AsNoTracking()
            .Where(item => item.TenantId == tenantId &&
                           item.BranchId == branchId &&
                           item.IsActive &&
                           item.SellingPrice.HasValue &&
                           item.SellingPrice.Value >= 0m &&
                           item.Quantity > 0)
            .Include(item => item.Category)
            .Include(item => item.Unit)
            .OrderBy(item => item.Name)
            .Select(item => new CustomerProductResponse(
                item.Id,
                item.Name,
                item.Description,
                item.Sku,
                item.Category == null ? "Everyday essentials" : item.Category.Name,
                item.Unit == null ? null : item.Unit.Name,
                item.Quantity,
                item.SellingPrice!.Value))
            .ToListAsync(cancellationToken);

        return Ok(products);
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<CustomerOrderResponse>>> GetMyOrders(
        CancellationToken cancellationToken)
    {
        if (!TryGetIdentity(out var tenantId, out var customerId)) return Unauthorized();

        var orders = await db.CustomerOrders.AsNoTracking()
            .Where(order => order.TenantId == tenantId && order.CustomerId == customerId)
            .OrderByDescending(order => order.CreatedAt)
            .Include(order => order.Items)
            .Include(order => order.StatusUpdates)
            .ToListAsync(cancellationToken);
        return Ok(orders.Select(ToResponse).ToList());
    }

    [HttpPost]
    public async Task<ActionResult<CustomerOrderResponse>> PlaceOrder(
        [FromBody] PlaceCustomerOrderRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetIdentity(out var tenantId, out var customerId)) return Unauthorized();
        if (request.Items is null || request.Items.Count is < 1 or > 100)
        {
            return BadRequest(new { message = "Choose between 1 and 100 products for your order." });
        }

        var fulfillmentMethod = request.FulfillmentMethod?.Trim();
        if (fulfillmentMethod is not ("Pickup" or "Delivery"))
        {
            return BadRequest(new { message = "Choose pickup or delivery." });
        }

        var deliveryAddress = request.DeliveryAddress?.Trim();
        if (fulfillmentMethod == "Delivery" &&
            (string.IsNullOrWhiteSpace(deliveryAddress) || deliveryAddress.Length > 500))
        {
            return BadRequest(new { message = "Enter a delivery address of 1 to 500 characters." });
        }

        if (request.Notes?.Length > 1000)
        {
            return BadRequest(new { message = "Order notes cannot exceed 1,000 characters." });
        }
        if (request.DeliveryLatitude.HasValue != request.DeliveryLongitude.HasValue ||
            request.DeliveryLatitude is < -90 or > 90 ||
            request.DeliveryLongitude is < -180 or > 180 ||
            (fulfillmentMethod == "Pickup" &&
             (request.DeliveryLatitude.HasValue || request.DeliveryLongitude.HasValue)))
        {
            return BadRequest(new { message = "Delivery coordinates must be a valid latitude/longitude pair for a delivery order." });
        }

        if (!await db.Branches.AnyAsync(
                branch => branch.Id == request.BranchId && branch.TenantId == tenantId,
                cancellationToken))
        {
            return BadRequest(new { message = "Choose a valid business location." });
        }

        var quantities = new Dictionary<Guid, decimal>();
        foreach (var line in request.Items)
        {
            if (line.Quantity <= 0 || line.Quantity > 99999 ||
                decimal.Round(line.Quantity, 3) != line.Quantity)
            {
                return BadRequest(new { message = "Product quantities must be positive and use at most 3 decimal places." });
            }
            quantities[line.InventoryItemId] = quantities.GetValueOrDefault(line.InventoryItemId) + line.Quantity;
        }

        if (quantities.Values.Any(quantity => quantity > 99999))
        {
            return BadRequest(new { message = "The requested quantity is too large." });
        }

        var inventoryItems = await db.InventoryItems
            .Where(item => item.TenantId == tenantId &&
                           item.BranchId == request.BranchId &&
                           item.IsActive &&
                           item.SellingPrice.HasValue &&
                           item.SellingPrice.Value >= 0m &&
                           quantities.Keys.Contains(item.Id))
            .Include(item => item.Unit)
            .ToListAsync(cancellationToken);

        if (inventoryItems.Count != quantities.Count)
        {
            return Conflict(new { message = "One or more products are no longer available at this location. Refresh the catalog and try again." });
        }

        var orderId = Guid.NewGuid();
        var number = $"ORD-{DateTime.UtcNow:yyMMdd}-{orderId.ToString("N")[..8].ToUpperInvariant()}";
        var order = new CustomerOrder
        {
            Id = orderId,
            TenantId = tenantId,
            CustomerId = customerId,
            BranchId = request.BranchId,
            Number = number,
            Status = "Pending",
            PaymentStatus = "DueOnFulfillment",
            FulfillmentMethod = fulfillmentMethod,
            DeliveryAddress = fulfillmentMethod == "Delivery" ? deliveryAddress : null,
            DeliveryLatitude = fulfillmentMethod == "Delivery" ? request.DeliveryLatitude : null,
            DeliveryLongitude = fulfillmentMethod == "Delivery" ? request.DeliveryLongitude : null,
            Notes = string.IsNullOrWhiteSpace(request.Notes) ? null : request.Notes.Trim(),
        };
        order.StatusUpdates.Add(new CustomerOrderStatusUpdate
        {
            TenantId = tenantId,
            CustomerOrderId = orderId,
            Status = "Pending",
            Message = "Order placed and waiting for the business to confirm.",
            ChangedByUserId = customerId,
        });

        foreach (var item in inventoryItems.OrderBy(item => item.Id))
        {
            var quantity = quantities[item.Id];
            var unitPrice = item.SellingPrice!.Value;
            var lineTotal = decimal.Round(unitPrice * quantity, 2, MidpointRounding.AwayFromZero);
            order.Total += lineTotal;
            order.Items.Add(new CustomerOrderItem
            {
                TenantId = tenantId,
                CustomerOrderId = orderId,
                InventoryItemId = item.Id,
                ItemName = item.Name,
                Sku = item.Sku,
                UnitName = item.Unit?.Name,
                Quantity = quantity,
                UnitPrice = unitPrice,
                LineTotal = lineTotal,
            });
        }

        await using var transaction = db.Database.IsRelational()
            ? await db.Database.BeginTransactionAsync(cancellationToken)
            : null;

        foreach (var item in inventoryItems.OrderBy(item => item.Id))
        {
            var quantity = quantities[item.Id];
            if (db.Database.IsRelational())
            {
                var affectedRows = await db.InventoryItems
                    .Where(candidate => candidate.Id == item.Id &&
                                        candidate.TenantId == tenantId &&
                                        candidate.BranchId == request.BranchId &&
                                        candidate.IsActive &&
                                        candidate.SellingPrice.HasValue &&
                                        candidate.Quantity >= quantity)
                    .ExecuteUpdateAsync(update => update
                        .SetProperty(candidate => candidate.Quantity, candidate => candidate.Quantity - quantity),
                        cancellationToken);
                if (affectedRows == 0)
                {
                    return Conflict(new { message = $"{item.Name} no longer has enough stock. Refresh the catalog and try again." });
                }
            }
            else
            {
                if (item.Quantity < quantity)
                {
                    return Conflict(new { message = $"{item.Name} no longer has enough stock. Refresh the catalog and try again." });
                }
                item.Quantity -= quantity;
            }

            if (item.BranchId.HasValue)
            {
                db.StockMovements.Add(new StockMovement
                {
                    TenantId = tenantId,
                    BranchId = item.BranchId.Value,
                    InventoryItemId = item.Id,
                    MovementType = "CustomerOrder",
                    Quantity = -quantity,
                    UnitCost = item.UnitCost,
                    Reference = number,
                    Notes = $"Reserved for customer {customerId}",
                    PerformedBy = User.FindFirst("fullName")?.Value ?? "Customer",
                });
            }
        }

        NotificationHelper.Queue(
            db,
            tenantId,
            customerId,
            "CustomerOrder",
            "Your order is placed",
            $"{number} is awaiting confirmation. Pay when you receive your order.");
        var businessRecipients = await db.Users.AsNoTracking()
            .Where(user => user.TenantId == tenantId &&
                           user.IsActive &&
                           (user.Role == UserRole.Admin ||
                            (user.BranchId == request.BranchId &&
                             (user.Role == UserRole.Manager || user.Role == UserRole.Staff))))
            .Select(user => user.Id)
            .ToListAsync(cancellationToken);
        foreach (var recipientId in businessRecipients)
        {
            NotificationHelper.Queue(
                db,
                tenantId,
                recipientId,
                "CustomerOrder",
                $"New customer order {number}",
                $"A {fulfillmentMethod.ToLowerInvariant()} order for LKR {order.Total:0.00} is ready to prepare.");
        }

        db.CustomerOrders.Add(order);
        await db.SaveChangesAsync(cancellationToken);
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);

        await EmailOrderUpdateAsync(tenantId, customerId, order, "Your order is placed", cancellationToken);
        return CreatedAtAction(nameof(GetMyOrders), new { }, ToResponse(order));
    }

    private async Task EmailOrderUpdateAsync(
        Guid tenantId,
        Guid customerId,
        CustomerOrder order,
        string subject,
        CancellationToken cancellationToken)
    {
        var email = await db.Users.IgnoreQueryFilters().AsNoTracking()
            .Where(user => user.Id == customerId && user.TenantId == tenantId && user.IsActive)
            .Select(user => user.Email)
            .FirstOrDefaultAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(email)) return;

        var safeNumber = HtmlEncoder.Default.Encode(order.Number);
        var safeStatus = HtmlEncoder.Default.Encode(order.Status);
        var html = $"<p>Your order <strong>{safeNumber}</strong> is now <strong>{safeStatus}</strong>.</p>" +
                   $"<p>Total: LKR {order.Total:0.00}. Payment is due when you receive your order.</p>";
        await messenger.SendEmailAsync(email, subject, html, ct: cancellationToken);
    }

    private bool TryGetIdentity(out Guid tenantId, out Guid customerId)
    {
        var tenantClaim = User.FindFirst("tenantId")?.Value;
        var customerClaim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                            ?? User.FindFirst("sub")?.Value;
        var hasTenant = Guid.TryParse(tenantClaim, out tenantId);
        var hasCustomer = Guid.TryParse(customerClaim, out customerId);
        return hasTenant && hasCustomer;
    }

    public static CustomerOrderResponse ToResponse(CustomerOrder order) =>
        new(
            order.Id,
            order.BranchId,
            order.Number,
            order.Status,
            order.PaymentStatus,
            order.FulfillmentMethod,
            order.DeliveryAddress,
            order.DeliveryLatitude,
            order.DeliveryLongitude,
            order.Notes,
            order.Total,
            order.CreatedAt,
            order.Items.Select(item => new CustomerOrderLineResponse(
                item.InventoryItemId,
                item.ItemName,
                item.Sku,
                item.UnitName,
                item.Quantity,
                item.UnitPrice,
                item.LineTotal)).ToList(),
            order.StatusUpdates.OrderBy(update => update.CreatedAt)
                .Select(update => new CustomerOrderStatusUpdateResponse(
                    update.Status,
                    update.Message,
                    update.CreatedAt))
                .ToList());
}

public sealed record CustomerOrderBranchResponse(Guid Id, string Name, string? Address);
public sealed record CustomerProductResponse(
    Guid Id,
    string Name,
    string? Description,
    string Sku,
    string Category,
    string? Unit,
    decimal QuantityAvailable,
    decimal Price);
public sealed record PlaceCustomerOrderLineRequest(Guid InventoryItemId, decimal Quantity);
public sealed record PlaceCustomerOrderRequest(
    Guid BranchId,
    string FulfillmentMethod,
    string? DeliveryAddress,
    string? Notes,
    IReadOnlyList<PlaceCustomerOrderLineRequest> Items,
    decimal? DeliveryLatitude = null,
    decimal? DeliveryLongitude = null);
public sealed record CustomerOrderLineResponse(
    Guid InventoryItemId,
    string ItemName,
    string Sku,
    string? Unit,
    decimal Quantity,
    decimal UnitPrice,
    decimal LineTotal);
public sealed record CustomerOrderStatusUpdateResponse(string Status, string Message, DateTime CreatedAt);
public sealed record CustomerOrderResponse(
    Guid Id,
    Guid BranchId,
    string Number,
    string Status,
    string PaymentStatus,
    string FulfillmentMethod,
    string? DeliveryAddress,
    decimal? DeliveryLatitude,
    decimal? DeliveryLongitude,
    string? Notes,
    decimal Total,
    DateTime CreatedAt,
    IReadOnlyList<CustomerOrderLineResponse> Items,
    IReadOnlyList<CustomerOrderStatusUpdateResponse> StatusUpdates);
