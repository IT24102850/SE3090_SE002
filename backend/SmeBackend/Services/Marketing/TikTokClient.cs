using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using SmeBackend.Models.Marketing;

namespace SmeBackend.Services.Marketing;

public sealed record TikTokToken(string AccessToken, DateTime ExpiresAt, string? RefreshToken, DateTime? RefreshExpiresAt, string OpenId, string? Scope);
public sealed record TikTokUser(string OpenId, string DisplayName, string? Username, string? AvatarUrl);

public interface ITikTokClient
{
    string BuildAuthorizeUrl(string redirectUri, string state);
    Task<TikTokToken> ExchangeCodeAsync(string code, string redirectUri, CancellationToken ct);
    Task<TikTokToken> RefreshAsync(string refreshToken, CancellationToken ct);
    Task<TikTokUser> GetUserAsync(string accessToken, CancellationToken ct);

    Task<PublishStep> StartPublishAsync(string accessToken, PublishRequest post, string? preferredPrivacy, CancellationToken ct);
    Task<PublishStep> ContinuePublishAsync(string accessToken, string publishId, string? handle, CancellationToken ct);

    Task SendEventAsync(string pixelCode, string accessToken, string? testEventCode, object eventData, CancellationToken ct);
    Task<IReadOnlyList<CampaignSpend>> GetCampaignSpendAsync(string advertiserId, string accessToken, DateOnly since, DateOnly until, CancellationToken ct);
}

/// TikTok is two separate developer products with two hosts and two auth
/// styles: Login Kit + Content Posting (open.tiktokapis.com, OAuth bearer
/// tokens per creator) and TikTok for Business (business-api.tiktok.com,
/// an Access-Token header) for the Events API and ad reporting. Both live
/// here so the rest of the code has one place to look.
public sealed class TikTokClient : ITikTokClient
{
    public const string ClientName = "social-tiktok";

    private const string Open = "https://open.tiktokapis.com/v2/";
    private const string Business = "https://business-api.tiktok.com/open_api/v1.3/";

    private readonly HttpClient _http;
    private readonly TikTokAppOptions _app;

    public TikTokClient(IHttpClientFactory factory, IOptions<SocialOptions> options)
    {
        _http = factory.CreateClient(ClientName);
        _app = options.Value.TikTok;
    }

    // ── OAuth ──────────────────────────────────────────────────────────────

    public string BuildAuthorizeUrl(string redirectUri, string state) =>
        "https://www.tiktok.com/v2/auth/authorize/" +
        $"?client_key={E(_app.ClientKey ?? "")}" +
        $"&scope={E(_app.Scopes)}" +
        "&response_type=code" +
        $"&redirect_uri={E(redirectUri)}" +
        $"&state={E(state)}";

    public Task<TikTokToken> ExchangeCodeAsync(string code, string redirectUri, CancellationToken ct) =>
        TokenAsync(new()
        {
            ["client_key"] = _app.ClientKey ?? "",
            ["client_secret"] = _app.ClientSecret ?? "",
            ["code"] = code,
            ["grant_type"] = "authorization_code",
            ["redirect_uri"] = redirectUri,
        }, ct);

    public Task<TikTokToken> RefreshAsync(string refreshToken, CancellationToken ct) =>
        TokenAsync(new()
        {
            ["client_key"] = _app.ClientKey ?? "",
            ["client_secret"] = _app.ClientSecret ?? "",
            ["grant_type"] = "refresh_token",
            ["refresh_token"] = refreshToken,
        }, ct);

