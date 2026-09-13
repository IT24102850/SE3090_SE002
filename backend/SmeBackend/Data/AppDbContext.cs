using Microsoft.EntityFrameworkCore;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Data;

public class AppDbContext : DbContext
{
    private readonly ITenantContext _tenantContext;

    public AppDbContext(DbContextOptions<AppDbContext> options, ITenantContext tenantContext) : base(options)
    {
        _tenantContext = tenantContext;
    }

    // Core / shared
    public DbSet<Tenant> Tenants { get; set; } = null!;
    public DbSet<TenantModule> TenantModules { get; set; } = null!;
    public DbSet<Branch> Branches { get; set; } = null!;
    public DbSet<User> Users { get; set; } = null!;

    // Booking engine
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

    // Fixed-departure excursion ops (whale watching, safari jeeps, ...) -
    // archetype A in docs/tourism-business-template.md. Only tenants whose
    // SubType selects a departure-board dashboard write to these.
    public DbSet<Departure> Departures { get; set; } = null!;
    public DbSet<SightingsLog> SightingsLogs { get; set; } = null!;
    public DbSet<WeatherObservation> WeatherObservations { get; set; } = null!;

    // Equipment reserved as part of a booking (dive tanks, wheelchairs, ...) -
    // distinct from the full Inventory module below; see EquipmentItem.cs.
    public DbSet<EquipmentItem> EquipmentItems { get; set; } = null!;
    public DbSet<EquipmentReservation> EquipmentReservations { get; set; } = null!;
    public DbSet<EquipmentMaintenance> EquipmentMaintenances { get; set; } = null!;

    // Inventory module
    public DbSet<InventoryCategory> InventoryCategories { get; set; } = null!;
    public DbSet<InventoryUnit> InventoryUnits { get; set; } = null!;
    public DbSet<InventoryItem> InventoryItems { get; set; } = null!;
    public DbSet<Supplier> Suppliers { get; set; } = null!;
    public DbSet<PurchaseOrder> PurchaseOrders { get; set; } = null!;
    public DbSet<PurchaseOrderItem> PurchaseOrderItems { get; set; } = null!;
    public DbSet<StockMovement> StockMovements { get; set; } = null!;
    public DbSet<Sale> Sales { get; set; } = null!;

    private Guid? CurrentTenantId => _tenantContext.CurrentTenantId;

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
            entity.HasIndex(b => b.DepartureId);

            entity.Property(b => b.Source).HasMaxLength(50);

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

