using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using SmeBackend.Services.Marketing;

namespace SmeBackend.Controllers.Marketing;

/// Meta's webhook for Messenger and Instagram messaging.
///
/// Register in the Meta App Dashboard (Webhooks → Page and Instagram) with
/// this URL and Social:Meta:WebhookVerifyToken. Every POST is authenticated
/// by X-Hub-Signature-256 against the app secret before a byte of it is
/// trusted; an unsigned or mis-signed body is refused, not parsed.
[ApiController]
[Route("api/social/webhooks")]
[AllowAnonymous]
[ApiExplorerSettings(IgnoreApi = true)]
public class SocialWebhooksController(
    IOptions<SocialOptions> options,
    MetaWebhookProcessor processor,
    ILogger<SocialWebhooksController> logger) : ControllerBase
{
    private const int MaxBodyBytes = 1024 * 1024;

    /// Subscription handshake.
    [HttpGet("meta")]
    public IActionResult Verify(
        [FromQuery(Name = "hub.mode")] string? mode,
        [FromQuery(Name = "hub.verify_token")] string? token,
        [FromQuery(Name = "hub.challenge")] string? challenge)
    {
        var expected = options.Value.Meta.WebhookVerifyToken;
        if (mode != "subscribe" || string.IsNullOrEmpty(expected) || string.IsNullOrEmpty(token) || challenge == null)
            return StatusCode(StatusCodes.Status403Forbidden);

        var a = Encoding.UTF8.GetBytes(token);
        var b = Encoding.UTF8.GetBytes(expected);
        if (a.Length != b.Length || !CryptographicOperations.FixedTimeEquals(a, b))
            return StatusCode(StatusCodes.Status403Forbidden);

        return Content(challenge, "text/plain");
    }

    [HttpPost("meta")]
    [RequestSizeLimit(MaxBodyBytes)]
    public async Task<IActionResult> Receive(CancellationToken ct)
    {
        byte[] body;
        using (var buffer = new MemoryStream())
        {
            await Request.Body.CopyToAsync(buffer, ct);
            body = buffer.ToArray();
        }

        if (!MetaGraphClient.VerifySignature(body, Request.Headers["X-Hub-Signature-256"], options.Value.Meta.AppSecret))
        {
            logger.LogWarning("Rejected Meta webhook with a missing or invalid signature");
            return Unauthorized();
        }

        JsonElement root;
        try
        {
            using var doc = JsonDocument.Parse(body);
            root = doc.RootElement.Clone();
        }
        catch (JsonException)
        {
            return BadRequest();
        }

        // A failure here returns 500 so Meta redelivers; message ids make
        // the redelivery a no-op for anything already stored.
        var recorded = await processor.ProcessAsync(root, DateTime.UtcNow, ct);
        logger.LogInformation("Meta webhook recorded {Count} message(s)", recorded);
        return Ok();
    }
}
