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

function Get-ExpectedRalphFunctions {
    <#
    .SYNOPSIS
        Returns the expected Ralph function definitions for the profile.
    .DESCRIPTION
        Generates the complete list of Ralph functions that should be in the profile,
        using the current ralph scripts path.
    .OUTPUTS
        Hashtable with FunctionBlock (string) and FunctionNames (array) properties.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $ralphDir = Get-RalphScriptsPath

    # Define all expected Ralph functions
    $functions = @(
        @{ Name = 'ralph'; Script = 'ralph.ps1' }
        @{ Name = 'ralph-once'; Script = 'ralph-once.ps1' }
        @{ Name = 'ralph-status'; Script = 'ralph-status.ps1' }
        @{ Name = 'ralph-parallel'; Script = 'ralph-parallel.ps1' }
        @{ Name = 'ralph-dashboard'; Script = 'ralph-dashboard.ps1' }
    )

    $functionLines = @()
    $functionNames = @()

    foreach ($func in $functions) {
        $scriptPath = Join-Path $ralphDir $func.Script
        # Only include functions whose scripts exist
        if (Test-Path $scriptPath) {
            $functionLines += "function $($func.Name) { pwsh `"$ralphDir/$($func.Script)`" @args }"
            $functionNames += $func.Name
        }
    }

    $functionBlock = @"

# Ralph functions
$($functionLines -join "`n")
"@

    return @{
        FunctionBlock = $functionBlock
        FunctionNames = $functionNames
        RalphDir      = $ralphDir
    }
}

function Get-ProfileRalphFunctions {
    <#
    .SYNOPSIS
        Parses the PowerShell profile to extract existing Ralph functions block.
    .DESCRIPTION
        Reads the profile and finds the Ralph functions section, returning its
        content, line positions, and parsed function information.
    .PARAMETER ProfilePath
        Path to the PowerShell profile file.
    .OUTPUTS
        Hashtable with Exists, StartLine, EndLine, Content, FunctionNames, and RalphDir properties.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath
    )

    $result = @{
        Exists        = $false
        StartLine     = -1
        EndLine       = -1
        Content       = ''
        FunctionNames = @()
        RalphDir      = ''
    }

    if (-not (Test-Path $ProfilePath)) {
        return $result
    }

    $content = Get-Content -Path $ProfilePath -Raw -ErrorAction SilentlyContinue
    if (-not $content) {
        return $result
    }

    # Split into lines (handle both Unix and Windows line endings)
    $lines = $content -split "`r?`n"

    # Find the Ralph functions marker
    $startLine = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*#\s*Ralph functions\s*$') {
            $startLine = $i
            break
        }
    }

    if ($startLine -eq -1) {
        return $result
    }

    # Find the end of the Ralph block (next comment marker or blank line after functions)
    $endLine = $startLine
    $functionNames = @()
    $ralphDir = ''

    for ($i = $startLine + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Check if this is a Ralph function line
        if ($line -match '^\s*function\s+(ralph[-\w]*)\s*\{') {
            $functionNames += $Matches[1]
            $endLine = $i

            # Extract the ralph directory from the function definition
            if ($line -match 'pwsh\s+"([^"]+)/ralph') {
                $ralphDir = $Matches[1]
            }
        }
        # Stop at a different comment section or empty line after functions
        elseif ($line -match '^\s*#\s*\w' -and $i -gt $startLine + 1) {
            break
        }
        elseif ($line -match '^\s*$' -and $functionNames.Count -gt 0) {
            # Allow one blank line, but stop at second or after content ends
            if ($i + 1 -lt $lines.Count -and $lines[$i + 1] -notmatch '^\s*function\s+ralph') {
                break
            }
        }
        elseif ($line -notmatch '^\s*$' -and $line -notmatch '^\s*function\s+ralph') {
            # Non-Ralph content found after Ralph section
            break
        }
    }

    $result.Exists = $true
    $result.StartLine = $startLine
    $result.EndLine = $endLine
    $result.Content = ($lines[$startLine..$endLine] -join "`n")
    $result.FunctionNames = $functionNames
    $result.RalphDir = $ralphDir

    return $result
}

