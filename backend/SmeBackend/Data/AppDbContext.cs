using Microsoft.EntityFrameworkCore;
using SmeBackend.Models;
using SmeBackend.Tenancy;

namespace SmeBackend.Data;

public class AppDbContext : DbContext
{
    private readonly ITenantContext _tenantContext;

    public AppDbContext(DbContextOptions<AppDbContext> options, ITenantContext tenantContext) : base(options)
    {
        _tenantContext = tenantContext;
    }

    public DbSet<Tenant> Tenants { get; set; }
    public DbSet<Branch> Branches { get; set; }
    public DbSet<User> Users { get; set; }
    public DbSet<InventoryCategory> InventoryCategories { get; set; }
    public DbSet<InventoryUnit> InventoryUnits { get; set; }
    public DbSet<InventoryItem> InventoryItems { get; set; }
    public DbSet<Supplier> Suppliers { get; set; }
    public DbSet<PurchaseOrder> PurchaseOrders { get; set; }
    public DbSet<PurchaseOrderItem> PurchaseOrderItems { get; set; }
    public DbSet<StockMovement> StockMovements { get; set; }
    public DbSet<Notification> Notifications { get; set; }

    private Guid? CurrentTenantId => _tenantContext.TenantId;

    public override int SaveChanges(bool acceptAllChangesOnSuccess)
    {
        AddDefaultInventoryCatalogs();
        ApplyTenantScope();
        return base.SaveChanges(acceptAllChangesOnSuccess);
    }

