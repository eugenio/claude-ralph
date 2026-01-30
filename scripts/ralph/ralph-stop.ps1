<#
.SYNOPSIS
    Ralph Loop Process Supervisor - Graceful Stop

.DESCRIPTION
    Stops the Ralph supervisor and Claude processes cleanly.
    By default uses graceful shutdown, use -Force for immediate termination.

.PARAMETER Force
    Force kill processes immediately instead of graceful shutdown

.EXAMPLE
    .\ralph-stop.ps1

.EXAMPLE
    .\ralph-stop.ps1 -Force
#>

[CmdletBinding()]
param(
    [switch]$Force
)

$StateFile = ".claude\ralph-supervisor.local.json"
$LogFile = ".claude\ralph-supervisor.log"
$PidFile = ".claude\ralph-supervisor.pid"
$ClaudePidFile = ".claude\ralph-supervisor-claude.pid"

# ============================================================================
# Helper Functions
# ============================================================================
function Stop-ProcessGracefully {
    param(
        [int]$ProcessId,
        [string]$Name,
        [switch]$Force
    )

    if ($ProcessId -le 0) { return $true }

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process) {
        Write-Host "  $Name (PID $ProcessId): " -NoNewline
        Write-Host "Not running" -ForegroundColor Yellow
        return $true
    }

    if ($Force) {
        Write-Host "  $Name (PID $ProcessId): Force killing..."
        try {
            Stop-Process -Id $ProcessId -Force -ErrorAction Stop
            Write-Host "  $Name (PID $ProcessId): " -NoNewline
            Write-Host "Stopped" -ForegroundColor Green
            return $true
        } catch {
            Write-Host "  $Name (PID $ProcessId): " -NoNewline
            Write-Host "Failed to stop" -ForegroundColor Red
            return $false
        }
    }

    Write-Host "  $Name (PID $ProcessId): Sending stop signal..."

    try {
        # Try graceful shutdown first
        $process.CloseMainWindow() | Out-Null

        # Wait up to 10 seconds for graceful shutdown
        $waited = 0
        while (-not $process.HasExited -and $waited -lt 10) {
            Start-Sleep -Seconds 1
            $waited++
            $process.Refresh()
        }

        if (-not $process.HasExited) {
            Write-Host "  $Name (PID $ProcessId): " -NoNewline
            Write-Host "Still running, force killing..." -ForegroundColor Yellow
            Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        }

        # Verify stopped
        Start-Sleep -Milliseconds 500
        $checkProcess = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if (-not $checkProcess) {
            Write-Host "  $Name (PID $ProcessId): " -NoNewline
            Write-Host "Stopped" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  $Name (PID $ProcessId): " -NoNewline
            Write-Host "Failed to stop" -ForegroundColor Red
            return $false
        }
    } catch {
        # Process might have already exited
        $checkProcess = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if (-not $checkProcess) {
            Write-Host "  $Name (PID $ProcessId): " -NoNewline
            Write-Host "Stopped" -ForegroundColor Green
            return $true
        }
        Write-Host "  $Name (PID $ProcessId): Error - $_" -ForegroundColor Red
        return $false
    }
}

function Remove-StateFiles {
    Write-Host ""
    Write-Host "Cleaning up state files..."

    $files = @($StateFile, $PidFile, $ClaudePidFile)

    foreach ($file in $files) {
        if (Test-Path $file) {
            Remove-Item $file -Force -ErrorAction SilentlyContinue
            Write-Host "  Removed: $file"
        }
    }
}

# ============================================================================
# Main
# ============================================================================
Write-Host ""
Write-Host "Ralph Loop Supervisor - Stop"
Write-Host "=============================="
Write-Host ""

# Check if state file exists
if (-not (Test-Path $StateFile) -and -not (Test-Path $PidFile)) {
    Write-Host "No Ralph supervisor appears to be running." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "No state files found:"
    Write-Host "  - $StateFile"
    Write-Host "  - $PidFile"
    Write-Host ""
    exit 0
}

# Get PIDs
$supervisorPid = 0
$claudePid = 0

if (Test-Path $StateFile) {
    try {
        $state = Get-Content $StateFile -Raw | ConvertFrom-Json
        $supervisorPid = [int]$state.pid
        if ($state.claude_pid) {
            $claudePid = [int]$state.claude_pid
        }
    } catch {
        # Ignore parse errors
    }
}

# Fallback to PID files
if ($supervisorPid -le 0 -and (Test-Path $PidFile)) {
    $supervisorPid = [int](Get-Content $PidFile -ErrorAction SilentlyContinue)
}

if ($claudePid -le 0 -and (Test-Path $ClaudePidFile)) {
    $claudePid = [int](Get-Content $ClaudePidFile -ErrorAction SilentlyContinue)
}

Write-Host "Stopping processes..."

# Stop Claude first (if running)
if ($claudePid -gt 0) {
    Stop-ProcessGracefully -ProcessId $claudePid -Name "Claude" -Force:$Force | Out-Null
}

# Stop supervisor
if ($supervisorPid -gt 0) {
    Stop-ProcessGracefully -ProcessId $supervisorPid -Name "Supervisor" -Force:$Force | Out-Null
}

# Clean up files
Remove-StateFiles

Write-Host ""
Write-Host "Ralph supervisor stopped." -ForegroundColor Green
Write-Host ""

# Log the stop
if (Test-Path $LogFile) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "[$timestamp] [INFO] Supervisor stopped by ralph-stop.ps1"
}
