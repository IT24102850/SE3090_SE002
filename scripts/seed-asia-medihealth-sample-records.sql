-- ============================================================================
-- Sample RECORDS for the "Asia Medihealth Services" (Weligama) clinic tenant.
--
-- Run AFTER scripts/seed-asia-medihealth-weligama.sql - that one creates the
-- tenant, branch, rooms, consultant roster and booking types; this one fills
-- them with activity so every clinic screen has something to show:
--
--   1) Staff users        - manager, receptionist, nurse
--   2) Patients           - 8 customers, mixed insured / uninsured / tourists
--   3) Resource schedules - OPD daily, consultants on their own evenings
--   4) Bookings           - 25 appointments over the last 6 days, today and
--                           the next 4 days, every clinic status represented,
--                           with real check-in / consult / check-out stamps so
--                           the wait-time and visit-length KPIs have data
--   5) Booking reminders  - for today's appointments
--   6) Inventory          - 14 medical supply items + 4 stock movements
--
-- Everything here is DEMO DATA. Patients, staff, phone numbers, insurance
-- numbers and stock levels are invented; the emails use the reserved
-- example-demo.test domain and the password for every login is  Passw0rd!
-- The clinic, its address, consultants and services come from the first
-- script and are real.
--
-- Times are written in Sri Lanka time (Asia/Colombo) and stored as
-- timestamptz, so the schedule reads correctly whatever the DB session
-- timezone is. "Today" is today in Colombo.
--
-- Idempotent: every INSERT is guarded (email / code / title / sku), so
-- re-running adds nothing. Wrapped in one transaction.
--
--   psql "$DATABASE_URL" -f scripts/seed-asia-medihealth-sample-records.sql
-- ============================================================================

BEGIN;

-- ── 0) Context: tenant, admin, branch, resources, booking types ─────────────
DROP TABLE IF EXISTS _seed_ctx;
DROP TABLE IF EXISTS _seed_branch;
DROP TABLE IF EXISTS _seed_res;
DROP TABLE IF EXISTS _seed_bt;
DROP TABLE IF EXISTS _seed_pat;
DROP TABLE IF EXISTS _seed_bookings;

CREATE TEMP TABLE _seed_ctx AS
SELECT t."Id" AS tenant_id,
       (SELECT u."Id" FROM "Users" u
         WHERE u."TenantId" = t."Id" AND u."Role" = 0
         ORDER BY u."CreatedAt" LIMIT 1) AS admin_user_id
FROM "Tenants" t
WHERE t."Name" = 'Asia Medihealth Services' AND t."BusinessType" = 'Clinic';

DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM _seed_ctx;
  IF n = 0 THEN
    RAISE EXCEPTION 'Tenant "Asia Medihealth Services" not found - run scripts/seed-asia-medihealth-weligama.sql first.';
  ELSIF n > 1 THEN
    RAISE EXCEPTION '% tenants are named "Asia Medihealth Services" - pin one by Id in the _seed_ctx query.', n;
  END IF;
  IF (SELECT admin_user_id FROM _seed_ctx) IS NULL THEN
    RAISE EXCEPTION 'Tenant has no Admin user - approvals below need one.';
  END IF;
END $$;

CREATE TEMP TABLE _seed_branch AS
SELECT b."Id" AS branch_id
FROM "Branches" b JOIN _seed_ctx ctx ON b."TenantId" = ctx.tenant_id
WHERE b."Name" = 'Weligama (Matara Road)'
LIMIT 1;

-- Resources and booking types are looked up by the codes / slugs the first
-- script created, so this file never depends on generated UUIDs.
CREATE TEMP TABLE _seed_res AS
SELECT r."Id" AS resource_id, r."Code" AS code
FROM "resources" r JOIN _seed_ctx ctx ON r."TenantId" = ctx.tenant_id
WHERE r."Code" LIKE 'AMS-%';

