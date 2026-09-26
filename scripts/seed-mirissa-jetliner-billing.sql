-- ============================================================================
-- Billing RECORDS for the "Mirissa JetLiner" whale-watching tenant, so every
-- panel of the Billing & Payments module has something real to show:
-- the billing dashboard KPIs and charts, the invoice list and its filters,
-- outstanding/aging, the daily revenue report, commission rules, the
-- subscription manager and the insurance claim tracker.
--
--   psql "$DATABASE_URL" -f scripts/seed-mirissa-jetliner-billing.sql

-- WHICH TENANT: six tenants are named some variant of "Mirissa Jetliner", so
-- this one is pinned by Id - the same tenant the other
-- scripts/seed-mirissa-jetliner-*.sql files target (vessels, departures,
-- packages, inventory). Change tenant_id below to point it elsewhere.
--
-- WHAT IT WRITES
--   1) Guests      - 10 travellers + 2 trade accounts (a hotel and an agent)
--   2) Commissions - the 4 payout rules a Mirissa operator actually runs:
--                    hotel desks, tuk-tuk drivers, OTAs, and staff upsells
--   3) Retainers   - 3 trade accounts on monthly credit (Subscriptions),
--                    which is what the MRR tile and the subscription
--                    manager read
--   4) Invoices    - 42 tour sales across the last 45 days, with their line
--                    items and payments: paid, part-paid (deposit), issued
--                    and not yet due, overdue, one weather cancellation
--                    refunded in full, and one declined card retried
--   5) Claims      - 2 travel-insurance claims against cancelled trips, so
--                    the claim tracker and the "pending claims" tile are
--                    not empty
--
-- PRICES are not invented: the adult/child fare of every line comes from
-- that booking type's own ConfigJson->pricing on this tenant, so the seed
-- and the product catalogue can never drift apart.
--
-- TAX: Sri Lankan tour prices are quoted VAT-inclusive, so a published
-- LKR 7,500 seat is stored as a net line of 7500/1.18 with the 18% VAT in
-- the invoice's Tax column - FinalAmount then lands exactly on the price the
-- guest was quoted, and the engine's own arithmetic
-- (FinalAmount = subtotal - discount + tax) still holds.
--
-- Everything here is DEMO DATA: guests, phone numbers, policy numbers and
-- transaction references are invented. Emails use the reserved
-- example-demo.test domain and every login created here has the password
-- Passw0rd!
--
-- Times are Sri Lanka time (Asia/Colombo), stored as timestamptz; "today"
-- is today in Colombo.
--
-- Idempotent: every block is guarded (guests by email, rules and retainers
-- by name, invoices by invoice number), so re-running adds nothing. Wrapped
-- in one transaction.
-- ============================================================================

BEGIN;

DROP TABLE IF EXISTS _mjl_ctx;
DROP TABLE IF EXISTS _mjl_guest;
DROP TABLE IF EXISTS _mjl_sales;
DROP TABLE IF EXISTS _mjl_invoice;

-- ── 0) Context ──────────────────────────────────────────────────────────────
CREATE TEMP TABLE _mjl_ctx AS
SELECT t."Id" AS tenant_id,
       (SELECT b."Id" FROM "Branches" b
         WHERE b."TenantId" = t."Id" AND b."IsActive"
         ORDER BY b."CreatedAt" LIMIT 1) AS branch_id
FROM "Tenants" t
WHERE t."Id" = 'f15bae97-fa7e-42f5-95b7-b624db319ad2'::uuid;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM _mjl_ctx) THEN
    RAISE EXCEPTION 'Tenant f15bae97-fa7e-42f5-95b7-b624db319ad2 (Mirissa JetLiner) was not found - check the Id at the top of this script.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM booking_types bt JOIN _mjl_ctx c ON bt."TenantId" = c.tenant_id
                  WHERE bt."Name" = 'Whale Watching' AND bt."DeletedAt" IS NULL) THEN
    RAISE EXCEPTION 'The tenant has no "Whale Watching" booking type - run scripts/seed-mirissa-jetliner.ps1 first; the fares here are read from the catalogue.';
  END IF;
END $$;

-- ── 1) Guests and trade accounts ────────────────────────────────────────────
-- Walk-up travellers pay on the spot; the hotel and the agent are invoiced
-- on credit, which is where the overdue and aging figures come from.
INSERT INTO "Users"
  ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","Email","PasswordHash",
   "FullName","Phone","Role","IsActive","IsApproved","Address")
