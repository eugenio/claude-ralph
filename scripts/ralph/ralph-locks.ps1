#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Manage story locks for multi-instance Ralph.

.DESCRIPTION
    ralph-locks.ps1 provides commands to view, release, and clean up story locks
    used by concurrent Ralph instances.

.PARAMETER Command
    The command to execute: Status, Release, ReleaseAll, Cleanup

.PARAMETER StoryId
    For Release command: the story ID to release.

.EXAMPLE
    ./ralph-locks.ps1 Status
    Shows all current locks.

.EXAMPLE
    ./ralph-locks.ps1 Release -StoryId US-001
    Force releases the lock on US-001.

.EXAMPLE
    ./ralph-locks.ps1 Cleanup
    Removes stale locks.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Status', 'Release', 'ReleaseAll', 'Cleanup', 'Help')]
    [string]$Command = 'Status',

    [Parameter()]
    [string]$StoryId
)

# Import module
$modulePath = Join-Path $PSScriptRoot 'RalphUtils.psm1'
if (-not (Test-Path $modulePath)) {
    Write-Host 'Error: RalphUtils.psm1 not found' -ForegroundColor Red
    exit 1
}
Import-Module $modulePath -Force

function Show-Help {
    Write-Host ''
    Write-Host 'Usage: ./ralph-locks.ps1 <Command> [Options]' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Commands:' -ForegroundColor Yellow
    Write-Host '  Status              Show all current locks'
    Write-Host '  Release -StoryId X  Force release a specific lock'
    Write-Host '  ReleaseAll          Force release all locks'
    Write-Host '  Cleanup             Remove stale locks (>2 hours or dead owner)'
    Write-Host '  Help                Show this help'
    Write-Host ''
    Write-Host 'Examples:' -ForegroundColor Yellow
    Write-Host '  ./ralph-locks.ps1 Status'
    Write-Host '  ./ralph-locks.ps1 Release -StoryId US-001'
    Write-Host '  ./ralph-locks.ps1 Cleanup'
    Write-Host ''
}

function Show-LockStatus {
    Write-Host ''
    Write-Host ([string]::new([char]0x2550, 60)) -ForegroundColor Blue
    Write-Host '                    RALPH LOCK STATUS' -ForegroundColor Cyan
    Write-Host ([string]::new([char]0x2550, 60)) -ForegroundColor Blue
    Write-Host ''

    $locks = Get-RalphStoryLocks

    if ($locks.Count -eq 0) {
        Write-Host '  No active locks' -ForegroundColor Green
        Write-Host ''
        return
    }

    # Header
    Write-Host ('{0,-12} {1,-30} {2,-10} {3,-10}' -f 'STORY', 'OWNER', 'AGE', 'STATUS') -ForegroundColor White
    Write-Host ('{0,-12} {1,-30} {2,-10} {3,-10}' -f '-----', '-----', '---', '------')

    foreach ($lock in $locks) {
        # Format age
        $ageStr = if ($lock.Age -lt 60) { "$($lock.Age)s" }
                  elseif ($lock.Age -lt 3600) { "$([math]::Floor($lock.Age / 60))m" }
                  else { "$([math]::Floor($lock.Age / 3600))h" }

        # Determine status and color
        $status = 'valid'
        $color = 'Green'
        if ($lock.IsDead) {
            $status = 'dead owner'
            $color = 'Red'
        }
        elseif ($lock.IsStale) {
            $status = 'stale'
            $color = 'Yellow'
        }

        $ownerShort = if ($lock.Owner.Length -gt 30) { $lock.Owner.Substring(0, 27) + '...' } else { $lock.Owner }

        Write-Host ('{0,-12} {1,-30} {2,-10} ' -f $lock.StoryId, $ownerShort, $ageStr) -NoNewline
        Write-Host $status -ForegroundColor $color
    }

    Write-Host ''
}

function Invoke-Release {
    param([string]$StoryId)

    if (-not $StoryId) {
        Write-Host 'Error: StoryId required for Release command' -ForegroundColor Red
        Write-Host 'Usage: ./ralph-locks.ps1 Release -StoryId US-001'
        exit 1
    }

    $lock = Get-RalphStoryLock -StoryId $StoryId
    if (-not $lock) {
        Write-Host "No lock found for $StoryId" -ForegroundColor Yellow
        return
    }

    Write-Host "Releasing lock for $StoryId (owner: $($lock.Owner))..." -ForegroundColor Yellow

    if (Unlock-RalphStory -StoryId $StoryId -Force) {
        Write-Host 'Lock released' -ForegroundColor Green
    }
    else {
        Write-Host 'Failed to release lock' -ForegroundColor Red
    }
}

function Invoke-ReleaseAll {
    Write-Host 'Releasing all locks...' -ForegroundColor Yellow

    $locks = Get-RalphStoryLocks
    $count = 0

    foreach ($lock in $locks) {
        if (Unlock-RalphStory -StoryId $lock.StoryId -Force) {
            Write-Host "  Released: $($lock.StoryId)" -ForegroundColor Gray
            $count++
        }
    }

    Write-Host "Released $count locks" -ForegroundColor Green
}

function Invoke-Cleanup {
    Write-Host 'Cleaning up stale locks...' -ForegroundColor Blue

    $locks = Get-RalphStoryLocks
    $cleaned = 0

    foreach ($lock in $locks) {
        if ($lock.IsDead -or $lock.IsStale) {
            $reason = if ($lock.IsDead) { 'dead owner' } else { "stale ($($lock.Age)s)" }
            Write-Host "  Removing: $($lock.StoryId) - $reason" -ForegroundColor Yellow

            if (Unlock-RalphStory -StoryId $lock.StoryId -Force) {
                $cleaned++
            }
        }
    }

    if ($cleaned -eq 0) {
        Write-Host 'No stale locks found' -ForegroundColor Green
    }
    else {
        Write-Host "Cleaned up $cleaned stale locks" -ForegroundColor Green
    }
}

# Main
switch ($Command) {
    'Status' { Show-LockStatus }
    'Release' { Invoke-Release -StoryId $StoryId }
    'ReleaseAll' { Invoke-ReleaseAll }
    'Cleanup' { Invoke-Cleanup }
    'Help' { Show-Help }
    default { Show-Help }
}