function Compare-RalphFunctions {
    <#
    .SYNOPSIS
        Compares expected Ralph functions against those installed in the profile.
    .DESCRIPTION
        Determines if the profile's Ralph functions are up-to-date, outdated, or missing.
    .PARAMETER ProfilePath
        Path to the PowerShell profile file.
    .OUTPUTS
        Hashtable with Status (up-to-date|outdated|missing), details about differences.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath
    )

    $expected = Get-ExpectedRalphFunctions
    $installed = Get-ProfileRalphFunctions -ProfilePath $ProfilePath

    $result = @{
        Status           = 'missing'
        ExpectedCount    = $expected.FunctionNames.Count
        InstalledCount   = 0
        MissingFunctions = @()
        ExtraFunctions   = @()
        PathOutdated     = $false
        ExpectedPath     = $expected.RalphDir
        InstalledPath    = ''
        NeedsUpdate      = $false
    }

    if (-not $installed.Exists) {
        $result.MissingFunctions = $expected.FunctionNames
        return $result
    }

    $result.InstalledCount = $installed.FunctionNames.Count
    $result.InstalledPath = $installed.RalphDir

    # Check for missing functions
    $result.MissingFunctions = @($expected.FunctionNames | Where-Object { $_ -notin $installed.FunctionNames })

    # Check for extra functions (in profile but not expected - rare)
    $result.ExtraFunctions = @($installed.FunctionNames | Where-Object { $_ -notin $expected.FunctionNames })

    # Check if path is outdated
    if ($installed.RalphDir -and $installed.RalphDir -ne $expected.RalphDir) {
        $result.PathOutdated = $true
    }

    # Determine overall status
    if ($result.MissingFunctions.Count -eq 0 -and -not $result.PathOutdated -and $result.ExtraFunctions.Count -eq 0) {
        $result.Status = 'up-to-date'
    }
    else {
        $result.Status = 'outdated'
        $result.NeedsUpdate = $true
    }

    return $result
}

function Install-PowerShellAliases {
    <#
    .SYNOPSIS
        Installs PowerShell functions for ralph tools to the user's profile.
    .DESCRIPTION
        Checks for existing Ralph functions and prompts user for action if found:
        - Skip: Leave profile unchanged
        - Update: Replace only the Ralph functions block in-place
        - Reinstall: Remove old block and append fresh one
    .OUTPUTS
        Hashtable with Success, ProfilePath, Message, and comparison details.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

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

    # Compare expected vs installed functions
    $comparison = Compare-RalphFunctions -ProfilePath $profilePath
    $expected = Get-ExpectedRalphFunctions

    # If no Ralph functions exist, install fresh
    if ($comparison.Status -eq 'missing') {
        return Install-RalphFunctionsToProfile -ProfilePath $profilePath -FunctionBlock $expected.FunctionBlock
    }

    # If up-to-date, report and skip
    if ($comparison.Status -eq 'up-to-date') {
        return @{
            Success       = $true
            ProfilePath   = $profilePath
            Message       = 'Ralph functions are up-to-date'
            AlreadyExists = $true
            Comparison    = $comparison
        }
    }

    # Functions exist but are outdated - prompt user
    Write-Host ''
    Write-Host 'Existing Ralph functions detected in profile:' -ForegroundColor Yellow
    Write-Host "  Installed: $($comparison.InstalledCount) functions" -ForegroundColor Cyan
    Write-Host "  Expected:  $($comparison.ExpectedCount) functions" -ForegroundColor Cyan

    if ($comparison.MissingFunctions.Count -gt 0) {
        Write-Host ''
        Write-Host 'Missing functions:' -ForegroundColor Yellow
        foreach ($func in $comparison.MissingFunctions) {
            Write-Host "  - $func" -ForegroundColor Red
        }
    }

    if ($comparison.PathOutdated) {
        Write-Host ''
        Write-Host 'Path is outdated:' -ForegroundColor Yellow
        Write-Host "  Current:  $($comparison.InstalledPath)" -ForegroundColor Red
        Write-Host "  Expected: $($comparison.ExpectedPath)" -ForegroundColor Green
    }

    Write-Host ''
    Write-Host 'Options:' -ForegroundColor Yellow
    Write-Host '  (S)kip     - Leave profile unchanged' -ForegroundColor Cyan
    Write-Host '  (U)pdate   - Update Ralph functions block in-place' -ForegroundColor Cyan
    Write-Host '  (R)einstall - Remove old block and append fresh one' -ForegroundColor Cyan
    Write-Host ''

    $response = Read-Host 'Choose action [S/U/R]'

    switch -Regex ($response) {
        '^[sS]$' {
            return @{
                Success       = $true
                ProfilePath   = $profilePath
                Message       = 'Skipped - profile unchanged'
                AlreadyExists = $true
                Comparison    = $comparison
                Action        = 'skip'
            }
        }
        '^[uU]$' {
            return Update-RalphFunctionsInProfile -ProfilePath $profilePath -Comparison $comparison
        }
        '^[rR]$' {
            return Reinstall-RalphFunctionsInProfile -ProfilePath $profilePath -Comparison $comparison
        }
        default {
            Write-ColoredOutput 'Invalid choice, skipping.' -Color Gray
            return @{
                Success       = $true
                ProfilePath   = $profilePath
                Message       = 'Skipped - invalid choice'
                AlreadyExists = $true
                Comparison    = $comparison
                Action        = 'skip'
            }
        }
    }
}

