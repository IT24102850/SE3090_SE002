<#
.SYNOPSIS
  Seeds the running backend with one realistic demo business per supported
  business type (Clinic, Restaurant, Gym, School/Tuition, RealEstate,
  Tourism, General) - each with real resources, weekly schedules, linked
  staff logins, and booking types, via the same public API the apps use
  (POST /tenant/onboard, /resources, /resources/{id}/schedule,
  /tenant/staff, /bookingtypes). Nothing here touches the DB directly, so
  it's exercised against the exact same validation every real signup goes
  through.

.PARAMETER BaseUrl
  Backend API base URL. Defaults to http://localhost:5298/api - make sure
  `dotnet run` is up in backend/SmeBackend first.

.EXAMPLE
  ./scripts/seed-demo-data.ps1
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
            dayOfWeek  = $d
            startTime  = $StartTime
            endTime    = $EndTime
            isAvailable = $OpenDays -contains $d
        }
    }
    return @{ days = $days }
}

# DayOfWeek: 0=Sun 1=Mon 2=Tue 3=Wed 4=Thu 5=Fri 6=Sat
$WeekdayOnly  = @(1, 2, 3, 4, 5)
$EveryDay     = @(0, 1, 2, 3, 4, 5, 6)
$WeekdayPlusSat = @(1, 2, 3, 4, 5, 6)

