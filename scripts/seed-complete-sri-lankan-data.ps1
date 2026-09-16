<#
.SYNOPSIS
  Seeds rich, real Sri Lankan data directly into the PostgreSQL database (SmePlatform)
  ensuring ALL pages (Dashboard, Calendar, Booking Manager, My Schedule, Reports,
  Resources, Booking Types, Staff, Branches, Profiles, Inventory, and Mobile Customer
  browsing) display live synced data.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'DbPassword',
    Justification = 'Password is passed via $env:PGPASSWORD to psql; stored only in process env, not persisted.')]
param(
    [string]$DbHost = "localhost",
    [string]$DbPort = "5432",
    [string]$DbName = "SmePlatform",
    [string]$DbUser = "postgres",
    [string]$DbPassword = "123456"
)

$ErrorActionPreference = "Stop"
$env:PGPASSWORD = $DbPassword

Write-Host "Creating complete Sri Lankan live sync seed script..." -ForegroundColor Cyan

$sqlFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "seed_sri_lankan_complete.sql")

$sql = @"
-- ==========================================================
-- 1. UPDATE USER TENANT ("Hasaranga") WITH RICH SRI LANKAN DATA
-- ==========================================================
UPDATE "Tenants"
SET 
  "Name" = 'Hasaranga Multi-Services Lanka',
  "Description" = 'Premier multi-service corporate solutions and consultancy enterprise based in Colombo, Sri Lanka. Providing executive advisory, technical diagnostics, and modern conference facilities.',
  "ShortTagline" = 'Excellence in Corporate Advisory & Multi-Services',
  "ContactPhone" = '+94 11 244 5566',
  "ContactEmail" = 'hasaranga0630@gmail.com',
  "Website" = 'https://hasaranga-services.lk',
  "LogoUrl" = 'https://images.unsplash.com/photo-1507679799987-c73779587ccf?w=400&q=80',
  "CoverImageUrl" = 'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=1600&q=80',
  "Amenities" = '["High-Speed WiFi", "Reserved Parking", "Air Conditioning", "Executive Lounge", "Card Payments Accepted", "Wheelchair Accessible"]'::jsonb,
  "BusinessHours" = '[
    {"dayOfWeek":"Monday","openTime":"08:30","closeTime":"18:00","isClosed":false},
    {"dayOfWeek":"Tuesday","openTime":"08:30","closeTime":"18:00","isClosed":false},
    {"dayOfWeek":"Wednesday","openTime":"08:30","closeTime":"18:00","isClosed":false},
    {"dayOfWeek":"Thursday","openTime":"08:30","closeTime":"18:00","isClosed":false},
    {"dayOfWeek":"Friday","openTime":"08:30","closeTime":"18:00","isClosed":false},
    {"dayOfWeek":"Saturday","openTime":"09:00","closeTime":"15:00","isClosed":false},
    {"dayOfWeek":"Sunday","openTime":"09:00","closeTime":"13:00","isClosed":true}
  ]'::jsonb,
  "UpdatedAt" = NOW()
WHERE "Id" = 'a5b97efc-e09d-403b-b116-0b01320bfbc1';

-- Ensure Main Branch address is set
UPDATE "Branches"
SET 
  "Name" = 'Colombo Head Office',
  "Address" = 'Level 14, West Tower, World Trade Center, Colombo 01',
  "Phone" = '+94 11 244 5566',
  "IsActive" = true,
  "UpdatedAt" = NOW()
WHERE "TenantId" = 'a5b97efc-e09d-403b-b116-0b01320bfbc1';

-- Add Resources for Hasaranga Tenant
DELETE FROM resource_schedules WHERE "ResourceId" IN (SELECT "Id" FROM resources WHERE "TenantId" = 'a5b97efc-e09d-403b-b116-0b01320bfbc1');
DELETE FROM bookings WHERE "TenantId" = 'a5b97efc-e09d-403b-b116-0b01320bfbc1';
DELETE FROM resources WHERE "TenantId" = 'a5b97efc-e09d-403b-b116-0b01320bfbc1';
DELETE FROM booking_types WHERE "TenantId" = 'a5b97efc-e09d-403b-b116-0b01320bfbc1';