SELECT gen_random_uuid(), now() - (v.days_ago || ' days')::interval, now(),
       ctx.tenant_id, ctx.branch_id, v.email,
       '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
       v.full_name, v.phone, 3, true, true, v.address
FROM _mjl_ctx ctx,
(VALUES
  ('emma.hartley@example-demo.test',      'Emma Hartley',        '+447700900142', 'Hotel - Mirissa Beach',        60),
  ('lukas.meyer@example-demo.test',       'Lukas Meyer',         '+4915112345678','Villa - Weligama',             55),
  ('sophie.dubois@example-demo.test',     'Sophie Dubois',       '+33612345678',  'Hotel - Mirissa Bay',          48),
  ('daniel.novak@example-demo.test',      'Daniel Novak',        '+420601234567', 'Hostel - Mirissa Harbour',     44),
  ('yuki.tanaka@example-demo.test',       'Yuki Tanaka',         '+819012345678', 'Hotel - Weligama Bay',         40),
  ('arjun.mehta@example-demo.test',       'Arjun Mehta',         '+919812345678', 'Resort - Polwathumodara',      33),
  ('nadeeka.perera@example-demo.test',    'Nadeeka Perera',      '+94771450021',  'Nugegoda, Colombo',            28),
  ('ruwan.dissanayake@example-demo.test', 'Ruwan Dissanayake',   '+94771450022',  'Matara',                       21),
  ('maria.rossi@example-demo.test',       'Maria Rossi',         '+393331234567', 'Hotel - Mirissa Beach',        14),
  ('oliver.brandt@example-demo.test',     'Oliver Brandt',       '+61412345678',  'Surf camp - Midigama',          9),
  ('paradise.beach.club@example-demo.test','Paradise Beach Club Mirissa','+94412250110','Mirissa Beach Road',      90),
  ('ocean.breeze.travels@example-demo.test','Ocean Breeze Travels (Galle)','+94912234455','Galle Fort',            90)
) AS v(email, full_name, phone, address, days_ago)
WHERE NOT EXISTS (SELECT 1 FROM "Users" u WHERE lower(u."Email") = v.email);

CREATE TEMP TABLE _mjl_guest AS
SELECT u."Id" AS user_id, split_part(u."Email", '.', 1) AS label
FROM "Users" u JOIN _mjl_ctx ctx ON u."TenantId" = ctx.tenant_id
WHERE u."Role" = 3 AND u."Email" LIKE '%@example-demo.test';

