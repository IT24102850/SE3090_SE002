-- ============================================================================
-- Sample RECORDS for the "BrightMinds Tuition Center" (Kadawatha) school
-- tenant, so every panel of the school dashboard has something to show.
--
-- Works on its own: if the tenant from scripts/seed-demo-data.ps1 exists it
-- is reused (matched by name + BusinessType School); otherwise the tenant,
-- its admin and its branch are created here. Needs the Subscriptions table
-- (migration AddGymMembershipsAndDemographics - start the API once).
--
--   1) Module config    - term calendar, at-risk thresholds, grade scale
--   2) Resources        - 3 classrooms (Room, with capacity), 4 teachers
--                         (Staff, rostered; the 3 from seed-demo-data get
--                         codes), plus the demo-seed activity types
--   3) Subjects         - Grade 10 Maths / Science / English, Grade 11
--                         Maths / ICT, exam prep, tutoring - each with kind,
--                         subject and grade in ConfigJson
--   4) Assessments      - quizzes, term tests, a lab report, an essay and an
--                         ICT project, each with a weight
--   5) Staff logins     - principal (Manager); teacher logins already exist
--   6) Students         - 24 approved (with date of birth and 3 medical
--                         alerts / accommodations) + 2 awaiting approval
--   7) Tuition          - monthly grade packages; paid / pending / overdue /
--                         failed, two lapsed, earlier months for YTD
--   8) Timetable        - 5 weeks of sessions on the teacher (the register)
--                         and a "room hold" on the classroom (utilisation
--                         and clashes), one deliberate clash next week
--   9) Registers        - deterministic present / late / absent / excused
--                         marks, behaviour points and notes; today's
--                         finished sessions left unmarked on purpose; three
--                         students engineered to trip the at-risk flags
--  10) Gradebook        - one booking per student per assessment with a
--                         score, submission time and some feedback; one
--                         essay left half-graded, one project still open
--  11) Tutoring         - paid one-to-one sessions (fee income)
--  12) Inventory        - stationery with a supplier and a purchase
--
-- Everything is DEMO DATA. Emails use the reserved example-demo.test domain;
-- logins created here have the password  Passw0rd!  (the admin keeps
-- Demo@12345 if seed-demo-data.ps1 created it).
--
-- Times are Sri Lanka time (Asia/Colombo), stored as timestamptz. "Today"
-- is today in Colombo. Idempotent: reference rows are guarded per row; the
-- dated activity (tuition, timetable, registers, gradebook, tutoring) is
-- guarded per tenant - written once and skipped on later runs, because it
-- is relative to "today". Delete the tenant's bookings and subscriptions
-- to regenerate it. One transaction.
--
--   psql "$DATABASE_URL" -f scripts/seed-brightminds-sample-records.sql
-- ============================================================================

BEGIN;

-- ── 0) Context ──────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS _seed_ctx;
DROP TABLE IF EXISTS _seed_branch;
DROP TABLE IF EXISTS _seed_res;
DROP TABLE IF EXISTS _seed_bt;
DROP TABLE IF EXISTS _seed_stu;
DROP TABLE IF EXISTS _seed_sessions;
DROP TABLE IF EXISTS _seed_register;
DROP TABLE IF EXISTS _seed_assess;

CREATE TEMP TABLE _seed_ctx AS
SELECT t."Id" AS tenant_id,
       (SELECT u."Id" FROM "Users" u WHERE u."TenantId" = t."Id" AND u."Role" = 0 ORDER BY u."CreatedAt" LIMIT 1) AS admin_user_id
FROM "Tenants" t
WHERE t."Name" = 'BrightMinds Tuition Center' AND lower(t."BusinessType") IN ('school','tuition','education','academy');

DO $$
DECLARE n integer; t_id uuid; u_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'Subscriptions') THEN
    RAISE EXCEPTION 'Table "Subscriptions" is missing - start the API once so migration AddGymMembershipsAndDemographics runs, then re-run.';
  END IF;
  SELECT count(*) INTO n FROM _seed_ctx;
  IF n > 1 THEN RAISE EXCEPTION '% tenants are named "BrightMinds Tuition Center" - pin one by Id in the _seed_ctx query.', n; END IF;
  IF n = 0 THEN
    t_id := gen_random_uuid(); u_id := gen_random_uuid();
    INSERT INTO "Tenants" ("Id","CreatedAt","UpdatedAt","Name","BusinessType","SubType","IsActive","CancellationCutoffHours","RescheduleCutoffHours","ReviewCount")
    VALUES (t_id, now(), now(), 'BrightMinds Tuition Center', 'School', NULL, true, 1, 2, 0);
    INSERT INTO "Users" ("Id","CreatedAt","UpdatedAt","TenantId","Email","PasswordHash","FullName","Phone","Role","IsActive","IsApproved")
    VALUES (u_id, now(), now(), t_id, 'admin@brightminds.lk', '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq', 'Sujeewa Gunawardena', '+94774567890', 0, true, true);
    INSERT INTO _seed_ctx (tenant_id, admin_user_id) VALUES (t_id, u_id);
  END IF;
  IF (SELECT admin_user_id FROM _seed_ctx) IS NULL THEN RAISE EXCEPTION 'Tenant has no Admin user.'; END IF;
END $$;

INSERT INTO "Branches" ("Id","CreatedAt","UpdatedAt","TenantId","Name","Address","Phone","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, 'Kadawatha', '23 Kandy Road, Kadawatha', '+94112654321', true
FROM _seed_ctx ctx WHERE NOT EXISTS (SELECT 1 FROM "Branches" b WHERE b."TenantId" = ctx.tenant_id);

CREATE TEMP TABLE _seed_branch AS
SELECT b."Id" AS branch_id FROM "Branches" b JOIN _seed_ctx ctx ON b."TenantId" = ctx.tenant_id ORDER BY b."CreatedAt" LIMIT 1;

UPDATE "Users" u SET "BranchId" = br.branch_id FROM _seed_ctx ctx, _seed_branch br WHERE u."TenantId" = ctx.tenant_id AND u."BranchId" IS NULL;

CREATE OR REPLACE FUNCTION pg_temp.lk(day_offset int, t time) RETURNS timestamptz
LANGUAGE sql STABLE AS $$
  SELECT (((now() AT TIME ZONE 'Asia/Colombo')::date + day_offset) + t) AT TIME ZONE 'Asia/Colombo';
$$;
CREATE OR REPLACE FUNCTION pg_temp.dow(day_offset int) RETURNS int
LANGUAGE sql STABLE AS $$
  SELECT extract(dow FROM ((now() AT TIME ZONE 'Asia/Colombo')::date + day_offset))::int;
$$;
CREATE OR REPLACE FUNCTION pg_temp.ymd(day_offset int) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT to_char((now() AT TIME ZONE 'Asia/Colombo')::date + day_offset, 'YYYY-MM-DD');
$$;

-- ── 1) Module config ────────────────────────────────────────────────────────
INSERT INTO "TenantModules" ("Id","CreatedAt","UpdatedAt","TenantId","ModuleName","IsEnabled","ConfigJson")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, v.module, true, '{}'
FROM _seed_ctx ctx, (VALUES ('Scheduling'), ('Attendance')) AS v(module)
WHERE NOT EXISTS (SELECT 1 FROM "TenantModules" m WHERE m."TenantId" = ctx.tenant_id AND m."ModuleName" = v.module);

