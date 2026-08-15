-- ============================================================================
-- Seed sample data for "Vihanga's" bike rental tenant so every sidebar
-- screen (Dashboard, Booking Manager, Resource Manager, Multi-Branch
-- Schedule, Reports, AI Planner, Booking Types, Staff, Branches) has real
-- data to render. Business Settings / Business Profile isn't touched here -
-- that's edited through its own UI, not seeded.
--
-- Run this once, as-is, in the Supabase SQL editor (or via psql) against the
-- project's Postgres database. It runs inside one transaction: if anything
-- fails, nothing is committed.
--
-- ASSUMPTION: it locates the tenant by looking up the Admin user named
-- 'Vihanga Nethmika' (as shown in the sidebar footer). If that doesn't
-- match exactly, edit the WHERE clause in step 0 below (or replace it with
-- a literal tenant UUID) before running.
--
-- Demo login for the new Staff/Customer accounts this script creates:
--   password: Passw0rd!
-- (real bcrypt hash below, verified to work with BCrypt.Net's Verify()).
-- ============================================================================

BEGIN;

-- ── 0) Locate the tenant ────────────────────────────────────────────────
CREATE TEMP TABLE _seed_ctx AS
SELECT u."Id" AS admin_user_id, u."TenantId" AS tenant_id
FROM "Users" u
WHERE u."FullName" = 'Vihanga Nethmika' AND u."Role" = 0
LIMIT 1;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM _seed_ctx) THEN
    RAISE EXCEPTION 'Could not find an Admin user named "Vihanga Nethmika" - edit the WHERE clause in step 0 to match your actual admin, or hardcode the tenant UUID.';
  END IF;
END $$;

-- ── 1) Branches ──────────────────────────────────────────────────────────
CREATE TEMP TABLE _seed_branches (branch_id uuid, label text);

