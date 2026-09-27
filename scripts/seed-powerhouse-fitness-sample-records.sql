-- ============================================================================
-- Sample RECORDS for the "PowerHouse Fitness" (Nugegoda) gym tenant, so
-- every panel of the gym operations dashboard has something to show.
--
-- Works on its own: if the tenant from scripts/seed-demo-data.ps1 exists it
-- is reused (matched by name + BusinessType Gym); otherwise the tenant,
-- its admin and its branch are created here. Needs the Subscriptions table
-- (migration 20260918_AddGymMembershipsAndDemographics - start the API once).
--
--   1) Module config    - capacity, revenue targets, maintenance threshold
--   2) Resources        - 5 zones (Room, with capacity), 5 trainers (Staff,
--                         rostered; the 3 from seed-demo-data get codes)
--   3) Activities       - gym access, HIIT / yoga / spin classes (capacity),
--                         personal training, day pass; each with a "kind"
--   4) Equipment        - 7 machine models with units, service history and
--                         one overdue / one in-progress maintenance
--   5) Staff logins     - manager and front desk, for the role-based views
--   6) Members          - 24 members with date of birth and gender
--   7) Memberships      - Basic / Standard / Premium / Student / Annual;
--                         active, frozen, expired, cancelled; pending, failed
--                         and overdue billings; renewals due this week
--   8) Visits           - ~230 check-ins over the last 4 weeks, generated
--                         deterministically (morning / lunch / evening
--                         crowds, weekends later, RFID / app / biometric /
--                         desk), several still inside right now
--   9) Classes          - 4 weeks of HIIT, yoga and spin sessions with
--                         attendance, no-shows and one full session
--  10) PT & day passes  - paid sessions for the drop-in revenue line
--  11) Equipment usage  - reservations linking visits to machines
--  12) Inventory        - supplement bar, cleaning and consumables stock with
--                         suppliers and movements (3 items below reorder)
--
-- Everything is DEMO DATA. Emails use the reserved example-demo.test domain;
-- logins created here have the password  Passw0rd!  (the admin keeps
-- Demo@12345 if seed-demo-data.ps1 created it).
--
-- Times are Sri Lanka time (Asia/Colombo), stored as timestamptz. "Today"
-- is today in Colombo. Idempotent: reference rows are guarded per row;
-- the dated activity (memberships, visits, classes, PT, equipment usage)
-- is guarded per tenant - it is written once and skipped on every later
-- run, because it is relative to "today" and a re-run on another day
-- would otherwise land a second, shifted copy. Delete the tenant's
-- bookings and subscriptions to regenerate it. One transaction.
--
--   psql "$DATABASE_URL" -f scripts/seed-powerhouse-fitness-sample-records.sql
-- ============================================================================

BEGIN;

-- ── 0) Context ──────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS _seed_ctx;
DROP TABLE IF EXISTS _seed_branch;
DROP TABLE IF EXISTS _seed_res;
DROP TABLE IF EXISTS _seed_bt;
DROP TABLE IF EXISTS _seed_mem;
DROP TABLE IF EXISTS _seed_eq;
DROP TABLE IF EXISTS _seed_visits;
DROP TABLE IF EXISTS _seed_classes;

CREATE TEMP TABLE _seed_ctx AS
SELECT t."Id" AS tenant_id,
       (SELECT u."Id" FROM "Users" u WHERE u."TenantId" = t."Id" AND u."Role" = 0 ORDER BY u."CreatedAt" LIMIT 1) AS admin_user_id
FROM "Tenants" t
WHERE t."Name" = 'PowerHouse Fitness' AND lower(t."BusinessType") IN ('gym','fitness');

DO $$
DECLARE n integer; t_id uuid; u_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'Subscriptions') THEN
    RAISE EXCEPTION 'Table "Subscriptions" is missing - start the API once so migration AddGymMembershipsAndDemographics runs, then re-run.';
  END IF;
  SELECT count(*) INTO n FROM _seed_ctx;
  IF n > 1 THEN
    RAISE EXCEPTION '% tenants are named "PowerHouse Fitness" - pin one by Id in the _seed_ctx query.', n;
  END IF;
  IF n = 0 THEN
    t_id := gen_random_uuid(); u_id := gen_random_uuid();
    INSERT INTO "Tenants" ("Id","CreatedAt","UpdatedAt","Name","BusinessType","SubType","IsActive","CancellationCutoffHours","RescheduleCutoffHours","ReviewCount")
    VALUES (t_id, now(), now(), 'PowerHouse Fitness', 'Gym', NULL, true, 1, 2, 0);
    INSERT INTO "Users" ("Id","CreatedAt","UpdatedAt","TenantId","Email","PasswordHash","FullName","Phone","Role","IsActive","IsApproved")
    VALUES (u_id, now(), now(), t_id, 'admin@powerhousefitness.lk', '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq', 'Isuru Wickramasinghe', '+94773456789', 0, true, true);
    INSERT INTO _seed_ctx (tenant_id, admin_user_id) VALUES (t_id, u_id);
  END IF;
  IF (SELECT admin_user_id FROM _seed_ctx) IS NULL THEN
    RAISE EXCEPTION 'Tenant has no Admin user.';
  END IF;
END $$;

INSERT INTO "Branches" ("Id","CreatedAt","UpdatedAt","TenantId","Name","Address","Phone","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, 'Nugegoda', '88 High Level Road, Nugegoda', '+94112765432', true
FROM _seed_ctx ctx WHERE NOT EXISTS (SELECT 1 FROM "Branches" b WHERE b."TenantId" = ctx.tenant_id);

CREATE TEMP TABLE _seed_branch AS
SELECT b."Id" AS branch_id FROM "Branches" b JOIN _seed_ctx ctx ON b."TenantId" = ctx.tenant_id ORDER BY b."CreatedAt" LIMIT 1;

UPDATE "Users" u SET "BranchId" = br.branch_id FROM _seed_ctx ctx, _seed_branch br
WHERE u."TenantId" = ctx.tenant_id AND u."BranchId" IS NULL;

CREATE OR REPLACE FUNCTION pg_temp.lk(day_offset int, t time) RETURNS timestamptz
LANGUAGE sql STABLE AS $$
  SELECT (((now() AT TIME ZONE 'Asia/Colombo')::date + day_offset) + t) AT TIME ZONE 'Asia/Colombo';
$$;
-- Day of week (0 = Sunday) of "today + offset" in Colombo.
CREATE OR REPLACE FUNCTION pg_temp.dow(day_offset int) RETURNS int
LANGUAGE sql STABLE AS $$
  SELECT extract(dow FROM ((now() AT TIME ZONE 'Asia/Colombo')::date + day_offset))::int;
$$;

-- ── 1) Module config (targets) ──────────────────────────────────────────────
INSERT INTO "TenantModules" ("Id","CreatedAt","UpdatedAt","TenantId","ModuleName","IsEnabled","ConfigJson")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, 'Memberships', true, '{}'
FROM _seed_ctx ctx WHERE NOT EXISTS (SELECT 1 FROM "TenantModules" m WHERE m."TenantId" = ctx.tenant_id AND m."ModuleName" = 'Memberships');

