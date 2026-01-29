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

# Dynamic frame width
$script:MinFrameWidth = 60
$script:FrameWidth = 73

function Get-FrameWidth {
    $termWidth = [Console]::WindowWidth
    if ($termWidth -lt 1) { $termWidth = 80 }
    $width = $termWidth - 2
    if ($width -lt $script:MinFrameWidth) { $width = $script:MinFrameWidth }
    return $width
}

function Get-ProgressBar {
    param(
        [int]$Complete,
        [int]$Total,
        [int]$Width = 30
    )

    if ($Total -eq 0) {
        return '[' + (' ' * $Width) + ']'
    }

    $filled = [int][math]::Floor($Complete * $Width / $Total)
    $empty = [int]($Width - $filled)

    $bar = '[' + ([string][char]0x2588 * $filled) + ([string][char]0x2591 * $empty) + ']'
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
    Write-Host ([char]0x2554 + [string]::new([char]0x2550, $script:FrameWidth) + [char]0x2557) -ForegroundColor Blue
    $title = 'RALPH DASHBOARD'
    $titlePad = [Math]::Max(0, $script:FrameWidth - $title.Length)
    $leftPad = [Math]::Floor($titlePad / 2)
    $rightPad = $titlePad - $leftPad
    Write-Host ([char]0x2551 + (' ' * $leftPad) + $title + (' ' * $rightPad) + [char]0x2551) -ForegroundColor Blue
    Write-Host ([char]0x2560 + [string]::new([char]0x2550, $script:FrameWidth) + [char]0x2563) -ForegroundColor Blue

    # Get all projects PRD status
    $projectsStatus = Get-AllProjectsPrdStatus
    if ($projectsStatus.Count -eq 0) {
        $emptyText = '  No PRD files found'
        $padding = $script:FrameWidth - $emptyText.Length
        Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
        Write-Host $emptyText -NoNewline -ForegroundColor Gray
        Write-Host (' ' * $padding) -NoNewline
        Write-Host ([char]0x2551) -ForegroundColor Blue
    } else {
        # Show each project's progress (max 4)
        $shown = 0
        foreach ($proj in $projectsStatus | Select-Object -First 4) {
            $name = $proj.Name
            if ($name.Length -gt 12) { $name = $name.Substring(0, 9) + '...' }
            $bar = Get-ProgressBar -Complete $proj.Complete -Total $proj.Total -Width 20
            $progressText = '  {0,-12} {1} {2}/{3}' -f $name, $bar, $proj.Complete, $proj.Total
            $padding = $script:FrameWidth - $progressText.Length
            Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
            Write-Host $progressText -NoNewline
            Write-Host (' ' * [Math]::Max(0, $padding)) -NoNewline
            Write-Host ([char]0x2551) -ForegroundColor Blue
            $shown++
        }
        if ($projectsStatus.Count -gt 4) {
            $moreCount = $projectsStatus.Count - 4
            $moreText = "  ... and $moreCount more projects"
            $padding = $script:FrameWidth - $moreText.Length
            Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
            Write-Host $moreText -NoNewline -ForegroundColor Gray
            Write-Host (' ' * $padding) -NoNewline
            Write-Host ([char]0x2551) -ForegroundColor Blue
        }
    }
    Write-Host ([char]0x2560 + [string]::new([char]0x2550, $script:FrameWidth) + [char]0x2563) -ForegroundColor Blue
}

function Render-Instances {
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    # Header - show PROJECT instead of INSTANCE for global view
    $headerLine = ' {0,-12} {1,-10} {2,-10} {3,-5} {4,-10} {5,-14}' -f 'PROJECT', 'STORY', 'STATE', 'ITER', 'RUNTIME', 'BRANCH'
    Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
    Write-Host $headerLine -NoNewline -ForegroundColor White
    Write-Host ([char]0x2551) -ForegroundColor Blue

    $dividerLine = ' {0,-12} {1,-10} {2,-10} {3,-5} {4,-10} {5,-14}' -f '-------', '-----', '-----', '----', '-------', '------'
    Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
    Write-Host $dividerLine -NoNewline -ForegroundColor Gray
    Write-Host ([char]0x2551) -ForegroundColor Blue

    # Use global instances to show all projects
    $instances = Get-RalphGlobalInstances -IncludeDead

    if ($instances.Count -eq 0) {
        $emptyText = '  No instances running'
        $emptyLine = $emptyText + (' ' * [Math]::Max(0, $script:FrameWidth - $emptyText.Length))
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

            # Truncate project and branch
            $projectName = if ($instance.projectName) { $instance.projectName } else { 'local' }
            if ($projectName.Length -gt 12) { $projectName = $projectName.Substring(0, 9) + '...' }

            $branch = if ($instance.branch.Length -gt 14) { $instance.branch.Substring(0, 11) + '...' } else { $instance.branch }
            if (-not $branch) { $branch = '-' }

            $story = if ($instance.currentStory) { $instance.currentStory } else { '-' }
            $iter = "$($instance.iteration)/$($instance.maxIterations)"

            $line = ' {0,-12} {1,-10} ' -f $projectName, $story
            Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
            Write-Host $line -NoNewline
            Write-Host ('{0,-10} ' -f $state) -NoNewline -ForegroundColor $color
            Write-Host ('{0,-5} {1,-10} {2,-14}' -f $iter, $runtimeStr, $branch) -NoNewline
            Write-Host ([char]0x2551) -ForegroundColor Blue
        }
    }
}

