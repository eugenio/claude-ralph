<#
.SYNOPSIS
    Ralph Loop Process Supervisor for PowerShell
    Monitors Claude Code process and restarts on crash

.DESCRIPTION
    Provides true process supervision with crash recovery for Claude Code.
    Supports foreground and background modes, configurable restart limits,
    and comprehensive logging.

.PARAMETER Prompt
    The prompt to run with Claude (required)

.PARAMETER MaxIterations
    Maximum iterations (0 = unlimited, default: 0)

.PARAMETER MaxRestarts
    Maximum crash restarts before giving up (default: 10)

.PARAMETER RestartDelay
    Seconds between restarts (default: 5)

.PARAMETER CompletionPromise
    Optional promise text to detect completion

.PARAMETER Background
    Run as background job

.PARAMETER Verbose
    Enable verbose logging

.EXAMPLE
    .\ralph-supervisor.ps1 -Prompt "Build a REST API" -MaxIterations 10

.EXAMPLE
    .\ralph-supervisor.ps1 -Prompt "Long task" -Background -Verbose
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Prompt,

    [int]$MaxIterations = 0,

    [int]$MaxRestarts = 10,

    [int]$RestartDelay = 5,

    [string]$CompletionPromise = $null,

    [switch]$Background,

    [switch]$VerboseLog,

    # Internal flag for background job
    [switch]$ForegroundInternal
)

# ============================================================================
# Configuration
# ============================================================================
$StateFile = ".claude\ralph-supervisor.local.json"
$LogFile = ".claude\ralph-supervisor.log"
$PidFile = ".claude\ralph-supervisor.pid"
$ClaudePidFile = ".claude\ralph-supervisor-claude.pid"

# Runtime state
$script:Iteration = 1
$script:RestartCount = 0
$script:StartedAt = $null
$script:ClaudeProcess = $null