UPDATE "TenantModules" m SET
  "ConfigJson" = ((CASE WHEN m."ConfigJson" ~ '^\s*\{' THEN m."ConfigJson"::jsonb ELSE '{}'::jsonb END) || jsonb_build_object(
      'terms', jsonb_build_array(
        jsonb_build_object('name','Term 1','from', to_char(now() AT TIME ZONE 'Asia/Colombo','YYYY') || '-01-06','to', to_char(now() AT TIME ZONE 'Asia/Colombo','YYYY') || '-04-10'),
        jsonb_build_object('name','Term 2','from', to_char(now() AT TIME ZONE 'Asia/Colombo','YYYY') || '-04-28','to', to_char(now() AT TIME ZONE 'Asia/Colombo','YYYY') || '-08-08'),
        jsonb_build_object('name','Term 3','from', to_char(now() AT TIME ZONE 'Asia/Colombo','YYYY') || '-08-25','to', to_char(now() AT TIME ZONE 'Asia/Colombo','YYYY') || '-12-05')),
      'holidays', jsonb_build_array(
        jsonb_build_object('date', pg_temp.ymd(1),  'name', 'Poya day'),
        jsonb_build_object('date', pg_temp.ymd(12), 'name', 'Staff training day'),
        jsonb_build_object('date', pg_temp.ymd(33), 'name', 'Deepavali'),
        jsonb_build_object('date', to_char(now() AT TIME ZONE 'Asia/Colombo','YYYY') || '-12-25', 'name', 'Christmas Day'))))::text,
  "UpdatedAt" = now()
FROM _seed_ctx ctx WHERE m."TenantId" = ctx.tenant_id AND m."ModuleName" = 'Scheduling';

UPDATE "TenantModules" m SET
  "ConfigJson" = ((CASE WHEN m."ConfigJson" ~ '^\s*\{' THEN m."ConfigJson"::jsonb ELSE '{}'::jsonb END) || jsonb_build_object(
      'atRiskAttendancePercent', 75, 'atRiskGradePercent', 50, 'lateAfterMinutes', 10,
      'gradeScale', jsonb_build_array(jsonb_build_object('grade','A','min',75), jsonb_build_object('grade','B','min',65),
                                      jsonb_build_object('grade','C','min',55), jsonb_build_object('grade','S','min',40), jsonb_build_object('grade','F','min',0))))::text,
  "UpdatedAt" = now()
FROM _seed_ctx ctx WHERE m."TenantId" = ctx.tenant_id AND m."ModuleName" = 'Attendance';

-- ── 2) Resources ────────────────────────────────────────────────────────────
UPDATE "resources" r SET "Code" = v.code, "UpdatedAt" = now()
FROM _seed_ctx ctx, (VALUES
  ('Mr. Dilshan Ekanayake%', 'BMT-TR-01'), ('Ms. Harshi Rodrigo%', 'BMT-TR-02'), ('Mr. Chathura Wijesinghe%', 'BMT-TR-03')
) AS v(pattern, code)
WHERE r."TenantId" = ctx.tenant_id AND r."Code" IS NULL AND r."Category" = 'Staff' AND r."Name" LIKE v.pattern
  AND NOT EXISTS (SELECT 1 FROM "resources" x WHERE x."TenantId" = ctx.tenant_id AND x."Code" = v.code);

INSERT INTO "resources" ("Id","TenantId","BranchId","Name","Code","Category","Specialty","Status","Capacity","HourlyRate","Description","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id, v.name, v.code, v.category, v.specialty, 'Available', v.capacity, v.rate, v.description, now(), now()
FROM _seed_ctx ctx, _seed_branch br, (VALUES
  ('Classroom A',                          'BMT-R-01',  'Room',  'Classroom',   20, NULL, 'Main classroom, whiteboard + projector.'),
  ('Classroom B',                          'BMT-R-02',  'Room',  'Classroom',   16, NULL, 'Second classroom.'),
  ('Computer Lab',                         'BMT-R-03',  'Room',  'Lab',         12, NULL, '12 PCs for ICT and science simulations.'),
  ('Mr. Dilshan Ekanayake - Mathematics',  'BMT-TR-01', 'Staff', 'Mathematics', NULL,  550, 'Grade 10 & 11 Mathematics.'),
  ('Ms. Harshi Rodrigo - Science',         'BMT-TR-02', 'Staff', 'Science',     NULL,  500, 'Grade 10 Science.'),
  ('Mr. Chathura Wijesinghe - English',    'BMT-TR-03', 'Staff', 'English',     NULL,  450, 'Grade 10 English.'),
  ('Ms. Sanduni Weerakoon - ICT',          'BMT-TR-04', 'Staff', 'ICT',         NULL,  480, 'Grade 11 ICT.')
) AS v(name, code, category, specialty, capacity, rate, description)
WHERE NOT EXISTS (SELECT 1 FROM "resources" r WHERE r."TenantId" = ctx.tenant_id AND r."Code" = v.code);

-- Hourly rates at a small tuition centre's scale (the demo seed's 2,500/h
-- across a 29-hour roster would put payroll at five times the fee income).
UPDATE "resources" r SET "HourlyRate" = v.rate, "UpdatedAt" = now()
FROM _seed_ctx ctx, (VALUES ('BMT-TR-01', 550), ('BMT-TR-02', 500), ('BMT-TR-03', 450), ('BMT-TR-04', 480)) AS v(code, rate)
WHERE r."TenantId" = ctx.tenant_id AND r."Code" = v.code;

CREATE TEMP TABLE _seed_res AS
SELECT r."Id" AS resource_id, r."Code" AS code FROM "resources" r JOIN _seed_ctx ctx ON r."TenantId" = ctx.tenant_id WHERE r."Code" LIKE 'BMT-%';

-- Rosters: weekdays 14:00-19:00, Saturday 09:00-13:00 (DayOfWeek 0 = Sunday).
INSERT INTO "resource_schedules" ("Id","CreatedAt","UpdatedAt","ResourceId","DayOfWeek","StartTime","EndTime","IsAvailable")
SELECT gen_random_uuid(), now(), now(), r.resource_id, d.dow,
       CASE WHEN d.dow = 6 THEN TIME '09:00' ELSE TIME '14:00' END, CASE WHEN d.dow = 6 THEN TIME '13:00' ELSE TIME '19:00' END, true
FROM _seed_res r CROSS JOIN generate_series(1, 6) AS d(dow)
WHERE NOT EXISTS (SELECT 1 FROM "resource_schedules" s WHERE s."ResourceId" = r.resource_id);