CREATE TEMP TABLE _seed_bt AS
SELECT bt."Id" AS bt_id, bt."Slug" AS slug, bt."DefaultDurationMinutes" AS minutes
FROM "booking_types" bt JOIN _seed_ctx ctx ON bt."TenantId" = ctx.tenant_id
WHERE bt."Slug" LIKE 'ams-%';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM _seed_branch) THEN
    RAISE EXCEPTION 'Branch "Weligama (Matara Road)" missing - run the first seed.';
  END IF;
  IF (SELECT count(*) FROM _seed_res) < 28 OR (SELECT count(*) FROM _seed_bt) < 15 THEN
    RAISE EXCEPTION 'Expected 28 AMS-* resources and 15 ams-* booking types, found % / %. Run the first seed.',
      (SELECT count(*) FROM _seed_res), (SELECT count(*) FROM _seed_bt);
  END IF;
END $$;

-- Colombo-local "day offset + time of day" -> timestamptz.
CREATE OR REPLACE FUNCTION pg_temp.lk(day_offset int, t time) RETURNS timestamptz
LANGUAGE sql STABLE AS $$
  SELECT (((now() AT TIME ZONE 'Asia/Colombo')::date + day_offset) + t) AT TIME ZONE 'Asia/Colombo';
$$;

-- ── 1) Staff users ──────────────────────────────────────────────────────────
-- Role: 0 Admin, 1 Manager, 2 Staff, 3 Customer.
INSERT INTO "Users"
  ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","Email","PasswordHash",
   "FullName","Phone","Role","IsActive","IsApproved")
SELECT gen_random_uuid(), now() - interval '90 days', now(), ctx.tenant_id, br.branch_id,
       v.email, '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
       v.full_name, v.phone, v.role, true, true
FROM _seed_ctx ctx, _seed_branch br,
(VALUES
  ('manager.ams@example-demo.test',   'Priyantha Weerasinghe', '+94412253209', 1),
  ('reception.ams@example-demo.test', 'Sachini Madushika',     '+94770112233', 2),
  ('nurse.ams@example-demo.test',     'Nirosha Kumari',        '+94770112244', 2)
) AS v(email, full_name, phone, role)
WHERE NOT EXISTS (SELECT 1 FROM "Users" u WHERE lower(u."Email") = v.email);

-- ── 2) Patients ─────────────────────────────────────────────────────────────
-- Insurance is a property of the patient (User.InsuranceProvider); the
-- clinic report groups revenue by it and buckets blanks as "Uninsured", so
-- the mix is deliberate: 3 local insurers, 2 travel insurers, 3 uninsured.
INSERT INTO "Users"
  ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","Email","PasswordHash",
   "FullName","Phone","Role","IsActive","IsApproved",
   "Address","InsuranceProvider","InsuranceNumber","MedicalNotes")
SELECT gen_random_uuid(), now() - (v.days_ago || ' days')::interval, now(), ctx.tenant_id, br.branch_id,
       v.email, '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
       v.full_name, v.phone, 3, true, true,
       v.address, v.insurer, v.policy, v.notes
FROM _seed_ctx ctx, _seed_branch br,
(VALUES
  ('nimal.wickramasinghe@example-demo.test', 'Nimal Wickramasinghe', '+94771234501',
   'No. 12, Pelena, Weligama', 'Ceylinco Life', 'CL-448211', 'Hypertension - on losartan. Annual cardiology review.', 400),
  ('sunethra.gunasekara@example-demo.test', 'Sunethra Gunasekara', '+94771234502',
   'Kapparatota Road, Weligama', 'Sri Lanka Insurance', 'SLI-90217', 'Type 2 diabetes. Metformin. HbA1c due.', 300),
  ('kamal.jayaweera@example-demo.test', 'Kamal Jayaweera', '+94771234503',
   'Galbokka, Weligama', NULL, NULL, NULL, 120),
  ('dilani.rathnayake@example-demo.test', 'Dilani Rathnayake', '+94771234504',
   'Mirissa Road, Weligama', 'AIA Insurance', 'AIA-77310', 'Antenatal - 2nd trimester.', 60),
  ('ruwani.peiris@example-demo.test', 'Ruwani Peiris', '+94771234505',
   'Denuwala, Weligama', NULL, NULL, 'Books paediatric visits for her son (age 4).', 45),
  ('olga.petrova@example-demo.test', 'Olga Petrova', '+79161234567',
   'Guesthouse - Weligama Bay', 'Allianz Travel', 'ATP-2026-55901', 'Russian speaking - prefers Dr slot with Russian-speaking staff. Penicillin allergy.', 14),
  ('anna.sokolova@example-demo.test', 'Anna Sokolova', '+79169876543',
   'Villa - Midigama', NULL, NULL, 'Russian speaking. Travelling with Olga Petrova.', 14),
  ('jake.morrison@example-demo.test', 'Jake Morrison', '+61412345678',
   'Surf camp - Weligama Beach', 'World Nomads', 'WN-AU-330187', 'Surf laceration, left shin - sutured, follow-up dressing scheduled.', 6)
) AS v(email, full_name, phone, address, insurer, policy, notes, days_ago)
WHERE NOT EXISTS (SELECT 1 FROM "Users" u WHERE lower(u."Email") = v.email);

