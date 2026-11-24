# Unify connector for Claude (MCP server)

Connects Claude to the **Unify SME booking platform** (<https://se-3090-se-002.vercel.app>) so you can run your business by chatting:

> *"What does tomorrow look like at the clinic?"*
> *"Find Dr. Perera's free slots on Friday afternoon and book Nimal Silva for a 30-minute check-up at the first one."*
> *"Move booking 7f3e… to next Tuesday at 10."*
> *"Which inventory items are running low?"*
> *"Show me pending AI planner workflows and reject the one that double-books the dentist."*

It is a [Model Context Protocol](https://modelcontextprotocol.io) server that talks to the same ASP.NET Core API the Unify web app uses (`/api/*`). It signs in with your Unify account, and everything it does respects your role (Admin / Manager / Staff) and stays inside your business (tenant).

---

## Install

### Option A: Claude on the web, desktop or phone (recommended)

The connector is deployed with the web app at **`https://se-3090-se-002.vercel.app/mcp`**.

1. In Claude, open **Settings → Connectors → Add custom connector**.
2. Name: **Unify**. URL: `https://se-3090-se-002.vercel.app/mcp`
3. Click **Connect**. A Unify sign-in page opens. Sign in with your Unify email and password, and leave **Allow changes** ticked unless you want view-only access.

Admins can also find the URL in the Unify web app under **Settings → Connect to Claude**.

### Option B: Claude Desktop extension

1. Download **`unify-claude.mcpb`** from `https://se-3090-se-002.vercel.app/downloads/unify-claude.mcpb` (or Settings → Connect to Claude → *Download for Claude Desktop*).
2. Double-click it (or in Claude Desktop: **Settings → Extensions → Advanced → Install extension…** and pick the file).
3. Fill in the form:
   - **Unify email** and **Unify password**: your web-app login. The password is kept in your OS keychain.
   - **API URL**: leave the default `https://se-3090-se-002.vercel.app/api`.
   - **Business time zone**: default `Asia/Colombo`.
   - **Read-only mode**: tick it if Claude should only look, not change anything.
4. Enable the extension and start a new chat. Try *"Who am I in Unify?"*

Node.js is built into Claude Desktop, so you don't need to install anything else.

### Option C: Claude Desktop, manual config

Build it once (`npm install && npm run build`), then add this to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "unify": {
      "command": "node",
      "args": ["/absolute/path/to/unify-mcp/dist/index.js"],
      "env": {
        "UNIFY_EMAIL": "you@yourbusiness.lk",
        "UNIFY_PASSWORD": "your-password",
        "UNIFY_TIMEZONE": "Asia/Colombo"
      }
    }
  }
}
```

### Option D: Claude Code

```bash
# remote (OAuth sign-in in the browser)
claude mcp add --transport http unify https://se-3090-se-002.vercel.app/mcp

# or local
claude mcp add unify \
  -e UNIFY_EMAIL=you@yourbusiness.lk \
  -e UNIFY_PASSWORD='your-password' \
  -- node /absolute/path/to/unify-mcp/dist/index.js
```

---

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `UNIFY_EMAIL` / `UNIFY_PASSWORD` | – | Unify login (Admin, Manager or Staff). |
| `UNIFY_ACCESS_TOKEN` | – | Alternative to email/password: a JWT from `/api/auth/login`. |
| `UNIFY_API_URL` | `https://se-3090-se-002.vercel.app/api` | API base. The Vercel site forwards `/api` to the Render backend. Use `http://localhost:5000/api` for local dev. |
| `UNIFY_TIMEZONE` | `Asia/Colombo` | Times you type without an offset are read in this zone, and every timestamp returned also gets a `…Local` field in it. |
| `UNIFY_READ_ONLY` | `false` | `true` registers only the read tools. |
| `UNIFY_TIMEOUT_SECONDS` | `90` | Per-request timeout. The free Render backend can take about a minute to wake up. |

## Tools (34)

| Area | Tools |
|---|---|
| Account & business | `unify_whoami`, `unify_list_branches`, `unify_list_staff`, `unify_search_customers`, `unify_list_public_businesses` |
| Resources & availability | `unify_list_resources`, `unify_get_resource` (with weekly schedule and exceptions), `unify_find_available_slots`, `unify_get_booked_ranges` (Night/DateRange) |
| Booking types | `unify_list_booking_types` |
| Bookings | `unify_list_bookings`, `unify_get_booking` (with history), `unify_get_my_schedule`, `unify_find_booking_conflicts`, `unify_create_booking`, `unify_reschedule_booking`, `unify_cancel_booking`, `unify_update_booking_status`, `unify_check_in_booking`, `unify_send_booking_reminder` |
| Reports | `unify_get_dashboard` (clinic / restaurant / gym / school / excursions, auto-picked from the business type), `unify_get_revenue_report`, `unify_get_booking_stats` (no-shows, revenue per slot) |
| Inventory & billing | `unify_list_inventory`, `unify_list_invoices`, `unify_get_invoice` |
| Notifications | `unify_list_notifications`, `unify_mark_notification_read` |
| AI planner | `unify_list_ai_workflows`, `unify_get_ai_workflow`, `unify_review_ai_workflow` (approve / reject / apply), `unify_plan_schedule_with_ai`, `unify_ask_workspace_assistant` |
| Everything else | `unify_api_request`: any `/api` endpoint (departures, sightings, equipment, subscriptions, purchase orders, forms…). Platform-owner and auth endpoints are blocked. |

