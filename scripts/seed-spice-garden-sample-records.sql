-- ============================================================================
-- Sample RECORDS for the "Spice Garden Restaurant" (Colombo 06) tenant, so
-- every panel of the restaurant operations dashboard has something to show.
--
-- Works on its own: if the tenant from scripts/seed-demo-data.ps1 exists it
-- is reused (matched by name + BusinessType 'Restaurant'); otherwise the
-- tenant, its admin and its branch are created here.
--
--   1) Resources        - 6 tables (Room), 3 kitchen stations (Equipment),
--                         2 delivery riders (Vehicle), 5 staff (Staff, with
--                         hourly rates and a weekly roster)
--   2) Menu types       - dine-in lunch / dinner, takeaway, home delivery,
--                         private event; each with serviceMode, a prep-time
--                         target and a recipe in ConfigJson
--   3) Inventory        - the 10 F&B items from seed-inventory-all-tenants
--                         (skipped if that seed already ran) + 3 waste entries
--   4) Staff logins     - manager and head chef, to see the role-based views
--   5) Customers        - 8 guests
--   6) Orders           - 38 bookings over the last 6 days, today and the
--                         next 2 days, every stage represented, with kitchen
--                         start / ready / served stamps so ticket-time,
--                         on-time and SLA figures have data
--
-- Everything here is DEMO DATA: guests, staff, phone numbers, prices and
-- stock levels are invented. Emails use the reserved example-demo.test
-- domain and every login created HERE has the password  Passw0rd!
-- (If the tenant already existed from seed-demo-data.ps1, its admin keeps
-- that script's password, Demo@12345.)
--
-- Times are written in Sri Lanka time (Asia/Colombo) and stored as
-- timestamptz. "Today" is today in Colombo.
--
-- Idempotent: reference rows are guarded per row (email / code / slug /
-- sku / reference); the orders block is guarded per tenant and written
-- once, because it is relative to "today". Wrapped in one transaction.
--
--   psql "$DATABASE_URL" -f scripts/seed-spice-garden-sample-records.sql
-- ============================================================================

BEGIN;

-- ── 0) Context: tenant, admin, branch ───────────────────────────────────────
DROP TABLE IF EXISTS _seed_ctx;
DROP TABLE IF EXISTS _seed_branch;
DROP TABLE IF EXISTS _seed_res;
DROP TABLE IF EXISTS _seed_bt;
DROP TABLE IF EXISTS _seed_cust;
DROP TABLE IF EXISTS _seed_orders;

CREATE TEMP TABLE _seed_ctx AS
SELECT t."Id" AS tenant_id,
       (SELECT u."Id" FROM "Users" u
         WHERE u."TenantId" = t."Id" AND u."Role" = 0
         ORDER BY u."CreatedAt" LIMIT 1) AS admin_user_id
FROM "Tenants" t
WHERE t."Name" = 'Spice Garden Restaurant' AND lower(t."BusinessType") = 'restaurant';

DO $$
DECLARE n integer; t_id uuid; u_id uuid;
BEGIN
  SELECT count(*) INTO n FROM _seed_ctx;
  IF n > 1 THEN
    RAISE EXCEPTION '% tenants are named "Spice Garden Restaurant" - pin one by Id in the _seed_ctx query.', n;
  END IF;
  IF n = 0 THEN
    t_id := gen_random_uuid();
    u_id := gen_random_uuid();
    INSERT INTO "Tenants"
      ("Id","CreatedAt","UpdatedAt","Name","BusinessType","SubType","IsActive",
       "CancellationCutoffHours","RescheduleCutoffHours","ReviewCount",
       "ShortTagline","Description","ContactPhone","ContactEmail")
    VALUES (t_id, now(), now(), 'Spice Garden Restaurant', 'Restaurant', NULL, true, 1, 2, 0,
            'Sri Lankan seafood & curry - Marine Drive, Colombo 06',
            'Family-run restaurant on Marine Drive serving Sri Lankan seafood, rice and curry, with takeaway and home delivery across Colombo 03-06.',
            '+94112987654', 'hello@spicegarden.lk');
    INSERT INTO "Users"
      ("Id","CreatedAt","UpdatedAt","TenantId","Email","PasswordHash","FullName","Phone","Role","IsActive","IsApproved")
    VALUES (u_id, now(), now(), t_id, 'admin@spicegarden.lk',
            '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
            'Chaminda Rathnayake', '+94772345678', 0, true, true);
    INSERT INTO _seed_ctx (tenant_id, admin_user_id) VALUES (t_id, u_id);
  END IF;
  IF (SELECT admin_user_id FROM _seed_ctx) IS NULL THEN
    RAISE EXCEPTION 'Tenant has no Admin user - walk-in orders below are created by one.';
  END IF;
END $$;

