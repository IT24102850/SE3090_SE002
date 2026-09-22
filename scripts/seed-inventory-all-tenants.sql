-- =============================================================
-- INVENTORY SEED: Real Sri Lankan Data for All Tenants
-- =============================================================
-- Covers:
--   Colombo Family Clinic       (c23aac1b) / branch df73583b
--   Spice Garden Restaurant     (32bf0ffe) / branch 6d0b82c3
--   PowerHouse Fitness          (d4c95983) / branch dda6a0e2
--   BrightMinds Tuition Center  (ebbecd8a) / branch b43e1f66
--   Prime Properties Lanka      (f867fee1) / branch 39a0790d
--   Ceylon Adventures Tours     (6e2bff01) / branch 9378ca63
--   QuickFix Home Services      (894644de) / branch a21961c3
--   Hasaranga Multi-Services    (a5b97efc) / branch c6df2b1a
--   Malkey Rent A Car           (91d422e3) / branch 7f2e7e31
--   Mirissa Jetliner Whale      (f295189f) / branch c3e5ec50
--   The Wallawwa                (f163610e) / branch 1e04a2e0
--   Weligama Bay Dive Center    (772c8068) / branch 4bbbd410
-- =============================================================

-- ------------------------------------------------------------------
-- 1. COLOMBO FAMILY CLINIC  (Medical supplies)
-- ------------------------------------------------------------------
INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
VALUES
  (gen_random_uuid(),'c23aac1b-13ba-4763-b589-e0cfd2ec97f4','df73583b-f0df-42c6-81e3-1cb6e8319b85','Paracetamol 500mg (x100 tabs)','PHARM-001','Standard paracetamol analgesic strip pack',180,50,245.00,true,NOW(),NOW()),
  (gen_random_uuid(),'c23aac1b-13ba-4763-b589-e0cfd2ec97f4','df73583b-f0df-42c6-81e3-1cb6e8319b85','Surgical Gloves — Medium (box/100)','SURG-001','Latex examination gloves, sterile',42,20,875.00,true,NOW(),NOW()),
  (gen_random_uuid(),'c23aac1b-13ba-4763-b589-e0cfd2ec97f4','df73583b-f0df-42c6-81e3-1cb6e8319b85','Surgical Gloves — Large (box/100)','SURG-002','Latex examination gloves, sterile',30,20,875.00,true,NOW(),NOW()),
  (gen_random_uuid(),'c23aac1b-13ba-4763-b589-e0cfd2ec97f4','df73583b-f0df-42c6-81e3-1cb6e8319b85','3M Surgical Mask (box/50)','PPE-001','Type IIR surgical masks, CE certified',96,40,1250.00,true,NOW(),NOW()),
  (gen_random_uuid(),'c23aac1b-13ba-4763-b589-e0cfd2ec97f4','df73583b-f0df-42c6-81e3-1cb6e8319b85','Saline Solution 500ml','MED-001','Normal saline 0.9% IV infusion bags',55,30,380.00,true,NOW(),NOW()),
  (gen_random_uuid(),'c23aac1b-13ba-4763-b589-e0cfd2ec97f4','df73583b-f0df-42c6-81e3-1cb6e8319b85','Blood Glucose Test Strips (x50)','DIAG-001','Compatible with Accu-Chek Active meter',14,25,1850.00,true,NOW(),NOW()),
  (gen_random_uuid(),'c23aac1b-13ba-4763-b589-e0cfd2ec97f4','df73583b-f0df-42c6-81e3-1cb6e8319b85','Disposable Syringes 5ml (x100)','SURG-003','Single-use Luer-lock syringes',72,50,640.00,true,NOW(),NOW()),
  (gen_random_uuid(),'c23aac1b-13ba-4763-b589-e0cfd2ec97f4','df73583b-f0df-42c6-81e3-1cb6e8319b85','Alcohol-Based Hand Sanitiser 500ml','HYG-001','70% isopropyl alcohol gel',28,15,320.00,true,NOW(),NOW()),
  (gen_random_uuid(),'c23aac1b-13ba-4763-b589-e0cfd2ec97f4','df73583b-f0df-42c6-81e3-1cb6e8319b85','Tongue Depressors (box/100)','EXAM-001','Wooden, individually wrapped',11,10,180.00,true,NOW(),NOW()),
  (gen_random_uuid(),'c23aac1b-13ba-4763-b589-e0cfd2ec97f4','df73583b-f0df-42c6-81e3-1cb6e8319b85','Digital Thermometer','DIAG-002','Non-contact infrared, °C display',8,5,2450.00,true,NOW(),NOW());

