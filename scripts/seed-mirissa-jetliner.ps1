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
    adminEmail    = "wowwhales@gmail.com"
    adminPassword = "Demo@12345"
    adminFullName = "Mirissa Jetliner Admin"
    adminPhone    = "+94777728439"
}

$onboard  = Invoke-Api -Method POST -Path "/tenant/onboard" -Body $onboardBody
$token    = $onboard.accessToken
$tenantId = $onboard.user.tenantId
$branchId = $onboard.user.branchId
Write-Host "Tenant created: $tenantId (admin: wowwhales@gmail.com / Demo@12345)"

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
    @{ Name = "Whale Watching Boat - Dawn Departure";   Departure = "06:30:00"; End = "10:30:00" }
    @{ Name = "Whale Watching Boat - Morning Cruise";   Departure = "10:00:00"; End = "14:00:00" }
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
}

$btBody = @{
    tenantId               = $tenantId
    name                   = "Whale Watching Tour"
    colorHex               = "#0891B2"
    defaultDurationMinutes = 240
    requiresApproval       = $false
    maxParticipants        = 120
}
Invoke-Api -Method POST -Path "/bookingtypes" -Body $btBody -Token $token | Out-Null
Write-Host "  + Booking type: Whale Watching Tour (240 min)"

Write-Host "`nDone. Admin login: wowwhales@gmail.com / Demo@12345" -ForegroundColor Green