CREATE TEMP TABLE _seed_pat AS
SELECT u."Id" AS user_id, split_part(u."Email", '.', 1) AS label   -- nimal, sunethra, ...
FROM "Users" u JOIN _seed_ctx ctx ON u."TenantId" = ctx.tenant_id
WHERE u."Role" = 3 AND u."Email" LIKE '%@example-demo.test';

-- ── 3) Resource schedules ───────────────────────────────────────────────────
-- DayOfWeek 0 = Sunday. Skipped for any resource that already has a row.

-- 3a) OPD rooms, duty doctors, lab, imaging, dental and procedure rooms:
--     every day 08:00-20:00 (the profile hours), lunch 13:00-14:00.
INSERT INTO "resource_schedules"
  ("Id","CreatedAt","UpdatedAt","ResourceId","DayOfWeek","StartTime","EndTime",
   "IsAvailable","LunchBreakStart","LunchBreakEnd")
SELECT gen_random_uuid(), now(), now(), r.resource_id, d.dow,
       TIME '08:00', TIME '20:00', true, TIME '13:00', TIME '14:00'
FROM _seed_res r CROSS JOIN generate_series(0, 6) AS d(dow)
WHERE r.code IN ('AMS-OPD-01','AMS-OPD-02','AMS-CH-01','AMS-GP-01','AMS-GP-02',
                 'AMS-LAB-01','AMS-XR-01','AMS-US-01','AMS-DEN-01','AMS-EYE-01',
                 'AMS-SKIN-01','AMS-PAIN-01','AMS-MT-01')
  AND NOT EXISTS (SELECT 1 FROM "resource_schedules" s WHERE s."ResourceId" = r.resource_id);

-- 3b) Visiting consultants: evening sessions on two fixed days each.
--     (Days are demo choices - the clinic does not publish its channelling
--     timetable.)
INSERT INTO "resource_schedules"
  ("Id","CreatedAt","UpdatedAt","ResourceId","DayOfWeek","StartTime","EndTime","IsAvailable")