INSERT INTO "Branches" ("Id","CreatedAt","UpdatedAt","TenantId","Name","Address","Phone","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, 'Mirissa Beach Branch', '123 Beach Road, Mirissa', '+94771234567', true
FROM _seed_ctx ctx;

INSERT INTO "Branches" ("Id","CreatedAt","UpdatedAt","TenantId","Name","Address","Phone","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, 'Weligama Bay Branch', '45 Bay Street, Weligama', '+94777654321', true
FROM _seed_ctx ctx;

INSERT INTO _seed_branches (branch_id, label)
SELECT b."Id", CASE WHEN b."Name" = 'Mirissa Beach Branch' THEN 'mirissa' ELSE 'weligama' END
FROM "Branches" b
JOIN _seed_ctx ctx ON b."TenantId" = ctx.tenant_id
WHERE b."Name" IN ('Mirissa Beach Branch', 'Weligama Bay Branch');

-- ── 2) Staff (Role=2) and Customers (Role=3) ────────────────────────────
-- Demo password for both: Passw0rd!
INSERT INTO "Users" ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","Email","PasswordHash","FullName","Phone","Role","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, br.branch_id,
       'kasun.perera@vihangabikes-demo.test',
       '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
       'Kasun Perera', '+94712223344', 2, true
FROM _seed_ctx ctx, _seed_branches br WHERE br.label = 'mirissa';

INSERT INTO "Users" ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","Email","PasswordHash","FullName","Phone","Role","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, br.branch_id,
       'nadeesha.silva@vihangabikes-demo.test',
       '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
       'Nadeesha Silva', '+94715556677', 2, true
FROM _seed_ctx ctx, _seed_branches br WHERE br.label = 'weligama';

INSERT INTO "Users" ("Id","CreatedAt","UpdatedAt","TenantId","Email","PasswordHash","FullName","Phone","Role","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id,
       'ishara.fernando@example-demo.test',
       '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
       'Ishara Fernando', '+94718889900', 3, true
FROM _seed_ctx ctx;

INSERT INTO "Users" ("Id","CreatedAt","UpdatedAt","TenantId","Email","PasswordHash","FullName","Phone","Role","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id,
       'tharindu.jayasuriya@example-demo.test',
       '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
       'Tharindu Jayasuriya', '+94719990011', 3, true
FROM _seed_ctx ctx;

CREATE TEMP TABLE _seed_customers AS
SELECT u."Id" AS user_id, CASE WHEN u."Email" LIKE 'ishara%' THEN 'ishara' ELSE 'tharindu' END AS label
FROM "Users" u JOIN _seed_ctx ctx ON u."TenantId" = ctx.tenant_id
WHERE u."Email" IN ('ishara.fernando@example-demo.test', 'tharindu.jayasuriya@example-demo.test');

-- ── 3) Resources (bikes) ─────────────────────────────────────────────────
INSERT INTO "resources" ("Id","TenantId","BranchId","Name","Category","Status","Description","Capacity","HourlyRate","CreatedAt","UpdatedAt","CreatedBy")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id, 'Honda Dio - MB01', 'Vehicle', 'Available', 'Automatic scooter, great for short beach hops.', 1, 500.00, now(), now(), ctx.admin_user_id
FROM _seed_ctx ctx, _seed_branches br WHERE br.label = 'mirissa'
UNION ALL
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id, 'Yamaha FZ - MB02', 'Vehicle', 'Available', 'Manual geared bike for coastal roads.', 1, 700.00, now(), now(), ctx.admin_user_id
FROM _seed_ctx ctx, _seed_branches br WHERE br.label = 'mirissa'
UNION ALL
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id, 'TVS Scooter - MB03', 'Vehicle', 'UnderMaintenance', 'Currently in for a service - back in 2 days.', 1, 450.00, now(), now(), ctx.admin_user_id
FROM _seed_ctx ctx, _seed_branches br WHERE br.label = 'mirissa'
UNION ALL
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id, 'Honda Dio - WB01', 'Vehicle', 'Available', 'Automatic scooter.', 1, 500.00, now(), now(), ctx.admin_user_id
FROM _seed_ctx ctx, _seed_branches br WHERE br.label = 'weligama'
UNION ALL
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id, 'Royal Enfield - WB02', 'Vehicle', 'Available', 'Classic 350cc, popular for longer day trips.', 1, 1200.00, now(), now(), ctx.admin_user_id
FROM _seed_ctx ctx, _seed_branches br WHERE br.label = 'weligama'
UNION ALL
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id, 'Mountain Bicycle - WB03', 'Equipment', 'Available', 'Pedal bicycle, no license needed.', 1, 200.00, now(), now(), ctx.admin_user_id
FROM _seed_ctx ctx, _seed_branches br WHERE br.label = 'weligama';

CREATE TEMP TABLE _seed_resources AS
SELECT r."Id" AS resource_id, r."Name" AS name,
       CASE r."Name"
         WHEN 'Honda Dio - MB01' THEN 'mb01'
         WHEN 'Yamaha FZ - MB02' THEN 'mb02'
         WHEN 'TVS Scooter - MB03' THEN 'mb03'
         WHEN 'Honda Dio - WB01' THEN 'wb01'
         WHEN 'Royal Enfield - WB02' THEN 'wb02'
         WHEN 'Mountain Bicycle - WB03' THEN 'wb03'
       END AS label
FROM "resources" r JOIN _seed_ctx ctx ON r."TenantId" = ctx.tenant_id
WHERE r."Name" IN ('Honda Dio - MB01','Yamaha FZ - MB02','TVS Scooter - MB03','Honda Dio - WB01','Royal Enfield - WB02','Mountain Bicycle - WB03');

-- ── 4) Resource schedules (08:00-18:00, every day, all 6 resources) ─────
INSERT INTO "resource_schedules" ("Id","CreatedAt","UpdatedAt","ResourceId","DayOfWeek","StartTime","EndTime","IsAvailable")
SELECT gen_random_uuid(), now(), now(), r.resource_id, d.dow, TIME '08:00', TIME '18:00', true
FROM _seed_resources r CROSS JOIN generate_series(0, 6) AS d(dow);

-- ── 5) Booking types ─────────────────────────────────────────────────────
INSERT INTO "booking_types" ("Id","TenantId","Name","Slug","Description","ColorHex","Status","DefaultDurationMinutes","RequiresApproval","MaxParticipants","BufferMinutesBefore","BufferMinutesAfter","BookingUnit","CreatedAt","UpdatedAt","CreatedBy")
SELECT gen_random_uuid(), ctx.tenant_id, 'Hourly Bike Rental', 'hourly-bike-rental-' || substr(gen_random_uuid()::text,1,6), 'Rent a bike by the hour.', '#3B82F6', 'Active', 60, false, NULL::integer, 0, 15, 'Slot', now(), now(), ctx.admin_user_id
FROM _seed_ctx ctx
UNION ALL
SELECT gen_random_uuid(), ctx.tenant_id, 'Daily Bike Rental', 'daily-bike-rental-' || substr(gen_random_uuid()::text,1,6), 'Multi-day rental, pick up and drop off.', '#F59E0B', 'Active', 1440, false, NULL::integer, 0, 0, 'DateRange', now(), now(), ctx.admin_user_id
FROM _seed_ctx ctx
UNION ALL
SELECT gen_random_uuid(), ctx.tenant_id, 'Guided Coastal Bike Tour', 'guided-coastal-bike-tour-' || substr(gen_random_uuid()::text,1,6), 'Small-group guided ride along the coast, includes a guide.', '#7C3AED', 'Active', 180, true, 4, 30, 30, 'Slot', now(), now(), ctx.admin_user_id
FROM _seed_ctx ctx;

