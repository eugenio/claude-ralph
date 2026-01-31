#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Launch and manage multiple Ralph instances in parallel.

.DESCRIPTION
    ralph-parallel.ps1 provides commands to start, stop, and monitor multiple
    concurrent Ralph instances using PowerShell jobs.

.PARAMETER Command
    The command to execute: Start, Stop, Status, Dashboard

.PARAMETER Count
    For Start command: number of instances to launch. Default: CPU cores / 2.

.PARAMETER MaxIterations
    For Start command: max iterations per instance. Default: 10.

.EXAMPLE
    ./ralph-parallel.ps1 Start -Count 3
    Launches 3 Ralph instances.

.EXAMPLE
    ./ralph-parallel.ps1 Stop
    Stops all running instances.

.EXAMPLE
    ./ralph-parallel.ps1 Status
    Shows running instance status.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Start', 'Stop', 'Kill', 'Status', 'Check', 'Dashboard', 'Queue', 'Help')]
    [string]$Command = 'Status',

    [Parameter()]
    [Alias('c')]
    [int]$Count = 0,

    [Parameter()]
    [Alias('m')]
    [int]$MaxIterations = 10,

    [Parameter()]
    [Alias('p')]
    [string]$Prd,

    [Parameter()]
    [Alias('r')]
    [string]$ProjectRoot,

    [Parameter()]
    [switch]$QueueMode,

    [Parameter()]
    [Alias('q')]
    [switch]$Quiet,

    [Parameter(ValueFromRemainingArguments)]
    [string[]]$RemainingArgs
)

# Import module
$modulePath = Join-Path $PSScriptRoot 'RalphUtils.psm1'
if (-not (Test-Path $modulePath)) {
    Write-Host 'Error: RalphUtils.psm1 not found' -ForegroundColor Red
    exit 1
}
Import-Module $modulePath -Force

$script:JobsFile = Join-Path (Join-Path (Get-RalphPaths).RalphDir 'instances') 'running-jobs.json'

function Get-DefaultCount {
    $cpuCount = [Environment]::ProcessorCount
    $default = [math]::Max(1, [math]::Floor($cpuCount / 2))
    return $default
}

function Save-Jobs {
    param([array]$Jobs)

    $dir = Split-Path $script:JobsFile -Parent
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    $Jobs | ConvertTo-Json -Depth 5 | Set-Content $script:JobsFile -Force
}

function Get-SavedJobs {
    if (-not (Test-Path $script:JobsFile)) {
        return @()
    }

    try {
        $content = Get-Content $script:JobsFile -Raw
        if ([string]::IsNullOrWhiteSpace($content)) {
            return @()
        }
        return $content | ConvertFrom-Json
    }
    catch {
        return @()
    }
}

function Show-Help {
    Write-Host ''
    Write-Host 'Usage: ./ralph-parallel.ps1 <Command> [Options]' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Commands:' -ForegroundColor Yellow
    Write-Host '  Start [-Count N] [-MaxIterations M]  Launch N instances'
    Write-Host '  Stop                                  Stop all instances gracefully'
    Write-Host '  Kill                                  Force kill all instances'
    Write-Host '  Status                                Show running instances'
    Write-Host '  Dashboard                             Open monitoring dashboard'
    Write-Host '  Queue <subcommand>                    Queue management (add, list, status, start)'
    Write-Host '  Help                                  Show this help'
    Write-Host ''
    Write-Host 'Options:' -ForegroundColor Yellow
    Write-Host '  -Count N, -c N           Number of instances (default: CPU cores / 2)'
    Write-Host '  -MaxIterations M, -m M   Max iterations per instance (default: 10)'
    Write-Host '  -Prd PATH, -p PATH       Path to prd.json file'
    Write-Host '  -ProjectRoot PATH, -r PATH  Project root directory'
    Write-Host ''
    Write-Host 'Examples:' -ForegroundColor Yellow
    Write-Host '  ./ralph-parallel.ps1 Start -Count 3'
    Write-Host '  ./ralph-parallel.ps1 Start -Prd /path/to/prd.json -Count 2'
    Write-Host '  ./ralph-parallel.ps1 Start -p /project/prd.json -r /project'
    Write-Host '  ./ralph-parallel.ps1 Stop'
    Write-Host '  ./ralph-parallel.ps1 Status'
    Write-Host ''
    Write-Host 'Environment Variables:' -ForegroundColor Yellow
    Write-Host '  RALPH_MAX_INSTANCES  Maximum instances allowed (default: 16)'
    Write-Host '  RALPH_ITERATIONS     Default max iterations (default: 10)'
    Write-Host ''
}

