using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Services.Inventory;
using SmeBackend.Tests.Api;

namespace SmeBackend.Tests.Inventory;

/// <summary>Seeds one branch, three suppliers and two items for the StockSense tests.</summary>
public sealed class StockSenseFixture : IDisposable
{
    public ApiWebApplicationFactory Factory { get; } = new();
    public Guid BranchId { get; } = Guid.NewGuid();
    public Guid KnownSupplierId { get; } = Guid.NewGuid();
    public Guid NewSupplierId { get; } = Guid.NewGuid();
    public Guid InactiveSupplierId { get; } = Guid.NewGuid();
    public Guid GlovesId { get; } = Guid.NewGuid();
    public Guid MasksId { get; } = Guid.NewGuid();

    public StockSenseFixture()
    {
        using var scope = Factory.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<ITenantContext>().SetTenantId(Factory.TenantId);
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var tenant = Factory.TenantId;

        db.Branches.Add(new Branch { Id = BranchId, TenantId = tenant, Name = "Weligama" });
        db.Suppliers.AddRange(
            new Supplier { Id = KnownSupplierId, TenantId = tenant, Name = "MediSupply" },
            new Supplier { Id = NewSupplierId, TenantId = tenant, Name = "Fresh Traders" },
            new Supplier { Id = InactiveSupplierId, TenantId = tenant, Name = "Closed Ltd", IsActive = false });
        // MediSupply has delivered before, so it is a known supplier.
        db.PurchaseOrders.Add(new PurchaseOrder { TenantId = tenant, BranchId = BranchId, SupplierId = KnownSupplierId, Number = "PO-OLD-1", Status = "Received" });
        db.InventoryItems.AddRange(
            new InventoryItem { Id = GlovesId, TenantId = tenant, BranchId = BranchId, Name = "Latex gloves", Sku = "GLV-1", Quantity = 15, ReorderLevel = 20, UnitCost = 800m },
            new InventoryItem { Id = MasksId, TenantId = tenant, BranchId = BranchId, Name = "Face masks", Sku = "MSK-1", Quantity = 40, ReorderLevel = 20, UnitCost = 50m });

        foreach (var user in db.Users.IgnoreQueryFilters().Where(u => u.TenantId == tenant))
            if (user.Role is UserRole.Manager or UserRole.Staff) user.BranchId = BranchId;
        db.SaveChanges();
    }

    public void Dispose() => Factory.Dispose();
}

