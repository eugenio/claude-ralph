#Requires -Version 7.0
<#
.SYNOPSIS
    Common utility functions for claude-ralph PowerShell scripts.

.DESCRIPTION
    RalphUtils.psm1 provides shared functionality for all ralph PowerShell scripts including:
    - Dependency checking (claude CLI, git, PowerShell version)
    - PRD file reading/writing and status tracking
    - Colored terminal output
    - Path resolution for ralph directories
    - Logging utilities

.NOTES
    This module is imported by ralph.ps1, ralph-once.ps1, ralph-status.ps1, and install-skills.ps1.
    Requires PowerShell 7.0 or higher for cross-platform compatibility.
#>

# Script-level variables for paths
$script:RalphRoot = $PSScriptRoot

<#
.SYNOPSIS
    Gets paths object with ralph directory locations.

.DESCRIPTION
    Returns a hashtable containing all relevant paths for ralph operations.
    Uses $PSScriptRoot for reliable path resolution regardless of current working directory.

.OUTPUTS
    System.Collections.Hashtable
    A hashtable with the following keys:
    - RalphDir: The ralph scripts directory
    - ProjectRoot: The project root (two levels up from ralph)
    - PrdFile: Path to prd.json
    - ProgressFile: Path to progress.txt
    - PromptFile: Path to prompt.md
    - LogFile: Path to ralph.log
    - ArchiveDir: Path to archive directory
    - LastBranchFile: Path to .last-branch file

.EXAMPLE
    $paths = Get-RalphPaths
    Write-Host "PRD file is at: $($paths.PrdFile)"
#>
function Get-RalphPaths {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $ralphDir = $script:RalphRoot
    $projectRoot = Split-Path -Path (Split-Path -Path $ralphDir -Parent) -Parent

    return @{
        RalphDir       = $ralphDir
        ProjectRoot    = $projectRoot
        PrdFile        = Join-Path $ralphDir 'prd.json'
        ProgressFile   = Join-Path $ralphDir 'progress.txt'
        PromptFile     = Join-Path $ralphDir 'prompt.md'
        LogFile        = Join-Path $ralphDir 'ralph.log'
        ArchiveDir     = Join-Path $ralphDir 'archive'
        LastBranchFile = Join-Path $ralphDir '.last-branch'
    }
}

<#
.SYNOPSIS
    Checks if required dependencies are available.

.DESCRIPTION
    Verifies that claude CLI, git, and PowerShell 7+ are available.
    Returns a hashtable with dependency status and any error messages.

.OUTPUTS
    System.Collections.Hashtable
    A hashtable with the following keys:
    - IsValid: Boolean indicating if all dependencies are met
    - Errors: Array of error messages for missing dependencies
    - Claude: Boolean indicating if claude CLI is available
    - Git: Boolean indicating if git is available
    - PowerShell: Boolean indicating if PowerShell 7+ is running

.EXAMPLE
    $deps = Test-Dependencies
    if (-not $deps.IsValid) {
        $deps.Errors | ForEach-Object { Write-Error $_ }
        exit 1
    }
#>
function Test-Dependencies {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $errors = @()
    $claudeAvailable = $null -ne (Get-Command 'claude' -ErrorAction SilentlyContinue)
    $gitAvailable = $null -ne (Get-Command 'git' -ErrorAction SilentlyContinue)
    $pwshValid = $PSVersionTable.PSVersion.Major -ge 7

    if (-not $claudeAvailable) {
        $errors += 'Claude Code CLI not found. Install with: npm install -g @anthropic-ai/claude-code'
    }

    if (-not $gitAvailable) {
        $errors += 'Git not found. Please install git.'
    }

    if (-not $pwshValid) {
        $errors += "PowerShell 7+ required. Current version: $($PSVersionTable.PSVersion)"
    }

    return @{
        IsValid    = $errors.Count -eq 0
        Errors     = $errors
        Claude     = $claudeAvailable
        Git        = $gitAvailable
        PowerShell = $pwshValid
    }
}

<#
.SYNOPSIS
    Reads and parses the PRD JSON file.

.DESCRIPTION
    Reads the prd.json file and returns its contents as a PowerShell object.
    Handles missing files and invalid JSON gracefully.

.PARAMETER Path
    Optional path to the prd.json file. If not specified, uses the default location.

.OUTPUTS
    System.Management.Automation.PSObject
    The parsed PRD object, or $null if the file doesn't exist or is invalid.

.EXAMPLE
    $prd = Read-PrdJson
    if ($prd) {
        Write-Host "Feature: $($prd.featureName)"
    }

.EXAMPLE
    $prd = Read-PrdJson -Path '/custom/path/prd.json'