function Install-RalphFunctionsToProfile {
    <#
    .SYNOPSIS
        Installs Ralph functions to an empty or new profile.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [Parameter(Mandatory)]
        [string]$FunctionBlock
    )

    try {
        Add-Content -Path $ProfilePath -Value $FunctionBlock -ErrorAction Stop
        return @{
            Success       = $true
            ProfilePath   = $ProfilePath
            Message       = 'Ralph functions added to profile'
            AlreadyExists = $false
            Action        = 'install'
        }
    }
    catch {
        return @{
            Success     = $false
            ProfilePath = $ProfilePath
            Message     = "Failed to write to profile: $_"
        }
    }
}

function Backup-ProfileFile {
    <#
    .SYNOPSIS
        Creates a backup of the profile file before modification.
    .DESCRIPTION
        Copies the profile file to a .bak file in the same directory.
        Overwrites any existing backup file.
    .PARAMETER ProfilePath
        Path to the PowerShell profile file.
    .OUTPUTS
        Hashtable with Success, BackupPath, and Message properties.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath
    )

    if (-not (Test-Path $ProfilePath)) {
        return @{
            Success    = $true
            BackupPath = $null
            Message    = 'No backup needed - profile does not exist'
        }
    }

    $backupPath = "$ProfilePath.bak"

    try {
        Copy-Item -Path $ProfilePath -Destination $backupPath -Force -ErrorAction Stop
        return @{
            Success    = $true
            BackupPath = $backupPath
            Message    = "Backup created: $backupPath"
        }
    }
    catch {
        return @{
            Success    = $false
            BackupPath = $null
            Message    = "Failed to create backup: $_"
        }
    }
}

function Update-RalphFunctionsInProfile {
    <#
    .SYNOPSIS
        Updates Ralph functions block in-place in the profile.
    .DESCRIPTION
        Replaces the existing Ralph functions section while preserving
        all other profile content. Creates a backup file (.bak) before modification.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [Parameter(Mandatory)]
        [hashtable]$Comparison
    )

    $installed = Get-ProfileRalphFunctions -ProfilePath $ProfilePath
    $expected = Get-ExpectedRalphFunctions

    if (-not $installed.Exists) {
        # Shouldn't happen, but handle gracefully
        return Install-RalphFunctionsToProfile -ProfilePath $ProfilePath -FunctionBlock $expected.FunctionBlock
    }

    try {
        # Create backup before modification
        $backupResult = Backup-ProfileFile -ProfilePath $ProfilePath
        if (-not $backupResult.Success) {
            return @{
                Success     = $false
                ProfilePath = $ProfilePath
                Message     = $backupResult.Message
            }
        }

        # Read the profile content
        $content = Get-Content -Path $ProfilePath -Raw -ErrorAction Stop

        # Detect original line ending style (CRLF vs LF)
        $lineEnding = if ($content -match "`r`n") { "`r`n" } else { "`n" }

        $lines = $content -split "`r?`n"

        # Build new content: before Ralph block + new block + after Ralph block
        $beforeBlock = if ($installed.StartLine -gt 0) {
            $lines[0..($installed.StartLine - 1)] -join $lineEnding
        } else { '' }

        $afterBlock = if ($installed.EndLine -lt ($lines.Count - 1)) {
            $lines[($installed.EndLine + 1)..($lines.Count - 1)] -join $lineEnding
        } else { '' }

        # Construct new content (trim the leading newline from FunctionBlock if beforeBlock is empty)
        # Also convert FunctionBlock line endings to match original
        # First normalize to LF, then convert to target line ending
        $normalizedBlock = $expected.FunctionBlock -replace "`r`n", "`n"
        $newFunctionBlock = if ($beforeBlock) {
            $normalizedBlock -replace "`n", $lineEnding
        } else {
            ($normalizedBlock.TrimStart("`n")) -replace "`n", $lineEnding
        }

        $newContent = if ($beforeBlock -and $afterBlock) {
            "$beforeBlock$lineEnding$newFunctionBlock$lineEnding$afterBlock"
        }
        elseif ($beforeBlock) {
            "$beforeBlock$lineEnding$newFunctionBlock"
        }
        elseif ($afterBlock) {
            "$newFunctionBlock$lineEnding$afterBlock"
        }
        else {
            $newFunctionBlock
        }

        # Write back to profile preserving encoding and line endings using raw file API
        # PowerShell's Set-Content may alter line endings on Windows
        [System.IO.File]::WriteAllText($ProfilePath, $newContent)

        return @{
            Success       = $true
            ProfilePath   = $ProfilePath
            Message       = 'Ralph functions updated in-place'
            AlreadyExists = $false
            Action        = 'update'
            BackupPath    = $backupResult.BackupPath
        }
    }
    catch {
        return @{
            Success     = $false
            ProfilePath = $ProfilePath
            Message     = "Failed to update profile: $_"
        }
    }
}

