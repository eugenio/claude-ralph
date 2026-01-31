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

.PARAMETER AutoClean
    Automatically clean dead instances on startup and periodically.

.PARAMETER AutoCleanInterval
    Seconds between automatic cleanups when -AutoClean is enabled. Default: 30.

.EXAMPLE
    ./ralph-dashboard.ps1
    Launch dashboard with default settings.

.EXAMPLE
    ./ralph-dashboard.ps1 -RefreshInterval 5
    Refresh every 5 seconds.

.EXAMPLE
    ./ralph-dashboard.ps1 -AutoClean
    Launch with automatic cleanup of dead instances every 30 seconds.

.EXAMPLE
    ./ralph-dashboard.ps1 -AutoClean -AutoCleanInterval 60
    Launch with automatic cleanup every 60 seconds.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [int]$RefreshInterval = 2,

    [Parameter()]
    [switch]$AutoClean,

    [Parameter()]
    [int]$AutoCleanInterval = 30
)

# Import module
$modulePath = Join-Path $PSScriptRoot 'RalphUtils.psm1'
if (-not (Test-Path $modulePath)) {
    Write-Host 'Error: RalphUtils.psm1 not found' -ForegroundColor Red
    exit 1
}
Import-Module $modulePath -Force

# Auto-clean configuration (set from params)
$script:AutoCleanEnabled = $AutoClean.IsPresent
$script:AutoCleanIntervalSec = $AutoCleanInterval

# Dynamic frame dimensions
$script:MinFrameWidth = 60
$script:MinFrameHeight = 20
$script:FrameWidth = 73

# Reserved lines for fixed UI elements
# Header: top border(1) + title(1) + separator(1) + separator after projects(1) = 4
# Instances: header row(1) + divider(1) = 2
# Locks: separator(1) + header(1) = 2
# Footer: separator(1) + help(1) + time(1) + bottom border(1) = 4
# Total fixed overhead = 12 lines
$script:ReservedLines = 12

# Section limits (calculated dynamically)
$script:MaxProjects = 4
$script:MaxInstances = 10
$script:MaxLocks = 5

function Get-FrameWidth {
    $termWidth = [Console]::WindowWidth
    if ($termWidth -lt 1) { $termWidth = 80 }
    $width = $termWidth - 2
    if ($width -lt $script:MinFrameWidth) { $width = $script:MinFrameWidth }
    return $width
}

function Get-FrameHeight {
    $termHeight = [Console]::WindowHeight
    if ($termHeight -lt 1) { $termHeight = 24 }
    if ($termHeight -lt $script:MinFrameHeight) { $termHeight = $script:MinFrameHeight }
    return $termHeight
}

