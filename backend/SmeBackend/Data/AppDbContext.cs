using Microsoft.EntityFrameworkCore;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
    {
    }

    public DbSet<Tenant> Tenants => Set<Tenant>();
    public DbSet<Branch> Branches => Set<Branch>();
    public DbSet<User> Users => Set<User>();
    public DbSet<AgentWorkflow> AgentWorkflows => Set<AgentWorkflow>();
    public DbSet<Resource> Resources => Set<Resource>();
    public DbSet<AvailabilitySlot> AvailabilitySlots => Set<AvailabilitySlot>();
    public DbSet<Booking> Bookings => Set<Booking>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<TenantModule> TenantModules { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<Tenant>(entity =>
        {
            entity.Property(t => t.Id).HasDefaultValueSql("gen_random_uuid()");
            entity.HasIndex(t => t.Name).IsUnique();

            entity.HasData(new Tenant
            {
                Id = Guid.Parse("11111111-1111-1111-1111-111111111111"),
                Name = "Lumenis",
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            });
        });

        modelBuilder.Entity<Branch>(entity =>
        {
            entity.HasOne(b => b.Tenant)
                .WithMany(t => t.Branches)
                .HasForeignKey(b => b.TenantId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.Property(b => b.Id).HasDefaultValueSql("gen_random_uuid()");
            entity.HasIndex(b => new { b.TenantId, b.Name }).IsUnique();

            entity.HasData(new Branch
            {
                Id = Guid.Parse("22222222-2222-2222-2222-222222222222"),
                TenantId = Guid.Parse("11111111-1111-1111-1111-111111111111"),
                Name = "Colombo Main Branch",
                Address = "123 Galle Road, Colombo 3",
                Phone = "+94112345678",
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            });
        });

        modelBuilder.Entity<User>(entity =>
        {
            entity.HasOne(u => u.Tenant)
                .WithMany(t => t.Users)
                .HasForeignKey(u => u.TenantId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(u => u.Branch)
                .WithMany(b => b.Users)
                .HasForeignKey(u => u.BranchId)
                .OnDelete(DeleteBehavior.SetNull);

            entity.Property(u => u.Id).HasDefaultValueSql("gen_random_uuid()");
            entity.HasIndex(u => u.Email).IsUnique();

            var tenantId = Guid.Parse("11111111-1111-1111-1111-111111111111");
            var branchId = Guid.Parse("22222222-2222-2222-2222-222222222222");

            entity.HasData(
                new User
                {
                    Id = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
                    TenantId = tenantId,
                    BranchId = branchId,
                    Email = "admin@lumenis.com",
                    PasswordHash = BCrypt.Net.BCrypt.HashPassword("Admin@123"),
                    FullName = "System Administrator",
                    Phone = "+94123456789",
                    Role = UserRole.Admin,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow
                },
                new User
                {
                    Id = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
                    TenantId = tenantId,
                    BranchId = branchId,
                    Email = "manager@lumenis.com",
                    PasswordHash = BCrypt.Net.BCrypt.HashPassword("Manager@123"),
                    FullName = "Branch Manager",
                    Phone = "+94123456780",
                    Role = UserRole.Manager,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow
                },
                new User
                {
                    Id = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc"),
                    TenantId = tenantId,
                    BranchId = branchId,
                    Email = "staff@lumenis.com",
                    PasswordHash = BCrypt.Net.BCrypt.HashPassword("Staff@123"),
                    FullName = "Staff Member",
                    Phone = "+94123456781",
                    Role = UserRole.Staff,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow
                },
                new User
                {
                    Id = Guid.Parse("dddddddd-dddd-dddd-dddd-dddddddddddd"),
                    TenantId = tenantId,
                    BranchId = null, // Customers are not tied to a specific branch
                    Email = "customer@lumenis.com",
                    PasswordHash = BCrypt.Net.BCrypt.HashPassword("Customer@123"),
                    FullName = "Test Customer",
                    Phone = "+94123456782",
                    Role = UserRole.Customer,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow
                }
            );
        });

        modelBuilder.Entity<AgentWorkflow>(entity =>
        {
            entity.HasOne(w => w.Tenant)
                .WithMany(t => t.AgentWorkflows)
                .HasForeignKey(w => w.TenantId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(w => w.Branch)
                .WithMany(b => b.AgentWorkflows)
                .HasForeignKey(w => w.BranchId)
                .OnDelete(DeleteBehavior.SetNull);

            entity.HasOne(w => w.CreatedByUser)
                .WithMany()
                .HasForeignKey(w => w.CreatedByUserId)
                .OnDelete(DeleteBehavior.SetNull);

            entity.Property(w => w.Id).HasDefaultValueSql("gen_random_uuid()");
        });

        modelBuilder.Entity<Resource>(entity =>
        {
            entity.HasOne(r => r.Tenant)
                .WithMany(t => t.Resources)
                .HasForeignKey(r => r.TenantId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(r => r.Branch)
                .WithMany(b => b.Resources)
                .HasForeignKey(r => r.BranchId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.Property(r => r.Id).HasDefaultValueSql("gen_random_uuid()");
            entity.HasIndex(r => new { r.BranchId, r.Name }).IsUnique();
        });

        modelBuilder.Entity<AvailabilitySlot>(entity =>
        {
            entity.HasOne(a => a.Resource)
                .WithMany(r => r.AvailabilitySlots)
                .HasForeignKey(a => a.ResourceId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.Property(a => a.Id).HasDefaultValueSql("gen_random_uuid()");
            entity.HasIndex(a => new { a.ResourceId, a.StartTime, a.EndTime });
        });

        modelBuilder.Entity<Booking>(entity =>
        {
            entity.HasOne(b => b.Tenant)
                .WithMany(t => t.Bookings)
                .HasForeignKey(b => b.TenantId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(b => b.Branch)
                .WithMany(branch => branch.Bookings)
                .HasForeignKey(b => b.BranchId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(b => b.Resource)
                .WithMany(r => r.Bookings)
                .HasForeignKey(b => b.ResourceId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(b => b.Customer)
                .WithMany(user => user.Bookings)
                .HasForeignKey(b => b.CustomerId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(b => b.CreatedByUser)
                .WithMany()
                .HasForeignKey(b => b.CreatedByUserId)
                .OnDelete(DeleteBehavior.SetNull);

            entity.Property(b => b.Id).HasDefaultValueSql("gen_random_uuid()");
            entity.HasIndex(b => new { b.ResourceId, b.StartTime, b.EndTime });
        });

        modelBuilder.Entity<RefreshToken>(entity =>
        {
            entity.HasOne(rt => rt.User)
                .WithMany() // No navigation property on User for RefreshTokens
                .HasForeignKey(rt => rt.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.Property(rt => rt.Id).HasDefaultValueSql("gen_random_uuid()");
            entity.HasIndex(rt => rt.Token).IsUnique();
        });

        modelBuilder.Entity<TenantModule>()
            .HasIndex(tm => new { tm.TenantId, tm.ModuleName })
            .IsUnique();
    }
}