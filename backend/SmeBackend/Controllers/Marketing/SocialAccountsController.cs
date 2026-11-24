using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SmeBackend.Data;
using SmeBackend.Middleware;
using SmeBackend.Models.Marketing;
using SmeBackend.Services;
using SmeBackend.Services.Marketing;

namespace SmeBackend.Controllers.Marketing;

/// Connecting Facebook Pages, Instagram professional accounts and TikTok
/// accounts to a business.
///
/// Meta: one "Continue with Facebook" round trip lists every Page the user
/// manages and the Instagram account linked to each, and stores one row per
/// Page and per Instagram account with the Page's (non-expiring) token.
/// TikTok: one round trip per TikTok account.
[ApiController]
[Route("api/social")]
public class SocialAccountsController : MarketingControllerBase
{
    private readonly AppDbContext _db;
    private readonly IMetaGraphClient _meta;
    private readonly ITikTokClient _tikTok;
    private readonly IOAuthStateProtector _state;
    private readonly IPlatformSecretProtector _protector;
    private readonly ISocialTokenService _tokens;
    private readonly SocialOptions _options;
    private readonly string[] _allowedOrigins;
    private readonly ILogger<SocialAccountsController> _logger;

    public SocialAccountsController(
        AppDbContext db,
        IMetaGraphClient meta,
        ITikTokClient tikTok,
        IOAuthStateProtector state,
        IPlatformSecretProtector protector,
        ISocialTokenService tokens,
        IOptions<SocialOptions> options,
        IConfiguration config,
        ILogger<SocialAccountsController> logger)
    {
        _db = db;
        _meta = meta;
        _tikTok = tikTok;
        _state = state;
        _protector = protector;
        _tokens = tokens;
        _options = options.Value;
        _allowedOrigins = config.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? new[] { "https://se-3090-se-002.vercel.app" };
        _logger = logger;
    }

    /// <summary>Which platforms this server can connect to, and the URLs to register with Meta/TikTok.</summary>
    [HttpGet("status")]
    [Authorize(Roles = "Admin,Manager")]
    public IActionResult Status() => Ok(new
    {
        meta = new { configured = _options.Meta.IsConfigured, redirectUri = RedirectUri("meta"), scopes = _options.Meta.Scopes.Split(',') },
        tiktok = new { configured = _options.TikTok.IsConfigured, redirectUri = RedirectUri("tiktok"), scopes = _options.TikTok.Scopes.Split(',') },
        webhook = new
        {
            url = $"{ApiBase()}/api/social/webhooks/meta",
            verifyTokenConfigured = !string.IsNullOrWhiteSpace(_options.Meta.WebhookVerifyToken),
        },
    });

    /// <summary>The business's connected social accounts.</summary>
    [HttpGet("accounts")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> List()
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var accounts = await _db.SocialAccounts.AsNoTracking()
            .Where(a => a.TenantId == tenantId && a.Status != SocialAccountStatus.Disconnected)
            .OrderBy(a => a.Platform).ThenBy(a => a.DisplayName)
            .ToListAsync();
        return Ok(accounts.Select(ToDto));
    }

    public sealed class ConnectRequest
    {
        /// The web app's origin, to come back to after the provider's
        /// consent screen. Must be one of the API's allowed CORS origins.
        [Required, MaxLength(200)]
        public string ReturnOrigin { get; set; } = string.Empty;
    }

