using Microsoft.EntityFrameworkCore;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Data;

public static class DevelopmentUserSeeder
{
    public const string Email = "admin@sme-demo.local";
    private static readonly (string Email, string FullName, string Password, string Phone, UserRole Role)[] DemoUsers =
    {
        (Email, "Demo Administrator", "Demo@12345", "+94 77 000 0000", UserRole.Admin),
        ("manager@sme-demo.local", "Demo Manager", "Manager@12345", "+94 77 000 0001", UserRole.Manager),
        ("staff@sme-demo.local", "Demo Staff", "Staff@12345", "+94 77 000 0002", UserRole.Staff),
        ("customer@sme-demo.local", "Demo Customer", "Customer@12345", "+94 77 000 0003", UserRole.Customer),
    };

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
            db.Tenants.Add(tenant);
            db.Branches.Add(branch);
            db.Users.Add(new User
            {
                Tenant = tenant,
                Branch = branch,
                Email = Email,
                FullName = "Demo Administrator",
                Phone = "+94 77 000 0000",
                Role = UserRole.Admin,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword("Demo@12345"),
                IsApproved = true,
            });
            await db.SaveChangesAsync();
        }
        else
        {
            // Ensure the query filters are scoped to the demo tenant on restarts.
            tenantContext.SetTenantId(existingAdmin.TenantId);
        }

        await SeedDemoUsersAsync(db, tenantContext);
        await SeedDemoResourcesAsync(db, tenantContext);
        await SeedDemoInventoryIfEmptyAsync(db);
        await SeedSriLankanPurchaseOrdersIfEmptyAsync(db, tenantContext);
    }

    private static async Task SeedDemoUsersAsync(AppDbContext db, ITenantContext tenantContext)
    {
        var admin = await db.Users.IgnoreQueryFilters()
            .SingleAsync(user => user.Email == Email);

        // Re-apply the seed tenant after the unfiltered lookup. This keeps the
        // subsequent updates inside the DbContext tenant guard on reused local
        // databases as well as first-run databases.
        tenantContext.SetTenantId(admin.TenantId);
        var branchId = admin.BranchId;

        foreach (var demoUser in DemoUsers)
        {
            var existingUser = await db.Users.IgnoreQueryFilters()
                .SingleOrDefaultAsync(user => user.Email == demoUser.Email);
            if (existingUser is not null)
            {
                // A reused database can contain an identically named sample
                // account from another tenant. Never change that tenant's user
                // while seeding the local demo workspace.
                if (existingUser.TenantId != admin.TenantId)
                {
                    continue;
                }

                // Keep documented development credentials usable after a database
                // is reused from an earlier local run.
                existingUser.PasswordHash = BCrypt.Net.BCrypt.HashPassword(demoUser.Password);
                existingUser.Role = demoUser.Role;
                existingUser.IsApproved = true;
                continue;
            }

            db.Users.Add(new User
            {
                TenantId = admin.TenantId,
                BranchId = branchId,
                Email = demoUser.Email,
                FullName = demoUser.FullName,
                Phone = demoUser.Phone,
                Role = demoUser.Role,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(demoUser.Password),
                IsApproved = true,
            });
        }

        await db.SaveChangesAsync();
    }

    private static async Task SeedDemoResourcesAsync(AppDbContext db, ITenantContext tenantContext)
    {
        var admin = await db.Users.IgnoreQueryFilters().SingleAsync(user => user.Email == Email);
        tenantContext.SetTenantId(admin.TenantId);
        var branch = await db.Branches.FirstOrDefaultAsync();
        if (branch is null) return;

        var staff = await db.Users.FirstOrDefaultAsync(user => user.Role == UserRole.Staff);
        var resourceDefinitions = new[]
        {
            new
            {
                Name = "Consultation Room 1",
                Code = "ROOM-01",
                Category = ResourceCategory.Room,
                Description = "Private consultation room at Main Branch.",
                Specialty = (string?)null,
                Capacity = (int?)2,
                HourlyRate = (decimal?)3500m,
                LinkedUserId = (Guid?)null,
            },
            new
            {
                Name = "Consultation Room 2",
                Code = "ROOM-02",
                Category = ResourceCategory.Room,
                Description = "Second private consultation room at Main Branch.",
                Specialty = (string?)null,
                Capacity = (int?)2,
                HourlyRate = (decimal?)3500m,
                LinkedUserId = (Guid?)null,
            },
            new
            {
                Name = "Demo Staff Consultant",
                Code = "STAFF-01",
                Category = ResourceCategory.Staff,
                Description = "Demo staff resource for testing AI-assisted bookings.",
                Specialty = (string?)"General Consultation",
                Capacity = (int?)1,
                HourlyRate = (decimal?)2500m,
                LinkedUserId = staff?.Id,
            },
        };

        foreach (var definition in resourceDefinitions)
        {
            var resource = await db.Resources.FirstOrDefaultAsync(item =>
                item.TenantId == admin.TenantId && item.Code == definition.Code);

            if (resource is null)
            {
                resource = new Resource
                {
                    TenantId = admin.TenantId,
                    BranchId = branch.Id,
                    Name = definition.Name,
                    Code = definition.Code,
                    Category = definition.Category,
                    Status = ResourceStatus.Available,
                    Description = definition.Description,
                    Specialty = definition.Specialty,
                    Capacity = definition.Capacity,
                    HourlyRate = definition.HourlyRate,
                    LinkedUserId = definition.LinkedUserId,
                };
                db.Resources.Add(resource);
            }
            else
            {
                resource.Status = ResourceStatus.Available;
                resource.BranchId = branch.Id;
                resource.LinkedUserId = definition.LinkedUserId;
            }

            var schedules = await db.ResourceSchedules
                .Where(schedule => schedule.ResourceId == resource.Id)
                .ToListAsync();
            if (schedules.Count == 0)
            {
                for (var day = 1; day <= 6; day++)
                {
                    db.ResourceSchedules.Add(new ResourceSchedule
                    {
                        Resource = resource,
                        DayOfWeek = day,
                        StartTime = new TimeSpan(9, 0, 0),
                        EndTime = new TimeSpan(17, 0, 0),
                        IsAvailable = true,
                        LunchBreakStart = new TimeSpan(13, 0, 0),
                        LunchBreakEnd = new TimeSpan(14, 0, 0),
                        MaxDailyBookedHours = 8m,
                    });
                }
            }
        }

        await db.SaveChangesAsync();
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

    // Supplier identities and contact details below are taken from the companies'
    // public websites. Quantities, prices, and purchase orders are deliberately
    // synthetic Sri Lankan demo operations data; they are not records of either
    // company and must be replaced with a tenant's own transactions in production.
    private static async Task SeedSriLankanPurchaseOrdersIfEmptyAsync(AppDbContext db, ITenantContext tenantContext)
    {
        if (await db.PurchaseOrders.AnyAsync()) return;

        var admin = await db.Users.IgnoreQueryFilters().SingleAsync(user => user.Email == Email);
        tenantContext.SetTenantId(admin.TenantId);
        var branch = await db.Branches.FirstOrDefaultAsync();
        if (branch is null) return;

        var suppliers = new[]
        {
            new Supplier
            {
                TenantId = admin.TenantId,
                Name = "Ceylon Biscuits Limited",
                Email = "inquiry.cbl@cbllk.com",
                Phone = "+94 11 500 0000",
            },
            new Supplier
            {
                TenantId = admin.TenantId,
                Name = "Keells Food Products PLC",
                Email = "foods@keells.com",
                Phone = "+94 11 223 6317",
            },
        };

        foreach (var supplier in suppliers)
        {
            if (!await db.Suppliers.IgnoreQueryFilters().AnyAsync(existing =>
                    existing.TenantId == admin.TenantId && existing.Name == supplier.Name))
            {
                db.Suppliers.Add(supplier);
            }
        }
        await db.SaveChangesAsync();

        var cbl = await db.Suppliers.SingleAsync(supplier => supplier.Name == "Ceylon Biscuits Limited");
        var keells = await db.Suppliers.SingleAsync(supplier => supplier.Name == "Keells Food Products PLC");
        var items = await db.InventoryItems.ToDictionaryAsync(item => item.Sku);
        if (!items.TryGetValue("SKU-00451", out var biscuits) ||
            !items.TryGetValue("SKU-00902", out var sugar) ||
            !items.TryGetValue("SKU-00741", out var milk)) return;

        var now = DateTime.UtcNow;
        var cblOrder = new PurchaseOrder
        {
            TenantId = admin.TenantId,
            BranchId = branch.Id,
            SupplierId = cbl.Id,
            Number = "PO-LK-0001",
            Status = "Received",
            CreatedAt = now.AddDays(-12),
            UpdatedAt = now.AddDays(-8),
        };
        var keellsOrder = new PurchaseOrder
        {
            TenantId = admin.TenantId,
            BranchId = branch.Id,
            SupplierId = keells.Id,
            Number = "PO-LK-0002",
            Status = "InTransit",
            CreatedAt = now.AddDays(-4),
            UpdatedAt = now.AddHours(-10),
        };
        db.PurchaseOrders.AddRange(cblOrder, keellsOrder);
        db.PurchaseOrderItems.AddRange(
            new PurchaseOrderItem { TenantId = admin.TenantId, PurchaseOrderId = cblOrder.Id, InventoryItemId = biscuits.Id, Description = "Butter Croissants (x12)", Quantity = 24m, UnitPrice = 1800m, ReceivedQuantity = 24m },
            new PurchaseOrderItem { TenantId = admin.TenantId, PurchaseOrderId = cblOrder.Id, InventoryItemId = sugar.Id, Description = "Brown Sugar 500g", Quantity = 40m, UnitPrice = 460m, ReceivedQuantity = 40m },
            new PurchaseOrderItem { TenantId = admin.TenantId, PurchaseOrderId = keellsOrder.Id, InventoryItemId = milk.Id, Description = "Whole Milk 1L", Quantity = 60m, UnitPrice = 290m, ReceivedQuantity = 0m });
        await db.SaveChangesAsync();
    }
}
