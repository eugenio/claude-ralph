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
$script:ResolvedPaths = $null

<#
.SYNOPSIS
    Gets paths object with ralph directory locations.

.DESCRIPTION
    Returns a hashtable containing all relevant paths for ralph operations.
    Supports external prd.json files for global usage.

.PARAMETER PrdFile
    Optional path to prd.json file. If specified, instance/lock paths are relative to its location.

.PARAMETER ProjectRoot
    Optional project root directory for git operations. Defaults to prd.json directory if PrdFile specified.

.OUTPUTS
    System.Collections.Hashtable
    A hashtable with the following keys:
    - RalphDir: The ralph scripts directory
    - ProjectRoot: The project root for git operations
    - PrdFile: Path to prd.json
    - PrdDir: Directory containing prd.json
    - ProgressFile: Path to progress.txt
    - PromptFile: Path to prompt.md
    - LogFile: Path to ralph.log
    - ArchiveDir: Path to archive directory
    - LastBranchFile: Path to .last-branch file
    - InstancesDir: Path to instances directory
    - LocksDir: Path to locks directory

.EXAMPLE
    $paths = Get-RalphPaths
    Write-Host "PRD file is at: $($paths.PrdFile)"

.EXAMPLE
    $paths = Get-RalphPaths -PrdFile '/project/docs/prd.json' -ProjectRoot '/project'
    Write-Host "Using external PRD at: $($paths.PrdFile)"
#>
function Get-RalphPaths {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$PrdFile,

        [Parameter()]
        [string]$ProjectRoot
    )

    # Return cached paths if available and no new parameters specified
    if (-not $PrdFile -and -not $ProjectRoot -and $script:ResolvedPaths) {
        return $script:ResolvedPaths
    }

    $ralphDir = $script:RalphRoot

    # Determine PRD file and its directory
    if ($PrdFile -and (Test-Path $PrdFile)) {
        $prdFilePath = Resolve-Path -Path $PrdFile | Select-Object -ExpandProperty Path
        $prdDir = Split-Path -Path $prdFilePath -Parent
    }
    elseif ($PrdFile) {
        # Path specified but doesn't exist - use it anyway (may be created later)
        $prdFilePath = $PrdFile
        $prdDir = Split-Path -Path $PrdFile -Parent
        if (-not $prdDir) { $prdDir = $ralphDir }
    }
    else {
        $prdFilePath = Join-Path $ralphDir 'prd.json'
        $prdDir = $ralphDir
    }

    # Determine project root
    if ($ProjectRoot -and (Test-Path $ProjectRoot)) {
        $projectRootPath = Resolve-Path -Path $ProjectRoot | Select-Object -ExpandProperty Path
    }
    elseif ($ProjectRoot) {
        $projectRootPath = $ProjectRoot
    }
    elseif ($env:RALPH_PROJECT_ROOT) {
        $projectRootPath = $env:RALPH_PROJECT_ROOT
    }
    elseif ($PrdFile) {
        # Default to prd.json directory when -PrdFile is specified
        $projectRootPath = $prdDir
    }
    else {
        $projectRootPath = Split-Path -Path (Split-Path -Path $ralphDir -Parent) -Parent
    }

    $paths = @{
        RalphDir       = $ralphDir
        ProjectRoot    = $projectRootPath
        PrdFile        = $prdFilePath
        PrdDir         = $prdDir
        ProgressFile   = Join-Path $prdDir 'progress.txt'
        PromptFile     = Join-Path $ralphDir 'prompt.md'
        LogFile        = Join-Path $prdDir 'ralph.log'
        ArchiveDir     = Join-Path $prdDir 'archive'
        LastBranchFile = Join-Path $prdDir '.last-branch'
        InstancesDir   = Join-Path $prdDir 'instances'
        LocksDir       = Join-Path $prdDir 'locks'
    }

    # Store resolved paths for subsequent calls without parameters
    if ($PrdFile -or $ProjectRoot) {
        $script:ResolvedPaths = $paths
    }

    return $paths
}

<#
.SYNOPSIS
    Clears cached resolved paths.

.DESCRIPTION
    Resets the module's cached paths, forcing the next Get-RalphPaths call
    to recalculate paths. Useful for testing.
#>
function Reset-RalphPaths {
    [CmdletBinding()]
    param()
    $script:ResolvedPaths = $null
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

# =============================================================================
# MULTI-INSTANCE FUNCTIONS
# =============================================================================

# Script-level instance variables (set once per session)
$script:InstanceId = $null
$script:InstanceShortId = $null

<#
.SYNOPSIS
    Generates a unique instance ID for this Ralph session.

.DESCRIPTION
    Creates a unique identifier in the format: {username}-{hostname}-{pid}-{timestamp}
    This ID is generated once per session and cached for subsequent calls.

.PARAMETER Force
    If specified, regenerates the instance ID even if already cached.

.OUTPUTS
    System.String
    The unique instance ID.

.EXAMPLE
    $id = Get-RalphInstanceId
    Write-Host "Instance: $id"
#>
function Get-RalphInstanceId {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [switch]$Force
    )

    if ($script:InstanceId -and -not $Force) {
        return $script:InstanceId
    }

    $user = $env:USERNAME ?? $env:USER ?? 'unknown'
    $hostname = $env:COMPUTERNAME ?? (hostname) ?? 'local'
    # Clean hostname of special characters
    $hostname = $hostname -replace '[^a-zA-Z0-9_-]', ''
    $pid = $PID
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    $script:InstanceId = "$user-$hostname-$pid-$timestamp"
    $script:InstanceShortId = $script:InstanceId.Substring(0, [Math]::Min(8, $script:InstanceId.Length))

    return $script:InstanceId
}

<#
.SYNOPSIS
    Gets the short (8-character) instance ID.

.DESCRIPTION
    Returns the first 8 characters of the instance ID for display purposes.
    Calls Get-RalphInstanceId if not already initialized.

.OUTPUTS
    System.String
    The short instance ID (8 characters).

.EXAMPLE
    $shortId = Get-RalphShortId
    Write-Host "[$shortId] Starting..."
#>
function Get-RalphShortId {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not $script:InstanceShortId) {
        $null = Get-RalphInstanceId
    }

    return $script:InstanceShortId
}

<#
.SYNOPSIS
    Creates the instance-specific directory structure.

.DESCRIPTION
    Creates the instances/{instance-id}/ directory with initial log and progress files.
    Also creates the locks/ directory if it doesn't exist.

.PARAMETER InstanceId
    Optional instance ID. If not specified, uses Get-RalphInstanceId.

.OUTPUTS
    System.Collections.Hashtable
    A hashtable with instance-specific paths:
    - InstanceDir: The instance directory path
    - LogFile: Instance-specific log file
    - ProgressFile: Instance-specific progress file
    - StatusFile: Instance-specific status.json

.EXAMPLE
    $instancePaths = New-RalphInstanceDirectory
    Write-Host "Logs at: $($instancePaths.LogFile)"
#>
function New-RalphInstanceDirectory {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$InstanceId
    )

    if (-not $InstanceId) {
        $InstanceId = Get-RalphInstanceId
    }

    $paths = Get-RalphPaths
    $instancesDir = Join-Path $paths.RalphDir 'instances'
    $instanceDir = Join-Path $instancesDir $InstanceId
    $locksDir = Join-Path $paths.RalphDir 'locks'

    # Create directories
    if (-not (Test-Path $instanceDir)) {
        New-Item -Path $instanceDir -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path $locksDir)) {
        New-Item -Path $locksDir -ItemType Directory -Force | Out-Null
    }

    $instancePaths = @{
        InstanceDir  = $instanceDir
        LogFile      = Join-Path $instanceDir 'ralph.log'
        ProgressFile = Join-Path $instanceDir 'progress.txt'
        StatusFile   = Join-Path $instanceDir 'status.json'
    }

    # Initialize log file
    $logHeader = @"
# Ralph Instance Log
# Instance ID: $InstanceId
# Short ID: $(Get-RalphShortId)
# Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Project: $($paths.ProjectRoot)
---
"@
    Set-Content -Path $instancePaths.LogFile -Value $logHeader -Force

    # Initialize progress file
    $progressContent = @"
# Ralph Progress Log
Instance: $InstanceId
Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## Codebase Patterns
(Patterns discovered during implementation will be added here)

---
"@
    Set-Content -Path $instancePaths.ProgressFile -Value $progressContent -Force

    # Initialize status
    Update-RalphStatus -State 'starting' -InstancePaths $instancePaths

    return $instancePaths
}

<#
.SYNOPSIS
    Updates the instance status.json file atomically.

.DESCRIPTION
    Writes the current instance status to status.json using atomic write
    (write to temp file, then rename). Includes heartbeat timestamp.

.PARAMETER State
    Current state: starting, idle, claiming, working, merging, completed, terminated, max_iterations

.PARAMETER CurrentStory
    Optional story ID currently being worked on.

.PARAMETER Iteration
    Optional current iteration number.

.PARAMETER MaxIterations
    Optional maximum iterations configured.

.PARAMETER Branch
    Optional current git branch name.

.PARAMETER InstancePaths
    Optional hashtable with instance paths. If not provided, uses default location.

.EXAMPLE
    Update-RalphStatus -State 'working' -CurrentStory 'US-001' -Iteration 3

.EXAMPLE
    Update-RalphStatus -State 'terminated'
