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
        exit 0
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
}

# Run main
Main