function Start-RalphInstances {
    param(
        [int]$Count,
        [int]$MaxIterations,
        [string]$PrdPath,
        [string]$ProjectPath,
        [switch]$QueueMode
    )

    if ($Count -le 0) {
        $Count = Get-DefaultCount
    }

    # Validate PRD path if provided
    if ($PrdPath) {
        if (-not (Test-Path $PrdPath -PathType Leaf)) {
            Write-Host "Error: PRD file not found: $PrdPath" -ForegroundColor Red
            exit 1
        }
    }

    # Validate project path if provided
    if ($ProjectPath) {
        if (-not (Test-Path $ProjectPath -PathType Container)) {
            Write-Host "Error: Project directory not found: $ProjectPath" -ForegroundColor Red
            exit 1
        }
    }

    $maxInstances = [int]($env:RALPH_MAX_INSTANCES ?? 16)
    if ($Count -gt $maxInstances) {
        Write-Host "Warning: Limiting to $maxInstances instances (RALPH_MAX_INSTANCES)" -ForegroundColor Yellow
        $Count = $maxInstances
    }

    Write-Host ''
    Write-Host ([string]::new([char]0x2550, 55)) -ForegroundColor Blue
    Write-Host '         RALPH PARALLEL LAUNCHER' -ForegroundColor Cyan
    Write-Host ([string]::new([char]0x2550, 55)) -ForegroundColor Blue
    Write-Host ''
    Write-Host "Launching $Count instances with $MaxIterations iterations each..."
    if ($PrdPath) {
        Write-Host "PRD file: $PrdPath"
    }
    if ($ProjectPath) {
        Write-Host "Project root: $ProjectPath"
    }
    Write-Host ''

    $ralphScript = Join-Path $PSScriptRoot 'ralph.ps1'
    $jobs = @()

    for ($i = 1; $i -le $Count; $i++) {
        Write-Host "  Starting instance $i/$Count..." -ForegroundColor Cyan

        # Small delay between launches
        if ($i -gt 1) {
            Start-Sleep -Seconds 1
        }

        $job = Start-Job -ScriptBlock {
            param($script, $iterations, $prd, $project, $queueMode)
            $params = @{
                MaxIterations = $iterations
            }
            if ($prd) {
                $params['Prd'] = $prd
            }
            if ($project) {
                $params['ProjectRoot'] = $project
            }
            if ($queueMode) {
                $params['QueueMode'] = $true
            }
            & $script @params
        } -ArgumentList $ralphScript, $MaxIterations, $PrdPath, $ProjectPath, $QueueMode.IsPresent

        $jobs += @{
            Id          = $job.Id
            Name        = $job.Name
            StartTime   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            Iterations  = $MaxIterations
        }

        Write-Host "    Job ID: $($job.Id)" -ForegroundColor Green
    }

    Save-Jobs -Jobs $jobs

    Write-Host ''
    Write-Host "Launched $Count instances" -ForegroundColor Green
    Write-Host ''
    Write-Host 'Monitor with:' -ForegroundColor Yellow
    Write-Host '  ./ralph-parallel.ps1 Status'
    Write-Host '  ./ralph-parallel.ps1 Dashboard'
    Write-Host ''
    Write-Host 'Stop with:' -ForegroundColor Yellow
    Write-Host '  ./ralph-parallel.ps1 Stop'
    Write-Host ''
}