INSERT INTO resources ("Id", "TenantId", "BranchId", "Name", "Category", "Specialty", "HourlyRate", "Capacity", "Status", "LinkedUserId", "CustomAttributes", "CreatedAt", "UpdatedAt")
VALUES 
  ('11111111-aaaa-4001-8001-000000000001', 'a5b97efc-e09d-403b-b116-0b01320bfbc1', 'c6df2b1a-d960-4ad1-b050-b7212121de74', 'Hasaranga Abeyrathna - Principal Consultant', 'Staff', 'Corporate Strategy', 8500, 1, 'Active', '72246d3f-1016-4a57-bec8-62d5b265e808', '{"rating":4.9, "experience":"12 years"}'::jsonb, NOW(), NOW()),
  ('11111111-aaaa-4001-8001-000000000002', 'a5b97efc-e09d-403b-b116-0b01320bfbc1', 'c6df2b1a-d960-4ad1-b050-b7212121de74', 'Charuka Abeyrathna - Technical Lead', 'Staff', 'Systems Architecture', 6500, 1, 'Active', 'b3f7d3fb-aba8-420e-9721-93688f273647', '{"rating":4.8, "experience":"8 years"}'::jsonb, NOW(), NOW()),
  ('11111111-aaaa-4001-8001-000000000003', 'a5b97efc-e09d-403b-b116-0b01320bfbc1', 'c6df2b1a-d960-4ad1-b050-b7212121de74', 'Nisal Jayawardena - Business Analyst', 'Staff', 'Financial Analytics', 4500, 1, 'Active', NULL, '{"rating":4.7, "experience":"5 years"}'::jsonb, NOW(), NOW()),
  ('11111111-aaaa-4001-8001-000000000004', 'a5b97efc-e09d-403b-b116-0b01320bfbc1', 'c6df2b1a-d960-4ad1-b050-b7212121de74', 'Executive Boardroom Suite (WTC 14th Fl)', 'Room', 'Boardroom', 5000, 16, 'Active', NULL, '{"rating":5.0, "screen":"75-inch 4K", "videoConf":"Zoom Rooms"}'::jsonb, NOW(), NOW());

-- Resource Schedules (Mon-Sat 08:30 to 18:00)
INSERT INTO resource_schedules ("Id", "ResourceId", "DayOfWeek", "StartTime", "EndTime", "IsAvailable", "CreatedAt", "UpdatedAt")
SELECT 
  gen_random_uuid(), 
  r."Id", 
  d, 
  '08:30:00'::interval, 
  '18:00:00'::interval, 
  CASE WHEN d = 0 THEN false ELSE true END, 
  NOW(), 
  NOW()
FROM resources r
CROSS JOIN generate_series(0, 6) AS d
WHERE r."TenantId" = 'a5b97efc-e09d-403b-b116-0b01320bfbc1';

-- Booking Types for Hasaranga Tenant
INSERT INTO booking_types ("Id", "TenantId", "Name", "Slug", "ColorHex", "DefaultDurationMinutes", "BookingUnit", "BufferMinutesBefore", "BufferMinutesAfter", "RequiresApproval", "Status", "CreatedAt", "UpdatedAt")
VALUES 
  ('22222222-aaaa-4001-8001-000000000001', 'a5b97efc-e09d-403b-b116-0b01320bfbc1', 'Executive Business Advisory', 'executive-business-advisory', '#2563EB', 60, 'Slot', 0, 10, false, 'Active', NOW(), NOW()),
  ('22222222-aaaa-4001-8001-000000000002', 'a5b97efc-e09d-403b-b116-0b01320bfbc1', 'Technical Architecture Review', 'technical-architecture-review', '#059669', 90, 'Slot', 0, 15, false, 'Active', NOW(), NOW()),
  ('22222222-aaaa-4001-8001-000000000003', 'a5b97efc-e09d-403b-b116-0b01320bfbc1', 'Boardroom Half-Day Session', 'boardroom-half-day', '#7C3AED', 240, 'Slot', 15, 30, true, 'Active', NOW(), NOW()),
  ('22222222-aaaa-4001-8001-000000000004', 'a5b97efc-e09d-403b-b116-0b01320bfbc1', 'Quick Consultation', 'quick-consultation', '#F59E0B', 30, 'Slot', 0, 5, false, 'Active', NOW(), NOW());

