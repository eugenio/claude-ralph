#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Start and manage queue workers for Ralph.

.DESCRIPTION
    ralph-queue-workers.ps1 provides commands to start, stop, and monitor
    queue workers that process PRDs from the global queue.

.PARAMETER Command
    The command to execute: start, stop, kill, status, help

.PARAMETER Count
    Number of workers to start. Default: CPU cores / 2.

.PARAMETER MaxIterations
    Maximum iterations per worker. Default: 10.

.EXAMPLE
    ./ralph-queue-workers.ps1 start -c 3 -m 10
    Start 3 workers with max 10 iterations each.

.EXAMPLE
    ./ralph-queue-workers.ps1 stop
    Stop all running workers gracefully.

.EXAMPLE
    ./ralph-queue-workers.ps1 status
    Show status of all workers.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'kill', 'status', 'help')]
    [string]$Command = 'status',

    [Parameter()]
    [Alias('c')]
    [int]$Count = 0,

    [Parameter()]
    [Alias('m')]
    [int]$MaxIterations = 10
)

# Import modules
$modulePath = Join-Path $PSScriptRoot 'RalphUtils.psm1'
if (-not (Test-Path $modulePath)) {
    Write-Host 'Error: RalphUtils.psm1 not found' -ForegroundColor Red
    exit 1
}
Import-Module $modulePath -Force

$queueModulePath = Join-Path $PSScriptRoot 'RalphQueue.psm1'
if (Test-Path $queueModulePath) {
    Import-Module $queueModulePath -Force
}

# Configuration
$script:DefaultIterations = [int]($env:RALPH_ITERATIONS ?? 10)
$script:GlobalDir = $env:RALPH_GLOBAL_DIR ?? (Join-Path $HOME '.ralph' 'global')
$script:WorkersFile = Join-Path $script:GlobalDir 'queue-workers.json'

function Get-DefaultWorkerCount {
    $cpuCount = [Environment]::ProcessorCount
    $default = [math]::Max(1, [math]::Floor($cpuCount / 2))
    return $default
}

function Test-WorkerRunning {
    param([int]$Pid)
    try {
        $process = Get-Process -Id $Pid -ErrorAction SilentlyContinue
        return $null -ne $process -and -not $process.HasExited
    }
    catch {
        return $false
    }
}

function Save-QueueWorkers {
    param([array]$Workers)

    $dir = Split-Path $script:WorkersFile -Parent
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    $Workers | ConvertTo-Json -Depth 5 | Set-Content $script:WorkersFile -Force
}

function Get-QueueWorkers {
    if (-not (Test-Path $script:WorkersFile)) {
        return @()
    }

    try {
        $content = Get-Content $script:WorkersFile -Raw
        if ([string]::IsNullOrWhiteSpace($content)) {
            return @()
        }
        $result = $content | ConvertFrom-Json
        if ($null -eq $result) {
            return @()
        }
        return @($result)
    }
    catch {
        return @()
    }
}

function Show-Help {
    @"

RALPH QUEUE WORKERS
===================

Usage: ralph-queue-workers.ps1 <command> [options]

Commands:
  start    Start queue workers
  stop     Stop all queue workers gracefully
  kill     Force kill all workers
  status   Show worker status
  help     Show this help

Options:
  -Count N, -c N            Number of workers (default: CPU cores / 2)
  -MaxIterations N, -m N    Max iterations per worker (default: 10)

Examples:
  ./ralph-queue-workers.ps1 start -c 3 -m 10
  ./ralph-queue-workers.ps1 stop
  ./ralph-queue-workers.ps1 status

"@ | Write-Host
}

