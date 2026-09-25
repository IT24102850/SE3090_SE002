namespace SmeBackend.Services;

/// Sends a push notification to every device registered for a user.
/// See FcmPushNotificationSender for the concrete FCM implementation.
public interface IPushNotificationSender
{
    Task SendAsync(Guid tenantId, Guid userId, string title, string message);
}
