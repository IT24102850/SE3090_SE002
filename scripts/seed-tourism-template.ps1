<#
.SYNOPSIS
  Reusable scaffold for onboarding any Sri Lankan tourism business, per the
  archetypes in docs/tourism-business-template.md. Unlike
  seed-demo-data.ps1 (one shared weekly schedule per business), each
  resource here carries its OWN schedule window - required for
  fixed-departure businesses like whale watching/safari that run multiple
  distinct daily departures on the same boat/vehicle type.

  Mirissa Jetliner is included below as the worked reference example and
  is marked DoNotSeed = $true because it was already onboarded via
  seed-mirissa-jetliner.ps1 - running it again here would create a
  duplicate tenant. To add a new tourism business, copy that block, set
  DoNotSeed = $false (or remove the flag), and fill in real sourced data
  per the CustomAttributes schema in docs/tourism-business-template.md.

.PARAMETER BaseUrl
  Backend API base URL. Defaults to http://localhost:5298/api.

.EXAMPLE
  ./scripts/seed-tourism-template.ps1
#>
param(
    [string]$BaseUrl = "http://localhost:5298/api"
)

$ErrorActionPreference = "Stop"

function Invoke-Api {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body,
        [string]$Token
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
        Write-Warning "  $Method $Path failed: $($_.Exception.Message) $respBody"
        throw
    }
}