-- Bookings for Hasaranga Tenant (Past, Today Sept 16 2026, and Future)
INSERT INTO bookings (
  "Id", "TenantId", "ResourceId", "BookingTypeId", "BookedBy",
  "StartTime", "EndTime", "Status", "Priority", "Title", "Notes", "TotalCost",
  "CreatedAt", "UpdatedAt", "Version", "ReminderSent"
)
VALUES
  -- Past Bookings (Completed / NoShow)
  (gen_random_uuid(), 'a5b97efc-e09d-403b-b116-0b01320bfbc1', '11111111-aaaa-4001-8001-000000000001', '22222222-aaaa-4001-8001-000000000001', '72246d3f-1016-4a57-bec8-62d5b265e808',
   '2026-09-10 09:30:00+05:30', '2026-09-10 10:30:00+05:30', 'Completed', 'Normal', 'Client: Dilan Gunasekara', 'Quarterly roadmap review', 8500, NOW(), NOW(), 1, true),
  (gen_random_uuid(), 'a5b97efc-e09d-403b-b116-0b01320bfbc1', '11111111-aaaa-4001-8001-000000000002', '22222222-aaaa-4001-8001-000000000002', '72246d3f-1016-4a57-bec8-62d5b265e808',
   '2026-09-11 11:00:00+05:30', '2026-09-11 12:30:00+05:30', 'Completed', 'High', 'Client: Malinda Perera (Apex Corp)', 'Cloud migration system audit', 9750, NOW(), NOW(), 1, true),
  (gen_random_uuid(), 'a5b97efc-e09d-403b-b116-0b01320bfbc1', '11111111-aaaa-4001-8001-000000000003', '22222222-aaaa-4001-8001-000000000004', '72246d3f-1016-4a57-bec8-62d5b265e808',
   '2026-09-12 14:00:00+05:30', '2026-09-12 14:30:00+05:30', 'Completed', 'Normal', 'Client: Chamari Senanayake', 'Financial feasibility discussion', 2250, NOW(), NOW(), 1, true),
  (gen_random_uuid(), 'a5b97efc-e09d-403b-b116-0b01320bfbc1', '11111111-aaaa-4001-8001-000000000004', '22222222-aaaa-4001-8001-000000000003', '72246d3f-1016-4a57-bec8-62d5b265e808',
   '2026-09-14 09:00:00+05:30', '2026-09-14 13:00:00+05:30', 'Completed', 'Urgent', 'Client: Lanka Capital Holdings', 'Board of Directors strategy summit', 20000, NOW(), NOW(), 1, true),
  (gen_random_uuid(), 'a5b97efc-e09d-403b-b116-0b01320bfbc1', '11111111-aaaa-4001-8001-000000000001', '22222222-aaaa-4001-8001-000000000001', '72246d3f-1016-4a57-bec8-62d5b265e808',
   '2026-09-15 15:00:00+05:30', '2026-09-15 16:00:00+05:30', 'NoShow', 'Normal', 'Client: Nuwan Wickramasinghe', 'Client failed to attend advisory session', 8500, NOW(), NOW(), 1, true),

  -- TODAY'S BOOKINGS (Sept 16 2026) - Real active live data!
  (gen_random_uuid(), 'a5b97efc-e09d-403b-b116-0b01320bfbc1', '11111111-aaaa-4001-8001-000000000001', '22222222-aaaa-4001-8001-000000000001', '72246d3f-1016-4a57-bec8-62d5b265e808',
   '2026-09-16 09:30:00+05:30', '2026-09-16 10:30:00+05:30', 'Completed', 'High', 'Client: Priyantha Silva (Ceylon Tea Exports)', 'Export tariff optimization strategy', 8500, NOW(), NOW(), 1, true),
  (gen_random_uuid(), 'a5b97efc-e09d-403b-b116-0b01320bfbc1', '11111111-aaaa-4001-8001-000000000001', '22222222-aaaa-4001-8001-000000000001', '72246d3f-1016-4a57-bec8-62d5b265e808',
   '2026-09-16 11:30:00+05:30', '2026-09-16 12:30:00+05:30', 'CheckedIn', 'Normal', 'Client: Anoma Jayasundara', 'Corporate governance restructuring', 8500, NOW(), NOW(), 1, true),
  (gen_random_uuid(), 'a5b97efc-e09d-403b-b116-0b01320bfbc1', '11111111-aaaa-4001-8001-000000000002', '22222222-aaaa-4001-8001-000000000002', '72246d3f-1016-4a57-bec8-62d5b265e808',
   '2026-09-16 14:00:00+05:30', '2026-09-16 15:30:00+05:30', 'Confirmed', 'Normal', 'Client: Roshan De Silva (FinTech Lanka)', 'Security & compliance verification', 9750, NOW(), NOW(), 1, false),
  (gen_random_uuid(), 'a5b97efc-e09d-403b-b116-0b01320bfbc1', '11111111-aaaa-4001-8001-000000000004', '22222222-aaaa-4001-8001-000000000003', '72246d3f-1016-4a57-bec8-62d5b265e808',
   '2026-09-16 14:00:00+05:30', '2026-09-16 18:00:00+05:30', 'Confirmed', 'Urgent', 'Client: Blue Ocean Ventures', 'Investor Pitch & Partner Meeting', 20000, NOW(), NOW(), 1, false),
  (gen_random_uuid(), 'a5b97efc-e09d-403b-b116-0b01320bfbc1', '11111111-aaaa-4001-8001-000000000003', '22222222-aaaa-4001-8001-000000000004', '72246d3f-1016-4a57-bec8-62d5b265e808',
   '2026-09-16 16:30:00+05:30', '2026-09-16 17:00:00+05:30', 'Pending', 'Low', 'Client: Kasun Rajapaksa', 'Initial introductory call', 2250, NOW(), NOW(), 1, false),

  -- UPCOMING BOOKINGS (Sept 17 - Sept 22 2026)
  (gen_random_uuid(), 'a5b97efc-e09d-403b-b116-0b01320bfbc1', '11111111-aaaa-4001-8001-000000000001', '22222222-aaaa-4001-8001-000000000001', '72246d3f-1016-4a57-bec8-62d5b265e808',
   '2026-09-17 10:00:00+05:30', '2026-09-17 11:00:00+05:30', 'Confirmed', 'Normal', 'Client: Nilmini Fernando', 'Enterprise valuation & investment assessment', 8500, NOW(), NOW(), 1, false),
  (gen_random_uuid(), 'a5b97efc-e09d-403b-b116-0b01320bfbc1', '11111111-aaaa-4001-8001-000000000002', '22222222-aaaa-4001-8001-000000000002', '72246d3f-1016-4a57-bec8-62d5b265e808',
   '2026-09-17 14:00:00+05:30', '2026-09-17 15:30:00+05:30', 'Confirmed', 'Normal', 'Client: Sahan Dharmasena', 'Infrastructure scalability consultation', 9750, NOW(), NOW(), 1, false),
  (gen_random_uuid(), 'a5b97efc-e09d-403b-b116-0b01320bfbc1', '11111111-aaaa-4001-8001-000000000001', '22222222-aaaa-4001-8001-000000000001', '72246d3f-1016-4a57-bec8-62d5b265e808',
   '2026-09-18 09:30:00+05:30', '2026-09-18 10:30:00+05:30', 'Confirmed', 'High', 'Client: Tharanga Weerasinghe', 'Commercial legal restructuring', 8500, NOW(), NOW(), 1, false),
  (gen_random_uuid(), 'a5b97efc-e09d-403b-b116-0b01320bfbc1', '11111111-aaaa-4001-8001-000000000004', '22222222-aaaa-4001-8001-000000000003', '72246d3f-1016-4a57-bec8-62d5b265e808',
   '2026-09-19 10:00:00+05:30', '2026-09-19 14:00:00+05:30', 'Pending', 'Normal', 'Client: Colombo Tech Syndicate', 'Quarterly General Meeting', 20000, NOW(), NOW(), 1, false);


