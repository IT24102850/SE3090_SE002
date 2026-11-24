using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models.Marketing;
using SmeBackend.Services.Marketing;

namespace SmeBackend.Controllers.Marketing;

/// One inbox for Facebook Messenger and Instagram DMs across every
/// connected account. Staff can answer; the "send booking link" action in
/// the web app is an ordinary reply whose link carries the conversation id,
/// so the booking that follows is tied back to this thread.
///
/// TikTok has no public direct-message API for business accounts, so TikTok
/// accounts do not appear here.
[ApiController]
[Route("api/social/inbox")]
[Authorize(Roles = "Admin,Manager,Staff")]
public class SocialInboxController(
    AppDbContext db,
    IMetaGraphClient meta,
    ISocialTokenService tokens,
    MetaWebhookProcessor processor) : MarketingControllerBase
{
    /// Meta's standard messaging window.
    public static readonly TimeSpan ReplyWindow = TimeSpan.FromHours(24);

    [HttpGet("conversations")]
    public async Task<IActionResult> Conversations([FromQuery] Guid? accountId, [FromQuery] bool archived = false,
        [FromQuery] string? search = null, [FromQuery] int take = 50)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        take = Math.Clamp(take, 1, 200);

        var q = db.SocialConversations.AsNoTracking()
            .Include(c => c.Account)
            .Where(c => c.TenantId == tenantId && c.IsArchived == archived);
        if (accountId.HasValue) q = q.Where(c => c.SocialAccountId == accountId.Value);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            q = q.Where(c => (c.ParticipantName != null && c.ParticipantName.ToLower().Contains(s))
                || (c.LastMessagePreview != null && c.LastMessagePreview.ToLower().Contains(s)));
        }

        var now = DateTime.UtcNow;
        var list = await q.OrderByDescending(c => c.LastMessageAt).Take(take).ToListAsync();
        return Ok(list.Select(c => ToDto(c, now)));
    }

    [HttpGet("unread-count")]
    public async Task<IActionResult> UnreadCount()
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var count = await db.SocialConversations
            .Where(c => c.TenantId == tenantId && !c.IsArchived)
            .SumAsync(c => c.UnreadCount);
        return Ok(new { count });
    }

    /// <summary>A thread's messages (oldest first). Opening it marks it read.</summary>
    [HttpGet("conversations/{id:guid}/messages")]
    public async Task<IActionResult> Messages(Guid id, [FromQuery] int take = 200)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var conversation = await db.SocialConversations.Include(c => c.Account)
            .FirstOrDefaultAsync(c => c.Id == id && c.TenantId == tenantId);
        if (conversation == null) return NotFound(new { message = "Conversation not found." });

        take = Math.Clamp(take, 1, 500);
        var messages = await db.SocialMessages.AsNoTracking()
            .Where(m => m.SocialConversationId == id)
            .OrderByDescending(m => m.SentAt).Take(take)
            .ToListAsync();

        if (conversation.UnreadCount > 0)
        {
            conversation.UnreadCount = 0;
            await db.SaveChangesAsync();
        }

        return Ok(new
        {
            conversation = ToDto(conversation, DateTime.UtcNow),
            messages = messages.OrderBy(m => m.SentAt).Select(MessageDto),
        });
    }

    public sealed class ReplyRequest
    {
        [Required, MaxLength(2000)]
        public string Text { get; set; } = string.Empty;
    }

    [HttpPost("conversations/{id:guid}/reply")]
    public async Task<IActionResult> Reply(Guid id, [FromBody] ReplyRequest body, CancellationToken ct)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var text = body.Text.Trim();
        if (text.Length == 0) return BadRequest(new { message = "Write a message first." });

        var conversation = await db.SocialConversations.Include(c => c.Account)
            .FirstOrDefaultAsync(c => c.Id == id && c.TenantId == tenantId, ct);
        if (conversation == null) return NotFound(new { message = "Conversation not found." });
        var account = conversation.Account!;
        if (account.Status == SocialAccountStatus.Disconnected)
            return Conflict(new { message = "This account has been disconnected." });

        var now = DateTime.UtcNow;
        string? mid;
        if (account.IsSandbox)
        {
            mid = "sandbox-" + Guid.NewGuid().ToString("N")[..16];
        }
        else
        {
            if (conversation.LastInboundAt is not { } last || now - last > ReplyWindow)
                return Conflict(new { message = $"{account.Platform} only allows replies within 24 hours of the customer's last message. Answer from the {account.Platform} app instead, or wait for them to write again." });

            var pageId = account.Platform == SocialPlatform.Instagram ? account.ParentExternalId : account.ExternalId;
            if (string.IsNullOrEmpty(pageId))
                return Conflict(new { message = "This Instagram account is not linked to a Facebook Page. Reconnect it." });

            try
            {
                var token = await tokens.GetAccessTokenAsync(account, ct);
                mid = await meta.SendMessageAsync(pageId, token, conversation.ParticipantId, text, ct);
            }
            catch (SocialApiException e)
            {
                if (e.TokenInvalid)
                {
                    tokens.MarkNeedsReconnect(account, e.Message);
                    await db.SaveChangesAsync(ct);
                }
                return StatusCode(StatusCodes.Status502BadGateway, new { message = $"{account.Platform} refused the message: {e.Message}" });
            }
        }

        var message = new SocialMessage
        {
            TenantId = tenantId,
            SocialConversationId = conversation.Id,
            Direction = SocialMessageDirection.Outbound,
            ExternalMessageId = mid,
            Text = text,
            SentAt = now,
            SentByUserId = UserId,
        };
        db.SocialMessages.Add(message);
        conversation.LastMessageAt = now;
        conversation.LastMessagePreview = SocialTokenService.Clip(text.ReplaceLineEndings(" "), 300);
        conversation.UnreadCount = 0;
        conversation.UpdatedAt = now;
        await db.SaveChangesAsync(ct);
        return Ok(MessageDto(message));
    }

    public sealed class ArchiveRequest
    {
        public bool Archived { get; set; } = true;
    }

    [HttpPost("conversations/{id:guid}/archive")]
    public async Task<IActionResult> Archive(Guid id, [FromBody] ArchiveRequest body)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var conversation = await db.SocialConversations.FirstOrDefaultAsync(c => c.Id == id && c.TenantId == tenantId);
        if (conversation == null) return NotFound(new { message = "Conversation not found." });
        conversation.IsArchived = body.Archived;
        if (body.Archived) conversation.UnreadCount = 0;
        conversation.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return NoContent();
    }

    public sealed class SimulateRequest
    {
        [Required]
        public Guid AccountId { get; set; }

        [MaxLength(200)]
        public string? ParticipantName { get; set; }

        [Required, MaxLength(2000)]
        public string Text { get; set; } = string.Empty;
    }

    /// <summary>Sandbox only: delivers a pretend incoming DM, to try the inbox without Meta.</summary>
    [HttpPost("sandbox/incoming")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> SimulateIncoming([FromBody] SimulateRequest body, CancellationToken ct)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var account = await db.SocialAccounts.FirstOrDefaultAsync(a => a.Id == body.AccountId && a.TenantId == tenantId, ct);
        if (account == null) return NotFound(new { message = "Account not found." });
        if (!account.IsSandbox) return BadRequest(new { message = "Only sandbox accounts can receive simulated messages." });
        if (account.Platform == SocialPlatform.TikTok) return BadRequest(new { message = "TikTok has no direct-message API." });

        var name = string.IsNullOrWhiteSpace(body.ParticipantName) ? "Sandbox customer" : body.ParticipantName.Trim();
        var participant = "sandbox-" + Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(name.ToLowerInvariant())))[..16];
        var now = DateTime.UtcNow;
        await processor.RecordAsync(account,
            new IncomingSocialMessage(participant, "sandbox-" + Guid.NewGuid().ToString("N"), body.Text.Trim(), null, now, SocialMessageDirection.Inbound),
            now, ct);

        var conversation = db.SocialConversations.Local.First(c => c.SocialAccountId == account.Id && c.ParticipantId == participant);
        conversation.ParticipantName ??= name;
        await db.SaveChangesAsync(ct);
        return Ok(new { conversationId = conversation.Id });
    }

    private static object ToDto(SocialConversation c, DateTime now) => new
    {
        id = c.Id,
        accountId = c.SocialAccountId,
        platform = c.Account?.Platform,
        accountName = c.Account?.DisplayName,
        isSandbox = c.Account?.IsSandbox ?? false,
        participantId = c.ParticipantId,
        participantName = c.ParticipantName,
        lastMessagePreview = c.LastMessagePreview,
        lastMessageAt = c.LastMessageAt,
        lastInboundAt = c.LastInboundAt,
        unreadCount = c.UnreadCount,
        isArchived = c.IsArchived,
        linkedBookingId = c.LinkedBookingId,
        canReply = (c.Account?.IsSandbox ?? false) || (c.LastInboundAt is { } last && now - last <= ReplyWindow),
        replyWindowEndsAt = c.LastInboundAt?.Add(ReplyWindow),
    };

    private static object MessageDto(SocialMessage m) => new
    {
        id = m.Id,
        direction = m.Direction,
        text = m.Text,
        attachmentUrl = m.AttachmentUrl,
        sentAt = m.SentAt,
        sentByUserId = m.SentByUserId,
        error = m.Error,
    };
}