/// <summary>
/// The StockSense reorder workflow over HTTP: a staff request goes through the
/// deterministic gate, a high-impact order pauses, only a manager can decide
/// it, the decision places (or does not place) a purchase order at database
/// prices, and the requester is told.
/// </summary>
public sealed class StockSenseReorderApiTests(StockSenseFixture fx) : IClassFixture<StockSenseFixture>
{
    private static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);

    private async Task<HttpClient> As(UserRole role)
    {
        var client = fx.Factory.CreateClient();
        var login = await client.PostAsJsonAsync("/api/auth/login",
            new { email = ApiWebApplicationFactory.EmailFor(role), password = ApiWebApplicationFactory.Password });
        login.EnsureSuccessStatusCode();
        using var body = JsonDocument.Parse(await login.Content.ReadAsStringAsync());
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", body.RootElement.GetProperty("accessToken").GetString());
        return client;
    }

    private async Task<(HttpStatusCode Status, JsonElement Body)> Request(HttpClient client, Guid supplier, params (Guid Item, decimal Qty)[] lines)
    {
        var response = await client.PostAsJsonAsync("/api/inventory/agent/reorders", new
        {
            branchId = fx.BranchId,
            supplierId = supplier,
            lines = lines.Select(l => new { inventoryItemId = l.Item, quantity = l.Qty }),
        });
        var text = await response.Content.ReadAsStringAsync();
        return (response.StatusCode, JsonDocument.Parse(string.IsNullOrEmpty(text) ? "{}" : text).RootElement.Clone());
    }

    private T Db<T>(Func<AppDbContext, T> read)
    {
        using var scope = fx.Factory.Services.CreateScope();
        return read(scope.ServiceProvider.GetRequiredService<AppDbContext>());
    }

    private Guid UserId(UserRole role) => Db(db => db.Users.IgnoreQueryFilters()
        .First(u => u.Email == ApiWebApplicationFactory.EmailFor(role)).Id);

    [Fact]
    public async Task SmallOrderFromKnownSupplier_IsPlacedAutomatically_AtDatabasePrices()
    {
        var staff = await As(UserRole.Staff);

        var (status, body) = await Request(staff, fx.KnownSupplierId, (fx.GlovesId, 5));

        Assert.Equal(HttpStatusCode.Created, status);
        Assert.Equal("Completed", body.GetProperty("status").GetString());
        Assert.Equal("NotRequired", body.GetProperty("approvalStatus").GetString());
        var poId = body.GetProperty("purchaseOrderId").GetGuid();
        var order = Db(db => db.PurchaseOrders.IgnoreQueryFilters().Include(o => o.Items).Single(o => o.Id == poId));
        Assert.Equal("Placed", order.Status);
        Assert.Equal(800m, order.Items.Single().UnitPrice);
        Assert.Equal(5m, order.Items.Single().Quantity);
    }

    [Fact]
    public async Task HighValueOrder_PausesForApproval_AndTellsManagers()
    {
        var staff = await As(UserRole.Staff);

        var (status, body) = await Request(staff, fx.KnownSupplierId, (fx.GlovesId, 200)); // 160,000

        Assert.Equal(HttpStatusCode.Created, status);
        Assert.Equal("AwaitingApproval", body.GetProperty("status").GetString());
        Assert.Equal(JsonValueKind.Null, body.GetProperty("purchaseOrderId").ValueKind);
        Assert.Contains(body.GetProperty("checks").EnumerateArray(),
            c => c.GetProperty("rule").GetString() == "value_within_auto_limit" && !c.GetProperty("passed").GetBoolean());
        var id = body.GetProperty("id").GetGuid();
        var stored = Db(db => db.AgentWorkflows.IgnoreQueryFilters().Single(w => w.Id == id));
        Assert.StartsWith(StockSenseWorkflows.ReorderPrefix, stored.Objective);
        Assert.Equal(UserId(UserRole.Staff), stored.RequestedByUserId);
        Assert.True(Db(db => db.Notifications.IgnoreQueryFilters()
            .Any(n => n.TenantId == fx.Factory.TenantId && n.UserId == null && n.Title == "Reorder needs approval")));
    }

    [Fact]
    public async Task Staff_CannotApprove_ButTheBranchManagerCan_AndTheRequesterIsNotified()
    {
        var staff = await As(UserRole.Staff);
        var (_, pending) = await Request(staff, fx.KnownSupplierId, (fx.GlovesId, 250));
        var id = pending.GetProperty("id").GetGuid();

        var staffAttempt = await staff.PostAsJsonAsync($"/api/inventory/agent/reorders/{id}/approve", new { });
        Assert.Equal(HttpStatusCode.Forbidden, staffAttempt.StatusCode);

        var manager = await As(UserRole.Manager);
        var approval = await manager.PostAsJsonAsync($"/api/inventory/agent/reorders/{id}/approve", new { });
        Assert.Equal(HttpStatusCode.OK, approval.StatusCode);
        var body = JsonDocument.Parse(await approval.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal("Completed", body.GetProperty("status").GetString());
        Assert.Equal("Approved", body.GetProperty("approvalStatus").GetString());
        Assert.Equal(UserId(UserRole.Manager), body.GetProperty("decidedBy").GetGuid());

        var poNumber = body.GetProperty("purchaseOrderNumber").GetString();
        Assert.True(Db(db => db.PurchaseOrders.IgnoreQueryFilters().Any(o => o.Number == poNumber && o.Status == "Placed")));
        var staffId = UserId(UserRole.Staff);
        Assert.True(Db(db => db.Notifications.IgnoreQueryFilters()
            .Any(n => n.UserId == staffId && n.Type == "WorkflowApproved" && n.Message.Contains(poNumber!))));

        var again = await manager.PostAsJsonAsync($"/api/inventory/agent/reorders/{id}/approve", new { });
        Assert.Equal(HttpStatusCode.Conflict, again.StatusCode);
    }

    [Fact]
    public async Task NewSupplier_PausesEvenForASmallOrder()
    {
        var staff = await As(UserRole.Staff);

        var (_, body) = await Request(staff, fx.NewSupplierId, (fx.MasksId, 2));

        Assert.Equal("AwaitingApproval", body.GetProperty("status").GetString());
    }

    [Fact]
    public async Task InactiveSupplier_IsRejected_AndNothingIsOrdered()
    {
        var staff = await As(UserRole.Staff);
        var ordersBefore = Db(db => db.PurchaseOrders.IgnoreQueryFilters().Count());

        var (status, body) = await Request(staff, fx.InactiveSupplierId, (fx.MasksId, 2));

        Assert.Equal(HttpStatusCode.Created, status);
        Assert.Equal("Rejected", body.GetProperty("status").GetString());
        Assert.Contains("inactive", body.GetProperty("error").GetString());
        Assert.Equal(ordersBefore, Db(db => db.PurchaseOrders.IgnoreQueryFilters().Count()));
    }

    [Fact]
    public async Task Reject_RecordsTheReason_AndCannotBeApprovedAfterwards()
    {
        var staff = await As(UserRole.Staff);
        var (_, pending) = await Request(staff, fx.KnownSupplierId, (fx.GlovesId, 300));
        var id = pending.GetProperty("id").GetGuid();
        var manager = await As(UserRole.Manager);

        var reject = await manager.PostAsJsonAsync($"/api/inventory/agent/reorders/{id}/reject", new { reason = "Budget frozen this month" });
        var approve = await manager.PostAsJsonAsync($"/api/inventory/agent/reorders/{id}/approve", new { });

        Assert.Equal(HttpStatusCode.OK, reject.StatusCode);
        var body = JsonDocument.Parse(await reject.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal("Rejected", body.GetProperty("status").GetString());
        Assert.Contains("Budget frozen", body.GetProperty("finalOutcome").GetString());
        Assert.Equal(HttpStatusCode.Conflict, approve.StatusCode);
    }

    [Fact]
    public async Task RequestRevision_SendsItBackToTheRequester()
    {
        var staff = await As(UserRole.Staff);
        var (_, pending) = await Request(staff, fx.KnownSupplierId, (fx.GlovesId, 400));
        var id = pending.GetProperty("id").GetGuid();
        var manager = await As(UserRole.Manager);

        var revise = await manager.PostAsJsonAsync($"/api/inventory/agent/reorders/{id}/revise", new { reason = "Split into two deliveries" });

        Assert.Equal(HttpStatusCode.OK, revise.StatusCode);
        Assert.Equal("RevisionRequested", JsonDocument.Parse(await revise.Content.ReadAsStringAsync()).RootElement.GetProperty("status").GetString());
        var staffId = UserId(UserRole.Staff);
        Assert.True(Db(db => db.Notifications.IgnoreQueryFilters()
            .Any(n => n.UserId == staffId && n.Type == "WorkflowRevision")));
    }

    [Fact]
    public async Task Reject_WithoutAReason_Returns400()
    {
        var staff = await As(UserRole.Staff);
        var (_, pending) = await Request(staff, fx.KnownSupplierId, (fx.GlovesId, 500));
        var manager = await As(UserRole.Manager);

        var reject = await manager.PostAsJsonAsync($"/api/inventory/agent/reorders/{pending.GetProperty("id").GetGuid()}/reject", new { reason = "" });

        Assert.Equal(HttpStatusCode.BadRequest, reject.StatusCode);
    }

    [Fact]
    public async Task UnknownItem_OrDuplicateLines_Return400()
    {
        var staff = await As(UserRole.Staff);

        var (unknown, _) = await Request(staff, fx.KnownSupplierId, (Guid.NewGuid(), 1));
        var (duplicate, _) = await Request(staff, fx.KnownSupplierId, (fx.GlovesId, 1), (fx.GlovesId, 2));

        Assert.Equal(HttpStatusCode.BadRequest, unknown);
        Assert.Equal(HttpStatusCode.BadRequest, duplicate);
    }

    [Fact]
    public async Task ManagerSeesTheirBranchsReorders()
    {
        var staff = await As(UserRole.Staff);
        await Request(staff, fx.NewSupplierId, (fx.MasksId, 1));
        var manager = await As(UserRole.Manager);

        var list = await manager.GetFromJsonAsync<List<JsonElement>>("/api/inventory/agent/reorders?status=AwaitingApproval", Web);

        Assert.NotNull(list);
        Assert.NotEmpty(list!);
        Assert.All(list!, r => Assert.Equal("AwaitingApproval", r.GetProperty("status").GetString()));
    }

    [Fact]
    public async Task StockAdjustmentBelowTheReorderLevel_RaisesOneLowStockAlert()
    {
        var admin = await As(UserRole.Admin);
        // Masks start at 40 with a reorder level of 20.
        await admin.PostAsJsonAsync($"/api/inventory/{fx.MasksId}/adjust", new { quantity = -21, reason = "Count correction" });
        await admin.PostAsJsonAsync($"/api/inventory/{fx.MasksId}/adjust", new { quantity = -1, reason = "Count correction" });

        var alerts = Db(db => db.Notifications.IgnoreQueryFilters()
            .Count(n => n.Type == "LowStock" && n.Title.StartsWith("Face masks")));
        Assert.Equal(1, alerts);
    }
}
