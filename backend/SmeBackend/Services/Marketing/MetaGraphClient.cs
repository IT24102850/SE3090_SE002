using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using SmeBackend.Models.Marketing;

namespace SmeBackend.Services.Marketing;

public sealed record MetaInstagramAccount(string Id, string? Username, string? ProfilePictureUrl);
public sealed record MetaPage(string Id, string Name, string AccessToken, string? PictureUrl, MetaInstagramAccount? Instagram);
public sealed record MetaUserToken(string AccessToken, DateTime? ExpiresAt);
public sealed record AdAccountInfo(string Id, string Name, string? Currency);
public sealed record CampaignSpend(string CampaignId, string CampaignName, decimal Spend, long Impressions, long Clicks);

public interface IMetaGraphClient
{
    string BuildAuthorizeUrl(string redirectUri, string state);
    Task<MetaUserToken> ExchangeCodeAsync(string code, string redirectUri, CancellationToken ct);
    Task<IReadOnlyList<MetaPage>> GetPagesAsync(string userToken, CancellationToken ct);
    Task SubscribePageToWebhooksAsync(string pageId, string pageToken, CancellationToken ct);
    Task<IReadOnlyList<AdAccountInfo>> GetAdAccountsAsync(string userToken, CancellationToken ct);

    Task<PublishStep> PublishFacebookAsync(string pageId, string pageToken, PublishRequest post, CancellationToken ct);
    Task<PublishStep> StartInstagramAsync(string igUserId, string pageToken, PublishRequest post, CancellationToken ct);
    Task<PublishStep> ContinueInstagramAsync(string igUserId, string pageToken, string containerId, CancellationToken ct);

    /// Re-reads a Page's or Instagram account's name and picture; doubles as
    /// a check that the stored token still works.
    Task<(string Name, string? Handle, string? PictureUrl)> GetProfileAsync(string id, string token, bool instagram, CancellationToken ct);

    Task<string?> SendMessageAsync(string pageId, string pageToken, string recipientId, string text, CancellationToken ct);
    Task<string?> GetParticipantNameAsync(string participantId, string pageToken, bool instagram, CancellationToken ct);

    Task SendConversionAsync(string pixelId, string accessToken, string? testEventCode, object serverEvent, CancellationToken ct);
    Task<IReadOnlyList<CampaignSpend>> GetCampaignSpendAsync(string adAccountId, string accessToken, DateOnly since, DateOnly until, CancellationToken ct);
}

/// Thin, explicit wrapper over the Graph API calls Unify makes. No SDK: the
/// surface is small, and an SDK would hide exactly the error codes the
/// publisher needs to tell "reconnect" from "try again later".
public sealed class MetaGraphClient : IMetaGraphClient
{
    public const string ClientName = "social-meta";

    private readonly HttpClient _http;
    private readonly MetaAppOptions _app;

    public MetaGraphClient(IHttpClientFactory factory, IOptions<SocialOptions> options)
    {
        _http = factory.CreateClient(ClientName);
        _app = options.Value.Meta;
    }

    private string Graph => $"https://graph.facebook.com/{_app.GraphVersion}/";
    private string GraphVideo => $"https://graph-video.facebook.com/{_app.GraphVersion}/";

    // ── OAuth ──────────────────────────────────────────────────────────────

    public string BuildAuthorizeUrl(string redirectUri, string state) =>
        $"https://www.facebook.com/{_app.GraphVersion}/dialog/oauth" +
        $"?client_id={Uri.EscapeDataString(_app.AppId ?? "")}" +
        $"&redirect_uri={Uri.EscapeDataString(redirectUri)}" +
        $"&state={Uri.EscapeDataString(state)}" +
        $"&response_type=code" +
        $"&scope={Uri.EscapeDataString(_app.Scopes)}";

