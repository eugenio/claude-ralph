# Ralph Multi-Instance Guide

This guide explains how to run multiple Ralph instances in parallel to speed up PRD completion.

## Overview

Ralph supports running multiple instances simultaneously, each working on different stories. This is useful for:

- Large PRDs with many independent stories
- Maximizing hardware utilization
- Reducing total completion time

## How It Works

Each instance:
1. Generates a unique instance ID: `{user}-{hostname}-{pid}-{timestamp}`
2. Creates its own instance directory in `instances/`
3. Maintains a `status.json` file with heartbeat
4. Uses file-based locking to claim stories atomically
5. Works on one story at a time

## Starting Parallel Instances

### Using Bash

```bash
# Start 3 instances, each with max 10 iterations
./scripts/ralph/ralph-parallel.sh start -c 3 -m 10

# Start with custom PRD and project root
./scripts/ralph/ralph-parallel.sh start -p /path/to/prd.json -r /path/to/project -c 3

# Check status
./scripts/ralph/ralph-parallel.sh status

# Open dashboard
./scripts/ralph/ralph-parallel.sh dashboard

# Stop gracefully
./scripts/ralph/ralph-parallel.sh stop

# Force kill
./scripts/ralph/ralph-parallel.sh kill
```

### Using PowerShell

```powershell
# Start 3 instances, each with max 10 iterations
pwsh ./scripts/ralph/ralph-parallel.ps1 Start -Count 3 -MaxIterations 10

# Start with custom PRD and project root
pwsh ./scripts/ralph/ralph-parallel.ps1 Start -Prd /path/to/prd.json -ProjectRoot /path/to/project -Count 3

# Check status
pwsh ./scripts/ralph/ralph-parallel.ps1 Status

# Open dashboard
pwsh ./scripts/ralph/ralph-parallel.ps1 Dashboard

# Stop gracefully
pwsh ./scripts/ralph/ralph-parallel.ps1 Stop

# Force kill
pwsh ./scripts/ralph/ralph-parallel.ps1 Kill
```

## Instance Directory Structure

Each instance creates a directory under `instances/`:

```
instances/
└── user-hostname-12345-1706745600/
    ├── status.json       # Current state and heartbeat
    ├── ralph.log         # Instance-specific log
    └── progress.txt      # Instance-specific progress
```

### status.json Format

```json
{
  "instanceId": "user-hostname-12345-1706745600",
  "shortId": "user-hos",
  "state": "working",
  "currentStory": "US-001",
  "iteration": 3,
  "maxIterations": 10,
  "lastMessage": "Working on US-001",
  "startTimeEpoch": 1706745600,
  "lastHeartbeatEpoch": 1706745900
}
```

**State Values:**
- `starting` - Instance initializing
- `waiting` - Looking for available story
- `working` - Actively processing a story
- `idle` - No stories available
- `completed` - All stories done
- `terminated` - Gracefully stopped
- `error` - Error occurred

## Story Locking

Ralph uses atomic directory creation for story locks:

```
locks/
└── US-001.lock/
    ├── owner.txt       # Instance ID that holds the lock
    ├── timestamp.txt   # When lock was acquired
    └── pid.txt         # Process ID
```

### Lock Operations

**Bash:**
```bash
# View lock status
./scripts/ralph/ralph-locks.sh status

# Release a specific lock
./scripts/ralph/ralph-locks.sh release US-001

# Release all locks
./scripts/ralph/ralph-locks.sh release-all

# Clean up stale locks (>2 hours)
./scripts/ralph/ralph-locks.sh cleanup
```

**PowerShell:**
```powershell
# View lock status
pwsh ./scripts/ralph/ralph-locks.ps1 Status

# Release a specific lock
pwsh ./scripts/ralph/ralph-locks.ps1 Release -StoryId US-001

# Release all locks
pwsh ./scripts/ralph/ralph-locks.ps1 ReleaseAll

# Clean up stale locks
pwsh ./scripts/ralph/ralph-locks.ps1 Cleanup
```

## PRD Claiming