-- ── 2) Commission rules ─────────────────────────────────────────────────────
-- What the harbour actually pays out: hotel front desks and tuk-tuk drivers
-- bring most walk-up seats, OTAs take a booking fee, and crew get a small
-- cut of onboard upsells.
INSERT INTO commission_rules
  ("Id","TenantId","Name","Role","RuleType","Rate","FixedAmount","MinAmount","MaxAmount",
   "Description","IsActive","EffectiveFrom","EffectiveTo","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, v.name, v.role, v.rule_type, v.rate, v.fixed_amount,
       v.min_amount, v.max_amount, v.description, v.is_active,
       now() - (v.from_days || ' days')::interval, NULL, now(), now()
FROM _mjl_ctx ctx,
(VALUES
  ('Hotel desk referral',      'Partner',  'Percentage', 15.0, NULL,   2000.0, 25000.0,
   'Paid to the hotel or guest house that books the seat, on the fare before tax.',            true,  180),
  ('Tuk-tuk driver drop-off',  'Driver',   'Fixed',       0.0,  500.0,  NULL,    5000.0,
   'Flat LKR 500 per guest delivered to the jetty before the 06:30 sailing.',                   true,  180),
  ('Online travel agent (OTA)','Agent',    'Percentage', 12.0, NULL,   1500.0, 40000.0,
   'GetYourGuide / Viator bookings; deducted when the platform settles.',                       true,  120),
  ('Crew onboard upsell',      'Staff',    'Percentage',  5.0, NULL,    NULL,    3000.0,
   'Crew share on photo packages and snorkelling add-ons sold on board.',                       true,   90)
) AS v(name, role, rule_type, rate, fixed_amount, min_amount, max_amount, description, is_active, from_days)
WHERE NOT EXISTS (
  SELECT 1 FROM commission_rules c WHERE c."TenantId" = ctx.tenant_id AND c."Name" = v.name);

-- ── 3) Trade retainers (monthly credit accounts) ────────────────────────────
-- Hotels and agents that hold a monthly allocation of seats and settle on
-- account. These are what the MRR tile and the subscription manager read.
INSERT INTO "Subscriptions"
  ("Id","TenantId","BranchId","CustomerId","PlanName","Amount","BillingCycle",
   "StartDate","EndDate","AutoRenew","Status","PaymentStatus","LastPaymentAt",
   "NextBillingAt","Notes","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, ctx.branch_id, g.user_id, v.plan, v.amount, 'Monthly',
       now() - (v.start_days || ' days')::interval,
       now() + (v.end_days || ' days')::interval,
       true, 'Active', v.pay_status,
       now() - (v.last_paid_days || ' days')::interval,
       now() + (v.next_days || ' days')::interval,
       v.notes, now() - (v.start_days || ' days')::interval, now()
FROM _mjl_ctx ctx
JOIN (VALUES
  ('paradise', 'Hotel allocation - 20 seats/month', 120000.0, 90, 275, 12, 18, 'Paid',
   'Paradise Beach Club holds 20 whale-watching seats a month; settled on the 1st.'),
  ('ocean',    'Agent allocation - 12 seats/month',  72000.0, 90, 275,  9, 21, 'Paid',
   'Ocean Breeze Travels (Galle); day tours sold with hotel transfers.'),
  ('paradise', 'Sunset cruise block - 8 seats/month',40000.0, 60, 305, 34,  -4, 'Overdue',
   'Second allocation for the coastal sunset run; September invoice is past due.')
) AS v(label, plan, amount, start_days, end_days, last_paid_days, next_days, pay_status, notes)
  ON true
JOIN _mjl_guest g ON g.label = v.label
WHERE NOT EXISTS (
  SELECT 1 FROM "Subscriptions" s
   WHERE s."TenantId" = ctx.tenant_id AND s."PlanName" = v.plan);

-- ── 4) Tour sales -> invoices, line items, payments ─────────────────────────
-- One row per sale. Columns:
--   seq        stable suffix of the invoice number (idempotency key)
--   days_ago   day the invoice was raised (Colombo)
--   tour       booking type sold; fares are read from its ConfigJson
--   addon      optional second product on the same bill (NULL = none)
--   guest      guest label from _mjl_guest
--   adults/children  seats
--   pickup     include the (free) hotel pickup line
--   disc_pct   agent/loyalty discount on the net subtotal
--   due_days   credit terms: 0 = payable on the day, 7/14 = trade account
--   pay_after  days after issue the money arrived (NULL = still unpaid)
--   pay_share  1.0 = paid in full, 0.5 = deposit only
--   method     Cash | Card | QR | BankTransfer
--   kind       sale | cancelled-refund | card-declined
CREATE TEMP TABLE _mjl_sales (
  seq text, days_ago int, tour text, addon text, guest text,
  adults int, children int, pickup boolean, disc_pct numeric,
  due_days int, pay_after int, pay_share numeric, method text, kind text, note text
);