    /// <summary>Starts the OAuth flow: returns the provider URL to send the browser to.</summary>
    [HttpPost("accounts/connect/{provider}")]
    [Authorize(Roles = "Admin,Manager")]
    public IActionResult Connect(string provider, [FromBody] ConnectRequest body)
    {
        if (TenantId is not { } tenantId || UserId is not { } userId) return MissingTenant();
        provider = provider.ToLowerInvariant();

        var origin = body.ReturnOrigin.TrimEnd('/');
        if (!CorsOrigins.IsAllowed(origin, _allowedOrigins))
            return BadRequest(new { message = "That return address is not an allowed origin for this API." });

        switch (provider)
        {
            case "meta":
                if (!_options.Meta.IsConfigured)
                    return Conflict(new { message = "Facebook/Instagram is not set up on this server yet. Set Social__Meta__AppId and Social__Meta__AppSecret, or add a sandbox account to try the features." });
                return Ok(new { url = _meta.BuildAuthorizeUrl(RedirectUri("meta"), _state.Create(tenantId, userId, "meta", origin)) });
            case "tiktok":
                if (!_options.TikTok.IsConfigured)
                    return Conflict(new { message = "TikTok is not set up on this server yet. Set Social__TikTok__ClientKey and Social__TikTok__ClientSecret, or add a sandbox account to try the features." });
                return Ok(new { url = _tikTok.BuildAuthorizeUrl(RedirectUri("tiktok"), _state.Create(tenantId, userId, "tiktok", origin)) });
            default:
                return BadRequest(new { message = "provider must be meta or tiktok." });
        }
    }

    /// <summary>OAuth redirect target. Anonymous: the tenant travels in the signed state.</summary>
    [HttpGet("oauth/{provider}/callback")]
    [AllowAnonymous]
    [ApiExplorerSettings(IgnoreApi = true)]
    public async Task<IActionResult> Callback(
        string provider,
        [FromQuery] string? code,
        [FromQuery] string? state,
        [FromQuery] string? error,
        [FromQuery(Name = "error_description")] string? errorDescription,
        [FromQuery(Name = "error_reason")] string? errorReason,
        CancellationToken ct)
    {
        provider = provider.ToLowerInvariant();
        var parsed = _state.Consume(state, provider);
        if (parsed == null)
            return Content("This sign-in link has expired or was already used. Close this tab and press Connect again.", "text/plain");

        string Back(string query) => $"{parsed.ReturnOrigin}/social?{query}";

        if (!string.IsNullOrEmpty(error) || string.IsNullOrEmpty(code))
        {
            var reason = errorReason == "user_denied" || error == "access_denied"
                ? "Connection cancelled."
                : errorDescription ?? error ?? "The provider did not return an authorisation code.";
            return Redirect(Back("error=" + Uri.EscapeDataString(reason)));
        }

        try
        {
            var count = provider switch
            {
                "meta" => await CompleteMetaAsync(parsed, code, ct),
                "tiktok" => await CompleteTikTokAsync(parsed, code, ct),
                _ => throw new SocialApiException("Unknown provider."),
            };
            return Redirect(Back($"connected={provider}&count={count}"));
        }
        catch (SocialApiException e)
        {
            _logger.LogWarning(e, "Social OAuth callback for {Provider} failed", provider);
            return Redirect(Back("error=" + Uri.EscapeDataString(e.Message)));
        }
    }

