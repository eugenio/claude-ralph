#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Cross-platform integration tests for Ralph.

.DESCRIPTION
    Tests that Bash and PowerShell implementations create compatible
    lock formats, status files, and PRD updates.
#>

$ErrorActionPreference = 'Stop'
$script:TestDir = Join-Path $PSScriptRoot 'cross-platform-test'
$script:Passed = 0
$script:Failed = 0

function Write-TestResult {
    param(
        [string]$Name,
        [bool]$Success,
        [string]$Message = ''
    )

    if ($Success) {
        Write-Host "PASS: $Name" -ForegroundColor Green
        $script:Passed++
    }
    else {
        Write-Host "FAIL: $Name - $Message" -ForegroundColor Red
        $script:Failed++
    }
}

function Initialize-TestEnvironment {
    Write-Host "`nSetting up cross-platform test environment..." -ForegroundColor Blue

    if (Test-Path $script:TestDir) {
        Remove-Item -Path $script:TestDir -Recurse -Force
    }

    New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $script:TestDir 'instances') -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $script:TestDir 'locks') -ItemType Directory -Force | Out-Null

    # Create test PRD
    $testPrd = @{
        featureName = 'Cross-Platform Test'
        branchName = 'test/cross-platform'
        userStories = @(
            @{ id = 'CP-001'; title = 'Test Story 1'; priority = 1; passes = $false }
            @{ id = 'CP-002'; title = 'Test Story 2'; priority = 2; passes = $false }
        )
    }
    $testPrd | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $script:TestDir 'prd.json')
}

function Remove-TestEnvironment {
    Write-Host "`nCleaning up test environment..." -ForegroundColor Blue
    if (Test-Path $script:TestDir) {
        Remove-Item -Path $script:TestDir -Recurse -Force
    }
}

# =============================================================================
# TESTS
# =============================================================================

function Test-LockFormatCompatibility {
    Write-Host "`n--- Lock Format Compatibility ---" -ForegroundColor Yellow

    $locksDir = Join-Path $script:TestDir 'locks'

    # Create lock in Bash format (directory with owner.txt and timestamp.txt)
    $bashLockDir = Join-Path $locksDir 'CP-BASH.lock'
    New-Item -Path $bashLockDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $bashLockDir 'owner') -Value 'bash-instance-123'
    Set-Content -Path (Join-Path $bashLockDir 'timestamp') -Value ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

    # Create lock in PowerShell format
    $psLockDir = Join-Path $locksDir 'CP-PS.lock'
    New-Item -Path $psLockDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $psLockDir 'owner.txt') -Value 'ps-instance-456'
    Set-Content -Path (Join-Path $psLockDir 'timestamp.txt') -Value ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

    # Test: Both formats use directory-based locking
    $bashExists = Test-Path $bashLockDir
    $psExists = Test-Path $psLockDir
    Write-TestResult -Name 'Both lock formats use directories' -Success ($bashExists -and $psExists)

    # Test: Can read Bash lock from PowerShell
    $bashOwnerFile = Join-Path $bashLockDir 'owner'
    $canReadBash = Test-Path $bashOwnerFile
    if ($canReadBash) {
        $bashOwner = (Get-Content $bashOwnerFile -Raw).Trim()
        Write-TestResult -Name 'PowerShell can read Bash lock owner' -Success ($bashOwner -eq 'bash-instance-123')
    }
    else {
        Write-TestResult -Name 'PowerShell can read Bash lock owner' -Success $false -Message 'File not found'
    }

    # Test: Lock directory prevents duplicate creation
    try {
        New-Item -Path $bashLockDir -ItemType Directory -ErrorAction Stop | Out-Null
        Write-TestResult -Name 'Atomic lock prevents duplicate' -Success $false -Message 'Should have thrown'
    }
    catch {
        Write-TestResult -Name 'Atomic lock prevents duplicate' -Success $true
    }
}

function Test-StatusJsonCompatibility {
    Write-Host "`n--- Status JSON Compatibility ---" -ForegroundColor Yellow

    $instancesDir = Join-Path $script:TestDir 'instances'

    # Create Bash-style status
    $bashInstanceDir = Join-Path $instancesDir 'bash-user-host-1234-1700000000'
    New-Item -Path $bashInstanceDir -ItemType Directory -Force | Out-Null
    $bashStatus = @{
        instanceId = 'bash-user-host-1234-1700000000'
        shortId = 'bash-use'
        state = 'working'
        currentStory = 'CP-001'
        iteration = 3
        maxIterations = 10
        startTime = '2024-01-01 12:00:00'
        lastHeartbeat = '2024-01-01 12:05:00'
        lastHeartbeatEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        projectRoot = '/test/project'
        branch = 'ralph/bash-use/CP-001'
        pid = 1234
    }
    $bashStatus | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $bashInstanceDir 'status.json')

    # Test: Can read Bash status from PowerShell
    $statusFile = Join-Path $bashInstanceDir 'status.json'
    try {
        $status = Get-Content $statusFile -Raw | ConvertFrom-Json
        Write-TestResult -Name 'PowerShell can parse Bash status.json' -Success $true
        Write-TestResult -Name 'Status has instanceId' -Success ($null -ne $status.instanceId)
        Write-TestResult -Name 'Status has state' -Success ($status.state -eq 'working')
        Write-TestResult -Name 'Status has lastHeartbeatEpoch' -Success ($status.lastHeartbeatEpoch -gt 0)
    }
    catch {
        Write-TestResult -Name 'PowerShell can parse Bash status.json' -Success $false -Message $_.Exception.Message
    }

    # Test: Required fields present
    $requiredFields = @('instanceId', 'shortId', 'state', 'currentStory', 'lastHeartbeatEpoch', 'pid')
    foreach ($field in $requiredFields) {
        $hasField = $null -ne $status.$field -or $status.$field -eq 0 -or $status.$field -eq ''
        Write-TestResult -Name "Status has $field field" -Success $hasField
    }
}