INSERT INTO _mjl_sales VALUES
 -- Walk-up and hotel-desk seats, paid on the day ----------------------------
 ('MJL001', 44, 'Whale Watching',     NULL,          'emma',    2, 0, true,  0,  0, 0, 1.0, 'Cash',        'sale', 'Hotel desk booking - Mirissa Beach'),
 ('MJL002', 43, 'Whale Watching',     'Snorkeling',  'lukas',   2, 1, true,  0,  0, 0, 1.0, 'Card',        'sale', 'Family trip, snorkelling on the way back'),
 ('MJL003', 42, 'Coastal Boat Tours', NULL,          'sophie',  2, 0, false, 0,  0, 0, 1.0, 'QR',          'sale', 'LankaQR at the jetty'),
 ('MJL004', 41, 'Whale Watching',     NULL,          'daniel',  1, 0, false, 0,  0, 0, 1.0, 'Cash',        'sale', 'Walk-up, 06:30 sailing'),
 ('MJL005', 40, 'Deep Sea Fishing',   NULL,          'oliver',  2, 0, true,  0,  0, 0, 1.0, 'Card',        'sale', 'Full-day charter share'),
 ('MJL006', 38, 'Whale Watching',     NULL,          'yuki',    2, 2, true,  0,  0, 0, 1.0, 'Card',        'sale', 'Two children at the child fare'),
 ('MJL007', 37, 'Photo Tours',        NULL,          'maria',   1, 0, false, 0,  0, 0, 1.0, 'Card',        'sale', 'Photography morning, small group'),
 ('MJL008', 36, 'Whale Watching',     NULL,          'arjun',   4, 0, true,  5,  0, 0, 1.0, 'Cash',        'sale', 'Group of four, 5% desk discount'),
 ('MJL009', 35, 'Snorkeling',         NULL,          'nadeeka', 2, 1, false, 0,  0, 0, 1.0, 'QR',          'sale', 'Reef trip, Colombo weekenders'),
 ('MJL010', 34, 'Whale Watching',     NULL,          'ruwan',   2, 0, false, 0,  0, 0, 1.0, 'Cash',        'sale', 'Local rate, cash at the counter'),
 ('MJL011', 32, 'Scuba Diving',       NULL,          'lukas',   1, 0, false, 0,  0, 0, 1.0, 'Card',        'sale', 'Certified diver, own log'),
 ('MJL012', 31, 'Whale Watching',     'Photo Tours', 'emma',    2, 0, true,  0,  0, 0, 1.0, 'Card',        'sale', 'Added the photo package on board'),
 ('MJL013', 30, 'Coastal Boat Tours', NULL,          'daniel',  3, 0, false, 0,  0, 0, 1.0, 'Cash',        'sale', 'Sunset run'),
 ('MJL014', 28, 'Whale Watching',     NULL,          'sophie',  2, 1, true,  0,  0, 0, 1.0, 'QR',          'sale', 'Blue whale sighting confirmed'),
 ('MJL015', 27, 'Whale Watching',     NULL,          'yuki',    2, 0, false, 0,  0, 0, 1.0, 'Card',        'sale', 'Second trip this stay'),
 ('MJL016', 25, 'Deep Sea Fishing',   NULL,          'ruwan',   2, 0, false, 0,  0, 0, 1.0, 'BankTransfer','sale', 'Paid ahead by transfer'),
 ('MJL017', 24, 'Whale Watching',     'Snorkeling',  'oliver',  2, 0, true,  0,  0, 0, 1.0, 'Card',        'sale', 'Surf camp group'),
 ('MJL018', 22, 'Snorkeling',         NULL,          'maria',   2, 0, false, 0,  0, 0, 1.0, 'Cash',        'sale', 'Morning reef session'),
 ('MJL019', 21, 'Whale Watching',     NULL,          'arjun',   2, 2, true,  0,  0, 0, 1.0, 'Card',        'sale', 'Family of four'),
 ('MJL020', 19, 'Photo Tours',        NULL,          'nadeeka', 2, 0, false, 0,  0, 0, 1.0, 'QR',          'sale', 'Photo tour for two'),
 ('MJL021', 18, 'Whale Watching',     NULL,          'emma',    1, 0, false, 0,  0, 0, 1.0, 'Cash',        'sale', 'Last-minute single seat'),
 ('MJL022', 16, 'Coastal Boat Tours', NULL,          'yuki',    2, 1, true,  0,  0, 0, 1.0, 'Card',        'sale', 'Calm-sea coastal run'),
 ('MJL023', 14, 'Whale Watching',     NULL,          'maria',   2, 0, true,  0,  0, 0, 1.0, 'Card',        'sale', 'Hotel pickup from Mirissa Beach'),
 ('MJL024', 12, 'Scuba Diving',       NULL,          'oliver',  2, 0, false, 0,  0, 0, 1.0, 'Card',        'sale', 'Two-tank dive'),
 ('MJL025', 11, 'Whale Watching',     NULL,          'daniel',  3, 0, true,  0,  0, 0, 1.0, 'QR',          'sale', 'Hostel group of three'),
 ('MJL026',  9, 'Whale Watching',     NULL,          'sophie',  2, 0, false, 0,  0, 0, 1.0, 'Cash',        'sale', 'Repeat guest'),
 ('MJL027',  7, 'Snorkeling',         NULL,          'lukas',   2, 2, true,  0,  0, 0, 1.0, 'Card',        'sale', 'Family reef trip'),
 ('MJL028',  5, 'Whale Watching',     NULL,          'nadeeka', 2, 0, false, 0,  0, 0, 1.0, 'QR',          'sale', 'Weekend trip from Colombo'),
 ('MJL029',  3, 'Whale Watching',     'Photo Tours', 'arjun',   2, 1, true,  0,  0, 0, 1.0, 'Card',        'sale', 'Photo package added at the desk'),
 ('MJL030',  1, 'Coastal Boat Tours', NULL,          'ruwan',   4, 0, false, 0,  0, 0, 1.0, 'Cash',        'sale', 'Yesterday''s sunset run'),
 -- Deposits taken, balance still due ----------------------------------------
 ('MJL031', 10, 'Deep Sea Fishing',   NULL,          'oliver',  4, 0, true,  0,  7, 0, 0.5, 'BankTransfer','sale', 'Half-day charter, 50% deposit'),
 ('MJL032',  6, 'Whale Watching',     NULL,          'paradise',8, 2, true,  0, 14, 1, 0.5, 'BankTransfer','sale', 'Hotel block booking, deposit received'),
 ('MJL033',  4, 'Scuba Diving',       NULL,          'maria',   2, 0, false, 0,  7, 0, 0.5, 'Card',        'sale', 'Course deposit'),
 -- Trade accounts, invoiced on credit and not yet due ------------------------
 ('MJL034',  8, 'Whale Watching',     NULL,          'ocean',   6, 2, true, 12, 14, NULL, 0, 'BankTransfer','sale', 'Ocean Breeze allocation - September week 3'),
 ('MJL035',  5, 'Coastal Boat Tours', NULL,          'paradise',6, 0, true, 10, 14, NULL, 0, 'BankTransfer','sale', 'Paradise Beach Club sunset block'),
 ('MJL036',  2, 'Whale Watching',     'Snorkeling',  'ocean',   4, 1, true, 12, 14, NULL, 0, 'BankTransfer','sale', 'Agent booking, invoice issued'),
 -- Overdue trade invoices (what the aging buckets and the chaser read) -------
 ('MJL037', 45, 'Whale Watching',     NULL,          'ocean',   8, 0, true, 12, 14, NULL, 0, 'BankTransfer','sale', 'August allocation - unpaid, chased twice'),
 ('MJL038', 39, 'Whale Watching',     NULL,          'paradise',10,4, true, 10, 14, NULL, 0, 'BankTransfer','sale', 'Hotel block - unpaid past terms'),
 ('MJL039', 29, 'Deep Sea Fishing',   NULL,          'ocean',   4, 0, false,12, 14, NULL, 0, 'BankTransfer','sale', 'Charter for an agent group - overdue'),
 ('MJL040', 20, 'Photo Tours',        NULL,          'paradise',4, 0, true, 10, 14, NULL, 0, 'BankTransfer','sale', 'Photo tour block - just past due'),
 -- Exceptions ---------------------------------------------------------------
 ('MJL041', 17, 'Whale Watching',     NULL,          'yuki',    2, 1, true,  0,  0, 0, 1.0, 'Card',        'cancelled-refund','Sea state 6 - sailing cancelled, refunded in full'),
 ('MJL042', 13, 'Whale Watching',     NULL,          'emma',    2, 0, false, 0,  0, 0, 1.0, 'Card',        'card-declined',   'First card declined, second attempt cleared');