function Stop-RalphInstances {
    Write-Host 'Stopping all Ralph instances...' -ForegroundColor Yellow

    $savedJobs = Get-SavedJobs
    $stopped = 0

    foreach ($savedJob in $savedJobs) {
        $job = Get-Job -Id $savedJob.Id -ErrorAction SilentlyContinue
        if ($job -and $job.State -eq 'Running') {
            Write-Host "  Stopping job $($savedJob.Id)..." -ForegroundColor Gray
            Stop-Job -Id $savedJob.Id -ErrorAction SilentlyContinue
            $stopped++
        }
    }

    # Also stop any ralph.ps1 jobs we might have missed
    Get-Job | Where-Object { $_.Command -like '*ralph.ps1*' -and $_.State -eq 'Running' } | ForEach-Object {
        Write-Host "  Stopping job $($_.Id)..." -ForegroundColor Gray
        Stop-Job -Id $_.Id -ErrorAction SilentlyContinue
        $stopped++
    }

    if ($stopped -eq 0) {
        Write-Host 'No running instances found' -ForegroundColor Green
    }
    else {
        Write-Host "Stopped $stopped instances" -ForegroundColor Green
    }

    # Clean up completed jobs
    Get-Job | Where-Object { $_.State -ne 'Running' } | Remove-Job -Force -ErrorAction SilentlyContinue

    # Clear jobs file
    Save-Jobs -Jobs @()
}

function Stop-RalphInstancesForce {
    Write-Host 'Force killing all Ralph instances...' -ForegroundColor Red

    Get-Job | Where-Object { $_.Command -like '*ralph.ps1*' } | ForEach-Object {
        Write-Host "  Killing job $($_.Id)..." -ForegroundColor Gray
        Stop-Job -Id $_.Id -ErrorAction SilentlyContinue
        Remove-Job -Id $_.Id -Force -ErrorAction SilentlyContinue
    }

    # Also try to kill any claude processes
    Get-Process -Name 'claude' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    Write-Host 'All instances killed' -ForegroundColor Red

    Save-Jobs -Jobs @()
}

function Show-Status {
    Write-Host ''
    Write-Host ([string]::new([char]0x2550, 55)) -ForegroundColor Blue
    Write-Host '         RALPH PARALLEL STATUS' -ForegroundColor Cyan
    Write-Host ([string]::new([char]0x2550, 55)) -ForegroundColor Blue
    Write-Host ''

    $savedJobs = Get-SavedJobs
    $running = 0
    $total = $savedJobs.Count

    Write-Host ('{0,-10} {1,-12} {2,-12} {3,-15}' -f 'JOB ID', 'STATUS', 'INSTANCE', 'STATE') -ForegroundColor White
    Write-Host ('{0,-10} {1,-12} {2,-12} {3,-15}' -f '------', '------', '--------', '-----')

    foreach ($savedJob in $savedJobs) {
        # Skip entries with null/empty Id
        if ($null -eq $savedJob -or $null -eq $savedJob.Id -or $savedJob.Id -eq '') {
            continue
        }

        $job = Get-Job -Id $savedJob.Id -ErrorAction SilentlyContinue
        $status = if ($job) { $job.State } else { 'Gone' }
        $color = switch ($status) {
            'Running' { 'Green'; $running++ }
            'Completed' { 'Blue' }
            'Failed' { 'Red' }
            default { 'Gray' }
        }

        # Try to find instance info
        $instanceId = '-'
        $state = '-'

        Write-Host ('{0,-10} ' -f $savedJob.Id) -NoNewline
        Write-Host ('{0,-12} ' -f $status) -NoNewline -ForegroundColor $color
        Write-Host ('{0,-12} {1,-15}' -f $instanceId, $state)
    }

    Write-Host ''
    Write-Host "Running: $running/$total" -ForegroundColor $(if ($running -gt 0) { 'Green' } else { 'Gray' })

    # Show locks
    $locks = Get-RalphStoryLocks
    Write-Host "Active locks: $($locks.Count)"

    # Show PRD status
    $prd = Read-PrdJson
    if ($prd) {
        $status = Get-PrdStatus -Prd $prd
        Write-Host "PRD progress: $($status.Complete)/$($status.Total) stories"
    }

    Write-Host ''
}

function Start-Dashboard {
    $dashboardScript = Join-Path $PSScriptRoot 'ralph-dashboard.ps1'
    if (Test-Path $dashboardScript) {
        & $dashboardScript
    }
    else {
        Write-Host 'Dashboard script not found' -ForegroundColor Red
    }
}