    private async Task<int> CompleteMetaAsync(OAuthState state, string code, CancellationToken ct)
    {
        var user = await _meta.ExchangeCodeAsync(code, RedirectUri("meta"), ct);
        var pages = await _meta.GetPagesAsync(user.AccessToken, ct);
        if (pages.Count == 0)
            throw new SocialApiException("No Facebook Pages were shared. Connect again and tick at least one Page (and its Instagram account) on the consent screen.");

        var now = DateTime.UtcNow;
        var count = 0;
        foreach (var page in pages)
        {
            var token = _protector.Protect(page.AccessToken);
            var fb = await UpsertAsync(state.TenantId, SocialPlatform.Facebook, page.Id, now);
            fb.DisplayName = Clip(page.Name, 200);
            fb.AvatarUrl = page.PictureUrl;
            fb.AccessTokenEncrypted = token;
            fb.AccessTokenExpiresAt = null;
            fb.Scopes = Clip(_options.Meta.Scopes, 1000);
            fb.ConnectedByUserId = state.UserId;
            count++;

            if (page.Instagram is { } ig)
            {
                var insta = await UpsertAsync(state.TenantId, SocialPlatform.Instagram, ig.Id, now);
                insta.ParentExternalId = page.Id;
                insta.DisplayName = Clip(ig.Username ?? page.Name, 200);
                insta.Handle = ig.Username;
                insta.AvatarUrl = ig.ProfilePictureUrl;
                insta.AccessTokenEncrypted = token;
                insta.AccessTokenExpiresAt = null;
                insta.Scopes = fb.Scopes;
                insta.ConnectedByUserId = state.UserId;
                count++;
            }

            // DMs only reach us once the Page is subscribed to the app.
            try { await _meta.SubscribePageToWebhooksAsync(page.Id, page.AccessToken, ct); }
            catch (SocialApiException e) { _logger.LogWarning(e, "Could not subscribe page {PageId} to webhooks", page.Id); }
        }

        // The same consent covers ads_read, so the campaign report can read
        // spend without a second login. The ad account itself is chosen in
        // Ads settings.
        var settings = await _db.MarketingSettings.IgnoreQueryFilters().FirstOrDefaultAsync(s => s.TenantId == state.TenantId, ct);
        if (settings == null)
        {
            settings = new MarketingSettings { TenantId = state.TenantId };
            _db.MarketingSettings.Add(settings);
        }
        settings.MetaAdsTokenEncrypted = _protector.Protect(user.AccessToken);
        settings.MetaAdsTokenExpiresAt = user.ExpiresAt;
        settings.UpdatedAt = now;

        await _db.SaveChangesAsync(ct);
        return count;
    }

    private async Task<int> CompleteTikTokAsync(OAuthState state, string code, CancellationToken ct)
    {
        var token = await _tikTok.ExchangeCodeAsync(code, RedirectUri("tiktok"), ct);
        var profile = await _tikTok.GetUserAsync(token.AccessToken, ct);
        var openId = string.IsNullOrEmpty(profile.OpenId) ? token.OpenId : profile.OpenId;
        if (string.IsNullOrEmpty(openId)) throw new SocialApiException("TikTok did not identify the account.");

        var now = DateTime.UtcNow;
        var account = await UpsertAsync(state.TenantId, SocialPlatform.TikTok, openId, now);
        account.DisplayName = Clip(profile.DisplayName, 200);
        account.Handle = profile.Username;
        account.AvatarUrl = profile.AvatarUrl;
        account.AccessTokenEncrypted = _protector.Protect(token.AccessToken);
        account.AccessTokenExpiresAt = token.ExpiresAt;
        account.RefreshTokenEncrypted = token.RefreshToken != null ? _protector.Protect(token.RefreshToken) : null;
        account.RefreshTokenExpiresAt = token.RefreshExpiresAt;
        account.Scopes = token.Scope != null ? Clip(token.Scope, 1000) : null;
        account.ConnectedByUserId = state.UserId;

        await _db.SaveChangesAsync(ct);
        return 1;
    }

    private async Task<SocialAccount> UpsertAsync(Guid tenantId, string platform, string externalId, DateTime now)
    {
        var account = _db.SocialAccounts.Local.FirstOrDefault(a => a.TenantId == tenantId && a.Platform == platform && a.ExternalId == externalId)
            ?? await _db.SocialAccounts.IgnoreQueryFilters()
                .FirstOrDefaultAsync(a => a.TenantId == tenantId && a.Platform == platform && a.ExternalId == externalId);
        if (account == null)
        {
            account = new SocialAccount { TenantId = tenantId, Platform = platform, ExternalId = externalId };
            _db.SocialAccounts.Add(account);
        }
        account.Status = SocialAccountStatus.Connected;
        account.IsSandbox = false;
        account.LastError = null;
        account.LastSyncedAt = now;
        account.UpdatedAt = now;
        return account;
    }