CREATE TEMP TABLE _seed_booking_types AS
SELECT bt."Id" AS bt_id, bt."Name" AS name,
       CASE bt."Name"
         WHEN 'Hourly Bike Rental' THEN 'hourly'
         WHEN 'Daily Bike Rental' THEN 'daily'
         WHEN 'Guided Coastal Bike Tour' THEN 'tour'
       END AS label
FROM "booking_types" bt JOIN _seed_ctx ctx ON bt."TenantId" = ctx.tenant_id
WHERE bt."Name" IN ('Hourly Bike Rental','Daily Bike Rental','Guided Coastal Bike Tour');

-- ── 6) Bookings (mixed statuses, both branches, past + today + future) ──
-- #1 Completed, 3 days ago
INSERT INTO "bookings" ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","TotalCost","ReminderSent","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, c.user_id,
       'Morning ride - Honda Dio (3 days ago)', 'Returned on time, no issues.',
       (CURRENT_DATE - 3)::timestamp + TIME '09:00', (CURRENT_DATE - 3)::timestamp + TIME '10:00',
       'Completed', 'Normal', 1, 500.00, true, now(), now(), 1
FROM _seed_ctx ctx, _seed_resources r, _seed_booking_types bt, _seed_customers c
WHERE r.label = 'mb01' AND bt.label = 'hourly' AND c.label = 'ishara';

-- #2 NoShow, 2 days ago
INSERT INTO "bookings" ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","TotalCost","ReminderSent","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, c.user_id,
       'Afternoon ride - Yamaha FZ (2 days ago)', 'Customer never arrived to collect the bike.',
       (CURRENT_DATE - 2)::timestamp + TIME '14:00', (CURRENT_DATE - 2)::timestamp + TIME '15:00',
       'NoShow', 'Normal', 1, 700.00, true, now(), now(), 1
FROM _seed_ctx ctx, _seed_resources r, _seed_booking_types bt, _seed_customers c
WHERE r.label = 'mb02' AND bt.label = 'hourly' AND c.label = 'tharindu';

-- #3 Cancelled, yesterday
INSERT INTO "bookings" ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","CancellationReason","TotalCost","ReminderSent","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, c.user_id,
       'Coastal cruise - Honda Dio Weligama (yesterday)', NULL,
       (CURRENT_DATE - 1)::timestamp + TIME '11:00', (CURRENT_DATE - 1)::timestamp + TIME '12:00',
       'Cancelled', 'Normal', 1, 'Guest changed travel plans.', 0.00, false, now(), now(), 1
FROM _seed_ctx ctx, _seed_resources r, _seed_booking_types bt, _seed_customers c
WHERE r.label = 'wb01' AND bt.label = 'hourly' AND c.label = 'ishara';

-- #4 CheckedIn, today
INSERT INTO "bookings" ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","CheckInAt","TotalCost","ReminderSent","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, c.user_id,
       'Morning ride - Royal Enfield (today)', 'Regular customer, always careful with the bike.',
       CURRENT_DATE::timestamp + TIME '09:00', CURRENT_DATE::timestamp + TIME '10:00',
       'CheckedIn', 'Normal', 1, CURRENT_DATE::timestamp + TIME '09:05', 1200.00, true, now(), now(), 1
