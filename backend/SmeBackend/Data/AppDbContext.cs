using Microsoft.EntityFrameworkCore;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Data;

public class AppDbContext : DbContext
{
    private readonly ITenantContext? _tenantContext;
    
    // Constructor for DI (runtime with tenant context)
    public AppDbContext(DbContextOptions<AppDbContext> options, ITenantContext tenantContext) : base(options)
    {
        _tenantContext = tenantContext;
    }
    
    // Constructor for migrations/design-time (no tenant context)
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<Tenant> Tenants { get; set; }
    public DbSet<Branch> Branches { get; set; }
    public DbSet<User> Users { get; set; }
    public DbSet<TenantModule> TenantModules { get; set; }
    
    // Hasiru's entities
    public DbSet<Booking> Bookings { get; set; }
    public DbSet<Resource> Resources { get; set; }
    public DbSet<ResourceSchedule> ResourceSchedules { get; set; }
    public DbSet<AvailabilitySlot> AvailabilitySlots { get; set; }
    public DbSet<BookingType> BookingTypes { get; set; }
    public DbSet<BookingReminder> BookingReminders { get; set; }
    public DbSet<RecurringPattern> RecurringPatterns { get; set; }
    
    // Student 2's entities
    public DbSet<Invoice> Invoices { get; set; }
    public DbSet<InvoiceItem> InvoiceItems { get; set; }
    public DbSet<Payment> Payments { get; set; }
    public DbSet<Subscription> Subscriptions { get; set; }
    public DbSet<InsuranceClaim> InsuranceClaims { get; set; }
    public DbSet<DynamicForm> DynamicForms { get; set; }
    public DbSet<FormSubmission> FormSubmissions { get; set; }
    
    // Student 3's entities
    public DbSet<InventoryItem> InventoryItems { get; set; }
    public DbSet<StockMovement> StockMovements { get; set; }
    public DbSet<Supplier> Suppliers { get; set; }
    public DbSet<PurchaseOrder> PurchaseOrders { get; set; }
    public DbSet<PurchaseOrderItem> PurchaseOrderItems { get; set; }
    public DbSet<EquipmentMaintenance> EquipmentMaintenances { get; set; }
    public DbSet<AnalyticsSnapshot> AnalyticsSnapshots { get; set; }
    public DbSet<Notification> Notifications { get; set; }
    
    // Shared
    public DbSet<AgentWorkflow> AgentWorkflows { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // ===== GLOBAL QUERY FILTERS (Multi-Tenancy) =====
        // These automatically filter ALL queries by TenantId when a tenant context is set
        // If no tenant context (migrations, seeding), the filter is bypassed
        
        ApplyTenantFilter<Branch>(modelBuilder);
        ApplyTenantFilter<User>(modelBuilder);
        modelBuilder.Entity<TenantModule>()
            .HasIndex(tm => new { tm.TenantId, tm.ModuleName })
            .IsUnique();
        
        // Hasiru's entities
        ApplyTenantFilter<Booking>(modelBuilder);
        ApplyTenantFilter<Resource>(modelBuilder);
        ApplyTenantFilter<BookingType>(modelBuilder);
        
        // Student 2's entities
        ApplyTenantFilter<Invoice>(modelBuilder);
        ApplyTenantFilter<Subscription>(modelBuilder);
        ApplyTenantFilter<DynamicForm>(modelBuilder);
        
        // Student 3's entities
        ApplyTenantFilter<InventoryItem>(modelBuilder);
        ApplyTenantFilter<Supplier>(modelBuilder);
        ApplyTenantFilter<PurchaseOrder>(modelBuilder);
        ApplyTenantFilter<AnalyticsSnapshot>(modelBuilder);
        ApplyTenantFilter<Notification>(modelBuilder);
        
        // Shared
        ApplyTenantFilter<AgentWorkflow>(modelBuilder);

        // ===== INDEXES =====
        modelBuilder.Entity<User>().HasIndex(u => u.Email).IsUnique();
        modelBuilder.Entity<Branch>().HasIndex(b => b.TenantId);
        modelBuilder.Entity<TenantModule>()
            .HasIndex(tm => new { tm.TenantId, tm.ModuleName })
            .IsUnique();
    }
    
    private void ApplyTenantFilter<TEntity>(ModelBuilder modelBuilder) where TEntity : class, ITenantScoped
    {
        modelBuilder.Entity<TEntity>().HasQueryFilter(e => 
            _tenantContext == null || _tenantContext.CurrentTenantId == null || e.TenantId == _tenantContext.CurrentTenantId);
    }
    
    public override int SaveChanges()
    {
        EnforceTenantId();
        return base.SaveChanges();
    }
    
    public override async Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        EnforceTenantId();
        return await base.SaveChangesAsync(cancellationToken);
    }
    
    private void EnforceTenantId()
    {
        if (_tenantContext?.CurrentTenantId == null) return;
        
        var entries = ChangeTracker.Entries<ITenantScoped>()
            .Where(e => e.State == EntityState.Added);
            
        foreach (var entry in entries)
        {
            if (entry.Entity.TenantId == Guid.Empty)
            {
                entry.Entity.TenantId = _tenantContext.CurrentTenantId.Value;
            }
        }
    }
}