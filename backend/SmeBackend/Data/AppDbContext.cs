using Microsoft.EntityFrameworkCore;
using SmeBackend.Models;

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

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<Tenant>(entity =>
        {
            entity.Property(t => t.Id).HasDefaultValueSql("gen_random_uuid()");
            entity.HasIndex(t => t.Name).IsUnique();
        });

        modelBuilder.Entity<Branch>(entity =>
        {
            entity.HasOne(b => b.Tenant)
                .WithMany(t => t.Branches)
                .HasForeignKey(b => b.TenantId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.Property(b => b.Id).HasDefaultValueSql("gen_random_uuid()");
            entity.HasIndex(b => new { b.TenantId, b.Name }).IsUnique();
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
    }
}