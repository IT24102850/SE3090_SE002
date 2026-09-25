# Website booking widget

Lets a business take bookings on **its own website** (a third-party site
Unify does not host) and have them arrive in its Unify dashboard.

The business pastes a two-line snippet where the form should appear. The
snippet mounts an iframe of Unify's booking form, which reads the business's
upcoming departures and ticket prices, and submits through an anonymous
endpoint. The booking lands in the dashboard as an ordinary **Pending**
booking with **Source = Website**, attached to the right departure, so it
shows on the bookings list, the departure board and manifest, the
channel-split report, and as a bell notification for the whole team.

## The snippet

Business admins get it from **Settings → Business Settings → Website booking
widget**, with a colour picker and a live preview link. It looks like this:

```html
<div data-unify-booking="TENANT-ID" data-accent="#0d3b66"></div>
<script src="https://YOUR-UNIFY-HOST/embed.js" async></script>
```

| Attribute | Purpose |
|---|---|
| `data-unify-booking` | The business's tenant id (required). |
| `data-accent` | Button / link colour, any hex. Defaults to Unify blue. |
| `data-theme="dark"` | Dark ground, for dark pages. |
| `data-min-height` | Height in px before the first measurement arrives (default 520). |
| `data-whatsapp` | The business's WhatsApp number with country code, digits only. When set, "Confirm & send on WhatsApp" creates the booking in Unify **and** opens a WhatsApp chat with the details pre-filled (name, contact, date, time, vessel, tickets, total, requests, plus the Unify reference). A "Confirm only" button skips the chat. Falls back to the contact phone on the business profile. |

The loader is plain JavaScript with no dependencies. It works on static HTML,
WordPress (Custom HTML block), Wix (Embed → Custom code), Squarespace (Code
block), Webflow (Embed) — anywhere raw HTML can be pasted. It is idempotent
and, for sites that render content later, exposes `window.UnifyBooking.mount()`.

The host page receives a DOM event after a successful booking, for analytics:

```js
document.addEventListener('unify:booked', (e) => console.log(e.detail.reference));
```

### For mirissajetliner.com/book-now

`book-now.html` is hand-written static HTML whose form currently composes a
WhatsApp message. Replace the `<form>` (or place beside it) with:

```html
<div data-unify-booking="98606fd7-1bdc-4cba-ae2d-26b8daeae15c"
     data-accent="#1b7a8c" data-theme="dark" data-whatsapp="94777728439"></div>
<script src="https://YOUR-UNIFY-HOST/embed.js" async></script>
```

`data-whatsapp` keeps the flow the team already runs on: the old page composed
a WhatsApp message by hand and nothing was recorded; now the same message
still arrives on WhatsApp *and* the booking exists in Unify with a reference
the message quotes.

Swap `YOUR-UNIFY-HOST` for the deployed Unify frontend (the Vercel domain)
and the tenant id for Mirissa Jetliner's real tenant once it has upcoming
departures. The id above is the seeded demo tenant.

## How it works

```
mirissajetliner.com/book-now            Unify frontend                   Unify API
─────────────────────────────           ────────────────────             ──────────────────────────
<div data-unify-booking>  ──embed.js──▶ <iframe /embed/book/:tenant>
                                          │ GET  /api/public/booking/:tenant/catalog   (anonymous)
                                          │ POST /api/public/booking/:tenant           (anonymous, rate limited)
   ◀── postMessage height ────────────────┤
   ◀── postMessage booked ────────────────┘
```

- **Frontend:** `frontend/public/embed.js` (loader),
  `frontend/src/features/embed/EmbedBookingPage.tsx` (the form, route
  `/embed/book/:tenantId`), `frontend/src/features/settings/WebsiteWidgetCard.tsx`
  (the snippet card).
- **Backend:** `backend/SmeBackend/Controllers/PublicBookingController.cs`.
  Availability rules are shared with the authenticated endpoints via
  `Shared/Availability.cs`, so the widget can never overbook a sailing the
  admin form would refuse.

The form adapts to the business:

- **Departure businesses** (whale watching, safaris, boat trips): pick a
  date, then a sailing on that date, with live seats remaining.
- **Everyone else:** pick a resource and a day, then a free slot from the
  existing `available-slots` endpoint.

Tickets are Adult / Child / Infant, priced from `BookingType.ConfigJson`
`pricing.*` — the same keys the dashboard and the Flutter app use. The widget
shows base prices as an estimate; the server re-prices with the seasonal
window for the actual date and returns the confirmed total.

## What the visitor's booking looks like in Unify

| Field | Value |
|---|---|
| Status | `Pending` — the operator confirms it (or rejects it) like any request. |
| Source | `Website` |
| BookedBy / BookedFor | A `Customer` user in the tenant, created on first booking, keyed on the visitor's email. The password hash is random; if the person later registers on Unify with the same email, their bookings are already theirs. |
| DepartureId | Set when they booked a sailing, so the manifest counts them. |
| TicketBreakdown / TotalCost | Server-priced lines and total. |
| Notes | Their special requests. |
| FormData | `{ channel, guestName, guestEmail, guestPhone, specialRequests, pageUrl }` — `pageUrl` is the page the widget was on. |

A tenant-wide `WebsiteBooking` notification is queued for every booking.

## Abuse controls

The endpoints are anonymous by design, so they carry their own protection:

- **Rate limit:** 10 booking submissions per minute per IP (`Program.cs`,
  policy `public-booking`; 429 beyond that).
- **Honeypot:** a hidden `website` field. Bots that fill it get a fake
  success response and nothing is stored.
- **Server-side everything:** prices, capacity, tenant ownership of every
  referenced row, at-least-one-adult, max 20 seats per booking.
- **Pending status:** nothing is confirmed or charged without a person at the
  business looking at it.

## Testing locally

```powershell
# 1. Backend + frontend running (dotnet run in backend/SmeBackend; npm run dev in frontend)
# 2. A tenant with upcoming departures - the whale-watching seed creates one:
./scripts/seed-whalewatching-full.ps1 -AdminEmail you@example.com
# 3. Open the widget directly:
#    http://localhost:5173/embed/book/<tenant-id>
#    or paste the snippet into any HTML file served from another origin.
```

Tests: `backend/SmeBackend.Tests/PublicBookingControllerTests.cs`.
