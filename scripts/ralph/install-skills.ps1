#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Installs ralph skills globally to ~/.claude/skills/ for use in any project.

.DESCRIPTION
    install-skills.ps1 copies all skills from the ralph skills directory to the
    global Claude Code skills directory (~/.claude/skills/). This makes the skills
    available for interactive Claude Code sessions in any project.

    Existing skills are updated (overwritten) when this script runs.

.EXAMPLE
    ./install-skills.ps1
    Installs all skills from scripts/ralph/skills/ to ~/.claude/skills/

.NOTES
    Requires:
    - PowerShell 7+

    The destination directory is:
    - Linux/macOS: ~/.claude/skills/
    - Windows: $env:USERPROFILE\.claude\skills\
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

function Get-HomeDirectory {
    <#
    .SYNOPSIS
        Gets the user's home directory cross-platform.
    .OUTPUTS
        String path to the home directory.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # PowerShell 7+ always has $HOME, but check $env:USERPROFILE as fallback for Windows
    if ($HOME) {
        return $HOME
    }
    elseif ($env:USERPROFILE) {
        return $env:USERPROFILE
    }
    else {
        # Last resort fallback
        return [Environment]::GetFolderPath('UserProfile')
    }
}

function Get-SourceSkillsPath {
    <#
    .SYNOPSIS
        Gets the path to the source skills directory.
    .OUTPUTS
        String path to the skills directory.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Skills are at repo root (../../skills from scripts/ralph/)
    return Join-Path $PSScriptRoot '..' '..' 'skills'
}

function Get-DestinationSkillsPath {
    <#
    .SYNOPSIS
        Gets the path to the global Claude skills directory.
    .OUTPUTS
        String path to ~/.claude/skills/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $homeDir = Get-HomeDirectory
    return Join-Path $homeDir '.claude' 'skills'
}

function Install-Skills {
    <#
    .SYNOPSIS
        Copies all skills from source to global destination.
    .DESCRIPTION
        Creates the destination directory if needed and copies all skill folders.
        Existing skills are overwritten.
    .OUTPUTS
        Hashtable with Success, SkillsInstalled, and Errors properties.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $sourcePath = Get-SourceSkillsPath
    $destPath = Get-DestinationSkillsPath
    $skillsInstalled = @()
    $errors = @()

    # Check if source skills directory exists
    if (-not (Test-Path $sourcePath)) {
        return @{
            Success         = $false
            SkillsInstalled = @()
            Errors          = @("Source skills directory not found: $sourcePath")
        }
    }

    # Get all skill directories
    $skillDirs = Get-ChildItem -Path $sourcePath -Directory -ErrorAction SilentlyContinue
    if (-not $skillDirs -or $skillDirs.Count -eq 0) {
        return @{
            Success         = $false
            SkillsInstalled = @()
            Errors          = @("No skills found in: $sourcePath")
        }
    }

    # Create destination directory if it doesn't exist
    if (-not (Test-Path $destPath)) {
        try {
            New-Item -Path $destPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-ColoredOutput "Created directory: $destPath" -Color Gray
        }
        catch {
            return @{
                Success         = $false
                SkillsInstalled = @()
                Errors          = @("Failed to create destination directory: $_")
            }
        }
    }

    # Copy each skill
    foreach ($skillDir in $skillDirs) {
        $skillName = $skillDir.Name
        $skillDest = Join-Path $destPath $skillName

        try {
            # Remove existing skill directory if it exists (for clean overwrite)
            if (Test-Path $skillDest) {
                Remove-Item -Path $skillDest -Recurse -Force -ErrorAction Stop
            }

            # Copy the skill directory
            Copy-Item -Path $skillDir.FullName -Destination $skillDest -Recurse -Force -ErrorAction Stop
            $skillsInstalled += $skillName
        }
        catch {
            $errors += "Failed to install skill '$skillName': $_"
        }
    }

    return @{
        Success         = $errors.Count -eq 0
        SkillsInstalled = $skillsInstalled
        Errors          = $errors
    }
}

function Show-Banner {
    <#
    .SYNOPSIS
        Displays the install-skills banner.
    #>
    [CmdletBinding()]
    param()

    Write-Host ''
    Write-Host ([string]::new([char]0x2550, 55)) -ForegroundColor Blue
    Write-Host '         RALPH SKILL INSTALLER' -ForegroundColor Yellow
    Write-Host ([string]::new([char]0x2550, 55)) -ForegroundColor Blue
}

function Get-RalphScriptsPath {
    <#
    .SYNOPSIS
        Gets the path to the ralph scripts directory.
    .OUTPUTS
        String path to the ralph scripts directory.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Check if we're in scripts/ralph or repo root
    $scriptDir = $PSScriptRoot
    if (Test-Path (Join-Path $scriptDir 'ralph.ps1')) {
        return $scriptDir
    }
    $candidatePath = Join-Path $scriptDir 'scripts' 'ralph'
    if (Test-Path (Join-Path $candidatePath 'ralph.ps1')) {
        return $candidatePath
    }
    # Fallback to PSScriptRoot
    return $scriptDir
}