    public async Task<MetaUserToken> ExchangeCodeAsync(string code, string redirectUri, CancellationToken ct)
    {
        RequireApp();
        var shortLived = await GetAsync(
            $"{Graph}oauth/access_token?client_id={E(_app.AppId!)}&client_secret={E(_app.AppSecret!)}" +
            $"&redirect_uri={E(redirectUri)}&code={E(code)}", token: null, ct);
        var token = Str(shortLived, "access_token") ?? throw new SocialApiException("Meta did not return an access token.");

        // Trade for the ~60-day token. Page tokens fetched with a long-lived
        // user token never expire, which is what keeps scheduled posts
        // working without the owner logging in every hour.
        var longLived = await GetAsync(
            $"{Graph}oauth/access_token?grant_type=fb_exchange_token&client_id={E(_app.AppId!)}" +
            $"&client_secret={E(_app.AppSecret!)}&fb_exchange_token={E(token)}", token: null, ct);
        var llToken = Str(longLived, "access_token") ?? token;
        DateTime? expires = longLived.TryGetProperty("expires_in", out var exp) && exp.TryGetInt64(out var secs)
            ? DateTime.UtcNow.AddSeconds(secs)
            : null;
        return new MetaUserToken(llToken, expires);
    }

    public async Task<IReadOnlyList<MetaPage>> GetPagesAsync(string userToken, CancellationToken ct)
    {
        var pages = new List<MetaPage>();
        string? url = $"{Graph}me/accounts?fields=id,name,access_token,picture{{url}},instagram_business_account{{id,username,profile_picture_url}}&limit=100";
        for (var guard = 0; url != null && guard < 10; guard++)
        {
            var root = await GetAsync(url, userToken, ct);
            if (root.TryGetProperty("data", out var data))
            {
                foreach (var p in data.EnumerateArray())
                {
                    var id = Str(p, "id");
                    var token = Str(p, "access_token");
                    if (id == null || token == null) continue;
                    MetaInstagramAccount? ig = null;
                    if (p.TryGetProperty("instagram_business_account", out var igEl) && Str(igEl, "id") is { } igId)
                        ig = new MetaInstagramAccount(igId, Str(igEl, "username"), Str(igEl, "profile_picture_url"));
                    string? picture = p.TryGetProperty("picture", out var pic) && pic.TryGetProperty("data", out var pd) ? Str(pd, "url") : null;
                    pages.Add(new MetaPage(id, Str(p, "name") ?? id, token, picture, ig));
                }
            }
            url = root.TryGetProperty("paging", out var paging) ? Str(paging, "next") : null;
        }
        return pages;
    }

    public async Task SubscribePageToWebhooksAsync(string pageId, string pageToken, CancellationToken ct) =>
        await PostFormAsync($"{Graph}{E(pageId)}/subscribed_apps", pageToken,
            new() { ["subscribed_fields"] = "messages,messaging_postbacks" }, ct);

    public async Task<IReadOnlyList<AdAccountInfo>> GetAdAccountsAsync(string userToken, CancellationToken ct)
    {
        var root = await GetAsync($"{Graph}me/adaccounts?fields=account_id,name,currency&limit=100", userToken, ct);
        var list = new List<AdAccountInfo>();
        if (root.TryGetProperty("data", out var data))
            foreach (var a in data.EnumerateArray())
                if (Str(a, "account_id") is { } id)
                    list.Add(new AdAccountInfo("act_" + id, Str(a, "name") ?? id, Str(a, "currency")));
        return list;
    }

    // ── Publishing ─────────────────────────────────────────────────────────

