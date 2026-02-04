# Ralph PowerShell Guide

This guide covers using Ralph with PowerShell 7+ for cross-platform compatibility.

## Prerequisites

### Installing PowerShell 7+

PowerShell 7+ (pwsh) is required. Windows PowerShell 5.1 is NOT supported.

**Windows:**
```powershell
# Using winget
winget install Microsoft.PowerShell

# Or download from GitHub
# https://github.com/PowerShell/PowerShell/releases
```

**macOS:**
```bash
brew install powershell/tap/powershell
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install -y powershell
```

**Verify Installation:**
```bash
pwsh --version
# Should output: PowerShell 7.x.x
```

### Execution Policy (Windows)

Windows restricts script execution by default:

```powershell
# Check current policy
Get-ExecutionPolicy

# Enable script execution (run as admin or for current user)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Installing Pester (for tests)

```powershell
Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck -Scope CurrentUser
```

## Quick Start

```powershell
# 1. Clone/setup ralph
New-Item -ItemType Directory -Path scripts -Force
Set-Location scripts
git clone https://github.com/RobinOppenstam/claude-ralph ralph
Set-Location ..

# 2. Create PRD
Copy-Item ./scripts/ralph/prd.json.example ./scripts/ralph/prd.json
# Edit prd.json with your stories

# 3. Run Ralph
pwsh ./scripts/ralph/ralph.ps1 -MaxIterations 10
```

## Script Reference

All Bash scripts have PowerShell equivalents:

| Bash Script | PowerShell Script | Purpose |
|-------------|-------------------|---------|
| `ralph.sh` | `ralph.ps1` | Main loop |
| `ralph-once.sh` | `ralph-once.ps1` | Single iteration |
| `ralph-parallel.sh` | `ralph-parallel.ps1` | Parallel execution |
| `ralph-status.sh` | `ralph-status.ps1` | Status check |
| `ralph-dashboard.sh` | `ralph-dashboard.ps1` | TUI dashboard |
| `ralph-cleanup.sh` | `ralph-cleanup.ps1` | Instance cleanup |
| `ralph-locks.sh` | `ralph-locks.ps1` | Lock management |
| `ralph-queue.sh` | `ralph-queue.ps1` | Queue management |
| `install-skills.sh` | `install-skills.ps1` | Skill installer |

### Invoking Scripts

Always use `pwsh` to invoke scripts:

```powershell
# Correct
pwsh ./scripts/ralph/ralph.ps1 -MaxIterations 10

# Also correct (if in PowerShell session)
./scripts/ralph/ralph.ps1 -MaxIterations 10

# NOT recommended (may use Windows PowerShell 5.1)
powershell ./scripts/ralph/ralph.ps1
```

## Common Operations

### Running Ralph

```powershell
# Basic run
pwsh ./scripts/ralph/ralph.ps1

# With max iterations
pwsh ./scripts/ralph/ralph.ps1 -MaxIterations 10
pwsh ./scripts/ralph/ralph.ps1 -m 10  # Short form

# Single iteration (no loop)
pwsh ./scripts/ralph/ralph-once.ps1
```

### Parallel Execution

```powershell
# Start 3 instances
pwsh ./scripts/ralph/ralph-parallel.ps1 Start -Count 3 -MaxIterations 10

# Check status
pwsh ./scripts/ralph/ralph-parallel.ps1 Status

# Open dashboard
pwsh ./scripts/ralph/ralph-parallel.ps1 Dashboard

# Stop all
pwsh ./scripts/ralph/ralph-parallel.ps1 Stop
```

### Lock Management

```powershell
# View locks
pwsh ./scripts/ralph/ralph-locks.ps1 Status

# Release a lock
pwsh ./scripts/ralph/ralph-locks.ps1 Release -StoryId US-001

# Release all
pwsh ./scripts/ralph/ralph-locks.ps1 ReleaseAll

# Cleanup stale
pwsh ./scripts/ralph/ralph-locks.ps1 Cleanup
```

### Instance Cleanup

```powershell
# Remove dead instances
pwsh ./scripts/ralph/ralph-cleanup.ps1 -Dead

# Remove old instances (>7 days)
pwsh ./scripts/ralph/ralph-cleanup.ps1 -Old

# Remove terminated instances
pwsh ./scripts/ralph/ralph-cleanup.ps1 -Terminated

# Remove all non-running
pwsh ./scripts/ralph/ralph-cleanup.ps1 -All

# Dry run (preview)
pwsh ./scripts/ralph/ralph-cleanup.ps1 -Dead -WhatIf
```

### Queue Management

```powershell
# Add to queue
pwsh ./scripts/ralph/ralph-queue.ps1 Add -Prd /path/to/prd.json -ProjectRoot /path/to/project

# List queue
pwsh ./scripts/ralph/ralph-queue.ps1 List
pwsh ./scripts/ralph/ralph-queue.ps1 List -Status pending

# Queue status
pwsh ./scripts/ralph/ralph-queue.ps1 Status

