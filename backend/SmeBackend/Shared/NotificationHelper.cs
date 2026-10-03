using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Shared;

/// Creates in-app Notification rows (FR-C11/FR-AS21 surface). There's no
/// Firebase/APNs credential in this project, so this is genuinely in-app
/// only — same honesty as the simulated SMS/email reminder channel, not a
/// claim of real device push.
public static class NotificationHelper
{
    /// userId == null means tenant-wide (surfaced to Admin/Manager, e.g. an
    /// agent workflow awaiting approval) rather than a specific person.
    public static void Queue(AppDbContext db, Guid tenantId, Guid? userId, string type, string title, string message)
    {
        db.Notifications.Add(new Notification
        {
            TenantId = tenantId,
            UserId = userId,
            Type = type,
            Title = title,
            Message = message,
            IsRead = false
        });
    }
}