-- ── 3) Subjects & 4) assessments (booking types) ────────────────────────────
-- The demo-seed types get an explicit kind: "Exam Prep" is a lesson, not
-- an exam, whatever its name says.
UPDATE "booking_types" bt SET
  "ConfigJson" = COALESCE(bt."ConfigJson", '{}'::jsonb) || v.config::jsonb, "MaxParticipants" = COALESCE(v.cap, bt."MaxParticipants"), "UpdatedAt" = now()
FROM _seed_ctx ctx, (VALUES
  ('1-on-1-tutoring', '{"kind":"tutoring","subject":"Tutoring","basePrice":{"amount":2500,"currency":"LKR"}}', NULL),
  ('exam-prep',       '{"kind":"lesson","subject":"Exam Prep","grade":"Grade 11"}', 20)
) AS v(slug, config, cap)
WHERE bt."TenantId" = ctx.tenant_id AND bt."Slug" = v.slug;
UPDATE "booking_types" bt SET "ConfigJson" = COALESCE(bt."ConfigJson", '{}'::jsonb) || '{"kind":"lesson"}'::jsonb, "UpdatedAt" = now()
FROM _seed_ctx ctx WHERE bt."TenantId" = ctx.tenant_id AND bt."Slug" LIKE 'group-class%';

INSERT INTO "booking_types" ("Id","TenantId","Name","Slug","Description","ColorHex","Status","DefaultDurationMinutes","RequiresApproval","MaxParticipants","BufferMinutesBefore","BufferMinutesAfter","BookingUnit","ConfigJson","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, v.name, v.slug, v.description, v.color, 'Active', v.minutes, false, v.cap, 0, 0, 'Slot', v.config::jsonb, now(), now()
FROM _seed_ctx ctx, (VALUES
  ('Mathematics - Grade 10',      'bmt-maths10',        'Grade 10 Mathematics, Mon / Wed / Fri.',        '#2563EB',  90, 20, '{"kind":"lesson","subject":"Mathematics","grade":"Grade 10"}'),
  ('Science - Grade 10',          'bmt-science10',      'Grade 10 Science, Mon / Wed / Fri.',            '#059669',  90, 20, '{"kind":"lesson","subject":"Science","grade":"Grade 10"}'),
  ('English - Grade 10',          'bmt-english10',      'Grade 10 English, Tue / Thu.',                  '#7C3AED',  90, 20, '{"kind":"lesson","subject":"English","grade":"Grade 10"}'),
  ('Mathematics - Grade 11',      'bmt-maths11',        'Grade 11 Mathematics, Tue / Thu.',              '#1D4ED8',  90, 20, '{"kind":"lesson","subject":"Mathematics","grade":"Grade 11"}'),
  ('ICT - Grade 11',              'bmt-ict11',          'Grade 11 ICT in the lab, Saturday.',            '#0891B2', 120, 12, '{"kind":"lesson","subject":"ICT","grade":"Grade 11"}'),
  ('Exam Prep - Grade 11',        'bmt-examprep11',     'O/L exam-prep, Saturday.',                      '#B45309', 120, 20, '{"kind":"lesson","subject":"Exam Prep","grade":"Grade 11"}'),
  ('Maths Quiz 1 (G10)',          'bmt-maths10-quiz1',  'Algebra quiz.',                                 '#2563EB',  30, 1,  '{"kind":"exam","subject":"Mathematics","grade":"Grade 10","weight":0.2}'),
  ('Maths Term Test (G10)',       'bmt-maths10-test',   'Term 3 test, paper 1.',                         '#2563EB',  90, 1,  '{"kind":"exam","subject":"Mathematics","grade":"Grade 10","weight":0.5}'),
  ('Science Quiz 1 (G10)',        'bmt-science10-quiz1','Cells and organisms quiz.',                     '#059669',  30, 1,  '{"kind":"exam","subject":"Science","grade":"Grade 10","weight":0.2}'),
  ('Science Lab Report (G10)',    'bmt-science10-lab',  'Lab report: photosynthesis experiment.',        '#059669',  60, 1,  '{"kind":"assignment","subject":"Science","grade":"Grade 10","weight":0.3}'),
  ('English Essay (G10)',         'bmt-english10-essay','Argumentative essay, 500 words.',               '#7C3AED',  60, 1,  '{"kind":"assignment","subject":"English","grade":"Grade 10","weight":0.3}'),
  ('Maths Term Test (G11)',       'bmt-maths11-test',   'Term 3 test.',                                  '#1D4ED8',  90, 1,  '{"kind":"exam","subject":"Mathematics","grade":"Grade 11","weight":0.5}'),
  ('ICT Project (G11)',           'bmt-ict11-project',  'Spreadsheet project.',                          '#0891B2',  60, 1,  '{"kind":"assignment","subject":"ICT","grade":"Grade 11","weight":0.4}')
) AS v(name, slug, description, color, minutes, cap, config)
WHERE NOT EXISTS (SELECT 1 FROM "booking_types" bt WHERE bt."TenantId" = ctx.tenant_id AND bt."Slug" = v.slug);

CREATE TEMP TABLE _seed_bt AS
SELECT bt."Id" AS bt_id, bt."Slug" AS slug, bt."DefaultDurationMinutes" AS minutes, bt."Name" AS name
FROM "booking_types" bt JOIN _seed_ctx ctx ON bt."TenantId" = ctx.tenant_id WHERE bt."Slug" LIKE 'bmt-%' OR bt."Slug" = '1-on-1-tutoring';

-- ── 5) Staff logins ─────────────────────────────────────────────────────────
INSERT INTO "Users" ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","Email","PasswordHash","FullName","Phone","Role","IsActive","IsApproved")
SELECT gen_random_uuid(), now() - interval '300 days', now(), ctx.tenant_id, br.branch_id, v.email,
       '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq', v.full_name, v.phone, v.role, true, v.approved
FROM _seed_ctx ctx, _seed_branch br, (VALUES
  ('principal.brightminds@example-demo.test', 'Nilanthi Jayasundara', '+94770445566', 1, true),
  ('ict.brightminds@example-demo.test',       'Sanduni Weerakoon',    '+94770445577', 2, true),
  ('newteacher.brightminds@example-demo.test','Ravindu Perera',       '+94770445588', 2, false)   -- awaiting staff onboarding approval
) AS v(email, full_name, phone, role, approved)
WHERE NOT EXISTS (SELECT 1 FROM "Users" u WHERE lower(u."Email") = v.email);

-- ── 6) Students ─────────────────────────────────────────────────────────────
-- m 1-14 are Grade 10, m 15-24 Grade 11; m 25-26 are registrations awaiting approval.
INSERT INTO "Users"
  ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","Email","PasswordHash","FullName","Phone","Role","IsActive","IsApproved","Address","DateOfBirth","Gender","MedicalNotes")
SELECT gen_random_uuid(), pg_temp.lk(v.joined_off, '10:00'), now(), ctx.tenant_id, br.branch_id, v.email,
       '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq', v.full_name, v.phone, 3, true, v.approved, v.address, (v.dob::date)::timestamptz, v.gender, v.medical
