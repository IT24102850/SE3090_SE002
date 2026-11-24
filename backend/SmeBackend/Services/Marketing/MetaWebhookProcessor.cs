using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models.Marketing;
using SmeBackend.Shared;

namespace SmeBackend.Services.Marketing;

public sealed record IncomingSocialMessage(
    string ParticipantId,
    string? ExternalMessageId,
    string Text,
    string? AttachmentUrl,
    DateTime SentAt,
    string Direction);

/// Turns Messenger / Instagram messaging webhooks into inbox threads.
///
/// Webhooks arrive anonymously and carry only the Page or Instagram account
/// id, so the account (and through it the tenant) is looked up by that id.
/// Message ids make redelivery harmless. Messages the business sent from
/// Meta's own apps arrive as echoes and are recorded as outbound, so the
/// thread here matches what the customer sees.
public sealed class MetaWebhookProcessor(
    AppDbContext db,
    IMetaGraphClient meta,
    ISocialTokenService tokens,
    ILogger<MetaWebhookProcessor> logger)
{
    public async Task<int> ProcessAsync(JsonElement root, DateTime now, CancellationToken ct)
    {
        var platform = Str(root, "object") switch
        {
            "page" => SocialPlatform.Facebook,
            "instagram" => SocialPlatform.Instagram,
            _ => null,
        };
        if (platform == null || !root.TryGetProperty("entry", out var entries) || entries.ValueKind != JsonValueKind.Array)
            return 0;

        var recorded = 0;
        foreach (var entry in entries.EnumerateArray())
        {
            var entryId = Str(entry, "id");
            if (entryId == null || !entry.TryGetProperty("messaging", out var messaging) || messaging.ValueKind != JsonValueKind.Array)
                continue;

            var accounts = await db.SocialAccounts.IgnoreQueryFilters()
                .Where(a => a.Platform == platform && a.ExternalId == entryId && a.Status != SocialAccountStatus.Disconnected)
                .ToListAsync(ct);
            if (accounts.Count == 0)
            {
                logger.LogInformation("Meta webhook for unconnected {Platform} account {Id} ignored", platform, entryId);
                continue;
            }

            foreach (var ev in messaging.EnumerateArray())
            {
                var message = Parse(ev, entryId);
                if (message == null) continue;
                foreach (var account in accounts)
                    if (await RecordAsync(account, message, now, ct)) recorded++;
            }
        }

        await db.SaveChangesAsync(ct);
        return recorded;
    }

    /// Adds one message to its thread, creating the thread on first contact.
    /// Returns false when the message was already recorded. Does not save.
    public async Task<bool> RecordAsync(SocialAccount account, IncomingSocialMessage message, DateTime now, CancellationToken ct)
    {
        var conversation = db.SocialConversations.Local
            .FirstOrDefault(c => c.SocialAccountId == account.Id && c.ParticipantId == message.ParticipantId)
            ?? await db.SocialConversations.IgnoreQueryFilters()
                .FirstOrDefaultAsync(c => c.SocialAccountId == account.Id && c.ParticipantId == message.ParticipantId, ct);

        if (conversation == null)
        {
            conversation = new SocialConversation
            {
                TenantId = account.TenantId,
                SocialAccountId = account.Id,
                ParticipantId = message.ParticipantId,
                ParticipantName = await LookupNameAsync(account, message.ParticipantId, ct),
                LastMessageAt = message.SentAt,
            };
            db.SocialConversations.Add(conversation);
        }
        else if (message.ExternalMessageId != null)
        {
            var mid = message.ExternalMessageId;
            var seen = db.SocialMessages.Local.Any(m => m.SocialConversationId == conversation.Id && m.ExternalMessageId == mid)
                || await db.SocialMessages.IgnoreQueryFilters().AnyAsync(m => m.SocialConversationId == conversation.Id && m.ExternalMessageId == mid, ct);
            if (seen) return false;
        }

        db.SocialMessages.Add(new SocialMessage
        {
            TenantId = account.TenantId,
            SocialConversationId = conversation.Id,
            Direction = message.Direction,
            ExternalMessageId = message.ExternalMessageId,
            Text = SocialTokenService.Clip(message.Text, 4000),
            AttachmentUrl = message.AttachmentUrl is { Length: <= 2048 } url ? url : null,
            SentAt = message.SentAt,
        });

        var preview = string.IsNullOrWhiteSpace(message.Text) ? (message.AttachmentUrl != null ? "[attachment]" : "") : message.Text;
        if (message.SentAt >= conversation.LastMessageAt || conversation.LastMessagePreview == null)
        {
            conversation.LastMessageAt = message.SentAt;
            conversation.LastMessagePreview = SocialTokenService.Clip(preview.ReplaceLineEndings(" "), 300);
        }
        conversation.UpdatedAt = now;

        if (message.Direction == SocialMessageDirection.Inbound)
        {
            conversation.UnreadCount++;
            conversation.IsArchived = false;
            if (conversation.LastInboundAt is null || message.SentAt > conversation.LastInboundAt)
                conversation.LastInboundAt = message.SentAt;

            NotificationHelper.Queue(db, account.TenantId, null, "SocialMessage",
                $"New {account.Platform} message",
                $"{conversation.ParticipantName ?? "Someone"}: {SocialTokenService.Clip(preview.ReplaceLineEndings(" "), 140)}");
        }
        return true;
    }

    private async Task<string?> LookupNameAsync(SocialAccount account, string participantId, CancellationToken ct)
    {
        if (account.IsSandbox || account.Status != SocialAccountStatus.Connected) return null;
        try
        {
            var token = await tokens.GetAccessTokenAsync(account, ct);
            return await meta.GetParticipantNameAsync(participantId, token, account.Platform == SocialPlatform.Instagram, ct);
        }
        catch (SocialApiException)
        {
            return null; // the thread still works; the name fills in as "Someone"
        }
    }

    internal static IncomingSocialMessage? Parse(JsonElement ev, string accountExternalId)
    {
        var sender = ev.TryGetProperty("sender", out var s) ? Str(s, "id") : null;
        var recipient = ev.TryGetProperty("recipient", out var r) ? Str(r, "id") : null;
        if (sender == null || recipient == null) return null;

        var sentAt = ev.TryGetProperty("timestamp", out var ts) && ts.TryGetInt64(out var ms)
            ? DateTimeOffset.FromUnixTimeMilliseconds(ms).UtcDateTime
            : DateTime.UtcNow;

        string? mid = null, text = null, attachment = null;
        var echo = false;
        if (ev.TryGetProperty("message", out var m) && m.ValueKind == JsonValueKind.Object)
        {
            if (m.TryGetProperty("is_deleted", out var del) && del.ValueKind == JsonValueKind.True) return null;
            mid = Str(m, "mid");
            text = Str(m, "text");
            echo = m.TryGetProperty("is_echo", out var e) && e.ValueKind == JsonValueKind.True;
            if (m.TryGetProperty("attachments", out var atts) && atts.ValueKind == JsonValueKind.Array)
                foreach (var att in atts.EnumerateArray())
                    if (att.TryGetProperty("payload", out var p) && Str(p, "url") is { } u) { attachment = u; break; }
        }
        else if (ev.TryGetProperty("postback", out var pb) && pb.ValueKind == JsonValueKind.Object)
        {
            mid = Str(pb, "mid");
            text = Str(pb, "title") ?? Str(pb, "payload");
        }
        else
        {
            return null; // delivery / read receipts, reactions, referrals
        }

        if (string.IsNullOrWhiteSpace(text) && attachment == null) return null;

        // Echo = the business's own message; the other side is the recipient.
        var outbound = echo || sender == accountExternalId;
        return new IncomingSocialMessage(
            outbound ? recipient : sender,
            mid,
            text ?? "",
            attachment,
            sentAt,
            outbound ? SocialMessageDirection.Outbound : SocialMessageDirection.Inbound);
    }

    private static string? Str(JsonElement el, string name) =>
        el.ValueKind == JsonValueKind.Object && el.TryGetProperty(name, out var v)
            ? v.ValueKind switch { JsonValueKind.String => v.GetString(), JsonValueKind.Number => v.GetRawText(), _ => null }
            : null;
}