    private async Task<TikTokToken> TokenAsync(Dictionary<string, string> form, CancellationToken ct)
    {
        if (!_app.IsConfigured)
            throw new SocialApiException("The TikTok app is not configured on this server (Social:TikTok:ClientKey / ClientSecret).");

        var req = new HttpRequestMessage(HttpMethod.Post, Open + "oauth/token/") { Content = new FormUrlEncodedContent(form) };
        var root = await SendAsync(req, ct, checkOpenError: false);

        // The token endpoint reports errors as top-level strings, not the
        // {error:{code}} envelope the rest of the Open API uses.
        if (Str(root, "error") is { Length: > 0 } error)
            throw new SocialApiException($"TikTok refused the token request: {Str(root, "error_description") ?? error}",
                tokenInvalid: error is "invalid_grant" or "invalid_request");

        var token = Str(root, "access_token") ?? throw new SocialApiException("TikTok did not return an access token.");
        var now = DateTime.UtcNow;
        return new TikTokToken(
            token,
            now.AddSeconds(Long(root, "expires_in") ?? 86400),
            Str(root, "refresh_token"),
            Long(root, "refresh_expires_in") is { } r ? now.AddSeconds(r) : null,
            Str(root, "open_id") ?? "",
            Str(root, "scope"));
    }

    public async Task<TikTokUser> GetUserAsync(string accessToken, CancellationToken ct)
    {
        var req = new HttpRequestMessage(HttpMethod.Get, Open + "user/info/?fields=open_id,display_name,avatar_url,username");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        var root = await SendAsync(req, ct);
        var user = root.TryGetProperty("data", out var d) && d.TryGetProperty("user", out var u) ? u : default;
        if (user.ValueKind != JsonValueKind.Object) throw new SocialApiException("TikTok did not return the account's profile.");
        var openId = Str(user, "open_id") ?? "";
        return new TikTokUser(openId, Str(user, "display_name") ?? "TikTok account", Str(user, "username"), Str(user, "avatar_url"));
    }

    // ── Content Posting API ────────────────────────────────────────────────

    public async Task<PublishStep> StartPublishAsync(string accessToken, PublishRequest post, string? preferredPrivacy, CancellationToken ct)
    {
        var privacy = await ChoosePrivacyAsync(accessToken, preferredPrivacy, ct);
        var caption = string.IsNullOrWhiteSpace(post.LinkUrl) || post.Caption.Contains(post.LinkUrl!, StringComparison.Ordinal)
            ? post.Caption
            : $"{post.Caption.TrimEnd()}\n\n{post.LinkUrl}";

        object body;
        string endpoint;
        if (post.MediaType == SocialMediaType.Video)
        {
            endpoint = "post/publish/video/init/";
            body = new
            {
                post_info = new { title = Truncate(caption, 2200), privacy_level = privacy, disable_comment = false, disable_duet = false, disable_stitch = false },
                source_info = new { source = "PULL_FROM_URL", video_url = post.MediaUrl },
            };
        }
        else
        {
            endpoint = "post/publish/content/init/";
            body = new
            {
                post_info = new { title = Truncate(FirstLine(caption), 90), description = Truncate(caption, 4000), privacy_level = privacy, disable_comment = false, auto_add_music = true },
                source_info = new { source = "PULL_FROM_URL", photo_cover_index = 0, photo_images = new[] { post.MediaUrl } },
                post_mode = "DIRECT_POST",
                media_type = "PHOTO",
            };
        }

        var root = await PostOpenJsonAsync(endpoint, accessToken, body, ct);
        var publishId = root.TryGetProperty("data", out var data) ? Str(data, "publish_id") : null;
        if (publishId == null) throw new SocialApiException("TikTok did not return a publish id.");
        return PublishStep.Processing(publishId);
    }

    public async Task<PublishStep> ContinuePublishAsync(string accessToken, string publishId, string? handle, CancellationToken ct)
    {
        var root = await PostOpenJsonAsync("post/publish/status/fetch/", accessToken, new { publish_id = publishId }, ct);
        var data = root.TryGetProperty("data", out var d) ? d : default;
        var status = Str(data, "status");
        switch (status)
        {
            case "PUBLISH_COMPLETE":
            {
                string? postId = null;
                if (data.TryGetProperty("publicaly_available_post_id", out var ids) && ids.ValueKind == JsonValueKind.Array)
                    postId = ids.EnumerateArray().Select(i => i.ValueKind == JsonValueKind.Number ? i.GetRawText() : i.GetString()).FirstOrDefault(i => i != null);
                var permalink = postId != null && !string.IsNullOrWhiteSpace(handle)
                    ? $"https://www.tiktok.com/@{handle!.TrimStart('@')}/video/{postId}"
                    : null;
                // A SELF_ONLY post has no public id; it is still published.
                return PublishStep.Done(postId ?? publishId, permalink);
            }
            case "FAILED":
                throw new SocialApiException("TikTok could not publish the post: " + (Str(data, "fail_reason") ?? "no reason given") +
                    ". TikTok pulls media from the URL itself, so the domain must be verified in the TikTok developer portal.");
            default:
                return PublishStep.Processing(publishId);
        }
    }

