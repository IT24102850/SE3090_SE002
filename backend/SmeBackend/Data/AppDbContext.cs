using Microsoft.EntityFrameworkCore;
using SmeBackend.Models;

namespace SmeBackend.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    // Existing DbSets (ADD THESE BACK IF THEY WERE REMOVED)
    public DbSet<Tenant> Tenants { get; set; } = null!;
    public DbSet<TenantModule> TenantModules { get; set; } = null!;
    public DbSet<Branch> Branches { get; set; } = null!;
    public DbSet<User> Users { get; set; } = null!;

    // NEW DbSets for your task
    public DbSet<Resource> Resources { get; set; } = null!;
    public DbSet<BookingType> BookingTypes { get; set; } = null!;
    public DbSet<Booking> Bookings { get; set; } = null!;

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // ==================== RESOURCES ====================
        modelBuilder.Entity<Resource>(entity =>
        {
            entity.ToTable("resources");
            entity.HasQueryFilter(r => r.DeletedAt == null);

            entity.HasIndex(r => new { r.TenantId, r.Category });
            entity.HasIndex(r => new { r.TenantId, r.Status });
            entity.HasIndex(r => new { r.TenantId, r.Name });
            entity.HasIndex(r => r.Code).IsUnique();

            entity.Property(r => r.Status)
                  .HasConversion<string>()
                  .HasMaxLength(20);
            entity.Property(r => r.Category)
                  .HasConversion<string>()
                  .HasMaxLength(20);
            entity.Property(r => r.HourlyRate)
                  .HasPrecision(18, 2);
        });

        // ==================== BOOKING TYPES ====================
        modelBuilder.Entity<BookingType>(entity =>
        {
            entity.ToTable("booking_types");
            entity.HasQueryFilter(bt => bt.DeletedAt == null);

            entity.HasIndex(bt => new { bt.TenantId, bt.Status });
            entity.HasIndex(bt => new { bt.TenantId, bt.Name });
            entity.HasIndex(bt => bt.Slug).IsUnique();

            entity.Property(bt => bt.Status)
                  .HasConversion<string>()
                  .HasMaxLength(20);
            entity.Property(bt => bt.Slug)
                  .HasMaxLength(50);
        });

        // ==================== BOOKINGS ====================
        modelBuilder.Entity<Booking>(entity =>
        {
            entity.ToTable("bookings");
            entity.HasQueryFilter(b => b.DeletedAt == null);

            entity.HasIndex(b => new { b.TenantId, b.StartTime });
            entity.HasIndex(b => new { b.TenantId, b.EndTime });
            entity.HasIndex(b => new { b.TenantId, b.Status });
            entity.HasIndex(b => new { b.TenantId, b.BookedBy });
            entity.HasIndex(b => new { b.TenantId, b.StartTime, b.EndTime });
            entity.HasIndex(b => new { b.ResourceId, b.StartTime, b.EndTime });
            entity.HasIndex(b => new { b.BookingTypeId, b.StartTime });

            entity.Property(b => b.Status)
                  .HasConversion<string>()
                  .HasMaxLength(20);
            entity.Property(b => b.Priority)
                  .HasConversion<string>()
                  .HasMaxLength(20);
            entity.Property(b => b.TotalCost)
                  .HasPrecision(18, 2);

            entity.HasOne(b => b.Resource)
                  .WithMany(r => r.Bookings)
                  .HasForeignKey(b => b.ResourceId)
                  .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(b => b.BookingType)
                  .WithMany(bt => bt.Bookings)
                  .HasForeignKey(b => b.BookingTypeId)
                  .OnDelete(DeleteBehavior.Restrict);
        });
    }
}