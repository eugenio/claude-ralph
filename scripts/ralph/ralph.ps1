#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Autonomous AI agent loop for Claude Code.

.DESCRIPTION
    ralph.ps1 runs Claude Code repeatedly until all PRD items are complete.
    Each iteration is a fresh Claude Code instance with clean context.
    Memory persists via git history, progress.txt, and prd.json.

.PARAMETER MaxIterations
    Maximum number of iterations to run. Defaults to 10.

.EXAMPLE
    ./ralph.ps1
    Runs with default 10 iterations.

.EXAMPLE
    ./ralph.ps1 -MaxIterations 20
    Runs with maximum 20 iterations.

.EXAMPLE
    ./ralph.ps1 5
    Runs with maximum 5 iterations (positional parameter).

.NOTES
    Requires:
    - PowerShell 7+
    - Claude Code CLI (claude)
    - Git
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$MaxIterations = 10
)

# Import the shared utilities module
$modulePath = Join-Path $PSScriptRoot 'RalphUtils.psm1'
if (-not (Test-Path $modulePath)) {
    Write-Host 'Error: RalphUtils.psm1 not found in script directory' -ForegroundColor Red
    exit 1
}
Import-Module $modulePath -Force

# Get paths
$paths = Get-RalphPaths

function Show-Banner {
    Write-Host ''
    Write-Host ([char]0x2554 + [string]::new([char]0x2550, 55) + [char]0x2557) -ForegroundColor Blue
    Write-Host ([char]0x2551 + '                  claude-ralph                         ' + [char]0x2551) -ForegroundColor Blue
    Write-Host ([char]0x2551 + '  Autonomous AI Agent Loop (Claude Subscription)       ' + [char]0x2551) -ForegroundColor Blue
    Write-Host ([char]0x255A + [string]::new([char]0x2550, 55) + [char]0x255D) -ForegroundColor Blue
    Write-Host ''
}

function Show-CompleteBanner {
    Write-Host '' -ForegroundColor Green
    Write-Host ([char]0x2554 + [string]::new([char]0x2550, 55) + [char]0x2557) -ForegroundColor Green
    Write-Host ([char]0x2551 + '              RALPH COMPLETE!                          ' + [char]0x2551) -ForegroundColor Green
    Write-Host ([char]0x2551 + '         All user stories have been implemented        ' + [char]0x2551) -ForegroundColor Green
    Write-Host ([char]0x255A + [string]::new([char]0x2550, 55) + [char]0x255D) -ForegroundColor Green
    Write-Host ''
}

function Show-MaxIterationsBanner {
    param([int]$Max)
    Write-Host '' -ForegroundColor Yellow
    Write-Host ([char]0x2554 + [string]::new([char]0x2550, 55) + [char]0x2557) -ForegroundColor Yellow
    Write-Host ([char]0x2551 + "     Max iterations ($Max) reached                       ".Substring(0, 55) + [char]0x2551) -ForegroundColor Yellow
    Write-Host ([char]0x2551 + '     Some stories may still be incomplete              ' + [char]0x2551) -ForegroundColor Yellow
    Write-Host ([char]0x255A + [string]::new([char]0x2550, 55) + [char]0x255D) -ForegroundColor Yellow
    Write-Host ''
}

function Show-IterationBanner {
    param([int]$Current, [int]$Max)
    Write-Host ([string]::new([char]0x2550, 55)) -ForegroundColor Blue
    Write-Host "                    ITERATION $Current / $Max" -ForegroundColor Cyan
    Write-Host ([string]::new([char]0x2550, 55)) -ForegroundColor Blue
}

function Show-Status {
    param([hashtable]$Status)

    if ($null -eq $Status -or $Status.Total -eq 0) {
        Write-Host 'No PRD file found or empty' -ForegroundColor Yellow
        return
    }

    Write-Host 'Stories: ' -ForegroundColor Cyan -NoNewline
    Write-Host "$($Status.Complete)" -ForegroundColor Green -NoNewline
    Write-Host "/$($Status.Total) complete, " -NoNewline
    Write-Host "$($Status.Remaining)" -ForegroundColor Yellow -NoNewline
    Write-Host ' remaining'
}

function Test-AllStoriesComplete {
    param([PSObject]$Prd)

    if ($null -eq $Prd -or $null -eq $Prd.userStories) {
        return $false
    }

    $incomplete = @($Prd.userStories | Where-Object { $_.passes -eq $false })
    return $incomplete.Count -eq 0
}

