# Ralph PowerShell Guide

This guide covers the PowerShell implementation of Ralph's multi-instance features for cross-platform compatibility.

## Prerequisites

- **PowerShell 7.0+** (pwsh)
- **Git** installed and in PATH
- **Claude Code CLI** installed

Check your PowerShell version:
```powershell
$PSVersionTable.PSVersion
```

## Quick Start

### Single Instance

```powershell
# Run Ralph with default settings
./scripts/ralph/ralph.ps1

# Run with custom iterations
./scripts/ralph/ralph.ps1 -MaxIterations 20
```

### Multiple Instances

```powershell
# Launch 3 parallel instances
./scripts/ralph/ralph-parallel.ps1 Start -Count 3

# Monitor progress
./scripts/ralph/ralph-dashboard.ps1

# Stop all instances
./scripts/ralph/ralph-parallel.ps1 Stop
```

## PowerShell Scripts

### ralph.ps1

Main entry point for running Ralph.

```powershell
# Basic usage
./scripts/ralph/ralph.ps1

# With options
./scripts/ralph/ralph.ps1 -MaxIterations 15 -PrdPath "./custom-prd.json"

# With debug output
$env:RALPH_DEBUG = "1"
./scripts/ralph/ralph.ps1
```

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-MaxIterations` | Int | 10 | Maximum Claude invocations |
| `-PrdPath` | String | prd.json | Path to PRD file |
| `-Force` | Switch | - | Force new instance ID |

### ralph-parallel.ps1

Launch and manage multiple instances using PowerShell jobs.

```powershell
# Start instances
./scripts/ralph/ralph-parallel.ps1 Start -Count 3
./scripts/ralph/ralph-parallel.ps1 Start -Count 4 -MaxIterations 20

# Check status
./scripts/ralph/ralph-parallel.ps1 Status

# Stop gracefully
./scripts/ralph/ralph-parallel.ps1 Stop

# Force kill
./scripts/ralph/ralph-parallel.ps1 Kill

# Open dashboard
./scripts/ralph/ralph-parallel.ps1 Dashboard
```

### ralph-dashboard.ps1

TUI dashboard for monitoring all instances.

```powershell
# Default view (2 second refresh)
./scripts/ralph/ralph-dashboard.ps1

# Custom refresh interval
./scripts/ralph/ralph-dashboard.ps1 -RefreshInterval 5

# Single snapshot (no auto-refresh)
./scripts/ralph/ralph-dashboard.ps1 -Once
```

**Keyboard Shortcuts:**
| Key | Action |
|-----|--------|
| Q | Quit |
| R | Force refresh |
| L | Show lock details |
| C | Cleanup dead instances |

### ralph-locks.ps1

Manage story locks.

```powershell
# Show all locks
./scripts/ralph/ralph-locks.ps1 Status

# Release specific lock
./scripts/ralph/ralph-locks.ps1 Release -StoryId "US-001"

# Release all locks
./scripts/ralph/ralph-locks.ps1 ReleaseAll

# Clean stale locks (>2 hours)
./scripts/ralph/ralph-locks.ps1 Cleanup

# Show help
./scripts/ralph/ralph-locks.ps1 Help
```

### ralph-cleanup.ps1

Clean up instances and stale data.

```powershell
# Show summary of all instances
./scripts/ralph/ralph-cleanup.ps1

# Clean dead instances (no heartbeat >5 min)
./scripts/ralph/ralph-cleanup.ps1 -Dead

# Clean old instances (>7 days)
./scripts/ralph/ralph-cleanup.ps1 -Old

# Clean both
./scripts/ralph/ralph-cleanup.ps1 -All

# Preview without deleting
./scripts/ralph/ralph-cleanup.ps1 -Dead -WhatIf
```

## RalphUtils Module

The core functionality is in `RalphUtils.psm1`. Import it to use functions directly:

```powershell
Import-Module ./scripts/ralph/RalphUtils.psm1

# Generate instance ID
$instanceId = Get-RalphInstanceId
$shortId = Get-RalphShortId

# Create instance directory
$paths = New-RalphInstanceDirectory

# Lock a story
$locked = Lock-RalphStory -StoryId "US-001"

# Update status
Update-RalphStatus -State "working" -CurrentStory "US-001"

# Read PRD safely
$prd = Read-RalphPrdSafe

# Update PRD atomically
Update-RalphPrd -ScriptBlock {
    param($prd)
    $prd.userStories[0].passes = $true
    return $prd
}

# Claim next available story
$story = Request-RalphNextStoryClaim

# Create feature branch
New-RalphStoryBranch -StoryId "US-001"
```

### Key Functions

| Function | Description |
|----------|-------------|
| `Get-RalphInstanceId` | Generate unique instance ID |
| `Get-RalphShortId` | Get 8-char short ID |
| `New-RalphInstanceDirectory` | Create instance workspace |
| `Update-RalphStatus` | Write status.json with heartbeat |
| `Lock-RalphStory` | Acquire atomic story lock |
| `Unlock-RalphStory` | Release story lock |
| `Test-RalphStoryLocked` | Check if story is locked |
| `Read-RalphPrdSafe` | Read PRD with mutex lock |
| `Update-RalphPrd` | Atomic PRD update |
| `Get-RalphNextStory` | Find next unclaimed story |
| `Request-RalphStoryClaim` | Lock + claim story |
| `New-RalphStoryBranch` | Create feature branch |
| `Merge-RalphStoryBranch` | Merge completed branch |
| `Register-RalphCleanup` | Register shutdown handler |

## Cross-Platform Compatibility

The PowerShell implementation is compatible with the Bash implementation:

### Shared Formats

**Lock Directory Structure:**
```
locks/{story-id}.lock/
  owner.txt       # Instance ID
  timestamp.txt   # Unix epoch
