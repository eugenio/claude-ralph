#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Clean up old and dead Ralph instances.

.DESCRIPTION
    ralph-cleanup.ps1 removes dead instances (no heartbeat >5 min) and
    old instances (older than configured TTL).

.PARAMETER Dead
    Clean up dead instances (no heartbeat > 5 min).

.PARAMETER Terminated
    Clean up terminated instances (cleanly finished).

.PARAMETER Old
    Clean up old instances (default TTL: 7 days).

.PARAMETER All
    Clean up dead, terminated, and old instances.

.PARAMETER WhatIf
    Show what would be cleaned without actually deleting.

.EXAMPLE
    ./ralph-cleanup.ps1
    Shows instance summary.

.EXAMPLE
    ./ralph-cleanup.ps1 -Dead
    Cleans up dead instances.

.EXAMPLE
    ./ralph-cleanup.ps1 -All -WhatIf
    Preview cleanup without deleting.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [switch]$Dead,

    [Parameter()]
    [switch]$Terminated,

    [Parameter()]
    [switch]$Old,

    [Parameter()]
    [switch]$All
)

# Import module
$modulePath = Join-Path $PSScriptRoot 'RalphUtils.psm1'
if (-not (Test-Path $modulePath)) {
    Write-Host 'Error: RalphUtils.psm1 not found' -ForegroundColor Red
    exit 1
}
Import-Module $modulePath -Force

function Show-Summary {
    Write-Host ''
    Write-Host ([string]::new([char]0x2550, 60)) -ForegroundColor Blue
    Write-Host '                  INSTANCE SUMMARY (Global)' -ForegroundColor Cyan
    Write-Host ([string]::new([char]0x2550, 60)) -ForegroundColor Blue
    Write-Host ''

    # Use global instances to show all projects
    $instances = Get-RalphGlobalInstances -IncludeDead
    $total = $instances.Count
    $running = @($instances | Where-Object { -not $_.isDead -and $_.state -notin @('terminated', 'completed') }).Count
    $completed = @($instances | Where-Object { $_.state -eq 'completed' }).Count
    $terminated = @($instances | Where-Object { $_.state -eq 'terminated' }).Count
    $dead = @($instances | Where-Object { $_.isDead }).Count

    Write-Host "Total instances: $total"
    Write-Host "  Running:    $running" -ForegroundColor Green
    Write-Host "  Completed:  $completed" -ForegroundColor Blue
    Write-Host "  Terminated: $terminated" -ForegroundColor Yellow
    Write-Host "  Dead:       $dead" -ForegroundColor Red
    Write-Host ''

    # Show locks
    $locks = Get-RalphStoryLocks
    Write-Host "Active locks: $($locks.Count)"
    Write-Host ''
}

function Clear-DeadInstances {
    Write-Host 'Checking for dead instances (global)...' -ForegroundColor Blue

    $instances = Get-RalphGlobalInstances -IncludeDead
    $dead = @($instances | Where-Object { $_.isDead })
    $cleaned = 0

    $globalDir = Get-RalphGlobalDir

    foreach ($instance in $dead) {
        $projectName = if ($instance.projectName) { $instance.projectName } else { 'unknown' }
        Write-Host "  Dead: $projectName ($($instance.instanceId)) - no heartbeat for $($instance.heartbeatAge)s" -ForegroundColor Yellow

        if ($PSCmdlet.ShouldProcess($instance.instanceId, 'Mark as terminated and release locks')) {
            # Find instance directory via global registry link by matching instanceId suffix
            $instancesDir = Join-Path $globalDir 'instances'
            $instanceDir = $null
            $linkItem = $null

            if (Test-Path $instancesDir) {
                # Find link ending with the instanceId
                $linkItem = Get-ChildItem -Path $instancesDir -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "*-$($instance.instanceId)" } |
                    Select-Object -First 1

                if ($linkItem) {
                    # Handle both SymbolicLink (Unix) and Junction (Windows)
                    if ($linkItem.LinkType -in @('SymbolicLink', 'Junction')) {
                        $instanceDir = $linkItem.Target
                    }
                }
            }

            # Update status to terminated
            if ($instanceDir -and (Test-Path (Join-Path $instanceDir 'status.json'))) {
                $statusFile = Join-Path $instanceDir 'status.json'
                $status = Get-Content $statusFile -Raw | ConvertFrom-Json
                $status.state = 'terminated'
                $status | ConvertTo-Json -Depth 5 | Set-Content $statusFile -Force
            }

            # Release any global locks
            $locksDir = Join-Path $globalDir 'locks'
            if (Test-Path $locksDir) {
                Get-ChildItem -Path $locksDir -Filter '*.lock' | ForEach-Object {
                    try {
                        $lock = Get-Content $_.FullName -Raw | ConvertFrom-Json
                        if ($lock.owner -eq $instance.instanceId) {
                            Write-Host "    Releasing lock: $($_.BaseName)" -ForegroundColor Yellow
                            Remove-Item $_.FullName -Force
                        }
                    }
                    catch { }
                }
            }

            $cleaned++
        }
    }

    if ($cleaned -eq 0 -and $dead.Count -eq 0) {
        Write-Host 'No dead instances found' -ForegroundColor Green
    }
    elseif ($WhatIfPreference) {
        Write-Host "Would clean up $($dead.Count) dead instances" -ForegroundColor Yellow
    }
    else {
        Write-Host "Cleaned up $cleaned dead instances" -ForegroundColor Green
    }
}