function Update-SectionLimits {
    $termHeight = Get-FrameHeight
    $available = $termHeight - $script:ReservedLines

    # Minimum 3 rows total (1 per section)
    if ($available -lt 3) { $available = 3 }

    # Get actual content counts
    $projectsStatus = Get-AllProjectsPrdStatus
    $projectCount = @($projectsStatus).Count
    if ($projectCount -lt 1) { $projectCount = 1 }

    $instances = Get-RalphGlobalInstances -IncludeDead
    $instanceCount = @($instances).Count
    if ($instanceCount -lt 1) { $instanceCount = 1 }

    $locks = Get-AllProjectsLocks
    $lockCount = @($locks).Count
    if ($lockCount -lt 1) { $lockCount = 1 }

    $totalNeeded = $projectCount + $instanceCount + $lockCount

    if ($totalNeeded -le $available) {
        # All content fits - show everything
        $script:MaxProjects = $projectCount
        $script:MaxInstances = $instanceCount
        $script:MaxLocks = $lockCount
    } else {
        # Account for overflow lines ("... and N more") - up to 3 extra lines
        # Each section that overflows adds 1 line for the overflow message
        $overflowLines = 0

        # First pass: estimate limits to check for overflow
        $estProjects = [Math]::Max(1, [int]($available * $projectCount / $totalNeeded))
        $estInstances = [Math]::Max(1, [int]($available * $instanceCount / $totalNeeded))
        $estLocks = [Math]::Max(1, $available - $estProjects - $estInstances)

        if ($projectCount -gt $estProjects) { $overflowLines++ }
        if ($instanceCount -gt $estInstances) { $overflowLines++ }
        if ($lockCount -gt $estLocks) { $overflowLines++ }

        # Reduce available space by overflow lines
        $available = [Math]::Max(3, $available - $overflowLines)

        # Distribute proportionally based on content
        $script:MaxProjects = [Math]::Max(1, [int]($available * $projectCount / $totalNeeded))
        $script:MaxInstances = [Math]::Max(1, [int]($available * $instanceCount / $totalNeeded))
        $script:MaxLocks = [Math]::Max(1, $available - $script:MaxProjects - $script:MaxInstances)
    }
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
        # Show each project's progress (limited by MaxProjects)
        $shown = 0
        foreach ($proj in $projectsStatus | Select-Object -First $script:MaxProjects) {
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
        if ($projectsStatus.Count -gt $script:MaxProjects) {
            $moreCount = $projectsStatus.Count - $script:MaxProjects
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

    # Calculate dynamic column widths based on frame width
    # Fixed columns: STATE(12), ITER(7), RUNTIME(12) = 31 + 5 spaces = 36
    $fixedWidth = 36
    $available = $script:FrameWidth - $fixedWidth
    # Distribute to: PROJECT, STORY, BRANCH (ratio 2:2:5 - prioritize BRANCH)
    $colProject = [Math]::Max(8, [int]($available * 2 / 9))
    $colStory = [Math]::Max(6, [int]($available * 2 / 9))
    $colBranch = [Math]::Max(15, $available - $colProject - $colStory)

    # Header row
    $headerLine = " {0,-$colProject} {1,-$colStory} {2,-12} {3,-7} {4,-12} {5,-$colBranch}" -f 'PROJECT', 'STORY', 'STATE', 'ITER', 'RUNTIME', 'BRANCH'
    $headerPad = [Math]::Max(0, $script:FrameWidth - $headerLine.Length)
    Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
    Write-Host $headerLine -NoNewline -ForegroundColor White
    Write-Host (' ' * $headerPad) -NoNewline
    Write-Host ([char]0x2551) -ForegroundColor Blue

    # Divider row
    $divProject = '-' * $colProject
    $divStory = '-' * $colStory
    $divBranch = '-' * $colBranch
    $dividerLine = " {0,-$colProject} {1,-$colStory} {2,-12} {3,-7} {4,-12} {5,-$colBranch}" -f $divProject, $divStory, '------------', '-------', '------------', $divBranch
    $divPad = [Math]::Max(0, $script:FrameWidth - $dividerLine.Length)
    Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
    Write-Host $dividerLine -NoNewline -ForegroundColor Gray
    Write-Host (' ' * $divPad) -NoNewline
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
        # Limit instances to MaxInstances
        $shownInstances = $instances | Select-Object -First $script:MaxInstances
        foreach ($instance in $shownInstances) {
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

            # Truncate to column widths
            $projectName = if ($instance.projectName) { $instance.projectName } else { 'local' }
            if ($projectName.Length -gt $colProject) { $projectName = $projectName.Substring(0, $colProject - 3) + '...' }

            $branch = if ($instance.branch) { $instance.branch } else { '-' }
            if ($branch.Length -gt $colBranch) { $branch = $branch.Substring(0, $colBranch - 3) + '...' }

            $story = if ($instance.currentStory) { $instance.currentStory } else { '-' }
            if ($story.Length -gt $colStory) { $story = $story.Substring(0, $colStory - 3) + '...' }

            $iter = "$($instance.iteration)/$($instance.maxIterations)"

            $linePart1 = " {0,-$colProject} {1,-$colStory} " -f $projectName, $story
            $statePart = "{0,-12} " -f $state
            $linePart2 = "{0,-7} {1,-12} {2,-$colBranch}" -f $iter, $runtimeStr, $branch
            $fullLine = $linePart1 + $statePart + $linePart2
            $linePad = [Math]::Max(0, $script:FrameWidth - $fullLine.Length)

            Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
            Write-Host $linePart1 -NoNewline
            Write-Host $statePart -NoNewline -ForegroundColor $color
            Write-Host $linePart2 -NoNewline
            Write-Host (' ' * $linePad) -NoNewline
            Write-Host ([char]0x2551) -ForegroundColor Blue
        }

        # Show "... and N more" if there are more instances
        if ($instances.Count -gt $script:MaxInstances) {
            $moreCount = $instances.Count - $script:MaxInstances
            $moreText = "  ... and $moreCount more instances"
            $morePad = [Math]::Max(0, $script:FrameWidth - $moreText.Length)
            Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
            Write-Host $moreText -NoNewline -ForegroundColor Gray
            Write-Host (' ' * $morePad) -NoNewline
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
        # Calculate dynamic column widths for locks
        # Fixed: "    " prefix (4) + " by " (4) + " for " (5) = 13
        $lockFixed = 15
        $lockAvailable = $script:FrameWidth - $lockFixed
        # Distribute to: PROJECT, STORY, OWNER, DURATION (ratio 2:2:3:2)
        $lkProject = [Math]::Max(8, [int]($lockAvailable * 2 / 9))
        $lkStory = [Math]::Max(8, [int]($lockAvailable * 2 / 9))
        $lkOwner = [Math]::Max(10, [int]($lockAvailable * 3 / 9))
        $lkDuration = [Math]::Max(10, $lockAvailable - $lkProject - $lkStory - $lkOwner)

        foreach ($lock in $locks | Select-Object -First $script:MaxLocks) {
            $ageStr = Format-Duration -Seconds $lock.Age
            $ownerStr = if ($lock.Owner.Length -gt $lkOwner) { $lock.Owner.Substring(0, $lkOwner - 3) + '...' } else { $lock.Owner }
            $projStr = if ($lock.Project.Length -gt $lkProject) { $lock.Project.Substring(0, $lkProject - 3) + '...' } else { $lock.Project }
            $storyStr = if ($lock.StoryId.Length -gt $lkStory) { $lock.StoryId.Substring(0, $lkStory - 3) + '...' } else { $lock.StoryId }
            $color = if ($lock.IsStale) { 'Yellow' } else { 'Green' }
            $lockLine = "    {0,-$lkProject} {1,-$lkStory} by {2,-$lkOwner} for {3,-$lkDuration}" -f $projStr, $storyStr, $ownerStr, $ageStr
            $padding = $script:FrameWidth - $lockLine.Length
            Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
            Write-Host $lockLine -NoNewline -ForegroundColor $color
            Write-Host (' ' * [Math]::Max(0, $padding)) -NoNewline
            Write-Host ([char]0x2551) -ForegroundColor Blue
        }
        if ($locks.Count -gt $script:MaxLocks) {
            $more = "    ... and $($locks.Count - $script:MaxLocks) more"
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

    $autoCleanStatus = if ($script:AutoCleanEnabled) { " [AutoClean: ${script:AutoCleanIntervalSec}s]" } else { '' }
    $timeText = "  Last update: $(Get-Date -Format 'HH:mm:ss')$autoCleanStatus"
    $timeLine = $timeText + (' ' * [Math]::Max(0, $script:FrameWidth - $timeText.Length))
    Write-Host ([char]0x2551) -NoNewline -ForegroundColor Blue
    Write-Host $timeLine -NoNewline -ForegroundColor Gray
    Write-Host ([char]0x2551) -ForegroundColor Blue

    Write-Host ([char]0x255A + [string]::new([char]0x2550, $script:FrameWidth) + [char]0x255D) -ForegroundColor Blue
}

function Render-Dashboard {
    # Update frame dimensions dynamically based on terminal size
    $script:FrameWidth = Get-FrameWidth
    Update-SectionLimits
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

function Clear-StaleLocksAllProjects {
    $locks = Get-AllProjectsLocks
    $instances = Get-RalphGlobalInstances -IncludeDead
    $projectRoots = @($instances | ForEach-Object { $_.projectRoot } | Where-Object { $_ } | Sort-Object -Unique)

    # Add local root
    $localRoot = (Get-RalphPaths).ProjectRoot
    if ($localRoot -and $localRoot -notin $projectRoots) {
        $projectRoots += $localRoot
    }

    $cleaned = 0
    foreach ($lock in $locks) {
        if ($lock.IsDead -or $lock.IsStale) {
            $reason = if ($lock.IsDead) { 'dead owner' } else { 'stale' }
            $projectName = $lock.Project
            $storyId = $lock.StoryId

            # Find the lock directory in the matching project
            foreach ($pr in $projectRoots) {
                if (-not $pr -or -not (Test-Path $pr)) { continue }
                $pname = Split-Path -Path $pr -Leaf
                if ($pname -ne $projectName) { continue }

                $lockDir = $null
                # Check all possible lock directory locations
                $lockBases = @(
                    (Join-Path $pr 'scripts' 'ralph' 'locks'),
                    (Join-Path $pr '.claude' 'ralph' 'locks'),
                    (Join-Path $pr 'ralph' 'locks'),
                    (Join-Path $pr 'tasks' 'locks'),
                    (Join-Path $pr 'project' 'locks'),
                    (Join-Path $pr 'locks')
                )
                foreach ($lockBase in $lockBases) {
                    $testLock = Join-Path $lockBase "$storyId.lock"
                    if (Test-Path $testLock) {
                        $lockDir = $testLock
                        break
                    }
                }

                if ($lockDir -and (Test-Path $lockDir)) {
                    Write-Host "  Removing lock: $projectName/$storyId ($reason)" -ForegroundColor Yellow
                    Remove-Item -Path $lockDir -Recurse -Force -ErrorAction SilentlyContinue
                    $cleaned++
                }
                break
            }
        }
    }
    return $cleaned
}

function Invoke-Cleanup {
    Clear-Host
    & (Join-Path $PSScriptRoot 'ralph-cleanup.ps1') -Dead -Terminated

    # Clean up stale locks from all projects
    Write-Host 'Cleaning up stale locks...' -ForegroundColor Blue
    $locksCleaned = Clear-StaleLocksAllProjects
    if ($locksCleaned -gt 0) {
        Write-Host "Cleaned $locksCleaned stale locks" -ForegroundColor Green
    } else {
        Write-Host 'No stale locks found' -ForegroundColor Green
    }

    # Also clean up global registry entries for completed projects
    $registryCleaned = Clear-RalphGlobalRegistry -IncludeCompleted
    if ($registryCleaned -gt 0) {
        Write-Host "Cleaned $registryCleaned completed project entries from global registry" -ForegroundColor Green
    }
    Write-Host ''
    Write-Host 'Press any key to return to dashboard...' -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

function Invoke-AutoCleanup {
    # Silently clean dead and terminated instances
    $instances = Get-RalphGlobalInstances -IncludeDead
    $dead = @($instances | Where-Object { $_.isDead })

    if ($dead.Count -eq 0) { return 0 }

    $globalDir = Get-RalphGlobalDir
    $cleaned = 0

    foreach ($instance in $dead) {
        # Find instance directory via global registry link by matching instanceId suffix
        $instancesDir = Join-Path $globalDir 'instances'
        $instanceDir = $null

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
            try {
                $status = Get-Content $statusFile -Raw | ConvertFrom-Json
                $status.state = 'terminated'
                $status | ConvertTo-Json -Depth 5 | Set-Content $statusFile -Force
            } catch { }
        }

        # Release any locks held by this instance in project-local locks directories
        $projectRoot = $instance.projectRoot
        if ($projectRoot -and (Test-Path $projectRoot)) {
            # Check all possible lock directory locations
            $locksDirs = @(
                (Join-Path $projectRoot 'scripts' 'ralph' 'locks'),
                (Join-Path $projectRoot '.claude' 'ralph' 'locks'),
                (Join-Path $projectRoot 'ralph' 'locks'),
                (Join-Path $projectRoot 'tasks' 'locks'),
                (Join-Path $projectRoot 'project' 'locks'),
                (Join-Path $projectRoot 'locks')
            )
            foreach ($projectLocksDir in $locksDirs) {
                if (-not (Test-Path $projectLocksDir)) { continue }
                Get-ChildItem -Path $projectLocksDir -Directory -Filter '*.lock' -ErrorAction SilentlyContinue | ForEach-Object {
                    $lockOwner = $null
                    $ownerFile = Join-Path $_.FullName 'owner.txt'
                    $ownerFileLegacy = Join-Path $_.FullName 'owner'
                    if (Test-Path $ownerFile) { $lockOwner = (Get-Content $ownerFile -Raw).Trim() }
                    elseif (Test-Path $ownerFileLegacy) { $lockOwner = (Get-Content $ownerFileLegacy -Raw).Trim() }
                    if ($lockOwner -eq $instance.instanceId) {
                        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }

        $cleaned++
    }

    # Also clean up global registry entries for completed projects
    $cleaned += Clear-RalphGlobalRegistry -IncludeCompleted

    return $cleaned
}

# Main loop
try {
    [Console]::CursorVisible = $false

    # Initial auto-cleanup if enabled
    if ($AutoClean) {
        $null = Invoke-AutoCleanup
    }

    $lastAutoClean = [DateTime]::Now

    while ($true) {
        # Periodic auto-cleanup if enabled
        if ($AutoClean -and ([DateTime]::Now - $lastAutoClean).TotalSeconds -ge $AutoCleanInterval) {
            $null = Invoke-AutoCleanup
            $lastAutoClean = [DateTime]::Now
        }

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