-- ------------------------------------------------------------------
-- 2. SPICE GARDEN RESTAURANT  (F&B supplies)
-- ------------------------------------------------------------------
INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
VALUES
  (gen_random_uuid(),'32bf0ffe-9271-42a3-8b5d-40a8b24f9967','6d0b82c3-824e-4b6c-9800-297a4dde28de','Basmati Rice 50kg','RICE-001','Premium long-grain basmati rice sack',12,5,9800.00,true,NOW(),NOW()),
  (gen_random_uuid(),'32bf0ffe-9271-42a3-8b5d-40a8b24f9967','6d0b82c3-824e-4b6c-9800-297a4dde28de','Ceylon Coconut Milk 400ml (x12 cans)','CONS-001','First-pressed coconut milk, Dilmah',24,10,2640.00,true,NOW(),NOW()),
  (gen_random_uuid(),'32bf0ffe-9271-42a3-8b5d-40a8b24f9967','6d0b82c3-824e-4b6c-9800-297a4dde28de','Ceylon Cinnamon Sticks 500g','SPICE-001','True Ceylon cinnamon, Grade C5',6,5,1850.00,true,NOW(),NOW()),
  (gen_random_uuid(),'32bf0ffe-9271-42a3-8b5d-40a8b24f9967','6d0b82c3-824e-4b6c-9800-297a4dde28de','Cooking Oil — Sunflower 5L','OIL-001','Refined sunflower cooking oil',15,8,2200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'32bf0ffe-9271-42a3-8b5d-40a8b24f9967','6d0b82c3-824e-4b6c-9800-297a4dde28de','Chicken Fillet 1kg (frozen)','PROT-001','Boneless chicken breast, IQF frozen',40,20,1350.00,true,NOW(),NOW()),
  (gen_random_uuid(),'32bf0ffe-9271-42a3-8b5d-40a8b24f9967','6d0b82c3-824e-4b6c-9800-297a4dde28de','Prawns Large (1kg frozen)','PROT-002','Tiger prawns 16/20 size, IQF',18,10,2800.00,true,NOW(),NOW()),
  (gen_random_uuid(),'32bf0ffe-9271-42a3-8b5d-40a8b24f9967','6d0b82c3-824e-4b6c-9800-297a4dde28de','Curry Leaves Fresh (500g)','HERB-001','Fresh organic curry leaves, Colombo market',3,5,180.00,true,NOW(),NOW()),
  (gen_random_uuid(),'32bf0ffe-9271-42a3-8b5d-40a8b24f9967','6d0b82c3-824e-4b6c-9800-297a4dde28de','Takeaway Boxes — Large (x100)','PACK-001','Eco-friendly kraft paper containers',4,10,1400.00,true,NOW(),NOW()),
  (gen_random_uuid(),'32bf0ffe-9271-42a3-8b5d-40a8b24f9967','6d0b82c3-824e-4b6c-9800-297a4dde28de','LPG Cylinder 12.5kg','GAS-001','Commercial cooking gas cylinder',3,2,3800.00,true,NOW(),NOW()),
  (gen_random_uuid(),'32bf0ffe-9271-42a3-8b5d-40a8b24f9967','6d0b82c3-824e-4b6c-9800-297a4dde28de','Cutlery Set — Stainless Steel','EQUIP-001','Forks, knives, spoons set (x24)',2,2,4500.00,true,NOW(),NOW());

-- ------------------------------------------------------------------
-- 3. POWERHOUSE FITNESS  (Gym & fitness supplies)
-- ------------------------------------------------------------------
INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
VALUES
  (gen_random_uuid(),'d4c95983-c79b-4798-b367-cd462240ca24','dda6a0e2-ad84-4e73-9e07-6dbf786442db','Protein Supplement — Whey 1kg','SUPP-001','Unflavoured whey protein isolate',22,10,8900.00,true,NOW(),NOW()),
  (gen_random_uuid(),'d4c95983-c79b-4798-b367-cd462240ca24','dda6a0e2-ad84-4e73-9e07-6dbf786442db','Resistance Band Set (light/med/heavy)','EQUIP-001','Latex loop bands with carry bag',14,8,1850.00,true,NOW(),NOW()),
  (gen_random_uuid(),'d4c95983-c79b-4798-b367-cd462240ca24','dda6a0e2-ad84-4e73-9e07-6dbf786442db','Foam Roller 60cm','EQUIP-002','High-density EVA foam roller',9,6,2400.00,true,NOW(),NOW()),
  (gen_random_uuid(),'d4c95983-c79b-4798-b367-cd462240ca24','dda6a0e2-ad84-4e73-9e07-6dbf786442db','Gym Towel — Microfibre (x10)','LINEN-001','Quick-dry 50×100cm gym towels',35,20,3200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'d4c95983-c79b-4798-b367-cd462240ca24','dda6a0e2-ad84-4e73-9e07-6dbf786442db','Sanitiser Spray 1L','HYG-001','Equipment disinfectant spray bottle',7,5,580.00,true,NOW(),NOW()),
  (gen_random_uuid(),'d4c95983-c79b-4798-b367-cd462240ca24','dda6a0e2-ad84-4e73-9e07-6dbf786442db','Dumbbells 5kg (pair)','EQUIP-003','Cast iron hex dumbbells, rubber coated',6,4,7500.00,true,NOW(),NOW()),
  (gen_random_uuid(),'d4c95983-c79b-4798-b367-cd462240ca24','dda6a0e2-ad84-4e73-9e07-6dbf786442db','Yoga Mat 6mm','EQUIP-004','Non-slip TPE exercise mat, 183×61cm',12,8,3200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'d4c95983-c79b-4798-b367-cd462240ca24','dda6a0e2-ad84-4e73-9e07-6dbf786442db','Isotonic Sports Drink Mix 1kg','SUPP-002','Electrolyte powder — lemon flavour',5,8,4200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'d4c95983-c79b-4798-b367-cd462240ca24','dda6a0e2-ad84-4e73-9e07-6dbf786442db','Jump Rope — Speed Cable','EQUIP-005','Adjustable aluminium handles',18,10,1250.00,true,NOW(),NOW()),
  (gen_random_uuid(),'d4c95983-c79b-4798-b367-cd462240ca24','dda6a0e2-ad84-4e73-9e07-6dbf786442db','Membership Card Stock (x200)','ADMIN-001','Blank PVC cards for member ID printing',45,50,8500.00,true,NOW(),NOW());

