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
    public DbSet<ResourceSchedule> ResourceSchedules { get; set; } = null!;
    public DbSet<AvailabilitySlot> AvailabilitySlots { get; set; } = null!;
    public DbSet<BookingReminder> BookingReminders { get; set; } = null!;
    public DbSet<RecurringPattern> RecurringPatterns { get; set; } = null!;
    public DbSet<AgentWorkflow> AgentWorkflows { get; set; } = null!;
    public DbSet<Resource> Resources { get; set; } = null!;
    public DbSet<BookingType> BookingTypes { get; set; } = null!;
    public DbSet<Booking> Bookings { get; set; } = null!;
    public DbSet<ResourceScheduleException> ResourceScheduleExceptions { get; set; } = null!;
    public DbSet<Notification> Notifications { get; set; } = null!;
    public DbSet<DeviceToken> DeviceTokens { get; set; } = null!;
    public DbSet<InventoryItem> InventoryItems { get; set; } = null!;
    public DbSet<EquipmentReservation> EquipmentReservations { get; set; } = null!;

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
            entity.HasIndex(r => new { r.TenantId, r.BranchId });
            entity.HasIndex(r => r.Code).IsUnique();

            entity.Property(r => r.Status)
                  .HasConversion<string>()
                  .HasMaxLength(20);
            entity.Property(r => r.Category)
                  .HasConversion<string>()
                  .HasMaxLength(20);
            entity.Property(r => r.HourlyRate)
                  .HasPrecision(18, 2);

            entity.HasOne(r => r.Branch)
                  .WithMany()
                  .HasForeignKey(r => r.BranchId)
                  .OnDelete(DeleteBehavior.SetNull);
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

        // ==================== RESOURCE SCHEDULES ====================
        modelBuilder.Entity<ResourceSchedule>(entity =>
        {
            entity.ToTable("resource_schedules");

            entity.HasIndex(rs => new { rs.ResourceId, rs.DayOfWeek });

            entity.HasOne(rs => rs.Resource)
                  .WithMany()
                  .HasForeignKey(rs => rs.ResourceId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // ==================== AVAILABILITY SLOTS ====================
        modelBuilder.Entity<AvailabilitySlot>(entity =>
        {
            entity.ToTable("availability_slots");

            entity.HasIndex(a => new { a.ResourceId, a.Date });
            entity.HasIndex(a => new { a.ResourceId, a.Date, a.StartTime, a.EndTime }).IsUnique();
            entity.HasIndex(a => a.BookingId);

            entity.HasOne(a => a.Resource)
                  .WithMany()
                  .HasForeignKey(a => a.ResourceId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // ==================== BOOKING REMINDERS ====================
        modelBuilder.Entity<BookingReminder>(entity =>
        {
            entity.ToTable("booking_reminders");

            entity.HasIndex(r => r.BookingId);
            entity.HasIndex(r => r.Status);

            entity.Property(r => r.Channel).HasMaxLength(20);
            entity.Property(r => r.Status).HasMaxLength(20);

            entity.HasOne(r => r.Booking)
                  .WithMany()
                  .HasForeignKey(r => r.BookingId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // ==================== RECURRING PATTERNS ====================
        modelBuilder.Entity<RecurringPattern>(entity =>
        {
            entity.ToTable("recurring_patterns");

            entity.HasIndex(p => p.BookingId);

            entity.Property(p => p.Frequency).HasMaxLength(20);

            entity.HasOne(p => p.Booking)
                  .WithMany()
                  .HasForeignKey(p => p.BookingId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // ==================== AGENT WORKFLOWS ====================
        modelBuilder.Entity<AgentWorkflow>(entity =>
        {
            entity.ToTable("agent_workflows");

            entity.HasIndex(w => new { w.TenantId, w.Status });
            entity.HasIndex(w => w.CreatedAt);

            entity.Property(w => w.Status).HasMaxLength(30);
            entity.Property(w => w.ApprovalStatus).HasMaxLength(30);
        });

        // ==================== RESOURCE SCHEDULE EXCEPTIONS ====================
        modelBuilder.Entity<ResourceScheduleException>(entity =>
        {
            entity.ToTable("resource_schedule_exceptions");

            entity.HasIndex(e => new { e.ResourceId, e.Date }).IsUnique();

            entity.HasOne(e => e.Resource)
                  .WithMany()
                  .HasForeignKey(e => e.ResourceId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // ==================== NOTIFICATIONS ====================
        modelBuilder.Entity<Notification>(entity =>
        {
            entity.ToTable("notifications");

            entity.HasIndex(n => new { n.TenantId, n.UserId, n.IsRead });
            entity.HasIndex(n => n.CreatedAt);

            entity.Property(n => n.Type).HasMaxLength(40);
        });

        // ==================== DEVICE TOKENS ====================
        modelBuilder.Entity<DeviceToken>(entity =>
        {
            entity.ToTable("device_tokens");

            entity.HasIndex(t => t.Token).IsUnique();
            entity.HasIndex(t => new { t.TenantId, t.UserId });

            entity.Property(t => t.Token).HasMaxLength(500);
            entity.Property(t => t.Platform).HasMaxLength(20);
        });

        // InventoryItem itself is intentionally left unconfigured here - it's
        // Student 3's pre-existing model/table from InitialCreate (default
        // PascalCase "InventoryItems" naming), and this Inventory placeholder
        // only reads/writes it, not re-shapes it.

        // ==================== EQUIPMENT RESERVATIONS ====================
        modelBuilder.Entity<EquipmentReservation>(entity =>
        {
            entity.ToTable("equipment_reservations");

            entity.HasIndex(r => r.BookingId);
            entity.HasIndex(r => r.InventoryItemId);

            entity.Property(r => r.Quantity).HasPrecision(18, 2);

            entity.HasOne(r => r.Booking)
                  .WithMany()
                  .HasForeignKey(r => r.BookingId)
                  .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(r => r.InventoryItem)
                  .WithMany()
                  .HasForeignKey(r => r.InventoryItemId)
                  .OnDelete(DeleteBehavior.Restrict);
        });
    }
}