SELECT gen_random_uuid(), now(), now(), r.resource_id, v.dow, TIME '16:00', TIME '19:00', true
FROM _seed_res r
JOIN (VALUES
  ('AMS-DR-01', 1), ('AMS-DR-01', 4),   -- General Surgeon        Mon/Thu
  ('AMS-DR-02', 2), ('AMS-DR-02', 5),   -- O&G                    Tue/Fri
  ('AMS-DR-03', 3), ('AMS-DR-03', 6),   -- O&G                    Wed/Sat
  ('AMS-DR-04', 1), ('AMS-DR-04', 5),   -- Gastroenterologist     Mon/Fri
  ('AMS-DR-05', 3), ('AMS-DR-05', 0),   -- Psychiatrist           Wed/Sun
  ('AMS-DR-06', 0), ('AMS-DR-06', 1), ('AMS-DR-06', 2), ('AMS-DR-06', 3),
  ('AMS-DR-06', 4), ('AMS-DR-06', 5), ('AMS-DR-06', 6),   -- Physician daily
  ('AMS-DR-07', 2), ('AMS-DR-07', 6),   -- Cardiologist           Tue/Sat
  ('AMS-DR-08', 1), ('AMS-DR-08', 4),   -- Dermatologist          Mon/Thu
  ('AMS-DR-09', 3), ('AMS-DR-09', 6),   -- Radiologist            Wed/Sat
  ('AMS-DR-10', 2), ('AMS-DR-10', 5),   -- Ophthalmologist        Tue/Fri
  ('AMS-DR-11', 0), ('AMS-DR-11', 3),   -- Paediatrician          Sun/Wed
  ('AMS-DR-12', 4),                     -- Chest                  Thu
  ('AMS-DR-13', 0), ('AMS-DR-13', 4),   -- Cardiologist           Sun/Thu
  ('AMS-DR-14', 2), ('AMS-DR-14', 6)    -- Orthopaedic Surgeon    Tue/Sat
) AS v(code, dow) ON v.code = r.code
WHERE NOT EXISTS (SELECT 1 FROM "resource_schedules" s WHERE s."ResourceId" = r.resource_id);

-- ── 4) Bookings ─────────────────────────────────────────────────────────────
-- One row per appointment. Columns:
--   day     : offset from today (Colombo)            start : local start time
--   res     : resource code                          bt    : booking type slug
--   pat     : patient label (email local-part)       status/priority/source
--   cost    : LKR, matches the booking type's basePrice (0 when cancelled/rejected)
--   ci/cs/co: minutes relative to start for CheckInAt / ConsultationStartedAt /
--             CheckOutAt (NULL = not reached). Negative = before start.
--   approved: true -> ApprovedBy admin (approval-required types)
--   reason  : CancellationReason or RejectionReason depending on status
--
-- Source values match the channel-split report: WalkIn | Online | Phone.
-- BookedBy = the patient; CreatedBy = the admin for walk-in / phone bookings.
CREATE TEMP TABLE _seed_bookings (
  n int, day int, start time, res text, bt text, pat text, status text, priority text,
  source text, cost numeric, ci int, cs int, co int, approved boolean, reason text,
  title text, notes text
);
INSERT INTO _seed_bookings VALUES
-- ── last week ──
 ( 1, -6, '09:00', 'AMS-OPD-01', 'ams-opd-consultation',      'nimal',    'Completed', 'Normal', 'WalkIn', 2500,  -5,  10,  25, false, NULL,
   'OPD - Nimal Wickramasinghe', 'BP review. 142/90 - dose adjusted, review in 4 weeks.'),
 ( 2, -6, '16:30', 'AMS-DR-07',  'ams-specialist-channelling', 'sunethra', 'Completed', 'Normal', 'Online', 4500, -10,  20,  40, false, NULL,
   'Cardiology - Sunethra Gunasekara', 'Diabetic cardiac screen. ECG normal. Echo recommended.'),
 ( 3, -5, '11:00', 'AMS-LAB-01', 'ams-pcr-test',               'olga',     'Completed', 'Normal', 'Online', 6500,  -2,   2,  15, false, NULL,
   'PCR - Olga Petrova', 'Fit-to-fly PCR. Result emailed same evening.'),
 ( 4, -5, '15:00', 'AMS-MT-01',  'ams-wound-care-dressing',    'jake',     'Completed', 'High',   'WalkIn', 2000, -10,   5,  35, false, NULL,
   'Wound care - Jake Morrison', 'Reef cut, left shin, 4 cm. Irrigated and sutured (3). Tetanus up to date.'),
 ( 5, -4, '16:30', 'AMS-DR-02',  'ams-specialist-channelling', 'dilani',   'NoShow',    'Normal', 'Online', 4500, NULL, NULL, NULL, false, NULL,
   'O&G - Dilani Rathnayake', NULL),
 ( 6, -4, '17:30', 'AMS-US-01',  'ams-ultrasound-scan',        'dilani',   'Cancelled', 'Normal', 'Online',    0, NULL, NULL, NULL, false,
   'Patient missed the consultant appointment; scan rebooked for a later date.',
   'Ultrasound - Dilani Rathnayake', NULL),
 ( 7, -3, '09:30', 'AMS-DEN-01', 'ams-dental-consultation',    'kamal',    'Completed', 'Normal', 'WalkIn', 3000,  -5,  15,  45, false, NULL,
   'Dental - Kamal Jayaweera', 'Toothache lower right. Filling done.'),
 ( 8, -3, '16:00', 'AMS-DR-08',  'ams-specialist-channelling', 'olga',     'Completed', 'Normal', 'Online', 4500, -15,  10,  30, false, NULL,
   'Dermatology - Olga Petrova', 'Sun rash on shoulders. Topical steroid. Russian-speaking nurse assisted.'),
 ( 9, -2, '10:00', 'AMS-GP-02',  'ams-opd-consultation',       'anna',     'Completed', 'Normal', 'WalkIn', 2500,  -8,  12,  27, false, NULL,
   'OPD - Anna Sokolova', 'Traveller''s diarrhoea, 2 days. ORS + antibiotics. Russian-speaking doctor.'),
 (10, -2, '11:00', 'AMS-XR-01',  'ams-xray',                   'jake',     'Completed', 'Normal', 'Phone',  3500,  -5,   5,  25, false, NULL,
   'X-ray - Jake Morrison', 'Right wrist after a fall on the board. No fracture.'),
 (11, -1, '16:00', 'AMS-DR-11',  'ams-specialist-channelling', 'ruwani',   'Completed', 'Normal', 'Online', 4500, -10,  25,  45, false, NULL,
   'Paediatrics - Ruwani Peiris (son)', 'Recurrent cough, 4-year-old. Inhaler technique reviewed.'),
 (12, -1, '18:00', 'AMS-DR-13',  'ams-specialist-channelling', 'nimal',    'Rejected',  'Normal', 'Online',    0, NULL, NULL, NULL, false,
   'Consultant unavailable this evening - patient offered Dr Gunawardena on Saturday instead.',
   'Cardiology - Nimal Wickramasinghe', NULL),