When an instance claims a story, it:
1. Acquires the story lock (atomic directory creation)
2. Updates `prd.json` with `claimedBy: instance-id`
3. Works on the story
4. On completion: releases lock, sets `passes: true`, clears `claimedBy`

### PRD Fields for Multi-Instance

```json
{
  "userStories": [
    {
      "id": "US-001",
      "title": "Story Title",
      "passes": false,
      "priority": 1,
      "claimedBy": "user-hostname-12345-1706745600"
    }
  ]
}
```

## Monitoring

### Dashboard

The dashboard provides real-time monitoring:

**Bash:**
```bash
./scripts/ralph/ralph-dashboard.sh
```

**PowerShell:**
```powershell
pwsh ./scripts/ralph/ralph-dashboard.ps1
```

Dashboard shows:
- Instance table: ID, Story, Status, Iteration, Runtime
- PRD progress bar
- Active locks
- Color coding: green=working, yellow=idle, red=error, gray=dead

### Status Check

**Bash:**
```bash
./scripts/ralph/ralph-status.sh
```

**PowerShell:**
```powershell
pwsh ./scripts/ralph/ralph-status.ps1
```

## Cleanup

Dead or old instances should be cleaned up:

**Bash:**
```bash
# Remove dead instances (no heartbeat > 5 min)
./scripts/ralph/ralph-cleanup.sh --dead

# Remove old instances (> 7 days)
./scripts/ralph/ralph-cleanup.sh --old

# Remove all non-running instances
./scripts/ralph/ralph-cleanup.sh --all

# Dry run (show what would be removed)
./scripts/ralph/ralph-cleanup.sh --dead --dry-run
```

**PowerShell:**
```powershell
# Remove dead instances
pwsh ./scripts/ralph/ralph-cleanup.ps1 -Dead

# Remove old instances
pwsh ./scripts/ralph/ralph-cleanup.ps1 -Old

# Remove all non-running instances
pwsh ./scripts/ralph/ralph-cleanup.ps1 -All

# Dry run
pwsh ./scripts/ralph/ralph-cleanup.ps1 -Dead -WhatIf
```

## Environment Variables

```bash
# Maximum parallel instances (default: 8)
export RALPH_MAX_INSTANCES=4

# Lock timeout in seconds (default: 7200)
export RALPH_LOCK_TIMEOUT=3600

# Cleanup TTL in days (default: 7)
export RALPH_CLEANUP_TTL=14

# Disable global registry
export RALPH_GLOBAL_DISABLE=1

# Enable debug logging
export RALPH_DEBUG=1
```

## Troubleshooting

### Instances Stuck in "waiting" State

All incomplete stories may have stale `claimedBy` values:

```bash
# Check claims
cat scripts/ralph/prd.json | jq '.userStories[] | select(.passes == false) | {id, claimedBy}'

# Clear all claims
jq '.userStories |= map(.claimedBy = null)' scripts/ralph/prd.json > /tmp/prd-clean.json && mv /tmp/prd-clean.json scripts/ralph/prd.json

# Clear stale locks
./scripts/ralph/ralph-locks.sh cleanup
```

### Lock Conflicts

If two instances seem to work on the same story:

1. Check lock status: `./scripts/ralph/ralph-locks.sh status`
2. Clear the conflicting lock
3. Clear the `claimedBy` field in PRD

### Instance Won't Start

Check for:
- PRD file exists and is valid JSON
- Enough unclaimed stories available
- No permission issues in instance directory

### Dashboard Shows "Dead" Instances

Dead instances have no heartbeat for >5 minutes. Clean up with:

```bash
./scripts/ralph/ralph-cleanup.sh --dead
```

## Platform Notes

### Windows (Git Bash)
- `flock` is not available; uses atomic directory creation only
- jq output may include carriage returns (handled automatically)

### Linux/macOS
- `flock` is available for additional PRD locking
- Native file locking supported

### Cross-Platform Compatibility
- Lock format is identical across platforms
- status.json format is identical
- Bash and PowerShell can work in the same project