UPDATE "TenantModules" m SET
  "ConfigJson" = ((CASE WHEN m."ConfigJson" ~ '^\s*\{' THEN m."ConfigJson"::jsonb ELSE '{}'::jsonb END) || jsonb_build_object(
      'facilityCapacity', 120, 'monthlyRevenueTarget', 180000, 'yearlyRevenueTarget', 2160000,
      'openHoursPerDay', 15, 'maintenanceEveryUses', 200))::text,
  "UpdatedAt" = now()
FROM _seed_ctx ctx WHERE m."TenantId" = ctx.tenant_id AND m."ModuleName" = 'Memberships';

-- ── 2) Resources ────────────────────────────────────────────────────────────
-- The three trainers seed-demo-data.ps1 created have no Code; give them one
-- so the rest of this file can address them, without duplicating them.
UPDATE "resources" r SET "Code" = v.code, "UpdatedAt" = now()
FROM _seed_ctx ctx, (VALUES
  ('Sanjeewa Kumara%', 'PHF-TR-01'), ('Nadeesha Perera%', 'PHF-TR-02'), ('Tharindu De Silva%', 'PHF-TR-03')
) AS v(pattern, code)
WHERE r."TenantId" = ctx.tenant_id AND r."Code" IS NULL AND r."Category" = 'Staff' AND r."Name" LIKE v.pattern
  AND NOT EXISTS (SELECT 1 FROM "resources" x WHERE x."TenantId" = ctx.tenant_id AND x."Code" = v.code);

INSERT INTO "resources"
  ("Id","TenantId","BranchId","Name","Code","Category","Specialty","Status","Capacity","HourlyRate","Description","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id, v.name, v.code, v.category, v.specialty, 'Available', v.capacity, v.rate, v.description, now(), now()
FROM _seed_ctx ctx, _seed_branch br, (VALUES
  -- zones (Room) - capacities sum to 120 = facilityCapacity
  ('Weights Floor',             'PHF-Z-WEIGHTS', 'Room',  'Strength',     40,  NULL, 'Free weights, racks, cable machines.'),
  ('Cardio Zone',               'PHF-Z-CARDIO',  'Room',  'Cardio',       30,  NULL, 'Treadmills, rowers, bikes, cross-trainers.'),
  ('Functional Box',            'PHF-Z-BOX',     'Room',  'Functional',   20,  NULL, 'CrossFit / HIIT floor.'),
  ('Studio A (Yoga)',           'PHF-Z-STUDIO-A','Room',  'Studio',       18,  NULL, 'Mind-body studio.'),
  ('Studio B (Spin)',           'PHF-Z-STUDIO-B','Room',  'Studio',       12,  NULL, 'Spin studio, 14 bikes.'),
  -- trainers created here (the demo-seed trio get codes above)
  ('Sanjeewa Kumara - Personal Trainer', 'PHF-TR-01', 'Staff', 'Strength Training', NULL, 3000, 'Head coach.'),
  ('Nadeesha Perera - Yoga Instructor',  'PHF-TR-02', 'Staff', 'Yoga',              NULL, 2000, 'Yoga and mobility.'),
  ('Tharindu De Silva - CrossFit Coach', 'PHF-TR-03', 'Staff', 'CrossFit',          NULL, 3500, 'HIIT and CrossFit.'),
  ('Amali Perera - Spin Instructor',     'PHF-TR-04', 'Staff', 'Spin',              NULL, 1800, 'Spin and cardio classes.'),
  ('Kavindu Jayasinghe - Front Desk',    'PHF-TR-05', 'Staff', 'Front Desk',        NULL,  600, 'Reception, memberships, day passes.')
) AS v(name, code, category, specialty, capacity, rate, description)
WHERE NOT EXISTS (SELECT 1 FROM "resources" r WHERE r."TenantId" = ctx.tenant_id AND r."Code" = v.code);

CREATE TEMP TABLE _seed_res AS
SELECT r."Id" AS resource_id, r."Code" AS code FROM "resources" r JOIN _seed_ctx ctx ON r."TenantId" = ctx.tenant_id WHERE r."Code" LIKE 'PHF-%';

-- Rosters (DayOfWeek 0 = Sunday). Zones are open 06:00-21:00 daily.
INSERT INTO "resource_schedules" ("Id","CreatedAt","UpdatedAt","ResourceId","DayOfWeek","StartTime","EndTime","IsAvailable","LunchBreakStart","LunchBreakEnd")
SELECT gen_random_uuid(), now(), now(), r.resource_id, d.dow, v.start_t, v.end_t, true, v.break_s, v.break_e
FROM _seed_res r
JOIN (VALUES
  ('PHF-TR-01', TIME '06:00', TIME '14:00', TIME '10:00', TIME '10:30'),
  ('PHF-TR-02', TIME '06:00', TIME '12:00', NULL, NULL),
  ('PHF-TR-03', TIME '13:00', TIME '21:00', TIME '16:00', TIME '16:30'),
  ('PHF-TR-04', TIME '15:00', TIME '21:00', NULL, NULL),
  ('PHF-TR-05', TIME '06:00', TIME '21:00', TIME '13:00', TIME '14:00')
) AS v(code, start_t, end_t, break_s, break_e) ON v.code = r.code
CROSS JOIN generate_series(0, 6) AS d(dow)
WHERE NOT EXISTS (SELECT 1 FROM "resource_schedules" s WHERE s."ResourceId" = r.resource_id);

INSERT INTO "resource_schedules" ("Id","CreatedAt","UpdatedAt","ResourceId","DayOfWeek","StartTime","EndTime","IsAvailable")
SELECT gen_random_uuid(), now(), now(), r.resource_id, d.dow, TIME '06:00', TIME '21:00', true
FROM _seed_res r CROSS JOIN generate_series(0, 6) AS d(dow)
WHERE r.code LIKE 'PHF-Z-%' AND NOT EXISTS (SELECT 1 FROM "resource_schedules" s WHERE s."ResourceId" = r.resource_id);

-- ── 3) Activities (booking types) ───────────────────────────────────────────
-- The demo-seed types get a "kind" (and the group class a capacity) so
-- GymConfig classifies them; the rest are created with slugs phf-*.
UPDATE "booking_types" bt SET
  "ConfigJson" = COALESCE(bt."ConfigJson", '{}'::jsonb) || jsonb_build_object('kind', v.kind),
  "MaxParticipants" = COALESCE(v.cap, bt."MaxParticipants"),
  "UpdatedAt" = now()
FROM _seed_ctx ctx, (VALUES
  ('personal-training-session', 'pt', NULL), ('group-class', 'class', 20), ('trial-session', 'dropIn', NULL)
) AS v(slug, kind, cap)
WHERE bt."TenantId" = ctx.tenant_id AND bt."Slug" = v.slug;