    public async Task<PublishStep> PublishFacebookAsync(string pageId, string pageToken, PublishRequest post, CancellationToken ct)
    {
        switch (post.MediaType)
        {
            case SocialMediaType.Image:
            {
                // Photo posts have no link card, so the link goes in the text.
                var root = await PostFormAsync($"{Graph}{E(pageId)}/photos", pageToken, new()
                {
                    ["url"] = post.MediaUrl!,
                    ["message"] = CaptionWithLink(post),
                }, ct);
                var id = Str(root, "post_id") ?? Str(root, "id") ?? throw new SocialApiException("Facebook did not return a post id.");
                return PublishStep.Done(id, $"https://www.facebook.com/{id}");
            }
            case SocialMediaType.Video:
            {
                var root = await PostFormAsync($"{GraphVideo}{E(pageId)}/videos", pageToken, new()
                {
                    ["file_url"] = post.MediaUrl!,
                    ["description"] = CaptionWithLink(post),
                }, ct);
                var id = Str(root, "id") ?? throw new SocialApiException("Facebook did not return a video id.");
                return PublishStep.Done(id, $"https://www.facebook.com/{pageId}/videos/{id}");
            }
            default:
            {
                var form = new Dictionary<string, string> { ["message"] = post.Caption };
                if (!string.IsNullOrWhiteSpace(post.LinkUrl)) form["link"] = post.LinkUrl!;
                var root = await PostFormAsync($"{Graph}{E(pageId)}/feed", pageToken, form, ct);
                var id = Str(root, "id") ?? throw new SocialApiException("Facebook did not return a post id.");
                return PublishStep.Done(id, $"https://www.facebook.com/{id}");
            }
        }
    }

    public async Task<PublishStep> StartInstagramAsync(string igUserId, string pageToken, PublishRequest post, CancellationToken ct)
    {
        var form = new Dictionary<string, string> { ["caption"] = CaptionWithLink(post) };
        if (post.MediaType == SocialMediaType.Video)
        {
            form["media_type"] = "REELS";
            form["video_url"] = post.MediaUrl!;
            form["share_to_feed"] = "true";
        }
        else
        {
            form["image_url"] = post.MediaUrl!;
        }

        var root = await PostFormAsync($"{Graph}{E(igUserId)}/media", pageToken, form, ct);
        var containerId = Str(root, "id") ?? throw new SocialApiException("Instagram did not return a media container id.");

        // Images are normally ready at once; give them one look before
        // handing the rest to the worker's next tick.
        return await ContinueInstagramAsync(igUserId, pageToken, containerId, ct);
    }

    public async Task<PublishStep> ContinueInstagramAsync(string igUserId, string pageToken, string containerId, CancellationToken ct)
    {
        var status = await GetAsync($"{Graph}{E(containerId)}?fields=status_code,status", pageToken, ct);
        var code = Str(status, "status_code");
        switch (code)
        {
            case "IN_PROGRESS":
                return PublishStep.Processing(containerId);
            case "ERROR":
            case "EXPIRED":
                throw new SocialApiException($"Instagram could not process the media ({code}): {Str(status, "status") ?? "no detail given"}. " +
                    "Check the file is a public https URL in a supported format (JPEG image; MP4/MOV video, 3-90s for Reels).");
            case "FINISHED":
            case "PUBLISHED":
            default:
                break;
        }

        var published = await PostFormAsync($"{Graph}{E(igUserId)}/media_publish", pageToken,
            new() { ["creation_id"] = containerId }, ct);
        var mediaId = Str(published, "id") ?? throw new SocialApiException("Instagram did not return a media id.");

        string? permalink = null;
        try
        {
            var media = await GetAsync($"{Graph}{E(mediaId)}?fields=permalink", pageToken, ct);
            permalink = Str(media, "permalink");
        }
        catch (SocialApiException)
        {
            // The post is live; a missing permalink is cosmetic.
        }
        return PublishStep.Done(mediaId, permalink);
    }

    public async Task<(string Name, string? Handle, string? PictureUrl)> GetProfileAsync(string id, string token, bool instagram, CancellationToken ct)
    {
        if (instagram)
        {
            var ig = await GetAsync($"{Graph}{E(id)}?fields=username,name,profile_picture_url", token, ct);
            var username = Str(ig, "username");
            return (Str(ig, "name") ?? username ?? id, username, Str(ig, "profile_picture_url"));
        }
        var page = await GetAsync($"{Graph}{E(id)}?fields=name,username,picture{{url}}", token, ct);
        string? picture = page.TryGetProperty("picture", out var pic) && pic.TryGetProperty("data", out var pd) ? Str(pd, "url") : null;
        return (Str(page, "name") ?? id, Str(page, "username"), picture);
    }

    // ── Messaging ──────────────────────────────────────────────────────────