-- ==========================================================
-- 2. SEED REAL SRI LANKAN BOOKINGS FOR COLOMBO FAMILY CLINIC
-- ==========================================================
-- Resources: Dr. Anjali (Cardio), Dr. Kasun (Pediatrics), Dr. Priya (Derm), Dr. Ruwan (GP)
DELETE FROM bookings WHERE "TenantId" = 'c23aac1b-13ba-4763-b589-e0cfd2ec97f4';

INSERT INTO bookings (
  "Id", "TenantId", "ResourceId", "BookingTypeId", "BookedBy",
  "StartTime", "EndTime", "Status", "Priority", "Title", "Notes", "TotalCost",
  "CreatedAt", "UpdatedAt", "Version", "ReminderSent"
)
SELECT 
  gen_random_uuid(),
  'c23aac1b-13ba-4763-b589-e0cfd2ec97f4',
  res."Id",
  bt."Id",
  'e4332aea-e8d0-49e3-866e-62605f4646c2', -- admin user
  ('2026-09-16 08:00:00+05:30'::timestamptz + (day_offset || ' days')::interval + (hour_offset || ' hours')::interval),
  ('2026-09-16 08:30:00+05:30'::timestamptz + (day_offset || ' days')::interval + (hour_offset || ' hours')::interval),
  status,
  priority,
  'Patient: ' || patient_name,
  symptom,
  res."HourlyRate" * 0.5,
  NOW(),
  NOW(),
  1,
  true