function Save-CurrentBranch {
    param([PSObject]$Prd)

    if ($null -ne $Prd -and $null -ne $Prd.branchName -and $Prd.branchName -ne '') {
        try {
            Set-Content -Path $paths.LastBranchFile -Value $Prd.branchName -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to save current branch: $_"
        }
    }
}

function Invoke-ArchivePreviousRun {
    param([PSObject]$Prd)

    # Check if we have both PRD file and last branch file
    if (-not (Test-Path $paths.PrdFile) -or -not (Test-Path $paths.LastBranchFile)) {
        return
    }

    $currentBranch = $Prd.branchName
    $lastBranch = Get-Content -Path $paths.LastBranchFile -Raw -ErrorAction SilentlyContinue
    if ($null -ne $lastBranch) {
        $lastBranch = $lastBranch.Trim()
    }

    # Only archive if branches differ
    if ([string]::IsNullOrEmpty($currentBranch) -or [string]::IsNullOrEmpty($lastBranch) -or $currentBranch -eq $lastBranch) {
        return
    }

    # Create archive folder
    $date = Get-Date -Format 'yyyy-MM-dd'
    $folderName = $lastBranch -replace '^ralph/', ''
    $archiveFolder = Join-Path $paths.ArchiveDir "$date-$folderName"

    try {
        if (-not (Test-Path $paths.ArchiveDir)) {
            New-Item -Path $paths.ArchiveDir -ItemType Directory -Force | Out-Null
        }
        New-Item -Path $archiveFolder -ItemType Directory -Force | Out-Null

        # Archive files
        if (Test-Path $paths.PrdFile) {
            Copy-Item -Path $paths.PrdFile -Destination $archiveFolder -Force
        }
        if (Test-Path $paths.ProgressFile) {
            Copy-Item -Path $paths.ProgressFile -Destination $archiveFolder -Force
        }
        if (Test-Path $paths.LogFile) {
            Copy-Item -Path $paths.LogFile -Destination $archiveFolder -Force
        }

        Add-LogEntry "Archived previous run to $archiveFolder"
        Write-ColoredOutput "Archived previous run to $archiveFolder" -Color Yellow

        # Clear progress for new feature
        if (Test-Path $paths.ProgressFile) {
            Remove-Item -Path $paths.ProgressFile -Force
        }
    }
    catch {
        Write-Warning "Failed to archive previous run: $_"
    }
}

function Initialize-ProgressFile {
    if (-not (Test-Path $paths.ProgressFile)) {
        $initialContent = @"
# Ralph Progress Log
Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## Codebase Patterns
(Patterns discovered during implementation will be added here)

---
"@
        try {
            Set-Content -Path $paths.ProgressFile -Value $initialContent -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to initialize progress file: $_"
        }
    }
}

function Invoke-ClaudeCode {
    <#
    .SYNOPSIS
        Runs Claude Code with the prompt file and captures output.
    .OUTPUTS
        Hashtable with ExitCode and Output properties.
    #>
    param(
        [string]$PromptPath,
        [string]$ProjectRoot
    )

    Write-ColoredOutput 'Running Claude Code...' -Color Yellow

    # Read the prompt content
    $promptContent = Get-Content -Path $PromptPath -Raw -ErrorAction Stop

    # Save current location
    $originalLocation = Get-Location

    try {
        # Change to project root
        Set-Location -Path $ProjectRoot

        # Run Claude Code with piped input
        # Using -p for non-interactive (print) mode
        # Using --dangerously-skip-permissions for full autonomy
        # Using --verbose for detailed output
        $output = $promptContent | claude -p --dangerously-skip-permissions --verbose 2>&1
        $exitCode = $LASTEXITCODE

        # Convert output to string if it's an array
        if ($output -is [array]) {
            $outputStr = $output -join "`n"
        }
        else {
            $outputStr = [string]$output
        }

        # Also write output to console (like tee in bash)
        if ($outputStr) {
            Write-Host $outputStr
        }

        return @{
            ExitCode = $exitCode
            Output   = $outputStr
        }
    }
    finally {
        Set-Location -Path $originalLocation
    }
}

function Test-CompletionSignal {
    <#
    .SYNOPSIS
        Checks if the output contains the completion signal.
    .DESCRIPTION
        Counts occurrences of <promise>COMPLETE</promise> in the output.
        Returns true if found at least once.
    #>
    param([string]$Output)

    if ([string]::IsNullOrEmpty($Output)) {
        return $false
    }

    $matches = [regex]::Matches($Output, '<promise>COMPLETE</promise>')
    return $matches.Count -gt 0
}

