<#
.SYNOPSIS
  Seeds "Weligama Bay Dive Center" - the diving sub-type example referenced
  throughout the tourism sub-type dashboard work (bookingUnit=Slot,
  Tenant.SubType="Water sports / diving"). Unlike Mirissa Jetliner/The
  Wallawwa/Malkey Rent A Car, this is clearly-labeled realistic demo data
  (not sourced from one specific real operator's website) - matching the
  precedent set by the original 7 seed-demo-data.ps1 businesses.

  Resources carry CustomAttributes.capacity/depth so the diving dashboard's
  cardFields (see registry/tourism_dashboard_registry.dart) have real data
  to render.

  Also populates the Business Profile shell (TenantProfileController) -
  logo/cover/gallery use Lorem Picsum seeded placeholder photos (stable,
  clearly generic stock images, not photos claiming to be this business -
  same demo-data honesty as everything else in this script) so the profile
  page has real content to render end-to-end.

.PARAMETER BaseUrl
  Backend API base URL. Defaults to http://localhost:5298/api.

.EXAMPLE
  ./scripts/seed-weligama-dive-center.ps1
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

function New-DailySchedule {
    param([string]$StartTime, [string]$EndTime)
    $days = @()
    for ($d = 0; $d -le 6; $d++) {
        $days += @{ dayOfWeek = $d; startTime = $StartTime; endTime = $EndTime; isAvailable = $true }
    }
    return @{ days = $days }
}

Write-Host "Seeding Weligama Bay Dive Center against $BaseUrl ...`n" -ForegroundColor Cyan

$onboard = Invoke-Api -Method POST -Path "/tenant/onboard" -Body @{
    businessName  = "Weligama Bay Dive Center"
    businessType  = "Tourism"
    subType       = "Water sports / diving"
    address       = "Weligama Bay, Weligama, Sri Lanka"
    phone         = "+94771234567"
    adminEmail    = "admin@weligamabaydive.lk"
    adminPassword = "Demo@12345"
    adminFullName = "Weligama Bay Dive Center Admin"
    adminPhone    = "+94771234567"
}
$token = $onboard.accessToken
$tenantId = $onboard.user.tenantId
$branchId = $onboard.user.branchId
Write-Host "Tenant created: $tenantId (admin: admin@weligamabaydive.lk / Demo@12345)"

$diveResources = @(
    @{ Name = "Reef Explorer - Dive Boat";  Capacity = 8;  Depth = 18; Start = "07:00:00"; End = "16:00:00" }
    @{ Name = "Wreck Diver - Dive Boat";    Capacity = 6;  Depth = 30; Start = "07:00:00"; End = "16:00:00" }
)
foreach ($r in $diveResources) {
    $customAttrs = @{ capacity = $r.Capacity; depth = $r.Depth } | ConvertTo-Json -Compress
    $created = Invoke-Api -Method POST -Path "/resources" -Body @{
        tenantId         = $tenantId
        branchId         = $branchId
        name             = $r.Name
        category         = "Vehicle"
        specialty        = "Diving"
        capacity         = $r.Capacity
        customAttributes = $customAttrs
    } -Token $token
    Write-Host "  + Resource: $($r.Name) (capacity $($r.Capacity), max depth $($r.Depth)m)"

    $scheduleBody = New-DailySchedule -StartTime $r.Start -EndTime $r.End
    Invoke-Api -Method PUT -Path "/resources/$($created.id)/schedule" -Body $scheduleBody -Token $token | Out-Null
}

$btConfig = @{ weatherDependent = $true } | ConvertTo-Json -Compress
Invoke-Api -Method POST -Path "/bookingtypes" -Body @{
    tenantId               = $tenantId
    name                   = "Reef Dive Trip"
    colorHex               = "#0077B6"
    defaultDurationMinutes = 180
    requiresApproval       = $false
    bookingUnit            = "Slot"
    configJson             = $btConfig
} -Token $token | Out-Null
Write-Host "  + Booking type: Reef Dive Trip (Slot, 180 min)"

# ── Business Profile (TenantProfileController) ─────────────────────
# Logo/cover/gallery are set via the imageUrl-based endpoints directly
# (no Cloudinary upload needed for seed data - those endpoints just take a
# URL string, same as the old LogoUrl field always did).
Invoke-Api -Method PUT -Path "/tenants/$tenantId/logo" -Body @{
    imageUrl = "https://picsum.photos/seed/weligama-dive-logo/400/400"
} -Token $token | Out-Null
Write-Host "  + Logo set"

Invoke-Api -Method PUT -Path "/tenants/$tenantId/cover-image" -Body @{
    imageUrl = "https://picsum.photos/seed/weligama-dive-cover/1200/500"
} -Token $token | Out-Null
Write-Host "  + Cover image set"

foreach ($seed in @("weligama-dive-1", "weligama-dive-2", "weligama-dive-3", "weligama-dive-4")) {
    Invoke-Api -Method POST -Path "/tenants/$tenantId/gallery-images" -Body @{
        imageUrl = "https://picsum.photos/seed/$seed/800/600"
    } -Token $token | Out-Null
}
Write-Host "  + Gallery: 4 photos added"

$dailyHours = @()
for ($d = 0; $d -le 6; $d++) {
    $dayName = @("Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday")[$d]
    $dailyHours += @{ dayOfWeek = $dayName; openTime = "07:00"; closeTime = "16:00"; isClosed = $false }
}
Invoke-Api -Method PUT -Path "/tenants/$tenantId/profile" -Body @{
    description      = "Weligama Bay Dive Center is a PADI-affiliated dive operator on Sri Lanka's south coast, running daily reef and wreck trips for divers of every level. Small groups, well-maintained gear, and easy access to some of the bay's best dive sites."
    shortTagline     = "PADI 5-Star Dive Center"
    amenities        = @("Free WiFi", "Equipment Rental", "Beginner Friendly", "Air Conditioning", "Parking")
    contactPhone     = "+94771234567"
    contactEmail     = "admin@weligamabaydive.lk"
    website          = "https://weligamabaydive.example.lk"
    socialLinks      = @{ instagram = "https://instagram.com/weligamabaydive"; facebook = "https://facebook.com/weligamabaydive" }
    businessHours    = $dailyHours
} -Token $token | Out-Null
Write-Host "  + Business profile: description, tagline, amenities, contact, hours set"

Write-Host "`nDone. Admin login: admin@weligamabaydive.lk / Demo@12345" -ForegroundColor Green