-- ------------------------------------------------------------------
-- 4. BRIGHTMINDS TUITION CENTER  (Stationery & supplies)
-- ------------------------------------------------------------------
INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
VALUES
  (gen_random_uuid(),'ebbecd8a-b5f9-4ab0-9fc6-a747152772fc','b43e1f66-5284-4a01-a444-a55c7ec0c642','A4 Paper Ream 80gsm','STAT-001','500 sheets premium white copier paper',62,20,680.00,true,NOW(),NOW()),
  (gen_random_uuid(),'ebbecd8a-b5f9-4ab0-9fc6-a747152772fc','b43e1f66-5284-4a01-a444-a55c7ec0c642','Whiteboard Marker Set (x12)','STAT-002','Assorted colours, dry-erase',28,15,480.00,true,NOW(),NOW()),
  (gen_random_uuid(),'ebbecd8a-b5f9-4ab0-9fc6-a747152772fc','b43e1f66-5284-4a01-a444-a55c7ec0c642','Whiteboard Eraser','STAT-003','Felt magnetic eraser for standard boards',15,10,120.00,true,NOW(),NOW()),
  (gen_random_uuid(),'ebbecd8a-b5f9-4ab0-9fc6-a747152772fc','b43e1f66-5284-4a01-a444-a55c7ec0c642','Scientific Calculator Casio FX-991','ELEC-001','Advanced scientific calculator',8,5,3800.00,true,NOW(),NOW()),
  (gen_random_uuid(),'ebbecd8a-b5f9-4ab0-9fc6-a747152772fc','b43e1f66-5284-4a01-a444-a55c7ec0c642','Exercise Books A4 (x50)','STAT-004','Ruled exercise books for students',120,60,3500.00,true,NOW(),NOW()),
  (gen_random_uuid(),'ebbecd8a-b5f9-4ab0-9fc6-a747152772fc','b43e1f66-5284-4a01-a444-a55c7ec0c642','Ballpoint Pens Blue (box/50)','STAT-005','Pilot BPS-GP medium tip blue pens',10,8,750.00,true,NOW(),NOW()),
  (gen_random_uuid(),'ebbecd8a-b5f9-4ab0-9fc6-a747152772fc','b43e1f66-5284-4a01-a444-a55c7ec0c642','Highlighter Set (x6 colours)','STAT-006','Chisel tip fluorescent highlighters',22,12,320.00,true,NOW(),NOW()),
  (gen_random_uuid(),'ebbecd8a-b5f9-4ab0-9fc6-a747152772fc','b43e1f66-5284-4a01-a444-a55c7ec0c642','Toner Cartridge — HP LaserJet','PRINT-001','Replacement toner for HP M404dn',3,3,7800.00,true,NOW(),NOW());

