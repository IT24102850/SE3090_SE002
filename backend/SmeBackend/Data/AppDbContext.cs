using Microsoft.EntityFrameworkCore;
using SmeBackend.Models;

namespace SmeBackend.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<Tenant> Tenants { get; set; }
    public DbSet<Branch> Branches { get; set; }
    public DbSet<User> Users { get; set; }
    public DbSet<Supplier> Suppliers { get; set; }
    public DbSet<InventoryItem> InventoryItems { get; set; }
    public DbSet<PurchaseOrder> PurchaseOrders { get; set; }
    public DbSet<StockMovement> StockMovements { get; set; }
    public DbSet<PurchaseOrderItem> PurchaseOrderItems { get; set; }
    public DbSet<EquipmentMaintenance> EquipmentMaintenanceRecords { get; set; }
    public DbSet<AnalyticsSnapshot> AnalyticsSnapshots { get; set; }
    public DbSet<Notification> Notifications { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Tenant isolation filter
        modelBuilder.Entity<Tenant>().HasQueryFilter(t => t.IsActive);
        modelBuilder.Entity<Branch>().HasQueryFilter(b => b.IsActive);
        modelBuilder.Entity<User>().HasQueryFilter(u => u.Tenant.IsActive);
        modelBuilder.Entity<Supplier>().HasQueryFilter(s => s.Tenant.IsActive && s.IsActive);
        modelBuilder.Entity<InventoryItem>().HasQueryFilter(i => i.Tenant.IsActive && i.IsActive);
        modelBuilder.Entity<PurchaseOrder>().HasQueryFilter(p => p.Tenant.IsActive);
        modelBuilder.Entity<StockMovement>().HasQueryFilter(m => m.Tenant.IsActive);
        modelBuilder.Entity<EquipmentMaintenance>().HasQueryFilter(m => m.Tenant.IsActive);
        modelBuilder.Entity<PurchaseOrderItem>().HasQueryFilter(i =>
            i.PurchaseOrder.Tenant.IsActive && i.InventoryItem.Tenant.IsActive && i.InventoryItem.IsActive);
        modelBuilder.Entity<AnalyticsSnapshot>().HasQueryFilter(s => s.Tenant.IsActive);
        modelBuilder.Entity<Notification>().HasQueryFilter(n => n.Tenant.IsActive);

        // Indexes
        modelBuilder.Entity<User>().HasIndex(u => u.Email).IsUnique();
        modelBuilder.Entity<Branch>().HasIndex(b => b.TenantId);

        modelBuilder.Entity<Supplier>(entity =>
        {
            entity.Property(s => s.Name).HasMaxLength(200).IsRequired();
            entity.Property(s => s.ContactPerson).HasMaxLength(150);
            entity.Property(s => s.Email).HasMaxLength(320);
            entity.Property(s => s.Phone).HasMaxLength(50);
            entity.Property(s => s.Address).HasMaxLength(500);
            entity.HasIndex(s => new { s.TenantId, s.BranchId });
            entity.HasOne(s => s.Tenant).WithMany().HasForeignKey(s => s.TenantId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(s => s.Branch).WithMany().HasForeignKey(s => s.BranchId).OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<InventoryItem>(entity =>
        {
            entity.Property(i => i.Sku).HasMaxLength(100).IsRequired();
            entity.Property(i => i.Name).HasMaxLength(200).IsRequired();
            entity.Property(i => i.Description).HasMaxLength(2000);
            entity.Property(i => i.QuantityOnHand).HasPrecision(18, 3);
            entity.Property(i => i.ReorderLevel).HasPrecision(18, 3);
            entity.Property(i => i.UnitCost).HasPrecision(18, 2);
            entity.HasIndex(i => new { i.TenantId, i.BranchId });
            entity.HasIndex(i => new { i.TenantId, i.Sku }).IsUnique();
            entity.HasOne(i => i.Tenant).WithMany().HasForeignKey(i => i.TenantId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(i => i.Branch).WithMany().HasForeignKey(i => i.BranchId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(i => i.Supplier).WithMany(s => s.InventoryItems).HasForeignKey(i => i.SupplierId).OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<PurchaseOrder>(entity =>
        {
            entity.Property(p => p.OrderNumber).HasMaxLength(100).IsRequired();
            entity.Property(p => p.Status).HasMaxLength(30).IsRequired();
            entity.Property(p => p.TotalAmount).HasPrecision(18, 2);
            entity.Property(p => p.Notes).HasMaxLength(2000);
            entity.HasIndex(p => new { p.TenantId, p.BranchId });
            entity.HasIndex(p => new { p.TenantId, p.OrderNumber }).IsUnique();
            entity.HasOne(p => p.Tenant).WithMany().HasForeignKey(p => p.TenantId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(p => p.Branch).WithMany().HasForeignKey(p => p.BranchId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(p => p.Supplier).WithMany(s => s.PurchaseOrders).HasForeignKey(p => p.SupplierId).OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<StockMovement>(entity =>
        {
            entity.Property(m => m.MovementType).HasMaxLength(30).IsRequired();
            entity.Property(m => m.Quantity).HasPrecision(18, 3);
            entity.Property(m => m.UnitCost).HasPrecision(18, 2);
            entity.Property(m => m.Reference).HasMaxLength(100);
            entity.Property(m => m.Notes).HasMaxLength(2000);
            entity.HasIndex(m => new { m.TenantId, m.BranchId });
            entity.HasIndex(m => new { m.InventoryItemId, m.OccurredAt });
            entity.HasOne(m => m.Tenant).WithMany().HasForeignKey(m => m.TenantId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(m => m.Branch).WithMany().HasForeignKey(m => m.BranchId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(m => m.InventoryItem).WithMany(i => i.StockMovements).HasForeignKey(m => m.InventoryItemId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(m => m.Supplier).WithMany(s => s.StockMovements).HasForeignKey(m => m.SupplierId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(m => m.PurchaseOrder).WithMany(p => p.StockMovements).HasForeignKey(m => m.PurchaseOrderId).OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<PurchaseOrderItem>(entity =>
        {
            entity.Property(i => i.OrderedQuantity).HasPrecision(18, 3);
            entity.Property(i => i.ReceivedQuantity).HasPrecision(18, 3);
            entity.Property(i => i.UnitCost).HasPrecision(18, 2);
            entity.Property(i => i.Notes).HasMaxLength(2000);
            entity.HasIndex(i => new { i.PurchaseOrderId, i.InventoryItemId }).IsUnique();
            entity.HasOne(i => i.PurchaseOrder).WithMany(p => p.Items).HasForeignKey(i => i.PurchaseOrderId).OnDelete(DeleteBehavior.Cascade);
            entity.HasOne(i => i.InventoryItem).WithMany(i => i.PurchaseOrderItems).HasForeignKey(i => i.InventoryItemId).OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<EquipmentMaintenance>(entity =>
        {
            entity.Property(m => m.MaintenanceType).HasMaxLength(100).IsRequired();
            entity.Property(m => m.Status).HasMaxLength(30).IsRequired();
            entity.Property(m => m.Cost).HasPrecision(18, 2);
            entity.Property(m => m.PerformedBy).HasMaxLength(200);
            entity.Property(m => m.Notes).HasMaxLength(2000);
            entity.HasIndex(m => new { m.TenantId, m.BranchId });
            entity.HasIndex(m => new { m.InventoryItemId, m.ScheduledFor });
            entity.HasOne(m => m.Tenant).WithMany().HasForeignKey(m => m.TenantId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(m => m.Branch).WithMany().HasForeignKey(m => m.BranchId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(m => m.InventoryItem).WithMany(i => i.MaintenanceRecords).HasForeignKey(m => m.InventoryItemId).OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<AnalyticsSnapshot>(entity =>
        {
            entity.Property(s => s.SnapshotType).HasMaxLength(100).IsRequired();
            entity.Property(s => s.Data).HasColumnType("jsonb").IsRequired();
            entity.HasIndex(s => new { s.TenantId, s.BranchId, s.SnapshotType, s.PeriodStart });
            entity.HasOne(s => s.Tenant).WithMany().HasForeignKey(s => s.TenantId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(s => s.Branch).WithMany().HasForeignKey(s => s.BranchId).OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<Notification>(entity =>
        {
            entity.Property(n => n.Type).HasMaxLength(50).IsRequired();
            entity.Property(n => n.Title).HasMaxLength(200).IsRequired();
            entity.Property(n => n.Message).HasMaxLength(2000).IsRequired();
            entity.Property(n => n.ActionUrl).HasMaxLength(2000);
            entity.HasIndex(n => new { n.TenantId, n.UserId, n.IsRead, n.CreatedAt });
            entity.HasIndex(n => new { n.TenantId, n.BranchId });
            entity.HasOne(n => n.Tenant).WithMany().HasForeignKey(n => n.TenantId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(n => n.Branch).WithMany().HasForeignKey(n => n.BranchId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(n => n.User).WithMany().HasForeignKey(n => n.UserId).OnDelete(DeleteBehavior.SetNull);
        });
    }
}