#>
function Update-RalphStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('starting', 'idle', 'claiming', 'working', 'merging', 'completed', 'terminated', 'max_iterations')]
        [string]$State,

        [Parameter()]
        [string]$CurrentStory = '',

        [Parameter()]
        [int]$Iteration = 0,

        [Parameter()]
        [int]$MaxIterations = 10,

        [Parameter()]
        [string]$Branch = '',

        [Parameter()]
        [hashtable]$InstancePaths
    )

    $instanceId = Get-RalphInstanceId
    $shortId = Get-RalphShortId

    if (-not $InstancePaths) {
        $paths = Get-RalphPaths
        $instanceDir = Join-Path (Join-Path $paths.RalphDir 'instances') $instanceId
        $InstancePaths = @{
            StatusFile = Join-Path $instanceDir 'status.json'
        }
    }

    $now = Get-Date
    $epochNow = [DateTimeOffset]::new($now).ToUnixTimeSeconds()

    $status = @{
        instanceId         = $instanceId
        shortId            = $shortId
        state              = $State
        currentStory       = $CurrentStory
        iteration          = $Iteration
        maxIterations      = $MaxIterations
        startTime          = $now.ToString('yyyy-MM-dd HH:mm:ss')
        lastHeartbeat      = $now.ToString('yyyy-MM-dd HH:mm:ss')
        lastHeartbeatEpoch = $epochNow
        projectRoot        = (Get-RalphPaths).ProjectRoot
        branch             = $Branch
        pid                = $PID
    }

    $json = $status | ConvertTo-Json -Depth 5

    # Atomic write: write to temp file, then rename
    $tempFile = "$($InstancePaths.StatusFile).tmp"
    try {
        Set-Content -Path $tempFile -Value $json -Force -ErrorAction Stop
        Move-Item -Path $tempFile -Destination $InstancePaths.StatusFile -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to update status: $_"
        if (Test-Path $tempFile) {
            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    # Re-register in global registry if symlink was removed (GM-004)
    $null = Ensure-RalphGlobalRegistration
}

<#
.SYNOPSIS
    Gets the status of a Ralph instance.

.DESCRIPTION
    Reads and returns the status.json for a specific instance.

.PARAMETER InstanceId
    The instance ID to get status for.

.OUTPUTS
    System.Management.Automation.PSObject
    The status object, or $null if not found.

.EXAMPLE
    $status = Get-RalphInstanceStatus -InstanceId 'user-host-1234-1700000000'
    Write-Host "State: $($status.state)"
#>
function Get-RalphInstanceStatus {
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory)]
        [string]$InstanceId
    )

    $paths = Get-RalphPaths
    $statusFile = Join-Path (Join-Path (Join-Path $paths.RalphDir 'instances') $InstanceId) 'status.json'

    if (-not (Test-Path $statusFile)) {
        return $null
    }

    try {
        $content = Get-Content -Path $statusFile -Raw -ErrorAction Stop
        return $content | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to read instance status: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Gets all Ralph instances.

.DESCRIPTION
    Returns a list of all instance directories with their status.

.PARAMETER IncludeDead
    If specified, includes instances that appear to be dead (no heartbeat > 5 min).

.OUTPUTS
    System.Array
    Array of instance status objects with additional 'isDead' property.

.EXAMPLE
    $instances = Get-RalphInstances
    $instances | ForEach-Object { Write-Host "$($_.instanceId): $($_.state)" }
#>
function Get-RalphInstances {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [switch]$IncludeDead
    )

    $paths = Get-RalphPaths
    $instancesDir = Join-Path $paths.RalphDir 'instances'

    if (-not (Test-Path $instancesDir)) {
        return @()
    }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $deadThreshold = 300  # 5 minutes

    $instances = @()
    Get-ChildItem -Path $instancesDir -Directory | ForEach-Object {
        $statusFile = Join-Path $_.FullName 'status.json'
        if (Test-Path $statusFile) {
            try {
                $status = Get-Content -Path $statusFile -Raw | ConvertFrom-Json
                $heartbeatAge = $now - $status.lastHeartbeatEpoch
                $isDead = ($heartbeatAge -gt $deadThreshold) -and ($status.state -notin @('terminated', 'completed'))

                $status | Add-Member -NotePropertyName 'isDead' -NotePropertyValue $isDead -Force
                $status | Add-Member -NotePropertyName 'heartbeatAge' -NotePropertyValue $heartbeatAge -Force

                if ($IncludeDead -or -not $isDead) {
                    $instances += $status
                }
            }
            catch {
                Write-Warning "Failed to read status for $($_.Name): $_"
            }
        }
    }

    return $instances
}

<#
.SYNOPSIS
    Gets all Ralph instances from the global registry across all projects.

.DESCRIPTION
    Reads instance status from the global registry (~/.ralph/global/instances)
    which contains symlinks to instances in different project directories.
    This allows dashboards to show instances from all projects.

.PARAMETER IncludeDead
    Include instances that appear dead (no heartbeat > 5 min).

.OUTPUTS
    Array of instance status objects with projectName property added.

.EXAMPLE
    Get-RalphGlobalInstances -IncludeDead
#>
function Get-RalphGlobalInstances {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [switch]$IncludeDead
    )

    $globalDir = Get-RalphGlobalDir
    $instancesDir = Join-Path $globalDir 'instances'

    if (-not (Test-Path $instancesDir)) {
        return @()
    }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $deadThreshold = 300  # 5 minutes

    $instances = @()
    Get-ChildItem -Path $instancesDir | ForEach-Object {
        $link = $_
        $instanceDir = $null

        # Handle both SymbolicLink (Unix) and Junction (Windows)
        if ($link.LinkType -in @('SymbolicLink', 'Junction')) {
            $instanceDir = $link.Target
        }
        elseif ($link.PSIsContainer) {
            $instanceDir = $link.FullName
        }

        if ($instanceDir -and (Test-Path $instanceDir)) {
            $statusFile = Join-Path $instanceDir 'status.json'
            if (Test-Path $statusFile) {
                try {
                    $status = Get-Content -Path $statusFile -Raw | ConvertFrom-Json
                    $heartbeatAge = $now - $status.lastHeartbeatEpoch
                    $isDead = ($heartbeatAge -gt $deadThreshold) -and ($status.state -notin @('terminated', 'completed'))

                    # Extract project name from link name (format: project-name-uge-...)
                    $linkName = $link.Name
                    $projectName = $linkName -replace '-uge-.*$', ''

                    $status | Add-Member -NotePropertyName 'isDead' -NotePropertyValue $isDead -Force
                    $status | Add-Member -NotePropertyName 'heartbeatAge' -NotePropertyValue $heartbeatAge -Force
                    $status | Add-Member -NotePropertyName 'projectName' -NotePropertyValue $projectName -Force

                    if ($IncludeDead -or -not $isDead) {
                        $instances += $status
                    }
                }
                catch {
                    Write-Warning "Failed to read status for $($link.Name): $_"
                }
            }
        }
    }

    # Sort by lastHeartbeatEpoch descending (most recent first)
    return $instances | Sort-Object -Property lastHeartbeatEpoch -Descending
}

<#
.SYNOPSIS
    Adds a log entry to the instance-specific log file.

.DESCRIPTION
    Appends a timestamped log entry with instance short ID prefix.

.PARAMETER Message
    The message to log.

.PARAMETER InstancePaths
    Optional hashtable with instance paths.

.EXAMPLE
    Add-RalphInstanceLog -Message "Starting iteration 1"
#>
function Add-RalphInstanceLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [Parameter()]
        [hashtable]$InstancePaths
    )

    $shortId = Get-RalphShortId
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$shortId] $Message"

    if (-not $InstancePaths) {
        $instanceId = Get-RalphInstanceId
        $paths = Get-RalphPaths
        $logFile = Join-Path (Join-Path (Join-Path $paths.RalphDir 'instances') $instanceId) 'ralph.log'
    }
    else {
        $logFile = $InstancePaths.LogFile
    }

    try {
        Add-Content -Path $logFile -Value $entry -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to write instance log: $_"
    }

    # Also output to console
    Write-Host $entry
}

# =============================================================================
# STORY LOCKING FUNCTIONS (PS-002)
# =============================================================================

<#
.SYNOPSIS
    Acquires a lock on a story for exclusive access.

.DESCRIPTION
    Uses atomic directory creation to acquire a lock. If the directory
    can be created, the lock is acquired. The lock contains owner ID
    and timestamp files.

.PARAMETER StoryId
    The story ID to lock (e.g., 'US-001').

.OUTPUTS
    System.Boolean
    Returns $true if lock acquired, $false if already locked.

.EXAMPLE
    if (Lock-RalphStory -StoryId 'US-001') {
        Write-Host "Lock acquired!"
    }
#>
function Lock-RalphStory {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$StoryId
    )

    # First cleanup any stale locks
    $null = Clear-RalphStaleLock -StoryId $StoryId

    $paths = Get-RalphPaths
    $lockDir = Join-Path (Join-Path $paths.RalphDir 'locks') "$StoryId.lock"

    try {
        # Atomic directory creation - fails if exists
        New-Item -Path $lockDir -ItemType Directory -ErrorAction Stop | Out-Null

        # Write owner and timestamp
        $instanceId = Get-RalphInstanceId
        Set-Content -Path (Join-Path $lockDir 'owner.txt') -Value $instanceId -Force
        Set-Content -Path (Join-Path $lockDir 'timestamp.txt') -Value ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -Force
        Set-Content -Path (Join-Path $lockDir 'pid.txt') -Value $PID -Force

        Add-RalphInstanceLog "Acquired lock for $StoryId"
        return $true
    }
    catch {
        # Directory already exists = lock held by someone else
        return $false
    }
}

<#
.SYNOPSIS
    Releases a lock on a story.

.DESCRIPTION
    Removes the lock directory if owned by this instance.

.PARAMETER StoryId
    The story ID to unlock.

.PARAMETER Force
    If specified, releases the lock even if owned by another instance.

.OUTPUTS
    System.Boolean
    Returns $true if lock released, $false otherwise.

.EXAMPLE
    Unlock-RalphStory -StoryId 'US-001'
#>
function Unlock-RalphStory {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$StoryId,

        [Parameter()]
        [switch]$Force
    )

    $paths = Get-RalphPaths
    $lockDir = Join-Path (Join-Path $paths.RalphDir 'locks') "$StoryId.lock"

    if (-not (Test-Path $lockDir)) {
        return $true  # Already unlocked
    }

    $ownerFile = Join-Path $lockDir 'owner.txt'
    $owner = if (Test-Path $ownerFile) { Get-Content $ownerFile -Raw } else { '' }
    $owner = $owner.Trim()

    $instanceId = Get-RalphInstanceId

    if ($Force -or $owner -eq $instanceId) {
        try {
            Remove-Item -Path $lockDir -Recurse -Force -ErrorAction Stop
            Add-RalphInstanceLog "Released lock for $StoryId"
            return $true
        }
        catch {
            Write-Warning "Failed to release lock for $StoryId`: $_"
            return $false
        }
    }
    else {
        Write-Warning "Cannot release lock for $StoryId - owned by $owner"
        return $false
    }
}

<#
.SYNOPSIS
    Tests if a story is currently locked.

.DESCRIPTION
    Checks if the lock directory exists for a story.

.PARAMETER StoryId
    The story ID to check.

.OUTPUTS
    System.Boolean
    Returns $true if locked, $false if available.

.EXAMPLE
    if (Test-RalphStoryLocked -StoryId 'US-001') {
        Write-Host "Story is locked"
    }
#>
function Test-RalphStoryLocked {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$StoryId
    )

    $paths = Get-RalphPaths
    $lockDir = Join-Path (Join-Path $paths.RalphDir 'locks') "$StoryId.lock"

    return Test-Path $lockDir
}

<#
.SYNOPSIS
    Gets information about a story lock.

.DESCRIPTION
    Returns details about who holds a lock and when it was acquired.

.PARAMETER StoryId
    The story ID to check.

.OUTPUTS
    System.Collections.Hashtable or $null
    Lock information including owner, timestamp, age, and isDead status.

.EXAMPLE
    $lock = Get-RalphStoryLock -StoryId 'US-001'
    if ($lock) { Write-Host "Locked by: $($lock.Owner)" }