-- ------------------------------------------------------------------
-- 5. PRIME PROPERTIES LANKA  (Office supplies)
-- ------------------------------------------------------------------
INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
VALUES
  (gen_random_uuid(),'f867fee1-287d-4b3e-8d28-abe3a20c0fe2','39a0790d-6956-4dbd-81aa-bd02a7039db9','For Sale / Rent Signboards','SIGN-001','Weatherproof PVC boards 60×90cm',18,10,1200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f867fee1-287d-4b3e-8d28-abe3a20c0fe2','39a0790d-6956-4dbd-81aa-bd02a7039db9','A4 Paper Ream 80gsm','STAT-001','Copier paper for property documents',30,15,680.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f867fee1-287d-4b3e-8d28-abe3a20c0fe2','39a0790d-6956-4dbd-81aa-bd02a7039db9','Property Brochure Stock (x100)','MKTG-001','Full-colour A5 property brochures',4,10,8500.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f867fee1-287d-4b3e-8d28-abe3a20c0fe2','39a0790d-6956-4dbd-81aa-bd02a7039db9','Toner Cartridge — HP Colour','PRINT-001','HP 410X high-yield colour toner set',2,2,18500.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f867fee1-287d-4b3e-8d28-abe3a20c0fe2','39a0790d-6956-4dbd-81aa-bd02a7039db9','Business Card Stock (x500)','MKTG-002','350gsm matte laminated business cards',8,5,2200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f867fee1-287d-4b3e-8d28-abe3a20c0fe2','39a0790d-6956-4dbd-81aa-bd02a7039db9','Tape Measure 30m','TOOL-001','Steel surveying tape with brake',5,3,1850.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f867fee1-287d-4b3e-8d28-abe3a20c0fe2','39a0790d-6956-4dbd-81aa-bd02a7039db9','USB-C Laptop Charger 65W','ELEC-001','Universal USB-C PD charger 65W',3,2,3800.00,true,NOW(),NOW());

-- ------------------------------------------------------------------
-- 6. CEYLON ADVENTURES TOURS  (Tour supplies)
-- ------------------------------------------------------------------
INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
VALUES
  (gen_random_uuid(),'6e2bff01-2eff-456c-b4b9-7bc98464e3f5','9378ca63-fdf1-449e-ac80-f2d7a71ec3e3','Life Jackets — Adult','SAFE-001','CE-approved buoyancy aids, multiple sizes',30,15,4500.00,true,NOW(),NOW()),
  (gen_random_uuid(),'6e2bff01-2eff-456c-b4b9-7bc98464e3f5','9378ca63-fdf1-449e-ac80-f2d7a71ec3e3','Life Jackets — Child','SAFE-002','Children 20–40kg buoyancy vests',12,8,3200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'6e2bff01-2eff-456c-b4b9-7bc98464e3f5','9378ca63-fdf1-449e-ac80-f2d7a71ec3e3','Waterproof Dry Bag 20L','EQUIP-001','Roll-top PVC dry bag for guest belongings',18,10,2100.00,true,NOW(),NOW()),
  (gen_random_uuid(),'6e2bff01-2eff-456c-b4b9-7bc98464e3f5','9378ca63-fdf1-449e-ac80-f2d7a71ec3e3','First Aid Kit — Travel','SAFE-003','Comprehensive 100-item travel first aid kit',6,4,3800.00,true,NOW(),NOW()),
  (gen_random_uuid(),'6e2bff01-2eff-456c-b4b9-7bc98464e3f5','9378ca63-fdf1-449e-ac80-f2d7a71ec3e3','Sunscreen SPF50 100ml','HLTH-001','Reef-safe mineral sunscreen',24,15,450.00,true,NOW(),NOW()),
  (gen_random_uuid(),'6e2bff01-2eff-456c-b4b9-7bc98464e3f5','9378ca63-fdf1-449e-ac80-f2d7a71ec3e3','Tour Guide Headset Set (x10)','TECH-001','Wireless tour guide audio system',2,1,45000.00,true,NOW(),NOW()),
  (gen_random_uuid(),'6e2bff01-2eff-456c-b4b9-7bc98464e3f5','9378ca63-fdf1-449e-ac80-f2d7a71ec3e3','Bottled Water 500ml (x24)','FOOD-001','Elephant House mineral water carton',40,20,960.00,true,NOW(),NOW()),
  (gen_random_uuid(),'6e2bff01-2eff-456c-b4b9-7bc98464e3f5','9378ca63-fdf1-449e-ac80-f2d7a71ec3e3','Insect Repellent Spray 100ml','HLTH-002','DEET-free jungle formula repellent',15,10,380.00,true,NOW(),NOW());