# Main execution
function Main {
    # Check dependencies
    $deps = Test-Dependencies
    if (-not $deps.IsValid) {
        foreach ($err in $deps.Errors) {
            Write-Host "Error: $err" -ForegroundColor Red
        }
        exit 1
    }

    # Show banner
    Show-Banner

    # Check for PRD file
    if (-not (Test-Path $paths.PrdFile)) {
        Write-Host "Error: prd.json not found in $($paths.RalphDir)" -ForegroundColor Red
        Write-Host 'Create a prd.json file with your user stories first.'
        Write-Host 'See prd.json.example for the expected format.'
        exit 1
    }

    # Read PRD
    $prd = Read-PrdJson
    if ($null -eq $prd) {
        Write-Host 'Error: Failed to read prd.json' -ForegroundColor Red
        exit 1
    }

    # Archive previous run if branch changed
    Invoke-ArchivePreviousRun -Prd $prd

    # Save current branch
    Save-CurrentBranch -Prd $prd

    # Initialize progress file
    Initialize-ProgressFile

    # Log start
    Add-LogEntry "Starting Ralph with max $MaxIterations iterations"

    # Show initial status
    $status = Get-PrdStatus -Prd $prd
    Show-Status -Status $status
    Write-Host ''

    # Main loop
    for ($i = 1; $i -le $MaxIterations; $i++) {
        Show-IterationBanner -Current $i -Max $MaxIterations

        # Refresh PRD and status at start of each iteration
        $prd = Read-PrdJson
        $status = Get-PrdStatus -Prd $prd
        Show-Status -Status $status

        # Check if already complete BEFORE starting work
        if (Test-AllStoriesComplete -Prd $prd) {
            Write-ColoredOutput 'All stories complete! Exiting successfully.' -Color Green
            Add-LogEntry "All stories complete at iteration $i"
            exit 0
        }

        Add-LogEntry "Starting iteration $i"

        # Run Claude Code
        try {
            $result = Invoke-ClaudeCode -PromptPath $paths.PromptFile -ProjectRoot $paths.ProjectRoot

            if ($result.ExitCode -ne 0) {
                Add-LogEntry "Claude Code exited with code $($result.ExitCode)"
                Write-ColoredOutput "Claude Code failed with exit code $($result.ExitCode)" -Color Red
                Write-ColoredOutput 'Continuing to next iteration...' -Color Yellow
            }
        }
        catch {
            Add-LogEntry "Error running Claude Code: $_"
            Write-ColoredOutput "Error running Claude Code: $_" -Color Red
            Write-ColoredOutput 'Continuing to next iteration...' -Color Yellow
            continue
        }

        Write-Host ''
        Write-ColoredOutput "Iteration $i completed. Checking status..." -Color Blue

        # Check for completion signal from Claude
        $hasSignal = Test-CompletionSignal -Output $result.Output

        # Re-read PRD to get latest status (Claude may have updated it)
        $prd = Read-PrdJson

        # Only exit if we find the tag AND all stories are actually complete
        # This prevents false positives from Claude mentioning the tag in explanations
        if ($hasSignal -and (Test-AllStoriesComplete -Prd $prd)) {
            Show-CompleteBanner
            Add-LogEntry "Done! All stories complete at iteration $i (verified via COMPLETE signal + PRD check)"
            exit 0
        }
        elseif ($hasSignal) {
            Add-LogEntry 'Claude output COMPLETE signal but PRD still has incomplete stories - ignoring false positive'
            Write-ColoredOutput 'Warning: Completion signal detected but stories remain incomplete. Continuing...' -Color Yellow
        }

        # Check again AFTER Claude runs in case it updated the PRD
        # This prevents early exit when there's still work to do
        if (Test-AllStoriesComplete -Prd $prd) {
            Show-CompleteBanner
            Add-LogEntry "Done! All stories verified complete at iteration $i (via PRD check)"
            exit 0
        }

        # Show what's remaining
        $status = Get-PrdStatus -Prd $prd
        if ($status.Remaining -gt 0) {
            Write-ColoredOutput "$($status.Remaining) stories still remaining. Continuing..." -Color Yellow
        }

        # Brief pause between iterations
        if ($i -lt $MaxIterations) {
            Write-ColoredOutput 'Waiting 2 seconds before next iteration...' -Color Yellow
            Start-Sleep -Seconds 2
        }
    }

    # Max iterations reached
    Show-MaxIterationsBanner -Max $MaxIterations

    $status = Get-PrdStatus
    Show-Status -Status $status

    Add-LogEntry 'Max iterations reached. Check prd.json for remaining stories.'
}

# Run main
Main