#>
function Get-RalphStoryLock {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$StoryId
    )

    $paths = Get-RalphPaths
    $lockDir = Join-Path (Join-Path $paths.RalphDir 'locks') "$StoryId.lock"

    if (-not (Test-Path $lockDir)) {
        return $null
    }

    # Read with .txt extension (new format) or without (legacy format)
    $ownerFile = Join-Path $lockDir 'owner.txt'
    $ownerFileLegacy = Join-Path $lockDir 'owner'
    $timestampFile = Join-Path $lockDir 'timestamp.txt'
    $timestampFileLegacy = Join-Path $lockDir 'timestamp'

    $owner = 'unknown'
    if (Test-Path $ownerFile) {
        $owner = (Get-Content $ownerFile -Raw).Trim()
    } elseif (Test-Path $ownerFileLegacy) {
        $owner = (Get-Content $ownerFileLegacy -Raw).Trim()
    }

    $timestamp = 0
    if (Test-Path $timestampFile) {
        $timestamp = [long](Get-Content $timestampFile -Raw).Trim()
    } elseif (Test-Path $timestampFileLegacy) {
        $timestamp = [long](Get-Content $timestampFileLegacy -Raw).Trim()
    }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $age = $now - $timestamp

    # Check if owner is dead
    $isDead = $false
    $ownerStatus = Get-RalphInstanceStatus -InstanceId $owner
    if ($ownerStatus) {
        $heartbeatAge = $now - $ownerStatus.lastHeartbeatEpoch
        $isDead = ($heartbeatAge -gt 300) -and ($ownerStatus.state -notin @('terminated', 'completed'))
    }

    return @{
        StoryId   = $StoryId
        Owner     = $owner
        Timestamp = $timestamp
        Age       = $age
        IsDead    = $isDead
        IsStale   = ($age -gt 7200)  # 2 hours
    }
}

<#
.SYNOPSIS
    Gets all current story locks.

.DESCRIPTION
    Returns information about all active locks.

.OUTPUTS
    System.Array
    Array of lock information hashtables.

.EXAMPLE
    Get-RalphStoryLocks | ForEach-Object { Write-Host "$($_.StoryId): $($_.Owner)" }
#>
function Get-RalphStoryLocks {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    $paths = Get-RalphPaths
    $locksDir = Join-Path $paths.RalphDir 'locks'

    if (-not (Test-Path $locksDir)) {
        return @()
    }

    $locks = @()
    Get-ChildItem -Path $locksDir -Directory -Filter '*.lock' | ForEach-Object {
        $storyId = $_.Name -replace '\.lock$', ''
        $lockInfo = Get-RalphStoryLock -StoryId $storyId
        if ($lockInfo) {
            $locks += $lockInfo
        }
    }

    return $locks
}

<#
.SYNOPSIS
    Clears a stale lock for a specific story.

.DESCRIPTION
    Checks if a lock is stale (>2 hours) or owner is dead, and removes it.

.PARAMETER StoryId
    The story ID to check.

.OUTPUTS
    System.Boolean
    Returns $true if lock was cleared, $false if lock is valid or doesn't exist.

.EXAMPLE
    Clear-RalphStaleLock -StoryId 'US-001'
#>
function Clear-RalphStaleLock {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$StoryId
    )

    $lock = Get-RalphStoryLock -StoryId $StoryId
    if (-not $lock) {
        return $false
    }

    $staleTimeout = [int]($env:RALPH_LOCK_TIMEOUT ?? 7200)  # 2 hours default

    if ($lock.Age -gt $staleTimeout -or $lock.IsDead) {
        $reason = if ($lock.IsDead) { "dead owner" } else { "stale ($($lock.Age)s)" }
        Add-RalphInstanceLog "Clearing $reason lock for $StoryId (owner: $($lock.Owner))"
        return Unlock-RalphStory -StoryId $StoryId -Force
    }

    return $false
}

<#
.SYNOPSIS
    Clears all stale locks.

.DESCRIPTION
    Finds and removes all locks that are stale or have dead owners.

.OUTPUTS
    System.Int32
    Number of locks cleared.

.EXAMPLE
    $count = Clear-RalphStaleLocks
    Write-Host "Cleared $count stale locks"
#>
function Clear-RalphStaleLocks {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    $cleared = 0
    Get-RalphStoryLocks | ForEach-Object {
        if (Clear-RalphStaleLock -StoryId $_.StoryId) {
            $cleared++
        }
    }

    return $cleared
}

<#
.SYNOPSIS
    Releases all locks held by this instance.

.DESCRIPTION
    Finds and releases all locks owned by the current instance.

.OUTPUTS
    System.Int32
    Number of locks released.

.EXAMPLE
    $count = Clear-RalphInstanceLocks
    Write-Host "Released $count locks"
#>
function Clear-RalphInstanceLocks {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    $instanceId = Get-RalphInstanceId
    $released = 0

    Get-RalphStoryLocks | Where-Object { $_.Owner -eq $instanceId } | ForEach-Object {
        if (Unlock-RalphStory -StoryId $_.StoryId) {
            $released++
        }
    }

    return $released
}

# =============================================================================
# PRD ATOMIC OPERATIONS (PS-003)
# =============================================================================

# Named mutex for cross-process PRD locking
$script:PrdMutexName = 'Global\RalphPrdLock'

<#
.SYNOPSIS
    Reads the PRD file with shared access.

.DESCRIPTION
    Reads prd.json using a brief lock to ensure consistency.

.OUTPUTS
    System.Management.Automation.PSObject
    The PRD object.

.EXAMPLE
    $prd = Read-RalphPrdSafe
#>
function Read-RalphPrdSafe {
    [CmdletBinding()]
    [OutputType([PSObject])]
    param()

    $paths = Get-RalphPaths

    # Brief lock just for reading
    $mutex = New-Object System.Threading.Mutex($false, $script:PrdMutexName)
    $acquired = $false

    try {
        $acquired = $mutex.WaitOne(5000)  # 5 second timeout
        if (-not $acquired) {
            Write-Warning "Timeout waiting for PRD read lock"
            return $null
        }

        return Read-PrdJson
    }
    finally {
        if ($acquired) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

<#
.SYNOPSIS
    Updates the PRD file atomically.

.DESCRIPTION
    Acquires exclusive lock, reads current PRD, applies update script block,
    validates JSON, backs up, and writes. Retries on lock timeout.

.PARAMETER UpdateScript
    A script block that receives the PRD object and modifies it.
    Return $true to proceed with save, $false to abort.

.PARAMETER Description
    Optional description of the update for logging.

.PARAMETER MaxRetries
    Maximum retry attempts for lock acquisition. Default 3.

.OUTPUTS
    System.Boolean
    Returns $true if update succeeded, $false otherwise.

.EXAMPLE
    Update-RalphPrd -Description "Mark US-001 complete" -UpdateScript {
        param($prd)
        $story = $prd.userStories | Where-Object { $_.id -eq 'US-001' }
        $story.passes = $true
        return $true
    }
#>
function Update-RalphPrd {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$UpdateScript,

        [Parameter()]
        [string]$Description = 'PRD update',

        [Parameter()]
        [int]$MaxRetries = 3
    )

    $paths = Get-RalphPaths
    $prdFile = $paths.PrdFile
    $backupFile = "$prdFile.bak"

    $mutex = New-Object System.Threading.Mutex($false, $script:PrdMutexName)
    $retry = 0

    while ($retry -lt $MaxRetries) {
        $acquired = $false
        try {
            $acquired = $mutex.WaitOne(5000)  # 5 second timeout
            if (-not $acquired) {
                $retry++
                Add-RalphInstanceLog "PRD lock timeout, retry $retry/$MaxRetries"
                Start-Sleep -Seconds 1
                continue
            }

            # Read current PRD
            $prd = Read-PrdJson
            if (-not $prd) {
                Write-Warning "Failed to read PRD"
                return $false
            }

            # Apply update
            $proceed = & $UpdateScript $prd
            if (-not $proceed) {
                return $false
            }

            # Backup before write
            if (Test-Path $prdFile) {
                Copy-Item -Path $prdFile -Destination $backupFile -Force
            }

            # Write to temp file first
            $tempFile = "$prdFile.tmp"
            $json = $prd | ConvertTo-Json -Depth 10
            Set-Content -Path $tempFile -Value $json -Force -ErrorAction Stop

            # Validate JSON
            try {
                $null = Get-Content $tempFile -Raw | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                Write-Warning "PRD update produced invalid JSON: $_"
                Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
                return $false
            }

            # Atomic rename
            Move-Item -Path $tempFile -Destination $prdFile -Force -ErrorAction Stop

            Add-RalphInstanceLog "PRD updated: $Description"
            return $true
        }
        catch {
            Write-Warning "PRD update failed: $_"
            return $false
        }
        finally {
            if ($acquired) {
                $mutex.ReleaseMutex()
            }
        }
    }

    $mutex.Dispose()
    Write-Warning "Failed to acquire PRD lock after $MaxRetries retries"
    return $false
}

# =============================================================================
# STORY CLAIMING FUNCTIONS (PS-004)
# =============================================================================

<#
.SYNOPSIS
    Gets the next unclaimed story by priority.

.DESCRIPTION
    Finds the highest priority story that is incomplete and not claimed
    by another instance.

.OUTPUTS
    System.Management.Automation.PSObject or $null
    The next available story object, or $null if none available.

.EXAMPLE
    $story = Get-RalphNextStory
    if ($story) { Write-Host "Next: $($story.id) - $($story.title)" }
#>
function Get-RalphNextStory {
    [CmdletBinding()]
    [OutputType([PSObject])]
    param()

    $prd = Read-RalphPrdSafe
    if (-not $prd -or -not $prd.userStories) {
        return $null
    }

    # Get incomplete, unclaimed stories sorted by priority
    $available = $prd.userStories |
        Where-Object { $_.passes -eq $false } |
        Where-Object { -not $_.claimedBy -or $_.claimedBy -eq '' } |
        Sort-Object priority

    foreach ($story in $available) {
        # Check if locked
        if (-not (Test-RalphStoryLocked -StoryId $story.id)) {
            return $story
        }
    }

    return $null
}

<#
.SYNOPSIS
    Claims a story for exclusive work.

.DESCRIPTION
    Acquires lock and updates PRD with claimedBy field.

.PARAMETER StoryId
    The story ID to claim.

.OUTPUTS
    System.Boolean
    Returns $true if claim succeeded, $false otherwise.

.EXAMPLE
    if (Request-RalphStoryClaim -StoryId 'US-001') {
        Write-Host "Claimed US-001!"
    }
#>
function Request-RalphStoryClaim {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$StoryId
    )

    # Try to acquire lock
    if (-not (Lock-RalphStory -StoryId $StoryId)) {
        return $false
    }

    # Update PRD with claim
    $instanceId = Get-RalphInstanceId
    $result = Update-RalphPrd -Description "Claim $StoryId" -UpdateScript {
        param($prd)
        $story = $prd.userStories | Where-Object { $_.id -eq $StoryId }
        if ($story) {
            $story | Add-Member -NotePropertyName 'claimedBy' -NotePropertyValue $instanceId -Force
            return $true
        }
        return $false
    }

    if (-not $result) {
        # Failed to update PRD, release lock
        Unlock-RalphStory -StoryId $StoryId
        return $false
    }

    Add-RalphInstanceLog "Claimed story: $StoryId"
    return $true
}