    public sealed class SandboxRequest
    {
        [Required, MaxLength(20)]
        public string Platform { get; set; } = string.Empty;

        [MaxLength(200)]
        public string? DisplayName { get; set; }
    }

    /// <summary>Adds a sandbox account: everything works except that nothing reaches the real platform.</summary>
    [HttpPost("accounts/sandbox")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> AddSandbox([FromBody] SandboxRequest body)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var platform = SocialPlatform.Normalize(body.Platform);
        if (platform == null) return BadRequest(new { message = "platform must be Facebook, Instagram or TikTok." });

        var existing = await _db.SocialAccounts.CountAsync(a => a.TenantId == tenantId && a.IsSandbox && a.Status != SocialAccountStatus.Disconnected);
        if (existing >= 6) return BadRequest(new { message = "You already have six sandbox accounts." });

        var name = string.IsNullOrWhiteSpace(body.DisplayName) ? $"Sandbox {platform}" : body.DisplayName.Trim();
        var account = new SocialAccount
        {
            TenantId = tenantId,
            Platform = platform,
            ExternalId = "sandbox-" + Guid.NewGuid().ToString("N")[..12],
            DisplayName = Clip(name, 200),
            Handle = platform == SocialPlatform.Facebook ? null : "sandbox." + platform.ToLowerInvariant(),
            IsSandbox = true,
            Status = SocialAccountStatus.Connected,
            ConnectedByUserId = UserId,
            LastSyncedAt = DateTime.UtcNow,
        };
        _db.SocialAccounts.Add(account);
        await _db.SaveChangesAsync();
        return Ok(ToDto(account));
    }

    public sealed class UpdateAccountRequest
    {
        /// TikTok: PUBLIC_TO_EVERYONE | MUTUAL_FOLLOW_FRIENDS | FOLLOWER_OF_CREATOR | SELF_ONLY
        [MaxLength(40)]
        public string? DefaultPrivacy { get; set; }
    }

    private static readonly HashSet<string> TikTokPrivacy = new() { "PUBLIC_TO_EVERYONE", "MUTUAL_FOLLOW_FRIENDS", "FOLLOWER_OF_CREATOR", "SELF_ONLY" };

    /// <summary>Updates per-account publishing preferences.</summary>
    [HttpPatch("accounts/{id:guid}")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateAccountRequest body)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var account = await _db.SocialAccounts.FirstOrDefaultAsync(a => a.Id == id && a.TenantId == tenantId && a.Status != SocialAccountStatus.Disconnected);
        if (account == null) return NotFound(new { message = "Account not found." });