function Install-PowerShellAliases {
    <#
    .SYNOPSIS
        Installs PowerShell functions for ralph tools to the user's profile.
    .OUTPUTS
        Hashtable with Success, ProfilePath, and Message properties.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $ralphDir = Get-RalphScriptsPath
    $profilePath = $PROFILE

    # Ensure profile directory exists
    $profileDir = Split-Path -Parent $profilePath
    if (-not (Test-Path $profileDir)) {
        try {
            New-Item -Path $profileDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-ColoredOutput "Created profile directory: $profileDir" -Color Gray
        }
        catch {
            return @{
                Success     = $false
                ProfilePath = $profilePath
                Message     = "Failed to create profile directory: $_"
            }
        }
    }

    # Create profile file if it doesn't exist
    if (-not (Test-Path $profilePath)) {
        try {
            New-Item -Path $profilePath -ItemType File -Force -ErrorAction Stop | Out-Null
            Write-ColoredOutput "Created profile: $profilePath" -Color Gray
        }
        catch {
            return @{
                Success     = $false
                ProfilePath = $profilePath
                Message     = "Failed to create profile: $_"
            }
        }
    }

    # Check if Ralph functions already exist
    $profileContent = Get-Content -Path $profilePath -Raw -ErrorAction SilentlyContinue
    if ($profileContent -and $profileContent -match '# Ralph functions') {
        return @{
            Success     = $true
            ProfilePath = $profilePath
            Message     = 'Ralph functions already exist in profile, skipping'
            AlreadyExists = $true
        }
    }

    # Build the function block
    $functionBlock = @"

# Ralph functions
function ralph { pwsh "$ralphDir/ralph.ps1" @args }
function ralph-once { pwsh "$ralphDir/ralph-once.ps1" @args }
function ralph-status { pwsh "$ralphDir/ralph-status.ps1" @args }
"@

    # Append to profile
    try {
        Add-Content -Path $profilePath -Value $functionBlock -ErrorAction Stop
        return @{
            Success     = $true
            ProfilePath = $profilePath
            Message     = 'Ralph functions added to profile'
            AlreadyExists = $false
        }
    }
    catch {
        return @{
            Success     = $false
            ProfilePath = $profilePath
            Message     = "Failed to write to profile: $_"
        }
    }
}

function Show-AliasInstructions {
    <#
    .SYNOPSIS
        Shows post-installation instructions for aliases.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [Parameter()]
        [bool]$AlreadyExists = $false
    )

    $ralphDir = Get-RalphScriptsPath

    if ($AlreadyExists) {
        Write-Host ''
        Write-ColoredOutput 'Ralph functions already installed in your profile.' -Color Gray
    }
    else {
        Write-Host ''
        Write-ColoredOutput 'PowerShell functions installed successfully!' -Color Green
        Write-Host ''
        Write-Host 'To activate the functions, run:' -ForegroundColor Yellow
        Write-Host "  . $ProfilePath" -ForegroundColor Cyan
        Write-ColoredOutput '  Or restart PowerShell' -Color Gray
    }

    Write-Host ''
    Write-Host 'Available commands (work from any directory):' -ForegroundColor Yellow
    Write-Host '  ralph        - Run the ralph loop' -ForegroundColor Cyan
    Write-Host '  ralph-once   - Run a single ralph iteration' -ForegroundColor Cyan
    Write-Host '  ralph-status - Check ralph progress' -ForegroundColor Cyan
    Write-Host ''
    Write-ColoredOutput "Note: Functions use absolute paths and will always run scripts from:" -Color Gray
    Write-ColoredOutput "  $ralphDir" -Color Gray
}

function Main {
    <#
    .SYNOPSIS
        Main execution function.
    #>
    [CmdletBinding()]
    param()

    Show-Banner
    Write-Host ''

    $sourcePath = Get-SourceSkillsPath
    $destPath = Get-DestinationSkillsPath

    Write-ColoredOutput "Source: $sourcePath" -Color Cyan
    Write-ColoredOutput "Destination: $destPath" -Color Cyan
    Write-Host ''

    # Install skills
    $result = Install-Skills

    if ($result.Success) {
        Write-ColoredOutput 'Skills installed successfully!' -Color Green
        Write-Host ''
        Write-Host 'Installed skills:' -ForegroundColor Cyan
        foreach ($skill in $result.SkillsInstalled) {
            Write-Host "  - $skill" -ForegroundColor Green
        }
        Write-Host ''
        Write-ColoredOutput 'Skills are now available globally in Claude Code.' -Color Gray
    }
    else {
        # Check if any skills were installed despite errors
        if ($result.SkillsInstalled.Count -gt 0) {
            Write-ColoredOutput 'Some skills installed with errors:' -Color Yellow
            Write-Host ''
            Write-Host 'Installed skills:' -ForegroundColor Cyan
            foreach ($skill in $result.SkillsInstalled) {
                Write-Host "  - $skill" -ForegroundColor Green
            }
            Write-Host ''
        }

        Write-ColoredOutput 'Errors:' -Color Red
        foreach ($err in $result.Errors) {
            Write-Host "  - $err" -ForegroundColor Red
        }
        exit 1
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Optional alias installation
    # ─────────────────────────────────────────────────────────────────────────
    Write-Host ''
    Write-Host ([string]::new([char]0x2500, 55)) -ForegroundColor Blue
    $response = Read-Host 'Would you like to install PowerShell aliases for ralph tools? (y/N)'

    if ($response -match '^[yY]') {
        $aliasResult = Install-PowerShellAliases
        if ($aliasResult.Success) {
            Show-AliasInstructions -ProfilePath $aliasResult.ProfilePath -AlreadyExists $aliasResult.AlreadyExists
        }
        else {
            Write-ColoredOutput "Failed to install aliases: $($aliasResult.Message)" -Color Red
        }
    }
    else {
        Write-ColoredOutput 'Skipping alias installation.' -Color Gray
    }

    Write-Host ''
    exit 0
}

# Run main
Main
