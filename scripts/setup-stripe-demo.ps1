<#
.SYNOPSIS
    Points Unify's own subscription billing at a Stripe test-mode account.

.DESCRIPTION
    Stores the Stripe test secret key in the backend's user-secrets and then
    proves it works by calling Stripe's /v1/balance with it - the same call
    the app's own "test connection" uses.

    Only the secret key is needed. Hosted Checkout redirects the browser to
    Stripe's own page, so the publishable key is never used on this path.

    Everything else (LKR pricing, USD settlement, the rate) is already set.
    Stripe does not accept LKR, so an invoice priced in LKR settles on its
    LKR amount while the card is charged the USD equivalent, and the rate
    used is recorded on the payment row.

    The key is written to user-secrets, which lives outside the repository -
    it is never committed.

.PARAMETER SecretKey
    Your Stripe TEST secret key, starting with sk_test_. A live key
    (sk_live_) is refused.

    Leave it out and the key is read from the clipboard instead, which is
    the easier path: the dashboard shows the key truncated and gives you a
    copy button beside it. Press that, run this with no arguments, and the
    key never passes through a terminal or a shell history file.

.PARAMETER RateLkrPerUsd
    How many rupees to one US dollar, for settlement. Defaults to 300.

.EXAMPLE
    # Copy the secret key in the Stripe dashboard first, then:
    ./scripts/setup-stripe-demo.ps1

.EXAMPLE
    ./scripts/setup-stripe-demo.ps1 -SecretKey sk_test_51ABC...
#>
[CmdletBinding()]
param(
    [string] $SecretKey,

    [decimal] $RateLkrPerUsd = 300
)

$ErrorActionPreference = 'Stop'

$backend = Join-Path $PSScriptRoot '..\backend\SmeBackend'
if (-not (Test-Path $backend)) { throw "Could not find the backend project at $backend" }

if ([string]::IsNullOrWhiteSpace($SecretKey)) {
    Write-Host 'No key given - reading the clipboard...' -ForegroundColor Cyan
    $SecretKey = Get-Clipboard -Raw
    if ([string]::IsNullOrWhiteSpace($SecretKey)) {
        throw 'The clipboard is empty. In the Stripe dashboard, press the copy button beside the Secret key, then run this again.'
    }
}

$key = $SecretKey.Trim()

# A live key here would take real money from a real card during a demo.
if ($key.StartsWith('sk_live_')) {
    throw 'That is a LIVE secret key. This script is for test mode only - use the sk_test_ key from the dashboard with Test mode switched on.'
}
if ($key.StartsWith('pk_test_')) {
    throw 'That is the publishable key. Copy the Secret key instead - the row above it, starting sk_test_.'
}
if (-not $key.StartsWith('sk_test_')) {
    throw "That does not look like a Stripe test secret key (it should start with sk_test_). Got something $($key.Length) characters long starting '$($key.Substring(0, [Math]::Min(8, $key.Length)))'."
}
# The dashboard truncates the key on screen as sk_test_...euto. Copying it
# with the button gives the whole thing; typing what is on screen does not.
if ($key.Contains('...') -or $key.Length -lt 30) {
    throw 'That looks like the truncated key shown on screen. Use the copy button beside it in the dashboard to get the full value.'
}

Write-Host 'Verifying the key against Stripe...' -ForegroundColor Cyan

try {
    $balance = Invoke-RestMethod -Method Get -Uri 'https://api.stripe.com/v1/balance' `
        -Headers @{ Authorization = "Bearer $key" }
}
catch {
    throw "Stripe refused that key: $($_.Exception.Message)"
}

if ($balance.livemode) {
    throw 'That key is in live mode. Switch Test mode on in the Stripe dashboard and copy the sk_test_ key.'
}

Write-Host 'Key accepted by Stripe (test mode).' -ForegroundColor Green

Push-Location $backend
try {
    dotnet user-secrets set 'Platform:Billing:Stripe:SecretKey' $key | Out-Null
    dotnet user-secrets set 'Platform:Billing:Currency' 'LKR' | Out-Null
    dotnet user-secrets set 'Platform:Billing:TestMode' 'true' | Out-Null
    dotnet user-secrets set 'Platform:Billing:SettlementCurrency' 'USD' | Out-Null
    dotnet user-secrets set 'Platform:Billing:Rates:LKR' $RateLkrPerUsd.ToString([System.Globalization.CultureInfo]::InvariantCulture) | Out-Null
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host 'Stored in user-secrets (not in the repository):' -ForegroundColor Green
Write-Host '  Platform:Billing:Stripe:SecretKey   sk_test_...(hidden)'
Write-Host '  Platform:Billing:Currency           LKR'
Write-Host '  Platform:Billing:TestMode           true'
Write-Host '  Platform:Billing:SettlementCurrency USD'
Write-Host "  Platform:Billing:Rates:LKR          $RateLkrPerUsd"
Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  1. Restart the backend so it picks the key up.'
Write-Host '  2. Sign in as a tenant Admin, open Business -> Your Unify Plan.'
Write-Host '  3. The payment picker should now offer "Card (Stripe)".'
Write-Host '  4. Pay with test card 4242 4242 4242 4242, any future expiry, any CVC.'
Write-Host ''
Write-Host 'Decline card for the failure path: 4000 0000 0000 0002' -ForegroundColor DarkGray
