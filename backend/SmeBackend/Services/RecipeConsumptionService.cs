using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Services;

/// Decrements ingredient stock when an order enters the kitchen.
///
/// A menu type's ConfigJson may carry a recipe (see RestaurantConfig); the
/// moment its order moves to CheckedIn - "preparing" on the restaurant
/// board - each line is taken off the matching inventory item (by SKU, in
/// the order's tenant) and a "Consumption" stock movement is written with
/// the order id as its reference. That reference is also the idempotency
/// key: re-saving the status, or the mobile app and the web board both
/// pressing "Start prep", consumes the recipe once.
///
/// Stock is never driven below zero here: a kitchen that has already
/// plated the dish has used the ingredient whatever the count said, so the
/// shortfall is recorded in the movement's notes for the stock take rather
/// than blocking the order. The low-stock alert then does its job.
public static class RecipeConsumptionService
{
    public const string MovementType = "Consumption";

    public static string ReferenceFor(Guid bookingId) => $"ORDER-{bookingId:N}";

    /// Applies the recipe to stock. Adds to the change tracker only - the
    /// caller's SaveChangesAsync commits it together with the status change.
    public static async Task<int> ApplyAsync(AppDbContext db, Booking booking, CancellationToken cancellationToken = default)
    {
        var type = booking.BookingType ?? await db.BookingTypes.AsNoTracking()
            .FirstOrDefaultAsync(bt => bt.Id == booking.BookingTypeId, cancellationToken);
        if (type == null) return 0;

        var recipe = RestaurantConfig.RecipeOf(type);
        if (recipe.Count == 0) return 0;

        var reference = ReferenceFor(booking.Id);
        var alreadyConsumed = await db.StockMovements.AsNoTracking()
            .AnyAsync(m => m.TenantId == booking.TenantId && m.MovementType == MovementType && m.Reference == reference, cancellationToken);
        if (alreadyConsumed) return 0;

        var skus = recipe.Select(r => r.Sku.ToLowerInvariant()).Distinct().ToList();
        var items = await db.InventoryItems
            .Where(i => i.TenantId == booking.TenantId && i.IsActive && skus.Contains(i.Sku.ToLower()))
            .ToListAsync(cancellationToken);
        if (items.Count == 0) return 0;

        var covers = Math.Max(1, booking.AttendeeCount ?? 1);
        var now = DateTime.UtcNow;
        var written = 0;

        foreach (var line in recipe)
        {
            var item = items.FirstOrDefault(i => string.Equals(i.Sku, line.Sku, StringComparison.OrdinalIgnoreCase));
            // An item without a branch cannot carry a movement (BranchId is
            // a required FK), so it is skipped rather than half-recorded.
            if (item == null || !item.BranchId.HasValue) continue;

            var wanted = line.Qty * (line.PerCover ? covers : 1);
            var taken = Math.Min(wanted, Math.Max(0m, item.Quantity));
            var shortfall = wanted - taken;

            item.Quantity -= taken;
            item.UpdatedAt = now;

            db.StockMovements.Add(new StockMovement
            {
                TenantId = booking.TenantId,
                BranchId = item.BranchId.Value,
                InventoryItemId = item.Id,
                MovementType = MovementType,
                Quantity = -wanted,
                UnitCost = item.UnitCost,
                Reference = reference,
                Notes = shortfall > 0
                    ? $"Recipe for {type.Name} ({covers} cover{(covers == 1 ? "" : "s")}). Stock short by {shortfall:0.##} - counted as used."
                    : $"Recipe for {type.Name} ({covers} cover{(covers == 1 ? "" : "s")}).",
                OccurredAt = now,
            });
            written++;
        }

        return written;
    }
}