INSERT INTO "booking_types"
  ("Id","TenantId","Name","Slug","Description","ColorHex","Status","DefaultDurationMinutes","RequiresApproval","MaxParticipants",
   "BufferMinutesBefore","BufferMinutesAfter","BookingUnit","ConfigJson","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, v.name, v.slug, v.description, v.color, 'Active', v.minutes, false, v.cap, 0, 0, 'Slot', v.config::jsonb, now(), now()
FROM _seed_ctx ctx, (VALUES
  ('Gym Access',        'phf-gym-access', 'A gym visit - the keycard, app or biometric check-in.',      '#64748B',  90, 1,  '{"kind":"access"}'),
  ('HIIT Class',        'phf-hiit',       '45-minute high-intensity interval class in the Functional Box.', '#DC2626', 45, 20, '{"kind":"class","basePrice":{"amount":0,"currency":"LKR"}}'),
  ('Yoga Flow',         'phf-yoga',       '60-minute vinyasa flow in Studio A.',                          '#059669',  60, 18, '{"kind":"class"}'),
  ('Spin Class',        'phf-spin',       '45-minute spin in Studio B - 14 bikes.',                       '#7C3AED',  45, 14, '{"kind":"class"}'),
  ('Personal Training', 'phf-pt',         'One-to-one session with a coach. LKR 3,000.',                   '#F59E0B',  60, 1,  '{"kind":"pt","basePrice":{"amount":3000,"currency":"LKR"}}'),
  ('Day Pass',          'phf-day-pass',   'Single-visit pass sold at the desk. LKR 1,500.',                '#0EA5E9', 120, 1,  '{"kind":"dropIn","basePrice":{"amount":1500,"currency":"LKR"}}')
) AS v(name, slug, description, color, minutes, cap, config)
WHERE NOT EXISTS (SELECT 1 FROM "booking_types" bt WHERE bt."TenantId" = ctx.tenant_id AND bt."Slug" = v.slug);

CREATE TEMP TABLE _seed_bt AS
SELECT bt."Id" AS bt_id, bt."Slug" AS slug, bt."DefaultDurationMinutes" AS minutes, bt."MaxParticipants" AS cap
FROM "booking_types" bt JOIN _seed_ctx ctx ON bt."TenantId" = ctx.tenant_id WHERE bt."Slug" LIKE 'phf-%';

-- ── 4) Equipment + maintenance ──────────────────────────────────────────────
INSERT INTO "EquipmentItems"
  ("Id","TenantId","BranchId","Name","Category","SKU","Unit","CurrentStock","ReorderLevel","ReorderQuantity","CostPrice","SellingPrice","IsActive","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id, v.name, v.category, v.sku, 'unit', v.units, 0, 0, v.cost, 0, true, now() - interval '400 days', now()
FROM _seed_ctx ctx, _seed_branch br, (VALUES
  ('Treadmill (Life Fitness T5)',  'Cardio',   'PHF-EQ-TREAD',  6,  850000),
  ('Rowing Machine (Concept2)',    'Cardio',   'PHF-EQ-ROW',    4,  420000),
  ('Spin Bike (Schwinn IC4)',      'Cardio',   'PHF-EQ-SPIN',  14,  260000),
  ('Squat Rack',                   'Strength', 'PHF-EQ-RACK',   4,  380000),
  ('Cable Crossover',              'Strength', 'PHF-EQ-CABLE',  2,  620000),
  ('Leg Press',                    'Strength', 'PHF-EQ-LEGP',   2,  540000),
  ('Smith Machine',                'Strength', 'PHF-EQ-SMITH',  1,  480000)
) AS v(name, category, sku, units, cost)
WHERE NOT EXISTS (SELECT 1 FROM "EquipmentItems" e WHERE e."TenantId" = ctx.tenant_id AND e."SKU" = v.sku);

CREATE TEMP TABLE _seed_eq AS
SELECT e."Id" AS eq_id, e."SKU" AS sku FROM "EquipmentItems" e JOIN _seed_ctx ctx ON e."TenantId" = ctx.tenant_id WHERE e."SKU" LIKE 'PHF-EQ-%';

-- Service history: one completed + one scheduled per machine, with the
-- rower overdue and one spin bike in the workshop right now. The Notes
-- doubles as the idempotency key.
INSERT INTO "equipment_maintenances" ("Id","CreatedAt","UpdatedAt","EquipmentItemId","MaintenanceDate","NextDueDate","Cost","Notes","Status")
SELECT gen_random_uuid(), now(), now(), e.eq_id, pg_temp.lk(v.done_off, '09:00'), pg_temp.lk(v.due_off, '09:00'), v.cost, v.notes, v.status
FROM _seed_eq e JOIN (VALUES
  ('PHF-EQ-TREAD', -75,  -75, 18000, 'Quarterly service: belts, lubrication, motor check (T5 x6)', 'Completed'),
  ('PHF-EQ-TREAD',  -75,   10,     0, 'Quarterly service due',                                   'Scheduled'),
  ('PHF-EQ-ROW',   -110, -110,  6500, 'Chain and damper service',                                 'Completed'),
  ('PHF-EQ-ROW',   -110,   -6,     0, 'Chain and damper service due - OVERDUE',                   'Scheduled'),
  ('PHF-EQ-SPIN',   -40,  -40, 21000, 'Brake pads and crank service (x14)',                       'Completed'),
  ('PHF-EQ-SPIN',    -1,   +2,  4500, 'Bike #7 crank bearing - in the workshop',                  'InProgress'),
  ('PHF-EQ-RACK',   -20,  -20,  3000, 'Safety-pin and J-hook inspection',                         'Completed'),
  ('PHF-EQ-RACK',   -20,  160,     0, 'Semi-annual inspection due',                               'Scheduled'),
  ('PHF-EQ-CABLE',  -95,  -95,  9000, 'Cable and pulley replacement',                             'Completed'),
  ('PHF-EQ-CABLE',  -95,   12,     0, 'Cable inspection due',                                     'Scheduled'),
  ('PHF-EQ-LEGP',   -30,  -30,  4000, 'Sled rail lubrication',                                    'Completed'),
  ('PHF-EQ-LEGP',   -30,  150,     0, 'Sled rail service due',                                    'Scheduled'),
  ('PHF-EQ-SMITH',  -60,  -60,  5000, 'Bar bearings and safety catches',                          'Completed'),
  ('PHF-EQ-SMITH',  -60,  120,     0, 'Bearing service due',                                      'Scheduled')
) AS v(sku, done_off, due_off, cost, notes, status) ON v.sku = e.sku
WHERE NOT EXISTS (SELECT 1 FROM "equipment_maintenances" m WHERE m."EquipmentItemId" = e.eq_id AND m."Notes" = v.notes);

-- ── 5) Staff logins ─────────────────────────────────────────────────────────
INSERT INTO "Users" ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","Email","PasswordHash","FullName","Phone","Role","IsActive","IsApproved")
SELECT gen_random_uuid(), now() - interval '200 days', now(), ctx.tenant_id, br.branch_id, v.email,
       '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq', v.full_name, v.phone, v.role, true, true
FROM _seed_ctx ctx, _seed_branch br, (VALUES
  ('manager.powerhouse@example-demo.test',   'Dilrukshi Amarasinghe', '+94770334455', 1),
  ('frontdesk.powerhouse@example-demo.test', 'Kavindu Jayasinghe',    '+94770334466', 2),
  ('coach.powerhouse@example-demo.test',     'Tharindu De Silva',     '+94770334477', 2)
) AS v(email, full_name, phone, role)
WHERE NOT EXISTS (SELECT 1 FROM "Users" u WHERE lower(u."Email") = v.email);

