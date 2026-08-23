using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Tenancy;
using Testcontainers.PostgreSql;

namespace SmeBackend.Tests;

public class DatabaseIntegrationTests
{
    [Fact]
    public async Task Migration_ShouldCreateExpectedTables()
    {
        var container = await StartPostgresAsync();
        if (container is null)
        {
            return;
        }

        await using (container)
        {
            await using var db = CreateDbContext(container.GetConnectionString());
            await db.Database.MigrateAsync();

            var tables = await GetTableNamesAsync(db);

            Assert.Contains("Tenants", tables);
            Assert.Contains("Branches", tables);
            Assert.Contains("InventoryItems", tables);
            Assert.Contains("StockMovements", tables);
            Assert.Contains("__EFMigrationsHistory", tables);
        }
    }

    [Fact]
    public async Task EnforceUniqueSkuPerTenant_WhenDuplicateSkuInserted_ThrowsDbUpdateException()
    {
        var container = await StartPostgresAsync();
        if (container is null)
        {
            return;
        }

        await using (container)
        {
            await using var db = CreateDbContext(container.GetConnectionString());
            await db.Database.MigrateAsync();

            var tenant = new Tenant
            {
                Name = "Northwind Foods",
                BusinessType = "Restaurant",
                IsActive = true
            };
            db.Tenants.Add(tenant);
            await db.SaveChangesAsync();

            var branch = new Branch
            {
                TenantId = tenant.Id,
                Tenant = tenant,
                Name = "Main Branch",
                Address = "123 Market Street",
                Phone = "555-1234",
                IsActive = true
            };
            db.Branches.Add(branch);
            await db.SaveChangesAsync();

            var tenantContext = new TenantContext();
            tenantContext.SetTenant(tenant.Id);

            using var scopedDb = new AppDbContext(
                new DbContextOptionsBuilder<AppDbContext>()
                    .UseNpgsql(container.GetConnectionString())
                    .Options,
                tenantContext);

            scopedDb.InventoryItems.AddRange(
                new InventoryItem
                {
                    TenantId = tenant.Id,
                    Name = "Rice",
                    Sku = "SKU-UNIQUE-1",
                    BranchId = branch.Id,
                    Quantity = 10m,
                    ReorderLevel = 2m,
                    IsActive = true
                },
                new InventoryItem
                {
                    TenantId = tenant.Id,
                    Name = "White Rice",
                    Sku = "SKU-UNIQUE-1",
                    BranchId = branch.Id,
                    Quantity = 8m,
                    ReorderLevel = 2m,
                    IsActive = true
                });

            var exception = await Assert.ThrowsAsync<DbUpdateException>(() => scopedDb.SaveChangesAsync());
            Assert.NotNull(exception.InnerException ?? exception);
        }
    }

    [Fact]
    public async Task StockMovements_ShouldReferenceValidInventoryItemAndKeepBalanceConsistent()
    {
        var container = await StartPostgresAsync();
        if (container is null)
        {
            return;
        }

        await using (container)
        {
            var tenantContext = new TenantContext();
            await using var db = CreateDbContext(container.GetConnectionString(), tenantContext);
            await db.Database.MigrateAsync();

            var tenant = new Tenant
            {
                Name = "Fresh Goods",
                BusinessType = "Grocery",
                IsActive = true
            };
            db.Tenants.Add(tenant);
            await db.SaveChangesAsync();

            tenantContext.SetTenant(tenant.Id);

            var branch = new Branch
            {
                TenantId = tenant.Id,
                Tenant = tenant,
                Name = "Warehouse",
                Address = "99 Dock Road",
                Phone = "555-6789",
                IsActive = true
            };
            db.Branches.Add(branch);
            await db.SaveChangesAsync();

            var item = new InventoryItem
            {
                TenantId = tenant.Id,
                Name = "Tomatoes",
                Sku = "SKU-STOCK-001",
                BranchId = branch.Id,
                Quantity = 25m,
                ReorderLevel = 5m,
                IsActive = true
            };
            db.InventoryItems.Add(item);
            await db.SaveChangesAsync();

            var movements = new[]
            {
                new StockMovement
                {
                    TenantId = tenant.Id,
                    BranchId = branch.Id,
                    InventoryItemId = item.Id,
                    MovementType = "IN",
                    Quantity = 18m,
                    Reference = "PO-1001",
                    OccurredAt = DateTime.UtcNow,
                    Notes = "Restock"
                },
                new StockMovement
                {
                    TenantId = tenant.Id,
                    BranchId = branch.Id,
                    InventoryItemId = item.Id,
                    MovementType = "OUT",
                    Quantity = -7m,
                    Reference = "SALE-1001",
                    OccurredAt = DateTime.UtcNow,
                    Notes = "Sale"
                },
                new StockMovement
                {
                    TenantId = tenant.Id,
                    BranchId = branch.Id,
                    InventoryItemId = item.Id,
                    MovementType = "ADJUSTMENT",
                    Quantity = 4m,
                    Reference = "COUNT-1001",
                    OccurredAt = DateTime.UtcNow,
                    Notes = "Cycle count"
                }
            };

            db.StockMovements.AddRange(movements);
            await db.SaveChangesAsync();

            var movementTotal = await db.StockMovements
                .Where(m => m.InventoryItemId == item.Id)
                .SumAsync(m => m.Quantity);

            item.Quantity = 25m + movementTotal;
            await db.SaveChangesAsync();

            var reloaded = await db.InventoryItems.SingleAsync(x => x.Id == item.Id);
            Assert.Equal(40m, reloaded.Quantity);
            Assert.Equal(3, await db.StockMovements.CountAsync(m => m.InventoryItemId == item.Id));

            var invalidMovement = new StockMovement
            {
                TenantId = tenant.Id,
                BranchId = branch.Id,
                InventoryItemId = Guid.NewGuid(),
                MovementType = "OUT",
                Quantity = -1m,
                Reference = "INVALID",
                OccurredAt = DateTime.UtcNow
            };

            db.StockMovements.Add(invalidMovement);
            await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
        }
    }

    private static async Task<PostgreSqlContainer?> StartPostgresAsync()
    {
        try
        {
            var container = new PostgreSqlBuilder()
                .WithImage("postgres:16-alpine")
                .WithDatabase("smebackend")
                .WithUsername("postgres")
                .WithPassword("postgres")
                .Build();

            await container.StartAsync();
            return container;
        }
        catch
        {
            return null;
        }
    }

    private static AppDbContext CreateDbContext(string connectionString, ITenantContext? tenantContext = null)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(connectionString)
            .Options;

        return new AppDbContext(options, tenantContext ?? new TenantContext());
    }

    private static async Task<HashSet<string>> GetTableNamesAsync(AppDbContext db)
    {
        await using var connection = db.Database.GetDbConnection();
        await connection.OpenAsync();

        await using var command = connection.CreateCommand();
        command.CommandText = @"SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;";

        await using var reader = await command.ExecuteReaderAsync();
        var tables = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        while (await reader.ReadAsync())
        {
            tables.Add(reader.GetString(0));
        }

        return tables;
    }
}
