using System.ComponentModel.DataAnnotations;

namespace SmeBackend.Models.Marketing;

/// A direct-message thread between one connected account (Facebook Page or
/// Instagram account) and one person, fed by the Meta webhook.
public class SocialConversation : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }

    public Guid SocialAccountId { get; set; }
    public SocialAccount? Account { get; set; }

    /// Page-scoped id (Messenger PSID) or Instagram-scoped id (IGSID).
    [MaxLength(100)]
    public string ParticipantId { get; set; } = string.Empty;

    [MaxLength(200)]
    public string? ParticipantName { get; set; }

    [MaxLength(300)]
    public string? LastMessagePreview { get; set; }

    public DateTime LastMessageAt { get; set; } = DateTime.UtcNow;

    /// Meta only allows a free-form reply within 24 hours of the person's
    /// last message. Tracked separately from LastMessageAt because our own
    /// replies do not reopen that window.
    public DateTime? LastInboundAt { get; set; }

    public int UnreadCount { get; set; }

    public bool IsArchived { get; set; }

    /// The booking this conversation turned into, once one is made from the
    /// link we sent - set when a booking arrives carrying the conversation id.
    public Guid? LinkedBookingId { get; set; }

    public List<SocialMessage> Messages { get; set; } = new();
}

public static class SocialMessageDirection
{
    public const string Inbound = "Inbound";
    public const string Outbound = "Outbound";
}

public class SocialMessage : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }

    public Guid SocialConversationId { get; set; }
    public SocialConversation? Conversation { get; set; }

    /// Inbound | Outbound
    [MaxLength(10)]
    public string Direction { get; set; } = SocialMessageDirection.Inbound;

    /// Provider message id (mid) - unique, which is what makes a redelivered
    /// webhook a no-op.
    [MaxLength(300)]
    public string? ExternalMessageId { get; set; }

    [MaxLength(4000)]
    public string Text { get; set; } = string.Empty;

    [MaxLength(2048)]
    public string? AttachmentUrl { get; set; }

    public DateTime SentAt { get; set; } = DateTime.UtcNow;

    public Guid? SentByUserId { get; set; }

    /// Outbound only: the provider refused it.
    [MaxLength(1000)]
    public string? Error { get; set; }
}
