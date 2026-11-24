# Submitting Unify to the Claude Connectors Directory

Answers for each step of Anthropic's developer portal, ready to paste. Requirements: <https://claude.com/docs/connectors/building/submission>. Review checklist: <https://claude.com/docs/connectors/building/review-criteria>.

## Before you open the portal

- [ ] `UNIFY_MCP_SECRET` is set in Vercel (Project → Settings → Environment Variables) and the site is redeployed. Check: `https://se-3090-se-002.vercel.app/oauth/authorize` must **not** say "Connector not configured".
- [ ] Add the connector to your own Claude as a custom connector (Settings → Connectors → Add custom connector → `https://se-3090-se-002.vercel.app/mcp`), sign in, and call every tool at least once. The portal asks you to confirm this.
- [ ] A **reviewer test account**: a Unify **Admin** login for a business that has resources, booking types, customers, bookings (past and upcoming), inventory and invoices. One of the seeded demo businesses works (see `scripts/seed-*.sql`), or create a fresh one and seed it. Don't use a real person's account.
- [ ] You're signed in to claude.ai on a paid plan (on Team/Enterprise, an Owner submits).

Then open <https://claude.ai/directory/manage> → **Submit new** → **MCP connector**.

---

## 1. Connection

- Server URL: `https://se-3090-se-002.vercel.app/mcp`
- Users connect to: **one URL** (the same URL for everyone; each user's own sign-in decides which business they see)

## 2. Tools

These sync automatically: 42 tools (27 read-only, 15 write), plus 2 prompts. Every tool has a `title` and `readOnlyHint` or `destructiveHint`. There's no catch-all tool with a method parameter; `unify_api_get` is GET-only and links the API reference.

## 3. Listing

**Server name:** Unify

**One-liner** (under 200 characters):
> Run your Unify booking business from Claude: check schedules, find free slots, book and reschedule, check guests in, and read your dashboards.

**Description** (under 2,000 characters):
> Unify is a booking and operations platform for small businesses: clinics, restaurants, gyms, schools and tuition centres, real estate agents and tourism operators. The Unify connector lets you manage your business by chatting with Claude.
>
> Ask what tomorrow looks like and Claude lists the day's bookings in your local time. Ask for a doctor's free slots on Friday afternoon and book a patient into one. Move a booking, cancel it, confirm it, mark a no-show, check a guest in or send a reminder. Claude can also find double-bookings, read your clinic, restaurant, gym, school or excursion dashboard, report revenue and no-show rates, list low-stock items, and look up invoices.
>
> Unify's AI planner proposes batches of bookings. With the connector you can review those plans in Claude and approve, reject or apply them.
>
> You sign in with your own Unify account, so Claude acts as you, with your role's permissions, inside your business only. Untick "Allow changes" when signing in for view-only access. Read tools run straight away, and every write asks first.

**Categories:** Productivity; Business operations / CRM; Scheduling (pick the closest the portal offers)

**Documentation URL:** `https://se-3090-se-002.vercel.app/connector/docs`

**Privacy policy URL:** `https://se-3090-se-002.vercel.app/connector/privacy`

**Support contact:** `https://github.com/IT24102850/SE3090_SE002/issues`. If the portal asks for an email, use a team mailbox you check, and add it to the privacy and docs pages too.

**Icon:** `mcp-connector/icon.png` (512×512)

**URL slug:** `unify` (permanent once published)

## 4. Use cases

**Primary use cases:**
1. Daily operations: see today's or tomorrow's bookings, a staff member's schedule, and dashboard alerts.
2. Booking management: find availability, then create, reschedule, cancel, confirm, check in or remind.
3. Reporting: revenue, no-shows, dashboard KPIs, low stock and invoices.
4. AI planner oversight: review, approve, reject and apply AI-proposed schedules.

**What users need before connecting:** a Unify business account (Admin, Manager or Staff role) at https://se-3090-se-002.vercel.app. Signing up is free at /register.

**Reads or writes:** both.

## 5. Company

- Company name: *(your team or business name, e.g. "Unify")*
- Website: `https://se-3090-se-002.vercel.app`
- Primary contact: *(name and email of the person who will answer reviewer feedback)*

## 6. Authentication

- Authentication requirement: **Required**
- Method: **OAuth 2.0** with dynamic client registration (RFC 7591) and PKCE (S256). There's no client ID or secret to enter, since Claude registers itself.
- Metadata: `https://se-3090-se-002.vercel.app/.well-known/oauth-protected-resource` and `/.well-known/oauth-authorization-server`

## 7. Data handling

- API ownership: **our own first-party API** (the Unify backend; the connector calls only Unify's API)
- **Personal health data: yes, possibly.** Clinic businesses on Unify store appointments and practitioner notes, and the connector can return them to the clinic's own signed-in staff. Answer the portal's health-data question honestly. If you'd rather not handle health data through the connector, say so and we can filter notes out of clinic responses before submitting.
- Sponsored content: no

## 8. Test & launch

**Reviewer instructions:**
> 1. In Claude, add the connector: Settings → Connectors → Unify (or Add custom connector → https://se-3090-se-002.vercel.app/mcp) → Connect.
> 2. On the Unify sign-in page, use the test account below and leave "Allow changes" ticked.
>    Email: <TEST EMAIL> / Password: <TEST PASSWORD>
>    This is an Admin of the demo business "<BUSINESS NAME>". It has resources, booking types, customers, bookings, inventory and invoices.
> 3. If the first sign-in takes up to a minute, that's the backend waking from idle (free hosting tier). Later calls are fast.
> 4. Try: "Who am I in Unify?", "What bookings are there tomorrow?", "Find free slots for <RESOURCE> next Monday", "Book <CUSTOMER> into the first one", "Reschedule it to 11:00", "Cancel it", "Show the dashboard", "Which items are low on stock?", "List pending AI workflows".
> 5. Write actions only change data in this demo business.

Tick the confirmation that you've run every tool yourself in Claude or MCP Inspector.

## 9. Compliance (all seven required)

- Directory guidelines: yes
- First-party API usage: yes, Unify's own API
- Financial transactions: none. There are no payment, refund or transfer tools; `unify_api_get` is read-only.
- AI media generation: none
- Prompt injection: tool descriptions say only what each tool does
- Conversation data: the connector receives only tool arguments and stores nothing
- Public documentation: `https://se-3090-se-002.vercel.app/connector/docs`

## 10. Review and submit

Submit, then track the status at <https://claude.ai/directory/manage>. For escalations, email `mcp-review@anthropic.com`.