    public override Task<int> SaveChangesAsync(bool acceptAllChangesOnSuccess, CancellationToken cancellationToken = default)
    {
        AddDefaultInventoryCatalogs();
        ApplyTenantScope();
        return base.SaveChangesAsync(acceptAllChangesOnSuccess, cancellationToken);
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Tenant isolation filter
        modelBuilder.Entity<Tenant>().HasQueryFilter(t => t.IsActive);
        modelBuilder.Entity<Branch>().HasQueryFilter(b => b.IsActive);
        modelBuilder.Entity<User>().HasQueryFilter(u => u.Tenant.IsActive);
        modelBuilder.Entity<InventoryCategory>().HasQueryFilter(c => c.TenantId == CurrentTenantId && c.Tenant.IsActive && c.IsActive);
        modelBuilder.Entity<InventoryUnit>().HasQueryFilter(u => u.TenantId == CurrentTenantId && u.Tenant.IsActive && u.IsActive);
        modelBuilder.Entity<InventoryItem>().HasQueryFilter(item => item.TenantId == CurrentTenantId && item.IsActive);
        modelBuilder.Entity<Supplier>().HasQueryFilter(supplier => supplier.TenantId == CurrentTenantId && supplier.IsActive);
        modelBuilder.Entity<PurchaseOrder>().HasQueryFilter(order => order.TenantId == CurrentTenantId);
        modelBuilder.Entity<StockMovement>().HasQueryFilter(movement => movement.TenantId == CurrentTenantId);
        modelBuilder.Entity<Notification>().HasQueryFilter(notification => notification.TenantId == CurrentTenantId);

        // Indexes
        modelBuilder.Entity<User>().HasIndex(u => u.Email).IsUnique();
        modelBuilder.Entity<Branch>().HasIndex(b => b.TenantId);
        modelBuilder.Entity<InventoryCategory>().HasIndex(c => new { c.TenantId, c.Name }).IsUnique();
        modelBuilder.Entity<InventoryUnit>().HasIndex(u => new { u.TenantId, u.Code }).IsUnique();
        modelBuilder.Entity<InventoryItem>().HasIndex(item => new { item.TenantId, item.Sku }).IsUnique();
        modelBuilder.Entity<Supplier>().HasIndex(supplier => new { supplier.TenantId, supplier.Name }).IsUnique();
        modelBuilder.Entity<PurchaseOrder>().HasIndex(order => new { order.TenantId, order.Number }).IsUnique();
        modelBuilder.Entity<StockMovement>().HasIndex(movement => new { movement.TenantId, movement.BranchId });
        modelBuilder.Entity<StockMovement>().HasIndex(movement => new { movement.InventoryItemId, movement.OccurredAt });
        modelBuilder.Entity<Notification>().HasIndex(notification => new { notification.TenantId, notification.BranchId, notification.IsRead });
        modelBuilder.Entity<Notification>().HasIndex(notification => notification.CreatedAt);

        modelBuilder.Entity<InventoryItem>(entity =>
        {
            entity.Property(item => item.Name).HasMaxLength(150).IsRequired();
            entity.Property(item => item.Sku).HasMaxLength(64).IsRequired();
            entity.Property(item => item.Description).HasMaxLength(2000);
            entity.Property(item => item.Quantity).HasPrecision(18, 3);
            entity.Property(item => item.ReorderLevel).HasPrecision(18, 3);
            entity.Property(item => item.UnitCost).HasPrecision(18, 2);
            entity.HasOne(item => item.Category)
                .WithMany()
                .HasForeignKey(item => item.CategoryId)
                .OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(item => item.Unit)
                .WithMany()
                .HasForeignKey(item => item.UnitId)
                .OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(item => item.Branch)
                .WithMany()
                .HasForeignKey(item => item.BranchId)
                .OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<StockMovement>(entity =>
        {
            entity.Property(movement => movement.MovementType).HasMaxLength(30).IsRequired();
            entity.Property(movement => movement.Quantity).HasPrecision(18, 3);
            entity.Property(movement => movement.UnitCost).HasPrecision(18, 2);
            entity.Property(movement => movement.Reference).HasMaxLength(100);
            entity.Property(movement => movement.Notes).HasMaxLength(2000);
            entity.HasOne<Branch>().WithMany().HasForeignKey(movement => movement.BranchId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne<InventoryItem>().WithMany().HasForeignKey(movement => movement.InventoryItemId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne<Supplier>().WithMany().HasForeignKey(movement => movement.SupplierId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne<PurchaseOrder>().WithMany().HasForeignKey(movement => movement.PurchaseOrderId).OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<Notification>(entity =>
        {
            entity.Property(notification => notification.Type).HasMaxLength(50).IsRequired();
            entity.Property(notification => notification.Title).HasMaxLength(150).IsRequired();
            entity.Property(notification => notification.Message).HasMaxLength(1000).IsRequired();
            entity.HasOne<Branch>().WithMany().HasForeignKey(notification => notification.BranchId).OnDelete(DeleteBehavior.SetNull);
        });

        // Purchase order items
        modelBuilder.Entity<PurchaseOrderItem>(entity =>
        {
            entity.Property(i => i.Quantity).HasPrecision(18, 3);
            entity.Property(i => i.UnitPrice).HasPrecision(18, 2);
            entity.Property(i => i.ReceivedQuantity).HasPrecision(18, 3);
            entity.HasOne<PurchaseOrder>().WithMany(p => p.Items).HasForeignKey(i => i.PurchaseOrderId).OnDelete(DeleteBehavior.Cascade);
            entity.HasIndex(i => i.PurchaseOrderId);
            entity.HasIndex(i => i.InventoryItemId);
        });
    }

    private void AddDefaultInventoryCatalogs()
    {
        var newTenants = ChangeTracker.Entries<Tenant>()
            .Where(entry => entry.State == EntityState.Added)
            .Select(entry => entry.Entity)
            .ToList();

        foreach (var tenant in newTenants)
        {
            DefaultInventoryCatalog.SeedFor(tenant, InventoryCategories.Local, InventoryUnits.Local);
        }
    }

    private void ApplyTenantScope()
    {
        var tenantId = CurrentTenantId;
        foreach (var entry in ChangeTracker.Entries<ITenantScopedEntity>())
        {
            if (entry.State == EntityState.Added)
            {
                if (!tenantId.HasValue)
                {
                    throw new InvalidOperationException("A tenant-scoped entity cannot be created without a tenant context.");
                }

                entry.Entity.TenantId = tenantId.Value;
            }
            else if ((entry.State is EntityState.Modified or EntityState.Deleted) &&
                     (!tenantId.HasValue || entry.Entity.TenantId != tenantId.Value))
            {
                throw new UnauthorizedAccessException("A tenant-scoped entity cannot be modified outside the current tenant.");
            }
        }
    }
}
