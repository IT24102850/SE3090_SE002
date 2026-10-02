using Microsoft.AspNetCore.Mvc;
using SmeBackend.Controllers;
using SmeBackend.Models;

namespace SmeBackend.Tests;

public class NotificationsControllerTests
{
    [Fact]
    public async Task GetMine_StaffReceivesTenantWideAndOwnNotifications()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var otherUserId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        db.Notifications.AddRange(
            CreateNotification(tenantId, null, "PurchaseOrderCreated"),
            CreateNotification(tenantId, userId, "BookingConfirmation"),
            CreateNotification(tenantId, otherUserId, "PrivateNotification"));
        await db.SaveChangesAsync();

        var controller = new NotificationsController(db);
        TestHelpers.SetUser(controller, userId, tenantId, "Staff");

        var result = Assert.IsType<OkObjectResult>(await controller.GetMine());
        var items = Assert.IsAssignableFrom<IEnumerable<object>>(
            result.Value!.GetType().GetProperty("items")!.GetValue(result.Value));

        Assert.Equal(2, items.Count());
    }

    [Fact]
    public async Task GetMine_CustomerReceivesOnlyOwnNotifications()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        db.Notifications.AddRange(
            CreateNotification(tenantId, null, "PurchaseOrderCreated"),
            CreateNotification(tenantId, userId, "BookingConfirmation"));
        await db.SaveChangesAsync();

        var controller = new NotificationsController(db);
        TestHelpers.SetUser(controller, userId, tenantId, "Customer");

        var result = Assert.IsType<OkObjectResult>(await controller.GetMine());
        var items = Assert.IsAssignableFrom<IEnumerable<object>>(
            result.Value!.GetType().GetProperty("items")!.GetValue(result.Value));

        Assert.Single(items);
    }

    [Fact]
    public async Task GetUnreadCount_CustomerIncludesOnlyOwnNotifications()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        db.Notifications.AddRange(
            CreateNotification(tenantId, null, "PurchaseOrderCreated"),
            CreateNotification(tenantId, userId, "BookingConfirmation"),
            CreateNotification(tenantId, userId, "ReadNotification", isRead: true));
        await db.SaveChangesAsync();

        var controller = new NotificationsController(db);
        TestHelpers.SetUser(controller, userId, tenantId, "Customer");

        var result = Assert.IsType<OkObjectResult>(await controller.GetUnreadCount());
        var count = (int)result.Value!.GetType().GetProperty("count")!.GetValue(result.Value)!;

        Assert.Equal(1, count);
    }

    [Fact]
    public async Task MarkRead_CustomerCannotMarkTenantWideNotificationRead()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        var notification = CreateNotification(tenantId, null, "PurchaseOrderCreated");
        db.Notifications.Add(notification);
        await db.SaveChangesAsync();

        var controller = new NotificationsController(db);
        TestHelpers.SetUser(controller, userId, tenantId, "Customer");

        var result = await controller.MarkRead(notification.Id);

        Assert.IsType<ForbidResult>(result);
        Assert.False((await db.Notifications.FindAsync(notification.Id))!.IsRead);
    }

    [Fact]
    public async Task GetUnreadCount_StaffIncludesTenantWideNotifications()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        db.Notifications.AddRange(
            CreateNotification(tenantId, null, "PurchaseOrderCreated"),
            CreateNotification(tenantId, userId, "BookingConfirmation"),
            CreateNotification(tenantId, userId, "ReadNotification", isRead: true));
        await db.SaveChangesAsync();

        var controller = new NotificationsController(db);
        TestHelpers.SetUser(controller, userId, tenantId, "Staff");

        var result = Assert.IsType<OkObjectResult>(await controller.GetUnreadCount());
        var count = (int)result.Value!.GetType().GetProperty("count")!.GetValue(result.Value)!;

        Assert.Equal(2, count);
    }

    [Fact]
    public async Task MarkRead_StaffCanMarkTenantWideNotificationRead()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        var notification = CreateNotification(tenantId, null, "PurchaseOrderCreated");
        db.Notifications.Add(notification);
        await db.SaveChangesAsync();

        var controller = new NotificationsController(db);
        TestHelpers.SetUser(controller, userId, tenantId, "Staff");

        var result = await controller.MarkRead(notification.Id);

        Assert.IsType<NoContentResult>(result);
        Assert.True((await db.Notifications.FindAsync(notification.Id))!.IsRead);
    }

    private static Notification CreateNotification(
        Guid tenantId,
        Guid? userId,
        string type,
        bool isRead = false) =>
        new()
        {
            TenantId = tenantId,
            UserId = userId,
            Type = type,
            Title = type,
            Message = type,
            IsRead = isRead,
        };
}
