#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Rate limit monitoring daemon for claude-ralph

.DESCRIPTION
    Background daemon that monitors for rate limits and automatically
    pauses/resumes ralph instances based on external API status.

.PARAMETER Command
    Command to execute: start, stop, status, check

.EXAMPLE
    ./ralph-rate-monitor.ps1 start
    ./ralph-rate-monitor.ps1 stop
    ./ralph-rate-monitor.ps1 status
    ./ralph-rate-monitor.ps1 check
#>

param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'status', 'check')]
    [string]$Command = 'status'
)

$ErrorActionPreference = 'Stop'

# Import the utilities module
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $scriptDir 'RalphUtils.psm1') -Force

# Configuration
$PollInterval = if ($env:RALPH_RATE_POLL_INTERVAL) { [int]$env:RALPH_RATE_POLL_INTERVAL } else { 30 }
$ApiUrl = if ($env:RALPH_RATE_API_URL) { $env:RALPH_RATE_API_URL } else { 'https://status.anthropic.com/api/v2/status.json' }
$PauseAll = if ($env:RALPH_RATE_PAUSE_ALL -eq '1') { $true } else { $false }

# Daemon files
$globalDir = Get-RalphGlobalDir
$DaemonPidFile = Join-Path $globalDir 'rate-monitor.pid'
$DaemonLogFile = Join-Path $globalDir 'rate-monitor.log'

function Write-DaemonLog {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$timestamp] $Message" | Add-Content -Path $DaemonLogFile
}

function Test-DaemonRunning {
    if (Test-Path $DaemonPidFile) {
        $pid = Get-Content $DaemonPidFile -ErrorAction SilentlyContinue
        if ($pid) {
            try {
                $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
                if ($process) {
                    return $true
                }
            }
            catch { }
        }
    }
    return $false
}

function Start-RateMonitorDaemon {
    if (Test-DaemonRunning) {
        $pid = Get-Content $DaemonPidFile
        Write-Host "Rate monitor daemon is already running (PID: $pid)"
        return
    }

    # Ensure global directory exists
    $null = New-Item -ItemType Directory -Path $globalDir -Force

    Write-Host "Starting rate limit monitor daemon..."
    Write-Host "  Poll interval: ${PollInterval}s"
    Write-Host "  API URL: $ApiUrl"
    Write-Host "  Log file: $DaemonLogFile"

    # Start daemon in background
    $scriptPath = $MyInvocation.PSCommandPath
    $job = Start-Job -ScriptBlock {
        param($scriptPath)
        & $scriptPath '_run_daemon'
    } -ArgumentList $scriptPath

    $job.Id | Set-Content -Path $DaemonPidFile

    Write-Host "Daemon started with Job ID: $($job.Id)"
}

function Stop-RateMonitorDaemon {
    if (-not (Test-DaemonRunning)) {
        Write-Host "Rate monitor daemon is not running"
        Remove-Item $DaemonPidFile -Force -ErrorAction SilentlyContinue
        return
    }

    $jobId = Get-Content $DaemonPidFile
    Write-Host "Stopping rate monitor daemon (Job ID: $jobId)..."

    try {
        Stop-Job -Id $jobId -ErrorAction SilentlyContinue
        Remove-Job -Id $jobId -Force -ErrorAction SilentlyContinue
    }
    catch { }

    Remove-Item $DaemonPidFile -Force -ErrorAction SilentlyContinue
    Write-Host "Daemon stopped"
}

function Show-DaemonStatus {
    if (Test-DaemonRunning) {
        $pid = Get-Content $DaemonPidFile
        Write-ColoredOutput "Rate monitor daemon is running (PID: $pid)" -Color Green
        Write-Host ""
        Write-Host "Recent log entries:"
        if (Test-Path $DaemonLogFile) {
            Get-Content $DaemonLogFile -Tail 20
        }
        else {
            Write-Host "  (no log entries)"
        }
    }
    else {
        Write-ColoredOutput "Rate monitor daemon is not running" -Color Yellow
    }
}