-- ── 6) Members ──────────────────────────────────────────────────────────────
-- m is the member's index, used by the visit generator below.
INSERT INTO "Users"
  ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","Email","PasswordHash","FullName","Phone","Role","IsActive","IsApproved","Address","DateOfBirth","Gender")
SELECT gen_random_uuid(), pg_temp.lk(v.joined_off, '10:00'), now(), ctx.tenant_id, br.branch_id, v.email,
       '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq', v.full_name, v.phone, 3, true, true, v.address,
       (v.dob::date)::timestamptz, v.gender
FROM _seed_ctx ctx, _seed_branch br, (VALUES
  ( 1, 'nuwan.perera@example-demo.test',        'Nuwan Perera',          '+94771340001', 'Nugegoda',        '1990-03-14', 'Male',   -400),
  ( 2, 'ishani.silva@example-demo.test',        'Ishani Silva',          '+94771340002', 'Nugegoda',        '1995-07-22', 'Female', -300),
  ( 3, 'kasun.fernando@example-demo.test',      'Kasun Fernando',        '+94771340003', 'Maharagama',      '1988-11-02', 'Male',   -250),
  ( 4, 'dilki.jayawardena@example-demo.test',   'Dilki Jayawardena',     '+94771340004', 'Kirulapone',      '2001-01-30', 'Female', -120),
  ( 5, 'ruwan.bandara@example-demo.test',       'Ruwan Bandara',         '+94771340005', 'Nugegoda',        '1979-05-09', 'Male',   -200),
  ( 6, 'sachini.gunasekara@example-demo.test',  'Sachini Gunasekara',    '+94771340006', 'Kohuwala',        '1993-09-17', 'Female', -180),
  ( 7, 'chamara.wijesinghe@example-demo.test',  'Chamara Wijesinghe',    '+94771340007', 'Nugegoda',        '1985-12-01', 'Male',   -90),
  ( 8, 'nimasha.rathnayake@example-demo.test',  'Nimasha Rathnayake',    '+94771340008', 'Maharagama',      '1998-04-25', 'Female', -75),
  ( 9, 'tharaka.dissanayake@example-demo.test', 'Tharaka Dissanayake',   '+94771340009', 'Nawala',          '1992-08-13', 'Male',   -160),
  (10, 'hansika.weerasinghe@example-demo.test', 'Hansika Weerasinghe',   '+94771340010', 'Nugegoda',        '1996-02-19', 'Female',   -3),
  (11, 'malith.karunaratne@example-demo.test',  'Malith Karunaratne',    '+94771340011', 'Kottawa',         '1983-06-06', 'Male',   -140),
  (12, 'anjali.fonseka@example-demo.test',      'Anjali Fonseka',        '+94771340012', 'Nugegoda',        '1990-10-28', 'Female', -110),
  (13, 'pramod.senanayake@example-demo.test',   'Pramod Senanayake',     '+94771340013', 'Pannipitiya',     '1975-03-03', 'Male',   -95),
  (14, 'shalini.abeysekara@example-demo.test',  'Shalini Abeysekara',    '+94771340014', 'Nugegoda',        '2003-11-11', 'Female',   -6),
  (15, 'dinesh.herath@example-demo.test',       'Dinesh Herath',         '+94771340015', 'Nawala',          '1968-07-07', 'Male',   -220),
  (16, 'kavya.ranasinghe@example-demo.test',    'Kavya Ranasinghe',      '+94771340016', 'Kohuwala',        '1999-12-24', 'Female',  -60),
  (17, 'asanka.mendis@example-demo.test',       'Asanka Mendis',         '+94771340017', 'Nugegoda',        '1987-01-15', 'Male',   -130),
  (18, 'lakmini.peiris@example-demo.test',      'Lakmini Peiris',        '+94771340018', 'Maharagama',      '1981-09-09', 'Female', -170),
  (19, 'supun.wickramasinghe@example-demo.test','Supun Wickramasinghe',  '+94771340019', 'Nugegoda',        '1994-05-20', 'Male',   -300),
  (20, 'nethmi.jayasuriya@example-demo.test',   'Nethmi Jayasuriya',     '+94771340020', 'Kirulapone',      '2000-08-08', 'Female',   -2),
  (21, 'roshan.desilva@example-demo.test',      'Roshan De Silva',       '+94771340021', 'Nugegoda',        '1986-04-04', 'Male',   -150),
  (22, 'thilini.cooray@example-demo.test',      'Thilini Cooray',        '+94771340022', 'Nawala',          '1991-02-02', 'Female', -210),
  (23, 'buddhika.samaraweera@example-demo.test','Buddhika Samaraweera',  '+94771340023', 'Kottawa',         '1989-10-10', 'Male',   -240),
  (24, 'emily.watson@example-demo.test',        'Emily Watson',          '+447700900456', 'Visiting - Colombo', '1997-06-30', NULL, -5)
) AS v(m, email, full_name, phone, address, dob, gender, joined_off)
WHERE NOT EXISTS (SELECT 1 FROM "Users" u WHERE lower(u."Email") = v.email);

CREATE TEMP TABLE _seed_mem AS
SELECT v.m, u."Id" AS user_id, u."FullName" AS name
FROM (VALUES
  (1,'nuwan.perera'),(2,'ishani.silva'),(3,'kasun.fernando'),(4,'dilki.jayawardena'),(5,'ruwan.bandara'),
  (6,'sachini.gunasekara'),(7,'chamara.wijesinghe'),(8,'nimasha.rathnayake'),(9,'tharaka.dissanayake'),(10,'hansika.weerasinghe'),
  (11,'malith.karunaratne'),(12,'anjali.fonseka'),(13,'pramod.senanayake'),(14,'shalini.abeysekara'),(15,'dinesh.herath'),
  (16,'kavya.ranasinghe'),(17,'asanka.mendis'),(18,'lakmini.peiris'),(19,'supun.wickramasinghe'),(20,'nethmi.jayasuriya'),
  (21,'roshan.desilva'),(22,'thilini.cooray'),(23,'buddhika.samaraweera'),(24,'emily.watson')
) AS v(m, local)
JOIN "Users" u ON lower(u."Email") = v.local || '@example-demo.test'
JOIN _seed_ctx ctx ON u."TenantId" = ctx.tenant_id;

-- ── 7) Memberships ──────────────────────────────────────────────────────────
-- Current membership per member (m 1-23; Emily has none - day passes).
-- Columns: plan, amount, cycle, start/end offsets (days), status, payment,
-- auto-renew, last-payment offset, next-billing offset.
INSERT INTO "Subscriptions"
  ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","CustomerId","PlanName","Amount","BillingCycle","StartDate","EndDate","AutoRenew","Status","PaymentStatus","LastPaymentAt","NextBillingAt","Notes")
SELECT gen_random_uuid(), pg_temp.lk(v.start_off, '10:00'), now(), ctx.tenant_id, br.branch_id, mem.user_id,
       v.plan, v.amount, v.cycle, pg_temp.lk(v.start_off, '00:00'), pg_temp.lk(v.end_off, '23:59'),
       v.auto, v.status, v.pay,
       CASE WHEN v.last_pay_off IS NOT NULL THEN pg_temp.lk(v.last_pay_off, '10:00') END,
       CASE WHEN v.next_bill_off IS NOT NULL THEN pg_temp.lk(v.next_bill_off, '06:00') END,
       v.notes