FROM _seed_ctx ctx, _seed_branch br, (VALUES
  ( 1, 'sahan.perera@example-demo.test',        'Sahan Perera',         '+94771450001', 'Kadawatha',   '2010-03-14', 'Male',   -400, true,  NULL),
  ( 2, 'thisuri.silva@example-demo.test',       'Thisuri Silva',        '+94771450002', 'Kadawatha',   '2010-07-22', 'Female', -380, true,  'Asthma - inhaler in bag; allow rest if breathless.'),
  ( 3, 'kavindu.fernando@example-demo.test',    'Kavindu Fernando',     '+94771450003', 'Ragama',      '2010-11-02', 'Male',   -300, true,  NULL),
  ( 4, 'nethmi.jayawardena@example-demo.test',  'Nethmi Jayawardena',   '+94771450004', 'Kiribathgoda','2011-01-30', 'Female', -250, true,  NULL),
  ( 5, 'dinuka.bandara@example-demo.test',      'Dinuka Bandara',       '+94771450005', 'Kadawatha',   '2010-05-09', 'Male',   -240, true,  NULL),
  ( 6, 'sanduni.gunasekara@example-demo.test',  'Sanduni Gunasekara',   '+94771450006', 'Mahara',      '2010-09-17', 'Female', -220, true,  NULL),
  ( 7, 'ravindu.wijesinghe@example-demo.test',  'Ravindu Wijesinghe',   '+94771450007', 'Kadawatha',   '2010-12-01', 'Male',   -200, true,  NULL),
  ( 8, 'imesha.rathnayake@example-demo.test',   'Imesha Rathnayake',    '+94771450008', 'Ragama',      '2010-04-25', 'Female', -180, true,  'Nut allergy (EpiPen in office). Emergency contact: mother +94771450108.'),
  ( 9, 'lahiru.dissanayake@example-demo.test',  'Lahiru Dissanayake',   '+94771450009', 'Kiribathgoda','2010-08-13', 'Male',   -160, true,  NULL),
  (10, 'hiruni.weerasinghe@example-demo.test',  'Hiruni Weerasinghe',   '+94771450010', 'Kadawatha',   '2010-02-19', 'Female', -140, true,  NULL),
  (11, 'yasas.karunaratne@example-demo.test',   'Yasas Karunaratne',    '+94771450011', 'Gampaha',     '2010-06-06', 'Male',   -120, true,  NULL),
  (12, 'sithmi.fonseka@example-demo.test',      'Sithmi Fonseka',       '+94771450012', 'Kadawatha',   '2010-10-28', 'Female', -100, true,  NULL),
  (13, 'pasindu.senanayake@example-demo.test',  'Pasindu Senanayake',   '+94771450013', 'Mahara',      '2010-03-03', 'Male',    -80, true,  'Dyslexia - accommodation: 25% extra time on tests, printed notes.'),
  (14, 'oshadi.abeysekara@example-demo.test',   'Oshadi Abeysekara',    '+94771450014', 'Kadawatha',   '2010-11-11', 'Female',  -20, true,  NULL),
  (15, 'chamod.herath@example-demo.test',       'Chamod Herath',        '+94771450015', 'Ragama',      '2009-07-07', 'Male',   -420, true,  NULL),
  (16, 'senuri.ranasinghe@example-demo.test',   'Senuri Ranasinghe',    '+94771450016', 'Kadawatha',   '2009-12-24', 'Female', -400, true,  NULL),
  (17, 'tharusha.mendis@example-demo.test',     'Tharusha Mendis',      '+94771450017', 'Kiribathgoda','2009-01-15', 'Male',   -380, true,  NULL),
  (18, 'dilmi.peiris@example-demo.test',        'Dilmi Peiris',         '+94771450018', 'Kadawatha',   '2009-09-09', 'Female', -360, true,  NULL),
  (19, 'sasmitha.wickrama@example-demo.test',   'Sasmitha Wickramasinghe','+94771450019','Gampaha',    '2009-05-20', 'Male',   -340, true,  NULL),
  (20, 'ridmi.jayasuriya@example-demo.test',    'Ridmi Jayasuriya',     '+94771450020', 'Kadawatha',   '2009-08-08', 'Female', -320, true,  NULL),
  (21, 'nimesh.desilva@example-demo.test',      'Nimesh De Silva',      '+94771450021', 'Mahara',      '2009-04-04', 'Male',   -300, true,  NULL),
  (22, 'anjana.cooray@example-demo.test',       'Anjana Cooray',        '+94771450022', 'Kadawatha',   '2009-02-02', 'Female', -280, true,  NULL),
  (23, 'malsha.samaraweera@example-demo.test',  'Malsha Samaraweera',   '+94771450023', 'Ragama',      '2009-10-10', 'Female', -260, true,  NULL),
  (24, 'vihanga.rajapaksa@example-demo.test',   'Vihanga Rajapaksa',    '+94771450024', 'Kadawatha',   '2009-06-30', 'Male',   -240, true,  NULL),
  (25, 'binuri.alwis@example-demo.test',        'Binuri Alwis',         '+94771450025', 'Kadawatha',   '2010-09-01', 'Female',   -2, false, NULL),
  (26, 'sehan.liyanage@example-demo.test',      'Sehan Liyanage',       '+94771450026', 'Kiribathgoda','2009-11-19', 'Male',     -1, false, NULL)
) AS v(m, email, full_name, phone, address, dob, gender, joined_off, approved, medical)
WHERE NOT EXISTS (SELECT 1 FROM "Users" u WHERE lower(u."Email") = v.email);

CREATE TEMP TABLE _seed_stu AS
SELECT v.m, u."Id" AS user_id, u."FullName" AS name, CASE WHEN v.m <= 14 THEN 'Grade 10' ELSE 'Grade 11' END AS grade
FROM (VALUES
  (1,'sahan.perera'),(2,'thisuri.silva'),(3,'kavindu.fernando'),(4,'nethmi.jayawardena'),(5,'dinuka.bandara'),(6,'sanduni.gunasekara'),
  (7,'ravindu.wijesinghe'),(8,'imesha.rathnayake'),(9,'lahiru.dissanayake'),(10,'hiruni.weerasinghe'),(11,'yasas.karunaratne'),(12,'sithmi.fonseka'),
  (13,'pasindu.senanayake'),(14,'oshadi.abeysekara'),(15,'chamod.herath'),(16,'senuri.ranasinghe'),(17,'tharusha.mendis'),(18,'dilmi.peiris'),
  (19,'sasmitha.wickrama'),(20,'ridmi.jayasuriya'),(21,'nimesh.desilva'),(22,'anjana.cooray'),(23,'malsha.samaraweera'),(24,'vihanga.rajapaksa')
) AS v(m, local)
JOIN "Users" u ON lower(u."Email") = v.local || '@example-demo.test'
JOIN _seed_ctx ctx ON u."TenantId" = ctx.tenant_id;

-- ── 7) Tuition (run-once) ───────────────────────────────────────────────────
INSERT INTO "Subscriptions"
  ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","CustomerId","PlanName","Amount","BillingCycle","StartDate","EndDate","AutoRenew","Status","PaymentStatus","LastPaymentAt","NextBillingAt","Notes")
