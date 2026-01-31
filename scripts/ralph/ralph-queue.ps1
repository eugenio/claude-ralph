#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    CLI for managing the global PRD queue.

.DESCRIPTION
    Command-line interface for managing the global PRD queue that enables
    cross-project automation. Workers can pick up queued PRDs when their
    current work completes.

.PARAMETER Command
    The command to execute: add, list, remove, clear, status, start, help

.EXAMPLE
    ./ralph-queue.ps1 add -Prd /path/to/prd.json -Project /path/to/project
    ./ralph-queue.ps1 list
    ./ralph-queue.ps1 start -Count 3 -MaxIterations 10
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('add', 'list', 'remove', 'clear', 'status', 'check', 'start', 'help')]
    [string]$Command = 'status',

    # Add command options
    [Parameter()]
    [Alias('p')]
    [string]$Prd,

    [Parameter()]
    [Alias('r')]
    [string]$Project,

    [Parameter()]
    [int]$Priority = 10,

    # Remove command options
    [Parameter()]
    [Alias('i')]
    [string]$Id,

    # List command options
    [Parameter()]
    [Alias('s')]
    [ValidateSet('pending', 'active', 'completed', 'failed', 'all')]
    [string]$Status = 'all',

    # Start command options
    [Parameter()]
    [Alias('c')]
    [int]$Count = 0,

    [Parameter()]
    [Alias('m')]
    [int]$MaxIterations = 10,

    # Check command options
    [Parameter()]
    [Alias('q')]
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# Import modules
$scriptDir = $PSScriptRoot
Import-Module (Join-Path $scriptDir 'RalphUtils.psm1') -Force
Import-Module (Join-Path $scriptDir 'RalphQueue.psm1') -Force

function Show-Banner {
    param([string]$Title)
    Write-Host ''
    Write-Host ([string]::new([char]0x2550, 78)) -ForegroundColor Blue
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ([string]::new([char]0x2550, 78)) -ForegroundColor Blue
    Write-Host ''
}

function Show-Help {
    @"

RALPH QUEUE MANAGEMENT
======================

Usage: ralph-queue.ps1 <command> [options]

Commands:
  add      Add a PRD to the queue
  list     Show queue entries
  remove   Remove an entry from the queue
  clear    Clear completed entries
  status   Show queue summary
  check    Check if a PRD is complete before adding
  start    Start workers to process queue
  help     Show this help message

Add Command:
  -Prd, -p PATH        Path to prd.json file (required)
  -Project, -r PATH    Project root directory (required)
  -Priority N          Priority (1-99, lower = higher priority, default: 10)

List Command:
  -Status, -s STATUS   Filter by status: pending, active, completed, failed, all
                       (default: all)

Remove Command:
  -Id, -i ID           Entry ID to remove (required)

Check Command:
  -Prd, -p PATH        Path to prd.json file (required)
  -Quiet, -q           Quiet mode (output count only, exit 0=complete, 1=incomplete)

Start Command:
  -Count, -c N         Number of workers to start (default: CPU cores / 2)
  -MaxIterations, -m N Max iterations per worker (default: 10)

Examples:
  # Add a PRD to the queue
  ./ralph-queue.ps1 add -p /home/user/project/prd.json -r /home/user/project

  # Add with high priority
  ./ralph-queue.ps1 add -p /path/prd.json -r /path/project -Priority 1

  # List all queue entries
  ./ralph-queue.ps1 list

  # List only pending entries
  ./ralph-queue.ps1 list -s pending

  # Remove an entry
  ./ralph-queue.ps1 remove -i q-1234567890-abcd1234

  # Clear completed entries
  ./ralph-queue.ps1 clear

  # Show queue summary
  ./ralph-queue.ps1 status

  # Start 3 workers to process queue
  ./ralph-queue.ps1 start -c 3 -m 10

"@ | Write-Host
}

