<#
.SYNOPSIS
  Seeds a fully demo-able whale-watching tenant: two vessels, two daily
  departures each, adult/child/infant pricing with a seasonal window,
  expiry-dated safety gear, ~10 days of bookings carrying real ticket
  breakdowns and mixed waiver states, and 15+ sightings across species so
  the success-rate and species-frequency analytics have something real to
  chart.

  This is the "full" companion to seed-mirissa-jetliner.ps1, which seeds the
  same real business (Mirissa Jetliner, sourced from
  https://www.mirissajetliner.com/) with resources and booking types only.
  Everything is driven through the same public API the apps use, so nothing
  here depends on database access.

.PARAMETER BaseUrl
  Backend API base URL. Defaults to http://localhost:5298/api - make sure
  `dotnet run` is up in backend/SmeBackend first.

.PARAMETER AdminEmail
  Overrides the admin email, so the script can be re-run against a fresh
  tenant without colliding with an existing one.

.EXAMPLE
  ./scripts/seed-whalewatching-full.ps1
  ./scripts/seed-whalewatching-full.ps1 -AdminEmail demo2@example.com
#>
param(
    [string]$BaseUrl = "http://localhost:5298/api",
    [string]$AdminEmail = "wowwhales.ops@gmail.com"
)

$ErrorActionPreference = "Stop"

function Invoke-Api {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body,
        [string]$Token,
        [switch]$IgnoreErrors
    )
    $headers = @{}
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }

    $params = @{
        Method  = $Method
        Uri     = "$BaseUrl$Path"
        Headers = $headers
    }
    if ($Body) {
        $params["Body"] = ($Body | ConvertTo-Json -Depth 10)
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
    param([string]$StartTime, [string]$EndTime)
    $days = @()
    for ($d = 0; $d -le 6; $d++) {
        $days += @{ dayOfWeek = $d; startTime = $StartTime; endTime = $EndTime; isAvailable = $true }
    }
    return @{ days = $days }
}

Write-Host "Seeding a full whale-watching demo tenant against $BaseUrl ...`n" -ForegroundColor Cyan

# ── 1. Tenant ────────────────────────────────────────────────────────
$onboard = Invoke-Api -Method POST -Path "/tenant/onboard" -Body @{
    businessName  = "Mirissa Jetliner Whale Watching"
    businessType  = "Tourism"
    address       = "Mirissa Harbour, Mirissa, Sri Lanka"
    phone         = "+94777728439"
    adminEmail    = $AdminEmail
    adminPassword = "Demo@12345"
    adminFullName = "Mirissa Jetliner Operations"
    adminPhone    = "+94777728439"
}

$token    = $onboard.accessToken
$tenantId = $onboard.user.tenantId
$branchId = $onboard.user.branchId
Write-Host "Tenant created: $tenantId" -ForegroundColor Green

# The SubType is what selects the departure-operations dashboard - without
# this exact string the tenant gets the generic dashboard, which is the
# whole point of the registry lookup.
Invoke-Api -Method PUT -Path "/tenant" -Token $token -Body @{
    subType                 = "Whale / dolphin watching"
    rescheduleCutoffHours   = 4
    cancellationCutoffHours = 2
} | Out-Null
Write-Host "  + SubType set to 'Whale / dolphin watching'"

# ── 2. Booking type, with per-ticket and seasonal pricing ────────────
# Key names (subType, pricing.adult, pricing.child, capacity, season) are
# exactly the ones documented in docs/tourism-business-template.md and
# parsed by the Flutter app. pricing.infant and seasonalPricing are new
# keys added alongside them, never replacements.
$configJson = @{
    subType     = "whaleWatching"
    bookingUnit = "Slot"
    capacity    = 120
    pricing     = @{ adult = 7500; child = 4000; infant = 0; currency = "LKR" }
    season      = @{ months = @("Nov","Dec","Jan","Feb","Mar","Apr"); weatherDependent = $true }
    seasonalPricing = @(
        @{ label = "Peak";     months = @("Dec","Jan","Feb","Mar"); offPeak = $false;
           pricing = @{ adult = 9000; child = 5000; infant = 0 } },
        @{ label = "Off-peak"; months = @("May","Jun","Jul","Aug","Sep","Oct"); offPeak = $true;
           pricing = @{ adult = 6000; child = 3000; infant = 0 } }
    )
    includes    = @("breakfast", "refreshments", "life jacket", "insurance", "WiFi")
} | ConvertTo-Json -Depth 10 -Compress

