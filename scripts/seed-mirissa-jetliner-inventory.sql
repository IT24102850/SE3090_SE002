-- ============================================================================
-- Seed: Mirissa Jetliner - inventory, stock movements and sales
-- ============================================================================
--
-- Purpose
--   Give the whale-watching tenant a realistic operational inventory so the
--   Inventory Analytics dashboard (/inventory-analytics) and the mobile
--   inventory app have real database rows to read. Every panel on that
--   dashboard reads from a table this file writes to:
--
--     Stock levels / Stock risk split   InventoryItems   (Quantity vs ReorderLevel)
--     Inventory movement mix / Stock issued   StockMovements   (last 30 days)
--     Revenue trends / Revenue KPI      Sales            (last 30 days)
--
--   Booking outcomes and Patient counts read Bookings and Users, which this
--   file does not touch - see seed-mirissa-jetliner-departures.sql for
--   bookings.
--
-- Provenance
--   SOURCED     ticket prices (LKR 7,500 adult / 4,000 child) and the two
--               daily departures, both published on the operator's book-now
--               page - same figures the packages seed uses.
--   ASSUMPTION  everything else. Item names are what a whale-watching boat
--               operator plausibly stocks; quantities, reorder levels, unit
--               costs, supplier names, passenger counts and consumption rates
--               are illustrative and chosen to exercise every dashboard
--               state (healthy, low, out of stock; received and issued).
--               None of it is data from Mirissa Jetliner.
--
-- Prerequisite
--   The "Sales" table arrives with migration 20260908170219_AddSalesLedger,
--   which is applied when the backend starts on the merge/inventory-analytics
--   branch (Program.cs runs Migrate() on startup). If the table is not there
--   yet the sales section is skipped with a NOTICE rather than failing the
--   whole transaction - re-run this file after the backend has started once.
--
-- Safe to re-run. Items upsert on (TenantId, Sku); movements and sales
-- tagged SEED-MJ-* are replaced, not duplicated.
--
-- Run
--   psql "$DATABASE_URL" -f scripts/seed-mirissa-jetliner-inventory.sql
-- ============================================================================

BEGIN;

-- ── Pin the tenant ──────────────────────────────────────────────────────────
-- Pinned by explicit id, NOT by admin email: this database carries two
-- tenants sharing wowwhales@gmail.com -
--   f15bae97-fa7e-42f5-95b7-b624db319ad2  "Mirissa JetLiner"  (created 2026-08-14)
--   d303c4ef-6eb9-4189-95e0-b537d2134ba9  "Mirissa Jetliner"  (created 2026-09-09)
-- List them yourself with:
--   SELECT t."Id", t."Name", t."SubType", t."CreatedAt"::date, u."Email"
--   FROM "Tenants" t JOIN "Users" u ON u."TenantId" = t."Id" AND u."Role" = 0
--   WHERE t."Name" ILIKE '%mirissa%' ORDER BY t."CreatedAt";
--
-- CHANGE THIS to the tenant you sign in to.
DROP TABLE IF EXISTS _seed_ctx;
CREATE TEMP TABLE _seed_ctx AS
SELECT 'f15bae97-fa7e-42f5-95b7-b624db319ad2'::uuid AS tenant_id;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n
  FROM "Tenants" t JOIN _seed_ctx ctx ON t."Id" = ctx.tenant_id;
  IF n <> 1 THEN
    RAISE EXCEPTION
      'The tenant id in _seed_ctx matches % rows in "Tenants". Set it to a real tenant id - see the listing query above.', n;
  END IF;
END $$;

-- Movements and sales hang off a branch; take the tenant's first.
DROP TABLE IF EXISTS _seed_branch;
CREATE TEMP TABLE _seed_branch AS
SELECT b."Id" AS branch_id
FROM "Branches" b, _seed_ctx ctx
WHERE b."TenantId" = ctx.tenant_id
ORDER BY b."CreatedAt"
LIMIT 1;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _seed_branch;
  IF n <> 1 THEN
    RAISE EXCEPTION 'The tenant has no branch. Create one in Business Settings first.';
  END IF;
END $$;