INSERT INTO "Branches" ("Id","CreatedAt","UpdatedAt","TenantId","Name","Address","Phone","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, 'Marine Drive', '12 Marine Drive, Colombo 06', '+94112987654', true
FROM _seed_ctx ctx
WHERE NOT EXISTS (SELECT 1 FROM "Branches" b WHERE b."TenantId" = ctx.tenant_id);

CREATE TEMP TABLE _seed_branch AS
SELECT b."Id" AS branch_id
FROM "Branches" b JOIN _seed_ctx ctx ON b."TenantId" = ctx.tenant_id
ORDER BY b."CreatedAt" LIMIT 1;

-- Users created by seed-demo-data.ps1 may have no branch; the dashboard's
-- Manager/Staff branch scoping needs one.
UPDATE "Users" u SET "BranchId" = br.branch_id
FROM _seed_ctx ctx, _seed_branch br
WHERE u."TenantId" = ctx.tenant_id AND u."BranchId" IS NULL;

-- Colombo-local "day offset + time of day" -> timestamptz.
CREATE OR REPLACE FUNCTION pg_temp.lk(day_offset int, t time) RETURNS timestamptz
LANGUAGE sql STABLE AS $$
  SELECT (((now() AT TIME ZONE 'Asia/Colombo')::date + day_offset) + t) AT TIME ZONE 'Asia/Colombo';
$$;

-- ── 1) Resources ────────────────────────────────────────────────────────────
-- Category: Room = table, Equipment = kitchen station, Vehicle = delivery
-- rider, Staff = staff member (HourlyRate drives the labor figures).
INSERT INTO "resources"
  ("Id","TenantId","BranchId","Name","Code","Category","Specialty","Status",
   "Capacity","HourlyRate","Description","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id,
       v.name, v.code, v.category, v.specialty, 'Available', v.capacity, v.rate, v.description, now(), now()
FROM _seed_ctx ctx, _seed_branch br,
(VALUES
  -- tables
  ('Table 1 - Window (2)',        'SGR-T01',      'Room',      'Indoor',     2, NULL, 'Two-seater by the window.'),
  ('Table 2 - Window (2)',        'SGR-T02',      'Room',      'Indoor',     2, NULL, 'Two-seater by the window.'),
  ('Table 3 - Family (4)',        'SGR-T03',      'Room',      'Indoor',     4, NULL, 'Four-seater, main room.'),
  ('Table 4 - Family (4)',        'SGR-T04',      'Room',      'Indoor',     4, NULL, 'Four-seater, main room.'),
  ('Garden Terrace (6)',          'SGR-T05',      'Room',      'Outdoor',    6, NULL, 'Six-seater on the terrace.'),
  ('Private Dining Room (10)',    'SGR-T06',      'Room',      'Private',   10, NULL, 'Private room for events.'),
  -- kitchen stations
  ('Grill Station',               'SGR-ST-GRILL', 'Equipment', 'Grill',      NULL, NULL, 'Seafood and meat grill; takeaway grill orders are ticketed here.'),
  ('Curry Station',               'SGR-ST-CURRY', 'Equipment', 'Curry',      NULL, NULL, 'Rice and curry line; takeaway curry orders are ticketed here.'),
  ('Cold Prep & Bar',             'SGR-ST-BAR',   'Equipment', 'Bar',        NULL, NULL, 'Salads, desserts and drinks.'),
  -- delivery riders
  ('Rider - Kasun (bike)',        'SGR-RD-01',    'Vehicle',   'Delivery',   NULL, NULL, 'Delivery rider, Colombo 03-06.'),
  ('Rider - Nuwan (bike)',        'SGR-RD-02',    'Vehicle',   'Delivery',   NULL, NULL, 'Delivery rider, Colombo 03-06.'),
  -- staff (hourly rate in LKR)
  ('Sunil Perera',                'SGR-STF-01',   'Staff',     'Head Chef',  NULL, 1200, 'Runs the kitchen.'),
  ('Malith Silva',                'SGR-STF-02',   'Staff',     'Line Cook',  NULL,  700, 'Curry and grill.'),
  ('Dilhani Fernando',            'SGR-STF-03',   'Staff',     'Server',     NULL,  550, 'Lunch service.'),
  ('Tharindu Jayasuriya',         'SGR-STF-04',   'Staff',     'Server',     NULL,  550, 'Dinner service.'),
  ('Ishara Wijesekara',           'SGR-STF-05',   'Staff',     'Cashier',    NULL,  600, 'Till and phone orders.')
) AS v(name, code, category, specialty, capacity, rate, description)
WHERE NOT EXISTS (SELECT 1 FROM "resources" r WHERE r."TenantId" = ctx.tenant_id AND r."Code" = v.code);

CREATE TEMP TABLE _seed_res AS
SELECT r."Id" AS resource_id, r."Code" AS code
FROM "resources" r JOIN _seed_ctx ctx ON r."TenantId" = ctx.tenant_id
WHERE r."Code" LIKE 'SGR-%';

-- Roster: one row per weekday per staff member (DayOfWeek 0 = Sunday).
-- Chef and cook cover the whole day with an afternoon break; servers split
-- lunch / dinner; the cashier works through.
INSERT INTO "resource_schedules"
  ("Id","CreatedAt","UpdatedAt","ResourceId","DayOfWeek","StartTime","EndTime",
   "IsAvailable","LunchBreakStart","LunchBreakEnd")
SELECT gen_random_uuid(), now(), now(), r.resource_id, d.dow,
       v.start_t, v.end_t, true, v.break_s, v.break_e
FROM _seed_res r
JOIN (VALUES
  ('SGR-STF-01', TIME '10:00', TIME '22:00', TIME '15:00', TIME '17:00'),
  ('SGR-STF-02', TIME '11:00', TIME '22:00', TIME '15:00', TIME '16:30'),
  ('SGR-STF-03', TIME '11:00', TIME '16:00', NULL,         NULL),
  ('SGR-STF-04', TIME '17:00', TIME '22:30', NULL,         NULL),
  ('SGR-STF-05', TIME '11:00', TIME '22:00', TIME '15:00', TIME '16:30')
) AS v(code, start_t, end_t, break_s, break_e) ON v.code = r.code
CROSS JOIN generate_series(0, 6) AS d(dow)
WHERE NOT EXISTS (SELECT 1 FROM "resource_schedules" s WHERE s."ResourceId" = r.resource_id);

-- Tables, stations and riders are open every day 11:00-22:00.
INSERT INTO "resource_schedules"
  ("Id","CreatedAt","UpdatedAt","ResourceId","DayOfWeek","StartTime","EndTime","IsAvailable")
SELECT gen_random_uuid(), now(), now(), r.resource_id, d.dow, TIME '11:00', TIME '22:00', true
FROM _seed_res r CROSS JOIN generate_series(0, 6) AS d(dow)
WHERE r.code NOT LIKE 'SGR-STF-%'
  AND NOT EXISTS (SELECT 1 FROM "resource_schedules" s WHERE s."ResourceId" = r.resource_id);

-- ── 2) Menu types ───────────────────────────────────────────────────────────
-- ConfigJson carries the restaurant settings RestaurantConfig reads:
-- serviceMode, prepTargetMinutes and the recipe (SKUs from section 3;
-- perCover lines scale with the order's AttendeeCount). Recipes are
-- consumed from stock when an order is started on the feed.
INSERT INTO "booking_types"
  ("Id","TenantId","Name","Slug","Description","ColorHex","Status",
   "DefaultDurationMinutes","RequiresApproval","MaxParticipants",
   "BufferMinutesBefore","BufferMinutesAfter","BookingUnit",
   "ConfigJson","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id,
       v.name, v.slug, v.description, v.color, 'Active',
       v.minutes, v.approval, v.max_pax, 0, v.buffer, 'Slot',
       v.config::jsonb, now(), now()
FROM _seed_ctx ctx,
(VALUES
  ('Lunch - Dine-in', 'sgr-lunch-dine-in',
   'Table for lunch service, 11:00-16:00. Rice & curry, seafood platters.',
   '#F59E0B', 75, false, 10, 15,
   '{"serviceMode":"dine-in","prepTargetMinutes":20,"basePrice":{"amount":2800,"currency":"LKR","per":"cover"},
     "recipe":[{"sku":"RICE-001","qty":0.004,"perCover":true},{"sku":"PROT-001","qty":0.25,"perCover":true},{"sku":"CONS-001","qty":0.1,"perCover":true}]}'),
  ('Dinner - Dine-in', 'sgr-dinner-dine-in',
   'Table for dinner service, 17:00-22:00.',
   '#DC2626', 120, false, 10, 15,
   '{"serviceMode":"dine-in","prepTargetMinutes":25,"basePrice":{"amount":4200,"currency":"LKR","per":"cover"},
     "recipe":[{"sku":"RICE-001","qty":0.005,"perCover":true},{"sku":"PROT-002","qty":0.2,"perCover":true},{"sku":"CONS-001","qty":0.1,"perCover":true}]}'),
  ('Takeaway', 'sgr-takeaway',
   'Collect at the counter. Ticketed to the grill or curry station.',
   '#0EA5E9', 20, false, 6, 0,
   '{"serviceMode":"takeaway","prepTargetMinutes":15,"basePrice":{"amount":2200,"currency":"LKR","per":"cover"},
     "recipe":[{"sku":"RICE-001","qty":0.004,"perCover":true},{"sku":"PROT-001","qty":0.25,"perCover":true},{"sku":"PACK-001","qty":0.01,"perCover":true}]}'),
  ('Home Delivery', 'sgr-delivery',
   'Delivered by our riders across Colombo 03-06, or via Uber Eats / PickMe Food.',
   '#7C3AED', 45, false, 6, 0,
   '{"serviceMode":"delivery","prepTargetMinutes":20,"basePrice":{"amount":2600,"currency":"LKR","per":"cover"},"deliveryFee":350,
     "recipe":[{"sku":"RICE-001","qty":0.004,"perCover":true},{"sku":"PROT-001","qty":0.25,"perCover":true},{"sku":"PACK-001","qty":0.01,"perCover":true}]}'),
  ('Private Dining Event', 'sgr-private-event',
   'Private dining room for parties and corporate dinners. Needs approval.',
   '#0F766E', 240, true, 10, 30,
   '{"serviceMode":"dine-in","prepTargetMinutes":40,"basePrice":{"amount":6500,"currency":"LKR","per":"cover"}}')
) AS v(name, slug, description, color, minutes, approval, max_pax, buffer, config)
WHERE NOT EXISTS (SELECT 1 FROM "booking_types" bt WHERE bt."TenantId" = ctx.tenant_id AND bt."Slug" = v.slug);

CREATE TEMP TABLE _seed_bt AS
SELECT bt."Id" AS bt_id, bt."Slug" AS slug, bt."DefaultDurationMinutes" AS minutes
FROM "booking_types" bt JOIN _seed_ctx ctx ON bt."TenantId" = ctx.tenant_id
WHERE bt."Slug" LIKE 'sgr-%';

-- ── 3) Inventory ────────────────────────────────────────────────────────────
-- Same items and figures as seed-inventory-all-tenants.sql; skipped per SKU
-- if that seed already ran. Curry leaves and takeaway boxes sit below
-- their reorder level on purpose.
INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id,
       v.name, v.sku, v.description, v.qty, v.reorder, v.cost, true, now(), now()
FROM _seed_ctx ctx, _seed_branch br,
(VALUES
  ('Basmati Rice 50kg',                     'RICE-001',  'Premium long-grain basmati rice sack',        12,  5, 9800.00),
  ('Ceylon Coconut Milk 400ml (x12 cans)',  'CONS-001',  'First-pressed coconut milk',                  24, 10, 2640.00),
  ('Ceylon Cinnamon Sticks 500g',           'SPICE-001', 'True Ceylon cinnamon, Grade C5',               6,  5, 1850.00),
  ('Cooking Oil - Sunflower 5L',            'OIL-001',   'Refined sunflower cooking oil',               15,  8, 2200.00),
  ('Chicken Fillet 1kg (frozen)',           'PROT-001',  'Boneless chicken breast, IQF frozen',         40, 20, 1350.00),
  ('Prawns Large (1kg frozen)',             'PROT-002',  'Tiger prawns 16/20 size, IQF',                18, 10, 2800.00),
  ('Curry Leaves Fresh (500g)',             'HERB-001',  'Fresh curry leaves, Colombo market',           3,  5,  180.00),
  ('Takeaway Boxes - Large (x100)',         'PACK-001',  'Kraft paper containers',                       4, 10, 1400.00),
  ('LPG Cylinder 12.5kg',                   'GAS-001',   'Commercial cooking gas cylinder',              3,  2, 3800.00),
  ('Cutlery Set - Stainless Steel',         'EQUIP-001', 'Forks, knives, spoons set (x24)',              2,  2, 4500.00)
) AS v(name, sku, description, qty, reorder, cost)
WHERE NOT EXISTS (SELECT 1 FROM "InventoryItems" i WHERE i."TenantId" = ctx.tenant_id AND i."Sku" = v.sku);

-- Waste log: Notes are "Reason: detail", which is how the waste endpoint
-- writes them and how the dashboard groups them.
INSERT INTO "StockMovements"
  ("Id","TenantId","InventoryItemId","BranchId","MovementType","Quantity","UnitCost","Reference","Notes","OccurredAt","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, i."Id", i."BranchId",
       'Waste', -v.qty, i."UnitCost", v.reference, v.notes,
       pg_temp.lk(v.day, v.at_time), now(), now()
FROM (VALUES
  ('PROT-002', 2,   'WASTE-SGR-0001', 'Spoiled: freezer door left open overnight',         -4, TIME '09:30'),
  ('HERB-001', 1,   'WASTE-SGR-0002', 'Expired: wilted, past use-by',                      -2, TIME '10:15'),
  ('CONS-001', 3,   'WASTE-SGR-0003', 'Over-prepped: curry base left from a quiet dinner', -1, TIME '22:10'),
  ('PROT-001', 1,   'WASTE-SGR-0004', 'Dropped / spilled: tray knocked off the pass',       0, TIME '12:40')
) AS v(sku, qty, reference, notes, day, at_time)
JOIN _seed_ctx ctx ON true
JOIN "InventoryItems" i ON i."TenantId" = ctx.tenant_id AND i."Sku" = v.sku
WHERE NOT EXISTS (SELECT 1 FROM "StockMovements" m WHERE m."InventoryItemId" = i."Id" AND m."Reference" = v.reference);

-- ── 4) Staff logins ─────────────────────────────────────────────────────────
-- Role: 0 Admin, 1 Manager, 2 Staff, 3 Customer. The manager sees the
-- floor view, the chef the kitchen view (no revenue).
INSERT INTO "Users"
  ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","Email","PasswordHash",
   "FullName","Phone","Role","IsActive","IsApproved")
