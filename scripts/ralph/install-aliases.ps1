<#
.SYNOPSIS
    Ralph Loop Alias Installation Script (PowerShell)
    Installs PowerShell aliases/functions for convenient access to Ralph commands

.DESCRIPTION
    Installs the following functions to your PowerShell profile:
    - ralph-supervisor    Start supervised Ralph loop
    - ralph-status        Show Ralph supervisor status
    - ralph-stop          Stop Ralph supervisor
    - ralph-cleanup       Clean stale state files
    - ralph-dashboard     Show all Ralph supervisors

.PARAMETER Command
    The action to perform: install, uninstall, show, check (default: install)

.PARAMETER DryRun
    Show what would be done without making changes

.EXAMPLE
    pwsh install-aliases.ps1
    pwsh install-aliases.ps1 -Command uninstall
    pwsh install-aliases.ps1 -Command show
    pwsh install-aliases.ps1 -Command check
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('install', 'uninstall', 'show', 'check')]
    [string]$Command = 'install',

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot

# Markers for the alias block
$AliasesMarker = '# Ralph Loop Aliases - BEGIN'
$AliasesEndMarker = '# Ralph Loop Aliases - END'

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = 'White'
    )
    Write-Host $Message -ForegroundColor $Color
}

function Get-ProfilePath {
    # Use CurrentUserAllHosts profile for broader compatibility
    if ($PROFILE) {
        return $PROFILE.CurrentUserAllHosts
    }
    # Fallback
    return Join-Path $HOME 'Documents\PowerShell\profile.ps1'
}

function Get-AliasBlock {
    $timestamp = Get-Date -Format 'o'
    $block = @"
$AliasesMarker
# Installed by: $ScriptDir\install-aliases.ps1
# Date: $timestamp

# Ralph Loop Process Supervisor functions
function global:ralph-supervisor { & '$ScriptDir\ralph-supervisor.ps1' @args }
function global:ralph-status { & '$ScriptDir\ralph-status.ps1' @args }
function global:ralph-stop { & '$ScriptDir\ralph-stop.ps1' @args }
function global:ralph-cleanup { & '$ScriptDir\ralph-cleanup.ps1' @args }
function global:ralph-dashboard { & '$ScriptDir\ralph-dashboard.ps1' @args }
function global:ralph-parallel { & '$ScriptDir\ralph-parallel.ps1' @args }
function global:ralph-locks { & '$ScriptDir\ralph-locks.ps1' @args }

# Main ralph function
function global:ralph { & '$ScriptDir\ralph.ps1' @args }

$AliasesEndMarker
"@
    return $block
}

function Show-Aliases {
    Write-ColorOutput "`nRalph Loop Functions:" -Color Cyan
    Write-Host ""

    $functions = @(
        @{ Name = 'ralph'; Desc = 'Main Ralph loop script' }
        @{ Name = 'ralph-supervisor'; Desc = 'Start supervised Ralph loop' }
        @{ Name = 'ralph-status'; Desc = 'Show Ralph supervisor status' }
        @{ Name = 'ralph-stop'; Desc = 'Stop Ralph supervisor' }
        @{ Name = 'ralph-cleanup'; Desc = 'Clean stale state files' }
        @{ Name = 'ralph-dashboard'; Desc = 'Show all Ralph supervisors' }
        @{ Name = 'ralph-parallel'; Desc = 'Run multiple Ralph instances' }
        @{ Name = 'ralph-locks'; Desc = 'Manage story locks' }
    )

    foreach ($fn in $functions) {
        Write-Host "  " -NoNewline
        Write-Host ("{0,-20}" -f $fn.Name) -ForegroundColor Green -NoNewline
        Write-Host " -> $($fn.Desc)"
    }
    Write-Host ""
}

function Test-AliasesInstalled {
    $profilePath = Get-ProfilePath

    if (-not (Test-Path $profilePath)) {
        Write-ColorOutput "Profile does not exist: $profilePath" -Color Yellow
        return $false
    }

    $content = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if ($content -and $content.Contains($AliasesMarker)) {
        Write-ColorOutput "Ralph aliases are installed in: $profilePath" -Color Green
        return $true
    } else {
        Write-ColorOutput "Ralph aliases are NOT installed in: $profilePath" -Color Yellow
        return $false
    }
}

function Install-Aliases {
    param([switch]$DryRun)

    $profilePath = Get-ProfilePath
    $profileDir = Split-Path $profilePath -Parent

    Write-ColorOutput "Installing Ralph aliases..." -Color White
    Write-Host "  Profile: $profilePath"
    Write-Host ""

    # Check if already installed
    if (Test-Path $profilePath) {
        $content = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
        if ($content -and $content.Contains($AliasesMarker)) {
            Write-ColorOutput "Aliases already installed. Updating..." -Color Yellow
            Uninstall-Aliases -Quiet
        }
    }

    $aliasBlock = Get-AliasBlock

    if ($DryRun) {
        Write-ColorOutput "[DRY RUN] Would append to $profilePath`:" -Color Cyan
        Write-Host ""
        Write-Host $aliasBlock
        Write-Host ""
        return
    }

    # Create profile directory if it doesn't exist
    if (-not (Test-Path $profileDir)) {
        Write-ColorOutput "Creating profile directory: $profileDir" -Color Yellow
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    # Create profile if it doesn't exist
    if (-not (Test-Path $profilePath)) {
        Write-ColorOutput "Creating profile: $profilePath" -Color Yellow
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }

    # Append aliases
    Add-Content -Path $profilePath -Value "`n$aliasBlock"

    Write-ColorOutput "Aliases installed successfully!" -Color Green
    Write-Host ""
    Write-Host "To use immediately, run:"
    Write-ColorOutput "  . `$PROFILE" -Color Cyan
    Write-Host ""
    Write-Host "Or restart your PowerShell session."
    Write-Host ""
    Show-Aliases
}

function Uninstall-Aliases {
    param([switch]$Quiet)

    $profilePath = Get-ProfilePath

    if (-not (Test-Path $profilePath)) {
        if (-not $Quiet) {
            Write-ColorOutput "Profile not found: $profilePath" -Color Yellow
        }
        return
    }

    $content = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if (-not $content -or -not $content.Contains($AliasesMarker)) {
        if (-not $Quiet) {
            Write-ColorOutput "No Ralph aliases found in: $profilePath" -Color Yellow
        }
        return
    }

    if (-not $Quiet) {
        Write-ColorOutput "Removing Ralph aliases from $profilePath..." -Color White
    }

    # Remove the alias block using regex
    $pattern = "(?s)`n?$([regex]::Escape($AliasesMarker)).*?$([regex]::Escape($AliasesEndMarker))"
    $newContent = $content -replace $pattern, ''

    # Write back
    Set-Content -Path $profilePath -Value $newContent.TrimEnd()

    if (-not $Quiet) {
        Write-ColorOutput "Aliases removed successfully!" -Color Green
    }
}

# Main
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       RALPH ALIAS INSTALLER" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

switch ($Command) {
    'install' {
        Install-Aliases -DryRun:$DryRun
    }
    'uninstall' {
        Uninstall-Aliases
    }
    'show' {
        Show-Aliases
    }
    'check' {
        Test-AliasesInstalled | Out-Null
    }
}