<#
.SYNOPSIS
    Removes a story claim.

.DESCRIPTION
    Removes lock and clears claimedBy in PRD.

.PARAMETER StoryId
    The story ID to release.

.OUTPUTS
    System.Boolean
    Returns $true if removal succeeded.

.EXAMPLE
    Remove-RalphStoryClaim -StoryId 'US-001'
#>
function Remove-RalphStoryClaim {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$StoryId
    )

    # Release lock
    $null = Unlock-RalphStory -StoryId $StoryId

    # Clear claimedBy in PRD
    $null = Update-RalphPrd -Description "Release $StoryId" -UpdateScript {
        param($prd)
        $story = $prd.userStories | Where-Object { $_.id -eq $StoryId }
        if ($story -and $story.claimedBy) {
            $story.claimedBy = $null
        }
        return $true
    }

    Add-RalphInstanceLog "Released claim on $StoryId"
    return $true
}

<#
.SYNOPSIS
    Claims the next available story.

.DESCRIPTION
    Finds and claims the next available story, with retry logic.

.PARAMETER MaxRetries
    Maximum retry attempts if no stories available. Default 5.

.PARAMETER RetryDelay
    Seconds to wait between retries. Default 30.

.OUTPUTS
    System.Management.Automation.PSObject or $null
    The claimed story object, or $null if none available.

.EXAMPLE
    $story = Request-RalphNextStoryClaim
    if ($story) { Write-Host "Working on: $($story.title)" }
#>
function Request-RalphNextStoryClaim {
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter()]
        [int]$MaxRetries = 5,

        [Parameter()]
        [int]$RetryDelay = 30
    )

    $retry = 0
    while ($retry -lt $MaxRetries) {
        # Clean up any stale locks first
        $null = Clear-RalphStaleLocks

        $story = Get-RalphNextStory
        if ($story) {
            if (Request-RalphStoryClaim -StoryId $story.id) {
                return $story
            }
            # Lock failed, try next story
            continue
        }

        # No stories available
        $retry++
        if ($retry -lt $MaxRetries) {
            Add-RalphInstanceLog "No available stories, waiting ${RetryDelay}s (retry $retry/$MaxRetries)"
            Start-Sleep -Seconds $RetryDelay
        }
    }

    Add-RalphInstanceLog "No stories available after $MaxRetries retries"
    return $null
}

# =============================================================================
# GIT BRANCH FUNCTIONS (PS-005)
# =============================================================================

# Script-level variable for current branch
$script:CurrentStoryBranch = $null

<#
.SYNOPSIS
    Creates a feature branch for a story.

.DESCRIPTION
    Creates a branch named ralph/{short-id}/{story-id} from the base branch
    specified in the PRD.

.PARAMETER StoryId
    The story ID to create branch for.

.OUTPUTS
    System.String
    The name of the created branch, or $null on failure.

.EXAMPLE
    $branch = New-RalphStoryBranch -StoryId 'US-001'
#>
function New-RalphStoryBranch {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$StoryId
    )

    $paths = Get-RalphPaths
    $prd = Read-RalphPrdSafe
    $baseBranch = if ($prd.branchName) { $prd.branchName } else { 'main' }
    $shortId = Get-RalphShortId
    $script:CurrentStoryBranch = "ralph/$shortId/$StoryId"

    try {
        Push-Location $paths.ProjectRoot

        # Fetch latest (suppress all output)
        git fetch origin 2>&1 | Out-Null

        # Try to checkout base branch
        $null = git show-ref --verify --quiet "refs/heads/$baseBranch" 2>&1
        if ($LASTEXITCODE -eq 0) {
            git checkout $baseBranch 2>&1 | Out-Null
            git pull origin $baseBranch 2>&1 | Out-Null
        }
        else {
            # Try remote
            $null = git show-ref --verify --quiet "refs/remotes/origin/$baseBranch" 2>&1
            if ($LASTEXITCODE -eq 0) {
                git checkout -b $baseBranch "origin/$baseBranch" 2>&1 | Out-Null
            }
        }

        # Check if story branch exists
        $null = git show-ref --verify --quiet "refs/heads/$($script:CurrentStoryBranch)" 2>&1
        if ($LASTEXITCODE -eq 0) {
            git checkout $script:CurrentStoryBranch 2>&1 | Out-Null
            Add-RalphInstanceLog "Checked out existing branch: $($script:CurrentStoryBranch)"
        }
        else {
            git checkout -b $script:CurrentStoryBranch 2>&1 | Out-Null
            Add-RalphInstanceLog "Created new branch: $($script:CurrentStoryBranch)"
        }

        return $script:CurrentStoryBranch
    }
    catch {
        Write-Warning "Failed to create story branch: $_"
        return ''
    }
    finally {
        Pop-Location
    }
}

<#
.SYNOPSIS
    Merges a story branch back to the base branch.

.DESCRIPTION
    Merges the story branch with --no-ff and cleans up.

.PARAMETER StoryId
    The story ID whose branch to merge.

.OUTPUTS
    System.Boolean
    Returns $true if merge succeeded.

.EXAMPLE
    Merge-RalphStoryBranch -StoryId 'US-001'
#>
function Merge-RalphStoryBranch {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$StoryId
    )

    if (-not $script:CurrentStoryBranch) {
        return $true
    }

    $paths = Get-RalphPaths
    $prd = Read-RalphPrdSafe
    $baseBranch = if ($prd.branchName) { $prd.branchName } else { 'main' }
    $shortId = Get-RalphShortId

    try {
        Push-Location $paths.ProjectRoot

        # Checkout base branch
        $result = git checkout $baseBranch 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-RalphInstanceLog "WARNING: Could not checkout $baseBranch for merge"
            return $false
        }

        # Pull latest
        git pull origin $baseBranch 2>$null

        # Merge with --no-ff
        $mergeResult = git merge --no-ff $script:CurrentStoryBranch -m "Merge $StoryId from instance $shortId" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-RalphInstanceLog "ERROR: Merge conflict! Manual resolution required."
            git merge --abort 2>$null
            return $false
        }

        Add-RalphInstanceLog "Merged $($script:CurrentStoryBranch) into $baseBranch"

        # Delete the feature branch
        git branch -d $script:CurrentStoryBranch 2>$null
        Add-RalphInstanceLog "Deleted branch: $($script:CurrentStoryBranch)"

        $script:CurrentStoryBranch = $null
        return $true
    }
    catch {
        Write-Warning "Failed to merge story branch: $_"
        return $false
    }
    finally {
        Pop-Location
    }
}

<#
.SYNOPSIS
    Removes a merged story branch.

.DESCRIPTION
    Removes the branch named ralph/{short-id}/{story-id} if it has been merged.
    This is typically called after a successful merge to clean up.

.PARAMETER StoryId
    The story ID whose branch to remove.

.PARAMETER ShortId
    Optional short instance ID. If not provided, uses the current instance's short ID.

.PARAMETER Force
    If specified, deletes the branch even if not merged (uses -D instead of -d).

.OUTPUTS
    System.Boolean
    Returns $true if branch was deleted or didn't exist.

.EXAMPLE
    Remove-RalphStoryBranch -StoryId 'US-001'

.EXAMPLE
    Remove-RalphStoryBranch -StoryId 'US-001' -Force
#>
function Remove-RalphStoryBranch {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$StoryId,

        [Parameter()]
        [string]$ShortId,

        [Parameter()]
        [switch]$Force
    )

    $paths = Get-RalphPaths

    # Use provided ShortId or get current instance's short ID
    if (-not $ShortId) {
        $ShortId = Get-RalphShortId
    }

    $branchName = "ralph/$ShortId/$StoryId"

    try {
        Push-Location $paths.ProjectRoot

        # Check if branch exists
        $null = git show-ref --verify --quiet "refs/heads/$branchName" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-RalphInstanceLog "Branch does not exist: $branchName"
            return $true
        }

        # Delete the branch
        if ($Force) {
            git branch -D $branchName 2>&1 | Out-Null
        }
        else {
            git branch -d $branchName 2>&1 | Out-Null
        }

        if ($LASTEXITCODE -eq 0) {
            Add-RalphInstanceLog "Deleted branch: $branchName"

            # Clear script-level variable if it was our branch
            if ($script:CurrentStoryBranch -eq $branchName) {
                $script:CurrentStoryBranch = $null
            }
            return $true
        }
        else {
            if (-not $Force) {
                Add-RalphInstanceLog "WARNING: Could not delete branch $branchName (not merged?). Use -Force to force delete."
            }
            else {
                Add-RalphInstanceLog "ERROR: Could not delete branch $branchName"
            }
            return $false
        }
    }
    catch {
        Write-Warning "Failed to remove story branch: $_"
        return $false
    }
    finally {
        Pop-Location
    }
}

<#
.SYNOPSIS
    Gets the current story branch name.

.OUTPUTS
    System.String
    The current story branch name, or $null.

.EXAMPLE
    $branch = Get-RalphCurrentBranch
#>
function Get-RalphCurrentBranch {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return $script:CurrentStoryBranch
}

<#
.SYNOPSIS
    Cleans up merged story branches.