FROM _seed_ctx ctx, _seed_branch br, (VALUES
  ( 1, 'Premium',        12000, 'Monthly',   -20,  10, 'Active',    'Paid',    true,  -20,  10, NULL),
  ( 2, 'Standard',        7500, 'Monthly',   -25,   5, 'Active',    'Paid',    false, -25,   5, 'Prefers to renew at the desk.'),
  ( 3, 'Basic',           4500, 'Monthly',   -10,  20, 'Active',    'Pending', false, -40, -10, 'Bank transfer promised.'),
  ( 4, 'Student',         3500, 'Monthly',   -15,  15, 'Active',    'Paid',    true,  -15,  15, NULL),
  ( 5, 'Annual Premium',120000, 'Yearly',   -200, 165, 'Active',    'Paid',    true, -200, 165, NULL),
  ( 6, 'Standard',        7500, 'Monthly',   -28,   2, 'Active',    'Failed',  true,  -58,  -1, 'Card declined on the renewal run.'),
  ( 7, 'Premium',        12000, 'Monthly',    -5,  25, 'Active',    'Paid',    true,   -5,  25, NULL),
  ( 8, 'Basic',           4500, 'Monthly',   -12,  18, 'Active',    'Overdue', false, -42, -12, 'Two reminders sent.'),
  ( 9, 'Standard',        7500, 'Monthly',   -18,  12, 'Active',    'Paid',    true,  -18,  12, NULL),
  (10, 'Student',         3500, 'Monthly',    -3,  27, 'Active',    'Paid',    false,  -3,  27, 'New this week.'),
  (11, 'Standard',        7500, 'Monthly',   -22,   8, 'Active',    'Paid',    true,  -22,   8, NULL),
  (12, 'Premium',        12000, 'Monthly',    -8,  22, 'Active',    'Paid',    true,   -8,  22, NULL),
  (13, 'Basic',           4500, 'Monthly',   -14,  16, 'Active',    'Paid',    false, -14,  16, NULL),
  (14, 'Student',         3500, 'Monthly',    -6,  24, 'Active',    'Paid',    true,   -6,  24, 'New this week.'),
  (15, 'Standard',       21000, 'Quarterly', -60,  30, 'Active',    'Paid',    true,  -60,  30, NULL),
  (16, 'Basic',           4500, 'Monthly',    -9,  21, 'Active',    'Paid',    true,   -9,  21, NULL),
  (17, 'Premium',        12000, 'Monthly',   -27,   3, 'Active',    'Paid',    false, -27,   3, 'Manual renewal - due in 3 days.'),
  (18, 'Standard',        7500, 'Monthly',   -16,  14, 'Frozen',    'Paid',    true,  -16,  14, 'Frozen - travelling until next month.'),
  (19, 'Annual Premium',120000, 'Yearly',   -300,  65, 'Active',    'Paid',    true, -300,  65, NULL),
  (20, 'Student',         3500, 'Monthly',    -2,  28, 'Active',    'Paid',    true,   -2,  28, 'New this week.'),
  (21, 'Basic',           4500, 'Monthly',   -45, -15, 'Expired',   'Paid',    false, -45, NULL, 'Lapsed - still has a keycard.'),
  (22, 'Standard',        7500, 'Monthly',   -50, -20, 'Expired',   'Paid',    false, -50, NULL, NULL),
  (23, 'Premium',        12000, 'Monthly',   -40, -10, 'Cancelled', 'Paid',    false, -40, NULL, 'Moved away.'),
  -- earlier periods for a few long-standing members (year-to-date revenue)
  ( 1, 'Premium',        12000, 'Monthly',   -50, -21, 'Expired',   'Paid',    true,  -50, NULL, NULL),
  ( 1, 'Premium',        12000, 'Monthly',   -80, -51, 'Expired',   'Paid',    true,  -80, NULL, NULL),
  ( 2, 'Standard',        7500, 'Monthly',   -55, -26, 'Expired',   'Paid',    false, -55, NULL, NULL),
  ( 7, 'Premium',        12000, 'Monthly',   -35,  -6, 'Expired',   'Paid',    true,  -35, NULL, NULL),
  ( 9, 'Standard',        7500, 'Monthly',   -48, -19, 'Expired',   'Paid',    true,  -48, NULL, NULL),
  (11, 'Standard',        7500, 'Monthly',   -52, -23, 'Expired',   'Paid',    true,  -52, NULL, NULL),
  (12, 'Premium',        12000, 'Monthly',   -38,  -9, 'Expired',   'Paid',    true,  -38, NULL, NULL),
  (13, 'Basic',           4500, 'Monthly',   -44, -15, 'Expired',   'Paid',    false, -44, NULL, NULL),
  (16, 'Basic',           4500, 'Monthly',   -39, -10, 'Expired',   'Paid',    true,  -39, NULL, NULL),
  (17, 'Premium',        12000, 'Monthly',   -57, -28, 'Expired',   'Paid',    false, -57, NULL, NULL)
) AS v(m, plan, amount, cycle, start_off, end_off, status, pay, auto, last_pay_off, next_bill_off, notes)
JOIN _seed_mem mem ON mem.m = v.m
-- Run-once: relative to today, so a later re-run would add a shifted copy.
WHERE NOT EXISTS (SELECT 1 FROM "Subscriptions" s WHERE s."TenantId" = ctx.tenant_id);

-- ── 8) Visits (gym access check-ins) ────────────────────────────────────────
-- Deterministic: member m visits on day d when (m + |d|) % 3 = 0 (about a
-- third of days); morning / lunch / evening crowd by (m % 4) % 3, weekends
-- later; method by m % 4; zone by m % 2. Members 21-24 (lapsed / none) get
-- one old visit and one today, which is what the lapsed-check-in alert is
-- for. Visits later than "now" are dropped; a visit whose check-out is in
-- the future is still inside (CheckedIn, no CheckOutAt).
CREATE TEMP TABLE _seed_visits AS
SELECT m.m, m.user_id, m.name, d.day,
       (CASE WHEN pg_temp.dow(d.day) IN (0, 6)
             THEN (CASE (m.m % 4) % 3 WHEN 0 THEN 8 WHEN 1 THEN 10 ELSE 16 END)
             ELSE (CASE (m.m % 4) % 3 WHEN 0 THEN 6 WHEN 1 THEN 12 ELSE 17 END) END
        + ((m.m + abs(d.day)) % 3)) AS hour,
       (((m.m * 7 + abs(d.day)) % 4) * 15) AS minute,
       45 + (((m.m + abs(d.day)) % 4) * 15) AS duration,
       (CASE m.m % 4 WHEN 0 THEN 'RFID' WHEN 1 THEN 'App' WHEN 2 THEN 'Biometric' ELSE 'Front desk' END) AS method,
       (CASE m.m % 2 WHEN 0 THEN 'PHF-Z-WEIGHTS' ELSE 'PHF-Z-CARDIO' END) AS zone
