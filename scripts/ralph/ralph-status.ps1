#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Displays the current status of ralph PRD stories.

.DESCRIPTION
    ralph-status.ps1 reads the PRD file and displays a formatted summary of all user stories,
    including completion status, progress bar, and current git branch.

.EXAMPLE
    ./ralph-status.ps1
    Shows status of all stories in the current PRD.

.NOTES
    Requires:
    - PowerShell 7+
    - Git (for branch display)
#>

[CmdletBinding()]
param()

# Import the shared utilities module
$modulePath = Join-Path $PSScriptRoot 'RalphUtils.psm1'
if (-not (Test-Path $modulePath)) {
    Write-Host 'Error: RalphUtils.psm1 not found in script directory' -ForegroundColor Red
    exit 1
}
Import-Module $modulePath -Force

# Get paths
$paths = Get-RalphPaths

function Get-GitBranch {
    <#
    .SYNOPSIS
        Gets the current git branch name.
    .OUTPUTS
        String with branch name, or $null if not in a git repo.
    #>
    try {
        $branch = git branch --show-current 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($branch)) {
            return $branch.Trim()
        }
    }
    catch {
        # Ignore errors
    }
    return $null
}

function Get-ProgressBar {
    <#
    .SYNOPSIS
        Creates a visual progress bar using Unicode block characters.
    .PARAMETER Percentage
        Completion percentage (0-100).
    .PARAMETER Width
        Width of the progress bar in characters (default 30).
    .OUTPUTS
        String containing the progress bar.
    #>
    param(
        [Parameter(Mandatory)]
        [int]$Percentage,

        [Parameter()]
        [int]$Width = 30
    )

    # Ensure percentage is in valid range
    $Percentage = [Math]::Max(0, [Math]::Min(100, $Percentage))

    # Calculate filled and empty portions
    $filledCount = [Math]::Floor(($Percentage / 100) * $Width)
    $emptyCount = $Width - $filledCount

    # Unicode block characters: full block (2588), light shade (2591)
    $fullBlock = [char]0x2588
    $emptyBlock = [char]0x2591

    $filled = [string]::new($fullBlock, $filledCount)
    $empty = [string]::new($emptyBlock, $emptyCount)

    return "$filled$empty"
}

function Show-Banner {
    <#
    .SYNOPSIS
        Displays the status banner with branch info.
    #>
    param(
        [string]$Branch
    )

    Write-Host ''
    Write-Host ([string]::new([char]0x2550, 55)) -ForegroundColor Blue
    Write-Host '              RALPH STATUS' -ForegroundColor Yellow
    Write-Host ([string]::new([char]0x2550, 55)) -ForegroundColor Blue

    if ($Branch) {
        Write-Host 'Branch: ' -ForegroundColor Cyan -NoNewline
        Write-Host $Branch -ForegroundColor White
    }
    Write-Host ''
}

function Show-ProgressSummary {
    <#
    .SYNOPSIS
        Displays the progress summary with visual progress bar.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Status
    )

    # Progress bar
    $progressBar = Get-ProgressBar -Percentage $Status.Percentage -Width 30
    Write-Host 'Progress: ' -ForegroundColor Cyan -NoNewline
    Write-Host '[' -NoNewline
    if ($Status.Percentage -eq 100) {
        Write-Host $progressBar -ForegroundColor Green -NoNewline
    }
    elseif ($Status.Percentage -ge 50) {
        Write-Host $progressBar -ForegroundColor Yellow -NoNewline
    }
    else {
        Write-Host $progressBar -ForegroundColor Red -NoNewline
    }
    Write-Host '] ' -NoNewline
    Write-Host "$($Status.Percentage)%" -ForegroundColor White

    # Story counts
    Write-Host 'Stories:  ' -ForegroundColor Cyan -NoNewline
    Write-Host "$($Status.Complete)" -ForegroundColor Green -NoNewline
    Write-Host ' complete, ' -NoNewline
    Write-Host "$($Status.Remaining)" -ForegroundColor Yellow -NoNewline
    Write-Host " remaining (total: $($Status.Total))"
    Write-Host ''
}