FROM _seed_ctx ctx, _seed_resources r, _seed_booking_types bt, _seed_customers c
WHERE r.label = 'wb02' AND bt.label = 'hourly' AND c.label = 'tharindu';

-- #5 Confirmed, today (has a reminder below)
INSERT INTO "bookings" ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","TotalCost","ReminderSent","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, c.user_id,
       'Afternoon ride - Honda Dio Mirissa (today)', NULL,
       CURRENT_DATE::timestamp + TIME '15:00', CURRENT_DATE::timestamp + TIME '16:00',
       'Confirmed', 'Normal', 1, 500.00, true, now(), now(), 1
FROM _seed_ctx ctx, _seed_resources r, _seed_booking_types bt, _seed_customers c
WHERE r.label = 'mb01' AND bt.label = 'hourly' AND c.label = 'ishara';

-- #6 Pending, tomorrow (has a reminder below)
INSERT INTO "bookings" ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","TotalCost","ReminderSent","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, c.user_id,
       'Morning ride - Yamaha FZ (tomorrow)', 'Awaiting front-desk confirmation.',
       (CURRENT_DATE + 1)::timestamp + TIME '10:00', (CURRENT_DATE + 1)::timestamp + TIME '11:00',
       'Pending', 'Normal', 1, 700.00, false, now(), now(), 1
FROM _seed_ctx ctx, _seed_resources r, _seed_booking_types bt, _seed_customers c
WHERE r.label = 'mb02' AND bt.label = 'hourly' AND c.label = 'tharindu';

-- #7 Confirmed, tomorrow
INSERT INTO "bookings" ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","TotalCost","ReminderSent","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, c.user_id,
       'Afternoon cycle - Mountain Bicycle (tomorrow)', NULL,
       (CURRENT_DATE + 1)::timestamp + TIME '13:00', (CURRENT_DATE + 1)::timestamp + TIME '14:00',
       'Confirmed', 'Low', 1, 200.00, false, now(), now(), 1
FROM _seed_ctx ctx, _seed_resources r, _seed_booking_types bt, _seed_customers c
WHERE r.label = 'wb03' AND bt.label = 'hourly' AND c.label = 'ishara';

-- #8 Confirmed, multi-day DateRange rental starting today
INSERT INTO "bookings" ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","TotalCost","ReminderSent","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, c.user_id,
       '3-day rental - Honda Dio Weligama', 'Drop-off at Weligama Bay Branch.',
       CURRENT_DATE::timestamp + TIME '09:00', (CURRENT_DATE + 3)::timestamp + TIME '09:00',
       'Confirmed', 'Normal', 1, 4500.00, false, now(), now(), 1
FROM _seed_ctx ctx, _seed_resources r, _seed_booking_types bt, _seed_customers c
WHERE r.label = 'wb01' AND bt.label = 'daily' AND c.label = 'tharindu';

-- #9 Pending, in 4 days
INSERT INTO "bookings" ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","TotalCost","ReminderSent","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, c.user_id,
       'Morning ride - Royal Enfield (in 4 days)', NULL,
       (CURRENT_DATE + 4)::timestamp + TIME '09:00', (CURRENT_DATE + 4)::timestamp + TIME '10:00',
       'Pending', 'Normal', 1, 1200.00, false, now(), now(), 1
FROM _seed_ctx ctx, _seed_resources r, _seed_booking_types bt, _seed_customers c
WHERE r.label = 'wb02' AND bt.label = 'hourly' AND c.label = 'ishara';

-- #10 Confirmed, guided tour (approval-required type), in 5 days - approved by the admin
INSERT INTO "bookings" ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","ApprovedBy","ApprovedAt","TotalCost","ReminderSent","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, c.user_id,
       'Guided Coastal Bike Tour - Honda Dio Mirissa (in 5 days)', 'Group of 3, meet at Mirissa Beach Branch 15 min early.',
       (CURRENT_DATE + 5)::timestamp + TIME '08:00', (CURRENT_DATE + 5)::timestamp + TIME '11:00',
       'Confirmed', 'High', 3, ctx.admin_user_id, now() - interval '1 day', 3500.00, false, now(), now(), 1