function New-DailySchedule {
    # A resource open every day between $StartTime and $EndTime. For a
    # business closed certain days, pass -OpenDays explicitly instead.
    param(
        [string]$StartTime,
        [string]$EndTime,
        [int[]]$OpenDays = @(0, 1, 2, 3, 4, 5, 6)
    )
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

function New-TourismCustomAttributes {
    # Builds the universal CustomAttributes JSON per
    # docs/tourism-business-template.md section 3. Every parameter is
    # optional - only pass what's real/sourced for the business.
    param(
        [string]$Subtype,
        [int]$Capacity,
        [decimal]$AdultPrice,
        [decimal]$ChildPrice,
        [string[]]$Includes,
        [string[]]$Excludes,
        [string]$DifficultyLevel,
        [string]$AgeRestriction,
        [string[]]$LanguagesSpoken,
        [double]$Rating,
        [int]$ReviewCount
    )
    $attrs = @{}
    if ($Subtype)          { $attrs.subtype = $Subtype }
    if ($Capacity)          { $attrs.capacity = $Capacity }
    if ($AdultPrice -or $ChildPrice) {
        $pricing = @{ currency = "LKR" }
        if ($AdultPrice) { $pricing.adult = $AdultPrice }
        if ($ChildPrice) { $pricing.child = $ChildPrice }
        $attrs.pricing = $pricing
    }
    if ($Includes)          { $attrs.includes = $Includes }
    if ($Excludes)          { $attrs.excludes = $Excludes }
    if ($DifficultyLevel)   { $attrs.difficultyLevel = $DifficultyLevel }
    if ($AgeRestriction)    { $attrs.ageRestriction = $AgeRestriction }
    if ($LanguagesSpoken)   { $attrs.languagesSpoken = $LanguagesSpoken }
    if ($Rating)             { $attrs.rating = $Rating }
    if ($ReviewCount)        { $attrs.reviewCount = $ReviewCount }
    return ($attrs | ConvertTo-Json -Compress -Depth 5)
}

# ==========================================================================
# Business list - each Resource carries its own schedule window, so a
# business with several fixed daily departures (whale watching, safari)
# is expressed naturally as one Resource per departure.
# ==========================================================================
$tourismBusinesses = @(
    @{
        DoNotSeed     = $true   # already onboarded via seed-mirissa-jetliner.ps1
        BusinessName  = "Mirissa Jetliner"
        BusinessType  = "Tourism"
        Address       = "Mirissa Harbour, Mirissa, Sri Lanka"
        Phone         = "+94777728439"
        AdminEmail    = "admin@mirissajetliner.lk"   # use a unique login email, not the shared public contact address
        AdminName     = "Mirissa Jetliner Admin"
        AdminPhone    = "+94777728439"
        Resources     = @(
            @{
                Name      = "Whale Watching Boat - Dawn Departure"
                Category  = "Vehicle"
                Specialty = "Whale and Dolphin Watching"
                Rate      = 7500
                Schedule  = @{ Start = "06:30:00"; End = "10:30:00" }
                Attrs     = @{
                    Subtype = "WildlifeExcursion"; Capacity = 120; AdultPrice = 7500; ChildPrice = 4000
                    Includes = @("breakfast", "refreshments", "life jacket", "insurance", "WiFi")
                }
            }
            @{
                Name      = "Whale Watching Boat - Morning Cruise"
                Category  = "Vehicle"
                Specialty = "Whale and Dolphin Watching"
                Rate      = 7500
                Schedule  = @{ Start = "10:00:00"; End = "14:00:00" }
                Attrs     = @{
                    Subtype = "WildlifeExcursion"; Capacity = 120; AdultPrice = 7500; ChildPrice = 4000
                    Includes = @("breakfast", "refreshments", "life jacket", "insurance", "WiFi")
                }
            }
        )
        BookingTypes  = @(
            @{ Name = "Whale Watching Tour"; Duration = 240; Color = "#0891B2"; RequiresApproval = $false; MaxParticipants = 120 }
        )
    }
    # --- Copy the block above for the next real tourism business. -------
    # Fill Resources/BookingTypes from real, sourced data (the operator's
    # own website/booking page), following the archetype table in
    # docs/tourism-business-template.md section 1-2.
)

Write-Host "Tourism template scaffold - $($tourismBusinesses.Count) business(es) defined against $BaseUrl`n" -ForegroundColor Cyan

foreach ($biz in $tourismBusinesses) {
    if ($biz.DoNotSeed) {
        Write-Host "=== $($biz.BusinessName) - skipped (DoNotSeed) ===" -ForegroundColor DarkGray
        continue
    }

    Write-Host "=== $($biz.BusinessName) ===" -ForegroundColor Yellow

    $onboardBody = @{
        businessName  = $biz.BusinessName
        businessType  = $biz.BusinessType
        address       = $biz.Address
        phone         = $biz.Phone
        adminEmail    = $biz.AdminEmail
        adminPassword = "Demo@12345"
        adminFullName = $biz.AdminName
        adminPhone    = $biz.AdminPhone
    }

    $onboard  = Invoke-Api -Method POST -Path "/tenant/onboard" -Body $onboardBody
    $token    = $onboard.accessToken
    $tenantId = $onboard.user.tenantId
    $branchId = $onboard.user.branchId
    Write-Host "  Tenant created: $tenantId (admin: $($biz.AdminEmail) / Demo@12345)"

    foreach ($res in $biz.Resources) {
        $attrsTable  = $res.Attrs
        $customAttrs = New-TourismCustomAttributes @attrsTable

        $resourceBody = @{
            tenantId         = $tenantId
            branchId         = $branchId
            name             = $res.Name
            category         = $res.Category
            specialty        = $res.Specialty
            hourlyRate       = $res.Rate
            customAttributes = $customAttrs
        }
        $created = Invoke-Api -Method POST -Path "/resources" -Body $resourceBody -Token $token
        Write-Host "  + Resource: $($res.Name)"

        $scheduleBody = New-DailySchedule -StartTime $res.Schedule.Start -EndTime $res.Schedule.End
        Invoke-Api -Method PUT -Path "/resources/$($created.id)/schedule" -Body $scheduleBody -Token $token | Out-Null
    }

    foreach ($bt in $biz.BookingTypes) {
        $btBody = @{
            tenantId               = $tenantId
            name                   = $bt.Name
            colorHex                = $bt.Color
            defaultDurationMinutes = $bt.Duration
            requiresApproval       = $bt.RequiresApproval
            maxParticipants        = $bt.MaxParticipants
        }
        Invoke-Api -Method POST -Path "/bookingtypes" -Body $btBody -Token $token | Out-Null
        Write-Host "  + Booking type: $($bt.Name) ($($bt.Duration) min)"
    }

    Write-Host ""
}

Write-Host "Done. Every admin login uses password: Demo@12345" -ForegroundColor Green
