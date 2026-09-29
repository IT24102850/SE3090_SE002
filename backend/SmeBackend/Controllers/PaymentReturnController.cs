using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace SmeBackend.Controllers;

/// Where a payment gateway sends someone back to after a hosted checkout
/// opened outside the app.
///
/// The React app handles its own return at /subscription and never reaches
/// here. This is for the Flutter app, which has nowhere of its own to land:
/// the card form runs in a browser the app does not control, and a deep link
/// back into a phone build needs app-link registration on both stores.
/// Without somewhere real to point at, the gateway falls back to a dead URL
/// and the customer's last impression of paying us is a browser error page.
///
/// What happens next depends on how the checkout was opened:
///
///   Flutter web  - the app opened this in a tab with window.open, so the
///                  tab can close itself and drop the person straight back
///                  on the app, which then confirms the payment. That is the
///                  "redirect back to the dashboard" behaviour, done without
///                  a redirect: there is nothing to navigate to, because the
///                  app is still sitting in the tab behind this one.
///   Phone        - close() does nothing in an ordinary tab, so the message
///                  stays up and tells them to switch back to the app.
///
/// It deliberately does NOT redirect to a URL handed in on the query string.
/// That is an open redirect, and an open redirect on a payment-return page
/// is a ready-made phishing step: a link that genuinely starts at our domain
/// and ends wherever the attacker likes.
///
/// It asserts nothing about the payment either. The query string comes from
/// the gateway's redirect and anybody can retype it, so this page never
/// touches the database - it is a signpost, not a receipt. The plan only
/// moves when the app asks the server, and the server asks the gateway.
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
            ? "Nothing was charged and your plan has not changed."
            : "Thanks - we are confirming it with your bank now.";

        var html = $$"""
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>{{heading}} - Unify</title>
              <style>
                /* Every colour is a token, so dark mode is one override block
                   at the end rather than a rule that has to out-order the
                   light one. Getting that wrong once already shipped white
                   text on a white card. */
                :root {
                  color-scheme: light dark;
                  --bg: #F7FAFD;
                  --fg: #0A0F1D;
                  --card: #FFFFFF;
                  --border: #DCE5EF;
                  --note: #4A5872;
                  --good: #15803D;
                  --warn: #B45309;
                  --btn: #2563EB;
                  --btn-fg: #FFFFFF;
                }
                @media (prefers-color-scheme: dark) {
                  :root {
                    --bg: #080C17;
                    --fg: #EEF3FA;
                    --card: #0F1626;
                    --border: rgba(148, 180, 220, .18);
                    --note: #A3B1C6;
                    --good: #4ADE80;
                    --warn: #FBBF24;
                    --btn: #38BDF8;
                    --btn-fg: #0A0F1D;
                  }
                }

                body {
                  margin: 0; min-height: 100vh; padding: 16px;
                  display: flex; align-items: center; justify-content: center;
                  font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
                  background: var(--bg); color: var(--fg);
                }
                .card {
                  box-sizing: border-box; width: 100%; max-width: 26rem;
                  padding: 32px 28px; text-align: center;
                  background: var(--card); color: var(--fg);
                  border: 1px solid var(--border); border-radius: 16px;
                }
                .mark { font-size: 44px; line-height: 1; color: var(--good); }
                .mark.warn { color: var(--warn); }
                h1 { font-size: 1.3rem; margin: 14px 0 8px; color: var(--fg); }
                p { margin: 0 0 10px; line-height: 1.55; color: var(--fg); }
                .note { color: var(--note); font-size: .9rem; }
                button {
                  margin-top: 14px; padding: 11px 20px; min-height: 44px;
                  font: inherit; font-weight: 600; cursor: pointer;
                  background: var(--btn); color: var(--btn-fg);
                  border: none; border-radius: 10px;
                }
                button:hover { filter: brightness(1.08); }
                /* Only shown when this tab cannot close itself. */
                #stuck { display: none; }
              </style>
            </head>
            <body>
              <main class="card">
                <div class="mark{{(cancelled ? " warn" : "")}}" aria-hidden="true">{{(cancelled ? "&#9888;" : "&#10003;")}}</div>
                <h1>{{heading}}</h1>
                <p>{{body}}</p>
                <p class="note" id="back">Taking you back to Unify&hellip;</p>
                <div id="stuck">
                  <p class="note">You can close this tab and go back to the Unify app - your plan updates there as soon as your payment clears.</p>
                  <button type="button" id="close">Close this tab</button>
                </div>
              </main>
              <script>
                (function () {
                  // The app opened this tab, so it is allowed to close it -
                  // which puts the person back on the app they were using,
                  // where the payment actually gets confirmed. A tab that was
                  // not script-opened (a phone browser, a pasted link) simply
                  // ignores close(), so we fall back to telling them.
                  function giveUp() {
                    document.getElementById('back').style.display = 'none';
                    document.getElementById('stuck').style.display = 'block';
                  }
                  document.getElementById('close').addEventListener('click', function () {
                    window.close();
                  });
                  // Long enough to read the outcome, short enough not to feel stuck.
                  setTimeout(function () {
                    window.close();
                    // Still here a moment later means close() was refused.
                    setTimeout(giveUp, 400);
                  }, 1600);
                })();
              </script>
            </body>
            </html>
            """;

        return Content(html, "text/html; charset=utf-8");
    }
}