-- ── today ──
 (13,  0, '08:30', 'AMS-OPD-01', 'ams-opd-consultation',       'kamal',    'Completed',  'Normal', 'WalkIn', 2500,  -5,  10,  25, false, NULL,
   'OPD - Kamal Jayaweera', 'Post-filling check. All fine.'),
 (14,  0, '09:00', 'AMS-OPD-02', 'ams-opd-consultation',       'sunethra', 'Completed',  'Normal', 'Phone',  2500,  -3,   8,  22, false, NULL,
   'OPD - Sunethra Gunasekara', 'Fasting glucose 148. Metformin continued. HbA1c sent to lab.'),
 (15,  0, '09:30', 'AMS-OPD-01', 'ams-opd-consultation',       'ruwani',   'InProgress', 'Normal', 'WalkIn', 2500, -10,   5, NULL, false, NULL,
   'OPD - Ruwani Peiris', 'Sore throat, 3 days.'),
 (16,  0, '10:00', 'AMS-OPD-02', 'ams-opd-consultation',       'anna',     'CheckedIn',  'High',   'WalkIn', 2500, -10, NULL, NULL, false, NULL,
   'OPD - Anna Sokolova', 'Fever 38.9 since last night. Triage: see next.'),
 (17,  0, '10:30', 'AMS-LAB-01', 'ams-rapid-antigen-test',     'jake',     'Confirmed',  'Normal', 'Online', 2250, NULL, NULL, NULL, false, NULL,
   'RAT - Jake Morrison', NULL),
 (18,  0, '11:00', 'AMS-DR-06',  'ams-specialist-channelling', 'nimal',    'Confirmed',  'Normal', 'Online', 4500, NULL, NULL, NULL, false, NULL,
   'Physician - Nimal Wickramasinghe', 'BP follow-up after dose change.'),
 (19,  0, '16:30', 'AMS-DR-07',  'ams-specialist-channelling', 'dilani',   'Confirmed',  'Normal', 'Online', 4500, NULL, NULL, NULL, false, NULL,
   'Cardiology - Dilani Rathnayake', 'Palpitations in pregnancy - referred by O&G.'),
 (20,  0, '17:00', 'AMS-US-01',  'ams-echocardiogram',         'sunethra', 'Pending',    'Normal', 'Online', 9000, NULL, NULL, NULL, false, NULL,
   'Echo - Sunethra Gunasekara', 'Recommended at last week''s cardiology visit. Awaiting approval.'),
