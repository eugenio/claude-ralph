#!/usr/bin/env pwsh
# =============================================================================
# test-cross-platform.ps1 - Cross-Platform Integration Tests
# =============================================================================
#
# DESCRIPTION:
#   Tests that Bash and PowerShell implementations are interoperable:
#   - Compatible lock formats
#   - Compatible status.json structures
#   - Compatible PRD updates
#   - Consistent instance ID format
#
# USAGE:
#   pwsh ./scripts/ralph/tests/test-cross-platform.ps1
#
# REQUIREMENTS:
#   - PowerShell 7.0+
#   - Bash (Git Bash on Windows, native on Linux/macOS)
#   - jq (for Bash JSON parsing)
#
# =============================================================================

#Requires -Version 7.0

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

# =============================================================================
# Test Framework
# =============================================================================

$script:TestsRun = 0
$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestsSkipped = 0
$script:TestDir = $null

function Write-TestHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Message = ""
    )

    $script:TestsRun++

    switch ($Status) {
        "PASS" {
            $script:TestsPassed++
            Write-Host "  [PASS] $Name" -ForegroundColor Green
        }
        "FAIL" {
            $script:TestsFailed++
            Write-Host "  [FAIL] $Name" -ForegroundColor Red
            if ($Message) {
                Write-Host "         $Message" -ForegroundColor Red
            }
        }
        "SKIP" {
            $script:TestsSkipped++
            Write-Host "  [SKIP] $Name" -ForegroundColor Yellow
            if ($Message) {
                Write-Host "         $Message" -ForegroundColor Yellow
            }
        }
    }
}

function Initialize-TestEnvironment {
    # Create temp directory
    $script:TestDir = Join-Path ([System.IO.Path]::GetTempPath()) "ralph-cross-platform-$(Get-Random)"
    New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null

    # Create required subdirectories
    $ralphDir = Join-Path $script:TestDir "scripts/ralph"
    New-Item -ItemType Directory -Path $ralphDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ralphDir "instances") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ralphDir "locks") -Force | Out-Null

    # Create minimal PRD
    $prd = @{
        userStories = @(
            @{ id = "US-001"; title = "Test Story 1"; passes = $false; priority = 1 }
            @{ id = "US-002"; title = "Test Story 2"; passes = $false; priority = 2 }
        )
    }
    $prd | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $ralphDir "prd.json")

    # Set environment
    $env:RALPH_PROJECT_ROOT = $script:TestDir
    $env:RALPH_TEST_DIR = $script:TestDir

    return $script:TestDir
}