$businesses = @(
    @{
        BusinessName = "Colombo Family Clinic"
        BusinessType = "Clinic"
        Address      = "45 Galle Road, Colombo 03"
        Phone        = "+94112345678"
        AdminEmail   = "admin@colombofamilyclinic.lk"
        AdminName    = "Nishantha Perera"
        AdminPhone   = "+94771234567"
        Schedule     = @{ Days = $WeekdayOnly; Start = "09:00:00"; End = "17:00:00" }
        Resources    = @(
            @{ Name = "Dr. Anjali Fernando"; Category = "Staff"; Specialty = "Cardiology";       Rate = 5000; Rating = 4.8; StaffEmail = "anjali.fernando@colombofamilyclinic.lk" }
            @{ Name = "Dr. Kasun Silva";     Category = "Staff"; Specialty = "Pediatrics";        Rate = 4000; Rating = 4.6; StaffEmail = "kasun.silva@colombofamilyclinic.lk" }
            @{ Name = "Dr. Priya Jayasuriya"; Category = "Staff"; Specialty = "Dermatology";      Rate = 4500; Rating = 4.9; StaffEmail = "priya.jayasuriya@colombofamilyclinic.lk" }
            @{ Name = "Dr. Ruwan Bandara";   Category = "Staff"; Specialty = "General Physician"; Rate = 3000; Rating = 4.5; StaffEmail = "ruwan.bandara@colombofamilyclinic.lk" }
        )
        BookingTypes = @(
            @{ Name = "Consultation"; Duration = 30; Color = "#2563EB"; RequiresApproval = $false }
            @{ Name = "Follow-up";    Duration = 15; Color = "#059669"; RequiresApproval = $false }
            @{ Name = "Vaccination";  Duration = 20; Color = "#7C3AED"; RequiresApproval = $false }
        )
    },
    @{
        BusinessName = "Spice Garden Restaurant"
        BusinessType = "Restaurant"
        Address      = "12 Marine Drive, Colombo 06"
        Phone        = "+94112987654"
        AdminEmail   = "admin@spicegarden.lk"
        AdminName    = "Chaminda Rathnayake"
        AdminPhone   = "+94772345678"
        Schedule     = @{ Days = $EveryDay; Start = "11:00:00"; End = "22:00:00" }
        Resources    = @(
            @{ Name = "Window Table for 2";      Category = "Room"; Specialty = "Indoor";  Rate = $null; Rating = 4.6 }
            @{ Name = "Family Table for 4";       Category = "Room"; Specialty = "Indoor";  Rate = $null; Rating = 4.7 }
            @{ Name = "Garden Terrace for 6";     Category = "Room"; Specialty = "Outdoor"; Rate = $null; Rating = 4.9 }
            @{ Name = "Private Dining Room";      Category = "Room"; Specialty = "Private"; Rate = 5000; Rating = 4.8 }
        )
        BookingTypes = @(
            @{ Name = "Lunch Reservation";  Duration = 90;  Color = "#F59E0B"; RequiresApproval = $false }
            @{ Name = "Dinner Reservation"; Duration = 120; Color = "#DC2626"; RequiresApproval = $false }
            @{ Name = "Private Event";      Duration = 240; Color = "#7C3AED"; RequiresApproval = $true }
        )
    },
    @{
        BusinessName = "PowerHouse Fitness"
        BusinessType = "Gym"
        Address      = "88 High Level Road, Nugegoda"
        Phone        = "+94112765432"
        AdminEmail   = "admin@powerhousefitness.lk"
        AdminName    = "Isuru Wickramasinghe"
        AdminPhone   = "+94773456789"
        Schedule     = @{ Days = $EveryDay; Start = "06:00:00"; End = "21:00:00" }
        Resources    = @(
            @{ Name = "Sanjeewa Kumara - Personal Trainer"; Category = "Staff"; Specialty = "Strength Training"; Rate = 3000; Rating = 4.7; StaffEmail = "sanjeewa.kumara@powerhousefitness.lk" }
            @{ Name = "Nadeesha Perera - Yoga Instructor";  Category = "Staff"; Specialty = "Yoga";              Rate = 2000; Rating = 4.9; StaffEmail = "nadeesha.perera@powerhousefitness.lk" }
            @{ Name = "Tharindu De Silva - CrossFit Coach"; Category = "Staff"; Specialty = "CrossFit";          Rate = 3500; Rating = 4.6; StaffEmail = "tharindu.desilva@powerhousefitness.lk" }
        )
        BookingTypes = @(
            @{ Name = "Personal Training Session"; Duration = 60; Color = "#DC2626"; RequiresApproval = $false }
            @{ Name = "Group Class";                Duration = 45; Color = "#059669"; RequiresApproval = $false }
            @{ Name = "Trial Session";               Duration = 30; Color = "#2563EB"; RequiresApproval = $false }
        )
    },
    @{
        BusinessName = "BrightMinds Tuition Center"
        BusinessType = "School"
        Address      = "23 Kandy Road, Kadawatha"
        Phone        = "+94112654321"
        AdminEmail   = "admin@brightminds.lk"
        AdminName    = "Sujeewa Gunawardena"
        AdminPhone   = "+94774567890"
        Schedule     = @{ Days = $WeekdayPlusSat; Start = "14:00:00"; End = "19:00:00" }
        Resources    = @(
            @{ Name = "Mr. Dilshan Ekanayake - Mathematics"; Category = "Staff"; Specialty = "Mathematics"; Rate = 2500; Rating = 4.8; StaffEmail = "dilshan.ekanayake@brightminds.lk" }
            @{ Name = "Ms. Harshi Rodrigo - Science";        Category = "Staff"; Specialty = "Science";     Rate = 2500; Rating = 4.7; StaffEmail = "harshi.rodrigo@brightminds.lk" }
            @{ Name = "Mr. Chathura Wijesinghe - English";   Category = "Staff"; Specialty = "English";     Rate = 2000; Rating = 4.9; StaffEmail = "chathura.wijesinghe@brightminds.lk" }
        )
        BookingTypes = @(
            @{ Name = "1-on-1 Tutoring"; Duration = 60; Color = "#7C3AED"; RequiresApproval = $false }
            @{ Name = "Group Class";     Duration = 90; Color = "#059669"; RequiresApproval = $false }
            @{ Name = "Exam Prep";       Duration = 120; Color = "#DC2626"; RequiresApproval = $false }
        )
    },
    @{
        BusinessName = "Prime Properties Lanka"
        BusinessType = "RealEstate"
        Address      = "5 Duplication Road, Colombo 04"
        Phone        = "+94112543210"
        AdminEmail   = "admin@primeproperties.lk"
        AdminName    = "Ravindra Jayawardena"
        AdminPhone   = "+94775678901"
        Schedule     = @{ Days = $WeekdayPlusSat; Start = "09:00:00"; End = "18:00:00" }
        Resources    = @(
            @{ Name = "Ayesha Karunaratne - Residential Sales";  Category = "Staff"; Specialty = "Residential Sales";  Rate = $null; Rating = 4.7; StaffEmail = "ayesha.karunaratne@primeproperties.lk" }
            @{ Name = "Manoj Fernando - Commercial Leasing";     Category = "Staff"; Specialty = "Commercial Leasing"; Rate = $null; Rating = 4.5; StaffEmail = "manoj.fernando@primeproperties.lk" }
            @{ Name = "Dilani Senaratne - Property Valuation";   Category = "Staff"; Specialty = "Valuation";          Rate = $null; Rating = 4.8; StaffEmail = "dilani.senaratne@primeproperties.lk" }
        )
        BookingTypes = @(
            @{ Name = "Property Viewing";        Duration = 45; Color = "#2563EB"; RequiresApproval = $false }
            @{ Name = "Consultation";             Duration = 30; Color = "#059669"; RequiresApproval = $false }
            @{ Name = "Valuation Appointment";   Duration = 60; Color = "#F59E0B"; RequiresApproval = $true }
        )
    },
    @{
        BusinessName = "Ceylon Adventures Tours"
        BusinessType = "Tourism"
        Address      = "9 Beach Road, Galle Fort"
        Phone        = "+94912345678"
        AdminEmail   = "admin@ceylonadventures.lk"
        AdminName    = "Nuwan Abeysekera"
        AdminPhone   = "+94776789012"
        Schedule     = @{ Days = $EveryDay; Start = "07:00:00"; End = "19:00:00" }
        Resources    = @(
            @{ Name = "Sampath Rajapaksha - City Tour Guide";      Category = "Staff"; Specialty = "City Tours";      Rate = 6000; Rating = 4.8; StaffEmail = "sampath.rajapaksha@ceylonadventures.lk" }
            @{ Name = "Ishara Madushani - Wildlife Safari Guide";  Category = "Staff"; Specialty = "Wildlife Safari"; Rate = 9000; Rating = 4.9; StaffEmail = "ishara.madushani@ceylonadventures.lk" }
            @{ Name = "Buddhika Herath - Hiking Guide";            Category = "Staff"; Specialty = "Hiking";         Rate = 7000; Rating = 4.7; StaffEmail = "buddhika.herath@ceylonadventures.lk" }
        )
        BookingTypes = @(
            @{ Name = "Day Tour";          Duration = 480; Color = "#059669"; RequiresApproval = $false }
            @{ Name = "Multi-day Package"; Duration = 1440; Color = "#7C3AED"; RequiresApproval = $true }
            @{ Name = "Airport Transfer";  Duration = 90;  Color = "#2563EB"; RequiresApproval = $false }
        )
    },
    @{
        BusinessName = "QuickFix Home Services"
        BusinessType = "General"
        Address      = "77 Baseline Road, Colombo 09"
        Phone        = "+94112432109"
        AdminEmail   = "admin@quickfixservices.lk"
        AdminName    = "Kamal Dissanayake"
        AdminPhone   = "+94777890123"
        Schedule     = @{ Days = $WeekdayPlusSat; Start = "08:00:00"; End = "18:00:00" }
        Resources    = @(
            @{ Name = "Chandana Wijeratne - Electrician"; Category = "Staff"; Specialty = "Electrical"; Rate = 2500; Rating = 4.6; StaffEmail = "chandana.wijeratne@quickfixservices.lk" }
            @{ Name = "Saman Kularatne - Plumber";        Category = "Staff"; Specialty = "Plumbing";   Rate = 2200; Rating = 4.5; StaffEmail = "saman.kularatne@quickfixservices.lk" }
        )
        BookingTypes = @(
            @{ Name = "Home Visit";    Duration = 60; Color = "#2563EB"; RequiresApproval = $false }
            @{ Name = "Consultation"; Duration = 20; Color = "#059669"; RequiresApproval = $false }
        )
    }
)