-- ── coming days ──
 (21,  1, '09:00', 'AMS-OPD-01', 'ams-opd-consultation',       'olga',     'Confirmed',  'Normal', 'Online', 2500, NULL, NULL, NULL, false, NULL,
   'OPD - Olga Petrova', 'Rash review.'),
 (22,  1, '16:00', 'AMS-DR-04',  'ams-specialist-channelling', 'kamal',    'Pending',    'Normal', 'Online', 4500, NULL, NULL, NULL, false, NULL,
   'Gastroenterology - Kamal Jayaweera', 'Reflux for 3 months.'),
 (23,  2, '15:00', 'AMS-MT-01',  'ams-minor-procedure',        'jake',     'Confirmed',  'High',   'Phone', 12000, NULL, NULL, NULL, true,  NULL,
   'Suture removal + wound check - Jake Morrison', 'Sutures out day 7. Approved by admin.'),
 (24,  3, '16:30', 'AMS-DR-10',  'ams-eye-care-consultation',  'sunethra', 'Confirmed',  'Normal', 'Online', 4500, NULL, NULL, NULL, false, NULL,
   'Eye care - Sunethra Gunasekara', 'Annual diabetic retinal check.'),
 (25,  4, '14:00', 'AMS-GP-01',  'ams-home-hotel-visit',       'anna',     'Pending',    'Normal', 'Phone',  8000, NULL, NULL, NULL, false, NULL,
   'Villa visit - Anna Sokolova (Midigama)', 'Requested a doctor at the villa for a follow-up. Awaiting approval.');

INSERT INTO "bookings"
  ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes",
   "StartTime","EndTime","Status","Priority","AttendeeCount","Source",
   "CheckInAt","ConsultationStartedAt","CheckOutAt",
   "ApprovedBy","ApprovedAt","CancellationReason","RejectionReason",
   "TotalCost","ReminderSent","CreatedBy","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, p.user_id,
       s.title, s.notes,
       pg_temp.lk(s.day, s.start),
       pg_temp.lk(s.day, s.start) + (bt.minutes || ' minutes')::interval,
       s.status, s.priority, 1, s.source,
       CASE WHEN s.ci IS NOT NULL THEN pg_temp.lk(s.day, s.start) + (s.ci || ' minutes')::interval END,
       CASE WHEN s.cs IS NOT NULL THEN pg_temp.lk(s.day, s.start) + (s.cs || ' minutes')::interval END,
       CASE WHEN s.co IS NOT NULL THEN pg_temp.lk(s.day, s.start) + (s.co || ' minutes')::interval END,
       CASE WHEN s.approved THEN ctx.admin_user_id END,
       CASE WHEN s.approved THEN pg_temp.lk(s.day, s.start) - interval '1 day' END,
       CASE WHEN s.status = 'Cancelled' THEN s.reason END,
       CASE WHEN s.status = 'Rejected'  THEN s.reason END,
       s.cost,
       s.day <= 0,                                             -- past/today: reminder already went
       CASE WHEN s.source IN ('WalkIn','Phone') THEN ctx.admin_user_id END,
       LEAST(pg_temp.lk(s.day, s.start) - interval '2 days', now()),
       LEAST(pg_temp.lk(s.day, s.start), now()),
       1
