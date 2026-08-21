using Microsoft.EntityFrameworkCore;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Data;

public static class DevelopmentUserSeeder
{
    public const string Email = "admin@sme-demo.local";

    public static async Task SeedAsync(AppDbContext db, ITenantContext tenantContext)
    {
        var existingAdmin = await db.Users.IgnoreQueryFilters()
            .SingleOrDefaultAsync(user => user.Email == Email);

        if (existingAdmin is null)
        {
            var tenant = new Tenant
            {
                Name = "SME Demo Store",
                BusinessType = "Retail",
            };
            tenantContext.SetTenantId(tenant.Id);

            var branch = new Branch
            {
                Tenant = tenant,
                Name = "Main Branch",
                Address = "Colombo",
                Phone = "+94 11 000 0000",
            };
            var user = new User
            {
                Tenant = tenant,
                Branch = branch,
                Email = Email,
                FullName = "Demo Administrator",
                Phone = "+94 77 000 0000",
                Role = UserRole.Admin,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword("Demo@12345"),
            };

            db.Users.Add(user);
            await db.SaveChangesAsync();
        }
        else
        {
            // Ensure the query filters are scoped to the demo tenant on restarts.
            tenantContext.SetTenantId(existingAdmin.TenantId);
        }

        await SeedDemoInventoryIfEmptyAsync(db);
    }

    private static async Task SeedDemoInventoryIfEmptyAsync(AppDbContext db)
    {
        // Inventory query filters scope to the current tenant, which was set above.
        if (await db.InventoryItems.AnyAsync()) return;

        var branch = await db.Branches.FirstOrDefaultAsync();
        var categories = await db.InventoryCategories.ToListAsync();
        var units = await db.InventoryUnits.ToListAsync();
        if (branch is null || categories.Count == 0 || units.Count == 0) return;

        var beverage = categories.First(category => category.Name == "Beverages").Id;
        var household = categories.First(category => category.Name == "Household").Id;
        var snacks = categories.First(category => category.Name == "Snacks").Id;
        var merchandize = categories.First(category => category.Name == "General Merchandise").Id;

        var kg = units.First(unit => unit.Code == "kg").Id;
        var ml = units.First(unit => unit.Code == "ml").Id;
        var pack = units.First(unit => unit.Code == "pack").Id;
        var bag = units.First(unit => unit.Code == "each").Id;
        var carton = units.First(unit => unit.Code == "each").Id;
        var box = units.First(unit => unit.Code == "box").Id;

        var items = new[]
        {
            ("SKU-00128", "Colombia Supremo Beans 1kg", "Whole-bean coffee, medium roast.", beverage, kg, 142m, 40m, 3400m),
            ("SKU-00132", "Premium Coffee Beans", "Single origin, 500g.", beverage, kg, 6m, 40m, 4200m),
            ("SKU-00324", "Vanilla Syrup 750ml", "Barista syrup for drinks.", beverage, ml, 0m, 25m, 1250m),
            ("SKU-00451", "Butter Croissants (x12)", "Fresh-baked case.", snacks, pack, 96m, 30m, 1800m),
            ("SKU-00598", "Packaging Boxes — Medium", "Kraft takeaway boxes.", household, box, 11m, 60m, 420m),
            ("SKU-00612", "Craft Paper Cups 12oz (x50)", "Compostable hot cups.", household, pack, 74m, 40m, 820m),
            ("SKU-00741", "Whole Milk 1L", "Chilled whole milk.", beverage, carton, 218m, 80m, 290m),
            ("SKU-00811", "Whole Milk 1L (Small)", "Chilled whole milk, small pack.", beverage, carton, 18m, 80m, 260m),
            ("SKU-00902", "Brown Sugar 500g", "For coffee and baking.", snacks, bag, 65m, 30m, 460m),
            ("SKU-01033", "Napkins — Kraft (x200)", "Restaurant napkins.", merchandize, pack, 43m, 25m, 680m),
        };

        foreach (var (sku, name, description, categoryId, unitId, quantity, reorderLevel, unitCost) in items)
        {
            db.InventoryItems.Add(new InventoryItem
            {
                Name = name,
                Sku = sku,
                Description = description,
                CategoryId = categoryId,
                UnitId = unitId,
                BranchId = branch.Id,
                Quantity = quantity,
                ReorderLevel = reorderLevel,
                UnitCost = unitCost,
            });
        }

        await db.SaveChangesAsync();
    }
}
