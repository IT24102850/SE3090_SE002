<#
.SYNOPSIS
  Seeds one real business - Mirissa Jetliner (whale watching boat tours,
  Mirissa Harbour, Sri Lanka) - with real resources/schedule/booking types
  sourced from https://www.mirissajetliner.com/, via the same public API
  the apps use (POST /tenant/onboard, /resources, /resources/{id}/schedule,
  /bookingtypes). This creates a brand new tenant; it does not touch the
  older duplicate/junk "Mirissa JetLiner" test tenants already in the DB -
  those should be removed separately (see the Supabase cleanup query).

.PARAMETER BaseUrl
  Backend API base URL. Defaults to http://localhost:5298/api - make sure
  `dotnet run` is up in backend/SmeBackend first.

.EXAMPLE
  ./scripts/seed-mirissa-jetliner.ps1
#>
param(
    [string]$BaseUrl = "http://localhost:5298/api",
    # Overridable because this database already carries older duplicate
    # "Mirissa JetLiner" test tenants sharing the default address; login
    # resolves whichever user row matches first, so a re-run needs a fresh
    # address to be reachable.
    [string]$AdminEmail = "wowwhales@gmail.com"
)

$ErrorActionPreference = "Stop"

function Invoke-Api {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body,
        [string]$Token,
        # Departure creation is idempotent by (vessel, time) and answers 409
        # on a re-run; -IgnoreErrors lets the caller treat that as a no-op
        # instead of aborting the seed.
        [switch]$IgnoreErrors
    )
    $uri = "$BaseUrl$Path"
    $headers = @{}
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }

    $params = @{
        Method  = $Method
        Uri     = $uri
        Headers = $headers
    }
    if ($Body) {
        $params["Body"] = ($Body | ConvertTo-Json -Depth 8)
        $params["ContentType"] = "application/json"
    }

    try {
        return Invoke-RestMethod @params
    }
    catch {
        $respBody = $null
        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $respBody = $reader.ReadToEnd()
            } catch {}
        }
        if ($IgnoreErrors) {
            Write-Verbose "  $Method $Path failed (ignored): $respBody"
            return $null
        }
        Write-Warning "  $Method $Path failed: $($_.Exception.Message) $respBody"
        throw
    }
}

function New-WeeklySchedule {
    param([int[]]$OpenDays, [string]$StartTime, [string]$EndTime)
    $days = @()
    for ($d = 0; $d -le 6; $d++) {
        $days += @{
            dayOfWeek   = $d
            startTime   = $StartTime
            endTime     = $EndTime
            isAvailable = $OpenDays -contains $d
        }
    }
    return @{ days = $days }
}

$EveryDay = @(0, 1, 2, 3, 4, 5, 6)

Write-Host "Seeding Mirissa Jetliner against $BaseUrl ...`n" -ForegroundColor Cyan

$onboardBody = @{
    businessName  = "Mirissa Jetliner"
    businessType  = "Tourism"
    address       = "Mirissa Harbour, Mirissa, Sri Lanka"
    phone         = "+94777728439"
    adminEmail    = $AdminEmail
    adminPassword = "Demo@12345"
    adminFullName = "Mirissa Jetliner Admin"
    adminPhone    = "+94777728439"
}

$onboard  = Invoke-Api -Method POST -Path "/tenant/onboard" -Body $onboardBody
$token    = $onboard.accessToken
$tenantId = $onboard.user.tenantId
$branchId = $onboard.user.branchId
Write-Host "Tenant created: $tenantId (admin: $AdminEmail / Demo@12345)"

# The exact TOURISM_SUB_TYPES string. Without it the tenant renders the
# generic calendar dashboard rather than the departure board.
Invoke-Api -Method PUT -Path "/tenant" -Token $token -Body @{
    subType = "Whale / dolphin watching"
} | Out-Null
Write-Host "  + SubType: Whale / dolphin watching"