FROM _seed_bookings s
JOIN _seed_ctx ctx ON true
JOIN _seed_res  r  ON r.code  = s.res
JOIN _seed_bt   bt ON bt.slug = s.bt
JOIN _seed_pat  p  ON p.label = s.pat
WHERE NOT EXISTS (
  SELECT 1 FROM "bookings" b
  WHERE b."TenantId" = ctx.tenant_id AND b."Title" = s.title
    AND b."StartTime" = pg_temp.lk(s.day, s.start)
);

-- Every row in _seed_bookings should have resolved a resource, type and
-- patient; a typo above would otherwise just silently drop that booking.
DO $$
DECLARE missing text;
BEGIN
  SELECT string_agg(s.n::text, ', ') INTO missing
  FROM _seed_bookings s
  WHERE NOT EXISTS (SELECT 1 FROM _seed_res  WHERE code  = s.res)
     OR NOT EXISTS (SELECT 1 FROM _seed_bt   WHERE slug  = s.bt)
     OR NOT EXISTS (SELECT 1 FROM _seed_pat  WHERE label = s.pat);
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'Bookings % reference an unknown resource code, booking-type slug or patient label.', missing;
  END IF;
END $$;

-- ── 5) Booking reminders ────────────────────────────────────────────────────
-- Only today's appointments get a reminder row here (ReminderSent = true was
-- set on them above). Tomorrow onwards is left to ReminderDispatchService,
-- which sends its own Email reminder inside its lead time and writes the
-- row itself - seeding one would just make it look sent twice.
-- Channel: SMS | WhatsApp | Email.  Status: the service only writes "Sent".
INSERT INTO "booking_reminders" ("Id","CreatedAt","UpdatedAt","BookingId","Channel","Status","SentAt")
SELECT gen_random_uuid(), now(), now(), b."Id", v.channel, 'Sent',
       b."StartTime" - interval '20 hours'
FROM (VALUES
  ('Physician - Nimal Wickramasinghe',     'SMS'),
  ('Cardiology - Dilani Rathnayake',       'WhatsApp'),
  ('RAT - Jake Morrison',                  'Email'),
  ('Echo - Sunethra Gunasekara',           'Email')
) AS v(title, channel)
JOIN "bookings" b ON b."Title" = v.title
JOIN _seed_ctx ctx ON b."TenantId" = ctx.tenant_id
WHERE b."StartTime" >= pg_temp.lk(0, '00:00')
  AND NOT EXISTS (
    SELECT 1 FROM "booking_reminders" x WHERE x."BookingId" = b."Id" AND x."Channel" = v.channel
  );

-- ── 6) Inventory ────────────────────────────────────────────────────────────
-- Same shape as seed-inventory-all-tenants.sql (Colombo Family Clinic).
-- Quantities and costs are demo figures. Two items sit below reorder level
-- on purpose so the low-stock widget has something to flag.
INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id,
       v.name, v.sku, v.description, v.qty, v.reorder, v.cost, true, now(), now()
FROM _seed_ctx ctx, _seed_branch br,
(VALUES
  ('Paracetamol 500mg (x100 tabs)',           'AMS-PHARM-001', 'Analgesic / antipyretic strip pack',              220, 60, 245.00),
  ('Amoxicillin 500mg (x100 caps)',           'AMS-PHARM-002', 'Broad-spectrum antibiotic',                       140, 40, 1650.00),
  ('ORS Sachets (box/25)',                    'AMS-PHARM-003', 'Oral rehydration salts - high demand in season',   18, 20, 375.00),
  ('Cetirizine 10mg (x100 tabs)',             'AMS-PHARM-004', 'Antihistamine',                                    90, 30, 420.00),
  ('Surgical Gloves - Medium (box/100)',      'AMS-SURG-001',  'Latex examination gloves, sterile',                36, 20, 875.00),
  ('Suture Kit - Nylon 3/0 (x12)',            'AMS-SURG-002',  'Skin closure, mini theatre',                        9, 10, 2950.00),
  ('Sterile Dressing Pack',                   'AMS-SURG-003',  'Single-use wound dressing pack',                   85, 40, 310.00),
  ('Disposable Syringes 5ml (x100)',          'AMS-SURG-004',  'Single-use Luer-lock syringes',                    64, 50, 640.00),
  ('Rapid Antigen Test Kit (x25)',            'AMS-DIAG-001',  'COVID-19 RAT cassettes',                            7,  4, 18500.00),
  ('PCR Swab & VTM Kit (x50)',                'AMS-DIAG-002',  'Nasopharyngeal swab + viral transport medium',      3,  2, 21000.00),
  ('Blood Glucose Test Strips (x50)',         'AMS-DIAG-003',  'Compatible with Accu-Chek Active meter',           22, 25, 1850.00),
  ('ECG Electrodes (box/50)',                 'AMS-DIAG-004',  'Adult foam electrodes for ECG / echo',             12,  6, 2400.00),
  ('Type IIR Surgical Masks (box/50)',        'AMS-PPE-001',   'CE-certified surgical masks',                     110, 40, 1250.00),
  ('Alcohol Hand Sanitiser 500ml',            'AMS-HYG-001',   '70% isopropyl gel',                                31, 15, 320.00)
) AS v(name, sku, description, qty, reorder, cost)
WHERE NOT EXISTS (
  SELECT 1 FROM "InventoryItems" i WHERE i."TenantId" = ctx.tenant_id AND i."Sku" = v.sku
);