function Show-StoryTable {
    <#
    .SYNOPSIS
        Displays all stories in a formatted table.
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Stories
    )

    # Column widths
    $idWidth = 8
    $priorityWidth = 8
    $statusWidth = 10
    $titleWidth = 40
    $totalWidth = $idWidth + $priorityWidth + $statusWidth + $titleWidth + 6

    # Header
    Write-Host ([string]::new([char]0x2500, $totalWidth)) -ForegroundColor Gray
    Write-Host ('ID'.PadRight($idWidth) + '  ' + 'Priority'.PadRight($priorityWidth) + '  ' + 'Status'.PadRight($statusWidth) + '  ' + 'Title') -ForegroundColor White
    Write-Host ([string]::new([char]0x2500, $totalWidth)) -ForegroundColor Gray

    # Sort by priority
    $sortedStories = $Stories | Sort-Object { $_.priority }

    foreach ($story in $sortedStories) {
        $status = if ($story.passes) { 'COMPLETE' } else { 'PENDING' }
        $statusColor = if ($story.passes) { 'Green' } else { 'Yellow' }

        # Truncate title if too long
        $title = $story.title
        if ($title.Length -gt $titleWidth) {
            $title = $title.Substring(0, $titleWidth - 3) + '...'
        }

        # Build the row with proper padding
        $idStr = $story.id.ToString().PadRight($idWidth)
        $priorityStr = $story.priority.ToString().PadRight($priorityWidth)
        $statusStr = $status.PadRight($statusWidth)

        Write-Host ($idStr + '  ' + $priorityStr + '  ') -NoNewline
        Write-Host ($statusStr + '  ') -ForegroundColor $statusColor -NoNewline
        Write-Host $title
    }

    Write-Host ([string]::new([char]0x2500, $totalWidth)) -ForegroundColor Gray
    Write-Host ''
}

function Show-IncompleteStories {
    <#
    .SYNOPSIS
        Lists incomplete stories with priorities.
    #>
    param(
        [Parameter(Mandatory)]
        [array]$IncompleteStories
    )

    if ($IncompleteStories.Count -eq 0) {
        return
    }

    Write-Host 'Incomplete Stories (by priority):' -ForegroundColor Yellow
    Write-Host ''

    foreach ($story in $IncompleteStories) {
        Write-Host '  ' -NoNewline
        Write-Host "[$($story.priority)]" -ForegroundColor Cyan -NoNewline
        Write-Host " $($story.id): " -ForegroundColor White -NoNewline
        Write-Host $story.title -ForegroundColor Gray
    }
    Write-Host ''
}

# Main execution
function Main {
    # Check for PRD file
    if (-not (Test-Path $paths.PrdFile)) {
        Write-Host 'Error: prd.json not found' -ForegroundColor Red
        Write-Host ''
        Write-Host "Expected location: $($paths.PrdFile)" -ForegroundColor Gray
        Write-Host ''
        Write-Host 'To get started:' -ForegroundColor Yellow
        Write-Host '  1. Copy prd.json.example to prd.json'
        Write-Host '  2. Edit prd.json with your user stories'
        Write-Host '  3. Run this script again'
        exit 1
    }

    # Read PRD
    $prd = Read-PrdJson
    if ($null -eq $prd) {
        Write-Host 'Error: Failed to parse prd.json' -ForegroundColor Red
        Write-Host 'Please check the file contains valid JSON.'
        exit 1
    }

    # Get branch
    $branch = Get-GitBranch

    # Show banner
    Show-Banner -Branch $branch

    # Get status
    $status = Get-PrdStatus -Prd $prd

    if ($status.Total -eq 0) {
        Write-Host 'No user stories found in prd.json' -ForegroundColor Yellow
        Write-Host 'Add user stories to the "userStories" array to get started.'
        exit 0
    }

    # Show progress summary
    Show-ProgressSummary -Status $status

    # Show story table
    $stories = @($prd.userStories)
    Show-StoryTable -Stories $stories

    # Show incomplete stories
    if ($status.IncompleteStories.Count -gt 0) {
        Show-IncompleteStories -IncompleteStories $status.IncompleteStories
    }
    else {
        Write-Host 'All stories complete!' -ForegroundColor Green
        Write-Host ''
    }
}

# Run main
Main
