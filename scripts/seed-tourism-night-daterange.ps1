<#
.SYNOPSIS
  Seeds two more real, sourced tourism businesses proving the two new
  booking units added alongside Slot: Malkey Rent A Car (Vehicle rental,
  bookingUnit=DateRange) and The Wallawwa (Accommodation, bookingUnit=Night).
  Real data pulled from each operator's own website (malkey.lk,
  teardrop-hotels.com/wallawwa) - no fabricated pricing beyond the clearly
  labeled per-day derivation noted below. See
  docs/tourism-business-template.md for the booking-unit design.

  Night/DateRange resources don't need a ResourceSchedule - unlike Slot,
  their availability comes from GET /bookings/unavailable-ranges, which
  only looks at existing Bookings, not weekly open-hours - so this script
  deliberately skips the schedule PUT call the other seed scripts make.

.PARAMETER BaseUrl
  Backend API base URL. Defaults to http://localhost:5298/api.

.EXAMPLE
  ./scripts/seed-tourism-night-daterange.ps1
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

    $params = @{ Method = $Method; Uri = $uri; Headers = $headers }
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

Write-Host "Seeding Malkey Rent A Car + The Wallawwa against $BaseUrl ...`n" -ForegroundColor Cyan

# ==========================================================================
# 1. Malkey Rent A Car - Vehicle rental / transport, bookingUnit=DateRange
#    Rates sourced from malkey.lk/rates/self-drive-rates (real weekly LKR
#    rates as of 2026-08-14). The site prices weekly, not daily; this
#    schema needs a per-day rate for the booking price calc, so HourlyRate
#    here is the weekly rate divided by 7, rounded - a clearly-labeled
#    derived figure, not a separately sourced daily rate.
# ==========================================================================
$malkeyOnboard = @{
    businessName  = "Malkey Rent A Car"
    businessType  = "Tourism"
    subType       = "Vehicle rental / transport"
    address       = "No 58, Pamankada Road, Colombo 06, Sri Lanka"
    phone         = "+94112365365"
    adminEmail    = "admin@malkey.lk"
    adminPassword = "Demo@12345"
    adminFullName = "Malkey Rent A Car Admin"
    adminPhone    = "+94112365365"
}
$malkey = Invoke-Api -Method POST -Path "/tenant/onboard" -Body $malkeyOnboard
$malkeyToken = $malkey.accessToken
$malkeyTenantId = $malkey.user.tenantId
$malkeyBranchId = $malkey.user.branchId
Write-Host "Tenant created: Malkey Rent A Car ($malkeyTenantId)"

$malkeyVehicles = @(
    @{ Name = "Suzuki Alto - Manual GR I";        Category = "Vehicle"; Specialty = "General Cars";     WeeklyRate = 32500; Capacity = 4 }
    @{ Name = "Toyota Corolla Axio 141";           Category = "Vehicle"; Specialty = "Premium Cars";     WeeklyRate = 45000; Capacity = 5 }
    @{ Name = "Toyota Hiace Commuter (15 Seater)"; Category = "Vehicle"; Specialty = "Buses, Vans & MPV"; WeeklyRate = 95000; Capacity = 15 }
)
foreach ($v in $malkeyVehicles) {
    $dailyRate = [Math]::Round($v.WeeklyRate / 7)
    $customAttrs = @{ pricing = @{ weekly = $v.WeeklyRate; currency = "LKR" } } | ConvertTo-Json -Compress
    $body = @{
        tenantId         = $malkeyTenantId
        branchId         = $malkeyBranchId
        name             = $v.Name
        category         = $v.Category
        specialty        = $v.Specialty
        capacity         = $v.Capacity
        hourlyRate       = $dailyRate
        customAttributes = $customAttrs
    }
    Invoke-Api -Method POST -Path "/resources" -Body $body -Token $malkeyToken | Out-Null
    Write-Host "  + Vehicle: $($v.Name) (LKR $dailyRate/day, derived from LKR $($v.WeeklyRate)/week)"
}