INSERT INTO "StockMovements"
  ("Id","TenantId","InventoryItemId","BranchId","MovementType","Quantity","UnitCost","Reference","Notes","OccurredAt","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, i."Id", i."BranchId",
       v.movement, v.qty, v.cost, v.reference, v.notes,
       now() - (v.days_ago || ' days')::interval, now(), now()
FROM (VALUES
  ('AMS-SURG-001', 'Receive',    50,  875.00,  'PO-AMS-2026-014', 'Monthly consumables order - Galle supplier', 7),
  ('AMS-PHARM-003','Receive',    30,  375.00,  'PO-AMS-2026-014', 'Monthly consumables order - Galle supplier', 7),
  ('AMS-DIAG-001', 'Adjustment', -3,  NULL,    'ADJ-AMS-0009',    'Two expired kits discarded, one damaged',    3),
  ('AMS-SURG-002', 'Adjustment', -2,  NULL,    'ADJ-AMS-0010',    'Used for suture on Jake Morrison (booking #4)', 5)
) AS v(sku, movement, qty, cost, reference, notes, days_ago)
JOIN _seed_ctx ctx ON true
JOIN "InventoryItems" i ON i."TenantId" = ctx.tenant_id AND i."Sku" = v.sku
WHERE NOT EXISTS (
  SELECT 1 FROM "StockMovements" m
  WHERE m."InventoryItemId" = i."Id" AND m."Reference" = v.reference
);

COMMIT;

-- ── Summary ─────────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM "Users" u JOIN _seed_ctx c ON u."TenantId" = c.tenant_id AND u."Role" = 3)   AS patients,
  (SELECT count(*) FROM "Users" u JOIN _seed_ctx c ON u."TenantId" = c.tenant_id AND u."Role" IN (1,2)) AS staff,
  (SELECT count(*) FROM "resource_schedules" s JOIN _seed_res r ON s."ResourceId" = r.resource_id)  AS schedule_rows,
  (SELECT count(*) FROM "bookings" b JOIN _seed_ctx c ON b."TenantId" = c.tenant_id)                AS bookings,
  (SELECT count(*) FROM "booking_reminders" x JOIN "bookings" b ON x."BookingId" = b."Id"
                                              JOIN _seed_ctx c ON b."TenantId" = c.tenant_id)       AS reminders,
  (SELECT count(*) FROM "InventoryItems" i JOIN _seed_ctx c ON i."TenantId" = c.tenant_id)          AS inventory_items,
  (SELECT count(*) FROM "StockMovements" m JOIN _seed_ctx c ON m."TenantId" = c.tenant_id)          AS stock_movements;

-- Bookings by status, for a quick eyeball:
--   SELECT "Status", count(*) FROM "bookings" b JOIN _seed_ctx c ON b."TenantId" = c.tenant_id
--   GROUP BY 1 ORDER BY 1;