SELECT gen_random_uuid(), pg_temp.lk(v.start_off, '10:00'), now(), ctx.tenant_id, br.branch_id, s.user_id,
       CASE WHEN s.m <= 14 THEN 'Grade 10 - Full package' ELSE 'Grade 11 - Full package' END,
       CASE WHEN s.m <= 14 THEN 15000 ELSE 16500 END, 'Monthly',
       pg_temp.lk(v.start_off, '00:00'), pg_temp.lk(v.end_off, '23:59'), v.auto, v.status, v.pay,
       CASE WHEN v.last_pay_off IS NOT NULL THEN pg_temp.lk(v.last_pay_off, '10:00') END,
       CASE WHEN v.next_bill_off IS NOT NULL THEN pg_temp.lk(v.next_bill_off, '06:00') END, v.notes
FROM _seed_ctx ctx, _seed_branch br, (VALUES
  -- m, start, end, status, pay, auto, last_pay, next_bill, notes  (current month for everyone except the two lapsed)
  ( 1, -10, 20, 'Active', 'Paid',    true,  -10, 20, NULL), ( 2, -10, 20, 'Active', 'Paid',    true,  -10, 20, NULL),
  ( 3, -10, 20, 'Active', 'Pending', false, -40, -3, 'Parent asked for a week.'), ( 4, -10, 20, 'Active', 'Paid', true, -10, 20, NULL),
  ( 5, -10, 20, 'Active', 'Paid',    true,  -10, 20, NULL), ( 6, -10, 20, 'Active', 'Paid',    true,  -10, 20, NULL),
  ( 7, -10, 20, 'Active', 'Overdue', false, -41, -10, 'Two reminders sent.'), ( 8, -10, 20, 'Active', 'Paid', true, -10, 20, NULL),
  ( 9, -10, 20, 'Active', 'Paid',    true,  -10, 20, NULL), (10, -10, 20, 'Active', 'Paid',    true,  -10, 20, NULL),
  (11, -10, 20, 'Active', 'Failed',  true,  -40, -9, 'Card declined on the billing run.'), (12, -10, 20, 'Active', 'Paid', true, -10, 20, NULL),
  (13, -10, 20, 'Active', 'Paid',    true,  -10, 20, NULL), (14, -10, 20, 'Active', 'Paid',    true,  -10, 20, 'Joined this month.'),
  (15, -10, 20, 'Active', 'Paid',    true,  -10, 20, NULL), (16, -10, 20, 'Active', 'Paid',    true,  -10, 20, NULL),
  (17, -10, 20, 'Active', 'Paid',    true,  -10, 20, NULL), (18, -10, 20, 'Active', 'Pending', false, -40, -2, NULL),
  (19, -10, 20, 'Active', 'Paid',    true,  -10, 20, NULL), (20, -10, 20, 'Active', 'Paid',    true,  -10, 20, NULL),
  (21, -10, 20, 'Active', 'Paid',    true,  -10, 20, NULL), (22, -10, 20, 'Active', 'Paid',    true,  -10, 20, NULL),
  (23, -40, -10, 'Expired', 'Paid',  false, -40, NULL, 'Lapsed - still attending; chase.'), (24, -70, -40, 'Expired', 'Paid', false, -70, NULL, 'Left in August.'),
  -- earlier months (year-to-date income) for the long-standing students
  ( 1, -40, -11, 'Expired', 'Paid', true, -40, NULL, NULL), ( 1, -70, -41, 'Expired', 'Paid', true, -70, NULL, NULL),
  ( 2, -40, -11, 'Expired', 'Paid', true, -40, NULL, NULL), ( 3, -40, -11, 'Expired', 'Paid', true, -40, NULL, NULL),
  ( 5, -40, -11, 'Expired', 'Paid', true, -40, NULL, NULL), ( 6, -40, -11, 'Expired', 'Paid', true, -40, NULL, NULL),
  ( 9, -40, -11, 'Expired', 'Paid', true, -40, NULL, NULL), (10, -40, -11, 'Expired', 'Paid', true, -40, NULL, NULL),
  (15, -40, -11, 'Expired', 'Paid', true, -40, NULL, NULL), (16, -40, -11, 'Expired', 'Paid', true, -40, NULL, NULL),
  (17, -40, -11, 'Expired', 'Paid', true, -40, NULL, NULL), (19, -40, -11, 'Expired', 'Paid', true, -40, NULL, NULL),
  (20, -40, -11, 'Expired', 'Paid', true, -40, NULL, NULL), (21, -40, -11, 'Expired', 'Paid', true, -40, NULL, NULL)
) AS v(m, start_off, end_off, status, pay, auto, last_pay_off, next_bill_off, notes)
JOIN _seed_stu s ON s.m = v.m
WHERE NOT EXISTS (SELECT 1 FROM "Subscriptions" x WHERE x."TenantId" = ctx.tenant_id);

UPDATE "Subscriptions" x SET "Amount" = CASE WHEN x."PlanName" LIKE 'Grade 10%' THEN 15000 ELSE 16500 END, "UpdatedAt" = now()
FROM _seed_ctx ctx WHERE x."TenantId" = ctx.tenant_id AND x."PlanName" LIKE 'Grade 1_ - Full package' AND x."Amount" IN (12000, 14000);

-- ── 8) Timetable ────────────────────────────────────────────────────────────
-- One row per session: subject, teacher, room, start, length, weekdays, grade.
CREATE TEMP TABLE _seed_sessions AS
SELECT c.slug, c.teacher, c.room, c.start_t, c.minutes, c.grade, d.day
FROM (VALUES
  ('bmt-maths10',    'BMT-TR-01', 'BMT-R-01', TIME '14:00',  90, 'Grade 10', ARRAY[1,3,5]),
  ('bmt-science10',  'BMT-TR-02', 'BMT-R-03', TIME '15:30',  90, 'Grade 10', ARRAY[1,3,5]),
  ('bmt-english10',  'BMT-TR-03', 'BMT-R-02', TIME '14:00',  90, 'Grade 10', ARRAY[2,4]),
  ('bmt-maths11',    'BMT-TR-01', 'BMT-R-01', TIME '15:30',  90, 'Grade 11', ARRAY[2,4]),
  ('bmt-ict11',      'BMT-TR-04', 'BMT-R-03', TIME '09:00', 120, 'Grade 11', ARRAY[6]),
  ('bmt-examprep11', 'BMT-TR-01', 'BMT-R-01', TIME '11:00', 120, 'Grade 11', ARRAY[6])
) AS c(slug, teacher, room, start_t, minutes, grade, dows)
CROSS JOIN generate_series(-27, 5) AS d(day)
WHERE pg_temp.dow(d.day) = ANY (c.dows);