FROM (
  VALUES
    (-5, 1, 'Completed', 'Normal', 'Kanchana Perera', 'Routine blood pressure review'),
    (-5, 3, 'Completed', 'High', 'Dilshan Jayamaha', 'ECG evaluation and cardiology consult'),
    (-4, 2, 'Completed', 'Normal', 'Nilanthi Fernando', 'Annual pediatric vaccination review'),
    (-4, 4, 'NoShow', 'Normal', 'Samantha Wickramatunga', 'General checkup - patient did not arrive'),
    (-3, 1, 'Completed', 'Normal', 'Tharindu Jayatillake', 'Skin allergy and dermatological examination'),
    (-3, 3, 'Completed', 'Normal', 'Chathurika Dissanayake', 'Asthma inhaler prescription update'),
    (-2, 2, 'Completed', 'Urgent', 'Asanka Ratnayake', 'Chest pain consultation - referral given'),
    (-2, 5, 'Cancelled', 'Normal', 'Sunethra Wijesinghe', 'Appointment cancelled 24h prior'),
    (-1, 1, 'Completed', 'Normal', 'Nirosha De Alwis', 'Post-surgery cardiac recovery follow-up'),
    (-1, 3, 'Completed', 'Normal', 'Lalith Gunawardena', 'Pediatric fever follow-up'),
    
    -- TODAY (Sept 16 2026)
    (0, 1, 'Completed', 'Normal', 'Suneth Silva', 'Morning BP monitoring and medication refill'),
    (0, 2, 'CheckedIn', 'Normal', 'Malinda Gunawardena', 'In waiting area - ECG review with Dr. Anjali'),
    (0, 3, 'InProgress', 'High', 'Ruwanthi Karunaratne', 'Consultation currently in progress with Dr. Priya'),
    (0, 4, 'Confirmed', 'Normal', 'Buddhika Senaratne', 'Afternoon consultation at 2:00 PM'),
    (0, 5, 'Confirmed', 'Urgent', 'Dayani Rajapaksa', 'Evening child fever consultation at 3:30 PM'),
    (0, 6, 'Pending', 'Normal', 'Hemantha Jayasuriya', 'Awaiting appointment confirmation'),

    -- UPCOMING (Sept 17 - Sept 21 2026)
    (1, 1, 'Confirmed', 'Normal', 'Gayan Mendis', 'Routine cardiac stress test consult'),
    (1, 3, 'Confirmed', 'Normal', 'Chamari Wickramasinghe', 'Skin lesion review with Dr. Priya'),
    (2, 2, 'Confirmed', 'Normal', 'Janaka Alahakoon', 'General physical examination'),
    (2, 4, 'Confirmed', 'Normal', 'Pavithra Gamage', 'Pediatric developmental checkup'),
    (3, 1, 'Confirmed', 'Normal', 'Mahesh Rodrigo', 'Cholesterol management plan'),
    (4, 2, 'Confirmed', 'Normal', 'Surangi Ekanayake', 'Dermatology patch test consult'),
    (5, 3, 'Confirmed', 'Normal', 'Dinesh Hettiarachchi', 'Preventive cardiac evaluation')
) AS sample(day_offset, hour_offset, status, priority, patient_name, symptom)
CROSS JOIN LATERAL (
  SELECT "Id", "HourlyRate" FROM resources 
  WHERE "TenantId" = 'c23aac1b-13ba-4763-b589-e0cfd2ec97f4'
  ORDER BY random() LIMIT 1
) res
CROSS JOIN LATERAL (
  SELECT "Id" FROM booking_types 
  WHERE "TenantId" = 'c23aac1b-13ba-4763-b589-e0cfd2ec97f4'
  ORDER BY random() LIMIT 1
) bt;


