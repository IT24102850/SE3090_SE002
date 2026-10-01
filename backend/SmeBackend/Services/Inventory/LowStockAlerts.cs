using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Services.Inventory;

/// <summary>
/// Raises one "LowStock" notification when an item's stock falls below its
/// reorder level - on the movement that crosses the line, not on every
/// movement after it, so a busy day does not bury the alert. The notification
/// reaches the web bell and, through the live stream, the phones of signed-in
/// staff (DeviceNotificationService in the Flutter app).
/// </summary>
public static class LowStockAlerts
{
    public static bool Crossed(decimal before, decimal after, decimal reorderLevel) =>
        reorderLevel > 0 && before >= reorderLevel && after < reorderLevel;

    public static void QueueIfCrossed(AppDbContext db, InventoryItem item, decimal quantityBefore)
    {
        if (!Crossed(quantityBefore, item.Quantity, item.ReorderLevel)) return;

        db.Notifications.Add(new Notification
        {
            TenantId = item.TenantId,
            BranchId = item.BranchId,
            UserId = null,
            Type = "LowStock",
            Title = item.Quantity <= 0 ? $"{item.Name} is out of stock" : $"{item.Name} is low on stock",
            Message = $"{item.Quantity:0.###} left, below the reorder level of {item.ReorderLevel:0.###}. Ask StockSense for a reorder.",
            IsRead = false,
        });
    }
}