FROM _seed_ctx ctx, _seed_resources r, _seed_booking_types bt, _seed_customers c
WHERE r.label = 'mb01' AND bt.label = 'tour' AND c.label = 'tharindu';

-- #11 Rejected, in 2 days
INSERT INTO "bookings" ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","RejectionReason","TotalCost","ReminderSent","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, c.user_id,
       'Afternoon ride - Royal Enfield (in 2 days)', NULL,
       (CURRENT_DATE + 2)::timestamp + TIME '15:00', (CURRENT_DATE + 2)::timestamp + TIME '16:00',
       'Rejected', 'Normal', 1, 'Vehicle already booked for a scheduled service on this date.', 0.00, false, now(), now(), 1
FROM _seed_ctx ctx, _seed_resources r, _seed_booking_types bt, _seed_customers c
WHERE r.label = 'wb02' AND bt.label = 'hourly' AND c.label = 'ishara';

-- ── 7) Booking reminders (tied to #5 and #6 above) ──────────────────────
INSERT INTO "booking_reminders" ("Id","CreatedAt","UpdatedAt","BookingId","Channel","Status","SentAt")
SELECT gen_random_uuid(), now(), now(), b."Id", 'Email', 'Sent', now() - interval '2 hours'
FROM "bookings" b JOIN _seed_ctx ctx ON b."TenantId" = ctx.tenant_id
WHERE b."Title" = 'Afternoon ride - Honda Dio Mirissa (today)';

INSERT INTO "booking_reminders" ("Id","CreatedAt","UpdatedAt","BookingId","Channel","Status","SentAt")
SELECT gen_random_uuid(), now(), now(), b."Id", 'SMS', 'Sent', now() - interval '1 hour'
FROM "bookings" b JOIN _seed_ctx ctx ON b."TenantId" = ctx.tenant_id
WHERE b."Title" = 'Morning ride - Yamaha FZ (tomorrow)';

-- ── 8) Sample AI Planner workflows ───────────────────────────────────────
-- NOTE ON THE DUAL "steps"/"Steps" KEYS BELOW: the React AI Planner page
-- parses PlanJson expecting lowercase keys ("steps", "agent", "parameters",
-- ...), but the backend's own PlanDto/StepDto records serialize (and
-- Apply() re-deserializes) using PascalCase ("Steps", "Agent", ...) with
-- System.Text.Json's default case-sensitive matching. That's a real,
-- pre-existing mismatch in the app, not something introduced by this seed -
-- worth a proper backend fix later. Storing both casings here is a
-- deliberate workaround so these sample workflows render correctly on
-- screen AND don't crash if you click "Apply" on one.

-- Workflow #1: staff-initiated, no approval needed
WITH step1_params AS (
  SELECT jsonb_build_object(
    'resourceId', r1.resource_id, 'resourceName', r1.name,
    'bookingTypeId', bt.bt_id,
    'startTime', to_char((CURRENT_DATE + 1)::timestamp + TIME '08:00', 'YYYY-MM-DD"T"HH24:MI:SS'),
    'endTime',   to_char((CURRENT_DATE + 1)::timestamp + TIME '09:00', 'YYYY-MM-DD"T"HH24:MI:SS')
  ) AS p
  FROM _seed_resources r1, _seed_booking_types bt
  WHERE r1.label = 'mb01' AND bt.label = 'hourly'
),
step2_params AS (
  SELECT jsonb_build_object(
    'resourceId', r2.resource_id, 'resourceName', r2.name,
    'bookingTypeId', bt.bt_id,
    'startTime', to_char((CURRENT_DATE + 1)::timestamp + TIME '09:00', 'YYYY-MM-DD"T"HH24:MI:SS'),
    'endTime',   to_char((CURRENT_DATE + 1)::timestamp + TIME '10:00', 'YYYY-MM-DD"T"HH24:MI:SS')
  ) AS p
  FROM _seed_resources r2, _seed_booking_types bt
  WHERE r2.label = 'mb02' AND bt.label = 'hourly'
)
INSERT INTO "agent_workflows" ("Id","CreatedAt","UpdatedAt","TenantId","Objective","PlanJson","Status","CurrentStep","ApprovalStatus","ApprovedBy","ApprovedAt","FinalOutcome","RequestedByUserId")
SELECT gen_random_uuid(), now() - interval '3 hours', now() - interval '3 hours', ctx.tenant_id,
  'Fill empty morning slots this week for Mirissa branch bikes',
  jsonb_build_object(
    'steps', jsonb_build_array(
      jsonb_build_object('agent','ActionToolAgent','action','CreateBooking','tool','bookings.create','parameters', s1.p),
      jsonb_build_object('agent','ActionToolAgent','action','CreateBooking','tool','bookings.create','parameters', s2.p)
    ),
    'Steps', jsonb_build_array(
      jsonb_build_object('Agent','ActionToolAgent','Action','CreateBooking','Tool','bookings.create','Parameters', s1.p),
      jsonb_build_object('Agent','ActionToolAgent','Action','CreateBooking','Tool','bookings.create','Parameters', s2.p)
    ),
    'estimatedRevenueImpact', 0, 'EstimatedRevenueImpact', 0
  )::text,
  'Approved', 2, 'NotRequired', ctx.admin_user_id, now() - interval '2 hours', NULL, NULL
