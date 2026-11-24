# Marketing & Social module

Facebook, Instagram and TikTok connected to the booking engine: one publisher,
one DM inbox, tracked booking links, server-side conversion tracking, and a
campaign report that joins ad spend to real bookings.

## What a business gets

| Screen (web) | Route | Roles | What it does |
|---|---|---|---|
| Social Accounts | `/social` | Admin, Manager (Staff read-only) | Connect Facebook Pages + linked Instagram accounts (one Meta login) and TikTok accounts; sandbox accounts; tracked booking links + QR; ad URL-parameter templates; server setup checklist |
| Publisher | `/social-posts` | Admin, Manager | Write once, publish now or schedule to any mix of accounts; per-platform validation and preview; per-destination status, permalink, retry, cancel, duplicate |
| Inbox | `/social-inbox` | Admin, Manager, Staff | Messenger + Instagram DMs across all accounts; reply (24 h window enforced); one-click tracked booking link that ties the resulting booking to the chat |
| Ads & Attribution | `/ads` | Admin, Manager (Admin edits settings) | Bookings/revenue by channel and day; campaign table with spend, CTR, CPC, bookings, revenue, cost per booking, ROAS; conversion-tracking settings; conversion event log |

## How the pieces connect

```
 Instagram bio / FB post / TikTok ad / inbox DM
        │  tracked link: /embed/book/{tenant}?utm_source=…&utm_campaign=…&conv=…
        ▼
 EmbedBookingPage ──(attribution: UTM, fbclid/ttclid, _fbp/_fbc/_ttp, referrer)──▶ POST /api/public/booking/{tenant}
        │                                                   Booking.Source = Instagram | Facebook | TikTok | Website
        │                                                   + BookingAttribution row (+ inbox thread linked)
        ▼
 ConversionWorker (every minute)
   sweep:    attributed booking created          → Meta "Schedule" / TikTok "PlaceAnOrder"
             attributed booking paid / delivered → Meta "Purchase" / TikTok "CompletePayment"
   dispatch: Meta Conversions API, TikTok Events API (hashed email/phone, click ids, IP/UA), retries
        ▼
 MarketingAnalyticsService: ad spend (Meta Marketing API, TikTok Marketing API)
                            ⨝ bookings by utm_campaign (id first, then name) → CPA, ROAS
```

Conversions are found by a sweeper rather than hooked into every place a
booking changes status (check-in, clinic flow, payment webhooks, hold expiry).
A unique index on `(BookingId, Platform, EventName)` makes it idempotent; the
booking id is the platform `event_id`, so the platforms dedupe too.

Publishing never happens inside the HTTP request. `SocialPublishingWorker`
(every 20 s) leases due targets, publishes, polls Instagram containers and
TikTok publish ids until they finish (30 min timeout), and retries transient
errors at 1/5/15/60 min (5 attempts). A revoked token flips the account to
`NeedsReconnect` and stops further attempts.

## Server configuration

| Setting (env var) | Needed for |
|---|---|
| `Social__Meta__AppId`, `Social__Meta__AppSecret` | Connecting Facebook/Instagram, webhook signature check |
| `Social__Meta__WebhookVerifyToken` | Meta webhook subscription handshake (any random string; type the same in the App Dashboard) |
| `Social__Meta__GraphVersion` | Optional, default `v23.0` |
| `Social__TikTok__ClientKey`, `Social__TikTok__ClientSecret` | Connecting TikTok |
| `Social__PublicApiBaseUrl` | Public https base of the API; builds OAuth redirect URIs. Defaults to the request host |
| `Social__StateKey` | Optional; OAuth state signing key (defaults to a derivation of `Jwt:Key`) |

Per-tenant pixel ids, Conversions/Events API tokens and ad-account tokens are
entered by each business on the Ads page and stored AES-256-GCM encrypted
(`IPlatformSecretProtector`, same as payment gateways). Tokens are never
returned by the API.

### Meta app
1. developers.facebook.com → Create app → Business. Add Facebook Login for Business, Instagram (API with Facebook Login), Messenger, Marketing API.
2. Valid OAuth redirect URI: `{PublicApiBaseUrl}/api/social/oauth/meta/callback` (shown on `/social` → Server setup).
3. Webhooks → Page **and** Instagram → callback `{PublicApiBaseUrl}/api/social/webhooks/meta`, verify token = `Social__Meta__WebhookVerifyToken`, subscribe to `messages`. Pages are subscribed to the app automatically on connect.
4. App Review for: `pages_show_list, pages_read_engagement, pages_manage_posts, pages_manage_metadata, pages_messaging, instagram_basic, instagram_content_publish, instagram_manage_messages, business_management, ads_read`. Until approved, only users with a role on the app can connect.

### TikTok app
1. developers.tiktok.com → app with Login Kit + Content Posting API (Direct Post). Scopes `user.info.basic, video.publish, video.upload`.
2. Redirect URI: `{PublicApiBaseUrl}/api/social/oauth/tiktok/callback`.
3. Verify the domain/URL prefix your media is served from (TikTok uses `PULL_FROM_URL`).
4. Unaudited apps can only post `SELF_ONLY`; the publisher reads the creator's allowed privacy levels and falls back automatically.
5. Ads reporting and the Events API are TikTok **for Business** (separate developer portal); the business pastes those tokens on the Ads page.

## Limits and decisions

- **TikTok DMs** are not supported: TikTok has no public messaging API for business accounts.
- **Meta 24-hour rule**: free-form replies only within 24 h of the customer's last message; enforced before calling Meta.
- **Video upload** from the browser isn't offered (Cloudinary upload is images ≤ 5 MB); videos are a public https URL.
- **Facebook "Book now" button**: the Graph API no longer lets apps set Page CTA buttons; the hub gives the tracked link to paste into it.
- **ROAS** compares booking revenue and ad spend as-is; it assumes the ad account bills in the booking currency.
- **Single API instance assumed** by both workers (the Render deployment). Leases stop a slow call being picked up twice by the same instance; two instances could race.
- **Personal data**: client IP and user agent are stored on `booking_attributions` because both conversion APIs require them raw; email/phone leave only as SHA-256.

## Tests

- Backend: `backend/SmeBackend.Tests/Marketing/` — OAuth state signing/replay, webhook signatures, attribution rules, publisher state machine (sandbox, IG polling, timeouts, token revocation, backoff, TikTok refresh), worker scheduling, webhook → inbox (dedupe, echoes, unknown pages), reply window, tenant isolation, conversion sweep/dispatch idempotency and hashing, settings encryption, campaign/ROAS join.
- Frontend: `frontend/src/features/social/*.test.ts(x)` — attribution collector, link builder, post rules, page smoke tests.