SELECT gen_random_uuid(), now() - interval '120 days', now(), ctx.tenant_id, br.branch_id,
       v.email, '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
       v.full_name, v.phone, v.role, true, true
FROM _seed_ctx ctx, _seed_branch br,
(VALUES
  ('manager.spicegarden@example-demo.test', 'Nadeesha Karunaratne', '+94770223344', 1),
  ('chef.spicegarden@example-demo.test',    'Sunil Perera',         '+94770223355', 2),
  ('cashier.spicegarden@example-demo.test', 'Ishara Wijesekara',    '+94770223366', 2)
) AS v(email, full_name, phone, role)
WHERE NOT EXISTS (SELECT 1 FROM "Users" u WHERE lower(u."Email") = v.email);

-- ── 5) Customers ────────────────────────────────────────────────────────────
INSERT INTO "Users"
  ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","Email","PasswordHash",
   "FullName","Phone","Role","IsActive","IsApproved","Address")
SELECT gen_random_uuid(), now() - (v.days_ago || ' days')::interval, now(), ctx.tenant_id, br.branch_id,
       v.email, '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
       v.full_name, v.phone, 3, true, true, v.address
FROM _seed_ctx ctx, _seed_branch br,
(VALUES
  ('manoji.weerasinghe@example-demo.test',  'Manoji Weerasinghe',   '+94771230001', 'Bambalapitiya, Colombo 04', 300),
  ('ranjith.fernando@example-demo.test',    'Ranjith Fernando',     '+94771230002', 'Wellawatte, Colombo 06',    250),
  ('kushan.wickrama@example-demo.test',     'Kushan Wickrama',      '+94771230003', 'Kollupitiya, Colombo 03',   180),
  ('shehan.abey@example-demo.test',         'Shehan Abeywickrama',  '+94771230004', 'Havelock Town, Colombo 05', 120),
  ('charith.jaya@example-demo.test',        'Charith Jayawardena',  '+94771230005', 'Wellawatte, Colombo 06',     60),
  ('anushka.sena@example-demo.test',        'Anushka Senanayake',   '+94771230006', 'Bambalapitiya, Colombo 04',  30),
  ('emma.clarke@example-demo.test',         'Emma Clarke',          '+447700900123', 'Hotel - Galle Face',        10),
  ('harsha.desilva@example-demo.test',      'Harsha De Silva',      '+94771230008', 'Kirulapone, Colombo 05',      5)
) AS v(email, full_name, phone, address, days_ago)
WHERE NOT EXISTS (SELECT 1 FROM "Users" u WHERE lower(u."Email") = v.email);