#>
function Read-PrdJson {
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter()]
        [string]$Path
    )

    if (-not $Path) {
        $paths = Get-RalphPaths
        $Path = $paths.PrdFile
    }

    if (-not (Test-Path $Path)) {
        Write-Warning "PRD file not found: $Path"
        return $null
    }

    try {
        $content = Get-Content -Path $Path -Raw -ErrorAction Stop
        $prd = $content | ConvertFrom-Json -ErrorAction Stop
        return $prd
    }
    catch {
        Write-Warning "Failed to parse PRD JSON: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Writes an object to the PRD JSON file.

.DESCRIPTION
    Serializes a PowerShell object to JSON and writes it to the prd.json file.
    Uses proper indentation for readability.

.PARAMETER Prd
    The PRD object to write.

.PARAMETER Path
    Optional path to the prd.json file. If not specified, uses the default location.

.OUTPUTS
    System.Boolean
    Returns $true if successful, $false otherwise.

.EXAMPLE
    $prd = Read-PrdJson
    $prd.userStories[0].passes = $true
    Write-PrdJson -Prd $prd
#>
function Write-PrdJson {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PSObject]$Prd,

        [Parameter()]
        [string]$Path
    )

    if (-not $Path) {
        $paths = Get-RalphPaths
        $Path = $paths.PrdFile
    }

    try {
        $json = $Prd | ConvertTo-Json -Depth 10
        Set-Content -Path $Path -Value $json -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warning "Failed to write PRD JSON: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Gets the status of PRD user stories.

.DESCRIPTION
    Reads the PRD and returns statistics about story completion including
    total count, completed count, remaining count, and completion percentage.

.PARAMETER Prd
    Optional PRD object. If not provided, reads from the default prd.json file.

.OUTPUTS
    System.Collections.Hashtable
    A hashtable with the following keys:
    - Total: Total number of user stories
    - Complete: Number of completed stories (passes = true)
    - Remaining: Number of incomplete stories
    - Percentage: Completion percentage (0-100)
    - IncompleteStories: Array of incomplete story objects sorted by priority

.EXAMPLE
    $status = Get-PrdStatus
    Write-Host "Progress: $($status.Complete)/$($status.Total) ($($status.Percentage)%)"
#>
function Get-PrdStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [PSObject]$Prd
    )

    # Only read from file if Prd was not provided at all
    # If explicitly passed as $null, treat it as null
    if (-not $PSBoundParameters.ContainsKey('Prd')) {
        $Prd = Read-PrdJson
    }

    if (-not $Prd) {
        return @{
            Total             = 0
            Complete          = 0
            Remaining         = 0
            Percentage        = 0
            IncompleteStories = @()
        }
    }

    $stories = @($Prd.userStories)
    $total = $stories.Count
    $complete = @($stories | Where-Object { $_.passes -eq $true }).Count
    $remaining = $total - $complete
    $percentage = if ($total -gt 0) { [math]::Round(($complete / $total) * 100) } else { 0 }

    $incompleteStories = @($stories | Where-Object { $_.passes -eq $false } | Sort-Object priority)

    return @{
        Total             = $total
        Complete          = $complete
        Remaining         = $remaining
        Percentage        = $percentage
        IncompleteStories = $incompleteStories
    }
}

<#
.SYNOPSIS
    Writes colored output to the console.

.DESCRIPTION
    A wrapper around Write-Host that provides consistent colored output
    across all ralph scripts. Supports standard color names.

.PARAMETER Message
    The message to display.

.PARAMETER Color
    The foreground color. Valid values: Red, Green, Yellow, Blue, Cyan, White, Gray.
    Defaults to White.

.PARAMETER NoNewline
    If specified, does not append a newline after the message.

.EXAMPLE
    Write-ColoredOutput -Message "Success!" -Color Green

.EXAMPLE
    Write-ColoredOutput "Warning: check this" -Color Yellow

.EXAMPLE
    Write-ColoredOutput "Status: " -Color Cyan -NoNewline
    Write-ColoredOutput "OK" -Color Green
#>
function Write-ColoredOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [Parameter(Position = 1)]
        [ValidateSet('Red', 'Green', 'Yellow', 'Blue', 'Cyan', 'White', 'Gray')]
        [string]$Color = 'White',

        [Parameter()]
        [switch]$NoNewline
    )

    $params = @{
        Object          = $Message
        ForegroundColor = $Color
    }

    if ($NoNewline) {
        $params.NoNewline = $true
    }

    Write-Host @params
}

<#
.SYNOPSIS
    Adds a timestamped entry to the ralph log file.

.DESCRIPTION
    Appends a log entry with timestamp to ralph.log.
    Creates the log file if it doesn't exist.

.PARAMETER Message
    The message to log.

.PARAMETER Path
    Optional path to the log file. If not specified, uses the default ralph.log.

.EXAMPLE
    Add-LogEntry "Starting iteration 1"

.EXAMPLE
    Add-LogEntry -Message "Error occurred" -Path "/custom/ralph.log"
#>
function Add-LogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [Parameter()]
        [string]$Path
    )

    if (-not $Path) {
        $paths = Get-RalphPaths
        $Path = $paths.LogFile
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] $Message"

    try {
        Add-Content -Path $Path -Value $entry -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to write log entry: $_"
    }
}

# Export all public functions
Export-ModuleMember -Function @(
    'Get-RalphPaths'
    'Test-Dependencies'
    'Read-PrdJson'
    'Write-PrdJson'
    'Get-PrdStatus'
    'Write-ColoredOutput'
    'Add-LogEntry'
)