        if (body.DefaultPrivacy != null)
        {
            if (account.Platform != SocialPlatform.TikTok) return BadRequest(new { message = "Privacy level only applies to TikTok accounts." });
            if (!TikTokPrivacy.Contains(body.DefaultPrivacy)) return BadRequest(new { message = "Unknown TikTok privacy level." });
            account.DefaultPrivacy = body.DefaultPrivacy;
        }
        account.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(ToDto(account));
    }

    /// <summary>Re-reads the account's profile, which also proves its token still works.</summary>
    [HttpPost("accounts/{id:guid}/refresh")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> Refresh(Guid id, CancellationToken ct)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var account = await _db.SocialAccounts.FirstOrDefaultAsync(a => a.Id == id && a.TenantId == tenantId && a.Status != SocialAccountStatus.Disconnected, ct);
        if (account == null) return NotFound(new { message = "Account not found." });

        var now = DateTime.UtcNow;
        if (!account.IsSandbox)
        {
            try
            {
                // A NeedsReconnect account gets one more honest try: the
                // provider may have been down rather than the token dead.
                if (account.Status == SocialAccountStatus.NeedsReconnect && !string.IsNullOrEmpty(account.AccessTokenEncrypted))
                    account.Status = SocialAccountStatus.Connected;

                var token = await _tokens.GetAccessTokenAsync(account, ct);
                if (account.Platform == SocialPlatform.TikTok)
                {
                    var p = await _tikTok.GetUserAsync(token, ct);
                    account.DisplayName = Clip(p.DisplayName, 200);
                    account.Handle = p.Username ?? account.Handle;
                    account.AvatarUrl = p.AvatarUrl;
                }
                else
                {
                    var p = await _meta.GetProfileAsync(account.ExternalId, token, account.Platform == SocialPlatform.Instagram, ct);
                    account.DisplayName = Clip(p.Name, 200);
                    account.Handle = p.Handle ?? account.Handle;
                    account.AvatarUrl = p.PictureUrl ?? account.AvatarUrl;
                }
                account.LastError = null;
            }
            catch (SocialApiException e) when (e.TokenInvalid)
            {
                _tokens.MarkNeedsReconnect(account, e.Message);
            }
            catch (SocialApiException e)
            {
                account.LastError = SocialTokenService.Clip(e.Message, 1000);
            }
        }
        account.LastSyncedAt = now;
        account.UpdatedAt = now;
        await _db.SaveChangesAsync(ct);
        return Ok(ToDto(account));
    }

    /// <summary>Disconnects an account. Its post history is kept; posts still waiting for it are cancelled.</summary>
    [HttpDelete("accounts/{id:guid}")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> Disconnect(Guid id)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var account = await _db.SocialAccounts.FirstOrDefaultAsync(a => a.Id == id && a.TenantId == tenantId && a.Status != SocialAccountStatus.Disconnected);
        if (account == null) return NotFound(new { message = "Account not found." });

        var now = DateTime.UtcNow;
        account.Status = SocialAccountStatus.Disconnected;
        account.AccessTokenEncrypted = null;
        account.RefreshTokenEncrypted = null;
        account.AccessTokenExpiresAt = null;
        account.RefreshTokenExpiresAt = null;
        account.LastError = null;
        account.UpdatedAt = now;

        var waiting = await _db.SocialPostTargets
            .Include(t => t.Post!).ThenInclude(p => p.Targets)
            .Where(t => t.SocialAccountId == id && (t.Status == SocialTargetStatus.Pending || t.Status == SocialTargetStatus.Processing))
            .ToListAsync();
        foreach (var t in waiting)
        {
            t.Status = SocialTargetStatus.Cancelled;
            t.Error = "The account was disconnected.";
            t.NextAttemptAt = null;
            t.UpdatedAt = now;
            t.Post!.Status = SocialPostRules.Rollup(t.Post);
        }

        await _db.SaveChangesAsync();
        return NoContent();
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private string ApiBase() =>
        (string.IsNullOrWhiteSpace(_options.PublicApiBaseUrl) ? $"{Request.Scheme}://{Request.Host}" : _options.PublicApiBaseUrl!).TrimEnd('/');

    private string RedirectUri(string provider) => $"{ApiBase()}/api/social/oauth/{provider}/callback";

    private static string Clip(string value, int max) => value.Length <= max ? value : value[..max];

    internal static object ToDto(SocialAccount a) => new
    {
        id = a.Id,
        platform = a.Platform,
        externalId = a.ExternalId,
        parentExternalId = a.ParentExternalId,
        displayName = a.DisplayName,
        handle = a.Handle,
        avatarUrl = a.AvatarUrl,
        status = a.Status,
        lastError = a.LastError,
        isSandbox = a.IsSandbox,
        defaultPrivacy = a.DefaultPrivacy,
        tokenExpiresAt = a.AccessTokenExpiresAt,
        lastSyncedAt = a.LastSyncedAt,
        createdAt = a.CreatedAt,
        // Instagram has no clickable feed links, TikTok needs media; the
        // composer uses these to warn before the user hits Publish.
        canMessage = a.Platform != SocialPlatform.TikTok,
    };
}
