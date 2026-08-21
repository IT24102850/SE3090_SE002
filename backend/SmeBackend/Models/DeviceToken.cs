namespace SmeBackend.Models;

/// One registered device (mobile app install) that can receive FCM push
/// notifications for a given user. See Services/FcmPushNotificationSender.cs.
public class DeviceToken : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid UserId { get; set; }
    public string Token { get; set; } = string.Empty;
    public string Platform { get; set; } = string.Empty; // android, ios
}