-- 8a) Room holds: the classroom's booking for each session, by the admin.
INSERT INTO "bookings"
  ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","Source","TotalCost","ReminderSent","CreatedBy","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, ctx.admin_user_id,
       'Room hold - ' || bt.name, NULL, pg_temp.lk(s.day, s.start_t), pg_temp.lk(s.day, s.start_t) + (s.minutes || ' minutes')::interval,
       CASE WHEN pg_temp.lk(s.day, s.start_t) + (s.minutes || ' minutes')::interval <= now() THEN 'Completed' ELSE 'Confirmed' END,
       'Normal', 1, 'Timetable', NULL, true, ctx.admin_user_id, LEAST(pg_temp.lk(s.day, s.start_t) - interval '14 days', now()), now(), 1
FROM _seed_sessions s
JOIN _seed_ctx ctx ON true
JOIN _seed_res r ON r.code = s.room
JOIN _seed_bt bt ON bt.slug = s.slug
-- Run-once per tenant (see header).
WHERE NOT EXISTS (SELECT 1 FROM "bookings" b WHERE b."TenantId" = ctx.tenant_id AND b."Title" LIKE 'Room hold - %');

-- A deliberate clash next week: the exam-prep class also holds Classroom A
-- at 14:30 on the next Wednesday, over the Grade 10 Maths lesson.
INSERT INTO "bookings"
  ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","Source","TotalCost","ReminderSent","CreatedBy","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, ctx.admin_user_id,
       'Room hold - Exam Prep (moved session)', 'Moved from Saturday - clashes with Grade 10 Maths in Classroom A.',
       pg_temp.lk(d.day, '14:30'), pg_temp.lk(d.day, '16:00'), 'Confirmed', 'Normal', 1, 'Timetable', NULL, true, ctx.admin_user_id, now(), now(), 1
FROM _seed_ctx ctx
JOIN _seed_res r ON r.code = 'BMT-R-01'
JOIN _seed_bt bt ON bt.slug = 'bmt-examprep11'
JOIN (SELECT d.day FROM generate_series(1, 7) AS d(day) WHERE pg_temp.dow(d.day) = 3 LIMIT 1) d ON true
WHERE NOT EXISTS (SELECT 1 FROM "bookings" b WHERE b."TenantId" = ctx.tenant_id AND b."Title" = 'Room hold - Exam Prep (moved session)');

-- 8b/9) Registers: one booking per student per session on the teacher,
-- with a deterministic mark for sessions already held. Today's finished
-- sessions are left unmarked so the "registers to mark" flow has work.
--   m = 7  : absent every other lesson (attendance at-risk)
--   m = 20 : an incident most weeks (behaviour at-risk)
CREATE TEMP TABLE _seed_register AS
SELECT s.slug, s.teacher, s.start_t, s.minutes, s.day, st.m, st.user_id, st.name,
       CASE
         WHEN s.day = 0 THEN NULL
         WHEN pg_temp.lk(s.day, s.start_t) > now() THEN NULL
         WHEN st.m = 7 AND abs(s.day) % 2 = 0 THEN 'absent'
         WHEN (st.m * 7 + abs(s.day) * 3) % 20 = 0 THEN 'absent'
         WHEN (st.m * 7 + abs(s.day) * 3) % 20 = 1 THEN 'excused'
         WHEN (st.m * 7 + abs(s.day) * 3) % 20 IN (2, 3) THEN 'late'
         ELSE 'present'
       END AS mark,
       CASE WHEN st.m = 20 AND abs(s.day) % 5 = 1 THEN -1
            WHEN (st.m + abs(s.day)) % 17 = 0 THEN 1
            WHEN (st.m * 5 + abs(s.day)) % 29 = 0 THEN -1
            ELSE 0 END AS points
FROM _seed_sessions s
JOIN _seed_stu st ON st.grade = s.grade;

INSERT INTO "bookings"
  ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","Source",
   "CheckInAt","CheckOutAt","CancellationReason","FormData","TotalCost","ReminderSent","CreatedBy","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, g.user_id,
       bt.name || ' - ' || g.name, NULL,
       pg_temp.lk(g.day, g.start_t), pg_temp.lk(g.day, g.start_t) + (g.minutes || ' minutes')::interval,
       CASE g.mark WHEN 'absent' THEN 'NoShow' WHEN 'excused' THEN 'Cancelled'
            WHEN 'present' THEN 'Completed' WHEN 'late' THEN 'Completed'
            ELSE CASE WHEN pg_temp.lk(g.day, g.start_t) <= now() AND pg_temp.lk(g.day, g.start_t) + (g.minutes || ' minutes')::interval > now() THEN 'CheckedIn' ELSE 'Confirmed' END END,
       'Normal', 1, 'Timetable',
       CASE g.mark WHEN 'present' THEN pg_temp.lk(g.day, g.start_t) - interval '3 minutes' WHEN 'late' THEN pg_temp.lk(g.day, g.start_t) + interval '14 minutes' END,
       CASE WHEN g.mark IN ('present','late') THEN pg_temp.lk(g.day, g.start_t) + (g.minutes || ' minutes')::interval END,
       CASE WHEN g.mark = 'excused' THEN 'Excused absence - note from parent' END,
       CASE WHEN g.mark IS NULL THEN NULL ELSE jsonb_build_object(
         'attendance', g.mark, 'points', g.points,
         'note', CASE WHEN g.points > 0 THEN 'Led the group work' WHEN g.points < 0 AND g.m = 20 THEN 'Phone out in class' WHEN g.points < 0 THEN 'Homework not done' ELSE NULL END,
         'markedAt', pg_temp.lk(g.day, g.start_t) + interval '20 minutes') END,
       NULL, true, NULL, LEAST(pg_temp.lk(g.day, g.start_t) - interval '14 days', now()), now(), 1
FROM _seed_register g
JOIN _seed_ctx ctx ON true
JOIN _seed_res r ON r.code = g.teacher
JOIN _seed_bt bt ON bt.slug = g.slug
-- Run-once per tenant (see header).
WHERE NOT EXISTS (SELECT 1 FROM "bookings" b JOIN _seed_bt x ON x.bt_id = b."BookingTypeId" JOIN _seed_stu y ON y.user_id = b."BookedBy" WHERE b."TenantId" = ctx.tenant_id);

-- ── 10) Gradebook ───────────────────────────────────────────────────────────
-- One row per student per assessment. Ability is per student (m = 13 low
-- for the grade at-risk flag); the score is ability +/- a small offset.
CREATE TEMP TABLE _seed_assess AS
SELECT a.slug, a.teacher, a.day, a.start_t, a.due_off, a.max_score, a.grade, a.graded_upto, a.submitted_upto, st.m, st.user_id, st.name,
       LEAST(a.max_score, GREATEST(0,
         round((CASE WHEN st.m = 13 THEN 36 ELSE 48 + ((st.m * 37) % 46) END + (((st.m + a.k * 7) % 15) - 7)) * a.max_score / 100.0)
       )) AS score