CREATE TEMP TABLE _seed_cust AS
SELECT u."Id" AS user_id, split_part(u."Email", '.', 1) AS label   -- manoji, ranjith, ...
FROM "Users" u JOIN _seed_ctx ctx ON u."TenantId" = ctx.tenant_id
WHERE u."Role" = 3 AND u."Email" LIKE '%@example-demo.test';

-- ── 6) Orders ───────────────────────────────────────────────────────────────
-- One row per order. Columns:
--   day/start : offset from today (Colombo) and local start time
--   res / bt  : resource code / menu-type slug     cust : customer label
--   status    : booking status (Pending=new, Confirmed=accepted,
--               CheckedIn=preparing, InProgress=ready, Completed=served)
--   source    : channel - POS | Online | Phone | Uber Eats | PickMe Food
--   pax/cost  : covers and LKR total (0 when cancelled/rejected)
--   ks/rd/sv  : minutes relative to start for kitchen start / ready /
--               served (NULL = not reached); negative = before start
--   made      : minutes ago the order was placed (NULL = 2 days before)
--   reason    : cancellation / rejection reason
CREATE TEMP TABLE _seed_orders (
  n int, day int, start time, res text, bt text, cust text, status text, source text,
  pax int, cost numeric, ks int, rd int, sv int, made int, reason text, title text, notes text
);
INSERT INTO _seed_orders VALUES
-- ── last week ──
 ( 1, -6, '12:30', 'SGR-T03',      'sgr-lunch-dine-in',  'manoji',  'Completed', 'POS',         4, 11200,   5,  22,  70, NULL, NULL, 'Table - Manoji Weerasinghe', 'Seafood platter x2, rice & curry x2'),
 ( 2, -6, '13:00', 'SGR-ST-CURRY', 'sgr-takeaway',       'kushan',  'Completed', 'Phone',       2,  4400,   0,  12,  16, NULL, NULL, 'Takeaway - Kushan Wickrama', 'Chicken curry rice x2'),
 ( 3, -6, '19:30', 'SGR-T05',      'sgr-dinner-dine-in', 'ranjith', 'Completed', 'Online',      6, 25200,  10,  28, 105, NULL, NULL, 'Table - Ranjith Fernando', 'Birthday - cake at 20:30'),
 ( 4, -6, '20:00', 'SGR-RD-01',    'sgr-delivery',       'charith', 'Completed', 'Uber Eats',   2,  5550,   0,  18,  42, NULL, NULL, 'Delivery - Charith Jayawardena', 'Prawn curry, 2 portions'),
 ( 5, -5, '12:00', 'SGR-T01',      'sgr-lunch-dine-in',  'anushka', 'Completed', 'Online',      2,  5600,   4,  19,  62, NULL, NULL, 'Table - Anushka Senanayake', NULL),
 ( 6, -5, '13:15', 'SGR-ST-GRILL', 'sgr-takeaway',       'harsha',  'Completed', 'POS',         3,  6600,   0,  21,  24, NULL, NULL, 'Takeaway - Harsha De Silva', 'Grilled fish x3 - ran late, grill backed up'),
 ( 7, -5, '19:00', 'SGR-T04',      'sgr-dinner-dine-in', 'shehan',  'NoShow',    'Online',      4,     0, NULL, NULL, NULL, NULL, NULL, 'Table - Shehan Abeywickrama', NULL),
 ( 8, -5, '20:30', 'SGR-RD-02',    'sgr-delivery',       'emma',    'Completed', 'PickMe Food', 1,  2950,   0,  15,  38, NULL, NULL, 'Delivery - Emma Clarke', 'Hotel delivery, mild spice'),
 ( 9, -4, '12:45', 'SGR-T02',      'sgr-lunch-dine-in',  'kushan',  'Completed', 'POS',         2,  5600,   3,  17,  55, NULL, NULL, 'Table - Kushan Wickrama', NULL),
 (10, -4, '19:00', 'SGR-T06',      'sgr-private-event',  'shehan',  'Completed', 'Phone',      10, 65000,  15,  45, 220, NULL, NULL, 'Event - Shehan Abeywickrama', 'Corporate dinner, set menu. Approved.'),
 (11, -4, '19:45', 'SGR-RD-01',    'sgr-delivery',       'manoji',  'Cancelled', 'Uber Eats',   3,     0, NULL, NULL, NULL, NULL, 'Customer cancelled after 25 min quoted delivery time.', 'Delivery - Manoji Weerasinghe', NULL),
 (12, -3, '12:15', 'SGR-T03',      'sgr-lunch-dine-in',  'ranjith', 'Completed', 'Online',      4, 11200,   6,  24,  75, NULL, NULL, 'Table - Ranjith Fernando', NULL),
 (13, -3, '13:30', 'SGR-ST-CURRY', 'sgr-takeaway',       'anushka', 'Completed', 'Phone',       1,  2200,   0,  11,  14, NULL, NULL, 'Takeaway - Anushka Senanayake', NULL),
 (14, -3, '19:30', 'SGR-T05',      'sgr-dinner-dine-in', 'charith', 'Completed', 'POS',         5, 21000,   8,  30,  95, NULL, NULL, 'Table - Charith Jayawardena', 'Family dinner'),
 (15, -3, '20:15', 'SGR-RD-02',    'sgr-delivery',       'harsha',  'Completed', 'Online',      2,  5550,   0,  16,  40, NULL, NULL, 'Delivery - Harsha De Silva', NULL),
 (16, -2, '12:00', 'SGR-T04',      'sgr-lunch-dine-in',  'emma',    'Completed', 'POS',         3,  8400,   5,  18,  60, NULL, NULL, 'Table - Emma Clarke', 'Asked for a vegetarian curry set'),
 (17, -2, '13:00', 'SGR-ST-GRILL', 'sgr-takeaway',       'manoji',  'Completed', 'POS',         2,  4400,   0,  13,  15, NULL, NULL, 'Takeaway - Manoji Weerasinghe', NULL),
 (18, -2, '19:00', 'SGR-T01',      'sgr-dinner-dine-in', 'kushan',  'Completed', 'Online',      2,  8400,   6,  22,  80, NULL, NULL, 'Table - Kushan Wickrama', 'Anniversary'),
 (19, -2, '20:45', 'SGR-RD-01',    'sgr-delivery',       'ranjith', 'Completed', 'PickMe Food', 4, 10750,   0,  27,  55, NULL, NULL, 'Delivery - Ranjith Fernando', 'Large order, ran over target'),
 (20, -1, '12:30', 'SGR-T05',      'sgr-lunch-dine-in',  'shehan',  'Completed', 'Phone',       6, 16800,   8,  26,  85, NULL, NULL, 'Table - Shehan Abeywickrama', 'Office lunch'),
 (21, -1, '13:45', 'SGR-ST-CURRY', 'sgr-takeaway',       'charith', 'Completed', 'Online',      2,  4400,   0,  14,  17, NULL, NULL, 'Takeaway - Charith Jayawardena', NULL),
 (22, -1, '19:15', 'SGR-T03',      'sgr-dinner-dine-in', 'anushka', 'Completed', 'Online',      4, 16800,   7,  24,  90, NULL, NULL, 'Table - Anushka Senanayake', NULL),
 (23, -1, '20:00', 'SGR-T02',      'sgr-dinner-dine-in', 'harsha',  'Rejected',  'Online',      2,     0, NULL, NULL, NULL, NULL, 'Fully booked for 20:00 - offered 21:00, guest declined.', 'Table - Harsha De Silva', NULL),
 (24, -1, '20:30', 'SGR-RD-02',    'sgr-delivery',       'emma',    'Completed', 'Uber Eats',   1,  2950,   0,  17,  36, NULL, NULL, 'Delivery - Emma Clarke', NULL),