# Real ticket pricing/inclusions from the live booking page (book-now):
# Adult LKR 7500, Child LKR 4000, both include breakfast/refreshments/
# life jacket/insurance/WiFi. Capacity 120 passengers per sailing.
$customAttrs = @{
    capacity    = 120
    adultPrice  = 7500
    childPrice  = 4000
    includes    = "breakfast, refreshments, life jacket, insurance, WiFi"
} | ConvertTo-Json -Compress

$resources = @(
    @{ Name = "Whale Watching Boat - Dawn Departure";   Departure = "06:30:00"; End = "10:30:00"; Id = $null }
    @{ Name = "Whale Watching Boat - Morning Cruise";   Departure = "10:00:00"; End = "14:00:00"; Id = $null }
)

foreach ($res in $resources) {
    $resourceBody = @{
        tenantId         = $tenantId
        branchId         = $branchId
        name             = $res.Name
        category         = "Vehicle"
        specialty        = "Whale and Dolphin Watching"
        hourlyRate       = 7500
        customAttributes = $customAttrs
    }
    $created = Invoke-Api -Method POST -Path "/resources" -Body $resourceBody -Token $token
    Write-Host "  + Resource: $($res.Name)"

    $scheduleBody = New-WeeklySchedule -OpenDays $EveryDay -StartTime $res.Departure -EndTime $res.End
    Invoke-Api -Method PUT -Path "/resources/$($created.id)/schedule" -Body $scheduleBody -Token $token | Out-Null

    $res.Id = $created.id
}

# ── Product catalogue ────────────────────────────────────────────────
# ConfigJson carries `category` (tour | package | addon) alongside the
# existing subType/pricing keys - see docs/tourism-business-template.md.
# The admin dashboard splits Packages & Tours from Services & Add-ons on it;
# a product with no category is treated as a tour, so nothing that predates
# the key disappears from the operator's view.
$season = @{ months = @("Nov","Dec","Jan","Feb","Mar","Apr"); weatherDependent = $true }

$products = @(
    @{
        Name = "Whale Watching Tour"; Colour = "#0891B2"; Duration = 240; MaxPax = 120
        Config = @{ subType = "whaleWatching"; category = "tour"; bookingUnit = "Slot"
                    capacity = 120; season = $season
                    pricing = @{ adult = 7500; child = 4000; infant = 0; currency = "LKR" } }
    }
    @{
        Name = "Sunset Dolphin Cruise"; Colour = "#F59E0B"; Duration = 150; MaxPax = 120
        Config = @{ subType = "whaleWatching"; category = "tour"; bookingUnit = "Slot"
                    capacity = 120; season = $season
                    pricing = @{ adult = 5500; child = 3000; infant = 0; currency = "LKR" } }
    }
    @{
        Name = "Whale Tour + Lunch + Hotel Transfer"; Colour = "#8B5CF6"; Duration = 360; MaxPax = 40
        Config = @{ subType = "whaleWatching"; category = "package"; bookingUnit = "Package"
                    capacity = 40; season = $season
                    pricing = @{ adult = 11500; child = 6500; infant = 0; currency = "LKR" } }
    }
    @{
        Name = "Hotel Pickup & Drop-off"; Colour = "#10B981"; Duration = 60; MaxPax = 12
        Config = @{ subType = "whaleWatching"; category = "addon"; bookingUnit = "Slot"
                    pricing = @{ adult = 1500; currency = "LKR" } }
    }
    @{
        Name = "Photo Package"; Colour = "#EC4899"; Duration = 30; MaxPax = 120
        Config = @{ subType = "whaleWatching"; category = "addon"; bookingUnit = "Slot"
                    pricing = @{ adult = 2500; currency = "LKR" } }
    }
    @{
        Name = "Snorkel Gear Rental"; Colour = "#06B6D4"; Duration = 240; MaxPax = 40
        Config = @{ subType = "whaleWatching"; category = "addon"; bookingUnit = "Slot"
                    pricing = @{ adult = 1200; currency = "LKR" } }
    }
)