-- Fares. The catalogue price is what the guest is quoted and is therefore
-- the gross; the line items carry it net of the 18% VAT it contains.
--
-- The bill is built from the gross so it lands exactly on the quoted price -
-- 2 x LKR 7,500 is an invoice for 15,000.00, not 14,999.99 - and the VAT
-- column takes up the rounding, which is how a VAT-inclusive price works.
-- The engine's own rule (FinalAmount = subtotal - discount + tax) still
-- holds line for line, and the effective rate stays 18.00%.
CREATE TEMP TABLE _mjl_invoice AS
WITH fares AS (
  SELECT bt."Name" AS tour,
         ((bt."ConfigJson"::jsonb -> 'pricing' ->> 'adult')::numeric) AS adult_gross,
         COALESCE((bt."ConfigJson"::jsonb -> 'pricing' ->> 'child')::numeric, 0) AS child_gross,
         round(((bt."ConfigJson"::jsonb -> 'pricing' ->> 'adult')::numeric) / 1.18, 2) AS adult_net,
         round((COALESCE((bt."ConfigJson"::jsonb -> 'pricing' ->> 'child')::numeric, 0)) / 1.18, 2) AS child_net
  FROM booking_types bt JOIN _mjl_ctx c ON bt."TenantId" = c.tenant_id
  WHERE bt."DeletedAt" IS NULL
),
priced AS (
  SELECT s.*,
         g.user_id,
         f.adult_net, f.child_net,
         af.adult_net AS addon_net,
         ((current_date - s.days_ago)::timestamp + interval '6 hours 15 minutes') AT TIME ZONE 'Asia/Colombo' AS issued_at,
         -- Net of VAT: the invoice's line items, and its TotalAmount.
         round(s.adults * f.adult_net + s.children * f.child_net
               + COALESCE(s.adults * af.adult_net, 0), 2) AS subtotal,
         -- Gross: the price on the board at the jetty.
         round(s.adults * f.adult_gross + s.children * f.child_gross
               + COALESCE(s.adults * af.adult_gross, 0), 2) AS gross
  FROM _mjl_sales s
  JOIN _mjl_guest g ON g.label = s.guest
  JOIN fares f ON f.tour = s.tour
  LEFT JOIN fares af ON af.tour = s.addon
),
billed AS (
  SELECT p.*,
         round(p.gross * p.disc_pct / 100, 2) AS gross_discount,
         round(round(p.gross * p.disc_pct / 100, 2) / 1.18, 2) AS discount
  FROM priced p
)
SELECT b.*,
       gen_random_uuid() AS invoice_id,
       b.gross - b.gross_discount AS final_amount,
       (b.gross - b.gross_discount) - (b.subtotal - b.discount) AS tax,
       b.issued_at + (b.due_days || ' days')::interval AS due_at