    /// Unaudited TikTok apps may only post SELF_ONLY; the creator's allowed
    /// options say so, and picking from them avoids a guaranteed rejection.
    private async Task<string> ChoosePrivacyAsync(string accessToken, string? preferred, CancellationToken ct)
    {
        var root = await PostOpenJsonAsync("post/publish/creator_info/query/", accessToken, new { }, ct);
        var options = new List<string>();
        if (root.TryGetProperty("data", out var data) && data.TryGetProperty("privacy_level_options", out var arr) && arr.ValueKind == JsonValueKind.Array)
            options.AddRange(arr.EnumerateArray().Select(o => o.GetString()).Where(o => o != null)!);

        if (preferred != null && options.Contains(preferred)) return preferred;
        if (options.Contains("PUBLIC_TO_EVERYONE")) return "PUBLIC_TO_EVERYONE";
        return options.FirstOrDefault() ?? "SELF_ONLY";
    }

    // ── TikTok for Business ────────────────────────────────────────────────

    public async Task SendEventAsync(string pixelCode, string accessToken, string? testEventCode, object eventData, CancellationToken ct)
    {
        var payload = new Dictionary<string, object>
        {
            ["event_source"] = "web",
            ["event_source_id"] = pixelCode,
            ["data"] = new[] { eventData },
        };
        if (!string.IsNullOrWhiteSpace(testEventCode)) payload["test_event_code"] = testEventCode!;

        var req = new HttpRequestMessage(HttpMethod.Post, Business + "event/track/")
        {
            Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json"),
        };
        req.Headers.Add("Access-Token", accessToken);
        var root = await SendAsync(req, ct, checkOpenError: false);
        ThrowOnBusinessError(root);
    }

    public async Task<IReadOnlyList<CampaignSpend>> GetCampaignSpendAsync(string advertiserId, string accessToken, DateOnly since, DateOnly until, CancellationToken ct)
    {
        var rows = new List<CampaignSpend>();
        var dimensions = E("[\"campaign_id\"]");
        var metrics = E("[\"campaign_name\",\"spend\",\"impressions\",\"clicks\"]");
        for (var page = 1; page <= 10; page++)
        {
            var url = Business + "report/integrated/get/" +
                $"?advertiser_id={E(advertiserId)}&report_type=BASIC&data_level=AUCTION_CAMPAIGN" +
                $"&dimensions={dimensions}&metrics={metrics}" +
                $"&start_date={since:yyyy-MM-dd}&end_date={until:yyyy-MM-dd}&page={page}&page_size=200";
            var req = new HttpRequestMessage(HttpMethod.Get, url);
            req.Headers.Add("Access-Token", accessToken);
            var root = await SendAsync(req, ct, checkOpenError: false);
            ThrowOnBusinessError(root);

            if (!root.TryGetProperty("data", out var data)) break;
            if (data.TryGetProperty("list", out var list))
                foreach (var row in list.EnumerateArray())
                {
                    var dims = row.TryGetProperty("dimensions", out var dm) ? dm : default;
                    var m = row.TryGetProperty("metrics", out var mm) ? mm : default;
                    rows.Add(new CampaignSpend(
                        Str(dims, "campaign_id") ?? "",
                        Str(m, "campaign_name") ?? "(unnamed)",
                        Dec(Str(m, "spend")),
                        (long)Dec(Str(m, "impressions")),
                        (long)Dec(Str(m, "clicks"))));
                }

            var totalPages = data.TryGetProperty("page_info", out var pi) ? Long(pi, "total_page") ?? 1 : 1;
            if (page >= totalPages) break;
        }
        return rows;
    }