-- ── today ──
 (25,  0, '11:30', 'SGR-ST-GRILL', 'sgr-takeaway',       'kushan',  'Completed',  'POS',         1,  2200,   0,  12,  14, NULL, NULL, 'Takeaway - Kushan Wickrama', NULL),
 (26,  0, '12:00', 'SGR-T03',      'sgr-lunch-dine-in',  'manoji',  'Completed',  'Online',      4, 11200,   5,  21,  68, NULL, NULL, 'Table - Manoji Weerasinghe', NULL),
 (27,  0, '12:15', 'SGR-T01',      'sgr-lunch-dine-in',  'emma',    'InProgress', 'POS',         2,  5600,   4,  20, NULL, NULL, NULL, 'Table - Emma Clarke', 'Mains served, dessert to follow'),
 (28,  0, '12:30', 'SGR-T05',      'sgr-lunch-dine-in',  'ranjith', 'CheckedIn',  'Phone',       6, 16800,   6, NULL, NULL, NULL, NULL, 'Table - Ranjith Fernando', 'Seated on the terrace'),
 (29,  0, '12:40', 'SGR-ST-CURRY', 'sgr-takeaway',       'charith', 'CheckedIn',  'Online',      2,  4400,   0, NULL, NULL, NULL, NULL, 'Takeaway - Charith Jayawardena', 'Collecting at 13:00'),
 (30,  0, '12:45', 'SGR-RD-01',    'sgr-delivery',       'anushka', 'Confirmed',  'Uber Eats',   2,  5550, NULL, NULL, NULL,   18, NULL, 'Delivery - Anushka Senanayake', 'Prawn curry x2, extra sambol'),
 (31,  0, '12:50', 'SGR-RD-02',    'sgr-delivery',       'harsha',  'Pending',    'PickMe Food', 3,  8150, NULL, NULL, NULL,   14, NULL, 'Delivery - Harsha De Silva', 'Chicken curry rice x3'),
 (32,  0, '13:00', 'SGR-T02',      'sgr-lunch-dine-in',  'shehan',  'Pending',    'Online',      2,  5600, NULL, NULL, NULL,    3, NULL, 'Table - Shehan Abeywickrama', 'Window table if possible'),
 (33,  0, '19:00', 'SGR-T04',      'sgr-dinner-dine-in', 'kushan',  'Confirmed',  'Online',      4, 16800, NULL, NULL, NULL, NULL, NULL, 'Table - Kushan Wickrama', NULL),
 (34,  0, '19:30', 'SGR-T05',      'sgr-dinner-dine-in', 'manoji',  'Confirmed',  'Phone',       6, 25200, NULL, NULL, NULL, NULL, NULL, 'Table - Manoji Weerasinghe', 'Family gathering'),
 (35,  0, '20:00', 'SGR-T06',      'sgr-private-event',  'ranjith', 'Pending',    'Phone',       8, 52000, NULL, NULL, NULL, NULL, NULL, 'Event - Ranjith Fernando', 'Awaiting approval - set menu B'),