FROM _seed_mem m CROSS JOIN generate_series(-27, 0) AS d(day)
WHERE (m.m <= 20 AND (m.m + abs(d.day)) % 3 = 0 AND (m.m * abs(d.day)) % 11 <> 5)
   OR (m.m BETWEEN 21 AND 23 AND d.day IN (-20, 0))
   OR (m.m = 24 AND d.day IN (-4, 0));

INSERT INTO "bookings"
  ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","Source",
   "CheckInAt","CheckOutAt","TotalCost","ReminderSent","CreatedBy","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, v.user_id,
       'Gym visit - ' || v.name, NULL,
       pg_temp.lk(v.day, make_time(v.hour, v.minute, 0)),
       pg_temp.lk(v.day, make_time(v.hour, v.minute, 0)) + (v.duration || ' minutes')::interval,
       CASE WHEN pg_temp.lk(v.day, make_time(v.hour, v.minute, 0)) + (v.duration || ' minutes')::interval > now() THEN 'CheckedIn' ELSE 'Completed' END,
       'Normal', 1, v.method,
       pg_temp.lk(v.day, make_time(v.hour, v.minute, 0)),
       CASE WHEN pg_temp.lk(v.day, make_time(v.hour, v.minute, 0)) + (v.duration || ' minutes')::interval > now() THEN NULL
            ELSE pg_temp.lk(v.day, make_time(v.hour, v.minute, 0)) + (v.duration || ' minutes')::interval END,
       CASE WHEN v.m = 24 THEN 1500 ELSE NULL END,
       true, NULL,
       pg_temp.lk(v.day, make_time(v.hour, v.minute, 0)), now(), 1
FROM _seed_visits v
JOIN _seed_ctx ctx ON true
JOIN _seed_res r  ON r.code = v.zone
JOIN _seed_bt  bt ON bt.slug = CASE WHEN v.m = 24 THEN 'phf-day-pass' ELSE 'phf-gym-access' END
WHERE pg_temp.lk(v.day, make_time(v.hour, v.minute, 0)) <= now()
  -- Run-once per tenant (see header).
  AND NOT EXISTS (SELECT 1 FROM "bookings" b WHERE b."TenantId" = ctx.tenant_id AND b."Title" LIKE 'Gym visit - %');

-- ── 9) Classes ──────────────────────────────────────────────────────────────
-- Timetable: HIIT Mon/Wed/Fri 18:00 (Tharindu), Yoga Tue/Thu/Sat 07:00
-- (Nadeesha), Spin Wed 19:00 + Sat 09:00 (Amali). Attendance is a
-- deterministic subset capped at the class size; the next spin session
-- (today to two days out) is booked full, for the classes-full alert.
CREATE TEMP TABLE _seed_classes AS
SELECT c.slug, c.trainer, c.start_t, d.day, c.cap
FROM (VALUES
  ('phf-hiit', 'PHF-TR-03', TIME '18:00', ARRAY[1,3,5], 20),
  ('phf-yoga', 'PHF-TR-02', TIME '07:00', ARRAY[2,4,6], 18),
  ('phf-spin', 'PHF-TR-04', TIME '19:00', ARRAY[3],     14),
  ('phf-spin', 'PHF-TR-04', TIME '09:00', ARRAY[6],     14)
) AS c(slug, trainer, start_t, dows, cap)
CROSS JOIN generate_series(-27, 2) AS d(day)
WHERE pg_temp.dow(d.day) = ANY (c.dows);

INSERT INTO "bookings"
  ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","Source",
   "CheckInAt","CheckOutAt","TotalCost","ReminderSent","CreatedBy","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, a.user_id,
       bt_name.name || ' - ' || a.name, NULL,
       pg_temp.lk(a.day, a.start_t),
       pg_temp.lk(a.day, a.start_t) + (bt.minutes || ' minutes')::interval,
       CASE WHEN pg_temp.lk(a.day, a.start_t) > now() THEN 'Confirmed'
            WHEN a.no_show THEN 'NoShow'
            WHEN pg_temp.lk(a.day, a.start_t) + (bt.minutes || ' minutes')::interval > now() THEN 'InProgress'
            ELSE 'Completed' END,
       'Normal', 1, CASE a.m % 3 WHEN 0 THEN 'App' ELSE 'Online' END,
       CASE WHEN pg_temp.lk(a.day, a.start_t) <= now() AND NOT a.no_show THEN pg_temp.lk(a.day, a.start_t) - interval '6 minutes' END,
       CASE WHEN pg_temp.lk(a.day, a.start_t) + (bt.minutes || ' minutes')::interval <= now() AND NOT a.no_show
            THEN pg_temp.lk(a.day, a.start_t) + (bt.minutes || ' minutes')::interval END,
       NULL, true, NULL,
       LEAST(pg_temp.lk(a.day, a.start_t) - interval '2 days', now()), now(), 1
FROM (
  SELECT c.slug, c.trainer, c.start_t, c.day, c.cap, m.m, m.user_id, m.name,
         ((m.m + c.day) % 9 = 0) AS no_show,
         row_number() OVER (PARTITION BY c.slug, c.start_t, c.day ORDER BY (m.m * 7 + c.day) % 24) AS rn
  FROM _seed_classes c
  JOIN _seed_mem m ON m.m <= 20
  WHERE ((m.m * 3 + c.day) % 5 <> 0)                                   -- ~80 % of members per session
     OR (c.slug = 'phf-spin' AND c.day BETWEEN 0 AND 2)                 -- next spin: everyone wants in
) a
JOIN _seed_ctx ctx ON true
JOIN _seed_res r ON r.code = a.trainer
JOIN _seed_bt bt ON bt.slug = a.slug
JOIN (VALUES ('phf-hiit','HIIT'),('phf-yoga','Yoga'),('phf-spin','Spin')) AS bt_name(slug, name) ON bt_name.slug = a.slug
WHERE a.rn <= a.cap
  -- Run-once per tenant (see header).
  AND NOT EXISTS (SELECT 1 FROM "bookings" b JOIN _seed_bt x ON x.bt_id = b."BookingTypeId" WHERE b."TenantId" = ctx.tenant_id AND x.slug IN ('phf-hiit','phf-yoga','phf-spin'));

-- ── 10) Personal training + day passes ──────────────────────────────────────
-- Tharindu's PT slots sit at 16:00, clear of his 18:00 HIIT class.
INSERT INTO "bookings"
  ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","Source",
   "CheckInAt","CheckOutAt","TotalCost","ReminderSent","CreatedBy","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, m.user_id,
       'PT - ' || m.name, v.notes,
       pg_temp.lk(v.day, v.start_t), pg_temp.lk(v.day, v.start_t) + interval '60 minutes',
       CASE WHEN pg_temp.lk(v.day, v.start_t) > now() THEN 'Confirmed'
            WHEN pg_temp.lk(v.day, v.start_t) + interval '60 minutes' > now() THEN 'InProgress' ELSE 'Completed' END,
       'Normal', 1, 'Online',
       CASE WHEN pg_temp.lk(v.day, v.start_t) <= now() THEN pg_temp.lk(v.day, v.start_t) END,
       CASE WHEN pg_temp.lk(v.day, v.start_t) + interval '60 minutes' <= now() THEN pg_temp.lk(v.day, v.start_t) + interval '60 minutes' END,
       3000, true, NULL, LEAST(pg_temp.lk(v.day, v.start_t) - interval '3 days', now()), now(), 1