            // SetNull, not Cascade: deleting a departure must never delete
            // the guests' reservations - the weather-cancel flow relies on
            // those bookings surviving so they can be rescheduled.
            entity.HasOne<Departure>()
                  .WithMany()
                  .HasForeignKey(b => b.DepartureId)
                  .OnDelete(DeleteBehavior.SetNull);
        });

        // ==================== DEPARTURES ====================
        modelBuilder.Entity<Departure>(entity =>
        {
            entity.ToTable("departures");
            entity.HasQueryFilter(d => d.DeletedAt == null);

            entity.HasIndex(d => new { d.TenantId, d.ScheduledDeparture });
            entity.HasIndex(d => new { d.TenantId, d.Status });
            entity.HasIndex(d => new { d.ResourceId, d.ScheduledDeparture }).IsUnique();

            entity.Property(d => d.Status)
                  .HasConversion<string>()
                  .HasMaxLength(20);

            entity.HasOne(d => d.Resource)
                  .WithMany()
                  .HasForeignKey(d => d.ResourceId)
                  .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(d => d.BookingType)
                  .WithMany()
                  .HasForeignKey(d => d.BookingTypeId)
                  .OnDelete(DeleteBehavior.SetNull);
        });

        // ==================== SIGHTINGS LOG ====================
        modelBuilder.Entity<SightingsLog>(entity =>
        {
            entity.ToTable("sightings_logs");
            entity.HasQueryFilter(s => s.DeletedAt == null);

            entity.HasIndex(s => new { s.TenantId, s.DepartureDateTime });
            entity.HasIndex(s => new { s.TenantId, s.Species });
            entity.HasIndex(s => s.DepartureId);

            entity.Property(s => s.Species)
                  .HasConversion<string>()
                  .HasMaxLength(30);
            entity.Property(s => s.Behaviour)
                  .HasConversion<string>()
                  .HasMaxLength(30);

            entity.HasOne(s => s.Resource)
                  .WithMany()
                  .HasForeignKey(s => s.ResourceId)
                  .OnDelete(DeleteBehavior.Restrict);

            // Cascade, unlike the other two FKs here: a sighting has no
            // meaning once its departure is gone, whereas a departure and a
            // vessel both outlive individual bookings.
            entity.HasOne(s => s.Departure)
                  .WithMany()
                  .HasForeignKey(s => s.DepartureId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // ==================== WEATHER OBSERVATIONS ====================
        modelBuilder.Entity<WeatherObservation>(entity =>
        {
            entity.ToTable("weather_observations");

            entity.HasIndex(w => new { w.TenantId, w.ObservedAt });
            entity.HasIndex(w => w.DepartureId);

            entity.Property(w => w.Source).HasMaxLength(50);
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
            entity.HasIndex(n => new { n.TenantId, n.BranchId, n.IsRead });
            entity.HasIndex(n => n.CreatedAt);

            entity.Property(n => n.Type).HasMaxLength(50).IsRequired();
            entity.Property(n => n.Title).HasMaxLength(150).IsRequired();
            entity.Property(n => n.Message).HasMaxLength(1000).IsRequired();

            entity.HasOne<Branch>().WithMany().HasForeignKey(n => n.BranchId).OnDelete(DeleteBehavior.SetNull);
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

        // ==================== EQUIPMENT (booking-linked, not the Inventory module) ====================
        modelBuilder.Entity<EquipmentReservation>(entity =>
        {
            entity.ToTable("equipment_reservations");

            entity.HasIndex(r => r.BookingId);
            entity.HasIndex(r => r.EquipmentItemId);

            entity.Property(r => r.Quantity).HasPrecision(18, 2);

            entity.HasOne(r => r.Booking)
                  .WithMany()
                  .HasForeignKey(r => r.BookingId)
                  .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(r => r.EquipmentItem)
                  .WithMany()
                  .HasForeignKey(r => r.EquipmentItemId)
                  .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<EquipmentMaintenance>(entity =>
        {
            entity.ToTable("equipment_maintenances");

            entity.HasIndex(m => m.EquipmentItemId);

            entity.Property(m => m.Cost).HasPrecision(18, 2);
            entity.Property(m => m.Status).HasMaxLength(20);

            entity.HasOne(m => m.EquipmentItem)
                  .WithMany()
                  .HasForeignKey(m => m.EquipmentItemId)
                  .OnDelete(DeleteBehavior.Restrict);
        });

        // ==================== INVENTORY MODULE ====================
        // Tenant isolation filters apply to both booking and inventory data.
        modelBuilder.Entity<Tenant>().HasQueryFilter(t => t.IsActive);
        modelBuilder.Entity<Branch>().HasQueryFilter(b => b.TenantId == CurrentTenantId && b.IsActive);
        modelBuilder.Entity<User>().HasQueryFilter(u => u.TenantId == CurrentTenantId && u.Tenant.IsActive);
        modelBuilder.Entity<InventoryCategory>().HasQueryFilter(c => c.TenantId == CurrentTenantId && c.Tenant.IsActive && c.IsActive);
        modelBuilder.Entity<InventoryUnit>().HasQueryFilter(u => u.TenantId == CurrentTenantId && u.Tenant.IsActive && u.IsActive);
        modelBuilder.Entity<InventoryItem>().HasQueryFilter(item => item.TenantId == CurrentTenantId && item.IsActive);
        modelBuilder.Entity<Supplier>().HasQueryFilter(supplier => supplier.TenantId == CurrentTenantId && supplier.IsActive);
        modelBuilder.Entity<PurchaseOrder>().HasQueryFilter(order => order.TenantId == CurrentTenantId);
        modelBuilder.Entity<PurchaseOrderItem>().HasQueryFilter(item => item.TenantId == CurrentTenantId);
        modelBuilder.Entity<StockMovement>().HasQueryFilter(movement => movement.TenantId == CurrentTenantId);
        modelBuilder.Entity<Sale>().HasQueryFilter(sale => sale.TenantId == CurrentTenantId);

        modelBuilder.Entity<InventoryCategory>().HasIndex(c => new { c.TenantId, c.Name }).IsUnique();
        modelBuilder.Entity<InventoryUnit>().HasIndex(u => new { u.TenantId, u.Code }).IsUnique();
        modelBuilder.Entity<InventoryItem>().HasIndex(item => new { item.TenantId, item.Sku }).IsUnique();
        modelBuilder.Entity<Supplier>().HasIndex(supplier => new { supplier.TenantId, supplier.Name }).IsUnique();
        modelBuilder.Entity<PurchaseOrder>().HasIndex(order => new { order.TenantId, order.Number }).IsUnique();
        modelBuilder.Entity<StockMovement>().HasIndex(movement => new { movement.TenantId, movement.BranchId });
        modelBuilder.Entity<StockMovement>().HasIndex(movement => new { movement.InventoryItemId, movement.OccurredAt });
        modelBuilder.Entity<Notification>().HasIndex(notification => new { notification.TenantId, notification.BranchId, notification.IsRead });
        modelBuilder.Entity<Notification>().HasIndex(notification => notification.CreatedAt);
        modelBuilder.Entity<Sale>().HasIndex(sale => new { sale.TenantId, sale.BranchId, sale.OccurredAt });

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

        modelBuilder.Entity<Sale>(entity =>
        {
            entity.Property(sale => sale.Amount).HasPrecision(18, 2);
            entity.Property(sale => sale.Reference).HasMaxLength(100).IsRequired();
            entity.HasOne<Branch>().WithMany().HasForeignKey(sale => sale.BranchId).OnDelete(DeleteBehavior.Restrict);
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
        foreach (var entry in ChangeTracker.Entries<ITenantScoped>())
        {
            if (entry.State == EntityState.Added)
            {
                if (entry.Entity.TenantId == Guid.Empty)
                {
                    if (!tenantId.HasValue)
                    {
                        throw new InvalidOperationException("A tenant-scoped entity cannot be created without a tenant context.");
                    }

                    entry.Entity.TenantId = tenantId.Value;
                }
            }
            else if (entry.State is EntityState.Modified or EntityState.Deleted &&
                      tenantId.HasValue && entry.Entity.TenantId != tenantId.Value)
            {
                throw new UnauthorizedAccessException("A tenant-scoped entity cannot be modified outside the current tenant.");
            }
        }
    }
}