FROM _seed_ctx ctx, step1_params s1, step2_params s2;

-- Workflow #2: customer-initiated (find-and-book), awaiting manager approval
-- (estimatedRevenueImpact deliberately set above the $500 default threshold)
WITH step1_params AS (
  SELECT jsonb_build_object(
    'resourceId', r.resource_id, 'resourceName', r.name,
    'bookingTypeId', bt.bt_id,
    'startTime', to_char((CURRENT_DATE + 6)::timestamp + TIME '08:00', 'YYYY-MM-DD"T"HH24:MI:SS'),
    'endTime',   to_char((CURRENT_DATE + 6)::timestamp + TIME '11:00', 'YYYY-MM-DD"T"HH24:MI:SS')
  ) AS p
  FROM _seed_resources r, _seed_booking_types bt
  WHERE r.label = 'mb01' AND bt.label = 'tour'
)
INSERT INTO "agent_workflows" ("Id","CreatedAt","UpdatedAt","TenantId","Objective","PlanJson","Status","CurrentStep","ApprovalStatus","RequestedByUserId")
SELECT gen_random_uuid(), now() - interval '40 minutes', now() - interval '40 minutes', ctx.tenant_id,
  'Book me a bike for a coastal tour this weekend',
  jsonb_build_object(
    'steps', jsonb_build_array(
      jsonb_build_object('agent','ActionToolAgent','action','CreateBooking','tool','bookings.create','parameters', s1.p)
    ),
    'Steps', jsonb_build_array(
      jsonb_build_object('Agent','ActionToolAgent','Action','CreateBooking','Tool','bookings.create','Parameters', s1.p)
    ),
    'estimatedRevenueImpact', 550, 'EstimatedRevenueImpact', 550
  )::text,
  'AwaitingApproval', 1, 'Pending', c.user_id
FROM _seed_ctx ctx, step1_params s1, _seed_customers c
WHERE c.label = 'ishara';

