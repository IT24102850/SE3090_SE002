/** HTML for the remote connector's sign-in and info pages. Self-contained, no external assets. */

export const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

const LOGO = `<svg width="44" height="44" viewBox="0 0 64 64" aria-hidden="true"><rect width="64" height="64" rx="14" fill="#2563eb"/><path d="M32 12 49 22v20L32 52 15 42V22z" fill="#fff"/><text x="32" y="40" text-anchor="middle" font-family="Arial,Helvetica,sans-serif" font-weight="700" font-size="20" fill="#2563eb">U</text></svg>`;

function shell(title: string, body: string, nonce?: string, script?: string) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>${esc(title)}</title>
<style>
:root{--blue:#2563eb;--ink:#0f172a;--muted:#64748b;--line:#e2e8f0;--bg:#f1f5f9}
*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:var(--bg);font:15px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:var(--ink);padding:24px}
.card{width:100%;max-width:420px;background:#fff;border:1px solid var(--line);border-radius:16px;padding:28px;box-shadow:0 10px 30px rgba(15,23,42,.06)}
.brand{display:flex;align-items:center;gap:12px;margin-bottom:18px}.brand b{font-size:1.15rem}.brand span{display:block;color:var(--muted);font-size:.85rem}
h1{font-size:1.15rem;margin:0 0 6px}p{margin:0 0 14px;color:var(--muted)}
label{display:block;font-weight:600;font-size:.88rem;margin:14px 0 6px}
input[type=email],input[type=password]{width:100%;padding:11px 12px;border:1px solid #cbd5e1;border-radius:10px;font:inherit}
input:focus{outline:2px solid var(--blue);outline-offset:1px;border-color:var(--blue)}
.check{display:flex;gap:10px;align-items:flex-start;margin:16px 0 4px;font-weight:500;font-size:.9rem;color:var(--ink)}
.check input{margin-top:3px}.check small{display:block;color:var(--muted);font-weight:400}
button{width:100%;margin-top:18px;padding:12px;border:0;border-radius:10px;background:var(--blue);color:#fff;font:600 15px system-ui,sans-serif;cursor:pointer}
button[disabled]{opacity:.7;cursor:wait}
.err{background:#fef2f2;border:1px solid #fecaca;color:#991b1b;border-radius:10px;padding:10px 12px;margin:0 0 6px;font-size:.9rem}
.fine{margin-top:16px;font-size:.8rem;color:var(--muted)}code{background:#f1f5f9;padding:2px 6px;border-radius:6px;font-size:.85em;word-break:break-all}
ol{padding-left:20px;color:var(--ink)}li{margin:6px 0}
</style></head><body><main class="card">
<div class="brand">${LOGO}<div><b>Unify</b><span>Booking platform</span></div></div>
${body}
</main>${script ? `<script nonce="${nonce}">${script}</script>` : ""}</body></html>`;
}

export function loginPage(opts: {
  clientName: string;
  hidden: Record<string, string>;
  error?: string;
  email?: string;
  allowWrite?: boolean;
  nonce: string;
}) {
  const hidden = Object.entries(opts.hidden)
    .map(([k, v]) => `<input type="hidden" name="${esc(k)}" value="${esc(v)}">`)
    .join("");
  const body = `
<h1>Connect ${esc(opts.clientName)} to Unify</h1>
<p>Sign in with your Unify account. ${esc(opts.clientName)} will be able to work with your business's bookings, resources and reports as you.</p>
${opts.error ? `<div class="err" role="alert">${esc(opts.error)}</div>` : ""}
<form method="post" action="/oauth/authorize" id="f">
${hidden}
<label for="email">Email</label>
<input id="email" name="email" type="email" autocomplete="username" required value="${esc(opts.email ?? "")}" autofocus>
<label for="password">Password</label>
<input id="password" name="password" type="password" autocomplete="current-password" required>
<label class="check"><input type="checkbox" name="allow_write" value="1" ${opts.allowWrite === false ? "" : "checked"}>
<span>Allow changes<small>Create, reschedule and cancel bookings, approve AI plans. Untick for view-only access.</small></span></label>
<button type="submit" id="go">Sign in and allow</button>
</form>
<p class="fine">Your password is sent only to Unify, never to ${esc(opts.clientName)}. You can disconnect at any time from the app's connector settings. <a href="/connector/privacy" target="_blank" rel="noopener">Privacy policy</a></p>`;
  const script = `document.getElementById('f').addEventListener('submit',function(){var b=document.getElementById('go');b.disabled=true;b.textContent='Signing in… (up to a minute if Unify was asleep)';});`;
  return shell("Sign in to Unify", body, opts.nonce, script);
}

export function errorPage(title: string, message: string) {
  return shell(title, `<h1>${esc(title)}</h1><p>${esc(message)}</p>`);
}

export function infoPage(base: string) {
  return shell(
    "Unify connector for Claude",
    `<h1>Unify connector for Claude</h1>
<p>This is a Model Context Protocol endpoint. Add it to Claude to manage your Unify business by chat.</p>
<ol>
<li>In Claude, open <b>Settings → Connectors → Add custom connector</b>.</li>
<li>Name: <b>Unify</b>. URL: <code>${esc(base)}/mcp</code></li>
<li>Click <b>Connect</b> and sign in with your Unify account.</li>
</ol>
<p class="fine">View-only variant: <code>${esc(base)}/mcp?readonly=1</code></p>
<p class="fine"><a href="/connector/docs">Documentation</a> · <a href="/connector/privacy">Privacy policy</a></p>`,
  );
}