function Render-Locks {
    Write-Host ([char]0x2560 + [string]::new([char]0x2550, $script:FrameWidth) + [char]0x2563) -ForegroundColor Blue

    # Get locks from all projects
    $locks = Get-AllProjectsLocks
    $lockHeaderText = '  ACTIVE LOCKS'
    $lockHeader = $lockHeaderText + (' ' * [Math]::Max(0, $script:FrameWidth - $lockHeaderText.Length))
    Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
    Write-Host $lockHeader -NoNewline -ForegroundColor White
    Write-Host ([char]0x2551) -ForegroundColor Blue

    if ($locks.Count -eq 0) {
        $noLocksText = '    No active locks'
        $noLocks = $noLocksText + (' ' * [Math]::Max(0, $script:FrameWidth - $noLocksText.Length))
        Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
        Write-Host $noLocks -NoNewline -ForegroundColor Gray
        Write-Host ([char]0x2551) -ForegroundColor Blue
    }
    else {
        foreach ($lock in $locks | Select-Object -First 5) {
            $ageStr = Format-Duration -Seconds $lock.Age
            $ownerShort = if ($lock.Owner.Length -gt 8) { $lock.Owner.Substring(0, 5) + '...' } else { $lock.Owner }
            $projShort = if ($lock.Project.Length -gt 8) { $lock.Project.Substring(0, 5) + '...' } else { $lock.Project }
            $color = if ($lock.IsStale) { 'Yellow' } else { 'Green' }
            $lockLine = '    {0,-8} {1,-8} by {2,-8} for {3,-8}' -f $projShort, $lock.StoryId, $ownerShort, $ageStr
            $padding = $script:FrameWidth - $lockLine.Length
            Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
            Write-Host $lockLine -NoNewline -ForegroundColor $color
            Write-Host (' ' * [Math]::Max(0, $padding)) -NoNewline
            Write-Host ([char]0x2551) -ForegroundColor Blue
        }
        if ($locks.Count -gt 5) {
            $more = "    ... and $($locks.Count - 5) more"
            $padding = $script:FrameWidth - $more.Length
            Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
            Write-Host $more -NoNewline -ForegroundColor Gray
            Write-Host (' ' * $padding) -NoNewline
            Write-Host ([char]0x2551) -ForegroundColor Blue
        }
    }
}

function Render-Footer {
    Write-Host ([char]0x2560 + [string]::new([char]0x2550, $script:FrameWidth) + [char]0x2563) -ForegroundColor Blue

    $helpText = '  Press: q=quit  r=refresh  l=locks  c=cleanup'
    $helpLine = $helpText + (' ' * [Math]::Max(0, $script:FrameWidth - $helpText.Length))
    Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
    Write-Host $helpLine -NoNewline -ForegroundColor Gray
    Write-Host ([char]0x2551) -ForegroundColor Blue

    $timeText = "  Last update: $(Get-Date -Format 'HH:mm:ss')"
    $timeLine = $timeText + (' ' * [Math]::Max(0, $script:FrameWidth - $timeText.Length))
    Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
    Write-Host $timeLine -NoNewline -ForegroundColor Gray
    Write-Host ([char]0x2551) -ForegroundColor Blue

    Write-Host ([char]0x255A + [string]::new([char]0x2550, $script:FrameWidth) + [char]0x255D) -ForegroundColor Blue
}

function Render-Dashboard {
    # Update frame width dynamically based on terminal size
    $script:FrameWidth = Get-FrameWidth
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
    & (Join-Path $PSScriptRoot 'ralph-cleanup.ps1') -Dead -Terminated
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