-- ------------------------------------------------------------------
-- 7. QUICKFIX HOME SERVICES  (Maintenance & tools)
-- ------------------------------------------------------------------
INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
VALUES
  (gen_random_uuid(),'894644de-0bf5-4858-a915-5b2e11b1aef8','a21961c3-99af-46ba-8810-f4df49fd7f68','PVC Pipe 1/2 inch (3m length)','PLMB-001','Schedule 40 uPVC water supply pipe',45,20,320.00,true,NOW(),NOW()),
  (gen_random_uuid(),'894644de-0bf5-4858-a915-5b2e11b1aef8','a21961c3-99af-46ba-8810-f4df49fd7f68','Electrical Wire 1.5mm (100m roll)','ELEC-001','3-core copper flex cable, white sheath',8,5,4800.00,true,NOW(),NOW()),
  (gen_random_uuid(),'894644de-0bf5-4858-a915-5b2e11b1aef8','a21961c3-99af-46ba-8810-f4df49fd7f68','Paint — Dulux Weathershield 4L (White)','PAINT-001','Exterior emulsion weather shield',12,6,4200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'894644de-0bf5-4858-a915-5b2e11b1aef8','a21961c3-99af-46ba-8810-f4df49fd7f68','Cement Bag 50kg (Holcim)','CIVI-001','Ordinary Portland cement, OPC 53 grade',0,10,2200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'894644de-0bf5-4858-a915-5b2e11b1aef8','a21961c3-99af-46ba-8810-f4df49fd7f68','Silicon Sealant 310ml (clear)','SEAL-001','Neutral cure silicone for windows & doors',22,12,480.00,true,NOW(),NOW()),
  (gen_random_uuid(),'894644de-0bf5-4858-a915-5b2e11b1aef8','a21961c3-99af-46ba-8810-f4df49fd7f68','Drill Bits Set (x19, HSS)','TOOL-001','High-speed steel drill bit set 1–10mm',6,4,2800.00,true,NOW(),NOW()),
  (gen_random_uuid(),'894644de-0bf5-4858-a915-5b2e11b1aef8','a21961c3-99af-46ba-8810-f4df49fd7f68','Safety Helmets (yellow)','PPE-001','ABS hard hat ANSI Z89.1 Class E',10,6,1200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'894644de-0bf5-4858-a915-5b2e11b1aef8','a21961c3-99af-46ba-8810-f4df49fd7f68','Tile Adhesive 20kg (grey)','CIVI-002','Polymer-modified floor & wall tile glue',7,8,1650.00,true,NOW(),NOW()),
  (gen_random_uuid(),'894644de-0bf5-4858-a915-5b2e11b1aef8','a21961c3-99af-46ba-8810-f4df49fd7f68','Cable Ties Assorted (x200)','ELEC-002','Nylon zip ties, 3 sizes mixed bag',30,20,280.00,true,NOW(),NOW()),
  (gen_random_uuid(),'894644de-0bf5-4858-a915-5b2e11b1aef8','a21961c3-99af-46ba-8810-f4df49fd7f68','Waterproofing Paint 4L','PAINT-002','Bitumen-based damp-proof membrane paint',5,4,3800.00,true,NOW(),NOW());

-- ------------------------------------------------------------------
-- 8. HASARANGA MULTI-SERVICES LANKA  (General office & services)
-- ------------------------------------------------------------------
INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
VALUES
  (gen_random_uuid(),'a5b97efc-e09d-403b-b116-0b01320bfbc1','c6df2b1a-d960-4ad1-b050-b7212121de74','A4 Paper Ream 80gsm','STAT-001','Premium white copier paper 500 sheets',48,20,680.00,true,NOW(),NOW()),
  (gen_random_uuid(),'a5b97efc-e09d-403b-b116-0b01320bfbc1','c6df2b1a-d960-4ad1-b050-b7212121de74','Laptop — Dell Latitude 5530','IT-001','Intel i5 12th gen, 16GB RAM, 512GB SSD',2,1,185000.00,true,NOW(),NOW()),
  (gen_random_uuid(),'a5b97efc-e09d-403b-b116-0b01320bfbc1','c6df2b1a-d960-4ad1-b050-b7212121de74','Toner Cartridge — HP LaserJet','PRINT-001','HP 17A black toner compatible',4,3,4200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'a5b97efc-e09d-403b-b116-0b01320bfbc1','c6df2b1a-d960-4ad1-b050-b7212121de74','USB Flash Drive 32GB (x5 pack)','IT-002','SanDisk Cruzer Blade, USB 2.0',10,6,2250.00,true,NOW(),NOW()),
  (gen_random_uuid(),'a5b97efc-e09d-403b-b116-0b01320bfbc1','c6df2b1a-d960-4ad1-b050-b7212121de74','Whiteboard Markers (x12 set)','STAT-002','Assorted dry-erase markers',8,5,480.00,true,NOW(),NOW()),
  (gen_random_uuid(),'a5b97efc-e09d-403b-b116-0b01320bfbc1','c6df2b1a-d960-4ad1-b050-b7212121de74','Bottled Water 1L (x12 pack)','PROV-001','Kelani Valley natural mineral water',20,10,960.00,true,NOW(),NOW()),
  (gen_random_uuid(),'a5b97efc-e09d-403b-b116-0b01320bfbc1','c6df2b1a-d960-4ad1-b050-b7212121de74','Business Cards (x500)','MKTG-001','350gsm matte laminated, full colour',3,5,3500.00,true,NOW(),NOW()),
  (gen_random_uuid(),'a5b97efc-e09d-403b-b116-0b01320bfbc1','c6df2b1a-d960-4ad1-b050-b7212121de74','Filing Cabinet — 4-drawer','FURN-001','Steel A4 lateral filing cabinet, grey',1,1,28000.00,true,NOW(),NOW());