function Test-ApiStatus {
    if ([string]::IsNullOrEmpty($ApiUrl) -or $ApiUrl -eq 'none') {
        return $true
    }

    try {
        $response = Invoke-RestMethod -Uri $ApiUrl -TimeoutSec 10 -ErrorAction Stop
        $indicator = $response.status.indicator

        switch ($indicator) {
            { $_ -in @('none', 'minor') } { return $true }
            { $_ -in @('major', 'critical') } {
                Write-DaemonLog "API reports degraded status: $indicator"
                return $false
            }
            default { return $true }
        }
    }
    catch {
        Write-DaemonLog "Failed to fetch API status from $ApiUrl : $_"
        return $true  # Assume OK on fetch failure
    }
}

function Suspend-AllInstances {
    param([string]$Reason)

    $instances = Get-RalphInstances

    foreach ($instance in $instances) {
        $state = $instance.state

        # Skip if already paused or in terminal state
        if ($state -in @('paused', 'rate_limited', 'completed', 'terminated')) {
            continue
        }

        Write-DaemonLog "Pausing instance $($instance.instanceId) due to: $Reason"

        $paths = Get-RalphPaths
        $instanceDir = Join-Path $paths.InstancesDir $instance.instanceId
        $pauseFile = Join-Path $instanceDir '.pause_requested'

        if (Test-Path $instanceDir) {
            @{
                requestedAt      = (Get-Date -Format 'o')
                requestedAtEpoch = [int][double]::Parse((Get-Date -UFormat %s))
                reason           = $Reason
                source           = 'rate-monitor'
            } | ConvertTo-Json | Set-Content -Path $pauseFile
        }
    }
}

function Resume-AllInstances {
    $instances = Get-RalphInstances

    foreach ($instance in $instances) {
        $state = $instance.state

        # Only resume paused instances
        if ($state -notin @('paused', 'rate_limited')) {
            continue
        }

        Write-DaemonLog "Resuming instance $($instance.instanceId)"

        $paths = Get-RalphPaths
        $instanceDir = Join-Path $paths.InstancesDir $instance.instanceId
        $resumeFile = Join-Path $instanceDir '.resume_requested'

        if (Test-Path $instanceDir) {
            @{
                requestedAt      = (Get-Date -Format 'o')
                requestedAtEpoch = [int][double]::Parse((Get-Date -UFormat %s))
                source           = 'rate-monitor'
            } | ConvertTo-Json | Set-Content -Path $resumeFile
        }
    }
}

function Invoke-SingleCheck {
    Write-Host "Checking rate limit status..."

    $apiOk = Test-ApiStatus
    if ($apiOk) {
        Write-ColoredOutput "API status: OK" -Color Green
    }
    else {
        Write-ColoredOutput "API status: DEGRADED" -Color Red
    }

    Write-Host ""
    Write-Host "Instance status:"

    $instances = Get-RalphInstances
    if ($instances.Count -eq 0) {
        Write-Host "  (no instances)"
    }
    else {
        foreach ($instance in $instances) {
            Write-Host "  $($instance.shortId): $($instance.state)"
        }
    }

    return $apiOk
}

function Start-DaemonLoop {
    Write-DaemonLog "Rate monitor daemon started (PID: $PID)"
    Write-DaemonLog "Poll interval: ${PollInterval}s, API URL: $ApiUrl"

    $wasRateLimited = $false

    while ($true) {
        if (Test-ApiStatus) {
            if ($wasRateLimited) {
                Write-DaemonLog "Rate limit cleared, resuming instances"
                if ($PauseAll) {
                    Resume-AllInstances
                }
                $wasRateLimited = $false
            }
        }
        else {
            if (-not $wasRateLimited) {
                Write-DaemonLog "Rate limit detected via API"
                if ($PauseAll) {
                    Suspend-AllInstances -Reason "api_rate_limit"
                }
                $wasRateLimited = $true
            }
        }

        Start-Sleep -Seconds $PollInterval
    }
}

# Main
switch ($Command) {
    'start' { Start-RateMonitorDaemon }
    'stop' { Stop-RateMonitorDaemon }
    'status' { Show-DaemonStatus }
    'check' { Invoke-SingleCheck }
    '_run_daemon' { Start-DaemonLoop }
    default {
        Write-Host "Usage: $($MyInvocation.MyCommand.Name) {start|stop|status|check}"
        Write-Host ""
        Write-Host "Commands:"
        Write-Host "  start   - Start the rate monitor daemon"
        Write-Host "  stop    - Stop the rate monitor daemon"
        Write-Host "  status  - Show daemon status and recent logs"
        Write-Host "  check   - Perform a single rate limit check"
    }
}
