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

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Tenant isolation filter
        modelBuilder.Entity<Tenant>().HasQueryFilter(t => t.IsActive);
        modelBuilder.Entity<Branch>().HasQueryFilter(b => b.IsActive);
        modelBuilder.Entity<User>().HasQueryFilter(u => u.Tenant.IsActive);
        modelBuilder.Entity<Supplier>().HasQueryFilter(s => s.Tenant.IsActive && s.IsActive);
        modelBuilder.Entity<InventoryItem>().HasQueryFilter(i => i.Tenant.IsActive && i.IsActive);

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
    }
}