-- Workflow #3: staff-initiated bulk reschedule, awaiting approval
WITH step1_params AS (
  SELECT jsonb_build_object('resourceId', r.resource_id, 'resourceName', r.name, 'bookingTypeId', bt.bt_id,
    'startTime', to_char((CURRENT_DATE + 2)::timestamp + TIME '09:00', 'YYYY-MM-DD"T"HH24:MI:SS'),
    'endTime',   to_char((CURRENT_DATE + 2)::timestamp + TIME '10:00', 'YYYY-MM-DD"T"HH24:MI:SS')) AS p
  FROM _seed_resources r, _seed_booking_types bt WHERE r.label = 'wb01' AND bt.label = 'hourly'
),
step2_params AS (
  SELECT jsonb_build_object('resourceId', r.resource_id, 'resourceName', r.name, 'bookingTypeId', bt.bt_id,
    'startTime', to_char((CURRENT_DATE + 2)::timestamp + TIME '10:00', 'YYYY-MM-DD"T"HH24:MI:SS'),
    'endTime',   to_char((CURRENT_DATE + 2)::timestamp + TIME '11:00', 'YYYY-MM-DD"T"HH24:MI:SS')) AS p
  FROM _seed_resources r, _seed_booking_types bt WHERE r.label = 'wb02' AND bt.label = 'hourly'
),
step3_params AS (
  SELECT jsonb_build_object('resourceId', r.resource_id, 'resourceName', r.name, 'bookingTypeId', bt.bt_id,
    'startTime', to_char((CURRENT_DATE + 2)::timestamp + TIME '11:00', 'YYYY-MM-DD"T"HH24:MI:SS'),
    'endTime',   to_char((CURRENT_DATE + 2)::timestamp + TIME '12:00', 'YYYY-MM-DD"T"HH24:MI:SS')) AS p
  FROM _seed_resources r, _seed_booking_types bt WHERE r.label = 'wb03' AND bt.label = 'hourly'
)
INSERT INTO "agent_workflows" ("Id","CreatedAt","UpdatedAt","TenantId","Objective","PlanJson","Status","CurrentStep","ApprovalStatus")
SELECT gen_random_uuid(), now() - interval '10 minutes', now() - interval '10 minutes', ctx.tenant_id,
  'Reschedule bookings due to a half-day branch closure at Weligama',
  jsonb_build_object(
    'steps', jsonb_build_array(
      jsonb_build_object('agent','ActionToolAgent','action','RescheduleBooking','tool','bookings.reschedule','parameters', s1.p),
      jsonb_build_object('agent','ActionToolAgent','action','RescheduleBooking','tool','bookings.reschedule','parameters', s2.p),
      jsonb_build_object('agent','ActionToolAgent','action','RescheduleBooking','tool','bookings.reschedule','parameters', s3.p)
    ),
    'Steps', jsonb_build_array(
      jsonb_build_object('Agent','ActionToolAgent','Action','RescheduleBooking','Tool','bookings.reschedule','Parameters', s1.p),
      jsonb_build_object('Agent','ActionToolAgent','Action','RescheduleBooking','Tool','bookings.reschedule','Parameters', s2.p),
      jsonb_build_object('Agent','ActionToolAgent','Action','RescheduleBooking','Tool','bookings.reschedule','Parameters', s3.p)
    ),
    'estimatedRevenueImpact', 0, 'EstimatedRevenueImpact', 0
  )::text,
  'AwaitingApproval', 3, 'Pending'
FROM _seed_ctx ctx, step1_params s1, step2_params s2, step3_params s3;

-- Workflow #4: rejected
INSERT INTO "agent_workflows" ("Id","CreatedAt","UpdatedAt","TenantId","Objective","PlanJson","Status","CurrentStep","ApprovalStatus","ErrorLog","CompletedAt")
SELECT gen_random_uuid(), now() - interval '2 days', now() - interval '2 days', ctx.tenant_id,
  'Auto price-match a competitor discount on all rentals',
  jsonb_build_object('steps', jsonb_build_array(), 'Steps', jsonb_build_array(), 'estimatedRevenueImpact', 0, 'EstimatedRevenueImpact', 0)::text,
  'Rejected', 0, 'Rejected', 'Discount exceeds the platform''s configured cap.', now() - interval '2 days'
FROM _seed_ctx ctx;

COMMIT;

-- ── Summary ──────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM "Branches" b JOIN _seed_ctx ctx ON b."TenantId" = ctx.tenant_id) AS branches,
  (SELECT count(*) FROM "Users" u JOIN _seed_ctx ctx ON u."TenantId" = ctx.tenant_id AND u."Role" IN (2,3)) AS staff_and_customers,
  (SELECT count(*) FROM "resources" r JOIN _seed_ctx ctx ON r."TenantId" = ctx.tenant_id) AS resources,
  (SELECT count(*) FROM "booking_types" bt JOIN _seed_ctx ctx ON bt."TenantId" = ctx.tenant_id) AS booking_types,
  (SELECT count(*) FROM "bookings" bk JOIN _seed_ctx ctx ON bk."TenantId" = ctx.tenant_id) AS bookings,
  (SELECT count(*) FROM "agent_workflows" w JOIN _seed_ctx ctx ON w."TenantId" = ctx.tenant_id) AS agent_workflows;