-- ------------------------------------------------------------------
-- 9. MALKEY RENT A CAR  (Vehicle & fleet supplies)
-- ------------------------------------------------------------------
INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
VALUES
  (gen_random_uuid(),'91d422e3-ee0b-48a5-a54a-8c6bf135c387','7f2e7e31-3e32-470c-8f6d-614acfe17282','Motor Oil SAE 5W-30 4L','AUTO-001','Synthetic engine oil for Japanese vehicles',18,10,2800.00,true,NOW(),NOW()),
  (gen_random_uuid(),'91d422e3-ee0b-48a5-a54a-8c6bf135c387','7f2e7e31-3e32-470c-8f6d-614acfe17282','Oil Filter — Toyota Corolla','AUTO-002','Genuine Toyota oil filter 90915-YZZD2',12,8,850.00,true,NOW(),NOW()),
  (gen_random_uuid(),'91d422e3-ee0b-48a5-a54a-8c6bf135c387','7f2e7e31-3e32-470c-8f6d-614acfe17282','Tyre Inflator 12V','AUTO-003','Portable digital tyre pump with pressure gauge',4,3,3500.00,true,NOW(),NOW()),
  (gen_random_uuid(),'91d422e3-ee0b-48a5-a54a-8c6bf135c387','7f2e7e31-3e32-470c-8f6d-614acfe17282','Car Air Freshener (x12)','AUTO-004','Assorted scents — vanilla, citrus, fresh linen',36,20,180.00,true,NOW(),NOW()),
  (gen_random_uuid(),'91d422e3-ee0b-48a5-a54a-8c6bf135c387','7f2e7e31-3e32-470c-8f6d-614acfe17282','Windshield Wiper Blades 24"','AUTO-005','Universal fit frameless wiper blades',8,6,650.00,true,NOW(),NOW()),
  (gen_random_uuid(),'91d422e3-ee0b-48a5-a54a-8c6bf135c387','7f2e7e31-3e32-470c-8f6d-614acfe17282','Car Washing Sponge & Cloth Set','AUTO-006','Microfibre wash mitt and drying towel set',15,10,380.00,true,NOW(),NOW()),
  (gen_random_uuid(),'91d422e3-ee0b-48a5-a54a-8c6bf135c387','7f2e7e31-3e32-470c-8f6d-614acfe17282','Jump Starter Powerbank 12V','AUTO-007','Peak 1000A lithium jump starter with USB',2,2,14500.00,true,NOW(),NOW()),
  (gen_random_uuid(),'91d422e3-ee0b-48a5-a54a-8c6bf135c387','7f2e7e31-3e32-470c-8f6d-614acfe17282','Rental Agreement Forms (x100)','ADMIN-001','Printed vehicle rental contract booklets',6,5,1800.00,true,NOW(),NOW());

