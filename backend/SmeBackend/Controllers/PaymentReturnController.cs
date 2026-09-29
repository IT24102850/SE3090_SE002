using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace SmeBackend.Controllers;

/// Where a payment gateway sends someone back to after a hosted checkout
/// opened outside the app - which on a phone is always, because the card
/// form runs in the system browser rather than in Flutter.
///
/// The web app handles its own return at /subscription and never reaches
/// here. The mobile app has nowhere of its own to land: a deep link back
/// into the app needs app-link registration on both stores, and without
/// somewhere real to point at, the gateway falls back to a dead URL and the
/// customer's last impression of paying us is a browser error page.
///
/// So this is deliberately a plain, self-contained page with no styling
/// dependencies and nothing to load: it renders the same whether the phone
/// has the app's assets cached or not. It reports what the gateway said and
/// tells the person to go back to the app, which is where the payment is
/// actually confirmed against the provider.
///
/// It asserts nothing about the payment. The query string comes from the
/// gateway's redirect and a customer could type anything into it, so this
/// page never touches the database - it is a signpost, not a receipt.
[ApiController]
[Route("payment-complete")]
[AllowAnonymous]
public sealed class PaymentReturnController : ControllerBase
{
    [HttpGet]
    public ContentResult Index([FromQuery] string? result)
    {
        var cancelled = string.Equals(result, "cancelled", StringComparison.OrdinalIgnoreCase);

        var heading = cancelled ? "Payment cancelled" : "Payment complete";
        var body = cancelled
            ? "Nothing was charged and your plan has not changed. You can try again whenever you are ready."
            : "Thanks - we are confirming it with your bank now.";
        var accent = cancelled ? "#B45309" : "#15803D";

        var html = $$"""
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>{{heading}} - Unify</title>
              <style>
                :root { color-scheme: light dark; }
                body {
                  margin: 0; min-height: 100vh;
                  display: flex; align-items: center; justify-content: center;
                  font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
                  background: #F7FAFD; color: #0A0F1D;
                }
                @media (prefers-color-scheme: dark) {
                  body { background: #080C17; color: #EEF3FA; }
                  .card { background: #0F1626; border-color: rgba(148,180,220,.16); }
                  .note { color: #A3B1C6; }
                }
                .card {
                  max-width: 26rem; margin: 16px; padding: 32px 28px;
                  background: #fff; border: 1px solid #DCE5EF; border-radius: 16px;
                  text-align: center;
                }
                .mark { font-size: 44px; line-height: 1; color: {{accent}}; }
                h1 { font-size: 1.3rem; margin: 14px 0 8px; }
                p { margin: 0 0 10px; line-height: 1.55; }
                .note { color: #4A5872; font-size: .9rem; }
              </style>
            </head>
            <body>
              <main class="card">
                <div class="mark" aria-hidden="true">{{(cancelled ? "&#9888;" : "&#10003;")}}</div>
                <h1>{{heading}}</h1>
                <p>{{body}}</p>
                <p class="note">You can close this tab and go back to the Unify app - your plan updates there as soon as your payment clears.</p>
              </main>
            </body>
            </html>
            """;

        return Content(html, "text/html; charset=utf-8");
    }
}