-- ── coming days ──
 (36,  1, '12:30', 'SGR-T03',      'sgr-lunch-dine-in',  'emma',    'Confirmed',  'Online',      3,  8400, NULL, NULL, NULL, NULL, NULL, 'Table - Emma Clarke', NULL),
 (37,  1, '19:00', 'SGR-T06',      'sgr-private-event',  'shehan',  'Confirmed',  'Phone',      10, 65000, NULL, NULL, NULL, NULL, NULL, 'Event - Shehan Abeywickrama', 'Approved. Corporate dinner.'),
 (38,  2, '19:30', 'SGR-T05',      'sgr-dinner-dine-in', 'charith', 'Confirmed',  'Online',      5, 21000, NULL, NULL, NULL, NULL, NULL, 'Table - Charith Jayawardena', NULL);

INSERT INTO "bookings"
  ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes",
   "StartTime","EndTime","Status","Priority","AttendeeCount","Source",
   "CheckInAt","ConsultationStartedAt","CheckOutAt",
   "ApprovedBy","ApprovedAt","CancellationReason","RejectionReason",
   "TotalCost","ReminderSent","CreatedBy","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, c.user_id,
       o.title, o.notes,
       pg_temp.lk(o.day, o.start),
       pg_temp.lk(o.day, o.start) + (bt.minutes || ' minutes')::interval,
       o.status, 'Normal', o.pax, o.source,
       CASE WHEN o.ks IS NOT NULL THEN pg_temp.lk(o.day, o.start) + (o.ks || ' minutes')::interval END,
       CASE WHEN o.rd IS NOT NULL THEN pg_temp.lk(o.day, o.start) + (o.rd || ' minutes')::interval END,
       CASE WHEN o.sv IS NOT NULL THEN pg_temp.lk(o.day, o.start) + (o.sv || ' minutes')::interval END,
       CASE WHEN o.bt = 'sgr-private-event' AND o.status <> 'Pending' THEN ctx.admin_user_id END,
       CASE WHEN o.bt = 'sgr-private-event' AND o.status <> 'Pending' THEN pg_temp.lk(o.day, o.start) - interval '2 days' END,
       CASE WHEN o.status = 'Cancelled' THEN o.reason END,
       CASE WHEN o.status = 'Rejected'  THEN o.reason END,
       o.cost,
       o.day <= 0,
       CASE WHEN o.source IN ('POS','Phone') THEN ctx.admin_user_id END,
       CASE WHEN o.made IS NOT NULL THEN now() - (o.made || ' minutes')::interval
            ELSE LEAST(pg_temp.lk(o.day, o.start) - interval '2 days', now()) END,
       LEAST(pg_temp.lk(o.day, o.start), now()),
       1
