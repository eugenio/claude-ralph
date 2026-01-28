#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    TUI dashboard for monitoring Ralph instances.

.DESCRIPTION
    ralph-dashboard.ps1 provides a real-time terminal dashboard showing
    all running Ralph instances, their status, and PRD progress.

.PARAMETER RefreshInterval
    Seconds between dashboard refreshes. Default: 2.

.EXAMPLE
    ./ralph-dashboard.ps1
    Launch dashboard with default settings.

.EXAMPLE
    ./ralph-dashboard.ps1 -RefreshInterval 5
    Refresh every 5 seconds.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [int]$RefreshInterval = 2
)

# Import module
$modulePath = Join-Path $PSScriptRoot 'RalphUtils.psm1'
if (-not (Test-Path $modulePath)) {
    Write-Host 'Error: RalphUtils.psm1 not found' -ForegroundColor Red
    exit 1
}
Import-Module $modulePath -Force

function Get-ProgressBar {
    param(
        [int]$Complete,
        [int]$Total,
        [int]$Width = 30
    )

    if ($Total -eq 0) {
        return '[' + (' ' * $Width) + ']'
    }

    $filled = [math]::Floor($Complete * $Width / $Total)
    $empty = $Width - $filled

    $bar = '[' + ([char]0x2588 * $filled) + ([char]0x2591 * $empty) + ']'
    return $bar
}

function Format-Duration {
    param([long]$Seconds)

    if ($Seconds -lt 60) {
        return "${Seconds}s"
    }
    elseif ($Seconds -lt 3600) {
        $m = [math]::Floor($Seconds / 60)
        $s = $Seconds % 60
        return "${m}m ${s}s"
    }
    else {
        $h = [math]::Floor($Seconds / 3600)
        $m = [math]::Floor(($Seconds % 3600) / 60)
        return "${h}h ${m}m"
    }
}

function Get-StateColor {
    param([string]$State)

    switch ($State) {
        'working' { return 'Green' }
        'merging' { return 'Green' }
        'claiming' { return 'Cyan' }
        'starting' { return 'Cyan' }
        'idle' { return 'Yellow' }
        'completed' { return 'Blue' }
        'terminated' { return 'Gray' }
        'max_iterations' { return 'Gray' }
        'dead' { return 'Red' }
        default { return 'White' }
    }
}

function Render-Header {
    $prd = Read-PrdJson
    $status = Get-PrdStatus -Prd $prd

    Write-Host ([char]0x2554 + [string]::new([char]0x2550, 73) + [char]0x2557) -ForegroundColor Blue
    Write-Host ([char]0x2551 + '              RALPH DASHBOARD                                            ' + [char]0x2551) -ForegroundColor Blue
    Write-Host ([char]0x2560 + [string]::new([char]0x2550, 73) + [char]0x2563) -ForegroundColor Blue

    # Progress bar
    $bar = Get-ProgressBar -Complete $status.Complete -Total $status.Total
    $progressText = "  PRD Progress: $bar $($status.Complete)/$($status.Total)"
    $padding = 73 - $progressText.Length
    Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
    Write-Host $progressText -NoNewline
    Write-Host (' ' * $padding) -NoNewline
    Write-Host ([char]0x2551) -ForegroundColor Blue

    Write-Host ([char]0x2560 + [string]::new([char]0x2550, 73) + [char]0x2563) -ForegroundColor Blue
}

function Render-Instances {
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    # Header
    $headerLine = ' {0,-10} {1,-12} {2,-12} {3,-6} {4,-12} {5,-14}' -f 'INSTANCE', 'STORY', 'STATE', 'ITER', 'RUNTIME', 'BRANCH'
    Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
    Write-Host $headerLine -NoNewline -ForegroundColor White
    Write-Host ([char]0x2551) -ForegroundColor Blue

    $dividerLine = ' {0,-10} {1,-12} {2,-12} {3,-6} {4,-12} {5,-14}' -f '--------', '-----', '-----', '----', '-------', '------'
    Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
    Write-Host $dividerLine -NoNewline -ForegroundColor Gray
    Write-Host ([char]0x2551) -ForegroundColor Blue

    $instances = Get-RalphInstances -IncludeDead

    if ($instances.Count -eq 0) {
        $emptyLine = '  No instances running' + (' ' * 51)
        Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
        Write-Host $emptyLine -NoNewline -ForegroundColor Gray
        Write-Host ([char]0x2551) -ForegroundColor Blue
    }
    else {
        foreach ($instance in $instances) {
            $state = if ($instance.isDead) { 'dead' } else { $instance.state }
            $color = Get-StateColor -State $state

            # Calculate runtime
            $startEpoch = $instance.instanceId -replace '.*-(\d+)$', '$1'
            if ($startEpoch -match '^\d+$') {
                $runtime = $now - [long]$startEpoch
                $runtimeStr = Format-Duration -Seconds $runtime
            }
            else {
                $runtimeStr = '-'
            }

            # Truncate branch
            $branch = if ($instance.branch.Length -gt 14) { $instance.branch.Substring(0, 11) + '...' } else { $instance.branch }
            if (-not $branch) { $branch = '-' }

            $story = if ($instance.currentStory) { $instance.currentStory } else { '-' }
            $iter = "$($instance.iteration)/$($instance.maxIterations)"

            $line = ' {0,-10} {1,-12} ' -f $instance.shortId, $story
            Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
            Write-Host $line -NoNewline
            Write-Host ('{0,-12} ' -f $state) -NoNewline -ForegroundColor $color
            Write-Host ('{0,-6} {1,-12} {2,-14}' -f $iter, $runtimeStr, $branch) -NoNewline
            Write-Host ([char]0x2551) -ForegroundColor Blue
        }
    }
}