-- ==========================================================
-- 3. SEED REAL SRI LANKAN BOOKINGS FOR SPICE GARDEN RESTAURANT
-- ==========================================================
DELETE FROM bookings WHERE "TenantId" = '32bf0ffe-9271-42a3-8b5d-40a8b24f9967';

INSERT INTO bookings (
  "Id", "TenantId", "ResourceId", "BookingTypeId", "BookedBy",
  "StartTime", "EndTime", "Status", "Priority", "Title", "Notes", "TotalCost",
  "CreatedAt", "UpdatedAt", "Version", "ReminderSent"
)
SELECT 
  gen_random_uuid(),
  '32bf0ffe-9271-42a3-8b5d-40a8b24f9967',
  res."Id",
  bt."Id",
  '82b2862f-f491-4c53-9523-3d7c179e14f7', -- admin user
  ('2026-09-16 12:00:00+05:30'::timestamptz + (day_offset || ' days')::interval + (hour_offset || ' hours')::interval),
  ('2026-09-16 13:30:00+05:30'::timestamptz + (day_offset || ' days')::interval + (hour_offset || ' hours')::interval),
  status,
  'Normal',
  'Reservation: ' || guest_name,
  pax || ' guests, ' || notes,
  pax * 3500,
  NOW(),
  NOW(),
  1,
  true
FROM (
  VALUES
    (-4, 0, 'Completed', 'Manoji Weerasinghe', 4, 'Lunch - Seafood special'),
    (-3, 6, 'Completed', 'Ranjith Fernando', 6, 'Dinner - Birthday celebration'),
    (-2, 0, 'Completed', 'Kushan Wickrama', 2, 'Lunch - Window table requested'),
    (-1, 7, 'Completed', 'Shehan Abeywickrama', 10, 'Dinner - Private dining room corporate treat'),
    (0, 0, 'CheckedIn', 'Charith Jayawardena', 4, 'Lunch reservation - Seated at Garden Terrace'),
    (0, 1, 'Confirmed', 'Anushka Senanayake', 2, 'Lunch date - Window table'),
    (0, 6, 'Confirmed', 'Harsha De Silva', 6, 'Dinner reservation 7:00 PM - Family gathering'),
    (0, 7, 'Confirmed', 'Nalin Gunasekera', 8, 'Dinner 8:00 PM - Private Dining Room booked'),
    (1, 0, 'Confirmed', 'Vipula Samaranayake', 4, 'Lunch booking'),
    (1, 6, 'Confirmed', 'Sujith Ranasinghe', 2, 'Dinner anniversary celebration'),
    (2, 6, 'Confirmed', 'Pradeep Rathnayake', 5, 'Family dinner weekend')
) AS sample(day_offset, hour_offset, status, guest_name, pax, notes)
CROSS JOIN LATERAL (
  SELECT "Id" FROM resources 
  WHERE "TenantId" = '32bf0ffe-9271-42a3-8b5d-40a8b24f9967'
  ORDER BY random() LIMIT 1
) res
CROSS JOIN LATERAL (
  SELECT "Id" FROM booking_types 
  WHERE "TenantId" = '32bf0ffe-9271-42a3-8b5d-40a8b24f9967'
  ORDER BY random() LIMIT 1
) bt;


-- ==========================================================
-- 4. SEED REAL SRI LANKAN BOOKINGS FOR POWERHOUSE FITNESS
-- ==========================================================
DELETE FROM bookings WHERE "TenantId" = 'd4c95983-c79b-4798-b367-cd462240ca24';

INSERT INTO bookings (
  "Id", "TenantId", "ResourceId", "BookingTypeId", "BookedBy",
  "StartTime", "EndTime", "Status", "Priority", "Title", "Notes", "TotalCost",
  "CreatedAt", "UpdatedAt", "Version", "ReminderSent"
)
SELECT 
  gen_random_uuid(),
  'd4c95983-c79b-4798-b367-cd462240ca24',
  res."Id",
  bt."Id",
  '0fb77d57-d4e3-457c-a919-f45dffa0a9e0',
  ('2026-09-16 07:00:00+05:30'::timestamptz + (day_offset || ' days')::interval + (hour_offset || ' hours')::interval),
  ('2026-09-16 08:00:00+05:30'::timestamptz + (day_offset || ' days')::interval + (hour_offset || ' hours')::interval),
  status,
  'Normal',
  'Trainee: ' || member_name,
  routine,
  3000,
  NOW(),
  NOW(),
  1,
  true