$malkeyConfig = @{
    requiresDocument = "International Driving Permit, OR a driving license endorsed by Sri Lanka's Automobile Association, OR a Temporary Driving License from the Department of Motor Traffic"
    ageRestriction   = "18+ (locals)"
} | ConvertTo-Json -Compress
Invoke-Api -Method POST -Path "/bookingtypes" -Body @{
    tenantId               = $malkeyTenantId
    name                   = "Self-Drive Rental"
    colorHex               = "#0EA5E9"
    defaultDurationMinutes = 1440
    requiresApproval       = $false
    bookingUnit            = "DateRange"
    configJson             = $malkeyConfig
} -Token $malkeyToken | Out-Null
Write-Host "  + Booking type: Self-Drive Rental (DateRange)`n"

# ==========================================================================
# 2. The Wallawwa - Accommodation, bookingUnit=Night
#    Room names/sizes/features sourced from teardrop-hotels.com/wallawwa.
#    No pricing or check-in/out times are published on the site, so
#    HourlyRate is left unset and checkInTime/checkOutTime are omitted from
#    config (the app's default 14:00/11:00 fallback applies) rather than
#    inventing figures.
# ==========================================================================
$wallawwaOnboard = @{
    businessName  = "The Wallawwa"
    businessType  = "Tourism"
    subType       = "Accommodation"
    address       = "Minuwangoda Road, Opatha, Kotugoda, Sri Lanka"
    phone         = "+94773638381"
    adminEmail    = "admin@thewallawwa.lk"
    adminPassword = "Demo@12345"
    adminFullName = "The Wallawwa Admin"
    adminPhone    = "+94773638381"
}
$wallawwa = Invoke-Api -Method POST -Path "/tenant/onboard" -Body $wallawwaOnboard
$wallawwaToken = $wallawwa.accessToken
$wallawwaTenantId = $wallawwa.user.tenantId
$wallawwaBranchId = $wallawwa.user.branchId
Write-Host "Tenant created: The Wallawwa ($wallawwaTenantId)"

$wallawwaRooms = @(
    @{ Name = "Wallawwa Bedroom";                   Specialty = "35 sqm - king bed, courtyard access";                     Capacity = 2 }
    @{ Name = "Garden Suite";                        Specialty = "55 sqm - four-poster king/twin bed, private terrace";     Capacity = 2 }
    @{ Name = "Family Suite";                        Specialty = "90 sqm - two-bedroom, separate bathrooms";                Capacity = 4 }
    @{ Name = "Mountbatten Suite with Plunge Pool";  Specialty = "162 sqm - two-bedroom, private garden with plunge pool"; Capacity = 4 }
)
foreach ($r in $wallawwaRooms) {
    $body = @{
        tenantId  = $wallawwaTenantId
        branchId  = $wallawwaBranchId
        name      = $r.Name
        category  = "Room"
        specialty = $r.Specialty
        capacity  = $r.Capacity
    }
    Invoke-Api -Method POST -Path "/resources" -Body $body -Token $wallawwaToken | Out-Null
    Write-Host "  + Room: $($r.Name)"
}

$wallawwaConfig = @{
    includes = @("breakfast", "USD 25 spa credit", "evening drinks 5-6pm", "afternoon tea")
} | ConvertTo-Json -Compress
Invoke-Api -Method POST -Path "/bookingtypes" -Body @{
    tenantId               = $wallawwaTenantId
    name                   = "Room Stay"
    colorHex               = "#B45309"
    defaultDurationMinutes = 1440
    requiresApproval       = $false
    bookingUnit            = "Night"
    configJson             = $wallawwaConfig
} -Token $wallawwaToken | Out-Null
Write-Host "  + Booking type: Room Stay (Night)"

Write-Host "`nDone. Admin logins: admin@malkey.lk / Demo@12345, admin@thewallawwa.lk / Demo@12345" -ForegroundColor Green