FROM billed b;

-- Invoices. Status follows from the money, so it can never contradict the
-- payments below: cancelled trips are Cancelled, a deposit leaves
-- PartiallyPaid, and an unpaid invoice is Overdue only once its terms lapse.
INSERT INTO invoices
  ("Id","TenantId","BranchId","CustomerId","BookingId","SubscriptionId","TemplateId",
   "InvoiceNumber","TotalAmount","Discount","DiscountCode","Tax","FinalAmount","Status",
   "DueDate","Currency","Notes","ScheduleGroup","ScheduleLabel","LastReminderAt",
   "CreatedAt","UpdatedAt")
SELECT i.invoice_id, ctx.tenant_id, ctx.branch_id, i.user_id, NULL, NULL, NULL,
       'INV-' || to_char(i.issued_at AT TIME ZONE 'Asia/Colombo', 'YYYYMMDD') || '-' || i.seq,
       i.subtotal, i.discount,
       CASE WHEN i.disc_pct > 0 THEN 'TRADE' || i.disc_pct::int END,
       i.tax, i.final_amount,
       CASE
         WHEN i.kind = 'cancelled-refund'                     THEN 'Cancelled'
         WHEN i.pay_after IS NULL                             THEN
              CASE WHEN i.due_at < now() THEN 'Overdue' ELSE 'Issued' END
         WHEN i.pay_share < 1                                 THEN 'PartiallyPaid'
         ELSE 'Paid'
       END,
       i.due_at, 'LKR',
       i.note || ' · ' || i.tour ||
         CASE WHEN i.addon IS NOT NULL THEN ' + ' || i.addon ELSE '' END,
       -- The charter deposits are half of a two-part schedule; the balance
       -- invoice is raised when the trip runs.
       CASE WHEN i.pay_share = 0.5 THEN 'SCH-' || i.seq END,
       CASE WHEN i.pay_share = 0.5 THEN 'Deposit (50%)' END,
       -- Overdue trade accounts have been chased; the automation spaces the
       -- next reminder off this stamp.
       CASE WHEN i.pay_after IS NULL AND i.due_at < now() THEN now() - interval '4 days' END,
       i.issued_at, i.issued_at
FROM _mjl_invoice i, _mjl_ctx ctx
WHERE NOT EXISTS (
  SELECT 1 FROM invoices x
   WHERE x."TenantId" = ctx.tenant_id
     AND x."InvoiceNumber" = 'INV-' || to_char(i.issued_at AT TIME ZONE 'Asia/Colombo', 'YYYYMMDD') || '-' || i.seq);