FROM (VALUES
  ( 1, -26, TIME '07:00', 'PHF-TR-01', 'Strength block, week 1'),
  ( 5, -24, TIME '08:00', 'PHF-TR-01', 'Mobility + squat technique'),
  ( 7, -21, TIME '16:00', 'PHF-TR-03', 'Conditioning'),
  ( 1, -19, TIME '07:00', 'PHF-TR-01', 'Strength block, week 2'),
  (12, -17, TIME '09:00', 'PHF-TR-01', 'Assessment'),
  ( 9, -13, TIME '16:00', 'PHF-TR-03', 'Olympic lifts intro'),
  ( 1, -12, TIME '07:00', 'PHF-TR-01', 'Strength block, week 3'),
  (17, -10, TIME '08:00', 'PHF-TR-01', 'Deadlift technique'),
  ( 5,  -8, TIME '08:00', 'PHF-TR-01', 'Programme review'),
  ( 1,  -5, TIME '07:00', 'PHF-TR-01', 'Strength block, week 4'),
  (12,  -3, TIME '09:00', 'PHF-TR-01', 'Programme, week 1'),
  ( 7,  -1, TIME '16:00', 'PHF-TR-03', 'Conditioning'),
  (19,   0, TIME '08:00', 'PHF-TR-01', 'Bench progression'),
  ( 9,   0, TIME '16:00', 'PHF-TR-03', 'Olympic lifts, session 2'),
  ( 1,   1, TIME '07:00', 'PHF-TR-01', 'Strength block, week 5'),
  (17,   2, TIME '08:00', 'PHF-TR-01', 'Deadlift, session 2')
) AS v(m, day, start_t, trainer, notes)
JOIN _seed_mem m ON m.m = v.m
JOIN _seed_ctx ctx ON true
JOIN _seed_res r ON r.code = v.trainer
JOIN _seed_bt bt ON bt.slug = 'phf-pt'
-- Run-once per tenant (see header).
WHERE NOT EXISTS (SELECT 1 FROM "bookings" b WHERE b."TenantId" = ctx.tenant_id AND b."BookingTypeId" = bt.bt_id);

-- ── 11) Equipment usage (reservations against visits) ───────────────────────
-- Weights-floor visitors use a rack (every third) or the cable machine;
-- cardio visitors a treadmill or the rower; spin classes a bike each.
INSERT INTO "equipment_reservations" ("Id","CreatedAt","UpdatedAt","TenantId","BookingId","EquipmentItemId","Quantity")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, b."Id", e.eq_id, 1
FROM "bookings" b
JOIN _seed_ctx ctx ON b."TenantId" = ctx.tenant_id
JOIN _seed_mem m ON m.user_id = b."BookedBy"
JOIN "resources" r ON r."Id" = b."ResourceId"
JOIN "booking_types" bt ON bt."Id" = b."BookingTypeId"
JOIN _seed_eq e ON e.sku = CASE
    WHEN bt."Slug" = 'phf-spin' THEN 'PHF-EQ-SPIN'
    WHEN r."Code" = 'PHF-Z-WEIGHTS' AND m.m % 3 = 0 THEN 'PHF-EQ-RACK'
    WHEN r."Code" = 'PHF-Z-WEIGHTS' AND m.m % 3 = 1 THEN 'PHF-EQ-CABLE'
    WHEN r."Code" = 'PHF-Z-WEIGHTS' THEN 'PHF-EQ-LEGP'
    WHEN r."Code" = 'PHF-Z-CARDIO' AND m.m % 3 = 0 THEN 'PHF-EQ-ROW'
    WHEN r."Code" = 'PHF-Z-CARDIO' THEN 'PHF-EQ-TREAD'
  END
WHERE b."DeletedAt" IS NULL AND b."Status" <> 'NoShow'
  AND NOT EXISTS (SELECT 1 FROM "equipment_reservations" x WHERE x."BookingId" = b."Id" AND x."EquipmentItemId" = e.eq_id);