function Invoke-Start {
    if ($Count -le 0) {
        $Count = Get-DefaultWorkerCount
    }
    if ($MaxIterations -le 0) {
        $MaxIterations = $script:DefaultIterations
    }

    # Check for pending queue entries
    $pending = @(Get-RalphQueueEntries -Status 'pending')

    if ($pending.Count -eq 0) {
        Write-Host ''
        Write-Host 'No pending entries in queue.' -ForegroundColor Yellow
        Write-Host 'Add PRDs first: ralph-queue.ps1 add -p /path/prd.json -r /path/project'
        Write-Host ''
        return
    }

    Write-Host ''
    Write-Host ([string]::new([char]0x2550, 78)) -ForegroundColor Blue
    Write-Host '  STARTING QUEUE WORKERS' -ForegroundColor Cyan
    Write-Host ([string]::new([char]0x2550, 78)) -ForegroundColor Blue
    Write-Host ''
    Write-Host "  Workers: $Count"
    Write-Host "  Max iterations: $MaxIterations per worker"
    Write-Host "  Pending PRDs: $($pending.Count)"
    Write-Host ''

    $ralphScript = Join-Path $PSScriptRoot 'ralph.ps1'
    if (-not (Test-Path $ralphScript)) {
        Write-Host 'Error: ralph.ps1 not found' -ForegroundColor Red
        return
    }

    $workers = @()
    $started = 0
    $logsDir = Join-Path $script:GlobalDir 'logs'
    if (-not (Test-Path $logsDir)) {
        New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
    }

    for ($i = 1; $i -le $Count; $i++) {
        $instanceId = "queue-worker-$PID-$i"

        # Claim a queue entry
        try {
            $entry = Request-RalphQueueEntryClaim -InstanceId $instanceId
            if ($null -eq $entry) {
                Write-Host "  Worker $i`: No more pending entries" -ForegroundColor Yellow
                break
            }
        }
        catch {
            Write-Host "  Worker $i`: Failed to claim entry - $_" -ForegroundColor Yellow
            continue
        }

        $entryId = $entry.id
        $prdPath = $entry.prdPath
        $projectRoot = $entry.projectRoot

        if ([string]::IsNullOrEmpty($prdPath)) {
            Write-Host "  Worker $i`: Invalid queue entry" -ForegroundColor Yellow
            continue
        }

        Write-Host "  Starting worker $i..." -ForegroundColor Cyan
        Write-Host "    PRD: $prdPath"
        Write-Host "    Project: $projectRoot"

        # Small delay between launches
        if ($started -gt 0) {
            Start-Sleep -Seconds 1
        }

        $logFile = Join-Path $logsDir "queue-worker-$i-$PID.log"

        # Start ralph.ps1 as a background job
        $job = Start-Job -ScriptBlock {
            param($script, $iterations, $prd, $project, $entryId)
            & $script -MaxIterations $iterations -PrdFile $prd -ProjectRoot $project -QueueMode -QueueEntryId $entryId
        } -ArgumentList $ralphScript, $MaxIterations, $prdPath, $projectRoot, $entryId

        $workers += @{
            pid = $job.Id
            index = $i
            logFile = $logFile
            entryId = $entryId
            prdPath = $prdPath
            projectRoot = $projectRoot
            startedAt = (Get-Date).ToString('o')
        }

        Write-Host "    Job ID: $($job.Id)" -ForegroundColor Green
        $started++
    }

    Save-QueueWorkers -Workers $workers

    Write-Host ''
    if ($started -gt 0) {
        Write-Host "Started $started queue workers" -ForegroundColor Green
        Write-Host ''
        Write-Host 'Monitor: ./ralph-queue-workers.ps1 status'
        Write-Host 'Stop: ./ralph-queue-workers.ps1 stop'
    }
    else {
        Write-Host 'No workers started' -ForegroundColor Yellow
    }
    Write-Host ''
}