FROM (
  VALUES
    (-3, 1, 'Completed', 'Danushka Jayalath', 'Hypertrophy upper body routine'),
    (-2, 10, 'Completed', 'Kavinda Perera', 'Evening CrossFit session'),
    (-1, 2, 'Completed', 'Oshadi Jayawardena', 'Yoga flexibility and core strength'),
    (0, 0, 'Completed', 'Akila Bandara', 'Morning 7am conditioning session'),
    (0, 2, 'CheckedIn', 'Chathura Senaratne', 'Personal training with Sanjeewa'),
    (0, 10, 'Confirmed', 'Thimira Fernando', 'Evening 5pm strength coaching'),
    (1, 1, 'Confirmed', 'Hirantha Jayasuriya', 'Leg day personal training'),
    (2, 2, 'Confirmed', 'Nethmi Wijesinghe', 'Morning Yoga class')
) AS sample(day_offset, hour_offset, status, member_name, routine)
CROSS JOIN LATERAL (
  SELECT "Id" FROM resources 
  WHERE "TenantId" = 'd4c95983-c79b-4798-b367-cd462240ca24'
  ORDER BY random() LIMIT 1
) res
CROSS JOIN LATERAL (
  SELECT "Id" FROM booking_types 
  WHERE "TenantId" = 'd4c95983-c79b-4798-b367-cd462240ca24'
  ORDER BY random() LIMIT 1
) bt;


-- ==========================================================
-- 5. SEED REAL SRI LANKAN BOOKINGS FOR MALKEY RENT A CAR
-- ==========================================================
DELETE FROM bookings WHERE "TenantId" = '91d422e3-ee0b-48a5-a54a-8c6bf135c387';

INSERT INTO bookings (
  "Id", "TenantId", "ResourceId", "BookingTypeId", "BookedBy",
  "StartTime", "EndTime", "Status", "Priority", "Title", "Notes", "TotalCost",
  "CreatedAt", "UpdatedAt", "Version", "ReminderSent"
)
SELECT 
  gen_random_uuid(),
  '91d422e3-ee0b-48a5-a54a-8c6bf135c387',
  res."Id",
  bt."Id",
  'd56f6f5d-f120-4440-9a56-04231bdd781c',
  ('2026-09-16 09:00:00+05:30'::timestamptz + (day_start || ' days')::interval),
  ('2026-09-16 18:00:00+05:30'::timestamptz + (day_end || ' days')::interval),
  status,
  'Normal',
  'Rental: ' || client_name,
  purpose,
  (day_end - day_start) * 6500,
  NOW(),
  NOW(),
  1,
  true
FROM (
  VALUES
    (-5, -2, 'Completed', 'Ruwan Jayasinghe', 'Colombo to Kandy family road trip (Alto)'),
    (-1, 3, 'InProgress', 'Samantha De Mel', 'Business travel Colombo to Galle (Axio) - active rental'),
    (0, 4, 'Confirmed', 'Graham Taylor', 'Foreign tourist Southern Expressway tour (Commuter Van)'),
    (2, 6, 'Confirmed', 'Ashan Wickramaratne', 'Weekend getaway to Nuwara Eliya')
) AS sample(day_start, day_end, status, client_name, purpose)
CROSS JOIN LATERAL (
  SELECT "Id" FROM resources 
  WHERE "TenantId" = '91d422e3-ee0b-48a5-a54a-8c6bf135c387'
  ORDER BY random() LIMIT 1
) res
CROSS JOIN LATERAL (
  SELECT "Id" FROM booking_types 
  WHERE "TenantId" = '91d422e3-ee0b-48a5-a54a-8c6bf135c387'
  ORDER BY random() LIMIT 1
) bt;


-- ==========================================================
-- 6. SEED REAL SRI LANKAN BOOKINGS FOR THE WALLAWWA (HOTEL)
-- ==========================================================
DELETE FROM bookings WHERE "TenantId" = 'f163610e-fb88-4aae-bf1d-7ce0d7a47b25';