.DESCRIPTION
    Removes local branches matching ralph/*/* pattern that have been merged.

.OUTPUTS
    System.Int32
    Number of branches cleaned up.

.EXAMPLE
    $count = Clear-RalphMergedBranches
#>
function Clear-RalphMergedBranches {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    $paths = Get-RalphPaths
    $cleaned = 0

    try {
        Push-Location $paths.ProjectRoot

        # Get merged branches matching ralph pattern
        $branches = git branch --merged | Where-Object { $_ -match 'ralph/[^/]+/[^/]+' }

        foreach ($branch in $branches) {
            $branchName = $branch.Trim().TrimStart('* ')
            if ($branchName -ne (git rev-parse --abbrev-ref HEAD)) {
                git branch -d $branchName 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $cleaned++
                    Add-RalphInstanceLog "Cleaned up merged branch: $branchName"
                }
            }
        }

        return $cleaned
    }
    catch {
        Write-Warning "Failed to clean merged branches: $_"
        return 0
    }
    finally {
        Pop-Location
    }
}

# =============================================================================
# GRACEFUL SHUTDOWN (PS-007)
# =============================================================================

# Script-level cleanup state
$script:CleanupRegistered = $false
$script:CurrentStoryId = $null

<#
.SYNOPSIS
    Registers cleanup handler for graceful shutdown.

.DESCRIPTION
    Sets up handlers to release locks and update status on script termination.

.EXAMPLE
    Register-RalphCleanup
#>
function Register-RalphCleanup {
    [CmdletBinding()]
    param()

    if ($script:CleanupRegistered) {
        return
    }

    # Register for process exit
    $null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        Invoke-RalphCleanup
    } -SupportEvent

    $script:CleanupRegistered = $true
}

<#
.SYNOPSIS
    Performs cleanup on shutdown.

.DESCRIPTION
    Releases locks, updates status, and stashes uncommitted changes.

.EXAMPLE
    Invoke-RalphCleanup
#>
function Invoke-RalphCleanup {
    [CmdletBinding()]
    param()

    Add-RalphInstanceLog "Shutting down instance..."

    # Update status
    try {
        Update-RalphStatus -State 'terminated' -CurrentStory $script:CurrentStoryId
    }
    catch {
        Write-Warning "Failed to update status: $_"
    }

    # Release all locks
    try {
        $released = Clear-RalphInstanceLocks
        Add-RalphInstanceLog "Released $released locks"
    }
    catch {
        Write-Warning "Failed to release locks: $_"
    }

    # Unregister from global registry (PS-004)
    try {
        $null = Unregister-RalphGlobalInstance
    }
    catch {
        Write-Warning "Failed to unregister from global registry: $_"
    }

    # Stash uncommitted changes
    try {
        $paths = Get-RalphPaths
        Push-Location $paths.ProjectRoot

        $hasChanges = git diff --quiet 2>$null
        $hasStagedChanges = git diff --cached --quiet 2>$null

        if ($LASTEXITCODE -ne 0) {
            $shortId = Get-RalphShortId
            git stash push -m "Ralph instance $shortId shutdown stash" 2>$null
            Add-RalphInstanceLog "Stashed uncommitted changes"
        }
        else {
            Add-RalphInstanceLog "No uncommitted changes"
        }

        Pop-Location
    }
    catch {
        Write-Warning "Failed to stash changes: $_"
    }

    Add-RalphInstanceLog "Cleanup complete. Goodbye!"
}

<#
.SYNOPSIS
    Sets the current story ID for cleanup purposes.

.PARAMETER StoryId
    The story ID being worked on.

.EXAMPLE
    Set-RalphCurrentStory -StoryId 'US-001'
#>
function Set-RalphCurrentStory {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$StoryId
    )

    $script:CurrentStoryId = $StoryId
}

# =============================================================================
# GLOBAL REGISTRY FUNCTIONS (GM-001)
# =============================================================================

function Get-RalphGlobalDir {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if ($env:RALPH_GLOBAL_DIR) { return $env:RALPH_GLOBAL_DIR }
    $h = if ($IsWindows -or $env:OS -eq 'Windows_NT') { $env:USERPROFILE } else { $env:HOME }
    return Join-Path $h '.ralph' 'global'
}

function Initialize-RalphGlobalRegistry {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    if ($env:RALPH_GLOBAL_DISABLE -eq '1') { return $true }
    $globalDir = Get-RalphGlobalDir
    $instancesDir = Join-Path $globalDir 'instances'
    $locksDir = Join-Path $globalDir 'locks'
    try {
        if (-not (Test-Path $instancesDir)) {
            New-Item -Path $instancesDir -ItemType Directory -Force | Out-Null
            if (-not ($IsWindows -or $env:OS -eq 'Windows_NT')) {
                if (Get-Command chmod -ErrorAction SilentlyContinue) {
                    chmod 700 $globalDir 2>$null
                    chmod 700 $instancesDir 2>$null
                }
            }
        }
        if (-not (Test-Path $locksDir)) {
            New-Item -Path $locksDir -ItemType Directory -Force | Out-Null
            if (-not ($IsWindows -or $env:OS -eq 'Windows_NT')) {
                if (Get-Command chmod -ErrorAction SilentlyContinue) {
                    chmod 700 $locksDir 2>$null
                }
            }
        }
        return $true
    }
    catch {
        Write-Warning "Failed to initialize global registry: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Gets the link name for global registry registration.

.DESCRIPTION
    Returns the link name in format: {project-name}-{instance-id}
    This is used to create symlinks/junctions in the global registry.

.OUTPUTS
    System.String
    The link name for the global registry.

.EXAMPLE
    $linkName = Get-RalphGlobalLinkName
    Write-Host "Link name: $linkName"
#>
function Get-RalphGlobalLinkName {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $paths = Get-RalphPaths
    $projectName = Split-Path -Path $paths.ProjectRoot -Leaf
    $instanceId = Get-RalphInstanceId

    return "$projectName-$instanceId"
}

<#
.SYNOPSIS
    Registers this instance in the global registry.

.DESCRIPTION
    Creates a symbolic link (Unix) or directory junction (Windows) in the global
    registry pointing to the local instance directory. This allows the global
    dashboard to discover instances across different projects.

.OUTPUTS
    System.Boolean
    Returns $true if registration succeeded, $false otherwise.

.EXAMPLE
    if (Register-RalphGlobalInstance) {
        Write-Host "Registered in global registry"
    }
#>
function Register-RalphGlobalInstance {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Skip if disabled
    if ($env:RALPH_GLOBAL_DISABLE -eq '1') {
        return $true
    }

    $globalDir = Get-RalphGlobalDir
    $instancesDir = Join-Path $globalDir 'instances'
    $linkName = Get-RalphGlobalLinkName
    $linkPath = Join-Path $instancesDir $linkName

    # Ensure global registry is initialized
    if (-not (Initialize-RalphGlobalRegistry)) {
        return $false
    }

    # Get the local instance directory
    $instanceId = Get-RalphInstanceId
    $paths = Get-RalphPaths
    $instanceDir = Join-Path (Join-Path $paths.RalphDir 'instances') $instanceId

    # Create instance directory if it doesn't exist
    if (-not (Test-Path $instanceDir)) {
        try {
            New-Item -Path $instanceDir -ItemType Directory -Force | Out-Null
        }
        catch {
            Write-Warning "Failed to create instance directory: $_"
            return $false
        }
    }

    # Remove existing link if present (in case of stale link)
    if (Test-Path $linkPath) {
        try {
            Remove-Item -Path $linkPath -Force -Recurse -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to remove existing link: $_"
        }
    }

    # Create link (junction on Windows, symlink on Unix)
    try {
        if ($IsWindows -or $env:OS -eq 'Windows_NT') {
            # Use directory junction on Windows (doesn't require admin)
            New-Item -ItemType Junction -Path $linkPath -Target $instanceDir -Force | Out-Null
        }
        else {
            # Use symbolic link on Unix
            New-Item -ItemType SymbolicLink -Path $linkPath -Target $instanceDir -Force | Out-Null
        }
        Add-RalphInstanceLog "Registered in global registry: $linkName"
        return $true
    }
    catch {
        # Log but don't fail - global registry is optional
        Add-RalphInstanceLog "Warning: Failed to register in global registry: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Unregisters this instance from the global registry.

.DESCRIPTION
    Removes the symbolic link or directory junction from the global registry
    that points to this instance. Called during cleanup/shutdown.

.OUTPUTS
    System.Boolean
    Returns $true if unregistration succeeded or link didn't exist.

.EXAMPLE
    Unregister-RalphGlobalInstance
#>
function Unregister-RalphGlobalInstance {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Skip if disabled
    if ($env:RALPH_GLOBAL_DISABLE -eq '1') {
        return $true
    }

    $globalDir = Get-RalphGlobalDir
    $linkName = Get-RalphGlobalLinkName
    $linkPath = Join-Path (Join-Path $globalDir 'instances') $linkName

    if (Test-Path $linkPath) {
        try {
            Remove-Item -Path $linkPath -Force -Recurse -ErrorAction Stop
            Add-RalphInstanceLog "Unregistered from global registry"
            return $true
        }
        catch {
            Write-Warning "Failed to unregister from global registry: $_"
            return $false
        }
    }

    return $true
}

<#
.SYNOPSIS
    Ensures the instance is registered in the global registry.

.DESCRIPTION
    Re-creates the global symlink if it was removed (by cleanup or manually).
    Called during status updates to maintain global registry consistency.
    Silently re-registers without spamming logs.

.OUTPUTS
    System.Boolean
    Returns $true if registration is valid or was restored.

.EXAMPLE
    Ensure-RalphGlobalRegistration
#>
function Ensure-RalphGlobalRegistration {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Skip if disabled
    if ($env:RALPH_GLOBAL_DISABLE -eq '1') {
        return $true
    }

    $globalDir = Get-RalphGlobalDir
    $instancesDir = Join-Path $globalDir 'instances'
    $linkName = Get-RalphGlobalLinkName
    $linkPath = Join-Path $instancesDir $linkName

    # Get the local instance directory
    $instanceId = Get-RalphInstanceId
    $paths = Get-RalphPaths
    $instanceDir = Join-Path (Join-Path $paths.RalphDir 'instances') $instanceId

    # Only recreate if symlink is missing but instance directory exists
    if (-not (Test-Path $linkPath) -and (Test-Path $instanceDir)) {
        # Ensure directory exists
        if (-not (Test-Path $instancesDir)) {
            try {
                New-Item -Path $instancesDir -ItemType Directory -Force | Out-Null
            }
            catch {
                return $false
            }
        }

        # Create link (junction on Windows, symlink on Unix) - silently
        try {
            if ($IsWindows -or $env:OS -eq 'Windows_NT') {
                New-Item -ItemType Junction -Path $linkPath -Target $instanceDir -Force | Out-Null
            }
            else {
                New-Item -ItemType SymbolicLink -Path $linkPath -Target $instanceDir -Force | Out-Null
            }
            return $true
        }
        catch {
            return $false
        }
    }

    return $true
}

<#
.SYNOPSIS
    Cleans up stale global registry entries.

.DESCRIPTION
    Removes global registry symlinks/junctions that point to:
    - Non-existent instance directories
    - Completed projects (all stories pass)
    - Dead instances with no recent heartbeat

.PARAMETER IncludeCompleted
    If specified, removes entries for fully completed projects.

.OUTPUTS
    System.Int32
    Number of entries cleaned up.

.EXAMPLE
    $count = Clear-RalphGlobalRegistry -IncludeCompleted
    Write-Host "Cleaned $count stale entries"
#>
function Clear-RalphGlobalRegistry {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter()]
        [switch]$IncludeCompleted
    )

    $globalDir = Get-RalphGlobalDir
    $instancesDir = Join-Path $globalDir 'instances'

    if (-not (Test-Path $instancesDir)) {
        return 0
    }

    $cleaned = 0
    Get-ChildItem -Path $instancesDir -ErrorAction SilentlyContinue | ForEach-Object {
        $link = $_
        $shouldRemove = $false
        $reason = ''

        # Check if it's a valid link
        if ($link.LinkType -in @('SymbolicLink', 'Junction')) {
            $target = $link.Target

            # Check if target exists
            if (-not (Test-Path $target)) {
                $shouldRemove = $true
                $reason = 'target missing'
            }
            elseif ($IncludeCompleted) {
                # Extract project root from target path
                $projectRoot = $null
                if ($target -match '^(.+)[/\\]scripts[/\\]ralph[/\\]instances[/\\]') { $projectRoot = $Matches[1] }
                elseif ($target -match '^(.+)[/\\]\.claude[/\\]ralph[/\\]instances[/\\]') { $projectRoot = $Matches[1] }
                elseif ($target -match '^(.+)[/\\]project[/\\]instances[/\\]') { $projectRoot = $Matches[1] }
                elseif ($target -match '^(.+)[/\\]tasks[/\\]instances[/\\]') { $projectRoot = $Matches[1] }
                elseif ($target -match '^(.+)[/\\]instances[/\\]') { $projectRoot = $Matches[1] }

                if ($projectRoot -and (Test-Path $projectRoot)) {
                    $status = Get-ProjectPrdStatus -ProjectRoot $projectRoot
                    if ($status.Total -gt 0 -and $status.Complete -eq $status.Total) {
                        $shouldRemove = $true
                        $reason = 'project completed'
                    }
                }
            }
        }
        else {
            # Not a symlink/junction - might be stale directory
            $statusFile = Join-Path $link.FullName 'status.json'
            if (-not (Test-Path $statusFile)) {
                $shouldRemove = $true
                $reason = 'no status file'
            }
        }

        if ($shouldRemove) {
            try {
                Remove-Item -Path $link.FullName -Force -Recurse -ErrorAction Stop
                Write-Verbose "Removed stale registry entry: $($link.Name) ($reason)"
                $cleaned++
            }
            catch {
                Write-Warning "Failed to remove $($link.Name): $_"
            }
        }
    }

    return $cleaned
}

# =============================================================================
# MULTI-PROJECT DASHBOARD FUNCTIONS
# =============================================================================

<#
.SYNOPSIS
    Gets PRD status for a specific project root path.
#>
function Get-ProjectPrdStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )
    $prdFile = $null
    $standardPath = Join-Path $ProjectRoot 'scripts' 'ralph' 'prd.json'
    $claudePath = Join-Path $ProjectRoot '.claude' 'ralph' 'prd.json'
    $projectPath = Join-Path $ProjectRoot 'project' 'prd.json'
    $tasksPath = Join-Path $ProjectRoot 'tasks' 'prd.json'
    $altPath = Join-Path $ProjectRoot 'prd.json'
    if (Test-Path $standardPath) { $prdFile = $standardPath }
    elseif (Test-Path $claudePath) { $prdFile = $claudePath }
    elseif (Test-Path $projectPath) { $prdFile = $projectPath }
    elseif (Test-Path $tasksPath) { $prdFile = $tasksPath }
    elseif (Test-Path $altPath) { $prdFile = $altPath }
    if (-not $prdFile) { return @{ Total = 0; Complete = 0 } }
    try {
        $prd = Get-Content -Path $prdFile -Raw | ConvertFrom-Json
        $total = @($prd.userStories).Count
        $complete = @($prd.userStories | Where-Object { $_.passes -eq $true }).Count
        return @{ Total = $total; Complete = $complete }
    } catch {
        return @{ Total = 0; Complete = 0 }
    }
}

<#
.SYNOPSIS
    Gets PRD status for all unique projects from global instances.
#>
function Get-AllProjectsPrdStatus {
    [CmdletBinding()]
    [OutputType([array])]
    param()
    $instances = Get-RalphGlobalInstances -IncludeDead
    $projectRoots = @($instances | ForEach-Object { $_.projectRoot } | Where-Object { $_ } | Sort-Object -Unique)

    # Also extract project roots from global registry symlinks (even stale ones)
    $globalDir = if ($env:RALPH_GLOBAL_DIR) { $env:RALPH_GLOBAL_DIR } else { Join-Path $HOME '.ralph' 'global' }
    $instancesDir = Join-Path $globalDir 'instances'
    if (Test-Path $instancesDir) {
        Get-ChildItem -Path $instancesDir -ErrorAction SilentlyContinue | ForEach-Object {
            $target = $null
            # Handle both SymbolicLink (Unix) and Junction (Windows)
            if ($_.LinkType -in @('SymbolicLink', 'Junction')) {
                $target = $_.Target
            }
            if ($target) {
                # Extract project root by removing known instance path suffixes
                $pr = $target
                if ($target -match '^(.+)/scripts/ralph/instances/') { $pr = $Matches[1] }
                elseif ($target -match '^(.+)/\.claude/ralph/instances/') { $pr = $Matches[1] }
                elseif ($target -match '^(.+)/project/instances/') { $pr = $Matches[1] }
                elseif ($target -match '^(.+)/tasks/instances/') { $pr = $Matches[1] }
                elseif ($target -match '^(.+)/instances/') { $pr = $Matches[1] }
                if ($pr -and (Test-Path $pr) -and $pr -notin $projectRoots) {
                    $projectRoots += $pr
                }
            }
        }
    }

    # Include local project
    $localRoot = (Get-RalphPaths).ProjectRoot
    if ($localRoot -and $localRoot -notin $projectRoots) {
        $projectRoots += $localRoot
    }
    $results = @()
    foreach ($pr in $projectRoots) {
        if (-not $pr -or -not (Test-Path $pr)) { continue }
        $name = Split-Path -Path $pr -Leaf
        $status = Get-ProjectPrdStatus -ProjectRoot $pr
        $isComplete = ($status.Total -gt 0) -and ($status.Complete -eq $status.Total)
        $remaining = $status.Total - $status.Complete
        $results += @{
            Name = $name
            Total = $status.Total
            Complete = $status.Complete
            Root = $pr
            IsComplete = $isComplete
            Remaining = $remaining
        }
    }
    # Sort: incomplete projects first (by remaining work desc), then complete projects
    $results = $results | Sort-Object -Property @{Expression={$_.IsComplete}; Ascending=$true}, @{Expression={$_.Remaining}; Descending=$true}
    # Filter out fully completed projects (no remaining work)
    $results = $results | Where-Object { -not $_.IsComplete }
    return $results
}

<#
.SYNOPSIS
    Gets locks from all projects in global registry.
#>
function Get-AllProjectsLocks {
    [CmdletBinding()]
    [OutputType([array])]
    param()
    $instances = Get-RalphGlobalInstances -IncludeDead
    $projectRoots = @($instances | ForEach-Object { $_.projectRoot } | Where-Object { $_ } | Sort-Object -Unique)
    $localRoot = (Get-RalphPaths).ProjectRoot
    if ($localRoot -and $localRoot -notin $projectRoots) {
        $projectRoots += $localRoot
    }
    $results = @()
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    foreach ($pr in $projectRoots) {
        if (-not $pr -or -not (Test-Path $pr)) { continue }
        # Find all possible lock directories for this project
        $locksDirPairs = @()
        $standardLocks = Join-Path $pr 'scripts' 'ralph' 'locks'
        $claudeLocks = Join-Path $pr '.claude' 'ralph' 'locks'
        $ralphLocks = Join-Path $pr 'ralph' 'locks'
        $tasksLocks = Join-Path $pr 'tasks' 'locks'
        $projectLocks = Join-Path $pr 'project' 'locks'
        $rootLocks = Join-Path $pr 'locks'
        if (Test-Path $standardLocks) {
            $locksDirPairs += @{ Locks = $standardLocks; Instances = Join-Path $pr 'scripts' 'ralph' 'instances' }
        }
        if (Test-Path $claudeLocks) {
            $locksDirPairs += @{ Locks = $claudeLocks; Instances = Join-Path $pr '.claude' 'ralph' 'instances' }
        }
        if (Test-Path $ralphLocks) {
            $locksDirPairs += @{ Locks = $ralphLocks; Instances = Join-Path $pr 'ralph' 'instances' }
        }
        if (Test-Path $tasksLocks) {
            $locksDirPairs += @{ Locks = $tasksLocks; Instances = Join-Path $pr 'tasks' 'instances' }
        }
        if (Test-Path $projectLocks) {
            $locksDirPairs += @{ Locks = $projectLocks; Instances = Join-Path $pr 'project' 'instances' }
        }
        if (Test-Path $rootLocks) {
            $locksDirPairs += @{ Locks = $rootLocks; Instances = Join-Path $pr 'instances' }
        }
        if ($locksDirPairs.Count -eq 0) { continue }
        $pname = Split-Path -Path $pr -Leaf
        foreach ($pair in $locksDirPairs) {
            $locksDir = $pair.Locks
            $instancesDir = $pair.Instances
            Get-ChildItem -Path $locksDir -Directory -Filter '*.lock' -ErrorAction SilentlyContinue | ForEach-Object {
            $storyId = $_.Name -replace '\.lock$', ''
            $ownerFile = Join-Path $_.FullName 'owner.txt'
            $ownerFileLegacy = Join-Path $_.FullName 'owner'
            $tsFile = Join-Path $_.FullName 'timestamp.txt'
            $tsFileLegacy = Join-Path $_.FullName 'timestamp'
            $owner = 'unknown'; $ts = 0
            if (Test-Path $ownerFile) { $owner = (Get-Content $ownerFile -Raw).Trim() }
            elseif (Test-Path $ownerFileLegacy) { $owner = (Get-Content $ownerFileLegacy -Raw).Trim() }
            if (Test-Path $tsFile) { $ts = [long](Get-Content $tsFile -Raw).Trim() }
            elseif (Test-Path $tsFileLegacy) { $ts = [long](Get-Content $tsFileLegacy -Raw).Trim() }
            $age = $now - $ts
            $isStale = $age -gt 7200
            # Check if the lock owner instance is dead
            $isDead = $false
            if ($owner -ne 'unknown' -and $instancesDir) {
                $ownerInstanceDir = Join-Path $instancesDir $owner
                $ownerStatusFile = Join-Path $ownerInstanceDir 'status.json'
                if (Test-Path $ownerStatusFile) {
                    try {
                        $ownerStatus = Get-Content $ownerStatusFile -Raw | ConvertFrom-Json
                        $heartbeatAge = $now - $ownerStatus.lastHeartbeatEpoch
                        # Dead if no heartbeat > 5 min and not in terminal state
                        if ($heartbeatAge -gt 300 -and $ownerStatus.state -notin @('terminated', 'completed')) {
                            $isDead = $true
                        }
                    } catch { }
                } else {
                    # Instance directory not found - owner is dead/gone
                    $isDead = $true
                }
            }
            $results += @{
                StoryId = $storyId
                Owner = $owner
                Age = $age
                IsStale = $isStale
                IsDead = $isDead
                Project = $pname
            }
            }
        }
    }
    return $results
}

# =============================================================================
# NOTIFICATION FUNCTIONS
# =============================================================================

function Get-NotificationConfigFile {
    <#
    .SYNOPSIS
    Returns the path to the notification config file
    #>
    $globalDir = Get-RalphGlobalDir
    return Join-Path $globalDir "mcp/notifications.json"
}

function Send-RalphNotification {
    <#
    .SYNOPSIS
    Sends a notification to configured channels
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('rate_limit_detected', 'rate_limit_cleared', 'prd_completed',
                     'story_completed', 'instance_error', 'instance_started',
                     'instance_stopped', 'queue_empty')]
        [string]$Event,
        [Parameter(Mandatory)]
        [string]$Title,
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$InstanceId = "",
        [string]$ProjectRoot = ""
    )

    $configFile = Get-NotificationConfigFile

    if (-not (Test-Path $configFile)) {
        return
    }

    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
    } catch {
        return
    }

    $eventConfig = $config.events.$Event
    if (-not $eventConfig -or -not $eventConfig.enabled -or $eventConfig.channels.Count -eq 0) {
        return
    }

    foreach ($channelName in $eventConfig.channels) {
        $channel = $config.channels.$channelName
        if (-not $channel -or -not $channel.enabled) {
            continue
        }

        $payload = switch ($channel.type) {
            'slack' { Format-SlackNotification -Event $Event -Title $Title -Message $Message -InstanceId $InstanceId }
            'discord' { Format-DiscordNotification -Event $Event -Title $Title -Message $Message -InstanceId $InstanceId }
            default { Format-WebhookNotification -Event $Event -Title $Title -Message $Message -InstanceId $InstanceId -ProjectRoot $ProjectRoot }
        }

        # Send notification in background
        Start-Job -ScriptBlock {
            param($url, $payload)
            try {
                Invoke-RestMethod -Uri $url -Method Post -Body $payload -ContentType 'application/json' -ErrorAction SilentlyContinue
            } catch { }
        } -ArgumentList $channel.url, $payload | Out-Null
    }
}

function Get-EventColor {
    param([string]$Event)
    switch ($Event) {
        'rate_limit_detected' { return '#ff9800' }
        'rate_limit_cleared' { return '#4caf50' }
        'prd_completed' { return '#2196f3' }
        'story_completed' { return '#8bc34a' }
        'instance_error' { return '#f44336' }
        'instance_started' { return '#9c27b0' }
        'instance_stopped' { return '#607d8b' }
        'queue_empty' { return '#00bcd4' }
        default { return '#757575' }
    }
}

function Get-EventEmoji {
    param([string]$Event)
    switch ($Event) {
        'rate_limit_detected' { return [char]::ConvertFromUtf32(0x26A0) + [char]::ConvertFromUtf32(0xFE0F) }
        'rate_limit_cleared' { return [char]::ConvertFromUtf32(0x2705) }
        'prd_completed' { return [char]::ConvertFromUtf32(0x1F389) }
        'story_completed' { return [char]::ConvertFromUtf32(0x1F4DD) }
        'instance_error' { return [char]::ConvertFromUtf32(0x274C) }
        'instance_started' { return [char]::ConvertFromUtf32(0x1F680) }
        'instance_stopped' { return [char]::ConvertFromUtf32(0x1F6D1) }
        'queue_empty' { return [char]::ConvertFromUtf32(0x1F4ED) }
        default { return [char]::ConvertFromUtf32(0x1F4E2) }
    }
}

function Format-SlackNotification {
    param([string]$Event, [string]$Title, [string]$Message, [string]$InstanceId)
    $color = Get-EventColor -Event $Event
    $emoji = Get-EventEmoji -Event $Event
    $timestamp = Get-Date -Format "o"

    @{
        attachments = @(@{
            color = $color
            blocks = @(
                @{ type = 'header'; text = @{ type = 'plain_text'; text = "$emoji $Title"; emoji = $true } }
                @{ type = 'section'; text = @{ type = 'mrkdwn'; text = $Message } }
                @{ type = 'context'; elements = @(@{ type = 'mrkdwn'; text = "Ralph MCP | $timestamp$(if ($InstanceId) { " | $InstanceId" })" }) }
            )
        })
    } | ConvertTo-Json -Depth 10
}

function Format-DiscordNotification {
    param([string]$Event, [string]$Title, [string]$Message, [string]$InstanceId)
    $color = Get-EventColor -Event $Event
    $colorDecimal = [Convert]::ToInt32($color.TrimStart('#'), 16)
    $emoji = Get-EventEmoji -Event $Event
    $timestamp = Get-Date -Format "o"

    @{
        embeds = @(@{
            title = "$emoji $Title"
            description = $Message
            color = $colorDecimal
            footer = @{ text = "Ralph MCP$(if ($InstanceId) { " | $InstanceId" })" }
            timestamp = $timestamp
        })
    } | ConvertTo-Json -Depth 10
}

function Format-WebhookNotification {
    param([string]$Event, [string]$Title, [string]$Message, [string]$InstanceId, [string]$ProjectRoot)
    @{
        event = $Event
        title = $Title
        message = $Message
        instanceId = $InstanceId
        projectRoot = $ProjectRoot
        timestamp = (Get-Date -Format "o")
    } | ConvertTo-Json
}

# =============================================================================
# RATE LIMIT DETECTION FUNCTIONS
# =============================================================================

function Get-GlobalRateLimitFile {
    <#
    .SYNOPSIS
    Returns the path to the global rate limit marker file
    #>
    $globalDir = Get-RalphGlobalDir
    return Join-Path $globalDir "rate_limited"
}

function Set-GlobalRateLimit {
    <#
    .SYNOPSIS
    Sets the global rate limit marker so all instances pause
    #>
    param(
        [Parameter(Mandatory)]
        [string]$DetectedBy,
        [Parameter(Mandatory)]
        [string]$DetectionMethod,
        [string]$TriggerInfo = ""
    )

    $rateLimitFile = Get-GlobalRateLimitFile
    $parentDir = Split-Path $rateLimitFile -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    $now = Get-Date -Format "o"
    $nowEpoch = [int][double]::Parse((Get-Date -UFormat %s))
    $initialBackoff = if ($env:RALPH_RATE_BACKOFF_INITIAL) { [int]$env:RALPH_RATE_BACKOFF_INITIAL } else { 60 }

    @{
        detectedBy = $DetectedBy
        detectedAt = $now
        detectedAtEpoch = $nowEpoch
        detectionMethod = $DetectionMethod
        triggerInfo = $TriggerInfo
        backoffSeconds = $initialBackoff
        retryCount = 0
    } | ConvertTo-Json | Set-Content -Path $rateLimitFile

    Write-ColoredOutput "[GLOBAL] Rate limit detected by $DetectedBy - all instances will pause" -Color Red
}

function Test-GlobalRateLimit {
    <#
    .SYNOPSIS
    Checks if a global rate limit is active
    .OUTPUTS
    Boolean - True if rate limited
    #>
    $rateLimitFile = Get-GlobalRateLimitFile
    return Test-Path $rateLimitFile
}

function Clear-GlobalRateLimit {
    <#
    .SYNOPSIS
    Clears the global rate limit marker
    #>
    $rateLimitFile = Get-GlobalRateLimitFile
    if (Test-Path $rateLimitFile) {
        Remove-Item $rateLimitFile -Force
        Write-ColoredOutput "[GLOBAL] Rate limit cleared - instances can resume" -Color Green

        # Send notification
        try {
            $instanceId = Get-RalphInstanceId
            $shortId = Get-RalphShortId
            Send-RalphNotification -Event 'rate_limit_cleared' -Title 'Rate Limit Cleared' `
                -Message "Instance $shortId completed work successfully. All instances can resume." `
                -InstanceId $instanceId
        } catch { }
    }
}

function Wait-GlobalRateLimitClear {
    <#
    .SYNOPSIS
    Waits for the global rate limit to clear with exponential backoff
    #>
    $shortId = Get-RalphShortId
    $rateLimitFile = Get-GlobalRateLimitFile

    $initialBackoff = if ($env:RALPH_RATE_BACKOFF_INITIAL) { [int]$env:RALPH_RATE_BACKOFF_INITIAL } else { 60 }
    $maxBackoff = if ($env:RALPH_RATE_BACKOFF_MAX) { [int]$env:RALPH_RATE_BACKOFF_MAX } else { 960 }
    $backoffSeconds = $initialBackoff

    Update-RalphStatus -State "rate_limited"

    while (Test-Path $rateLimitFile) {
        # Read current backoff from file
        try {
            $currentInfo = Get-Content $rateLimitFile -Raw | ConvertFrom-Json
            $backoffSeconds = $currentInfo.backoffSeconds
        } catch { }

        # Add jitter
        $jitter = Get-Random -Minimum 0 -Maximum ([Math]::Max(1, [int]($backoffSeconds / 10)))
        $waitTime = $backoffSeconds + $jitter

        Write-ColoredOutput "[$shortId] Global rate limit active. Waiting ${waitTime}s..." -Color Yellow
        Add-RalphInstanceLog "Waiting for global rate limit to clear (${waitTime}s)"

        $elapsed = 0
        while ($elapsed -lt $waitTime) {
            if (-not (Test-Path $rateLimitFile)) {
                Write-ColoredOutput "[$shortId] Global rate limit cleared. Resuming..." -Color Green
                Add-RalphInstanceLog "Global rate limit cleared, resuming"
                Update-RalphStatus -State "idle"
                return
            }

            if (Test-RalphResumeRequested) {
                Clear-RalphResumeRequest
                Clear-GlobalRateLimit
                Write-ColoredOutput "[$shortId] Manual resume - clearing global rate limit" -Color Green
                Add-RalphInstanceLog "Manual resume, cleared global rate limit"
                Update-RalphStatus -State "idle"
                return
            }

            Start-Sleep -Seconds 5
            $elapsed += 5
        }

        # Exponential backoff
        $backoffSeconds = [Math]::Min($backoffSeconds * 2, $maxBackoff)

        # Update backoff in file
        if (Test-Path $rateLimitFile) {
            try {
                $currentInfo = Get-Content $rateLimitFile -Raw | ConvertFrom-Json
                $currentInfo.backoffSeconds = $backoffSeconds
                $currentInfo.retryCount = $currentInfo.retryCount + 1
                $currentInfo | ConvertTo-Json | Set-Content -Path $rateLimitFile
            } catch { }
        }
    }

    Update-RalphStatus -State "idle"
}

function Find-RateLimitInOutput {
    <#
    .SYNOPSIS
    Scans a log file for rate limit patterns
    .PARAMETER LogFile
    Path to log file to scan
    .OUTPUTS
    String - The matched pattern if found, $null otherwise
    #>
    param(
        [Parameter(Mandatory)]
        [string]$LogFile
    )

    if (-not (Test-Path $LogFile)) {
        return $null
    }

    $patterns = @(
        'rate.?limit',
        '429',
        'too.?many.?requests',
        'overloaded',
        'capacity',
        'try.?again.?later',
        'request.?limit',
        'throttl'
    )

    $content = Get-Content $LogFile -Raw -ErrorAction SilentlyContinue

    foreach ($pattern in $patterns) {
        if ($content -match $pattern) {
            return $pattern
        }
    }

    return $null
}

function Test-RateLimitByExitCode {
    <#
    .SYNOPSIS
    Checks if exit code indicates rate limiting
    .PARAMETER ExitCode
    Exit code from Claude process
    .OUTPUTS
    Boolean - True if rate limit indicated
    #>
    param(
        [Parameter(Mandatory)]
        [int]$ExitCode
    )

    # Exit code 2 = rate limited (proposed convention)
    return $ExitCode -eq 2
}

function Invoke-RateLimitHandler {
    <#
    .SYNOPSIS
    Handles rate limit detection and enters rate limited state
    .PARAMETER DetectionMethod
    Detection method ("output_pattern", "exit_code", "api_poll")
    .PARAMETER TriggerInfo
    Pattern or code that triggered detection
    .OUTPUTS
    Boolean - True when ready to continue
    #>
    param(
        [Parameter(Mandatory)]
        [string]$DetectionMethod,
        [string]$TriggerInfo = ""
    )

    $instanceId = Get-RalphInstanceId
    $shortId = Get-RalphShortId

    Write-ColoredOutput "[$shortId] Rate limit detected via $DetectionMethod" -Color Yellow
    if ($TriggerInfo) {
        Write-ColoredOutput "[$shortId] Trigger: $TriggerInfo" -Color Yellow
    }

    Add-RalphInstanceLog "Rate limit detected: method=$DetectionMethod trigger=$TriggerInfo"

    # Set global rate limit so all instances pause
    Set-GlobalRateLimit -DetectedBy $instanceId -DetectionMethod $DetectionMethod -TriggerInfo $TriggerInfo

    # Send notification
    Send-RalphNotification -Event 'rate_limit_detected' -Title 'Rate Limit Detected' `
        -Message "Instance $shortId detected rate limiting via $DetectionMethod" `
        -InstanceId $instanceId

    # Wait for global rate limit to clear
    Wait-GlobalRateLimitClear

    return $true
}

# =============================================================================
# PAUSE/RESUME FUNCTIONS (MCP Integration)
# =============================================================================

function Test-RalphPauseRequested {
    <#
    .SYNOPSIS
    Checks if a pause has been requested for this instance
    .OUTPUTS
    Boolean - True if pause requested
    #>
    $instanceId = Get-RalphInstanceId
    $paths = Get-RalphPaths
    $instanceDir = Join-Path $paths.InstancesDir $instanceId
    $pauseFile = Join-Path $instanceDir ".pause_requested"

    return Test-Path $pauseFile
}

function Test-RalphResumeRequested {
    <#
    .SYNOPSIS
    Checks if a resume has been requested for this instance
    .OUTPUTS
    Boolean - True if resume requested
    #>
    $instanceId = Get-RalphInstanceId
    $paths = Get-RalphPaths
    $instanceDir = Join-Path $paths.InstancesDir $instanceId
    $resumeFile = Join-Path $instanceDir ".resume_requested"

    return Test-Path $resumeFile
}

function Clear-RalphPauseRequest {
    <#
    .SYNOPSIS
    Clears the pause request file
    #>
    $instanceId = Get-RalphInstanceId
    $paths = Get-RalphPaths
    $instanceDir = Join-Path $paths.InstancesDir $instanceId
    $pauseFile = Join-Path $instanceDir ".pause_requested"

    if (Test-Path $pauseFile) {
        Remove-Item $pauseFile -Force
    }
}

function Clear-RalphResumeRequest {
    <#
    .SYNOPSIS
    Clears the resume request file
    #>
    $instanceId = Get-RalphInstanceId
    $paths = Get-RalphPaths
    $instanceDir = Join-Path $paths.InstancesDir $instanceId
    $resumeFile = Join-Path $instanceDir ".resume_requested"

    if (Test-Path $resumeFile) {
        Remove-Item $resumeFile -Force
    }
}

function Enter-RalphPausedState {
    <#
    .SYNOPSIS
    Enters paused state and waits for resume signal
    .PARAMETER Reason
    Reason for pause (default "manual")
    .OUTPUTS
    Boolean - True if resumed, False if terminated
    #>
    param(
        [string]$Reason = "manual"
    )

    $instanceId = Get-RalphInstanceId
    $shortId = Get-RalphShortId
    $paths = Get-RalphPaths
    $instanceDir = Join-Path $paths.InstancesDir $instanceId

    # Clear the pause request since we're now handling it
    Clear-RalphPauseRequest

    # Update status to paused
    Update-RalphStatus -State "paused"

    Write-ColoredOutput "[$shortId] Instance paused ($Reason). Waiting for resume signal..." -Color Yellow
    Add-RalphInstanceLog "Instance paused: $Reason"

    # Wait for resume signal
    while ($true) {
        if (Test-RalphResumeRequested) {
            Clear-RalphResumeRequest
            Write-ColoredOutput "[$shortId] Resume signal received. Continuing..." -Color Green
            Add-RalphInstanceLog "Instance resumed"
            Update-RalphStatus -State "idle"
            return $true
        }

        # Also check if we should terminate
        $terminateFile = Join-Path $instanceDir ".terminate_requested"
        if (Test-Path $terminateFile) {
            Remove-Item $terminateFile -Force
            Write-ColoredOutput "[$shortId] Terminate signal received during pause." -Color Red
            Add-RalphInstanceLog "Instance terminated during pause"
            return $false
        }

        Start-Sleep -Seconds 5
    }
}

function Enter-RalphRateLimitedState {
    <#
    .SYNOPSIS
    Enters rate-limited state with exponential backoff
    .PARAMETER InitialBackoff
    Initial backoff in seconds (default 60)
    .PARAMETER MaxRetries
    Maximum number of retries (default 5)
    .OUTPUTS
    Boolean - True when backoff complete
    #>
    param(
        [int]$InitialBackoff = 60,
        [int]$MaxRetries = 5
    )

    $instanceId = Get-RalphInstanceId
    $shortId = Get-RalphShortId
    $paths = Get-RalphPaths
    $instanceDir = Join-Path $paths.InstancesDir $instanceId
    $rateLimitFile = Join-Path $instanceDir ".rate_limited"

    # Write rate limit state file
    $now = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    $nowEpoch = [int][double]::Parse((Get-Date -UFormat %s))

    $rateLimitData = @{
        instanceId = $instanceId
        pausedAt = $now
        pausedAtEpoch = $nowEpoch
        reason = "rate_limit_detected"
        backoffSeconds = $InitialBackoff
        retryCount = 0
        maxRetries = $MaxRetries
    }

    $rateLimitData | ConvertTo-Json | Set-Content -Path $rateLimitFile

    # Update status
    Update-RalphStatus -State "rate_limited"

    $backoffSeconds = $InitialBackoff
    $retryCount = 0

    while ($retryCount -lt $MaxRetries) {
        # Add jitter (10% random variation)
        $jitter = Get-Random -Minimum 0 -Maximum ([Math]::Max(1, [int]($backoffSeconds / 10)))
        $waitTime = $backoffSeconds + $jitter

        Write-ColoredOutput "[$shortId] Rate limited. Waiting ${waitTime}s (retry $($retryCount + 1)/$MaxRetries)..." -Color Yellow
        Add-RalphInstanceLog "Rate limited, waiting ${waitTime}s (retry $($retryCount + 1)/$MaxRetries)"

        # Check for manual resume during backoff
        $elapsed = 0
        while ($elapsed -lt $waitTime) {
            if (Test-RalphResumeRequested) {
                Clear-RalphResumeRequest
                if (Test-Path $rateLimitFile) { Remove-Item $rateLimitFile -Force }
                Write-ColoredOutput "[$shortId] Manual resume during rate limit backoff." -Color Green
                Add-RalphInstanceLog "Manually resumed from rate limit"
                Update-RalphStatus -State "idle"
                return $true
            }

            Start-Sleep -Seconds 5
            $elapsed += 5
        }

        # Exponential backoff (double each time, max 960s = 16min)
        $backoffSeconds = [Math]::Min($backoffSeconds * 2, 960)
        $retryCount++

        # Update retry count in file
        $rateLimitData.retryCount = $retryCount
        $rateLimitData.backoffSeconds = $backoffSeconds
        $rateLimitData | ConvertTo-Json | Set-Content -Path $rateLimitFile
    }

    # Max retries exceeded
    if (Test-Path $rateLimitFile) { Remove-Item $rateLimitFile -Force }
    Write-ColoredOutput "[$shortId] Max rate limit retries exceeded." -Color Red
    Add-RalphInstanceLog "Rate limit max retries exceeded"
    Update-RalphStatus -State "idle"
    return $true
}

# Export all public functions
Export-ModuleMember -Function @(
    'Get-RalphPaths'
    'Reset-RalphPaths'
    'Test-Dependencies'
    'Read-PrdJson'
    'Write-PrdJson'
    'Get-PrdStatus'
    'Write-ColoredOutput'
    'Add-LogEntry'
    # Multi-instance functions (PS-001)
    'Get-RalphInstanceId'
    'Get-RalphShortId'
    'New-RalphInstanceDirectory'
    'Update-RalphStatus'
    'Get-RalphInstanceStatus'
    'Get-RalphInstances'
    'Add-RalphInstanceLog'
    # Locking functions (PS-002)
    'Lock-RalphStory'
    'Unlock-RalphStory'
    'Test-RalphStoryLocked'
    'Get-RalphStoryLock'
    'Get-RalphStoryLocks'
    'Clear-RalphStaleLock'
    'Clear-RalphStaleLocks'
    'Clear-RalphInstanceLocks'
    # PRD atomic functions (PS-003)
    'Read-RalphPrdSafe'
    'Update-RalphPrd'
    # Story claiming functions (PS-004)
    'Get-RalphNextStory'
    'Request-RalphStoryClaim'
    'Remove-RalphStoryClaim'
    'Request-RalphNextStoryClaim'
    # Git branch functions (PS-005)
    'New-RalphStoryBranch'
    'Merge-RalphStoryBranch'
    'Remove-RalphStoryBranch'
    'Get-RalphCurrentBranch'
    'Clear-RalphMergedBranches'
    # Cleanup functions (PS-007)
    'Register-RalphCleanup'
    'Invoke-RalphCleanup'
    'Set-RalphCurrentStory'
    # Global registry functions (GM-001, PS-004)
    'Get-RalphGlobalDir'
    'Initialize-RalphGlobalRegistry'
    'Get-RalphGlobalLinkName'
    'Register-RalphGlobalInstance'
    'Unregister-RalphGlobalInstance'
    'Ensure-RalphGlobalRegistration'
    'Get-RalphGlobalInstances'
    'Clear-RalphGlobalRegistry'
    # Multi-project dashboard functions
    'Get-ProjectPrdStatus'
    'Get-AllProjectsPrdStatus'
    'Get-AllProjectsLocks'
    # Notification functions
    'Get-NotificationConfigFile'
    'Send-RalphNotification'
    'Get-EventColor'
    'Get-EventEmoji'
    'Format-SlackNotification'
    'Format-DiscordNotification'
    'Format-WebhookNotification'
    # Rate limit detection functions
    'Get-GlobalRateLimitFile'
    'Set-GlobalRateLimit'
    'Test-GlobalRateLimit'
    'Clear-GlobalRateLimit'
    'Wait-GlobalRateLimitClear'
    'Find-RateLimitInOutput'
    'Test-RateLimitByExitCode'
    'Invoke-RateLimitHandler'
    # Pause/Resume functions (MCP Integration)
    'Test-RalphPauseRequested'
    'Test-RalphResumeRequested'
    'Clear-RalphPauseRequest'
    'Clear-RalphResumeRequest'
    'Enter-RalphPausedState'
    'Enter-RalphRateLimitedState'
)