-- ------------------------------------------------------------------
-- 10. MIRISSA JETLINER WHALE WATCHING  (Marine & boat supplies)
-- ------------------------------------------------------------------
INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
VALUES
  (gen_random_uuid(),'f295189f-4992-4388-94fb-3e3efe04d609','c3e5ec50-5c95-4939-9c64-10f823ac8599','Life Jackets — Adult ISO 395','SAFE-001','SOLAS-approved inflatable life jackets',45,20,8500.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f295189f-4992-4388-94fb-3e3efe04d609','c3e5ec50-5c95-4939-9c64-10f823ac8599','Life Jackets — Child','SAFE-002','Child sizes 15–40kg buoyancy vest',10,8,4200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f295189f-4992-4388-94fb-3e3efe04d609','c3e5ec50-5c95-4939-9c64-10f823ac8599','Marine Binoculars 10×42','EQUIP-001','Waterproof 10×42 marine binoculars',6,4,12000.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f295189f-4992-4388-94fb-3e3efe04d609','c3e5ec50-5c95-4939-9c64-10f823ac8599','Seasickness Tablets (x100)','MED-001','Meclizine 25mg anti-nausea tablets',8,5,1200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f295189f-4992-4388-94fb-3e3efe04d609','c3e5ec50-5c95-4939-9c64-10f823ac8599','Sunscreen SPF50 100ml','HLTH-001','Reef-safe mineral sunscreen sachets',60,30,350.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f295189f-4992-4388-94fb-3e3efe04d609','c3e5ec50-5c95-4939-9c64-10f823ac8599','Bottled Water 500ml (x24)','PROV-001','Elephant House mineral water carton',25,15,960.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f295189f-4992-4388-94fb-3e3efe04d609','c3e5ec50-5c95-4939-9c64-10f823ac8599','Engine Oil — Marine 2-Stroke','MAINT-001','2-stroke outboard engine oil 1L',12,6,2400.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f295189f-4992-4388-94fb-3e3efe04d609','c3e5ec50-5c95-4939-9c64-10f823ac8599','Flare Kit — Emergency','SAFE-003','SOLAS approved distress signal flare set',5,3,18000.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f295189f-4992-4388-94fb-3e3efe04d609','c3e5ec50-5c95-4939-9c64-10f823ac8599','First Aid Kit — Marine','SAFE-004','DAN marine first aid kit, 100 items',4,3,8500.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f295189f-4992-4388-94fb-3e3efe04d609','c3e5ec50-5c95-4939-9c64-10f823ac8599','Ticket Receipt Book (x2 pad)','ADMIN-001','50-page carbon copy boat ticket pads',3,5,480.00,true,NOW(),NOW());

-- ------------------------------------------------------------------
-- 11. THE WALLAWWA  (Boutique hotel — amenities)
-- ------------------------------------------------------------------
INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
VALUES
  (gen_random_uuid(),'f163610e-fb88-4aae-bf1d-7ce0d7a47b25','1e04a2e0-3d8e-4f53-b1e7-3ad6495a9589','Bath Towels — Premium (each)','LINEN-001','600gsm Egyptian cotton bath towels',80,30,2400.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f163610e-fb88-4aae-bf1d-7ce0d7a47b25','1e04a2e0-3d8e-4f53-b1e7-3ad6495a9589','Bed Sheets — King Size Set','LINEN-002','400TC percale cotton, white',22,10,6500.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f163610e-fb88-4aae-bf1d-7ce0d7a47b25','1e04a2e0-3d8e-4f53-b1e7-3ad6495a9589','Guest Amenity Kit (shampoo/soap)','AMEN-001','Lemongrass & coconut hotel amenity set',120,60,380.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f163610e-fb88-4aae-bf1d-7ce0d7a47b25','1e04a2e0-3d8e-4f53-b1e7-3ad6495a9589','Coffee Capsules — Nespresso (x50)','FOOD-001','Illy Intenso Nespresso-compatible capsules',18,10,2800.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f163610e-fb88-4aae-bf1d-7ce0d7a47b25','1e04a2e0-3d8e-4f53-b1e7-3ad6495a9589','Ceylon Tea — Premium 100g','FOOD-002','Dilmah single origin loose-leaf tea',30,15,580.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f163610e-fb88-4aae-bf1d-7ce0d7a47b25','1e04a2e0-3d8e-4f53-b1e7-3ad6495a9589','Pool Towels (each)','LINEN-003','Striped pool/beach towels, 70×140cm',45,20,1800.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f163610e-fb88-4aae-bf1d-7ce0d7a47b25','1e04a2e0-3d8e-4f53-b1e7-3ad6495a9589','Mini Bar — Soft Drinks (x24 can)','FOOD-003','Coca-Cola, Fanta, Sprite assorted 330ml',8,6,1440.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f163610e-fb88-4aae-bf1d-7ce0d7a47b25','1e04a2e0-3d8e-4f53-b1e7-3ad6495a9589','Laundry Detergent 5kg','HOUSE-001','Commercial grade front-load laundry powder',4,3,3200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'f163610e-fb88-4aae-bf1d-7ce0d7a47b25','1e04a2e0-3d8e-4f53-b1e7-3ad6495a9589','DEET Mosquito Repellent 100ml','AMEN-002','Tropical strength, guest room amenity',90,40,280.00,true,NOW(),NOW());

-- ------------------------------------------------------------------
-- 12. WELIGAMA BAY DIVE CENTER  (Diving equipment & supplies)
-- ------------------------------------------------------------------
INSERT INTO "InventoryItems"
  ("Id","TenantId","BranchId","Name","Sku","Description","Quantity","ReorderLevel","UnitCost","IsActive","CreatedAt","UpdatedAt")
VALUES
  (gen_random_uuid(),'772c8068-e0e6-4d5e-a58a-e097cfd3c85f','4bbbd410-2780-4966-9f85-53455651bf8b','Scuba Mask — Adult','EQUIP-001','Tempered glass wide-view dive mask',18,10,4500.00,true,NOW(),NOW()),
  (gen_random_uuid(),'772c8068-e0e6-4d5e-a58a-e097cfd3c85f','4bbbd410-2780-4966-9f85-53455651bf8b','Scuba Fins — Adjustable','EQUIP-002','Open-heel adjustable dive fins, S/M/L',20,12,6200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'772c8068-e0e6-4d5e-a58a-e097cfd3c85f','4bbbd410-2780-4966-9f85-53455651bf8b','3mm Wetsuit — Full Body (S)','SUIT-001','3mm neoprene, warm-water dive suit',8,5,12000.00,true,NOW(),NOW()),
  (gen_random_uuid(),'772c8068-e0e6-4d5e-a58a-e097cfd3c85f','4bbbd410-2780-4966-9f85-53455651bf8b','3mm Wetsuit — Full Body (M)','SUIT-002','3mm neoprene, warm-water dive suit',10,6,12000.00,true,NOW(),NOW()),
  (gen_random_uuid(),'772c8068-e0e6-4d5e-a58a-e097cfd3c85f','4bbbd410-2780-4966-9f85-53455651bf8b','3mm Wetsuit — Full Body (L)','SUIT-003','3mm neoprene, warm-water dive suit',6,4,12000.00,true,NOW(),NOW()),
  (gen_random_uuid(),'772c8068-e0e6-4d5e-a58a-e097cfd3c85f','4bbbd410-2780-4966-9f85-53455651bf8b','Scuba Tank 12L Steel (Al80)','EQUIP-003','Aluminium 80 cu ft dive cylinder, valve included',14,8,45000.00,true,NOW(),NOW()),
  (gen_random_uuid(),'772c8068-e0e6-4d5e-a58a-e097cfd3c85f','4bbbd410-2780-4966-9f85-53455651bf8b','Regulator — Aqualung Mikron','EQUIP-004','Dive regulator first + second stage set',6,4,38000.00,true,NOW(),NOW()),
  (gen_random_uuid(),'772c8068-e0e6-4d5e-a58a-e097cfd3c85f','4bbbd410-2780-4966-9f85-53455651bf8b','Weight Belt — Lead 4kg','EQUIP-005','Nylon weight belt with quick-release buckle',12,8,3200.00,true,NOW(),NOW()),
  (gen_random_uuid(),'772c8068-e0e6-4d5e-a58a-e097cfd3c85f','4bbbd410-2780-4966-9f85-53455651bf8b','Reef-Safe Sunscreen SPF50 100ml','HLTH-001','Mineral zinc-oxide sunscreen for divers',36,20,480.00,true,NOW(),NOW()),
  (gen_random_uuid(),'772c8068-e0e6-4d5e-a58a-e097cfd3c85f','4bbbd410-2780-4966-9f85-53455651bf8b','PADI Open Water Course Manual','TRAIN-001','Official PADI OWD student manual + slate',5,4,8500.00,true,NOW(),NOW());

-- =============================================================
-- Add some stock movements (recent receives) for realism
-- =============================================================
-- Colombo Clinic received surgical gloves last week
INSERT INTO "StockMovements"
  ("Id","InventoryItemId","BranchId","MovementType","Quantity","Reference","OccurredAt")
SELECT
  gen_random_uuid(),
  i."Id",
  i."BranchId",
  'Receive',
  50,
  'PO-CLINIC-2026-01',
  NOW() - INTERVAL '5 days'
FROM "InventoryItems" i
WHERE i."TenantId" = 'c23aac1b-13ba-4763-b589-e0cfd2ec97f4' AND i."Sku" = 'SURG-001';

-- Spice Garden received chicken fillet
INSERT INTO "StockMovements"
  ("Id","InventoryItemId","BranchId","MovementType","Quantity","Reference","OccurredAt")
SELECT
  gen_random_uuid(),
  i."Id",
  i."BranchId",
  'Receive',
  40,
  'PO-SPICE-2026-01',
  NOW() - INTERVAL '2 days'
FROM "InventoryItems" i
WHERE i."TenantId" = '32bf0ffe-9271-42a3-8b5d-40a8b24f9967' AND i."Sku" = 'PROT-001';

-- QuickFix used cement (out of stock adjustment)
INSERT INTO "StockMovements"
  ("Id","InventoryItemId","BranchId","MovementType","Quantity","Reference","OccurredAt")
SELECT
  gen_random_uuid(),
  i."Id",
  i."BranchId",
  'Sale',
  -15,
  'JOB-QF-2026-044',
  NOW() - INTERVAL '1 day'
FROM "InventoryItems" i
WHERE i."TenantId" = '894644de-0bf5-4858-a915-5b2e11b1aef8' AND i."Sku" = 'CIVI-001';

-- Wallawwa received guest amenity kits
INSERT INTO "StockMovements"
  ("Id","InventoryItemId","BranchId","MovementType","Quantity","Reference","OccurredAt")
SELECT
  gen_random_uuid(),
  i."Id",
  i."BranchId",
  'Receive',
  120,
  'PO-WALL-2026-07',
  NOW() - INTERVAL '3 days'
FROM "InventoryItems" i
WHERE i."TenantId" = 'f163610e-fb88-4aae-bf1d-7ce0d7a47b25' AND i."Sku" = 'AMEN-001';

-- Whale Watch received life jackets
INSERT INTO "StockMovements"
  ("Id","InventoryItemId","BranchId","MovementType","Quantity","Reference","OccurredAt")
SELECT
  gen_random_uuid(),
  i."Id",
  i."BranchId",
  'Receive',
  10,
  'PO-MW-2026-03',
  NOW() - INTERVAL '7 days'
FROM "InventoryItems" i
WHERE i."TenantId" = 'f295189f-4992-4388-94fb-3e3efe04d609' AND i."Sku" = 'SAFE-001';

SELECT 'Inventory seed complete.' as status;
SELECT t."Name" as tenant, COUNT(i."Id") as items
FROM "Tenants" t
LEFT JOIN "InventoryItems" i ON i."TenantId" = t."Id" AND i."IsActive" = true
GROUP BY t."Id", t."Name"
ORDER BY items DESC, t."Name";