```

**Status JSON:**
```json
{
  "instanceId": "user-hostname-pid-timestamp",
  "shortId": "user-hos",
  "state": "working",
  "currentStory": "US-001",
  "iteration": 3,
  "maxIterations": 10,
  "lastHeartbeatEpoch": 1700000000,
  "pid": 12345
}
```

**Instance ID Format:**
```
{username}-{hostname}-{pid}-{timestamp}
```

### Running Mixed Environments

You can run Bash and PowerShell instances simultaneously:

```bash
# Terminal 1 (Bash)
./ralph-parallel.sh 2

# Terminal 2 (PowerShell)
pwsh -c "./scripts/ralph/ralph-parallel.ps1 Start -Count 2"

# Both will share locks and PRD safely
```

## Pester Tests

Run the test suite with Pester:

```powershell
# Install Pester if needed
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser

# Run all tests
Invoke-Pester ./scripts/ralph/tests/ -Output Detailed

# Run specific test file
Invoke-Pester ./scripts/ralph/tests/RalphMultiInstance.Tests.ps1
```

### Test Files

| File | Tests |
|------|-------|
| `RalphMultiInstance.Tests.ps1` | Core module functions |
| `RalphScripts.Tests.ps1` | Script commands |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RALPH_DEBUG` | 0 | Enable debug output |
| `RALPH_LOCK_TIMEOUT` | 7200 | Lock timeout (seconds) |
| `RALPH_CLEANUP_TTL` | 7 | Days to keep old instances |
| `RALPH_PROJECT_ROOT` | . | Project root directory |

## Troubleshooting

### Module Import Fails

```powershell
# Check module path
Test-Path ./scripts/ralph/RalphUtils.psm1

# Import with verbose
Import-Module ./scripts/ralph/RalphUtils.psm1 -Verbose
```

### Lock Issues

```powershell
# Check lock status
./scripts/ralph/ralph-locks.ps1 Status

# Force cleanup
./scripts/ralph/ralph-locks.ps1 Cleanup
```

### PRD Mutex Timeout

If PRD updates time out:

```powershell
# Check for stuck mutex
# Kill any hung PowerShell processes

# Increase timeout
$env:RALPH_LOCK_TIMEOUT = "30"
```

### Job Issues

```powershell
# Check running jobs
Get-Job | Where-Object { $_.Name -like "Ralph*" }

# Remove stuck jobs
Get-Job | Where-Object { $_.State -eq "Failed" } | Remove-Job

# Force stop all Ralph jobs
Get-Job | Where-Object { $_.Name -like "Ralph*" } | Stop-Job -PassThru | Remove-Job
```

## Platform-Specific Notes

### Windows

- Use `pwsh.exe` (PowerShell 7+), not `powershell.exe`
- Mutex names are global across the system
- File locking uses Windows native mechanisms

### Linux/macOS

- Install PowerShell 7: `brew install powershell` or via package manager
- Mutex uses named semaphores
- Atomic mkdir is POSIX-compliant

## Architecture Diagram

```
                    ┌─────────────────────────────┐
                    │   ralph-dashboard.ps1       │
                    │   Auto-refresh TUI          │
                    └─────────────┬───────────────┘
                                  │ reads
         ┌────────────────────────┼────────────────────────┐
         │                        │                        │
         ▼                        ▼                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  ralph.ps1      │    │  ralph.ps1      │    │  ralph.ps1      │
│  Instance A     │    │  Instance B     │    │  Instance C     │
│  (PowerShell)   │    │  (PowerShell)   │    │  (PowerShell)   │
└────────┬────────┘    └────────┬────────┘    └────────┬────────┘
         │                      │                      │
         └──────────────────────┼──────────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    RalphUtils.psm1                              │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐         │
│  │ Lock-Ralph* │  │ Update-Ralph*│  │ New-RalphStory*│         │
│  │ Functions   │  │ Functions    │  │ Branch funcs   │         │
│  └─────────────┘  └──────────────┘  └────────────────┘         │
└──────────────────────────┬──────────────────────────────────────┘
                           │
    ┌──────────────────────┼──────────────────────┐
    │                      │                      │
    ▼                      ▼                      ▼
┌───────────┐       ┌────────────┐        ┌─────────────┐
│ prd.json  │       │  locks/    │        │ instances/  │
│ (Mutex)   │       │ (mkdir)    │        │ status.json │
└───────────┘       └────────────┘        └─────────────┘
```

## See Also

- [Multi-Instance Guide](./multi-instance.md) - Full architecture documentation
- [Ralph README](../README.md) - Getting started