$bookingType = Invoke-Api -Method POST -Path "/bookingtypes" -Token $token -Body @{
    tenantId               = $tenantId
    name                   = "Whale Watching Tour"
    description            = "Four-hour blue whale and dolphin excursion from Mirissa Harbour."
    colorHex               = "#0891B2"
    defaultDurationMinutes = 240
    requiresApproval       = $false
    maxParticipants        = 120
    bookingUnit            = "Slot"
    configJson             = $configJson
}
$bookingTypeId = $bookingType.id
Write-Host "  + Booking type: Whale Watching Tour (adult 7500 / child 4000, peak + off-peak windows)"

# ── 3. Two vessels ───────────────────────────────────────────────────
$vessels = @(
    @{ Name = "Sea Guardian";  Capacity = 120; Start = "06:30:00"; End = "10:30:00" }
    @{ Name = "Ocean Spirit";  Capacity = 80;  Start = "06:30:00"; End = "10:30:00" }
)

$vesselRows = @()
foreach ($v in $vessels) {
    $created = Invoke-Api -Method POST -Path "/resources" -Token $token -Body @{
        tenantId         = $tenantId
        branchId         = $branchId
        name             = $v.Name
        category         = "Vehicle"
        specialty        = "Whale and Dolphin Watching"
        capacity         = $v.Capacity
        hourlyRate       = 7500
        customAttributes = (@{
            capacity = $v.Capacity
            pricing  = @{ adult = 7500; child = 4000; currency = "LKR" }
            season   = @{ months = @("Nov","Dec","Jan","Feb","Mar","Apr"); weatherDependent = $true }
            includes = @("breakfast", "life jacket", "insurance")
        } | ConvertTo-Json -Depth 8 -Compress)
    }
    Invoke-Api -Method PUT -Path "/resources/$($created.id)/schedule" -Token $token `
        -Body (New-WeeklySchedule -StartTime $v.Start -EndTime "14:00:00") | Out-Null

    $vesselRows += @{ Id = $created.id; Name = $v.Name; Capacity = $v.Capacity }
    Write-Host "  + Vessel: $($v.Name) ($($v.Capacity) pax)"
}

# ── 4. Safety gear, with expiry dates ────────────────────────────────
# Equipment is matched to a vessel by name mention, which is what the
# safety panel groups on (EquipmentItem has no ResourceId).
$today = (Get-Date).Date
$gear = @()
foreach ($v in $vesselRows) {
    $gear += @{ Name = "Life jackets - $($v.Name)";      Category = "Life jacket"; Stock = $v.Capacity; Expiry = $null }
    $gear += @{ Name = "Life raft - $($v.Name)";         Category = "Life raft";   Stock = 2;  Expiry = $today.AddMonths(8) }
    $gear += @{ Name = "Distress flares - $($v.Name)";   Category = "Flares";      Stock = 12; Expiry = $today.AddDays(45) }
    $gear += @{ Name = "Fire extinguisher - $($v.Name)"; Category = "Fire safety"; Stock = 4;  Expiry = $today.AddMonths(14) }
    $gear += @{ Name = "EPIRB - $($v.Name)";             Category = "EPIRB";       Stock = 1;  Expiry = $today.AddYears(3) }
    $gear += @{ Name = "First-aid kit - $($v.Name)";     Category = "First aid";   Stock = 2;  Expiry = $today.AddDays(-10) }
}
# One deliberately short jacket count so the panel has a real red flag to
# show; the demo is more useful if not everything is green.
$gear += @{ Name = "Spare life jackets - shared"; Category = "Life jacket"; Stock = 20; Expiry = $null }

foreach ($item in $gear) {
    $body = @{
        tenantId     = $tenantId
        branchId     = $branchId
        name         = $item.Name
        category     = $item.Category
        sku          = ($item.Name -replace '[^a-zA-Z0-9]', '-').ToUpper()
        unit         = "unit"
        currentStock = $item.Stock
        reorderLevel = 1
        costPrice    = 0
        sellingPrice = 0
        isActive     = $true
    }
    if ($item.Expiry) { $body["expiryDate"] = $item.Expiry.ToString("o") }
    Invoke-Api -Method POST -Path "/equipment" -Token $token -Body $body -IgnoreErrors | Out-Null
}
Write-Host "  + Safety gear: $($gear.Count) items, including expiry-dated rafts, flares, EPIRBs and first-aid kits"

# ── 5. Departures: 2 vessels x 2 daily sailings, 10 days back + 7 ahead
$departureTimes = @(6.5, 10.0)   # dawn departure and morning cruise
$departures = @()

for ($dayOffset = -10; $dayOffset -le 7; $dayOffset++) {
    $day = $today.AddDays($dayOffset)
    foreach ($v in $vesselRows) {
        foreach ($hour in $departureTimes) {
            $depart = $day.AddHours($hour)
            $created = Invoke-Api -Method POST -Path "/departures" -Token $token -Body @{
                resourceId         = $v.Id
                bookingTypeId      = $bookingTypeId
                scheduledDeparture = $depart.ToUniversalTime().ToString("o")
                scheduledReturn    = $depart.AddHours(4).ToUniversalTime().ToString("o")
                crew               = (@(
                    @{ name = "Capt. Sunil Fernando"; role = "Captain" },
                    @{ name = "Nimal Perera";         role = "Marine guide" }
                ) | ConvertTo-Json -Depth 5 -Compress)
            } -IgnoreErrors

            if ($created) {
                $departures += @{
                    Id       = $created.id
                    VesselId = $v.Id
                    Capacity = $v.Capacity
                    When     = $depart
                    Past     = ($dayOffset -lt 0)
                }
            }
        }
    }
}
Write-Host "  + Departures: $($departures.Count) sailings across 18 days"

# ── 6. Guests + bookings with real ticket breakdowns ─────────────────
$guestNames = @(
    "Anika Silva","Tom Whitfield","Yuki Tanaka","Lena Mueller","Raj Patel",
    "Sophie Dubois","Marco Rossi","Hannah Olsen","Diego Alvarez","Mei Chen",
    "Oliver Bennett","Priya Nair","Lars Jensen","Carla Moreno","Sam Okafor"
)
$sources = @("Online","WalkIn","OTA","Phone")
$nationalities = @("United Kingdom","Germany","Japan","Australia","France","India","Sri Lanka")
$rngSeedPhone = [System.Random]::new(4242)

# Real Customer accounts via the public self-registration endpoint, so the
# manifest shows guest names rather than one repeated staff account.
$guests = @()
foreach ($name in $guestNames) {
    $slug = ($name -replace '[^a-zA-Z]', '').ToLower()
    $registered = Invoke-Api -Method POST -Path "/auth/register" -IgnoreErrors -Body @{
        email    = "$slug@whale-demo.example"
        password = "Demo@12345"
        fullName = $name
        phone    = "+9477" + $rngSeedPhone.Next(1000000, 9999999)
        tenantId = $tenantId
        branchId = $branchId
    }
    if ($registered) { $guests += @{ id = $registered.user.id; name = $name } }
}
# Fall back to the admin as the booker if registration is unavailable - the
# demo still works, the manifest just shows one name.
if ($guests.Count -eq 0) { $guests = @(@{ id = $onboard.user.id; name = "Operations" }) }
Write-Host "  + Guest logins: $($guests.Count)"

$rng = [System.Random]::new(20260909)   # fixed seed: reruns look the same
$bookingsMade = 0
$bookingIndex = 0

foreach ($departure in $departures) {
    # Past sailings fill up more than future ones, which is what a real
    # forward book looks like.
    $partyCount = if ($departure.Past) { $rng.Next(4, 9) } else { $rng.Next(1, 5) }

    for ($i = 0; $i -lt $partyCount; $i++) {
        $adults = $rng.Next(1, 5)
        $children = if ($rng.Next(0, 10) -lt 4) { $rng.Next(1, 3) } else { 0 }
        $infants = if ($rng.Next(0, 10) -lt 2) { 1 } else { 0 }

        $tickets = @(@{ type = "Adult"; qty = $adults })
        if ($children -gt 0) { $tickets += @{ type = "Child";  qty = $children } }
        if ($infants  -gt 0) { $tickets += @{ type = "Infant"; qty = $infants } }

        $guest = $guests[$bookingIndex % $guests.Count]
        $bookingIndex++

        # Roughly two thirds of guests have signed a waiver, so the
        # completion percentage on the board is a real number rather than
        # a flat 0% or 100%.
        $waiver = $null
        if ($rng.Next(0, 3) -lt 2) {
            $waiver = @{
                signedAt   = $departure.When.AddDays(-1).ToUniversalTime().ToString("o")
                signerName = "Guest $bookingIndex"
                minorCount = $children
            } | ConvertTo-Json -Compress
        }

        $created = Invoke-Api -Method POST -Path "/bookings" -Token $token -IgnoreErrors -Body @{
            tenantId        = $tenantId
            resourceId      = $departure.VesselId
            bookingTypeId   = $bookingTypeId
            bookedBy        = $guest.id
            departureId     = $departure.Id
            startTime       = $departure.When.ToUniversalTime().ToString("o")
            endTime         = $departure.When.AddHours(4).ToUniversalTime().ToString("o")
            priority        = "Normal"
            title           = "Whale watching"
            ticketBreakdown = $tickets
            waiver          = $waiver
            source          = $sources[$rng.Next(0, $sources.Count)]
            formData        = (@{ nationality = $nationalities[$rng.Next(0, $nationalities.Count)] } | ConvertTo-Json -Compress)
        }
        if ($created) { $bookingsMade++ }
    }
}
Write-Host "  + Bookings: $bookingsMade, each with an adult/child/infant breakdown, a channel and a nationality"

# ── 7. Weather cancellations on two past days ────────────────────────
$stormed = $departures | Where-Object { $_.Past -and $_.When.Date -eq $today.AddDays(-4) }
foreach ($departure in $stormed) {
    Invoke-Api -Method POST -Path "/departures/$($departure.Id)/cancel-weather" -Token $token -IgnoreErrors -Body @{
        reason  = "Force 6 south-westerly, harbour master advised against sailing."
        weather = @{ windSpeedKnots = 28; waveHeightMetres = 2.6; visibilityKm = 3; seaStateCode = 5 }
    } | Out-Null
}
Write-Host "  + Weather cancellations: $($stormed.Count) sailings on $($today.AddDays(-4).ToString('yyyy-MM-dd'))"

# ── 8. Sightings across species, on past sailings only ───────────────
$species = @(
    "BlueWhale","BlueWhale","BlueWhale","SpermWhale","BrydesWhale",
    "SpinnerDolphin","SpinnerDolphin","BottlenoseDolphin","RissoDolphin",
    "Turtle","HumpbackWhale","FinWhale","KillerWhale","SpinnerDolphin","BlueWhale",
    "Turtle","BrydesWhale","BottlenoseDolphin"
)
$behaviours = @("Breaching","Spyhopping","TailSlapping","PodSwimming","Feeding","Resting")

# Sailings that actually went out - a cancelled departure can have no
# sighting, and including one would corrupt the success rate.
$sailed = $departures | Where-Object { $_.Past -and $stormed.Id -notcontains $_.Id }
$sightingsLogged = 0
$s = 0

foreach ($departure in $sailed) {
    # Not every sailing sees something: a 100% success rate would be a
    # fabricated number, and the whole point of the KPI is that it varies.
    if ($rng.Next(0, 10) -lt 3) { continue }
    if ($s -ge $species.Count) { $s = 0 }

    $result = Invoke-Api -Method POST -Path "/sightings" -Token $token -IgnoreErrors -Body @{
        departureId = $departure.Id
        species     = $species[$s]
        count       = $rng.Next(1, 12)
        locationLat = 5.90 + ($rng.NextDouble() * 0.15)
        locationLng = 80.40 + ($rng.NextDouble() * 0.20)
        behaviour   = $behaviours[$rng.Next(0, $behaviours.Count)]
        notes       = "Logged from the manifest by the marine guide."
    }
    if ($result) { $sightingsLogged++ }
    $s++
}
Write-Host "  + Sightings: $sightingsLogged logged across $($species | Select-Object -Unique | Measure-Object | Select-Object -ExpandProperty Count) species"

# ── 9. A harbour weather reading for the dashboard console ───────────
Invoke-Api -Method POST -Path "/departures/weather" -Token $token -IgnoreErrors -Body @{
    windSpeedKnots   = 11
    waveHeightMetres = 0.8
    visibilityKm     = 12
    seaStateCode     = 2
    note             = "Light south-westerly, good visibility. Safe to sail."
} | Out-Null

Write-Host "`nDone." -ForegroundColor Green
Write-Host "  Admin login: $AdminEmail / Demo@12345"
Write-Host "  Sign in on the web app and open /dashboard to see the departure operations board."