function Reinstall-RalphFunctionsInProfile {
    <#
    .SYNOPSIS
        Removes old Ralph functions block and appends fresh one.
    .DESCRIPTION
        Completely removes the existing Ralph section and adds a new one
        at the end of the profile. Creates a backup file (.bak) before modification.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [Parameter(Mandatory)]
        [hashtable]$Comparison
    )

    $installed = Get-ProfileRalphFunctions -ProfilePath $ProfilePath
    $expected = Get-ExpectedRalphFunctions

    if (-not $installed.Exists) {
        return Install-RalphFunctionsToProfile -ProfilePath $ProfilePath -FunctionBlock $expected.FunctionBlock
    }

    try {
        # Create backup before modification
        $backupResult = Backup-ProfileFile -ProfilePath $ProfilePath
        if (-not $backupResult.Success) {
            return @{
                Success     = $false
                ProfilePath = $ProfilePath
                Message     = $backupResult.Message
            }
        }

        # Read the profile content
        $content = Get-Content -Path $ProfilePath -Raw -ErrorAction Stop

        # Detect original line ending style (CRLF vs LF)
        $lineEnding = if ($content -match "`r`n") { "`r`n" } else { "`n" }

        $lines = $content -split "`r?`n"

        # Build new content: before Ralph block + after Ralph block
        $beforeBlock = if ($installed.StartLine -gt 0) {
            $lines[0..($installed.StartLine - 1)] -join $lineEnding
        } else { '' }

        $afterBlock = if ($installed.EndLine -lt ($lines.Count - 1)) {
            $lines[($installed.EndLine + 1)..($lines.Count - 1)] -join $lineEnding
        } else { '' }

        # Construct new content without the old Ralph block
        $newContent = if ($beforeBlock -and $afterBlock) {
            "$beforeBlock$lineEnding$afterBlock"
        }
        elseif ($beforeBlock) {
            $beforeBlock
        }
        elseif ($afterBlock) {
            $afterBlock
        }
        else {
            ''
        }

        # Append fresh Ralph block (convert line endings to match original)
        # First normalize to LF, then convert to target line ending
        $normalizedBlock = $expected.FunctionBlock -replace "`r`n", "`n"
        $newFunctionBlock = $normalizedBlock -replace "`n", $lineEnding

        # Combine content with new function block
        $finalContent = if ($newContent) {
            "$newContent$newFunctionBlock"
        } else {
            $newFunctionBlock
        }

        # Write back to profile preserving encoding and line endings using raw file API
        [System.IO.File]::WriteAllText($ProfilePath, $finalContent)

        return @{
            Success       = $true
            ProfilePath   = $ProfilePath
            Message       = 'Ralph functions reinstalled (removed old, added fresh)'
            AlreadyExists = $false
            Action        = 'reinstall'
            BackupPath    = $backupResult.BackupPath
        }
    }
    catch {
        return @{
            Success     = $false
            ProfilePath = $ProfilePath
            Message     = "Failed to reinstall functions: $_"
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
        [bool]$AlreadyExists = $false,

        [Parameter()]
        [string]$Action = ''
    )

    $ralphDir = Get-RalphScriptsPath

    if ($AlreadyExists -and $Action -ne 'update' -and $Action -ne 'reinstall') {
        Write-Host ''
        Write-ColoredOutput 'Ralph functions already installed in your profile.' -Color Gray
    }
    else {
        Write-Host ''
        $actionMessage = switch ($Action) {
            'update' { 'Ralph functions updated successfully!' }
            'reinstall' { 'Ralph functions reinstalled successfully!' }
            default { 'PowerShell functions installed successfully!' }
        }
        Write-ColoredOutput $actionMessage -Color Green
        Write-Host ''
        Write-Host 'To activate the functions, run:' -ForegroundColor Yellow
        Write-Host "  . $ProfilePath" -ForegroundColor Cyan
        Write-ColoredOutput '  Or restart PowerShell' -Color Gray
    }

    Write-Host ''
    Write-Host 'Available commands (work from any directory):' -ForegroundColor Yellow
    Write-Host '  ralph           - Run the ralph loop' -ForegroundColor Cyan
    Write-Host '  ralph-once      - Run a single ralph iteration' -ForegroundColor Cyan
    Write-Host '  ralph-status    - Check ralph progress' -ForegroundColor Cyan
    Write-Host '  ralph-parallel  - Run multiple ralph instances in parallel' -ForegroundColor Cyan
    Write-Host '  ralph-dashboard - Monitor ralph instances in a TUI dashboard' -ForegroundColor Cyan
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
            $action = if ($aliasResult.Action) { $aliasResult.Action } else { '' }
            Show-AliasInstructions -ProfilePath $aliasResult.ProfilePath -AlreadyExists $aliasResult.AlreadyExists -Action $action
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