FROM _seed_orders o
JOIN _seed_ctx  ctx ON true
JOIN _seed_res  r   ON r.code  = o.res
JOIN _seed_bt   bt  ON bt.slug = o.bt
JOIN _seed_cust c   ON c.label = o.cust
-- Run-once per tenant: the orders are relative to today, so a re-run on a
-- later day would land a second, shifted copy. Delete the tenant's seeded
-- orders (titles in _seed_orders) to regenerate them.
WHERE NOT EXISTS (
  SELECT 1 FROM "bookings" b
  WHERE b."TenantId" = ctx.tenant_id AND b."Title" IN (SELECT title FROM _seed_orders)
);

-- Every row above must have resolved a resource, menu type and customer;
-- a typo would otherwise just silently drop that order.
DO $$
DECLARE missing text;
BEGIN
  SELECT string_agg(o.n::text, ', ') INTO missing
  FROM _seed_orders o
  WHERE NOT EXISTS (SELECT 1 FROM _seed_res  WHERE code  = o.res)
     OR NOT EXISTS (SELECT 1 FROM _seed_bt   WHERE slug  = o.bt)
     OR NOT EXISTS (SELECT 1 FROM _seed_cust WHERE label = o.cust);
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'Orders % reference an unknown resource code, menu-type slug or customer label.', missing;
  END IF;