-- ── Categories ──────────────────────────────────────────────────────────────
INSERT INTO "InventoryCategories" ("Id","TenantId","Name","IsActive","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, v.name, true, now(), now()
FROM _seed_ctx ctx,
     (VALUES ('Safety'), ('Fuel & Engine'), ('Guest Supplies'), ('Refreshments'), ('Equipment')) AS v(name)
WHERE NOT EXISTS (
  SELECT 1 FROM "InventoryCategories" c
  WHERE c."TenantId" = ctx.tenant_id AND c."Name" = v.name
);

-- ── Units ───────────────────────────────────────────────────────────────────
INSERT INTO "InventoryUnits" ("Id","TenantId","Code","Name","IsActive","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, v.code, v.name, true, now(), now()
FROM _seed_ctx ctx,
     (VALUES ('pcs','Pieces'), ('L','Litres'), ('kg','Kilograms'), ('box','Boxes'), ('strip','Strips')) AS v(code, name)
WHERE NOT EXISTS (
  SELECT 1 FROM "InventoryUnits" u
  WHERE u."TenantId" = ctx.tenant_id AND u."Code" = v.code
);

-- ── Suppliers ───────────────────────────────────────────────────────────────
-- ASSUMPTION: names are illustrative.
INSERT INTO "Suppliers" ("Id","TenantId","Name","Email","Phone","IsActive","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, v.name, v.email, v.phone, true, now(), now()
FROM _seed_ctx ctx,
     (VALUES
       ('Lanka Marine Supplies',      'orders@lankamarine.example',   '+94 91 222 0101'),
       ('Mirissa Fuel Depot',         'depot@mirissafuel.example',    '+94 41 225 0202'),
       ('Southern Provisions (Pvt)',  'sales@southernprov.example',   '+94 41 223 0303')
     ) AS v(name, email, phone)
WHERE NOT EXISTS (
  SELECT 1 FROM "Suppliers" s
  WHERE s."TenantId" = ctx.tenant_id AND s."Name" = v.name
);

-- ── Items ───────────────────────────────────────────────────────────────────
-- ASSUMPTION throughout. "Quantity" is on-hand as of seeding; the movements
-- below are the 30-day history the usage report reads. The two are not
-- reconciled to an opening balance - the report does not need them to be,
-- and the point is to land every stock state on the dashboard:
--
--   healthy   Quantity >= ReorderLevel
--   low       Quantity <  ReorderLevel          (low-stock filter)
--   out       Quantity <= 0                     (low-stock filter, red)
--
-- Costs in LKR.
INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","CategoryId","UnitId","Name","Sku","Description",
   "Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id,
       (SELECT "Id" FROM "InventoryCategories" WHERE "TenantId" = ctx.tenant_id AND "Name" = v.category),
       (SELECT "Id" FROM "InventoryUnits"      WHERE "TenantId" = ctx.tenant_id AND "Code" = v.unit),
       v.name, v.sku, v.description, v.qty, v.reorder, v.cost, true, now(), now()
FROM _seed_ctx ctx
CROSS JOIN _seed_branch br
CROSS JOIN (VALUES
       -- Safety                                                                                 qty  reorder   cost
       ('Safety',         'pcs',   'Life jacket - adult',            'MJ-SAF-001', 'SOLAS-type adult PFD, orange',               48,    40,   3200),
       ('Safety',         'pcs',   'Life jacket - child',            'MJ-SAF-002', 'Child PFD 15-40 kg',                          6,    12,   2800),  -- low
       ('Safety',         'box',   'First-aid kit - marine',         'MJ-SAF-003', 'Sealed marine kit, one per vessel',           2,     3,   4500),  -- low
       ('Safety',         'box',   'Distress flare kit',             'MJ-SAF-004', 'Hand flares x4 + smoke x2, dated',            0,     2,  12000),  -- OUT
       ('Safety',         'pcs',   'Throw ring with line',           'MJ-SAF-005', '30 m floating line',                          5,     4,   6800),
       -- Fuel & Engine
       ('Fuel & Engine',  'L',     'Marine diesel',                  'MJ-FUE-001', 'Bunkered at Mirissa harbour',               640,   500,    340),
       ('Fuel & Engine',  'L',     'Engine oil 15W-40',              'MJ-FUE-002', 'Marine grade, 4 L drums',                     8,    20,   1850),  -- low
       ('Fuel & Engine',  'pcs',   'Fuel filter element',            'MJ-FUE-003', 'Primary filter, per engine service',          3,     4,   3600),  -- low
       ('Fuel & Engine',  'pcs',   'Impeller kit',                   'MJ-FUE-004', 'Raw-water pump impeller',                     4,     2,   5200),
       -- Guest Supplies
       ('Guest Supplies', 'strip', 'Seasickness tablets',            'MJ-GST-001', 'Strip of 10, offered at boarding',           14,    30,    180),  -- low
       ('Guest Supplies', 'pcs',   'Rain poncho - disposable',       'MJ-GST-002', 'Handed out in the wet season',              120,    60,     95),
       ('Guest Supplies', 'pcs',   'Binoculars - loaner',            'MJ-GST-003', '8x42, one per four guests',                  10,     8,   8500),
       ('Guest Supplies', 'pcs',   'Sun hat - branded',              'MJ-GST-004', 'Sold on board',                              22,    25,    650),  -- low
       -- Refreshments
       ('Refreshments',   'pcs',   'Drinking water 500 ml',          'MJ-REF-001', 'One per guest, more on hot days',           240,   300,     55),  -- low
       ('Refreshments',   'pcs',   'Snack pack',                     'MJ-REF-002', 'Biscuits + banana, per guest',               90,   120,    220),  -- low
       ('Refreshments',   'kg',    'Fresh fruit',                    'MJ-REF-003', 'Bought the morning of',                       0,    10,    380),  -- OUT
       ('Refreshments',   'pcs',   'Tea / coffee sachets',           'MJ-REF-004', 'Served on the return leg',                  310,   150,     40),
       -- Equipment
       ('Equipment',      'pcs',   'Sighting log book',              'MJ-EQP-001', 'One per vessel per month',                    4,     2,    650),
       ('Equipment',      'pcs',   'Hydrophone battery pack',        'MJ-EQP-002', 'Rechargeable, spares',                        3,     2,   9800)
     ) AS v(category, unit, name, sku, description, qty, reorder, cost)
ON CONFLICT ("TenantId","Sku") DO UPDATE
SET "Quantity"     = EXCLUDED."Quantity",
    "ReorderLevel" = EXCLUDED."ReorderLevel",
    "UnitCost"     = EXCLUDED."UnitCost",
    "Name"         = EXCLUDED."Name",
    "Description"  = EXCLUDED."Description",
    "CategoryId"   = EXCLUDED."CategoryId",
    "UnitId"       = EXCLUDED."UnitId",
    "BranchId"     = EXCLUDED."BranchId",
    "IsActive"     = true,
    "UpdatedAt"    = now();

-- ── Stock movements: the last 30 days ───────────────────────────────────────
-- The usage report classifies by sign: positive Quantity is received,
-- negative is issued. MovementType strings match what the API itself writes
-- ("Receive" for deliveries, "Adjustment" for everything else).
DELETE FROM "StockMovements" m
USING _seed_ctx ctx
WHERE m."TenantId" = ctx.tenant_id AND m."Reference" LIKE 'SEED-MJ-%';

-- Deliveries: a handful of receipts spread over the window.
INSERT INTO "StockMovements"
  ("Id","TenantId","BranchId","InventoryItemId","SupplierId","PurchaseOrderId",
   "MovementType","Quantity","UnitCost","Reference","OccurredAt","Notes","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id, i."Id",
       (SELECT "Id" FROM "Suppliers" WHERE "TenantId" = ctx.tenant_id AND "Name" = v.supplier),
       NULL,
       'Receive', v.qty, i."UnitCost",
       'SEED-MJ-RCV-' || v.sku || '-' || v.days_ago,
       now() - (v.days_ago || ' days')::interval + time '07:30',
       'Delivery, ' || v.supplier, now(), now()
FROM _seed_ctx ctx
CROSS JOIN _seed_branch br
CROSS JOIN (VALUES
       ('MJ-REF-001', 'Southern Provisions (Pvt)',  600, 27),
       ('MJ-REF-001', 'Southern Provisions (Pvt)',  600, 13),
       ('MJ-REF-002', 'Southern Provisions (Pvt)',  240, 27),
       ('MJ-REF-002', 'Southern Provisions (Pvt)',  240, 12),
       ('MJ-REF-004', 'Southern Provisions (Pvt)',  400, 20),
       ('MJ-GST-001', 'Southern Provisions (Pvt)',   60, 25),
       ('MJ-GST-002', 'Lanka Marine Supplies',      200, 22),
       ('MJ-FUE-001', 'Mirissa Fuel Depot',        1200, 28),
       ('MJ-FUE-001', 'Mirissa Fuel Depot',        1200, 18),
       ('MJ-FUE-001', 'Mirissa Fuel Depot',        1200,  8),
       ('MJ-FUE-002', 'Lanka Marine Supplies',       16, 24),
       ('MJ-SAF-002', 'Lanka Marine Supplies',        6, 29)
     ) AS v(sku, supplier, qty, days_ago)
JOIN "InventoryItems" i ON i."TenantId" = ctx.tenant_id AND i."Sku" = v.sku;

-- Consumption: two departures a day (SOURCED), so the consumables go out
-- every day. The per-day figure wobbles with the day of month so the bars
-- are not flat - a real week is not flat either.
INSERT INTO "StockMovements"
  ("Id","TenantId","BranchId","InventoryItemId","SupplierId","PurchaseOrderId",
   "MovementType","Quantity","UnitCost","Reference","OccurredAt","Notes","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id, i."Id", NULL, NULL,
       'Adjustment',
       -1 * (v.per_day + ((extract(day from d)::int * 7) % v.wobble)),
       i."UnitCost",
       'SEED-MJ-USE-' || v.sku || '-' || to_char(d, 'YYYYMMDD'),
       d + time '16:45',
       'Issued for the day''s departures', now(), now()
FROM _seed_ctx ctx
CROSS JOIN _seed_branch br
CROSS JOIN generate_series((now() - interval '29 days')::date, now()::date, interval '1 day') AS d
CROSS JOIN (VALUES
       -- sku          per_day  wobble
       ('MJ-REF-001',      36,      9),   -- water: ~40 guests/day
       ('MJ-REF-002',      14,      6),
       ('MJ-REF-004',      12,      5),
       ('MJ-GST-001',       2,      2),
       ('MJ-FUE-001',     110,     30),   -- diesel: two sailings
       ('MJ-GST-002',       3,      6)    -- ponchos: weather-dependent
     ) AS v(sku, per_day, wobble)
JOIN "InventoryItems" i ON i."TenantId" = ctx.tenant_id AND i."Sku" = v.sku;

-- One engine service in the window: oil and a filter.
INSERT INTO "StockMovements"
  ("Id","TenantId","BranchId","InventoryItemId","SupplierId","PurchaseOrderId",
   "MovementType","Quantity","UnitCost","Reference","OccurredAt","Notes","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id, i."Id", NULL, NULL,
       'Adjustment', v.qty, i."UnitCost",
       'SEED-MJ-SVC-' || v.sku,
       now() - interval '9 days' + time '10:00',
       '250-hour engine service', now(), now()
FROM _seed_ctx ctx
CROSS JOIN _seed_branch br
CROSS JOIN (VALUES ('MJ-FUE-002', -8), ('MJ-FUE-003', -1), ('MJ-FUE-004', -1)) AS v(sku, qty)
JOIN "InventoryItems" i ON i."TenantId" = ctx.tenant_id AND i."Sku" = v.sku;

-- ── Sales: the last 30 days ─────────────────────────────────────────────────
-- Guarded: the table only exists once AddSalesLedger has been applied.
DO $$
DECLARE
  ctx_tenant uuid;
  ctx_branch uuid;
BEGIN
  IF to_regclass('"Sales"') IS NULL THEN
    RAISE NOTICE 'Skipping sales: "Sales" table not present yet. Start the backend on merge/inventory-analytics once (it applies AddSalesLedger), then re-run this file.';
    RETURN;
  END IF;

  SELECT tenant_id INTO ctx_tenant FROM _seed_ctx;
  SELECT branch_id INTO ctx_branch FROM _seed_branch;

  DELETE FROM "Sales" WHERE "TenantId" = ctx_tenant AND "Reference" LIKE 'SEED-MJ-%';

  -- Two departures a day (SOURCED: 06:30 and 10:00). Passenger counts are
  -- ASSUMPTION - the AM sailing runs fuller. Amount = adults x 7,500 +
  -- children x 4,000, the SOURCED published prices. Weekends carry more.
  INSERT INTO "Sales" ("Id","TenantId","BranchId","OccurredAt","Amount","Reference","CreatedAt","UpdatedAt")
  SELECT gen_random_uuid(), ctx_tenant, ctx_branch,
         d + s.at,
         (s.adults + CASE WHEN extract(isodow from d) >= 6 THEN 6 ELSE 0 END
                   + ((extract(day from d)::int * 3) % 5)) * 7500
         + (s.children + ((extract(day from d)::int) % 3)) * 4000,
         'SEED-MJ-DEP-' || to_char(d, 'YYYYMMDD') || '-' || s.tag,
         now(), now()
  FROM generate_series((now() - interval '29 days')::date, now()::date, interval '1 day') AS d,
       (VALUES ('AM', time '06:30', 22, 4), ('PM', time '10:00', 14, 2)) AS s(tag, at, adults, children);
END $$;

-- ── What the dashboard will now read ────────────────────────────────────────
SELECT
  (SELECT count(*) FROM "InventoryItems" i, _seed_ctx c WHERE i."TenantId" = c.tenant_id AND i."IsActive")                              AS items,
  (SELECT count(*) FROM "InventoryItems" i, _seed_ctx c WHERE i."TenantId" = c.tenant_id AND i."IsActive"
     AND (i."Quantity" <= 0 OR i."Quantity" < i."ReorderLevel"))                                                                        AS low_or_out,
  (SELECT count(*) FROM "StockMovements" m, _seed_ctx c WHERE m."TenantId" = c.tenant_id AND m."Reference" LIKE 'SEED-MJ-%')           AS movements_30d,
  (SELECT count(*) FROM "Suppliers" s, _seed_ctx c WHERE s."TenantId" = c.tenant_id)                                                    AS suppliers,
  CASE WHEN to_regclass('"Sales"') IS NULL THEN 'Sales table not present - see NOTICE'
       ELSE (SELECT 'LKR ' || to_char(coalesce(sum("Amount"),0), 'FM999,999,999')
             FROM "Sales" s, _seed_ctx c WHERE s."TenantId" = c.tenant_id AND s."Reference" LIKE 'SEED-MJ-%') END                      AS revenue_30d;

COMMIT;