    public async Task<string?> SendMessageAsync(string pageId, string pageToken, string recipientId, string text, CancellationToken ct)
    {
        var body = new
        {
            recipient = new { id = recipientId },
            messaging_type = "RESPONSE",
            message = new { text },
        };
        var root = await PostJsonAsync($"{Graph}{E(pageId)}/messages", pageToken, body, ct);
        return Str(root, "message_id");
    }

    public async Task<string?> GetParticipantNameAsync(string participantId, string pageToken, bool instagram, CancellationToken ct)
    {
        try
        {
            var fields = instagram ? "name,username" : "first_name,last_name,name";
            var root = await GetAsync($"{Graph}{E(participantId)}?fields={fields}", pageToken, ct);
            var name = Str(root, "name");
            if (string.IsNullOrWhiteSpace(name))
                name = string.Join(' ', new[] { Str(root, "first_name"), Str(root, "last_name") }.Where(s => !string.IsNullOrWhiteSpace(s)));
            if (string.IsNullOrWhiteSpace(name) && instagram && Str(root, "username") is { } u) name = "@" + u;
            return string.IsNullOrWhiteSpace(name) ? null : name;
        }
        catch (SocialApiException)
        {
            return null;
        }
    }

    // ── Ads ────────────────────────────────────────────────────────────────

    public async Task SendConversionAsync(string pixelId, string accessToken, string? testEventCode, object serverEvent, CancellationToken ct)
    {
        var payload = new Dictionary<string, object> { ["data"] = new[] { serverEvent } };
        if (!string.IsNullOrWhiteSpace(testEventCode)) payload["test_event_code"] = testEventCode!;
        var root = await PostJsonAsync($"{Graph}{E(pixelId)}/events", accessToken, payload, ct);
        if (root.TryGetProperty("events_received", out var received) && received.TryGetInt32(out var n) && n < 1)
            throw new SocialApiException("Meta accepted the request but received no events.");
    }

    public async Task<IReadOnlyList<CampaignSpend>> GetCampaignSpendAsync(string adAccountId, string accessToken, DateOnly since, DateOnly until, CancellationToken ct)
    {
        var account = adAccountId.StartsWith("act_", StringComparison.Ordinal) ? adAccountId : "act_" + adAccountId;
        var range = JsonSerializer.Serialize(new { since = since.ToString("yyyy-MM-dd"), until = until.ToString("yyyy-MM-dd") });
        string? url = $"{Graph}{E(account)}/insights?level=campaign&fields=campaign_id,campaign_name,spend,impressions,clicks&time_range={E(range)}&limit=500";
        var rows = new List<CampaignSpend>();
        for (var guard = 0; url != null && guard < 10; guard++)
        {
            var root = await GetAsync(url, accessToken, ct);
            if (root.TryGetProperty("data", out var data))
                foreach (var r in data.EnumerateArray())
                    rows.Add(new CampaignSpend(
                        Str(r, "campaign_id") ?? "",
                        Str(r, "campaign_name") ?? "(unnamed)",
                        Dec(Str(r, "spend")),
                        (long)Dec(Str(r, "impressions")),
                        (long)Dec(Str(r, "clicks"))));
            url = root.TryGetProperty("paging", out var paging) ? Str(paging, "next") : null;
        }
        return rows;
    }

    // ── Webhook signature ──────────────────────────────────────────────────