function Invoke-Stop {
    Write-Host 'Stopping all queue workers...' -ForegroundColor Yellow

    $workers = Get-QueueWorkers
    $stopped = 0

    foreach ($worker in $workers) {
        if ($null -eq $worker -or $null -eq $worker.pid) {
            continue
        }

        $job = Get-Job -Id $worker.pid -ErrorAction SilentlyContinue
        if ($job -and $job.State -eq 'Running') {
            Write-Host "  Stopping Job $($worker.pid)..." -ForegroundColor Gray
            Stop-Job -Id $worker.pid -ErrorAction SilentlyContinue
            $stopped++
        }
    }

    # Also stop any ralph.ps1 jobs
    Get-Job | Where-Object { $_.Command -like '*ralph.ps1*' -and $_.State -eq 'Running' } | ForEach-Object {
        Write-Host "  Stopping Job $($_.Id)..." -ForegroundColor Gray
        Stop-Job -Id $_.Id -ErrorAction SilentlyContinue
        $stopped++
    }

    if ($stopped -eq 0) {
        Write-Host 'No running workers found' -ForegroundColor Green
    }
    else {
        Write-Host "Stopped $stopped workers" -ForegroundColor Green
    }

    # Clean up completed jobs
    Get-Job | Where-Object { $_.State -ne 'Running' } | Remove-Job -Force -ErrorAction SilentlyContinue

    Save-QueueWorkers -Workers @()
}

function Invoke-Kill {
    Write-Host 'Force killing all queue workers...' -ForegroundColor Red

    $workers = Get-QueueWorkers
    $killed = 0

    foreach ($worker in $workers) {
        if ($null -eq $worker -or $null -eq $worker.pid) {
            continue
        }

        $job = Get-Job -Id $worker.pid -ErrorAction SilentlyContinue
        if ($job) {
            Write-Host "  Killing Job $($worker.pid)..." -ForegroundColor Gray
            Stop-Job -Id $worker.pid -ErrorAction SilentlyContinue
            Remove-Job -Id $worker.pid -Force -ErrorAction SilentlyContinue
            $killed++
        }
    }

    # Also kill any ralph.ps1 jobs
    Get-Job | Where-Object { $_.Command -like '*ralph.ps1*' } | ForEach-Object {
        Write-Host "  Killing Job $($_.Id)..." -ForegroundColor Gray
        Stop-Job -Id $_.Id -ErrorAction SilentlyContinue
        Remove-Job -Id $_.Id -Force -ErrorAction SilentlyContinue
        $killed++
    }

    Write-Host "Killed $killed workers" -ForegroundColor Red
    Save-QueueWorkers -Workers @()
}

function Invoke-Status {
    Write-Host ''
    Write-Host ([string]::new([char]0x2550, 78)) -ForegroundColor Blue
    Write-Host '  QUEUE WORKERS STATUS' -ForegroundColor Cyan
    Write-Host ([string]::new([char]0x2550, 78)) -ForegroundColor Blue
    Write-Host ''

    $workers = Get-QueueWorkers
    $workerCount = $workers.Count
    $running = 0

    if ($workerCount -eq 0) {
        Write-Host '  No workers registered.'
        Write-Host ''
        return
    }

    Write-Host ('{0,-8} {1,-12} {2,-40}' -f 'JOB ID', 'STATUS', 'PRD') -ForegroundColor White
    Write-Host ('{0,-8} {1,-12} {2,-40}' -f '------', '----------', '----------------------------------------')

    foreach ($worker in $workers) {
        if ($null -eq $worker -or $null -eq $worker.pid) {
            continue
        }

        $job = Get-Job -Id $worker.pid -ErrorAction SilentlyContinue
        $status = if ($job) {
            if ($job.State -eq 'Running') {
                $running++
                'running'
            }
            else {
                $job.State.ToString().ToLower()
            }
        }
        else {
            'gone'
        }

        $color = switch ($status) {
            'running' { 'Green' }
            'completed' { 'Blue' }
            'failed' { 'Red' }
            default { 'Gray' }
        }

        $prdName = if ($worker.prdPath) { Split-Path $worker.prdPath -Leaf } else { '-' }

        Write-Host -NoNewline ('{0,-8} ' -f $worker.pid)
        Write-Host -NoNewline ('{0,-12} ' -f $status) -ForegroundColor $color
        Write-Host ('{0,-40}' -f $prdName)
    }

    Write-Host ''
    Write-Host "  Total: $workerCount workers, $running running"
    Write-Host ''
}

# Main
switch ($Command) {
    'start' { Invoke-Start }
    'stop' { Invoke-Stop }
    'kill' { Invoke-Kill }
    'status' { Invoke-Status }
    'help' { Show-Help }
    default { Invoke-Status }
}