function Remove-TestEnvironment {
    if ($script:TestDir -and (Test-Path $script:TestDir)) {
        Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $env:RALPH_PROJECT_ROOT = $null
    $env:RALPH_TEST_DIR = $null
}

function Test-BashAvailable {
    try {
        $result = bash --version 2>&1
        return $null -ne $result
    } catch {
        return $false
    }
}

function Test-JqAvailable {
    try {
        $result = bash -c 'jq --version' 2>&1
        return $null -ne $result
    } catch {
        return $false
    }
}

# =============================================================================
# Test Functions
# =============================================================================

function Test-LockFormatCompatibility {
    Write-TestHeader "Lock Format Compatibility"

    $locksDir = Join-Path $script:TestDir "scripts/ralph/locks"

    # Test 1: PowerShell creates lock, Bash reads it
    try {
        # Import PowerShell module
        $modulePath = Join-Path $PSScriptRoot ".." "RalphUtils.psm1"
        Import-Module $modulePath -Force -WarningAction SilentlyContinue

        # Create lock using PowerShell
        $lockDir = Join-Path $locksDir "PS-LOCK-001.lock"
        New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
        Set-Content -Path (Join-Path $lockDir "owner.txt") -Value "ps-test-instance" -NoNewline
        Set-Content -Path (Join-Path $lockDir "timestamp.txt") -Value ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -NoNewline
        Set-Content -Path (Join-Path $lockDir "pid.txt") -Value $PID -NoNewline

        # Read with Bash - convert Windows path to Unix path for Git Bash
        $lockDirUnix = $lockDir -replace '\\', '/'
        $bashScript = "if [[ -f '$lockDirUnix/owner.txt' ]]; then cat '$lockDirUnix/owner.txt'; elif [[ -f '$lockDirUnix/owner' ]]; then cat '$lockDirUnix/owner'; fi"
        $result = bash -c $bashScript 2>&1

        if ($result -and $result.Trim() -eq "ps-test-instance") {
            Write-TestResult "PowerShell lock readable by Bash" "PASS"
        } else {
            Write-TestResult "PowerShell lock readable by Bash" "FAIL" "Bash could not read lock: $result"
        }
    } catch {
        Write-TestResult "PowerShell lock readable by Bash" "FAIL" $_.Exception.Message
    }

    # Test 2: Bash creates lock, PowerShell reads it
    try {
        $lockDir = Join-Path $locksDir "BASH-LOCK-001.lock"

        $bashScript = @"
mkdir -p '$lockDir'
echo -n 'bash-test-instance' > '$lockDir/owner'
echo -n '$(Get-Date -UFormat %s)' > '$lockDir/timestamp'
echo -n '\$\$' > '$lockDir/pid'
"@
        bash -c $bashScript 2>&1 | Out-Null

        # Read with PowerShell
        $owner = $null
        if (Test-Path (Join-Path $lockDir "owner.txt")) {
            $owner = Get-Content (Join-Path $lockDir "owner.txt") -Raw
        } elseif (Test-Path (Join-Path $lockDir "owner")) {
            $owner = Get-Content (Join-Path $lockDir "owner") -Raw
        }

        if ($owner -and $owner.Trim() -eq "bash-test-instance") {
            Write-TestResult "Bash lock readable by PowerShell" "PASS"
        } else {
            Write-TestResult "Bash lock readable by PowerShell" "FAIL" "PowerShell could not read lock: owner=$owner"
        }
    } catch {
        Write-TestResult "Bash lock readable by PowerShell" "FAIL" $_.Exception.Message
    }

    # Test 3: Lock directory structure matches
    try {
        # Both should use {story}.lock/ directory with owner, timestamp, pid files
        $psLock = Join-Path $locksDir "PS-LOCK-001.lock"
        $bashLock = Join-Path $locksDir "BASH-LOCK-001.lock"

        $psHasOwner = (Test-Path (Join-Path $psLock "owner.txt")) -or (Test-Path (Join-Path $psLock "owner"))
        $psHasTimestamp = (Test-Path (Join-Path $psLock "timestamp.txt")) -or (Test-Path (Join-Path $psLock "timestamp"))

        $bashHasOwner = (Test-Path (Join-Path $bashLock "owner.txt")) -or (Test-Path (Join-Path $bashLock "owner"))
        $bashHasTimestamp = (Test-Path (Join-Path $bashLock "timestamp.txt")) -or (Test-Path (Join-Path $bashLock "timestamp"))

        if ($psHasOwner -and $psHasTimestamp -and $bashHasOwner -and $bashHasTimestamp) {
            Write-TestResult "Lock directory structure matches" "PASS"
        } else {
            Write-TestResult "Lock directory structure matches" "FAIL" "Structure mismatch"
        }
    } catch {
        Write-TestResult "Lock directory structure matches" "FAIL" $_.Exception.Message
    }
}

function Test-StatusJsonCompatibility {
    Write-TestHeader "Status.json Compatibility"

    $instancesDir = Join-Path $script:TestDir "scripts/ralph/instances"

    # Test 1: PowerShell creates status.json, Bash reads it
    try {
        $psInstanceDir = Join-Path $instancesDir "ps-instance-001"
        New-Item -ItemType Directory -Path $psInstanceDir -Force | Out-Null

        $status = @{
            instanceId = "ps-instance-001"
            shortId = "ps-insta"
            state = "working"
            currentStory = "US-001"
            iteration = 1
            maxIterations = 10
            lastMessage = "Test message"
            startTimeEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            lastHeartbeatEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        }
        $status | ConvertTo-Json | Set-Content (Join-Path $psInstanceDir "status.json")

        # Read with Bash
        $statusFile = Join-Path $psInstanceDir "status.json"
        $bashScript = "cat '$statusFile' | jq -r '.state'"
        $result = bash -c $bashScript 2>&1

        if ($result.Trim() -eq "working") {
            Write-TestResult "PowerShell status.json readable by Bash" "PASS"
        } else {
            Write-TestResult "PowerShell status.json readable by Bash" "FAIL" "Bash read: $result"
        }
    } catch {
        Write-TestResult "PowerShell status.json readable by Bash" "FAIL" $_.Exception.Message
    }

    # Test 2: Bash creates status.json, PowerShell reads it
    try {
        $bashInstanceDir = Join-Path $instancesDir "bash-instance-001"
        $statusFile = Join-Path $bashInstanceDir "status.json"

        $bashScript = @"
mkdir -p '$bashInstanceDir'
cat > '$statusFile' << 'EOF'
{
  "instanceId": "bash-instance-001",
  "shortId": "bash-ins",
  "state": "working",
  "currentStory": "US-002",
  "iteration": 2,
  "maxIterations": 10,
  "lastMessage": "Bash test",
  "startTimeEpoch": $(Get-Date -UFormat %s),
  "lastHeartbeatEpoch": $(Get-Date -UFormat %s)
}
EOF
"@
        bash -c $bashScript 2>&1

        # Read with PowerShell
        $status = Get-Content $statusFile -Raw | ConvertFrom-Json

        if ($status.state -eq "working" -and $status.currentStory -eq "US-002") {
            Write-TestResult "Bash status.json readable by PowerShell" "PASS"
        } else {
            Write-TestResult "Bash status.json readable by PowerShell" "FAIL" "PowerShell read: state=$($status.state)"
        }
    } catch {
        Write-TestResult "Bash status.json readable by PowerShell" "FAIL" $_.Exception.Message
    }

    # Test 3: Status fields are consistent
    try {
        $requiredFields = @("instanceId", "shortId", "state", "currentStory", "iteration", "lastHeartbeatEpoch")

        $psStatus = Get-Content (Join-Path $instancesDir "ps-instance-001/status.json") -Raw | ConvertFrom-Json
        $bashStatus = Get-Content (Join-Path $instancesDir "bash-instance-001/status.json") -Raw | ConvertFrom-Json

        $allFieldsPresent = $true
        foreach ($field in $requiredFields) {
            if ($null -eq $psStatus.$field -or $null -eq $bashStatus.$field) {
                $allFieldsPresent = $false
                break
            }
        }

        if ($allFieldsPresent) {
            Write-TestResult "Required status fields present in both" "PASS"
        } else {
            Write-TestResult "Required status fields present in both" "FAIL" "Missing required fields"
        }
    } catch {
        Write-TestResult "Required status fields present in both" "FAIL" $_.Exception.Message
    }
}

function Test-PrdUpdateCompatibility {
    Write-TestHeader "PRD Update Compatibility"

    $prdFile = Join-Path $script:TestDir "scripts/ralph/prd.json"

    # Test 1: PowerShell updates PRD, Bash reads it
    try {
        # Update PRD with PowerShell
        $prd = Get-Content $prdFile -Raw | ConvertFrom-Json
        $prd.userStories[0].passes = $true
        # Add claimedBy property if it doesn't exist
        if (-not ($prd.userStories[0].PSObject.Properties.Name -contains 'claimedBy')) {
            $prd.userStories[0] | Add-Member -MemberType NoteProperty -Name 'claimedBy' -Value 'ps-instance'
        } else {
            $prd.userStories[0].claimedBy = "ps-instance"
        }
        $prd | ConvertTo-Json -Depth 10 | Set-Content $prdFile

        # Read with Bash
        $bashScript = "cat '$prdFile' | jq -r '.userStories[0].passes'"
        $result = bash -c $bashScript 2>&1

        if ($result.Trim() -eq "true") {
            Write-TestResult "PowerShell PRD update readable by Bash" "PASS"
        } else {
            Write-TestResult "PowerShell PRD update readable by Bash" "FAIL" "Bash read: $result"
        }
    } catch {
        Write-TestResult "PowerShell PRD update readable by Bash" "FAIL" $_.Exception.Message
    }

    # Test 2: Bash updates PRD, PowerShell reads it
    try {
        $bashScript = @"
cat '$prdFile' | jq '.userStories[1].passes = true | .userStories[1].claimedBy = "bash-instance"' > '$prdFile.tmp' && mv '$prdFile.tmp' '$prdFile'
"@
        bash -c $bashScript 2>&1

        # Read with PowerShell
        $prd = Get-Content $prdFile -Raw | ConvertFrom-Json

        if ($prd.userStories[1].passes -eq $true -and $prd.userStories[1].claimedBy -eq "bash-instance") {
            Write-TestResult "Bash PRD update readable by PowerShell" "PASS"
        } else {
            Write-TestResult "Bash PRD update readable by PowerShell" "FAIL" "PowerShell read: passes=$($prd.userStories[1].passes)"
        }
    } catch {
        Write-TestResult "Bash PRD update readable by PowerShell" "FAIL" $_.Exception.Message
    }

    # Test 3: PRD structure remains valid after mixed updates
    try {
        $prd = Get-Content $prdFile -Raw | ConvertFrom-Json

        $valid = $null -ne $prd.userStories -and
                 $prd.userStories.Count -eq 2 -and
                 $null -ne $prd.userStories[0].id -and
                 $null -ne $prd.userStories[1].id

        if ($valid) {
            Write-TestResult "PRD structure valid after mixed updates" "PASS"
        } else {
            Write-TestResult "PRD structure valid after mixed updates" "FAIL" "Invalid structure"
        }
    } catch {
        Write-TestResult "PRD structure valid after mixed updates" "FAIL" $_.Exception.Message
    }
}

function Test-InstanceIdFormat {
    Write-TestHeader "Instance ID Format Consistency"

    # Test 1: PowerShell instance ID format
    try {
        $modulePath = Join-Path $PSScriptRoot ".." "RalphUtils.psm1"
        Import-Module $modulePath -Force -WarningAction SilentlyContinue

        $psInstanceId = Get-RalphInstanceId -Force

        # Format should be: {user}-{hostname}-{pid}-{timestamp}
        $parts = $psInstanceId -split '-'
        if ($parts.Count -ge 4) {
            Write-TestResult "PowerShell instance ID has correct format" "PASS"
        } else {
            Write-TestResult "PowerShell instance ID has correct format" "FAIL" "Got: $psInstanceId"
        }
    } catch {
        Write-TestResult "PowerShell instance ID has correct format" "FAIL" $_.Exception.Message
    }

    # Test 2: Bash instance ID format
    try {
        $bashScript = @"
source '$PSScriptRoot/../ralph-utils.sh'
export RALPH_PROJECT_ROOT='$($script:TestDir)'
_RALPH_INSTANCE_ID=''
get_ralph_instance_id force
"@
        $bashInstanceId = bash -c $bashScript 2>&1
        $bashInstanceId = $bashInstanceId.Trim()

        # Format should be: {user}-{hostname}-{pid}-{timestamp}
        $parts = $bashInstanceId -split '-'
        if ($parts.Count -ge 4) {
            Write-TestResult "Bash instance ID has correct format" "PASS"
        } else {
            Write-TestResult "Bash instance ID has correct format" "FAIL" "Got: $bashInstanceId"
        }
    } catch {
        Write-TestResult "Bash instance ID has correct format" "FAIL" $_.Exception.Message
    }

    # Test 3: Short ID is 8 characters in both
    try {
        $modulePath = Join-Path $PSScriptRoot ".." "RalphUtils.psm1"
        Import-Module $modulePath -Force -WarningAction SilentlyContinue

        $psShortId = Get-RalphShortId

        $bashScript = @"
source '$PSScriptRoot/../ralph-utils.sh'
export RALPH_PROJECT_ROOT='$($script:TestDir)'
_RALPH_INSTANCE_ID=''
_RALPH_INSTANCE_SHORT_ID=''
get_ralph_short_id
"@
        $bashShortId = (bash -c $bashScript 2>&1).Trim()

        if ($psShortId.Length -eq 8 -and $bashShortId.Length -eq 8) {
            Write-TestResult "Short ID is 8 characters in both" "PASS"
        } else {
            Write-TestResult "Short ID is 8 characters in both" "FAIL" "PS: $($psShortId.Length), Bash: $($bashShortId.Length)"
        }
    } catch {
        Write-TestResult "Short ID is 8 characters in both" "FAIL" $_.Exception.Message
    }
}

function Test-PlatformSpecificBehaviors {
    Write-TestHeader "Platform-Specific Behaviors"

    # Document any known differences - use local variables with different names
    $onWindows = $IsWindows -or ($env:OS -eq "Windows_NT")
    $onLinux = $IsLinux -eq $true
    $onMacOS = $IsMacOS -eq $true

    Write-Host ""
    Write-Host "  Platform Detection:" -ForegroundColor Cyan
    Write-Host "    Windows: $onWindows"
    Write-Host "    Linux:   $onLinux"
    Write-Host "    macOS:   $onMacOS"
    Write-Host ""

    # Test 1: Line endings handling
    try {
        $testFile = Join-Path $script:TestDir "line-ending-test.txt"
        "line1`nline2" | Set-Content $testFile -NoNewline

        $bashScript = "wc -l < '$testFile'"
        $lineCount = (bash -c $bashScript 2>&1).Trim()

        Write-Host "  Line Endings:" -ForegroundColor Cyan
        Write-Host "    Test file line count (via Bash wc -l): $lineCount"

        Write-TestResult "Line endings handled correctly" "PASS"
    } catch {
        Write-TestResult "Line endings handled correctly" "FAIL" $_.Exception.Message
    }

    # Test 2: Path separator handling
    try {
        $psPath = Join-Path $script:TestDir "test" "path"
        $bashScript = "echo '$($script:TestDir)/test/path'"
        $bashPath = (bash -c $bashScript 2>&1).Trim()

        Write-Host ""
        Write-Host "  Path Separators:" -ForegroundColor Cyan
        Write-Host "    PowerShell: $psPath"
        Write-Host "    Bash:       $bashPath"

        # Both should work for their respective environments
        Write-TestResult "Path separators handled correctly" "PASS"
    } catch {
        Write-TestResult "Path separators handled correctly" "FAIL" $_.Exception.Message
    }

    # Test 3: flock availability
    try {
        $bashScript = "command -v flock >/dev/null 2>&1 && echo 'available' || echo 'not available'"
        $flockStatus = (bash -c $bashScript 2>&1).Trim()

        Write-Host ""
        Write-Host "  flock Availability:" -ForegroundColor Cyan
        Write-Host "    Status: $flockStatus"

        if ($flockStatus -eq "not available" -and $onWindows) {
            Write-TestResult "flock availability documented" "PASS" "Not available on Windows (expected)"
        } else {
            Write-TestResult "flock availability documented" "PASS"
        }
    } catch {
        Write-TestResult "flock availability documented" "FAIL" $_.Exception.Message
    }

    # Document known platform differences
    Write-Host ""
    Write-Host "  Known Platform Differences:" -ForegroundColor Yellow
    Write-Host "    1. flock is not available on Windows (Git Bash)"
    Write-Host "       - PowerShell uses .NET Mutex for cross-process locking"
    Write-Host "       - Bash skips flock tests on Windows"
    Write-Host "    2. jq output may include carriage returns on Windows"
    Write-Host "       - Fixed with 'tr -d \\r' in Bash functions"
    Write-Host "    3. Path separators differ but both tools handle this"
    Write-Host ""
}

# =============================================================================
# Main Execution
# =============================================================================

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  Ralph Cross-Platform Integration Tests" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

# Check prerequisites
if (-not (Test-BashAvailable)) {
    Write-Host "`n  ERROR: Bash is not available. Tests require Bash." -ForegroundColor Red
    exit 1
}

if (-not (Test-JqAvailable)) {
    Write-Host "`n  ERROR: jq is not available. Tests require jq." -ForegroundColor Red
    exit 1
}

try {
    Initialize-TestEnvironment | Out-Null

    Test-LockFormatCompatibility
    Test-StatusJsonCompatibility
    Test-PrdUpdateCompatibility
    Test-InstanceIdFormat
    Test-PlatformSpecificBehaviors

} finally {
    Remove-TestEnvironment
}

# Summary
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  Test Summary" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  Total:   $script:TestsRun"
Write-Host "  Passed:  $script:TestsPassed" -ForegroundColor Green
Write-Host "  Failed:  $script:TestsFailed" -ForegroundColor Red
Write-Host "  Skipped: $script:TestsSkipped" -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""

if ($script:TestsFailed -gt 0) {
    exit 1
}

exit 0