FROM (VALUES
  -- slug, teacher, day, start, due_off (days after set), max, grade, k, graded_upto (m), submitted_upto (m)
  ('bmt-maths10-quiz1',   'BMT-TR-01', -20, TIME '14:00',  0, 20,  'Grade 10', 1, 14, 14),
  ('bmt-science10-quiz1', 'BMT-TR-02', -17, TIME '15:30',  0, 20,  'Grade 10', 2, 14, 14),
  ('bmt-science10-lab',   'BMT-TR-02', -15, TIME '15:30',  7, 50,  'Grade 10', 3, 14, 14),
  ('bmt-maths11-test',    'BMT-TR-01', -12, TIME '15:30',  0, 100, 'Grade 11', 4, 24, 24),
  ('bmt-english10-essay', 'BMT-TR-03',  -9, TIME '14:00',  7, 100, 'Grade 10', 5,  6, 11),
  ('bmt-maths10-test',    'BMT-TR-01',  -6, TIME '14:00',  0, 100, 'Grade 10', 6, 14, 14),
  ('bmt-ict11-project',   'BMT-TR-04', -10, TIME '09:00', 14, 100, 'Grade 11', 7,  0, 18)
) AS a(slug, teacher, day, start_t, due_off, max_score, grade, k, graded_upto, submitted_upto)
JOIN _seed_stu st ON st.grade = a.grade;