$tourTypeId = $null
foreach ($product in $products) {
    $btBody = @{
        tenantId               = $tenantId
        name                   = $product.Name
        colorHex               = $product.Colour
        defaultDurationMinutes = $product.Duration
        requiresApproval       = ($product.Config.category -eq "package")
        maxParticipants        = $product.MaxPax
        bookingUnit            = $product.Config.bookingUnit
        configJson             = ($product.Config | ConvertTo-Json -Depth 8 -Compress)
    }
    $createdType = Invoke-Api -Method POST -Path "/bookingtypes" -Body $btBody -Token $token
    if (-not $tourTypeId -and $product.Config.category -eq "tour") { $tourTypeId = $createdType.id }
    Write-Host "  + $($product.Config.category): $($product.Name) ($($product.Duration) min)"
}

# ── Departures + sightings for the success-rate KPI ──────────────────
# Sightings hang off departures, and the success rate is departures-with-a-
# sighting over departures that sailed - so past departures have to exist
# before there is anything to divide by.
$speciesPool = @(
    "BlueWhale","BlueWhale","BlueWhale","SpermWhale","BrydesWhale",
    "SpinnerDolphin","SpinnerDolphin","BottlenoseDolphin","RissoDolphin",
    "Turtle","HumpbackWhale","FinWhale","KillerWhale","SpinnerDolphin",
    "BlueWhale","BrydesWhale","Turtle","BottlenoseDolphin"
)
$behaviours = @("Breaching","Spyhopping","TailSlapping","PodSwimming","Feeding","Resting")
$rng = [System.Random]::new(310872)
$today = (Get-Date).Date

$departureIds = @()
for ($dayOffset = -30; $dayOffset -le 3; $dayOffset++) {
    $day = $today.AddDays($dayOffset)
    foreach ($res in $resources) {
        if (-not $res.Id) { continue }
        $depart = $day.Add([TimeSpan]::Parse($res.Departure))
        $created = Invoke-Api -Method POST -Path "/departures" -Token $token -IgnoreErrors -Body @{
            resourceId         = $res.Id
            bookingTypeId      = $tourTypeId
            scheduledDeparture = $depart.ToUniversalTime().ToString("o")
            scheduledReturn    = $day.Add([TimeSpan]::Parse($res.End)).ToUniversalTime().ToString("o")
        }
        if ($created) { $departureIds += @{ Id = $created.id; Past = ($dayOffset -lt 0) } }
    }
}
Write-Host "  + Departures: $($departureIds.Count)"

# Past departures are marked Returned so they count in the success-rate
# denominator; a Scheduled sailing in the past is just stale data.
$sailed = @($departureIds | Where-Object { $_.Past })
foreach ($d in $sailed) {
    Invoke-Api -Method PUT -Path "/departures/$($d.Id)/status" -Token $token -IgnoreErrors `
        -Body @{ status = "Returned" } | Out-Null
}

# Deliberately not every sailing: a 100% success rate would be a fabricated
# number, and the KPI only means something if it varies.
$logged = 0
$i = 0
foreach ($d in $sailed) {
    if ($rng.Next(0, 10) -lt 3) { continue }
    $result = Invoke-Api -Method POST -Path "/sightings" -Token $token -IgnoreErrors -Body @{
        departureId = $d.Id
        species     = $speciesPool[$i % $speciesPool.Count]
        count       = $rng.Next(1, 12)
        behaviour   = $behaviours[$rng.Next(0, $behaviours.Count)]
        locationLat = 5.90 + ($rng.NextDouble() * 0.15)
        locationLng = 80.40 + ($rng.NextDouble() * 0.20)
        notes       = "Logged from the manifest by the marine guide."
    }
    if ($result) { $logged++ }
    $i++
}
Write-Host "  + Sightings: $logged across $(($speciesPool | Select-Object -Unique).Count) species"

Write-Host "`nDone. Admin login: $AdminEmail / Demo@12345" -ForegroundColor Green