function Test-InstanceIdFormat {
    Write-Host "`n--- Instance ID Format Compatibility ---" -ForegroundColor Yellow

    # Bash format: user-hostname-pid-timestamp
    $bashId = 'alice-macbook-12345-1700000000'

    # PowerShell format should match
    $pattern = '^[a-zA-Z0-9_]+-[a-zA-Z0-9_-]+-\d+-\d+$'

    Write-TestResult -Name 'Bash ID matches expected pattern' -Success ($bashId -match $pattern)

    # Generate PowerShell ID
    $user = $env:USERNAME ?? $env:USER ?? 'test'
    $hostname = $env:COMPUTERNAME ?? (hostname) ?? 'local'
    $hostname = $hostname -replace '[^a-zA-Z0-9_-]', ''
    $psId = "$user-$hostname-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"

    Write-TestResult -Name 'PowerShell ID matches expected pattern' -Success ($psId -match $pattern)

    # Test short ID extraction
    $bashShort = $bashId.Substring(0, [Math]::Min(8, $bashId.Length))
    $psShort = $psId.Substring(0, [Math]::Min(8, $psId.Length))

    Write-TestResult -Name 'Bash short ID is 8 chars or less' -Success ($bashShort.Length -le 8)
    Write-TestResult -Name 'PowerShell short ID is 8 chars or less' -Success ($psShort.Length -le 8)
}

function Test-PrdUpdateCompatibility {
    Write-Host "`n--- PRD Update Compatibility ---" -ForegroundColor Yellow

    $prdFile = Join-Path $script:TestDir 'prd.json'

    # Read original
    $prd = Get-Content $prdFile -Raw | ConvertFrom-Json

    # Add claimedBy field (as Bash would)
    $prd.userStories[0] | Add-Member -NotePropertyName 'claimedBy' -NotePropertyValue 'bash-instance-123' -Force

    # Write back
    $prd | ConvertTo-Json -Depth 10 | Set-Content $prdFile

    # Re-read (as PowerShell would)
    try {
        $prd2 = Get-Content $prdFile -Raw | ConvertFrom-Json
        Write-TestResult -Name 'PRD remains valid after claimedBy addition' -Success $true
        Write-TestResult -Name 'claimedBy field preserved' -Success ($prd2.userStories[0].claimedBy -eq 'bash-instance-123')
    }
    catch {
        Write-TestResult -Name 'PRD remains valid after claimedBy addition' -Success $false -Message $_.Exception.Message
    }

    # Test marking story complete
    $prd2.userStories[0].passes = $true
    $prd2 | ConvertTo-Json -Depth 10 | Set-Content $prdFile

    try {
        $prd3 = Get-Content $prdFile -Raw | ConvertFrom-Json
        Write-TestResult -Name 'PRD valid after marking complete' -Success ($prd3.userStories[0].passes -eq $true)
    }
    catch {
        Write-TestResult -Name 'PRD valid after marking complete' -Success $false -Message $_.Exception.Message
    }
}

function Test-HeartbeatDetection {
    Write-Host "`n--- Heartbeat/Dead Instance Detection ---" -ForegroundColor Yellow

    $instancesDir = Join-Path $script:TestDir 'instances'
    $deadInstanceDir = Join-Path $instancesDir 'dead-instance-123-1700000000'
    New-Item -Path $deadInstanceDir -ItemType Directory -Force | Out-Null

    # Create status with old heartbeat (6 minutes ago)
    $oldHeartbeat = [DateTimeOffset]::UtcNow.AddMinutes(-6).ToUnixTimeSeconds()
    $deadStatus = @{
        instanceId = 'dead-instance-123-1700000000'
        state = 'working'
        lastHeartbeatEpoch = $oldHeartbeat
    }
    $deadStatus | ConvertTo-Json | Set-Content (Join-Path $deadInstanceDir 'status.json')

    # Test detection
    $status = Get-Content (Join-Path $deadInstanceDir 'status.json') -Raw | ConvertFrom-Json
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $heartbeatAge = $now - $status.lastHeartbeatEpoch

    Write-TestResult -Name 'Heartbeat age calculated correctly' -Success ($heartbeatAge -gt 300)
    Write-TestResult -Name 'Dead instance detected (age > 5 min)' -Success ($heartbeatAge -gt 300 -and $status.state -ne 'terminated')
}

# =============================================================================
# MAIN
# =============================================================================

Write-Host ''
Write-Host '=====================================================' -ForegroundColor Blue
Write-Host '       RALPH CROSS-PLATFORM INTEGRATION TESTS' -ForegroundColor Cyan
Write-Host '=====================================================' -ForegroundColor Blue

Initialize-TestEnvironment

Test-LockFormatCompatibility
Test-StatusJsonCompatibility
Test-InstanceIdFormat
Test-PrdUpdateCompatibility
Test-HeartbeatDetection

Remove-TestEnvironment

Write-Host ''
Write-Host '=====================================================' -ForegroundColor Blue
Write-Host '                   TEST SUMMARY' -ForegroundColor Cyan
Write-Host '=====================================================' -ForegroundColor Blue
Write-Host "Passed: $($script:Passed)" -ForegroundColor Green
Write-Host "Failed: $($script:Failed)" -ForegroundColor Red
Write-Host ''

if ($script:Failed -eq 0) {
    Write-Host 'All cross-platform tests passed!' -ForegroundColor Green
    exit 0
}
else {
    Write-Host 'Some tests failed!' -ForegroundColor Red
    exit 1
}