END $$;

COMMIT;

-- ── Summary ─────────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM "resources" r JOIN _seed_ctx c ON r."TenantId" = c.tenant_id AND r."Code" LIKE 'SGR-%')     AS resources,
  (SELECT count(*) FROM "booking_types" bt JOIN _seed_ctx c ON bt."TenantId" = c.tenant_id AND bt."Slug" LIKE 'sgr-%') AS menu_types,
  (SELECT count(*) FROM "resource_schedules" s JOIN _seed_res r ON s."ResourceId" = r.resource_id)                      AS schedule_rows,
  (SELECT count(*) FROM "Users" u JOIN _seed_ctx c ON u."TenantId" = c.tenant_id AND u."Role" = 3)                      AS customers,
  (SELECT count(*) FROM "Users" u JOIN _seed_ctx c ON u."TenantId" = c.tenant_id AND u."Role" IN (1,2))                 AS staff_logins,
  (SELECT count(*) FROM "bookings" b JOIN _seed_ctx c ON b."TenantId" = c.tenant_id)                                    AS orders,
  (SELECT count(*) FROM "InventoryItems" i JOIN _seed_ctx c ON i."TenantId" = c.tenant_id)                              AS inventory_items,
  (SELECT count(*) FROM "StockMovements" m JOIN _seed_ctx c ON m."TenantId" = c.tenant_id AND m."MovementType" = 'Waste') AS waste_entries;

-- Logins:
--   admin@spicegarden.lk                     owner view   (Admin)  - Demo@12345 if
--                                            seed-demo-data.ps1 made it, else Passw0rd!
--   manager.spicegarden@example-demo.test    floor view   (Manager) - Passw0rd!
--   chef.spicegarden@example-demo.test       kitchen view (Staff, no revenue) - Passw0rd!
