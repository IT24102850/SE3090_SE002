using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;

namespace SmeBackend.Controllers;

[ApiController]
[Authorize]
[Route("api/workspace-assistant")]
public sealed class WorkspaceAssistantController(AppDbContext db) : ControllerBase
{
    [HttpPost("chat")]
    public async Task<ActionResult<AssistantChatResponse>> Chat(
        AssistantChatRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Message))
        {
            return BadRequest(new { message = "Ask a question about your workspace." });
        }

        if (!Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out var tenantId))
        {
            return Unauthorized();
        }

        var message = request.Message.Trim();
        var normalized = message.ToLowerInvariant();
        var inventoryCount = await db.InventoryItems.CountAsync(item => item.TenantId == tenantId && item.IsActive, cancellationToken);
        var lowStockItems = await db.InventoryItems
            .AsNoTracking()
            .Where(item => item.TenantId == tenantId && item.IsActive && item.Quantity <= item.ReorderLevel)
            .OrderBy(item => item.Quantity)
            .Select(item => new AssistantInventoryItem(item.Name, item.Quantity, item.ReorderLevel, item.Branch != null ? item.Branch.Name : null))
            .Take(8)
            .ToListAsync(cancellationToken);
        var branchCount = await db.Branches.CountAsync(branch => branch.TenantId == tenantId && branch.IsActive, cancellationToken);
        var openOrders = await db.PurchaseOrders.CountAsync(order => order.TenantId == tenantId && order.Status != "Received" && order.Status != "Cancelled", cancellationToken);
        var bookingCount = await db.Bookings.CountAsync(booking => booking.TenantId == tenantId && booking.Status != SmeBackend.Models.BookingStatus.Cancelled, cancellationToken);

        string answer;
        if (normalized.Contains("low stock") || normalized.Contains("reorder") || normalized.Contains("inventory"))
        {
            answer = lowStockItems.Count == 0
                ? $"Your workspace has {inventoryCount} active inventory items and no items at or below their reorder level."
                : $"You have {lowStockItems.Count} item(s) at or below reorder level. " +
                  string.Join(" ", lowStockItems.Select(item =>
                      $"{item.Name}: {item.Quantity:0.##} remaining (reorder at {item.ReorderLevel:0.##})" +
                      (string.IsNullOrWhiteSpace(item.BranchName) ? "." : $" at {item.BranchName}.")));
        }
        else if (normalized.Contains("purchase order") || normalized.Contains("po"))
        {
            answer = $"There are {openOrders} open purchase order(s). You can create or review them from Purchase Orders, including line items, quantities, unit prices, suppliers, and branches.";
        }
        else if (normalized.Contains("branch") || normalized.Contains("location"))
        {
            answer = $"Your workspace has {branchCount} active branch(es). Branch Overview shows stock value, quantities, and replenishment needs by branch.";
        }
        else if (normalized.Contains("booking") || normalized.Contains("appointment") || normalized.Contains("schedule"))
        {
            answer = $"There are {bookingCount} non-cancelled booking(s) in the workspace. Use Booking Manager for changes, Multi-Branch Schedule for availability, or AI Planner for scheduling proposals.";
        }
        else if (normalized.Contains("help") || normalized.Contains("what can") || normalized.Contains("how"))
        {
            answer = "I can help with inventory and low-stock questions, purchase orders, branches, bookings, schedules, AI workflows, and where to find features. Ask something like “Which items need reordering?” or “How many open purchase orders do we have?”";
        }
        else
        {
            answer = $"I can answer questions about this workspace using live data. Currently I can see {inventoryCount} active inventory item(s), {branchCount} active branch(es), {openOrders} open purchase order(s), and {bookingCount} non-cancelled booking(s). Try asking about low stock, purchase orders, branches, bookings, or AI workflows.";
        }

        return Ok(new AssistantChatResponse(answer, DateTimeOffset.UtcNow));
    }
}

public sealed record AssistantChatRequest(string Message);
public sealed record AssistantChatResponse(string Answer, DateTimeOffset AnsweredAt);
public sealed record AssistantInventoryItem(string Name, decimal Quantity, decimal ReorderLevel, string? BranchName);