-- Line items: adult seats, child seats, the optional add-on tour, and the
-- hotel transfer, which the catalogue prices at zero because it is included.
INSERT INTO invoice_items
  ("Id","InvoiceId","Description","Quantity","UnitPrice","Amount","Category","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), i.invoice_id,
       i.tour || ' - adult', i.adults, i.adult_net, round(i.adults * i.adult_net, 2),
       'Tour', i.issued_at, i.issued_at
FROM _mjl_invoice i
WHERE i.adults > 0 AND EXISTS (SELECT 1 FROM invoices x WHERE x."Id" = i.invoice_id)
  AND NOT EXISTS (SELECT 1 FROM invoice_items it WHERE it."InvoiceId" = i.invoice_id);

INSERT INTO invoice_items
  ("Id","InvoiceId","Description","Quantity","UnitPrice","Amount","Category","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), i.invoice_id,
       i.tour || ' - child', i.children, i.child_net, round(i.children * i.child_net, 2),
       'Tour', i.issued_at, i.issued_at
FROM _mjl_invoice i
WHERE i.children > 0 AND EXISTS (SELECT 1 FROM invoices x WHERE x."Id" = i.invoice_id)
  AND NOT EXISTS (SELECT 1 FROM invoice_items it WHERE it."InvoiceId" = i.invoice_id AND it."Description" LIKE '%- child');

INSERT INTO invoice_items
  ("Id","InvoiceId","Description","Quantity","UnitPrice","Amount","Category","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), i.invoice_id,
       i.addon || ' (add-on)', i.adults, i.addon_net, round(i.adults * i.addon_net, 2),
       'Add-on', i.issued_at, i.issued_at
FROM _mjl_invoice i
WHERE i.addon IS NOT NULL AND EXISTS (SELECT 1 FROM invoices x WHERE x."Id" = i.invoice_id)
  AND NOT EXISTS (SELECT 1 FROM invoice_items it WHERE it."InvoiceId" = i.invoice_id AND it."Category" = 'Add-on');

INSERT INTO invoice_items
  ("Id","InvoiceId","Description","Quantity","UnitPrice","Amount","Category","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), i.invoice_id,
       'Hotel pickup & drop-off (within 3 km) - included', 1, 0, 0,
       'Transfer', i.issued_at, i.issued_at
FROM _mjl_invoice i
WHERE i.pickup AND EXISTS (SELECT 1 FROM invoices x WHERE x."Id" = i.invoice_id)
  AND NOT EXISTS (SELECT 1 FROM invoice_items it WHERE it."InvoiceId" = i.invoice_id AND it."Category" = 'Transfer');

-- Payments. Cash and bank transfers are recorded by the desk (Manual);
-- cards and LankaQR come through the gateway.
INSERT INTO payments
  ("Id","InvoiceId","Amount","Method","Provider","Status","PayerLabel",
   "TransactionRef","GatewayResponse","PaidAt","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), i.invoice_id,
       round(i.final_amount * i.pay_share, 2), i.method,
       CASE WHEN i.method IN ('Card','QR') THEN 'Stripe' ELSE 'Manual' END,
       'Succeeded',
       CASE WHEN i.pay_share < 1 THEN 'Deposit' END,
       'MJL-' || i.seq || '-01', NULL,
       i.issued_at + (i.pay_after || ' days')::interval,
       i.issued_at + (i.pay_after || ' days')::interval,
       i.issued_at + (i.pay_after || ' days')::interval
FROM _mjl_invoice i
WHERE i.pay_after IS NOT NULL
  AND EXISTS (SELECT 1 FROM invoices x WHERE x."Id" = i.invoice_id)
  AND NOT EXISTS (SELECT 1 FROM payments p WHERE p."InvoiceId" = i.invoice_id AND p."TransactionRef" = 'MJL-' || i.seq || '-01');

-- The cancelled sailing: the guest was refunded the same afternoon, so the
-- money in and the money back both belong in the day's takings.
INSERT INTO payments
  ("Id","InvoiceId","Amount","Method","Provider","Status","PayerLabel",
   "TransactionRef","GatewayResponse","PaidAt","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), i.invoice_id, i.final_amount, i.method, 'Stripe', 'Refunded', NULL,
       'MJL-' || i.seq || '-RF', 'Refunded in full - sailing cancelled, sea state 6.',
       i.issued_at + interval '8 hours', i.issued_at + interval '8 hours', i.issued_at + interval '8 hours'
FROM _mjl_invoice i
WHERE i.kind = 'cancelled-refund'
  AND EXISTS (SELECT 1 FROM invoices x WHERE x."Id" = i.invoice_id)
  AND NOT EXISTS (SELECT 1 FROM payments p WHERE p."InvoiceId" = i.invoice_id AND p."TransactionRef" = 'MJL-' || i.seq || '-RF');

-- The declined card, kept on the invoice so the retry is visible. Failed
-- payments never count toward the balance.
INSERT INTO payments
  ("Id","InvoiceId","Amount","Method","Provider","Status","PayerLabel",
   "TransactionRef","GatewayResponse","PaidAt","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), i.invoice_id, i.final_amount, 'Card', 'Stripe', 'Failed', NULL,
       'MJL-' || i.seq || '-FL', 'card_declined: insufficient_funds',
       NULL, i.issued_at - interval '6 minutes', i.issued_at - interval '6 minutes'
FROM _mjl_invoice i
WHERE i.kind = 'card-declined'
  AND EXISTS (SELECT 1 FROM invoices x WHERE x."Id" = i.invoice_id)
  AND NOT EXISTS (SELECT 1 FROM payments p WHERE p."InvoiceId" = i.invoice_id AND p."TransactionRef" = 'MJL-' || i.seq || '-FL');

-- ── 5) Travel-insurance claims ──────────────────────────────────────────────
-- Not medical cover: these are the guests' own travel policies reimbursing a
-- trip the weather cancelled, which is what a tour operator actually files.
INSERT INTO insurance_claims
  ("Id","InvoiceId","Provider","PolicyNumber","ClaimAmount","Status","SubmittedAt",
   "ReviewStartedAt","ApprovedAt","RejectionReason","Notes","DocumentsJson","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), i.invoice_id, v.provider, v.policy,
       round(i.final_amount * v.share, 2), v.status,
       now() - (v.submitted_days || ' days')::interval,
       CASE WHEN v.status = 'UnderReview' THEN now() - (v.submitted_days - 2 || ' days')::interval END,
       NULL, NULL, v.notes, NULL,
       now() - (v.submitted_days || ' days')::interval, now()
FROM _mjl_invoice i
JOIN (VALUES
  ('MJL041', 'Ceylinco Travel Shield', 'CTS-2026-448120', 1.0,  'Submitted',   9,
   'Sailing cancelled by sea state; guest claiming the full fare back.'),
  ('MJL039', 'Sri Lanka Insurance',    'SLI/TR/2026/7741', 0.6, 'UnderReview', 6,
   'Group charter cut short by weather; partial reimbursement under the agent policy.')
) AS v(seq, provider, policy, share, status, submitted_days, notes) ON v.seq = i.seq
WHERE EXISTS (SELECT 1 FROM invoices x WHERE x."Id" = i.invoice_id)
  AND NOT EXISTS (SELECT 1 FROM insurance_claims c WHERE c."InvoiceId" = i.invoice_id);

COMMIT;

-- ── What landed ─────────────────────────────────────────────────────────────
-- Re-run this block on its own any time to see the tenant's billing position.
SELECT i."Status",
       count(*)                                      AS invoices,
       round(sum(i."FinalAmount"), 2)                AS billed,
       -- Netted the way the reports do it: a refund is money going back out.
       round(sum(COALESCE(p.collected, 0)), 2)       AS collected,
       round(sum(i."FinalAmount" - COALESCE(p.paid, 0)), 2) AS outstanding
FROM invoices i
LEFT JOIN LATERAL (
  SELECT sum(x."Amount") FILTER (WHERE x."Status" = 'Succeeded') AS paid,
         sum(CASE x."Status" WHEN 'Succeeded' THEN x."Amount"
                             WHEN 'Refunded'  THEN -x."Amount" END) AS collected
    FROM payments x WHERE x."InvoiceId" = i."Id"
) p ON true
WHERE i."TenantId" = 'f15bae97-fa7e-42f5-95b7-b624db319ad2'::uuid
GROUP BY i."Status"
ORDER BY billed DESC;
