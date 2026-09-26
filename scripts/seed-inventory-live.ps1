param(
    [string]$BaseUrl = "https://sef-project-production.up.railway.app/api"
)

$ErrorActionPreference = "Stop"

function Invoke-Api {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body,
        [string]$Token
    )
    $headers = @{}
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }
    $params = @{
        Method  = $Method
        Uri     = "$BaseUrl$Path"
        Headers = $headers
    }
    if ($Body) {
        $params["Body"] = ($Body | ConvertTo-Json -Depth 6)
        $params["ContentType"] = "application/json"
    }
    return Invoke-RestMethod @params
}

$inventories = @(
    @{
        Email = "admin@colombofamilyclinic.lk"
        Items = @(
            @{ Name = "Paracetamol 500mg (x100 tabs)"; Sku = "PHARM-001"; Description = "Standard paracetamol analgesic strip pack"; Quantity = 180; ReorderLevel = 50; UnitCost = 245.00 }
            @{ Name = "Surgical Gloves - Medium (box/100)"; Sku = "SURG-001"; Description = "Latex examination gloves, sterile"; Quantity = 42; ReorderLevel = 20; UnitCost = 875.00 }
            @{ Name = "Surgical Gloves - Large (box/100)"; Sku = "SURG-002"; Description = "Latex examination gloves, sterile"; Quantity = 30; ReorderLevel = 20; UnitCost = 875.00 }
            @{ Name = "3M Surgical Mask (box/50)"; Sku = "PPE-001"; Description = "Type IIR surgical masks, CE certified"; Quantity = 96; ReorderLevel = 40; UnitCost = 1250.00 }
            @{ Name = "Saline Solution 500ml"; Sku = "MED-001"; Description = "Normal saline 0.9% IV infusion bags"; Quantity = 55; ReorderLevel = 30; UnitCost = 380.00 }
            @{ Name = "Blood Glucose Test Strips (x50)"; Sku = "DIAG-001"; Description = "Compatible with Accu-Chek Active meter"; Quantity = 14; ReorderLevel = 25; UnitCost = 1850.00 }
            @{ Name = "Disposable Syringes 5ml (x100)"; Sku = "SURG-003"; Description = "Single-use Luer-lock syringes"; Quantity = 72; ReorderLevel = 50; UnitCost = 640.00 }
            @{ Name = "Alcohol-Based Hand Sanitiser 500ml"; Sku = "HYG-001"; Description = "70% isopropyl alcohol gel"; Quantity = 28; ReorderLevel = 15; UnitCost = 320.00 }
            @{ Name = "Digital Thermometer"; Sku = "DIAG-002"; Description = "Non-contact infrared, Celsius display"; Quantity = 8; ReorderLevel = 5; UnitCost = 2450.00 }
        )
    },
    @{
        Email = "admin@spicegarden.lk"
        Items = @(
            @{ Name = "Basmati Rice 50kg"; Sku = "RICE-001"; Description = "Premium long-grain basmati rice sack"; Quantity = 12; ReorderLevel = 5; UnitCost = 9800.00 }
            @{ Name = "Ceylon Coconut Milk 400ml (x12 cans)"; Sku = "CONS-001"; Description = "First-pressed coconut milk, Dilmah"; Quantity = 24; ReorderLevel = 10; UnitCost = 2640.00 }
            @{ Name = "Ceylon Cinnamon Sticks 500g"; Sku = "SPICE-001"; Description = "True Ceylon cinnamon, Grade C5"; Quantity = 6; ReorderLevel = 5; UnitCost = 1850.00 }
            @{ Name = "Cooking Oil - Sunflower 5L"; Sku = "OIL-001"; Description = "Refined sunflower cooking oil"; Quantity = 15; ReorderLevel = 8; UnitCost = 2200.00 }
            @{ Name = "Chicken Fillet 1kg (frozen)"; Sku = "PROT-001"; Description = "Boneless chicken breast, IQF frozen"; Quantity = 40; ReorderLevel = 20; UnitCost = 1350.00 }
            @{ Name = "Prawns Large (1kg frozen)"; Sku = "PROT-002"; Description = "Tiger prawns 16/20 size, IQF"; Quantity = 18; ReorderLevel = 10; UnitCost = 2800.00 }
            @{ Name = "Curry Leaves Fresh (500g)"; Sku = "HERB-001"; Description = "Fresh organic curry leaves, Colombo market"; Quantity = 3; ReorderLevel = 5; UnitCost = 180.00 }
            @{ Name = "Takeaway Boxes - Large (x100)"; Sku = "PACK-001"; Description = "Eco-friendly kraft paper containers"; Quantity = 4; ReorderLevel = 10; UnitCost = 1400.00 }
            @{ Name = "LPG Cylinder 12.5kg"; Sku = "GAS-001"; Description = "Commercial cooking gas cylinder"; Quantity = 3; ReorderLevel = 2; UnitCost = 3800.00 }
        )
    },
    @{
        Email = "admin@powerhousefitness.lk"
        Items = @(
            @{ Name = "Protein Supplement - Whey 1kg"; Sku = "SUPP-001"; Description = "Unflavoured whey protein isolate"; Quantity = 22; ReorderLevel = 10; UnitCost = 8900.00 }
            @{ Name = "Resistance Band Set"; Sku = "EQUIP-001"; Description = "Latex loop bands with carry bag"; Quantity = 14; ReorderLevel = 8; UnitCost = 1850.00 }
            @{ Name = "Foam Roller 60cm"; Sku = "EQUIP-002"; Description = "High-density EVA foam roller"; Quantity = 9; ReorderLevel = 6; UnitCost = 2400.00 }
            @{ Name = "Gym Towel - Microfibre (x10)"; Sku = "LINEN-001"; Description = "Quick-dry 50x100cm gym towels"; Quantity = 35; ReorderLevel = 20; UnitCost = 3200.00 }
            @{ Name = "Sanitiser Spray 1L"; Sku = "HYG-001"; Description = "Equipment disinfectant spray bottle"; Quantity = 7; ReorderLevel = 5; UnitCost = 580.00 }
            @{ Name = "Dumbbells 5kg (pair)"; Sku = "EQUIP-003"; Description = "Cast iron hex dumbbells, rubber coated"; Quantity = 6; ReorderLevel = 4; UnitCost = 7500.00 }
            @{ Name = "Yoga Mat 6mm"; Sku = "EQUIP-004"; Description = "Non-slip TPE exercise mat, 183x61cm"; Quantity = 12; ReorderLevel = 8; UnitCost = 3200.00 }
            @{ Name = "Isotonic Sports Drink Mix 1kg"; Sku = "SUPP-002"; Description = "Electrolyte powder - lemon flavour"; Quantity = 5; ReorderLevel = 8; UnitCost = 4200.00 }
        )
    },
    @{
        Email = "admin@quickfixservices.lk"
        Items = @(
            @{ Name = "PVC Pipe 1/2 inch (3m length)"; Sku = "PLMB-001"; Description = "Schedule 40 uPVC water supply pipe"; Quantity = 45; ReorderLevel = 20; UnitCost = 320.00 }
            @{ Name = "Electrical Wire 1.5mm (100m roll)"; Sku = "ELEC-001"; Description = "3-core copper flex cable, white sheath"; Quantity = 8; ReorderLevel = 5; UnitCost = 4800.00 }
            @{ Name = "Paint - Dulux Weathershield 4L"; Sku = "PAINT-001"; Description = "Exterior emulsion weather shield"; Quantity = 12; ReorderLevel = 6; UnitCost = 4200.00 }
            @{ Name = "Cement Bag 50kg (Holcim)"; Sku = "CIVI-001"; Description = "Ordinary Portland cement, OPC 53 grade"; Quantity = 25; ReorderLevel = 10; UnitCost = 2200.00 }
            @{ Name = "Silicon Sealant 310ml (clear)"; Sku = "SEAL-001"; Description = "Neutral cure silicone for windows and doors"; Quantity = 22; ReorderLevel = 12; UnitCost = 480.00 }
            @{ Name = "Drill Bits Set (x19, HSS)"; Sku = "TOOL-001"; Description = "High-speed steel drill bit set 1-10mm"; Quantity = 6; ReorderLevel = 4; UnitCost = 2800.00 }
            @{ Name = "Safety Helmets (yellow)"; Sku = "PPE-001"; Description = "ABS hard hat ANSI Z89.1 Class E"; Quantity = 10; ReorderLevel = 6; UnitCost = 1200.00 }
        )
    },
    @{
        Email = "admin@ceylonadventures.lk"
        Items = @(
            @{ Name = "Life Jackets - Adult"; Sku = "SAFE-001"; Description = "CE-approved buoyancy aids, multiple sizes"; Quantity = 30; ReorderLevel = 15; UnitCost = 4500.00 }
            @{ Name = "Life Jackets - Child"; Sku = "SAFE-002"; Description = "Children 20-40kg buoyancy vests"; Quantity = 12; ReorderLevel = 8; UnitCost = 3200.00 }
            @{ Name = "Waterproof Dry Bag 20L"; Sku = "EQUIP-001"; Description = "Roll-top PVC dry bag for guest belongings"; Quantity = 18; ReorderLevel = 10; UnitCost = 2100.00 }
            @{ Name = "First Aid Kit - Travel"; Sku = "SAFE-003"; Description = "Comprehensive 100-item travel first aid kit"; Quantity = 6; ReorderLevel = 4; UnitCost = 3800.00 }
            @{ Name = "Sunscreen SPF50 100ml"; Sku = "HLTH-001"; Description = "Reef-safe mineral sunscreen"; Quantity = 24; ReorderLevel = 15; UnitCost = 450.00 }
        )
    }
)