# Start workers
pwsh ./scripts/ralph/ralph-queue.ps1 Start -Count 3 -MaxIterations 10
```

## RalphUtils Module

The `RalphUtils.psm1` module provides shared functions:

### Importing the Module

```powershell
Import-Module ./scripts/ralph/RalphUtils.psm1 -Force
```

### Key Functions

```powershell
# Instance ID
$id = Get-RalphInstanceId
$shortId = Get-RalphShortId

# Create instance directory
$vars = New-RalphInstanceDirectory
# Returns hashtable with InstanceDir, LogFile, etc.

# Update status
Update-RalphStatus -State "working" -CurrentStory "US-001" -Iteration 3

# Locking
$locked = Lock-RalphStory -StoryId "US-001"
$isLocked = Test-RalphStoryLocked -StoryId "US-001"
Unlock-RalphStory -StoryId "US-001"

# PRD operations
$prd = Read-RalphPrdSafe
Update-RalphPrd -ScriptBlock { param($prd) $prd.userStories[0].passes = $true; $prd }

# Story claiming
$story = Get-RalphNextStory
$claimed = Request-RalphStoryClaim -StoryId "US-001"
Release-RalphStoryClaim -StoryId "US-001"

# Cleanup
$cleared = Clear-RalphStaleLocks
$released = Clear-RalphInstanceLocks
```

## Running Tests

### All Tests

```powershell
# Run all Pester tests
pwsh -Command "Invoke-Pester ./scripts/ralph/tests/ -Output Detailed"

# With code coverage
pwsh -Command "Invoke-Pester ./scripts/ralph/tests/ -CodeCoverage ./scripts/ralph/*.ps1"
```

### Individual Test Files

```powershell
# Core module tests
Invoke-Pester ./scripts/ralph/tests/RalphUtils.Tests.ps1 -Output Detailed

# Main script tests
Invoke-Pester ./scripts/ralph/tests/ralph.Tests.ps1 -Output Detailed

# Multi-instance tests (comprehensive)
Invoke-Pester ./scripts/ralph/tests/RalphMultiInstance.Tests.ps1 -Output Detailed

# Script tests
Invoke-Pester ./scripts/ralph/tests/RalphScripts.Tests.ps1 -Output Detailed

# Cross-platform tests
pwsh ./scripts/ralph/tests/test-cross-platform.ps1
```

### Test Coverage

Current test coverage:
- `RalphUtils.Tests.ps1`: Core module functions
- `RalphMultiInstance.Tests.ps1`: Multi-instance locking, claiming, cleanup
- `RalphScripts.Tests.ps1`: All script commands
- `ralph.Tests.ps1`: Main loop script
- `test-cross-platform.ps1`: Bash/PowerShell interoperability

## Troubleshooting

### "cannot be loaded because running scripts is disabled"

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "The term 'pwsh' is not recognized"

PowerShell 7+ is not installed. Install from:
- https://github.com/PowerShell/PowerShell/releases
- Or use package manager (winget, brew, apt)

### "Module 'Pester' not found"

```powershell
Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck -Scope CurrentUser
```

### "Module 'RalphUtils' not found"

Run scripts from the project root directory. Scripts use `$PSScriptRoot` to find modules.

### "Access denied" or permission errors

- Windows: Run as administrator or check folder permissions
- Linux/macOS: Check file permissions with `ls -la`

### Tests fail with JSON parsing errors

Ensure jq is installed for Bash tests. PowerShell uses native `ConvertFrom-Json`.

### "Import-Module: The names of some imported commands include unapproved verbs"

This warning is safe to ignore. Ralph uses verb names like `Lock-` and `Unlock-` which are not in PowerShell's approved verb list but are more descriptive for locking operations.

To suppress:
```powershell
Import-Module ./scripts/ralph/RalphUtils.psm1 -WarningAction SilentlyContinue
```

## Platform Differences

### Windows vs Linux/macOS

| Feature | Windows | Linux/macOS |
|---------|---------|-------------|
| flock | Not available | Available |
| PRD locking | .NET Mutex | flock + Mutex |
| Line endings | CRLF | LF |
| Path separator | \ | / |

### jq Output on Windows

Git Bash jq may output CRLF line endings. Ralph handles this with `tr -d '\r'` in Bash functions.

### Atomic Operations

Both platforms use:
- Atomic directory creation for story locks
- .NET Mutex for cross-process PRD locking
- JSON file writes with backup

## Best Practices

1. **Always use `pwsh`** - Not `powershell` (which is Windows PowerShell 5.1)

2. **Run from project root** - Scripts use relative paths

3. **Use parameter names** - More readable:
   ```powershell
   # Good
   pwsh ./ralph-parallel.ps1 Start -Count 3 -MaxIterations 10

   # Less clear
   pwsh ./ralph-parallel.ps1 Start -c 3 -m 10
   ```

4. **Check status before running** - Verify no stuck instances:
   ```powershell
   pwsh ./ralph-parallel.ps1 Status
   pwsh ./ralph-locks.ps1 Status
   ```

5. **Clean up periodically** - Remove dead/old instances:
   ```powershell
   pwsh ./ralph-cleanup.ps1 -All
   ```

6. **Use -WhatIf for dangerous operations**:
   ```powershell
   pwsh ./ralph-cleanup.ps1 -All -WhatIf
   ```
