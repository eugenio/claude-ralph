#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Single iteration runner for ralph.

.DESCRIPTION
    ralph-once.ps1 runs a single iteration of Claude Code for the current PRD.
    Useful for testing or manual control over the execution flow.
    Unlike ralph.ps1, this script does not loop or archive previous runs.

.EXAMPLE
    ./ralph-once.ps1
    Runs a single iteration with the current PRD.

.NOTES
    Requires:
    - PowerShell 7+
    - Claude Code CLI (claude)
    - Git
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

function Show-Banner {
    Write-Host ''
    Write-Host ([string]::new([char]0x2550, 55)) -ForegroundColor Blue
    Write-Host '           RALPH SINGLE ITERATION' -ForegroundColor Yellow
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
    Write-Host ''

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

    # Show banner
    Show-Banner

    # Get and show current status
    $status = Get-PrdStatus -Prd $prd
    Show-Status -Status $status
    Write-Host ''

    # Check if already complete
    if ($status.Remaining -eq 0) {
        Write-ColoredOutput 'All stories already complete!' -Color Green
        exit 0
    }

    # Run Claude Code
    try {
        $result = Invoke-ClaudeCode -PromptPath $paths.PromptFile -ProjectRoot $paths.ProjectRoot

        if ($result.ExitCode -ne 0) {
            Write-ColoredOutput "Claude Code exited with code $($result.ExitCode)" -Color Red
        }
    }
    catch {
        Write-ColoredOutput "Error running Claude Code: $_" -Color Red
        exit 1
    }

    # Check for completion signal
    $hasSignal = $false
    if (-not [string]::IsNullOrEmpty($result.Output)) {
        $hasSignal = [regex]::Matches($result.Output, '<promise>COMPLETE</promise>').Count -gt 0
    }

    if ($hasSignal) {
        Write-Host ''
        Write-ColoredOutput 'All stories complete!' -Color Green
    }
    else {
        # Show updated status
        Write-Host ''
        Write-Host ([string]::new([char]0x2550, 55)) -ForegroundColor Blue

        # Re-read PRD to get latest status (Claude may have updated it)
        $prd = Read-PrdJson
        $statusNew = Get-PrdStatus -Prd $prd

        Write-Host 'Completed: ' -ForegroundColor Cyan -NoNewline
        Write-Host "$($statusNew.Complete)" -ForegroundColor Green -NoNewline
        Write-Host "/$($statusNew.Total) stories"

        if ($statusNew.Complete -gt $status.Complete) {
            Write-ColoredOutput 'Progress made! Run again to continue.' -Color Green
        }
        else {
            Write-ColoredOutput 'No new stories completed. Check progress.txt for details.' -Color Yellow
        }
    }
}

# Run main
Main