INSERT INTO "bookings"
  ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","Source",
   "CheckInAt","CheckOutAt","FormData","TotalCost","ReminderSent","CreatedBy","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, g.user_id,
       bt.name || ' - ' || g.name, NULL,
       pg_temp.lk(g.day, g.start_t), pg_temp.lk(g.day + g.due_off, g.start_t) + (bt.minutes || ' minutes')::interval,
       CASE WHEN g.m <= g.graded_upto THEN 'Completed' ELSE 'Confirmed' END, 'Normal', 1, 'Gradebook',
       CASE WHEN g.m <= g.submitted_upto THEN pg_temp.lk(g.day + g.due_off, g.start_t) - ((g.m % 5) || ' hours')::interval END,
       CASE WHEN g.m <= g.graded_upto THEN pg_temp.lk(g.day + g.due_off, g.start_t) + interval '1 day' END,
       jsonb_strip_nulls(jsonb_build_object(
         'maxScore', g.max_score,
         'dueAt', to_char((pg_temp.lk(g.day + g.due_off, g.start_t) + (bt.minutes || ' minutes')::interval) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
         'submittedAt', CASE WHEN g.m <= g.submitted_upto THEN to_char((pg_temp.lk(g.day + g.due_off, g.start_t) - ((g.m % 5) || ' hours')::interval) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') END,
         'score', CASE WHEN g.m <= g.graded_upto THEN g.score END,
         'gradedAt', CASE WHEN g.m <= g.graded_upto THEN to_char((pg_temp.lk(g.day + g.due_off, g.start_t) + interval '1 day') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') END,
         'feedback', CASE WHEN g.m <= g.graded_upto AND g.score < g.max_score * 0.5 THEN 'Below the pass line - book a tutoring slot before the next test.'
                          WHEN g.m <= g.graded_upto AND g.score >= g.max_score * 0.85 THEN 'Excellent - clear working throughout.'
                          WHEN g.m <= g.graded_upto AND g.m % 3 = 0 THEN 'Show your working on the longer questions.' END)),
       NULL, true, NULL, LEAST(pg_temp.lk(g.day, g.start_t) - interval '7 days', now()), now(), 1
FROM _seed_assess g
JOIN _seed_ctx ctx ON true
JOIN _seed_res r ON r.code = g.teacher
JOIN _seed_bt bt ON bt.slug = g.slug
-- Run-once per tenant (see header).
WHERE NOT EXISTS (SELECT 1 FROM "bookings" b JOIN _seed_bt x ON x.bt_id = b."BookingTypeId" WHERE b."TenantId" = ctx.tenant_id AND x.slug LIKE 'bmt-%-%' AND x.slug NOT IN ('bmt-maths10','bmt-science10','bmt-english10','bmt-maths11','bmt-ict11','bmt-examprep11'));

-- ── 11) Tutoring (paid one-to-one) ──────────────────────────────────────────
INSERT INTO "bookings"
  ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","Source",
   "CheckInAt","CheckOutAt","FormData","TotalCost","ReminderSent","CreatedBy","CreatedAt","UpdatedAt","Version")
SELECT gen_random_uuid(), ctx.tenant_id, r.resource_id, bt.bt_id, st.user_id,
       'Tutoring - ' || st.name, v.notes, pg_temp.lk(v.day, v.start_t), pg_temp.lk(v.day, v.start_t) + interval '60 minutes',
       CASE WHEN pg_temp.lk(v.day, v.start_t) + interval '60 minutes' <= now() THEN 'Completed' ELSE 'Confirmed' END, 'Normal', 1, 'Phone',
       CASE WHEN pg_temp.lk(v.day, v.start_t) <= now() THEN pg_temp.lk(v.day, v.start_t) END,
       CASE WHEN pg_temp.lk(v.day, v.start_t) + interval '60 minutes' <= now() THEN pg_temp.lk(v.day, v.start_t) + interval '60 minutes' END,
       CASE WHEN pg_temp.lk(v.day, v.start_t) <= now() THEN '{"attendance":"present","points":0}'::jsonb END,
       2500, true, ctx.admin_user_id, LEAST(pg_temp.lk(v.day, v.start_t) - interval '3 days', now()), now(), 1
FROM (VALUES
  (13, -24, TIME '17:15', 'BMT-TR-01', 'Algebra catch-up'), (13, -17, TIME '17:15', 'BMT-TR-01', 'Algebra catch-up 2'),
  ( 7, -19, TIME '17:15', 'BMT-TR-02', 'Missed lessons - cells'), (13, -10, TIME '17:15', 'BMT-TR-01', 'Pre-test revision'),
  (22,  -8, TIME '17:15', 'BMT-TR-01', 'Trigonometry'), (13,  -3, TIME '17:15', 'BMT-TR-01', 'Test corrections'),
  ( 3,   0, TIME '17:15', 'BMT-TR-03', 'Essay structure'), (13,   3, TIME '17:15', 'BMT-TR-01', 'Weekly slot')
) AS v(m, day, start_t, teacher, notes)
JOIN _seed_stu st ON st.m = v.m
JOIN _seed_ctx ctx ON true
JOIN _seed_res r ON r.code = v.teacher
JOIN _seed_bt bt ON bt.slug = '1-on-1-tutoring'
-- Run-once per tenant (see header).
WHERE NOT EXISTS (SELECT 1 FROM "bookings" b WHERE b."TenantId" = ctx.tenant_id AND b."Title" LIKE 'Tutoring - %');

-- ── 12) Inventory ───────────────────────────────────────────────────────────
INSERT INTO "InventoryCategories" ("Id","CreatedAt","UpdatedAt","TenantId","Name","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, v.name, true
FROM _seed_ctx ctx, (VALUES ('Stationery'),('Printing'),('Lab'),('Cleaning Supplies')) AS v(name)
WHERE NOT EXISTS (SELECT 1 FROM "InventoryCategories" c WHERE c."TenantId" = ctx.tenant_id AND c."Name" = v.name);
INSERT INTO "InventoryUnits" ("Id","CreatedAt","UpdatedAt","TenantId","Code","Name","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, v.code, v.name, true
FROM _seed_ctx ctx, (VALUES ('each','Each'),('box','Box'),('pack','Pack')) AS v(code, name)
WHERE NOT EXISTS (SELECT 1 FROM "InventoryUnits" u WHERE u."TenantId" = ctx.tenant_id AND u."Code" = v.code);
INSERT INTO "Suppliers" ("Id","CreatedAt","UpdatedAt","TenantId","Name","Email","Phone","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id, v.name, v.email, v.phone, true
FROM _seed_ctx ctx, (VALUES ('Atlas Stationers Kadawatha', 'orders@atlas.example-demo.test', '+94112667788'), ('PrintRight Solutions', 'sales@printright.example-demo.test', '+94112998877')) AS v(name, email, phone)
WHERE NOT EXISTS (SELECT 1 FROM "Suppliers" x WHERE x."TenantId" = ctx.tenant_id AND x."Name" = v.name);
INSERT INTO "InventoryItems" ("Id","TenantId","BranchId","CategoryId","UnitId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id,
       (SELECT c."Id" FROM "InventoryCategories" c WHERE c."TenantId" = ctx.tenant_id AND c."Name" = v.category LIMIT 1),
       (SELECT u."Id" FROM "InventoryUnits" u WHERE u."TenantId" = ctx.tenant_id AND u."Code" = v.unit LIMIT 1),
       v.name, v.sku, v.description, v.qty, v.reorder, v.cost, true, now() - interval '200 days', now()
FROM _seed_ctx ctx, _seed_branch br, (VALUES
  ('A4 Paper Ream 80gsm',            'BMT-STAT-001', 'Stationery', 'each', 'Handouts and test papers',      14, 10,  680.00),
  ('Whiteboard Markers (x12)',       'BMT-STAT-002', 'Stationery', 'box',  'Assorted colours',                3,  6,  480.00),
  ('Exercise Books (x50)',           'BMT-STAT-003', 'Stationery', 'pack', 'Ruled, for sale to students',    12,  8, 3500.00),
  ('Printer Toner (HP 85A)',         'BMT-PRNT-001', 'Printing',   'each', 'Office printer',                  1,  2, 9800.00),
  ('Lab Safety Goggles (x10)',       'BMT-LAB-001',  'Lab',        'pack', 'Science practicals',              2,  2, 4200.00),
  ('Whiteboard Cleaner 500ml',       'BMT-CLEAN-001','Cleaning Supplies','each','Classrooms',                 5,  3,  520.00)
) AS v(name, sku, category, unit, description, qty, reorder, cost)
WHERE NOT EXISTS (SELECT 1 FROM "InventoryItems" i WHERE i."TenantId" = ctx.tenant_id AND i."Sku" = v.sku);
INSERT INTO "StockMovements" ("Id","TenantId","InventoryItemId","BranchId","SupplierId","MovementType","Quantity","UnitCost","Reference","Notes","OccurredAt","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, i."Id", i."BranchId",
       (SELECT s."Id" FROM "Suppliers" s WHERE s."TenantId" = ctx.tenant_id AND s."Name" = v.supplier LIMIT 1),
       v.movement, v.qty, v.cost, v.reference, v.notes, pg_temp.lk(v.day, '10:00'), now(), now()
FROM (VALUES
  ('BMT-STAT-001', 'Receive', 20, 680.00, 'Atlas Stationers Kadawatha', 'PO-BMT-2026-011', 'Term 3 paper order', -14),
  ('BMT-STAT-003', 'Receive', 10, 3500.00,'Atlas Stationers Kadawatha', 'PO-BMT-2026-011', 'Term 3 paper order', -14),
  ('BMT-PRNT-001', 'Receive',  2, 9800.00,'PrintRight Solutions',        'PO-BMT-2026-012', 'Toner',              -9),
  ('BMT-STAT-001', 'Adjustment', -12, NULL, NULL,                        'ADJ-BMT-0004',    'Term test papers printed', -6)
) AS v(sku, movement, qty, cost, supplier, reference, notes, day)
JOIN _seed_ctx ctx ON true
JOIN "InventoryItems" i ON i."TenantId" = ctx.tenant_id AND i."Sku" = v.sku
WHERE NOT EXISTS (SELECT 1 FROM "StockMovements" m WHERE m."InventoryItemId" = i."Id" AND m."Reference" = v.reference);

DO $$
BEGIN
  IF (SELECT count(*) FROM _seed_stu) < 24 THEN RAISE EXCEPTION 'Only % of 24 students resolved.', (SELECT count(*) FROM _seed_stu); END IF;
  IF (SELECT count(*) FROM _seed_res) < 7 OR (SELECT count(*) FROM _seed_bt) < 14 THEN
    RAISE EXCEPTION 'Expected 7 BMT-* resources and 14 activity types, found % / %.', (SELECT count(*) FROM _seed_res), (SELECT count(*) FROM _seed_bt);
  END IF;
END $$;

COMMIT;

-- ── Summary ─────────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM "Users" u JOIN _seed_ctx c ON u."TenantId" = c.tenant_id AND u."Role" = 3 AND u."IsApproved")                 AS students,
  (SELECT count(*) FROM "Users" u JOIN _seed_ctx c ON u."TenantId" = c.tenant_id AND NOT u."IsApproved")                             AS pending_approvals,
  (SELECT count(*) FROM "Subscriptions" s JOIN _seed_ctx c ON s."TenantId" = c.tenant_id)                                            AS tuition_rows,
  (SELECT count(*) FROM "bookings" b JOIN _seed_ctx c ON b."TenantId" = c.tenant_id AND b."Title" LIKE 'Room hold - %')              AS room_holds,
  (SELECT count(*) FROM "bookings" b JOIN _seed_ctx c ON b."TenantId" = c.tenant_id AND b."FormData" IS NOT NULL AND b."FormData"::text LIKE '%attendance%') AS register_marks,
  (SELECT count(*) FROM "bookings" b JOIN _seed_ctx c ON b."TenantId" = c.tenant_id AND b."FormData"::text LIKE '%maxScore%')        AS gradebook_rows,
  (SELECT count(*) FROM "bookings" b JOIN _seed_ctx c ON b."TenantId" = c.tenant_id AND b."Title" LIKE 'Tutoring - %')               AS tutoring,
  (SELECT count(*) FROM "InventoryItems" i JOIN _seed_ctx c ON i."TenantId" = c.tenant_id)                                           AS inventory_items;

-- Logins:
--   admin@brightminds.lk                          admin view   - Demo@12345 if seed-demo-data.ps1 made it, else Passw0rd!
--   principal.brightminds@example-demo.test       academic head (Manager) - Passw0rd!
--   dilshan.ekanayake@brightminds.lk              teacher view (Staff) - Demo@12345 (from seed-demo-data.ps1)
--   ict.brightminds@example-demo.test             teacher view (Staff) - Passw0rd!