Write-Host "Seeding $($businesses.Count) demo businesses against $BaseUrl ...`n" -ForegroundColor Cyan

foreach ($biz in $businesses) {
    Write-Host "=== $($biz.BusinessName) ($($biz.BusinessType)) ===" -ForegroundColor Yellow

    $onboardBody = @{
        businessName = $biz.BusinessName
        businessType = $biz.BusinessType
        address      = $biz.Address
        phone        = $biz.Phone
        adminEmail   = $biz.AdminEmail
        adminPassword = "Demo@12345"
        adminFullName = $biz.AdminName
        adminPhone    = $biz.AdminPhone
    }

    try {
        $onboard = Invoke-Api -Method POST -Path "/tenant/onboard" -Body $onboardBody
    }
    catch {
        Write-Warning "  Skipping $($biz.BusinessName) - onboarding failed (may already exist)."
        continue
    }

    $token    = $onboard.accessToken
    $tenantId = $onboard.user.tenantId
    $branchId = $onboard.user.branchId
    Write-Host "  Tenant created: $tenantId (admin: $($biz.AdminEmail) / Demo@12345)"

    $scheduleBody = New-WeeklySchedule -OpenDays $biz.Schedule.Days -StartTime $biz.Schedule.Start -EndTime $biz.Schedule.End

    foreach ($res in $biz.Resources) {
        $customAttrs = @{ rating = $res.Rating } | ConvertTo-Json -Compress

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
        Write-Host "  + Resource: $($res.Name) [$($res.Specialty)]"

        Invoke-Api -Method PUT -Path "/resources/$($created.id)/schedule" -Body $scheduleBody -Token $token | Out-Null

        if ($res.StaffEmail) {
            $staffBody = @{
                email    = $res.StaffEmail
                password = "Demo@12345"
                fullName = $res.Name -replace '\s*-\s.*$', ''
                phone    = $biz.Phone
                branchId = $branchId
                role     = "Staff"
            }
            try {
                $staff = Invoke-Api -Method POST -Path "/tenant/staff" -Body $staffBody -Token $token
                Invoke-Api -Method PUT -Path "/resources/$($created.id)" -Body @{ linkedUserId = $staff.id } -Token $token | Out-Null
                Write-Host "    linked staff login: $($res.StaffEmail) / Demo@12345"
            }
            catch {
                Write-Warning "    Could not create/link staff login for $($res.Name)."
            }
        }
    }

    foreach ($bt in $biz.BookingTypes) {
        $btBody = @{
            tenantId               = $tenantId
            name                   = $bt.Name
            colorHex               = $bt.Color
            defaultDurationMinutes = $bt.Duration
            requiresApproval       = $bt.RequiresApproval
        }
        Invoke-Api -Method POST -Path "/bookingtypes" -Body $btBody -Token $token | Out-Null
        Write-Host "  + Booking type: $($bt.Name) ($($bt.Duration) min)"
    }

    Write-Host ""
}

Write-Host "Done. Every admin/staff login uses password: Demo@12345" -ForegroundColor Green