    /// X-Hub-Signature-256: "sha256=" + hex(HMAC-SHA256(appSecret, raw body)).
    public static bool VerifySignature(byte[] body, string? header, string? appSecret)
    {
        if (string.IsNullOrWhiteSpace(appSecret) || string.IsNullOrWhiteSpace(header)) return false;
        const string prefix = "sha256=";
        if (!header.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return false;
        byte[] given;
        try { given = Convert.FromHexString(header[prefix.Length..].Trim()); }
        catch (FormatException) { return false; }
        var expected = HMACSHA256.HashData(Encoding.UTF8.GetBytes(appSecret), body);
        return CryptographicOperations.FixedTimeEquals(given, expected);
    }

    // ── Plumbing ───────────────────────────────────────────────────────────

    private static string CaptionWithLink(PublishRequest post) =>
        string.IsNullOrWhiteSpace(post.LinkUrl) || post.Caption.Contains(post.LinkUrl!, StringComparison.Ordinal)
            ? post.Caption
            : $"{post.Caption.TrimEnd()}\n\n{post.LinkUrl}";

    private void RequireApp()
    {
        if (!_app.IsConfigured)
            throw new SocialApiException("The Meta app is not configured on this server (Social:Meta:AppId / AppSecret).");
    }

    private Task<JsonElement> GetAsync(string url, string? token, CancellationToken ct)
    {
        var req = new HttpRequestMessage(HttpMethod.Get, url);
        if (token != null) req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return SendAsync(req, ct);
    }

    private Task<JsonElement> PostFormAsync(string url, string token, Dictionary<string, string> form, CancellationToken ct)
    {
        var req = new HttpRequestMessage(HttpMethod.Post, url) { Content = new FormUrlEncodedContent(form) };
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return SendAsync(req, ct);
    }

    private Task<JsonElement> PostJsonAsync(string url, string token, object body, CancellationToken ct)
    {
        var req = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json"),
        };
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return SendAsync(req, ct);
    }

    private async Task<JsonElement> SendAsync(HttpRequestMessage req, CancellationToken ct)
    {
        HttpResponseMessage res;
        try
        {
            res = await _http.SendAsync(req, ct);
        }
        catch (HttpRequestException e)
        {
            throw new SocialApiException("Could not reach Meta: " + e.Message, transient: true, inner: e);
        }
        catch (TaskCanceledException e) when (!ct.IsCancellationRequested)
        {
            throw new SocialApiException("Meta did not answer in time.", transient: true, inner: e);
        }
        finally
        {
            req.Dispose();
        }

        using (res)
        {
            var body = await res.Content.ReadAsStringAsync(ct);
            JsonElement root;
            try
            {
                using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(body) ? "{}" : body);
                root = doc.RootElement.Clone();
            }
            catch (JsonException)
            {
                throw new SocialApiException($"Meta returned HTTP {(int)res.StatusCode} with an unreadable body.",
                    transient: (int)res.StatusCode >= 500);
            }

            if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("error", out var err))
                throw FromMetaError(err, res.StatusCode);
            if (!res.IsSuccessStatusCode)
                throw new SocialApiException($"Meta returned HTTP {(int)res.StatusCode}.", transient: (int)res.StatusCode >= 500);
            return root;
        }
    }

    /// https://developers.facebook.com/docs/graph-api/guides/error-handling
    private static SocialApiException FromMetaError(JsonElement err, HttpStatusCode status)
    {
        int? code = err.TryGetProperty("code", out var c) && c.TryGetInt32(out var ci) ? ci : null;
        var message = Str(err, "error_user_msg") ?? Str(err, "message") ?? "Meta rejected the request.";
        var transientFlag = err.TryGetProperty("is_transient", out var t) && t.ValueKind == JsonValueKind.True;
        // 190 = token expired/revoked, 102 = session invalid. Permission
        // errors (10, 200-299) are permanent but not a dead token.
        var tokenInvalid = code is 190 or 102;
        var transient = transientFlag || code is 1 or 2 or 4 or 17 or 32 or 341 or 368 or 613 or 80001 or 80002 or 80006 || (int)status >= 500;
        if (code is 10 or (>= 200 and <= 299))
            message += " (the account has not granted this permission - reconnect and approve every requested permission)";
        return new SocialApiException(message, transient, tokenInvalid, code);
    }

    private static string E(string value) => Uri.EscapeDataString(value);

    private static string? Str(JsonElement el, string name) =>
        el.ValueKind == JsonValueKind.Object && el.TryGetProperty(name, out var v)
            ? v.ValueKind switch
            {
                JsonValueKind.String => v.GetString(),
                JsonValueKind.Number => v.GetRawText(),
                _ => null,
            }
            : null;

    private static decimal Dec(string? value) =>
        decimal.TryParse(value, NumberStyles.Any, CultureInfo.InvariantCulture, out var d) ? d : 0m;
}