-- ── 12) Inventory (supplements bar, cleaning, consumables) ──────────────────
-- The Inventory module's own tables, so the Inventory manager, low-stock
-- alerts and stock-movement log have rows. Categories and units normally
-- come from DefaultInventoryCatalog at tenant creation; guarded here for a
-- tenant that predates it. Three items sit below reorder level on purpose.
INSERT INTO "InventoryCategories" ("Id","CreatedAt","UpdatedAt","TenantId","Name","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, v.name, true
FROM _seed_ctx ctx, (VALUES ('Supplements'),('Beverages'),('Cleaning Supplies'),('Equipment'),('Merchandise')) AS v(name)
WHERE NOT EXISTS (SELECT 1 FROM "InventoryCategories" c WHERE c."TenantId" = ctx.tenant_id AND c."Name" = v.name);

INSERT INTO "InventoryUnits" ("Id","CreatedAt","UpdatedAt","TenantId","Code","Name","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, v.code, v.name, true
FROM _seed_ctx ctx, (VALUES ('each','Each'),('box','Box'),('pack','Pack'),('kg','Kilogram'),('l','Litre')) AS v(code, name)
WHERE NOT EXISTS (SELECT 1 FROM "InventoryUnits" u WHERE u."TenantId" = ctx.tenant_id AND u."Code" = v.code);

INSERT INTO "Suppliers" ("Id","CreatedAt","UpdatedAt","TenantId","Name","Email","Phone","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, v.name, v.email, v.phone, true
FROM _seed_ctx ctx, (VALUES
  ('NutriMax Lanka (Pvt) Ltd', 'orders@nutrimax.example-demo.test',  '+94112223344'),
  ('CleanPro Supplies',        'sales@cleanpro.example-demo.test',    '+94112556677'),
  ('FitGear Colombo',          'hello@fitgear.example-demo.test',     '+94777889900')
) AS v(name, email, phone)
WHERE NOT EXISTS (SELECT 1 FROM "Suppliers" x WHERE x."TenantId" = ctx.tenant_id AND x."Name" = v.name);

INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","CategoryId","UnitId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id,
       (SELECT c."Id" FROM "InventoryCategories" c WHERE c."TenantId" = ctx.tenant_id AND c."Name" = v.category LIMIT 1),
       (SELECT u."Id" FROM "InventoryUnits" u WHERE u."TenantId" = ctx.tenant_id AND u."Code" = v.unit LIMIT 1),
       v.name, v.sku, v.description, v.qty, v.reorder, v.cost, true, now() - interval '120 days', now()
FROM _seed_ctx ctx, _seed_branch br, (VALUES
  ('Whey Protein Isolate 1kg (unflavoured)', 'PHF-SUPP-001', 'Supplements',       'each', 'Sold at the supplement bar and per scoop',      22, 10,  8900.00),
  ('Whey Protein 1kg (chocolate)',           'PHF-SUPP-002', 'Supplements',       'each', 'Supplement bar',                                 6, 10,  8900.00),
  ('Creatine Monohydrate 300g',              'PHF-SUPP-003', 'Supplements',       'each', 'Supplement bar',                                14,  6,  4200.00),
  ('Isotonic Drink Mix 1kg (lemon)',         'PHF-SUPP-004', 'Supplements',       'each', 'Made up at the bar per serving',                 5,  8,  4200.00),
  ('Protein Bars (box/12)',                  'PHF-SUPP-005', 'Supplements',       'box',  'Impulse buys at the desk',                      18,  8,  3600.00),
  ('Bottled Water 500ml (case/24)',          'PHF-BEV-001',  'Beverages',         'box',  'Desk fridge',                                   30, 12,  1440.00),
  ('Energy Drink 250ml (case/24)',           'PHF-BEV-002',  'Beverages',         'box',  'Desk fridge',                                   11,  6,  4800.00),
  ('Equipment Disinfectant Spray 1L',        'PHF-CLEAN-001','Cleaning Supplies', 'each', 'Spray bottles on every zone',                   9,  6,   580.00),
  ('Paper Towel Rolls (pack/6)',             'PHF-CLEAN-002','Cleaning Supplies', 'pack', 'Wipe stations',                                 4,  8,   960.00),
  ('Floor Cleaner 5L',                       'PHF-CLEAN-003','Cleaning Supplies', 'each', 'Nightly floor clean',                           7,  3,  2100.00),
  ('Gym Towels - Microfibre (pack/10)',      'PHF-EQ-TOWEL', 'Equipment',         'pack', 'Loan towels, laundered weekly',                12,  5,  3200.00),
  ('Resistance Band Set',                    'PHF-EQ-BANDS', 'Equipment',         'each', 'Functional box, walk-off losses',                8,  4,  1850.00),
  ('Yoga Mat 6mm',                           'PHF-EQ-MAT',   'Equipment',         'each', 'Studio A loan mats',                            16, 10,  3200.00),
  ('Membership Keycards (pack/100)',         'PHF-MERCH-001','Merchandise',       'pack', 'Blank RFID cards for new members',               2,  1, 12500.00),
  ('Branded T-shirt (assorted sizes)',       'PHF-MERCH-002','Merchandise',       'each', 'Sold at the desk',                              25, 10,  1900.00)
) AS v(name, sku, category, unit, description, qty, reorder, cost)
WHERE NOT EXISTS (SELECT 1 FROM "InventoryItems" i WHERE i."TenantId" = ctx.tenant_id AND i."Sku" = v.sku);

INSERT INTO "StockMovements"
  ("Id","TenantId","InventoryItemId","BranchId","SupplierId","MovementType","Quantity","UnitCost","Reference","Notes","OccurredAt","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, i."Id", i."BranchId",
       (SELECT s."Id" FROM "Suppliers" s WHERE s."TenantId" = ctx.tenant_id AND s."Name" = v.supplier LIMIT 1),
       v.movement, v.qty, v.cost, v.reference, v.notes, pg_temp.lk(v.day, v.at_time), now(), now()
FROM (VALUES
  ('PHF-SUPP-001',  'Receive',    24,  8900.00, 'NutriMax Lanka (Pvt) Ltd', 'PO-PHF-2026-031', 'Monthly supplement order',                 -12, TIME '10:30'),
  ('PHF-SUPP-005',  'Receive',    12,  3600.00, 'NutriMax Lanka (Pvt) Ltd', 'PO-PHF-2026-031', 'Monthly supplement order',                 -12, TIME '10:30'),
  ('PHF-BEV-001',   'Receive',    36,  1440.00, NULL,                        'PO-PHF-2026-032', 'Water for the desk fridge',                 -9, TIME '11:00'),
  ('PHF-CLEAN-001', 'Receive',    12,   580.00, 'CleanPro Supplies',         'PO-PHF-2026-033', 'Cleaning restock',                          -7, TIME '09:15'),
  ('PHF-SUPP-002',  'Adjustment', -4,  NULL,    NULL,                        'ADJ-PHF-0012',    'Stock take: 4 tubs short at the bar',       -3, TIME '21:10'),
  ('PHF-EQ-BANDS',  'Adjustment', -2,  NULL,    NULL,                        'ADJ-PHF-0013',    'Two band sets missing from the box',        -2, TIME '20:45'),
  ('PHF-CLEAN-002', 'Adjustment', -6,  NULL,    NULL,                        'ADJ-PHF-0014',    'Issued to the wipe stations',               -1, TIME '07:05')
) AS v(sku, movement, qty, cost, supplier, reference, notes, day, at_time)
JOIN _seed_ctx ctx ON true
JOIN "InventoryItems" i ON i."TenantId" = ctx.tenant_id AND i."Sku" = v.sku
WHERE NOT EXISTS (SELECT 1 FROM "StockMovements" m WHERE m."InventoryItemId" = i."Id" AND m."Reference" = v.reference);

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _seed_mem;
  IF n < 24 THEN RAISE EXCEPTION 'Only % of 24 members resolved - check the member emails.', n; END IF;
  IF (SELECT count(*) FROM _seed_res) < 10 OR (SELECT count(*) FROM _seed_bt) < 6 THEN
    RAISE EXCEPTION 'Expected 10 PHF-* resources and 6 phf-* activities, found % / %.', (SELECT count(*) FROM _seed_res), (SELECT count(*) FROM _seed_bt);
  END IF;
END $$;

COMMIT;

-- ── Summary ─────────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM "Users" u JOIN _seed_ctx c ON u."TenantId" = c.tenant_id AND u."Role" = 3)                         AS members,
  (SELECT count(*) FROM "Subscriptions" s JOIN _seed_ctx c ON s."TenantId" = c.tenant_id)                                  AS memberships,
  (SELECT count(*) FROM "bookings" b JOIN _seed_ctx c ON b."TenantId" = c.tenant_id AND b."CheckInAt" IS NOT NULL)         AS check_ins,
  (SELECT count(*) FROM "bookings" b JOIN _seed_ctx c ON b."TenantId" = c.tenant_id AND b."Status" = 'CheckedIn')          AS inside_now,
  (SELECT count(*) FROM "bookings" b JOIN _seed_ctx c ON b."TenantId" = c.tenant_id AND b."StartTime" > now())             AS upcoming,
  (SELECT count(*) FROM "EquipmentItems" e JOIN _seed_ctx c ON e."TenantId" = c.tenant_id)                                 AS equipment,
  (SELECT count(*) FROM "equipment_reservations" x JOIN _seed_ctx c ON x."TenantId" = c.tenant_id)                         AS equipment_uses,
  (SELECT count(*) FROM "equipment_maintenances" m JOIN _seed_eq e ON m."EquipmentItemId" = e.eq_id)                       AS maintenance_rows,
  (SELECT count(*) FROM "InventoryItems" i JOIN _seed_ctx c ON i."TenantId" = c.tenant_id)                                 AS inventory_items,
  (SELECT count(*) FROM "Suppliers" x JOIN _seed_ctx c ON x."TenantId" = c.tenant_id AND x."IsActive")                     AS suppliers;

-- Logins:
--   admin@powerhousefitness.lk                 owner view    - Demo@12345 if seed-demo-data.ps1 made it, else Passw0rd!
--   manager.powerhouse@example-demo.test       manager view  - Passw0rd!
--   frontdesk.powerhouse@example-demo.test     floor view (Staff, no revenue) - Passw0rd!