# ============================================================================
# Logging Functions
# ============================================================================
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Level,

        [Parameter(Mandatory=$true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Always write to log file
    Add-Content -Path $LogFile -Value $logEntry -ErrorAction SilentlyContinue

    # Print to console based on level and verbose setting
    if ($VerboseLog -or $Level -eq "ERROR" -or $Level -eq "WARN") {
        switch ($Level) {
            "ERROR" { Write-Host $logEntry -ForegroundColor Red }
            "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
            "INFO"  { Write-Host $logEntry -ForegroundColor Cyan }
            "DEBUG" { Write-Host $logEntry -ForegroundColor Gray }
        }
    }
}

function Write-LogInfo  { param([string]$Message) Write-Log -Level "INFO" -Message $Message }
function Write-LogWarn  { param([string]$Message) Write-Log -Level "WARN" -Message $Message }
function Write-LogError { param([string]$Message) Write-Log -Level "ERROR" -Message $Message }
function Write-LogDebug { param([string]$Message) if ($VerboseLog) { Write-Log -Level "DEBUG" -Message $Message } }

# ============================================================================
# State Management
# ============================================================================
function Ensure-ClaudeDir {
    if (-not (Test-Path ".claude")) {
        New-Item -ItemType Directory -Path ".claude" -Force | Out-Null
    }
}

function Write-State {
    param(
        [string]$Status = "running",
        [int]$ClaudePid = 0
    )

    $state = @{
        pid = $PID
        claude_pid = if ($ClaudePid -gt 0) { $ClaudePid } else { $null }
        started_at = $script:StartedAt
        iteration = $script:Iteration
        restart_count = $script:RestartCount
        max_iterations = $MaxIterations
        max_restarts = $MaxRestarts
        completion_promise = $CompletionPromise
        prompt = $Prompt
        status = $Status
        log_file = $LogFile
        last_update = (Get-Date -Format "o")
    }

    $state | ConvertTo-Json -Depth 10 | Set-Content -Path $StateFile -Encoding UTF8
}

function Update-State {
    param(
        [string]$Status = "running",
        [int]$ClaudePid = 0
    )
    Write-State -Status $Status -ClaudePid $ClaudePid
}

function Remove-StateFiles {
    Write-LogInfo "Cleaning up supervisor state files"
    Remove-Item -Path $StateFile -ErrorAction SilentlyContinue
    Remove-Item -Path $PidFile -ErrorAction SilentlyContinue
    Remove-Item -Path $ClaudePidFile -ErrorAction SilentlyContinue
}

# ============================================================================
# Process Management
# ============================================================================
function Stop-ClaudeProcess {
    if ($script:ClaudeProcess -and -not $script:ClaudeProcess.HasExited) {
        Write-LogInfo "Stopping Claude process (PID: $($script:ClaudeProcess.Id))"
        try {
            $script:ClaudeProcess.Kill()
            $script:ClaudeProcess.WaitForExit(5000) | Out-Null
        } catch {
            Write-LogWarn "Could not stop Claude process: $_"
        }
    }
}

function Handle-ExitCode {
    param([int]$ExitCode)

    switch ($ExitCode) {
        0 {
            Write-LogInfo "Claude exited successfully (code 0)"
            Write-Host ""
            Write-Host "Ralph supervisor: Claude completed successfully" -ForegroundColor Green
            Remove-StateFiles
            return $true  # Stop loop
        }

        # Ctrl+C variants on Windows
        { $_ -in @(-1073741510, 130, 0xC000013A) } {
            Write-LogInfo "Claude interrupted by user"
            Write-Host ""
            Write-Host "Ralph supervisor: Stopped by user (Ctrl+C)" -ForegroundColor Yellow
            Remove-StateFiles
            return $true  # Stop loop
        }

        # SIGTERM equivalent
        143 {
            Write-LogInfo "Claude terminated (SIGTERM)"
            Write-Host ""
            Write-Host "Ralph supervisor: Stopped by SIGTERM" -ForegroundColor Yellow
            Remove-StateFiles
            return $true  # Stop loop
        }

        # SIGKILL equivalent
        137 {
            Write-LogWarn "Claude was killed (exit 137)"
            return Test-ShouldRestart -Reason "SIGKILL"
        }

        default {
            Write-LogWarn "Claude crashed with exit code $ExitCode"
            return Test-ShouldRestart -Reason "exit code $ExitCode"
        }
    }
}

function Test-ShouldRestart {
    param([string]$Reason)

    $script:RestartCount++

    if ($script:RestartCount -ge $MaxRestarts) {
        Write-LogError "Max restarts ($MaxRestarts) reached after $Reason"
        Write-Host ""
        Write-Host "Ralph supervisor: Max restarts ($MaxRestarts) reached" -ForegroundColor Red
        Write-Host "Check log for details: $LogFile"
        Remove-StateFiles
        return $true  # Stop loop (with error)
    }

    Write-LogInfo "Crash detected ($Reason), restart $($script:RestartCount)/$MaxRestarts in ${RestartDelay}s"
    Write-Host ""
    Write-Host "Ralph supervisor: Crash detected ($Reason)" -ForegroundColor Yellow
    Write-Host "Restarting in ${RestartDelay}s (attempt $($script:RestartCount)/$MaxRestarts)..."

    Start-Sleep -Seconds $RestartDelay

    # Increment iteration and update state
    $script:Iteration++
    Update-State -Status "restarting"

    return $false  # Continue loop
}

# ============================================================================
# Main Loop (Foreground)
# ============================================================================
function Start-Foreground {
    Ensure-ClaudeDir

    $script:StartedAt = (Get-Date -Format "o")
    $PID | Set-Content -Path $PidFile

    Write-State -Status "running"

    Write-LogInfo "Starting Ralph supervisor"
    Write-LogInfo "Prompt: $Prompt"
    Write-LogInfo "Max iterations: $MaxIterations (0=unlimited)"
    Write-LogInfo "Max restarts: $MaxRestarts"
    Write-LogInfo "Completion promise: $(if ($CompletionPromise) { $CompletionPromise } else { '<none>' })"

    Write-Host ""
    Write-Host "Ralph supervisor started (PID: $PID)" -ForegroundColor Green
    Write-Host "Log file: $LogFile"
    Write-Host "State file: $StateFile"
    Write-Host "Stop with: Ctrl+C or ralph-stop.ps1"
    Write-Host ""

    # Register cleanup handler
    $null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        Stop-ClaudeProcess
        Remove-StateFiles
    }

    try {
        while ($true) {
            # Check max iterations
            if ($MaxIterations -gt 0 -and $script:Iteration -gt $MaxIterations) {
                Write-LogInfo "Max iterations ($MaxIterations) reached"
                Write-Host ""
                Write-Host "Ralph supervisor: Max iterations ($MaxIterations) reached" -ForegroundColor Green
                Remove-StateFiles
                return
            }

            Write-LogInfo "Starting iteration $($script:Iteration)"

            # Build Claude arguments
            if ($script:Iteration -eq 1) {
                # First iteration: start with prompt
                Write-LogDebug "Running: claude -p `"$Prompt`""
                $claudeArgs = @("-p", $Prompt)
            } else {
                # Subsequent iterations: continue previous session
                Write-LogDebug "Running: claude --continue"
                $claudeArgs = @("--continue")
            }

            Update-State -Status "running"

            # Start Claude process
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = "claude"
            $processInfo.Arguments = $claudeArgs -join " "
            $processInfo.UseShellExecute = $false
            $processInfo.RedirectStandardOutput = $false
            $processInfo.RedirectStandardError = $false
            $processInfo.CreateNoWindow = $false

            try {
                $script:ClaudeProcess = [System.Diagnostics.Process]::Start($processInfo)
                $script:ClaudeProcess.Id | Set-Content -Path $ClaudePidFile

                Write-LogDebug "Claude started with PID: $($script:ClaudeProcess.Id)"

                # Wait for process to exit
                $script:ClaudeProcess.WaitForExit()
                $exitCode = $script:ClaudeProcess.ExitCode

                Write-LogDebug "Claude exited with code: $exitCode"

                # Handle exit code
                $shouldStop = Handle-ExitCode -ExitCode $exitCode

                if ($shouldStop) {
                    return
                }
            }
            catch {
                Write-LogError "Failed to start Claude: $_"
                $script:RestartCount++

                if ($script:RestartCount -ge $MaxRestarts) {
                    Write-LogError "Max restarts reached due to start failures"
                    Remove-StateFiles
                    return
                }

                Write-Host "Failed to start Claude, retrying in ${RestartDelay}s..." -ForegroundColor Yellow
                Start-Sleep -Seconds $RestartDelay
            }
        }
    }
    finally {
        Stop-ClaudeProcess
        Remove-StateFiles
        Unregister-Event -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# Background Mode
# ============================================================================
function Start-Background {
    Ensure-ClaudeDir

    # Check if already running
    if (Test-Path $PidFile) {
        $existingPid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($existingPid) {
            $process = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
            if ($process) {
                Write-Host "Error: Ralph supervisor already running (PID: $existingPid)" -ForegroundColor Red
                Write-Host "Use ralph-stop.ps1 to stop it first"
                return
            }
        }
        # Stale PID file
        Remove-Item $PidFile -ErrorAction SilentlyContinue
    }

    Write-Host "Starting Ralph supervisor in background..."

    # Build argument string for background job
    $scriptPath = $PSCommandPath
    $args = @(
        "-File", "`"$scriptPath`"",
        "-Prompt", "`"$Prompt`"",
        "-ForegroundInternal"
    )

    if ($MaxIterations -gt 0) { $args += @("-MaxIterations", $MaxIterations) }
    if ($MaxRestarts -ne 10) { $args += @("-MaxRestarts", $MaxRestarts) }
    if ($RestartDelay -ne 5) { $args += @("-RestartDelay", $RestartDelay) }
    if ($CompletionPromise) { $args += @("-CompletionPromise", "`"$CompletionPromise`"") }
    if ($VerboseLog) { $args += "-VerboseLog" }

    # Start PowerShell in background
    $bgProcess = Start-Process -FilePath "powershell.exe" `
        -ArgumentList $args `
        -WindowStyle Hidden `
        -PassThru `
        -RedirectStandardOutput $LogFile `
        -RedirectStandardError "$LogFile.err"

    $bgProcess.Id | Set-Content -Path $PidFile

    Write-Host ""
    Write-Host "Ralph supervisor started in background" -ForegroundColor Green
    Write-Host "  PID: $($bgProcess.Id)"
    Write-Host "  Log: $LogFile"
    Write-Host "  State: $StateFile"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  Check status: .\ralph-status.ps1"
    Write-Host "  Stop: .\ralph-stop.ps1"
    Write-Host "  View logs: Get-Content $LogFile -Tail 50 -Wait"
}

# ============================================================================
# Main Entry Point
# ============================================================================
if ($Background -and -not $ForegroundInternal) {
    Start-Background
} else {
    Start-Foreground
}
