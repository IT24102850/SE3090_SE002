$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$evidence = Join-Path $root 'tests\evidence\assignment-2'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null

function Run-Step([string] $Name, [string] $WorkingDirectory, [string] $Command) {
    $safeName = $Name -replace '[^A-Za-z0-9_-]', '-'
    $log = Join-Path $evidence "$safeName.log"
    Push-Location $WorkingDirectory
    try {
        "# $Name" | Set-Content $log
        "# $(Get-Date -Format o)" | Add-Content $log
        Invoke-Expression $Command 2>&1 | Tee-Object -FilePath $log -Append
        if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

Run-Step 'backend-tests' $root 'dotnet test backend/SmeBackend.Tests/SmeBackend.Tests.csproj --configuration Release --logger "trx;LogFileName=assignment-backend.trx"'
Run-Step 'frontend-tests' (Join-Path $root 'frontend') 'npm run test -- --reporter=dot'
Run-Step 'frontend-build' (Join-Path $root 'frontend') 'npm run build'
Run-Step 'frontend-security' (Join-Path $root 'frontend') 'npm audit --audit-level=high'
Run-Step 'agent-tests' (Join-Path $root 'agentic-ai-service') 'python -m pytest tests/ -q --junitxml=../tests/evidence/assignment-2/agent-tests.xml'
Run-Step 'flutter-analysis' (Join-Path $root 'mobile\sme_mobile') 'flutter analyze'
Run-Step 'flutter-tests' (Join-Path $root 'mobile\sme_mobile') 'flutter test'

Write-Host "Evidence written to $evidence"