INSERT INTO bookings (
  "Id", "TenantId", "ResourceId", "BookingTypeId", "BookedBy",
  "StartTime", "EndTime", "Status", "Priority", "Title", "Notes", "TotalCost",
  "CreatedAt", "UpdatedAt", "Version", "ReminderSent"
)
SELECT 
  gen_random_uuid(),
  'f163610e-fb88-4aae-bf1d-7ce0d7a47b25',
  res."Id",
  bt."Id",
  '945f995e-49b0-4107-8a5f-7b57df90aa96',
  ('2026-09-16 14:00:00+05:30'::timestamptz + (day_start || ' days')::interval),
  ('2026-09-16 11:00:00+05:30'::timestamptz + (day_end || ' days')::interval),
  status,
  'Normal',
  'Guest: ' || guest_name,
  nights || ' night stay - ' || room_type,
  nights * 48000,
  NOW(),
  NOW(),
  1,
  true
FROM (
  VALUES
    (-4, -1, 'Completed', 'Dr. Alistair Cook', 3, 'Mountbatten Suite - UK Guest'),
    (-1, 2, 'InProgress', 'Rohan & Dinithi Senanayake', 3, 'Garden Suite - Honeymoon stay'),
    (0, 3, 'CheckedIn', 'Marcus Lindqvist', 3, 'Wallawwa Bedroom - In-house guest'),
    (1, 4, 'Confirmed', 'Kenji Sato', 3, 'Family Suite - Business & leisure stay')
) AS sample(day_start, day_end, status, guest_name, nights, room_type)
CROSS JOIN LATERAL (
  SELECT "Id" FROM resources 
  WHERE "TenantId" = 'f163610e-fb88-4aae-bf1d-7ce0d7a47b25'
  ORDER BY random() LIMIT 1
) res
CROSS JOIN LATERAL (
  SELECT "Id" FROM booking_types 
  WHERE "TenantId" = 'f163610e-fb88-4aae-bf1d-7ce0d7a47b25'
  ORDER BY random() LIMIT 1
) bt;


-- ==========================================================
-- 7. SEED REAL INVENTORY STOCK MOVEMENTS FOR SME DEMO STORE
-- ==========================================================
DELETE FROM "StockMovements" WHERE "TenantId" = '97c98d83-a22a-4b10-8415-3033bdc2bdbb';

INSERT INTO "StockMovements" (
  "Id", "TenantId", "BranchId", "InventoryItemId", "MovementType",
  "Quantity", "UnitCost", "Reference", "OccurredAt", "Notes", "CreatedAt", "UpdatedAt"
)
SELECT
  gen_random_uuid(),
  '97c98d83-a22a-4b10-8415-3033bdc2bdbb',
  'c9b256a2-c5fd-4c08-a802-ab1c718a27e1',
  item."Id",
  movement_type,
  qty,
  item."UnitCost",
  ref,
  ('2026-09-16 10:00:00+05:30'::timestamptz + (day_offset || ' days')::interval),
  note,
  NOW(),
  NOW()
FROM (
  VALUES
    (-6, 'Receive', 50, 'PO-2026-0901', 'Received weekly stock shipment from Colombo Dairy Co.'),
    (-5, 'Sale', -15, 'INV-2026-1044', 'Store retail sales batch'),
    (-4, 'Receive', 30, 'PO-2026-0904', 'Restock of craft paper cups and coffee syrups'),
    (-3, 'Adjustment', -2, 'ADJ-2026-003', 'Inventory count adjustment - damaged packaging discarded'),
    (-2, 'Sale', -25, 'INV-2026-1092', 'Bulk corporate order dispatch'),
    (-1, 'Receive', 100, 'PO-2026-0912', 'Fresh delivery of roasted coffee beans'),
    (0, 'Sale', -12, 'INV-2026-1120', 'Morning cafe sales transactions')
) AS sample(day_offset, movement_type, qty, ref, note)
CROSS JOIN LATERAL (
  SELECT "Id", "UnitCost" FROM "InventoryItems"
  WHERE "TenantId" = '97c98d83-a22a-4b10-8415-3033bdc2bdbb'
  ORDER BY random() LIMIT 1
) item;

"@

[System.IO.File]::WriteAllText($sqlFile, $sql)

Write-Host "Executing SQL script against $DbName on ${DbHost}:${DbPort}..." -ForegroundColor Yellow
$psqlOutput = & psql -U $DbUser -h $DbHost -p $DbPort -d $DbName -f $sqlFile 2>&1
Write-Host $psqlOutput

Remove-Item $sqlFile -Force

Write-Host "Successfully seeded real Sri Lankan live sync data across all businesses!" -ForegroundColor Green
