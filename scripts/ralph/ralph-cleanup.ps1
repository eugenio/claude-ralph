#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Clean up old and dead Ralph instances.

.DESCRIPTION
    ralph-cleanup.ps1 removes dead instances (no heartbeat >5 min) and
    old instances (older than configured TTL).

.PARAMETER Dead
    Clean up dead instances.

.PARAMETER Old
    Clean up old instances (default TTL: 7 days).

.PARAMETER All
    Clean up both dead and old instances.

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
    Write-Host '                  INSTANCE SUMMARY' -ForegroundColor Cyan
    Write-Host ([string]::new([char]0x2550, 60)) -ForegroundColor Blue
    Write-Host ''

    $paths = Get-RalphPaths
    $instancesDir = Join-Path $paths.RalphDir 'instances'

    if (-not (Test-Path $instancesDir)) {
        Write-Host 'No instances directory'
        return
    }

    $instances = Get-RalphInstances -IncludeDead
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
    Write-Host 'Checking for dead instances...' -ForegroundColor Blue

    $instances = Get-RalphInstances -IncludeDead
    $dead = @($instances | Where-Object { $_.isDead })
    $cleaned = 0

    foreach ($instance in $dead) {
        Write-Host "  Dead instance: $($instance.shortId) (no heartbeat for $($instance.heartbeatAge)s)" -ForegroundColor Yellow

        if ($PSCmdlet.ShouldProcess($instance.instanceId, 'Mark as terminated and release locks')) {
            # Update status to terminated
            $paths = Get-RalphPaths
            $statusFile = Join-Path (Join-Path (Join-Path $paths.RalphDir 'instances') $instance.instanceId) 'status.json'

            if (Test-Path $statusFile) {
                $status = Get-Content $statusFile -Raw | ConvertFrom-Json
                $status.state = 'terminated'
                $status | ConvertTo-Json -Depth 5 | Set-Content $statusFile -Force
            }

            # Release any locks
            Get-RalphStoryLocks | Where-Object { $_.Owner -eq $instance.instanceId } | ForEach-Object {
                Write-Host "    Releasing lock: $($_.StoryId)" -ForegroundColor Yellow
                $null = Unlock-RalphStory -StoryId $_.StoryId -Force
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

function Clear-OldInstances {
    Write-Host 'Checking for old instances...' -ForegroundColor Blue

    $ttlDays = [int]($env:RALPH_CLEANUP_TTL ?? 7)
    $cutoff = [DateTimeOffset]::UtcNow.AddDays(-$ttlDays).ToUnixTimeSeconds()

    $paths = Get-RalphPaths
    $instancesDir = Join-Path $paths.RalphDir 'instances'

    if (-not (Test-Path $instancesDir)) {
        Write-Host 'No instances directory' -ForegroundColor Green
        return
    }

    $cleaned = 0
    Get-ChildItem -Path $instancesDir -Directory | ForEach-Object {
        $statusFile = Join-Path $_.FullName 'status.json'
        if (Test-Path $statusFile) {
            try {
                $status = Get-Content $statusFile -Raw | ConvertFrom-Json
                if ($status.lastHeartbeatEpoch -lt $cutoff) {
                    $ageDays = [math]::Floor(([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $status.lastHeartbeatEpoch) / 86400)
                    Write-Host "  Old instance: $($_.Name) ($ageDays days old)" -ForegroundColor Yellow

                    if ($PSCmdlet.ShouldProcess($_.Name, 'Remove instance directory')) {
                        Remove-Item -Path $_.FullName -Recurse -Force
                        $cleaned++
                    }
                }
            }
            catch {
                Write-Warning "Failed to check $($_.Name): $_"
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
    $Old = $true
}

if (-not $Dead -and -not $Old) {
    Show-Summary
    Write-Host 'Run with -Dead, -Old, or -All to clean up instances'
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

if ($Old) {
    Clear-OldInstances
    Write-Host ''
}

Show-Summary
