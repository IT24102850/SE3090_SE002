using SmeBackend.Models;

namespace SmeBackend.Data;

internal static class DefaultInventoryCatalog
{
    private static readonly (string Code, string Name)[] DefaultUnits =
    [
        ("each", "Each"),
        ("box", "Box"),
        ("pack", "Pack"),
        ("kg", "Kilogram"),
        ("g", "Gram"),
        ("l", "Litre"),
        ("ml", "Millilitre")
    ];

    public static void SeedFor(Tenant tenant, ICollection<InventoryCategory> categories, ICollection<InventoryUnit> units)
    {
        foreach (var category in CategoriesFor(tenant.BusinessType))
        {
            categories.Add(new InventoryCategory { TenantId = tenant.Id, Name = category });
        }

        foreach (var (code, name) in DefaultUnits)
        {
            units.Add(new InventoryUnit { TenantId = tenant.Id, Code = code, Name = name });
        }
    }

    private static string[] CategoriesFor(string businessType) => businessType.Trim().ToLowerInvariant() switch
    {
        "restaurant" or "cafe" or "bakery" => ["Ingredients", "Beverages", "Packaging", "Cleaning Supplies"],
        "clinic" or "pharmacy" => ["Medical Supplies", "Pharmaceuticals", "PPE", "Office Supplies"],
        "gym" or "fitness" => ["Supplements", "Beverages", "Cleaning Supplies", "Equipment"],
        "retail" or "store" => ["General Merchandise", "Beverages", "Snacks", "Household"],
        _ => ["General", "Supplies", "Equipment", "Other"]
    };
}