    private static void ThrowOnBusinessError(JsonElement root)
    {
        var code = Long(root, "code");
        if (code is null or 0) return;
        var message = Str(root, "message") ?? "TikTok rejected the request.";
        // 40001/40100-40105: auth problems; 40016/51xxx: rate/system.
        throw new SocialApiException($"TikTok: {message} (code {code})",
            transient: code is 40016 or 40100 or >= 50000,
            tokenInvalid: code is 40001 or 40102 or 40104 or 40105,
            providerCode: (int)code);
    }

    // ── Plumbing ───────────────────────────────────────────────────────────

    private Task<JsonElement> PostOpenJsonAsync(string path, string accessToken, object body, CancellationToken ct)
    {
        var req = new HttpRequestMessage(HttpMethod.Post, Open + path)
        {
            Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json"),
        };
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        return SendAsync(req, ct);
    }

    private async Task<JsonElement> SendAsync(HttpRequestMessage req, CancellationToken ct, bool checkOpenError = true)
    {
        HttpResponseMessage res;
        try
        {
            res = await _http.SendAsync(req, ct);
        }
        catch (HttpRequestException e)
        {
            throw new SocialApiException("Could not reach TikTok: " + e.Message, transient: true, inner: e);
        }
        catch (TaskCanceledException e) when (!ct.IsCancellationRequested)
        {
            throw new SocialApiException("TikTok did not answer in time.", transient: true, inner: e);
        }
        finally
        {
            req.Dispose();
        }

        using (res)
        {
            var text = await res.Content.ReadAsStringAsync(ct);
            JsonElement root;
            try
            {
                using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(text) ? "{}" : text);
                root = doc.RootElement.Clone();
            }
            catch (JsonException)
            {
                throw new SocialApiException($"TikTok returned HTTP {(int)res.StatusCode} with an unreadable body.",
                    transient: (int)res.StatusCode >= 500);
            }

            // Open API envelope: { data, error: { code: "ok" | "...", message } }
            if (checkOpenError && root.TryGetProperty("error", out var err) && err.ValueKind == JsonValueKind.Object)
            {
                var code = Str(err, "code");
                if (!string.IsNullOrEmpty(code) && code != "ok")
                {
                    var message = Str(err, "message");
                    throw new SocialApiException(
                        $"TikTok: {(string.IsNullOrWhiteSpace(message) ? code : message)}",
                        transient: code is "rate_limit_exceeded" or "internal_error" || (int)res.StatusCode >= 500,
                        tokenInvalid: code is "access_token_invalid" or "token_not_authorized_for_specified_open_id");
                }
            }

            if (!res.IsSuccessStatusCode && (checkOpenError || (int)res.StatusCode >= 500))
                throw new SocialApiException($"TikTok returned HTTP {(int)res.StatusCode}.", transient: (int)res.StatusCode >= 500,
                    tokenInvalid: (int)res.StatusCode == 401);
            return root;
        }
    }

    private static string FirstLine(string text)
    {
        var line = text.Split('\n', 2)[0].Trim();
        return line.Length == 0 ? "New post" : line;
    }

    private static string Truncate(string text, int max) => text.Length <= max ? text : text[..max];

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

    private static long? Long(JsonElement el, string name) =>
        el.ValueKind == JsonValueKind.Object && el.TryGetProperty(name, out var v)
            ? v.ValueKind == JsonValueKind.Number && v.TryGetInt64(out var n) ? n
            : v.ValueKind == JsonValueKind.String && long.TryParse(v.GetString(), out var s) ? s : null
            : null;

    private static decimal Dec(string? value) =>
        decimal.TryParse(value, NumberStyles.Any, CultureInfo.InvariantCulture, out var d) ? d : 0m;
}