function Invoke-Check {
    param(
        [string]$PrdPath,
        [switch]$QuietMode
    )

    # Default to local PRD file if not specified
    if (-not $PrdPath) {
        $paths = Get-RalphPaths
        $PrdPath = $paths.PrdFile
    }

    # Convert to absolute path if needed
    if (-not [System.IO.Path]::IsPathRooted($PrdPath)) {
        $PrdPath = Join-Path (Get-Location) $PrdPath
    }

    if (-not (Test-Path $PrdPath)) {
        if (-not $QuietMode) {
            Write-Host "PRD file not found: $PrdPath" -ForegroundColor Red
        }
        $script:checkExitCode = 1
        return
    }

    try {
        $prdData = Get-Content $PrdPath -Raw | ConvertFrom-Json
        $stories = @($prdData.userStories)
        $total = $stories.Count
        $complete = @($stories | Where-Object { $_.passes -eq $true }).Count
        $incomplete = $total - $complete
    }
    catch {
        if (-not $QuietMode) {
            Write-Host "Error: Failed to parse PRD file: $_" -ForegroundColor Red
        }
        $script:checkExitCode = 1
        return
    }

    if ($QuietMode) {
        # Quiet mode: output count to stdout
        Write-Output $incomplete
        if ($incomplete -eq 0 -and $total -gt 0) {
            $script:checkExitCode = 0  # Complete
        }
        else {
            $script:checkExitCode = 1  # Incomplete or empty
        }
        return
    }

    # Verbose output
    Write-Host ''
    Write-Host ([string]::new([char]0x2550, 55)) -ForegroundColor Blue
    Write-Host '         PRD STATUS CHECK' -ForegroundColor Cyan
    Write-Host ([string]::new([char]0x2550, 55)) -ForegroundColor Blue
    Write-Host ''

    if ($total -eq 0) {
        Write-Host '  PRD has no stories' -ForegroundColor Red
        Write-Host "  File: $PrdPath"
        Write-Host ''
        Write-Host 'Incomplete: 0'
        $script:checkExitCode = 1
        return
    }
    elseif ($incomplete -eq 0) {
        Write-Host '  STATUS: COMPLETE' -ForegroundColor Green
        Write-Host ''
        Write-Host "  Stories: $complete/$total (100%)"
        Write-Host "  File: $PrdPath"
        Write-Host ''
        Write-Host 'Incomplete: 0'
        $script:checkExitCode = 0
        return
    }
    else {
        $pct = [int]($complete * 100 / $total)
        Write-Host '  STATUS: INCOMPLETE' -ForegroundColor Yellow
        Write-Host ''
        Write-Host "  Stories: $complete/$total ($pct%)"
        Write-Host "  Remaining: $incomplete"
        Write-Host "  File: $PrdPath"
        Write-Host ''
        Write-Host '  Incomplete stories:'
        foreach ($story in ($stories | Where-Object { $_.passes -ne $true })) {
            Write-Host "    $($story.id): $($story.title)"
        }
        Write-Host ''
        Write-Host "Incomplete: $incomplete"
        $script:checkExitCode = 1
        return
    }
}

# Main
$script:checkExitCode = 0

switch ($Command) {
    'Start' {
        $startParams = @{
            Count = $Count
            MaxIterations = $MaxIterations
            PrdPath = $Prd
            ProjectPath = $ProjectRoot
        }
        if ($QueueMode) { $startParams['QueueMode'] = $true }
        Start-RalphInstances @startParams
    }
    'Stop' { Stop-RalphInstances }
    'Kill' { Stop-RalphInstancesForce }
    'Status' { Show-Status }
    'Check' { Invoke-Check -PrdPath $Prd -QuietMode:$Quiet; exit $script:checkExitCode }
    'Dashboard' { Start-Dashboard }
    'Queue' {
        # Delegate to ralph-queue.ps1
        $queueScript = Join-Path $PSScriptRoot 'ralph-queue.ps1'
        if (Test-Path $queueScript) {
            & $queueScript @RemainingArgs
        } else {
            Write-Host 'Error: ralph-queue.ps1 not found' -ForegroundColor Red
        }
    }
    'Help' { Show-Help }
    default { Show-Help }
}