function Render-Locks {
    Write-Host ([char]0x2560 + [string]::new([char]0x2550, 73) + [char]0x2563) -ForegroundColor Blue

    $locks = Get-RalphStoryLocks
    $lockHeader = '  ACTIVE LOCKS' + (' ' * 59)
    Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
    Write-Host $lockHeader -NoNewline -ForegroundColor White
    Write-Host ([char]0x2551) -ForegroundColor Blue

    if ($locks.Count -eq 0) {
        $noLocks = '    No active locks' + (' ' * 54)
        Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
        Write-Host $noLocks -NoNewline -ForegroundColor Gray
        Write-Host ([char]0x2551) -ForegroundColor Blue
    }
    else {
        foreach ($lock in $locks | Select-Object -First 5) {
            $ageStr = Format-Duration -Seconds $lock.Age
            $ownerShort = if ($lock.Owner.Length -gt 10) { $lock.Owner.Substring(0, 7) + '...' } else { $lock.Owner }

            $color = if ($lock.IsDead) { 'Red' } elseif ($lock.IsStale) { 'Yellow' } else { 'Green' }

            $lockLine = '    {0,-10} held by {1,-10} for {2,-10}' -f $lock.StoryId, $ownerShort, $ageStr
            $padding = 73 - $lockLine.Length
            Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
            Write-Host $lockLine -NoNewline -ForegroundColor $color
            Write-Host (' ' * $padding) -NoNewline
            Write-Host ([char]0x2551) -ForegroundColor Blue
        }

        if ($locks.Count -gt 5) {
            $more = "    ... and $($locks.Count - 5) more"
            $padding = 73 - $more.Length
            Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
            Write-Host $more -NoNewline -ForegroundColor Gray
            Write-Host (' ' * $padding) -NoNewline
            Write-Host ([char]0x2551) -ForegroundColor Blue
        }
    }
}

function Render-Footer {
    Write-Host ([char]0x2560 + [string]::new([char]0x2550, 73) + [char]0x2563) -ForegroundColor Blue

    $helpLine = '  Press: q=quit  r=refresh  l=locks  c=cleanup' + (' ' * 27)
    Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
    Write-Host $helpLine -NoNewline -ForegroundColor Gray
    Write-Host ([char]0x2551) -ForegroundColor Blue

    $timeLine = "  Last update: $(Get-Date -Format 'HH:mm:ss')" + (' ' * 49)
    Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
    Write-Host $timeLine -NoNewline -ForegroundColor Gray
    Write-Host ([char]0x2551) -ForegroundColor Blue

    Write-Host ([char]0x255A + [string]::new([char]0x2550, 73) + [char]0x255D) -ForegroundColor Blue
}

function Render-Dashboard {
    Clear-Host
    Render-Header
    Render-Instances
    Render-Locks
    Render-Footer
}

function Show-LocksDetail {
    Clear-Host
    & (Join-Path $PSScriptRoot 'ralph-locks.ps1') Status
    Write-Host ''
    Write-Host 'Press any key to return to dashboard...' -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

function Invoke-Cleanup {
    Clear-Host
    & (Join-Path $PSScriptRoot 'ralph-cleanup.ps1') -Dead
    Write-Host ''
    Write-Host 'Press any key to return to dashboard...' -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

# Main loop
try {
    [Console]::CursorVisible = $false

    while ($true) {
        Render-Dashboard

        # Wait for key or timeout
        $timeout = [DateTime]::Now.AddSeconds($RefreshInterval)
        while ([DateTime]::Now -lt $timeout) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                switch ($key.KeyChar) {
                    'q' { return }
                    'Q' { return }
                    'r' { break }  # Force refresh
                    'R' { break }
                    'l' { Show-LocksDetail; break }
                    'L' { Show-LocksDetail; break }
                    'c' { Invoke-Cleanup; break }
                    'C' { Invoke-Cleanup; break }
                }
                break
            }
            Start-Sleep -Milliseconds 100
        }
    }
}
finally {
    [Console]::CursorVisible = $true
    Clear-Host
}