function Invoke-Add {
    if (-not $Prd) {
        Write-Host 'Error: PRD path required. Use -Prd or -p' -ForegroundColor Red
        return
    }
    if (-not $Project) {
        Write-Host 'Error: Project root required. Use -Project or -r' -ForegroundColor Red
        return
    }

    # Convert to absolute paths
    if (-not [System.IO.Path]::IsPathRooted($Prd)) {
        $Prd = Join-Path (Get-Location) $Prd
    }
    if (-not [System.IO.Path]::IsPathRooted($Project)) {
        $Project = Join-Path (Get-Location) $Project
    }

    # Resolve paths
    if (Test-Path $Prd) {
        $Prd = Resolve-Path $Prd | Select-Object -ExpandProperty Path
    }
    if (Test-Path $Project) {
        $Project = Resolve-Path $Project | Select-Object -ExpandProperty Path
    }

    try {
        $entryId = Add-RalphQueueEntry -PrdPath $Prd -ProjectRoot $Project -Priority $Priority
        Write-Host ''
        Write-Host ([char]0x2714 + ' Added to queue successfully') -ForegroundColor Green
        Write-Host ''
        Write-Host "  Entry ID:    $entryId"
        Write-Host "  PRD:         $Prd"
        Write-Host "  Project:     $Project"
        Write-Host "  Priority:    $Priority"
        Write-Host ''
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

function Invoke-List {
    Show-Banner "RALPH QUEUE - $($Status.ToUpper()) ENTRIES"

    $entries = Get-RalphQueueEntries -Status $Status

    if ($entries.Count -eq 0) {
        Write-Host '  No entries found.'
        Write-Host ''
        return
    }

    # Table header
    Write-Host ('  {0,-24} {1,-10} {2,-8} {3,-30} {4,-6}' -f 'ID', 'STATUS', 'PRIORITY', 'PROJECT', 'STORIES') -ForegroundColor White
    Write-Host ('  {0,-24} {1,-10} {2,-8} {3,-30} {4,-6}' -f ('-' * 24), ('-' * 10), ('-' * 8), ('-' * 30), ('-' * 6))

    foreach ($entry in $entries) {
        $shortId = if ($entry.id.Length -gt 24) { $entry.id.Substring(0, 21) + '...' } else { $entry.id }
        $shortProject = Split-Path $entry.projectRoot -Leaf
        if ($shortProject.Length -gt 30) { $shortProject = $shortProject.Substring(0, 27) + '...' }

        # Get story count from PRD
        $stories = '?'
        if (Test-Path $entry.prdPath) {
            try {
                $prd = Get-Content $entry.prdPath -Raw | ConvertFrom-Json
                $total = @($prd.userStories).Count
                $complete = @($prd.userStories | Where-Object { $_.passes -eq $true }).Count
                $stories = "$complete/$total"
            } catch { }
        }

        # Color based on status
        $color = switch ($entry.status) {
            'pending'   { 'Yellow' }
            'active'    { 'Cyan' }
            'completed' { 'Green' }
            'failed'    { 'Red' }
            default     { 'White' }
        }

        Write-Host -NoNewline ('  {0,-24} ' -f $shortId)
        Write-Host -NoNewline ('{0,-10} ' -f $entry.status) -ForegroundColor $color
        Write-Host ('{0,-8} {1,-30} {2,-6}' -f $entry.priority, $shortProject, $stories)
    }

    Write-Host ''
    Write-Host "  Total: $($entries.Count) entries"
    Write-Host ''
}

function Invoke-Remove {
    if (-not $Id) {
        Write-Host 'Error: Entry ID required. Use -Id or -i' -ForegroundColor Red
        return
    }

    $entry = Get-RalphQueueEntry -EntryId $Id
    if (-not $entry) {
        Write-Host ''
        Write-Host "Entry not found: $Id" -ForegroundColor Yellow
        Write-Host ''
        return
    }

    if (Remove-RalphQueueEntry -EntryId $Id) {
        Write-Host ''
        Write-Host ([char]0x2714 + ' Removed entry from queue') -ForegroundColor Green
        Write-Host ''
        Write-Host "  Entry ID: $Id"
        Write-Host "  Project:  $($entry.projectRoot)"
        Write-Host ''
    }
    else {
        Write-Host 'Error: Failed to remove entry' -ForegroundColor Red
    }
}

function Invoke-Clear {
    Show-Banner 'CLEARING COMPLETED ENTRIES'

    $cleared = Clear-RalphQueueCompleted

    if ($cleared -eq 0) {
        Write-Host '  No completed entries to clear.'
    }
    else {
        Write-Host "  $([char]0x2714) Cleared $cleared completed entries" -ForegroundColor Green
    }
    Write-Host ''
}

function Invoke-Status {
    Show-Banner 'RALPH QUEUE STATUS'

    $summary = Get-RalphQueueSummary

    Write-Host '  Queue Summary:'
    Write-Host ''
    Write-Host ('    {0,-12} {1}' -f 'Total:', $summary.total)
    Write-Host -NoNewline ('    {0,-12} ' -f 'Pending:')
    Write-Host $summary.pending -ForegroundColor Yellow
    Write-Host -NoNewline ('    {0,-12} ' -f 'Active:')
    Write-Host $summary.active -ForegroundColor Cyan
    Write-Host -NoNewline ('    {0,-12} ' -f 'Completed:')
    Write-Host $summary.completed -ForegroundColor Green
    Write-Host -NoNewline ('    {0,-12} ' -f 'Failed:')
    Write-Host $summary.failed -ForegroundColor Red
    Write-Host ''

    $queueFile = Get-RalphQueueFile
    Write-Host "  Queue file: $queueFile"
    Write-Host ''
}

function Invoke-Check {
    [CmdletBinding()]
    param()

    if (-not $script:Prd) {
        Write-Host 'Error: PRD path required. Use -Prd or -p' -ForegroundColor Red
        $script:checkExitCode = 1
        return
    }

    # Convert to absolute path if needed
    $prdPath = if ([System.IO.Path]::IsPathRooted($script:Prd)) { $script:Prd } else { Join-Path (Get-Location) $script:Prd }

    if (-not (Test-Path $prdPath)) {
        if (-not $script:Quiet) {
            Write-Host "Error: PRD file not found: $prdPath" -ForegroundColor Red
        }
        $script:checkExitCode = 1
        return
    }

    try {
        $prdData = Get-Content $prdPath -Raw | ConvertFrom-Json
        $stories = @($prdData.userStories)
        $total = $stories.Count
        $complete = @($stories | Where-Object { $_.passes -eq $true }).Count
        $incomplete = $total - $complete
    }
    catch {
        if (-not $script:Quiet) {
            Write-Host "Error: Failed to parse PRD file: $_" -ForegroundColor Red
        }
        $script:checkExitCode = 1
        return
    }

    if ($script:Quiet) {
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
    if ($total -eq 0) {
        Write-Host "PRD has no stories: $prdPath" -ForegroundColor Red
        Write-Host ''
        Write-Host "Incomplete: 0"
        $script:checkExitCode = 1
        return
    }
    elseif ($incomplete -eq 0) {
        Write-Host "PRD COMPLETE: $complete/$total stories done" -ForegroundColor Green
        Write-Host ''
        Write-Host "  PRD: $prdPath"
        Write-Host ''
        Write-Host "Incomplete: 0"
        $script:checkExitCode = 0
        return
    }
    else {
        Write-Host "PRD INCOMPLETE: $complete/$total stories done, $incomplete remaining" -ForegroundColor Yellow
        Write-Host ''
        Write-Host "  PRD: $prdPath"
        Write-Host ''
        Write-Host '  Incomplete stories:'
        foreach ($story in ($stories | Where-Object { $_.passes -ne $true })) {
            Write-Host "    - $($story.id): $($story.title)"
        }
        Write-Host ''
        Write-Host "Incomplete: $incomplete"
        $script:checkExitCode = 1
        return
    }
}

function Invoke-Start {
    # Default count to CPU cores / 2
    if ($Count -le 0) {
        $Count = [Math]::Max(1, [int]([Environment]::ProcessorCount / 2))
    }

    # Check if there are pending entries
    $pending = @(Get-RalphQueueEntries -Status 'pending')
    if ($pending.Count -eq 0) {
        Write-Host ''
        Write-Host 'No pending entries in queue.' -ForegroundColor Yellow
        Write-Host 'Use "ralph-queue.ps1 add -p <prd> -r <project>" to add entries first.'
        Write-Host ''
        return
    }

    Show-Banner 'STARTING QUEUE WORKERS'

    Write-Host "  Pending entries: $($pending.Count)"
    Write-Host "  Starting $Count workers with $MaxIterations max iterations each..."
    Write-Host ''

    # Use ralph-parallel.ps1 with queue mode
    $parallelScript = Join-Path $scriptDir 'ralph-parallel.ps1'
    if (-not (Test-Path $parallelScript)) {
        Write-Host 'Error: ralph-parallel.ps1 not found' -ForegroundColor Red
        return
    }

    # Start workers in queue mode
    & $parallelScript Start -Count $Count -MaxIterations $MaxIterations -QueueMode

    Write-Host ''
    Write-Host 'Workers started in queue mode.' -ForegroundColor Green
    Write-Host 'Use "ralph-queue.ps1 status" to monitor progress.'
    Write-Host ''
}

# Main
$script:checkExitCode = 0

switch ($Command) {
    'add'    { Invoke-Add }
    'list'   { Invoke-List }
    'remove' { Invoke-Remove }
    'clear'  { Invoke-Clear }
    'status' { Invoke-Status }
    'check'  { Invoke-Check; exit $script:checkExitCode }
    'start'  { Invoke-Start }
    'help'   { Show-Help }
    default  { Invoke-Status }
}
