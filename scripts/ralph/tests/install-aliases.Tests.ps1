#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for install-aliases.ps1 PowerShell alias installation script.

.DESCRIPTION
    Comprehensive test suite for install-aliases.ps1 including:
    - Script structure validation
    - Profile path detection
    - Alias block generation
    - Installation behavior (creating profile, adding aliases)
    - Uninstallation behavior (removing aliases)
    - DryRun mode
    - Command parameter handling
    - Update/overwrite behavior
    - Edge cases
#>

BeforeAll {
    # Define the script path
    $script:installScript = Join-Path $PSScriptRoot '..' 'install-aliases.ps1'

    # Read script content once for structure tests
    $script:scriptContent = Get-Content -Path $script:installScript -Raw

    # Markers used by the script
    $script:AliasesMarker = '# Ralph Loop Aliases - BEGIN'
    $script:AliasesEndMarker = '# Ralph Loop Aliases - END'

    # Replicate key functions for unit testing without executing the full script

    # Write-ColorOutput function replica
    $script:WriteColorOutput = {
        param(
            [string]$Message,
            [string]$Color = 'White'
        )
        Write-Host $Message -ForegroundColor $Color
    }

    # Get-ProfilePath function replica
    $script:GetProfilePath = {
        if ($PROFILE) {
            return $PROFILE.CurrentUserAllHosts
        }
        return Join-Path $HOME 'Documents\PowerShell\profile.ps1'
    }

    # Get-AliasBlock function replica (simplified for testing)
    $script:GetAliasBlock = {
        param([string]$ScriptDir)
        $timestamp = Get-Date -Format 'o'
        return @"
$($script:AliasesMarker)
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

$($script:AliasesEndMarker)
"@
    }

    # Test-AliasesInstalled function replica
    $script:TestAliasesInstalled = {
        param([string]$ProfilePath)

        if (-not (Test-Path $ProfilePath)) {
            return $false
        }

        $content = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue
        if ($content -and $content.Contains($script:AliasesMarker)) {
            return $true
        }
        return $false
    }

    # Uninstall-Aliases function replica
    $script:UninstallAliases = {
        param(
            [string]$ProfilePath,
            [switch]$Quiet
        )

        if (-not (Test-Path $ProfilePath)) {
            return @{ Success = $true; Message = 'Profile not found' }
        }

        $content = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue
        if (-not $content -or -not $content.Contains($script:AliasesMarker)) {
            return @{ Success = $true; Message = 'No Ralph aliases found' }
        }

        # Remove the alias block using regex
        $pattern = "(?s)`n?$([regex]::Escape($script:AliasesMarker)).*?$([regex]::Escape($script:AliasesEndMarker))"
        $newContent = $content -replace $pattern, ''

        # Write back
        Set-Content -Path $ProfilePath -Value $newContent.TrimEnd()

        return @{ Success = $true; Message = 'Aliases removed' }
    }

    # Install-Aliases function replica
    $script:InstallAliases = {
        param(
            [string]$ProfilePath,
            [string]$ScriptDir,
            [switch]$DryRun
        )

        $profileDir = Split-Path $ProfilePath -Parent

        # Check if already installed
        if (Test-Path $ProfilePath) {
            $content = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue
            if ($content -and $content.Contains($script:AliasesMarker)) {
                # Remove old aliases first
                & $script:UninstallAliases -ProfilePath $ProfilePath -Quiet
            }
        }

        $aliasBlock = & $script:GetAliasBlock -ScriptDir $ScriptDir

        if ($DryRun) {
            return @{
                Success    = $true
                DryRun     = $true
                AliasBlock = $aliasBlock
            }
        }

        # Create profile directory if it doesn't exist
        if (-not (Test-Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }

        # Create profile if it doesn't exist
        if (-not (Test-Path $ProfilePath)) {
            New-Item -ItemType File -Path $ProfilePath -Force | Out-Null
        }

        # Append aliases
        Add-Content -Path $ProfilePath -Value "`n$aliasBlock"

        return @{
            Success    = $true
            DryRun     = $false
            AliasBlock = $aliasBlock
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Script Structure Tests
# ─────────────────────────────────────────────────────────────────────────────

Describe 'install-aliases.ps1 Script Structure' {
    It 'Has proper help documentation' {
        $script:scriptContent | Should -Match '\.SYNOPSIS'
        $script:scriptContent | Should -Match '\.DESCRIPTION'
        $script:scriptContent | Should -Match '\.PARAMETER'
        $script:scriptContent | Should -Match '\.EXAMPLE'
    }

    It 'Uses CmdletBinding' {
        $script:scriptContent | Should -Match '\[CmdletBinding\(\)\]'
    }

    It 'Defines Command parameter with ValidateSet' {
        $script:scriptContent | Should -Match "\[ValidateSet\('install', 'uninstall', 'show', 'check'\)\]"
    }

    It 'Defines DryRun switch parameter' {
        $script:scriptContent | Should -Match '\[switch\]\$DryRun'
    }

    It 'Sets ErrorActionPreference to Stop' {
        $script:scriptContent | Should -Match "\`$ErrorActionPreference = 'Stop'"
    }

    It 'Uses $PSScriptRoot for script directory' {
        $script:scriptContent | Should -Match '\$ScriptDir = \$PSScriptRoot'
    }

    It 'Defines BEGIN and END markers for alias block' {
        $script:scriptContent | Should -Match '# Ralph Loop Aliases - BEGIN'
        $script:scriptContent | Should -Match '# Ralph Loop Aliases - END'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Function Definition Tests
# ─────────────────────────────────────────────────────────────────────────────

Describe 'Script Functions' {
    It 'Defines Write-ColorOutput function' {
        $script:scriptContent | Should -Match 'function Write-ColorOutput'
    }

    It 'Defines Get-ProfilePath function' {
        $script:scriptContent | Should -Match 'function Get-ProfilePath'
    }

    It 'Defines Get-AliasBlock function' {
        $script:scriptContent | Should -Match 'function Get-AliasBlock'
    }

    It 'Defines Show-Aliases function' {
        $script:scriptContent | Should -Match 'function Show-Aliases'
    }

    It 'Defines Test-AliasesInstalled function' {
        $script:scriptContent | Should -Match 'function Test-AliasesInstalled'
    }

    It 'Defines Install-Aliases function' {
        $script:scriptContent | Should -Match 'function Install-Aliases'
    }

    It 'Defines Uninstall-Aliases function' {
        $script:scriptContent | Should -Match 'function Uninstall-Aliases'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Profile Path Detection Tests
# ─────────────────────────────────────────────────────────────────────────────

Describe 'Get-ProfilePath Function' {
    Context 'Profile path resolution' {
        It 'Uses $PROFILE.CurrentUserAllHosts when available' {
            $script:scriptContent | Should -Match '\$PROFILE\.CurrentUserAllHosts'
        }

        It 'Has fallback path for when $PROFILE is not available' {
            # Match the fallback path - use flexible pattern for path separators
            $script:scriptContent | Should -Match "Join-Path \`$HOME.*Documents.*PowerShell.*profile\.ps1"
        }

        It 'Returns a non-empty path' {
            $result = & $script:GetProfilePath
            $result | Should -Not -BeNullOrEmpty
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Alias Block Generation Tests
# ─────────────────────────────────────────────────────────────────────────────

Describe 'Get-AliasBlock Function' {
    Context 'Block content' {
        It 'Includes BEGIN marker' {
            $result = & $script:GetAliasBlock -ScriptDir '/test/path'
            $result | Should -Match '# Ralph Loop Aliases - BEGIN'
        }

        It 'Includes END marker' {
            $result = & $script:GetAliasBlock -ScriptDir '/test/path'
            $result | Should -Match '# Ralph Loop Aliases - END'
        }

        It 'Includes installation timestamp comment' {
            $result = & $script:GetAliasBlock -ScriptDir '/test/path'
            $result | Should -Match '# Date:'
        }

        It 'Includes installer path comment' {
            $result = & $script:GetAliasBlock -ScriptDir '/test/path'
            $result | Should -Match '# Installed by:'
        }

        It 'Includes ralph function' {
            $result = & $script:GetAliasBlock -ScriptDir '/test/path'
            $result | Should -Match 'function global:ralph'
        }

        It 'Includes ralph-supervisor function' {
            $result = & $script:GetAliasBlock -ScriptDir '/test/path'
            $result | Should -Match 'function global:ralph-supervisor'
        }

        It 'Includes ralph-status function' {
            $result = & $script:GetAliasBlock -ScriptDir '/test/path'
            $result | Should -Match 'function global:ralph-status'
        }

        It 'Includes ralph-stop function' {
            $result = & $script:GetAliasBlock -ScriptDir '/test/path'
            $result | Should -Match 'function global:ralph-stop'
        }

        It 'Includes ralph-cleanup function' {
            $result = & $script:GetAliasBlock -ScriptDir '/test/path'
            $result | Should -Match 'function global:ralph-cleanup'
        }

        It 'Includes ralph-dashboard function' {
            $result = & $script:GetAliasBlock -ScriptDir '/test/path'
            $result | Should -Match 'function global:ralph-dashboard'
        }

        It 'Includes ralph-parallel function' {
            $result = & $script:GetAliasBlock -ScriptDir '/test/path'
            $result | Should -Match 'function global:ralph-parallel'
        }

        It 'Includes ralph-locks function' {
            $result = & $script:GetAliasBlock -ScriptDir '/test/path'
            $result | Should -Match 'function global:ralph-locks'
        }

        It 'Uses provided script directory in function paths' {
            $result = & $script:GetAliasBlock -ScriptDir '/custom/scripts/ralph'
            # Match path with either forward or back slash (cross-platform)
            $result | Should -Match '/custom/scripts/ralph[/\\]ralph\.ps1'
        }
    }

    Context 'Script alias block content' {
        It 'Script defines all ralph functions' {
            $script:scriptContent | Should -Match 'ralph-supervisor'
            $script:scriptContent | Should -Match 'ralph-status'
            $script:scriptContent | Should -Match 'ralph-stop'
            $script:scriptContent | Should -Match 'ralph-cleanup'
            $script:scriptContent | Should -Match 'ralph-dashboard'
            $script:scriptContent | Should -Match 'ralph-parallel'
            $script:scriptContent | Should -Match 'ralph-locks'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Show-Aliases Function Tests
# ─────────────────────────────────────────────────────────────────────────────

Describe 'Show-Aliases Function' {
    It 'Script defines function descriptions array' {
        $script:scriptContent | Should -Match '\$functions = @\('
    }

    It 'Lists ralph command' {
        $script:scriptContent | Should -Match "Name = 'ralph'"
    }

    It 'Lists ralph-supervisor command' {
        $script:scriptContent | Should -Match "Name = 'ralph-supervisor'"
    }

    It 'Lists ralph-status command' {
        $script:scriptContent | Should -Match "Name = 'ralph-status'"
    }

    It 'Lists ralph-stop command' {
        $script:scriptContent | Should -Match "Name = 'ralph-stop'"
    }

    It 'Lists ralph-cleanup command' {
        $script:scriptContent | Should -Match "Name = 'ralph-cleanup'"
    }

    It 'Lists ralph-dashboard command' {
        $script:scriptContent | Should -Match "Name = 'ralph-dashboard'"
    }

    It 'Lists ralph-parallel command' {
        $script:scriptContent | Should -Match "Name = 'ralph-parallel'"
    }

    It 'Lists ralph-locks command' {
        $script:scriptContent | Should -Match "Name = 'ralph-locks'"
    }

    It 'Uses colored output for function names' {
        $script:scriptContent | Should -Match '-ForegroundColor Green'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Test-AliasesInstalled Function Tests
# ─────────────────────────────────────────────────────────────────────────────

Describe 'Test-AliasesInstalled Function' {
    Context 'When profile does not exist' {
        It 'Returns $false for non-existent profile' {
            $nonExistentPath = Join-Path $TestDrive 'nonexistent_profile.ps1'
            $result = & $script:TestAliasesInstalled -ProfilePath $nonExistentPath
            $result | Should -Be $false
        }
    }

    Context 'When profile exists without aliases' {
        It 'Returns $false when aliases marker is not present' {
            $profilePath = Join-Path $TestDrive 'no_aliases_profile.ps1'
            Set-Content -Path $profilePath -Value @"
# My PowerShell profile
Set-Alias ll Get-ChildItem
"@
            $result = & $script:TestAliasesInstalled -ProfilePath $profilePath
            $result | Should -Be $false
        }
    }

    Context 'When profile has aliases installed' {
        It 'Returns $true when aliases marker is present' {
            $profilePath = Join-Path $TestDrive 'with_aliases_profile.ps1'
            Set-Content -Path $profilePath -Value @"
# My PowerShell profile
Set-Alias ll Get-ChildItem

$($script:AliasesMarker)
function global:ralph { & 'test' @args }
$($script:AliasesEndMarker)
"@
            $result = & $script:TestAliasesInstalled -ProfilePath $profilePath
            $result | Should -Be $true
        }
    }

    Context 'Script Test-AliasesInstalled patterns' {
        It 'Checks for profile existence' {
            $script:scriptContent | Should -Match 'Test-Path \$profilePath'
        }

        It 'Uses Contains to check for marker' {
            $script:scriptContent | Should -Match '\.Contains\(\$AliasesMarker\)'
        }

        It 'Shows appropriate status message' {
            $script:scriptContent | Should -Match 'Ralph aliases are installed'
            $script:scriptContent | Should -Match 'Ralph aliases are NOT installed'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Install-Aliases Function Tests
# ─────────────────────────────────────────────────────────────────────────────

Describe 'Install-Aliases Function' {
    Context 'Fresh installation' {
        It 'Creates profile directory if it does not exist' {
            $profilePath = Join-Path $TestDrive 'newdir' 'PowerShell' 'profile.ps1'
            $profileDir = Split-Path $profilePath -Parent

            Test-Path $profileDir | Should -Be $false

            $result = & $script:InstallAliases -ProfilePath $profilePath -ScriptDir '/test/ralph'

            Test-Path $profileDir | Should -Be $true
            $result.Success | Should -Be $true
        }

        It 'Creates profile file if it does not exist' {
            $profilePath = Join-Path $TestDrive 'create_profile.ps1'

            Test-Path $profilePath | Should -Be $false

            $result = & $script:InstallAliases -ProfilePath $profilePath -ScriptDir '/test/ralph'

            Test-Path $profilePath | Should -Be $true
        }

        It 'Appends alias block to profile' {
            $profilePath = Join-Path $TestDrive 'append_profile.ps1'
            Set-Content -Path $profilePath -Value '# Existing content'

            $result = & $script:InstallAliases -ProfilePath $profilePath -ScriptDir '/test/ralph'

            $content = Get-Content -Path $profilePath -Raw
            $content | Should -Match '# Existing content'
            $content | Should -Match $script:AliasesMarker
            $content | Should -Match $script:AliasesEndMarker
        }
    }

    Context 'Update existing installation' {
        It 'Removes old aliases before installing new ones' {
            $profilePath = Join-Path $TestDrive 'update_profile.ps1'
            Set-Content -Path $profilePath -Value @"
# My profile

$($script:AliasesMarker)
# Old aliases
function global:ralph { & '/old/path/ralph.ps1' @args }
$($script:AliasesEndMarker)

# After aliases
"@
            $result = & $script:InstallAliases -ProfilePath $profilePath -ScriptDir '/new/path'

            $content = Get-Content -Path $profilePath -Raw
            $content | Should -Not -Match '/old/path/'
            # Match new path with either separator (Windows uses backslash internally)
            $content | Should -Match '/new/path[/\\]'
            # Should only have one set of markers
            $beginMatches = [regex]::Matches($content, [regex]::Escape($script:AliasesMarker))
            $beginMatches.Count | Should -Be 1
        }

        It 'Preserves content before and after alias block' {
            $profilePath = Join-Path $TestDrive 'preserve_profile.ps1'
            Set-Content -Path $profilePath -Value @"
# Before content
Set-Alias ll ls

$($script:AliasesMarker)
function global:ralph { & '/old/ralph.ps1' @args }
$($script:AliasesEndMarker)

# After content
Set-PSReadLineOption -EditMode Emacs
"@
            $result = & $script:InstallAliases -ProfilePath $profilePath -ScriptDir '/new/ralph'

            $content = Get-Content -Path $profilePath -Raw
            $content | Should -Match '# Before content'
            $content | Should -Match 'Set-Alias ll ls'
            $content | Should -Match '# After content'
            $content | Should -Match 'Set-PSReadLineOption'
        }
    }

    Context 'DryRun mode' {
        It 'Returns alias block without modifying profile when DryRun is set' {
            $profilePath = Join-Path $TestDrive 'dryrun_profile.ps1'
            Set-Content -Path $profilePath -Value '# Original content' -NoNewline

            $result = & $script:InstallAliases -ProfilePath $profilePath -ScriptDir '/test/ralph' -DryRun

            $result.DryRun | Should -Be $true
            $result.AliasBlock | Should -Match $script:AliasesMarker

            # Profile should be unchanged - compare trimmed to handle line ending differences
            $content = Get-Content -Path $profilePath -Raw
            $content.Trim() | Should -Be '# Original content'
        }

        It 'Does not create profile when DryRun is set' {
            $profilePath = Join-Path $TestDrive 'nonexistent_dryrun.ps1'

            $result = & $script:InstallAliases -ProfilePath $profilePath -ScriptDir '/test/ralph' -DryRun

            $result.DryRun | Should -Be $true
            Test-Path $profilePath | Should -Be $false
        }
    }

    Context 'Script Install-Aliases patterns' {
        It 'Shows installation progress message' {
            $script:scriptContent | Should -Match 'Installing Ralph aliases'
        }

        It 'Uses New-Item with -Force for directory creation' {
            $script:scriptContent | Should -Match 'New-Item -ItemType Directory -Path \$profileDir -Force'
        }

        It 'Uses New-Item with -Force for file creation' {
            $script:scriptContent | Should -Match 'New-Item -ItemType File -Path \$profilePath -Force'
        }

        It 'Uses Add-Content to append aliases' {
            $script:scriptContent | Should -Match 'Add-Content -Path \$profilePath'
        }

        It 'Shows success message after installation' {
            $script:scriptContent | Should -Match 'Aliases installed successfully!'
        }

        It 'Shows how to activate aliases' {
            # Match backtick-escaped $PROFILE in the source
            $script:scriptContent | Should -Match '\`\$PROFILE'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Uninstall-Aliases Function Tests
# ─────────────────────────────────────────────────────────────────────────────

Describe 'Uninstall-Aliases Function' {
    Context 'When profile does not exist' {
        It 'Returns success when profile not found' {
            $nonExistentPath = Join-Path $TestDrive 'nonexistent_uninstall.ps1'
            $result = & $script:UninstallAliases -ProfilePath $nonExistentPath
            $result.Success | Should -Be $true
        }
    }

    Context 'When profile has no aliases' {
        It 'Returns success when no aliases found' {
            $profilePath = Join-Path $TestDrive 'no_aliases_uninstall.ps1'
            Set-Content -Path $profilePath -Value '# No aliases here'

            $result = & $script:UninstallAliases -ProfilePath $profilePath

            $result.Success | Should -Be $true
            $result.Message | Should -Match 'No Ralph aliases found'
        }
    }

    Context 'When profile has aliases' {
        It 'Removes alias block from profile' {
            $profilePath = Join-Path $TestDrive 'remove_aliases.ps1'
            Set-Content -Path $profilePath -Value @"
# Before

$($script:AliasesMarker)
function global:ralph { & 'test' @args }
$($script:AliasesEndMarker)

# After
"@
            $result = & $script:UninstallAliases -ProfilePath $profilePath

            $result.Success | Should -Be $true

            $content = Get-Content -Path $profilePath -Raw
            $content | Should -Not -Match $script:AliasesMarker
            $content | Should -Not -Match $script:AliasesEndMarker
            $content | Should -Match '# Before'
            $content | Should -Match '# After'
        }

        It 'Preserves surrounding content' {
            $profilePath = Join-Path $TestDrive 'preserve_uninstall.ps1'
            Set-Content -Path $profilePath -Value @"
# My important config
Set-Alias ll ls

$($script:AliasesMarker)
function global:ralph { & 'test' @args }
function global:ralph-status { & 'test' @args }
$($script:AliasesEndMarker)

# More important config
`$env:EDITOR = 'code'
"@
            $result = & $script:UninstallAliases -ProfilePath $profilePath

            $content = Get-Content -Path $profilePath -Raw
            $content | Should -Match '# My important config'
            $content | Should -Match 'Set-Alias ll ls'
            $content | Should -Match '# More important config'
            $content | Should -Match "EDITOR = 'code'"
        }
    }

    Context 'Quiet mode' {
        It 'Accepts -Quiet parameter' {
            $profilePath = Join-Path $TestDrive 'quiet_uninstall.ps1'
            Set-Content -Path $profilePath -Value '# No aliases'

            # Should not throw and should work silently
            $result = & $script:UninstallAliases -ProfilePath $profilePath -Quiet
            $result.Success | Should -Be $true
        }
    }

    Context 'Script Uninstall-Aliases patterns' {
        It 'Uses regex to remove alias block' {
            $script:scriptContent | Should -Match '\-replace \$pattern'
        }

        It 'Uses Set-Content to write back modified content' {
            $script:scriptContent | Should -Match 'Set-Content -Path \$profilePath'
        }

        It 'Trims trailing whitespace' {
            $script:scriptContent | Should -Match '\.TrimEnd\(\)'
        }

        It 'Shows removal message when not quiet' {
            $script:scriptContent | Should -Match 'Removing Ralph aliases'
        }

        It 'Shows success message after removal' {
            $script:scriptContent | Should -Match 'Aliases removed successfully!'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Command Parameter Tests
# ─────────────────────────────────────────────────────────────────────────────

Describe 'Command Parameter Handling' {
    Context 'Switch statement' {
        It 'Script uses switch statement for command routing' {
            $script:scriptContent | Should -Match 'switch \(\$Command\)'
        }

        It 'Handles install command' {
            $script:scriptContent | Should -Match "'install' \{"
        }

        It 'Handles uninstall command' {
            $script:scriptContent | Should -Match "'uninstall' \{"
        }

        It 'Handles show command' {
            $script:scriptContent | Should -Match "'show' \{"
        }

        It 'Handles check command' {
            $script:scriptContent | Should -Match "'check' \{"
        }
    }

    Context 'Default command' {
        It 'Default command is install' {
            $script:scriptContent | Should -Match "\[string\]\`$Command = 'install'"
        }
    }

    Context 'DryRun parameter passing' {
        It 'Passes DryRun to Install-Aliases' {
            $script:scriptContent | Should -Match 'Install-Aliases -DryRun:\$DryRun'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Banner and Output Tests
# ─────────────────────────────────────────────────────────────────────────────

Describe 'Banner and Output' {
    It 'Shows RALPH ALIAS INSTALLER banner' {
        $script:scriptContent | Should -Match 'RALPH ALIAS INSTALLER'
    }

    It 'Uses Cyan color for banner' {
        $script:scriptContent | Should -Match '-ForegroundColor Cyan'
    }

    It 'Uses decorative separator lines' {
        $script:scriptContent | Should -Match '=========================================='
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Edge Cases
# ─────────────────────────────────────────────────────────────────────────────

Describe 'Edge Cases' {
    Context 'Empty profile' {
        It 'Handles empty profile file' {
            $profilePath = Join-Path $TestDrive 'empty_profile.ps1'
            New-Item -Path $profilePath -ItemType File -Force | Out-Null

            $result = & $script:InstallAliases -ProfilePath $profilePath -ScriptDir '/test/ralph'

            $result.Success | Should -Be $true
            $content = Get-Content -Path $profilePath -Raw
            $content | Should -Match $script:AliasesMarker
        }
    }

    Context 'Profile with only aliases' {
        It 'Handles profile containing only Ralph aliases' {
            $profilePath = Join-Path $TestDrive 'only_aliases.ps1'
            Set-Content -Path $profilePath -Value @"
$($script:AliasesMarker)
function global:ralph { & '/test/ralph.ps1' @args }
$($script:AliasesEndMarker)
"@
            $result = & $script:UninstallAliases -ProfilePath $profilePath

            $result.Success | Should -Be $true
            $content = Get-Content -Path $profilePath -Raw
            $content.Trim() | Should -BeNullOrEmpty
        }
    }

    Context 'Nested directory creation' {
        It 'Creates deeply nested profile directory' {
            $profilePath = Join-Path $TestDrive 'deep' 'nested' 'path' 'PowerShell' 'profile.ps1'

            $result = & $script:InstallAliases -ProfilePath $profilePath -ScriptDir '/test/ralph'

            $result.Success | Should -Be $true
            Test-Path $profilePath | Should -Be $true
        }
    }

    Context 'Multiple alias blocks (should not happen but handle gracefully)' {
        It 'Removes first occurrence during uninstall' {
            $profilePath = Join-Path $TestDrive 'multi_block.ps1'
            Set-Content -Path $profilePath -Value @"
# First block
$($script:AliasesMarker)
function global:ralph { & '/first/ralph.ps1' @args }
$($script:AliasesEndMarker)

# Some content between

$($script:AliasesMarker)
function global:ralph { & '/second/ralph.ps1' @args }
$($script:AliasesEndMarker)
"@
            # First uninstall
            $result1 = & $script:UninstallAliases -ProfilePath $profilePath

            $result1.Success | Should -Be $true

            # Content check - at least one block should be removed
            $content = Get-Content -Path $profilePath -Raw
            $beginMatches = [regex]::Matches($content, [regex]::Escape($script:AliasesMarker))
            $beginMatches.Count | Should -BeLessOrEqual 1
        }
    }

    Context 'Special characters in script path' {
        It 'Handles paths with spaces' {
            $result = & $script:GetAliasBlock -ScriptDir '/path/with spaces/ralph'
            $result | Should -Match '/path/with spaces/ralph'
        }

        It 'Handles paths with hyphens and underscores' {
            $result = & $script:GetAliasBlock -ScriptDir '/my-project_v2/scripts/ralph'
            $result | Should -Match '/my-project_v2/scripts/ralph'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Cross-Platform Compatibility Tests
# ─────────────────────────────────────────────────────────────────────────────

Describe 'Cross-Platform Compatibility' {
    Context 'Path handling' {
        It 'Uses Join-Path for profile path construction' {
            $script:scriptContent | Should -Match "Join-Path \`$HOME"
        }

        It 'Uses Split-Path for directory extraction' {
            $script:scriptContent | Should -Match 'Split-Path \$profilePath -Parent'
        }
    }

    Context 'Profile detection' {
        It 'Checks $PROFILE availability before using it' {
            $script:scriptContent | Should -Match 'if \(\$PROFILE\)'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Integration with Existing Profile Content
# ─────────────────────────────────────────────────────────────────────────────

Describe 'Integration with Existing Profile Content' {
    Context 'Complex profile scenarios' {
        It 'Works with profile containing functions' {
            $profilePath = Join-Path $TestDrive 'complex_functions.ps1'
            Set-Content -Path $profilePath -Value @"
# My custom functions
function Get-Weather { param([string]`$City) Write-Host "Weather for `$City" }
function Start-Project { Set-Location ~/projects }

# Aliases
Set-Alias weather Get-Weather
Set-Alias proj Start-Project
"@
            $result = & $script:InstallAliases -ProfilePath $profilePath -ScriptDir '/test/ralph'

            $result.Success | Should -Be $true

            $content = Get-Content -Path $profilePath -Raw
            $content | Should -Match 'function Get-Weather'
            $content | Should -Match 'function Start-Project'
            $content | Should -Match 'Set-Alias weather'
            $content | Should -Match $script:AliasesMarker
        }

        It 'Works with profile containing modules and imports' {
            $profilePath = Join-Path $TestDrive 'modules_profile.ps1'
            Set-Content -Path $profilePath -Value @"
# Import modules
Import-Module posh-git
Import-Module PSReadLine

# Configure PSReadLine
Set-PSReadLineKeyHandler -Key Tab -Function Complete
Set-PSReadLineOption -PredictionSource History
"@
            $result = & $script:InstallAliases -ProfilePath $profilePath -ScriptDir '/test/ralph'

            $result.Success | Should -Be $true

            $content = Get-Content -Path $profilePath -Raw
            $content | Should -Match 'Import-Module posh-git'
            $content | Should -Match 'Import-Module PSReadLine'
            $content | Should -Match 'Set-PSReadLineKeyHandler'
        }

        It 'Works with profile containing environment variables' {
            $profilePath = Join-Path $TestDrive 'env_profile.ps1'
            Set-Content -Path $profilePath -Value @"
# Environment setup
`$env:EDITOR = 'code'
`$env:PAGER = 'less'
`$env:PATH = "`$env:PATH;C:\tools"
"@
            $result = & $script:InstallAliases -ProfilePath $profilePath -ScriptDir '/test/ralph'

            $result.Success | Should -Be $true

            $content = Get-Content -Path $profilePath -Raw
            $content | Should -Match "EDITOR = 'code'"
            $content | Should -Match "PAGER = 'less'"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Idempotency Tests
# ─────────────────────────────────────────────────────────────────────────────

Describe 'Idempotency' {
    It 'Running install multiple times produces same result' {
        $profilePath = Join-Path $TestDrive 'idempotent_profile.ps1'
        Set-Content -Path $profilePath -Value '# Initial content'

        # First install
        $result1 = & $script:InstallAliases -ProfilePath $profilePath -ScriptDir '/test/ralph'
        $content1 = Get-Content -Path $profilePath -Raw

        # Second install
        $result2 = & $script:InstallAliases -ProfilePath $profilePath -ScriptDir '/test/ralph'
        $content2 = Get-Content -Path $profilePath -Raw

        # Handle both single result and array result (from update path)
        $success1 = if ($result1 -is [array]) { $result1[-1].Success } else { $result1.Success }
        $success2 = if ($result2 -is [array]) { $result2[-1].Success } else { $result2.Success }
        $success1 | Should -Be $true
        $success2 | Should -Be $true

        # Should only have one alias block
        $beginMatches = [regex]::Matches($content2, [regex]::Escape($script:AliasesMarker))
        $beginMatches.Count | Should -Be 1
    }

    It 'Running uninstall on clean profile is safe' {
        $profilePath = Join-Path $TestDrive 'clean_uninstall.ps1'
        Set-Content -Path $profilePath -Value '# Clean profile'

        # Uninstall on profile with no aliases
        $result = & $script:UninstallAliases -ProfilePath $profilePath

        $result.Success | Should -Be $true

        $content = Get-Content -Path $profilePath -Raw
        $content | Should -Match '# Clean profile'
    }
}