Write-Host "Seeding live inventory for Sri Lankan businesses..." -ForegroundColor Cyan

foreach ($group in $inventories) {
    Write-Host "Logging in as $($group.Email)..." -ForegroundColor Yellow
    try {
        $login = Invoke-Api -Method POST -Path "/auth/login" -Body @{ email = $group.Email; password = "Demo@12345" }
        $token = $login.accessToken
        $branchId = $login.user.branchId

        foreach ($item in $group.Items) {
            $itemBody = @{
                name = $item.Name
                sku = $item.Sku
                description = $item.Description
                quantity = [decimal]$item.Quantity
                reorderLevel = [decimal]$item.ReorderLevel
                unitCost = [decimal]$item.UnitCost
                branchId = $branchId
            }
            try {
                $created = Invoke-Api -Method POST -Path "/inventory" -Body $itemBody -Token $token
                Write-Host "  + Added: $($item.Name) (Qty: $($item.Quantity), Cost: LKR $($item.UnitCost))" -ForegroundColor Green
            } catch {
                Write-Host "  . Exists or skipped: $($item.Name)" -ForegroundColor DarkGray
            }
        }
    } catch {
        Write-Warning "Could not log in as $($group.Email): $_"
    }
}

Write-Host "Done seeding inventory items!" -ForegroundColor Cyan