Prompts: **daily_briefing** and **book_appointment**.

Every tool is marked read-only or write/destructive (MCP tool annotations), so Claude asks before cancelling, rejecting or applying anything.

## How it works

- **Sign-in**: `POST /api/auth/login` on first use. When the 2-hour access token expires it calls `POST /api/auth/refresh` and retries; if that fails it signs in again.
- **Tenant scoping**: endpoints that need `tenantId` get it from your login automatically. `bookedBy` defaults to you unless you pass a `customerId`.
- **Time zones**: the backend stores UTC and treats any time without an offset as UTC. The connector converts `2026-11-25T10:00` (Colombo) to `2026-11-25T04:30:00Z` before sending, and passes `tz=330` to the dashboards, as the web app does.
- **Cold starts**: GET requests are retried on 502/503/504 or a timeout.
- **Big responses** are compacted and cut at about 60k characters, with a hint to narrow the query.

## Develop

```bash
npm install
npm run typecheck
npm test          # builds, then runs end-to-end tests against a mock Unify API
npm run build          # -> dist/index.js (Desktop/stdio) and dist/http.js (remote, standalone)
npm run build:vercel   # -> ../frontend/api/claude-mcp.js (the deployed remote connector)
npm run pack:desktop   # -> ../frontend/public/downloads/unify-claude.mcpb
```

Source layout: `src/config.ts` (env), `src/client.ts` (Unify HTTP client + auth/refresh), `src/time.ts` (time zones), `src/tools.ts` (tool definitions), `src/server.ts` (server + prompts), `src/index.ts` (Desktop/stdio entry), `src/remote/` (OAuth server, sign-in page, MCP-over-HTTP handler), `src/vercel.ts` and `src/http.ts` (remote entries).

## The remote connector (how `/mcp` is deployed)

`src/vercel.ts` is bundled by `npm run build:vercel` into **`frontend/api/claude-mcp.js`**, a Vercel Function deployed with the web app. `frontend/vercel.json` routes these paths to it, ahead of the `/api` proxy and the SPA fallback:

| Path | Purpose |
|---|---|
| `/mcp` | MCP endpoint (Streamable HTTP, stateless, Bearer token) |
| `/.well-known/oauth-protected-resource` | RFC 9728 resource metadata (where to sign in) |
| `/.well-known/oauth-authorization-server` | RFC 8414 authorization-server metadata |
| `/oauth/register` | RFC 7591 dynamic client registration |
| `/oauth/authorize` | Unify sign-in page (PKCE S256 required) |
| `/oauth/token` | `authorization_code` and `refresh_token` grants |

It keeps no database. Client ids, codes and tokens are sealed with AES-256-GCM under **`UNIFY_MCP_SECRET`**. The access token wraps the user's own Unify JWT and the refresh token wraps their Unify refresh token, so a connector refresh rotates the Unify session (`/api/auth/refresh`). The password goes only to Unify's `/api/auth/login`, never to Claude.

### One-time setup on Vercel

In the Vercel project: **Settings → Environment Variables**, add (Production and Preview):

| Name | Value |
|---|---|
| `UNIFY_MCP_SECRET` | a random string of 32+ characters. PowerShell: `-join ((48..57)+(65..90)+(97..122) \| Get-Random -Count 48 \| % {[char]$_})` |
| `UNIFY_API_URL` *(optional)* | defaults to `https://sme-backend-lxsp.onrender.com/api` |
| `UNIFY_TIMEZONE` *(optional)* | defaults to `Asia/Colombo` |

Then redeploy. Until the secret is set, `/mcp` and `/oauth/*` answer with an error explaining what's missing. Changing the secret signs everyone out of the connector, so they have to reconnect.

When you change anything in `src/`, run `npm run build:vercel` and commit `frontend/api/claude-mcp.js`. CI fails if it's out of date. For the Desktop download, run `npm run pack:desktop`.

### Running it yourself

`UNIFY_MCP_SECRET=... PORT=8787 npm run start:http` serves the same thing at `http://localhost:8787/mcp`, for local testing or hosting elsewhere.