function Clear-TerminatedInstances {
    Write-Host 'Checking for terminated instances (global)...' -ForegroundColor Blue

    $globalDir = Get-RalphGlobalDir
    $instancesDir = Join-Path $globalDir 'instances'

    if (-not (Test-Path $instancesDir)) {
        Write-Host 'No global instances directory' -ForegroundColor Green
        return
    }

    $cleaned = 0

    Get-ChildItem -Path $instancesDir | ForEach-Object {
        $link = $_
        $instanceDir = $null

        # Resolve symlink or directory
        # Handle both SymbolicLink (Unix) and Junction (Windows)
        if ($link.LinkType -in @('SymbolicLink', 'Junction')) {
            $instanceDir = $link.Target
        }
        elseif ($link.PSIsContainer) {
            $instanceDir = $link.FullName
        }

        if ($instanceDir -and (Test-Path $instanceDir)) {
            $statusFile = Join-Path $instanceDir 'status.json'
            if (Test-Path $statusFile) {
                try {
                    $status = Get-Content $statusFile -Raw | ConvertFrom-Json
                    $state = $status.state

                    if ($state -in @('terminated', 'completed')) {
                        $projectName = $link.Name -replace '-uge-.*$', ''
                        Write-Host "  Terminated: $projectName ($state)" -ForegroundColor Yellow

                        if ($PSCmdlet.ShouldProcess($link.Name, 'Remove instance directory and global link')) {
                            # Remove actual instance directory
                            Remove-Item -Path $instanceDir -Recurse -Force -ErrorAction SilentlyContinue
                            # Remove global registry link
                            Remove-Item -Path $link.FullName -Force -ErrorAction SilentlyContinue
                            $cleaned++
                        }
                    }
                }
                catch {
                    Write-Warning "Failed to check $($link.Name): $_"
                }
            }
        }
    }

    if ($cleaned -eq 0 -and -not $WhatIfPreference) {
        Write-Host 'No terminated instances found' -ForegroundColor Green
    }
    elseif ($WhatIfPreference) {
        Write-Host 'Would remove terminated instances' -ForegroundColor Yellow
    }
    else {
        Write-Host "Removed $cleaned terminated instances" -ForegroundColor Green
    }
}

function Clear-OldInstances {
    Write-Host 'Checking for old instances (global)...' -ForegroundColor Blue

    $ttlDays = [int]($env:RALPH_CLEANUP_TTL ?? 7)
    $cutoff = [DateTimeOffset]::UtcNow.AddDays(-$ttlDays).ToUnixTimeSeconds()

    $globalDir = Get-RalphGlobalDir
    $instancesDir = Join-Path $globalDir 'instances'

    if (-not (Test-Path $instancesDir)) {
        Write-Host 'No global instances directory' -ForegroundColor Green
        return
    }

    $cleaned = 0
    Get-ChildItem -Path $instancesDir | ForEach-Object {
        $link = $_
        $instanceDir = $null

        # Handle both SymbolicLink (Unix) and Junction (Windows)
        if ($link.LinkType -in @('SymbolicLink', 'Junction')) {
            $instanceDir = $link.Target
        }
        elseif ($link.PSIsContainer) {
            $instanceDir = $link.FullName
        }

        if ($instanceDir -and (Test-Path $instanceDir)) {
            $statusFile = Join-Path $instanceDir 'status.json'
            if (Test-Path $statusFile) {
                try {
                    $status = Get-Content $statusFile -Raw | ConvertFrom-Json
                    if ($status.lastHeartbeatEpoch -lt $cutoff) {
                        $ageDays = [math]::Floor(([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $status.lastHeartbeatEpoch) / 86400)
                        $projectName = $link.Name -replace '-uge-.*$', ''
                        Write-Host "  Old: $projectName ($ageDays days old)" -ForegroundColor Yellow

                        if ($PSCmdlet.ShouldProcess($link.Name, 'Remove instance directory and global link')) {
                            # Remove actual instance directory
                            Remove-Item -Path $instanceDir -Recurse -Force -ErrorAction SilentlyContinue
                            # Remove global registry link
                            Remove-Item -Path $link.FullName -Force -ErrorAction SilentlyContinue
                            $cleaned++
                        }
                    }
                }
                catch {
                    Write-Warning "Failed to check $($link.Name): $_"
                }
            }
        }
    }

    if ($cleaned -eq 0 -and -not $WhatIfPreference) {
        Write-Host "No old instances found (TTL: $ttlDays days)" -ForegroundColor Green
    }
    elseif ($WhatIfPreference) {
        Write-Host "Would remove old instances (TTL: $ttlDays days)" -ForegroundColor Yellow
    }
    else {
        Write-Host "Removed $cleaned old instances" -ForegroundColor Green
    }
}

# Main
if ($All) {
    $Dead = $true
    $Terminated = $true
    $Old = $true
}

if (-not $Dead -and -not $Terminated -and -not $Old) {
    Show-Summary
    Write-Host 'Run with -Dead, -Terminated, -Old, or -All to clean up instances'
    exit 0
}

if ($WhatIfPreference) {
    Write-Host 'WHATIF MODE - No changes will be made' -ForegroundColor Yellow
    Write-Host ''
}

if ($Dead) {
    Clear-DeadInstances
    Write-Host ''
}

if ($Terminated) {
    Clear-TerminatedInstances
    Write-Host ''
}

if ($Old) {
    Clear-OldInstances
    Write-Host ''
}

Show-Summary
