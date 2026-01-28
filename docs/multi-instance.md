# Multi-Instance Ralph Guide

This guide covers running multiple Ralph instances concurrently for parallel story execution.

## Overview

Multi-instance Ralph allows you to:
- Run multiple instances on the same PRD, each working on different stories
- Run instances across different repositories simultaneously
- Monitor all instances via a TUI dashboard
- Automatically handle lock conflicts and dead instance recovery

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     ralph-dashboard.sh                       │
│  - Reads status.json from all instances                     │
│  - Displays TUI with instance status                        │
└─────────────────────┬───────────────────────────────────────┘
                      │ reads
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│  Instance 1  │ │  Instance 2  │ │  Instance 3  │
│  ralph.sh    │ │  ralph.sh    │ │  ralph.sh    │
│  ID: abc123  │ │  ID: def456  │ │  ID: ghi789  │
└──────┬───────┘ └──────┬───────┘ └──────┬───────┘
       │                │                │
       └────────────────┼────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                     Shared Resources                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │ prd.json    │  │ locks/      │  │ instances/  │          │
│  │ (flock)     │  │ US-001.lock/│  │ abc123/     │          │
│  │             │  │ US-002.lock/│  │ def456/     │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Launch Multiple Instances

**Bash:**
```bash
# Launch 3 instances in parallel
./ralph-parallel.sh 3

# Or launch with custom iteration count
RALPH_ITERATIONS=20 ./ralph-parallel.sh 3
```

**PowerShell:**
```powershell
# Launch 3 instances in parallel
./scripts/ralph/ralph-parallel.ps1 Start -Count 3

# Or launch with custom iterations
./scripts/ralph/ralph-parallel.ps1 Start -Count 3 -MaxIterations 20
```

### Monitor Progress

**Bash:**
```bash
# Launch the dashboard
./ralph-dashboard.sh

# Or check status quickly
./ralph-parallel.sh status
```

**PowerShell:**
```powershell
# Launch the dashboard
./scripts/ralph/ralph-dashboard.ps1

# Or check status quickly
./scripts/ralph/ralph-parallel.ps1 Status
```

### Stop All Instances

**Bash:**
```bash
# Graceful stop (SIGTERM)
./ralph-parallel.sh stop

# Force kill (SIGKILL)
./ralph-parallel.sh kill
```

**PowerShell:**
```powershell
# Graceful stop
./scripts/ralph/ralph-parallel.ps1 Stop

# Force kill
./scripts/ralph/ralph-parallel.ps1 Kill
```

## How It Works

### Instance Identification

Each instance gets a unique ID:
```
{username}-{hostname}-{pid}-{timestamp}
```

Example: `alice-macbook-12345-1700000000`

The first 8 characters form the "short ID" used in logs and branch names.

### Story Locking

Before working on a story, an instance must acquire a lock:

1. Attempts atomic `mkdir locks/{story-id}.lock/`
2. If successful, writes owner ID and timestamp
3. If failed, story is already claimed - try next story

Locks are automatically released when:
- Story completes successfully
- Instance exits (graceful shutdown)
- Lock becomes stale (>2 hours old)
- Owner instance is detected as dead (no heartbeat >5 min)

### Feature Branches

Each instance works on its own branch:
```
ralph/{short-id}/{story-id}
```

Example: `ralph/abc12345/US-001`

On story completion, the branch is merged to the main ralph branch with `--no-ff`.

### PRD Synchronization

The shared `prd.json` is protected with `flock`:
- Read operations use shared locks
- Write operations use exclusive locks
- 5-second timeout with 3 retries
- Automatic backup before modifications

## Commands Reference

### ralph.sh / ralph.ps1

The main script, now multi-instance aware.

**Bash:**
```bash
./ralph.sh [max_iterations]
```

**PowerShell:**
```powershell
./scripts/ralph/ralph.ps1 -MaxIterations 10
```

Environment variables:
- `RALPH_DEBUG=1` - Enable debug logging
- `RALPH_LOCK_TIMEOUT=7200` - Lock timeout in seconds (default: 2 hours)
- `RALPH_CLEANUP_TTL=7` - Days to keep old instances (default: 7)

### ralph-parallel.sh / ralph-parallel.ps1

Launch and manage multiple instances.

**Bash:**
```bash
./ralph-parallel.sh 3           # Launch 3 instances
./ralph-parallel.sh stop        # Stop all instances
./ralph-parallel.sh kill        # Force kill all
./ralph-parallel.sh status      # Show running instances
./ralph-parallel.sh dashboard   # Open dashboard
```

**PowerShell:**
```powershell
./scripts/ralph/ralph-parallel.ps1 Start -Count 3
./scripts/ralph/ralph-parallel.ps1 Stop
./scripts/ralph/ralph-parallel.ps1 Kill
./scripts/ralph/ralph-parallel.ps1 Status
./scripts/ralph/ralph-parallel.ps1 Dashboard
```

Environment variables:
- `RALPH_MAX_INSTANCES=8` - Maximum instances allowed
- `RALPH_ITERATIONS=10` - Iterations per instance

### ralph-dashboard.sh / ralph-dashboard.ps1

TUI dashboard for monitoring.

**Bash:**
```bash
./ralph-dashboard.sh            # Default view
./ralph-dashboard.sh --refresh 5  # Custom refresh interval
```

**PowerShell:**
```powershell
./scripts/ralph/ralph-dashboard.ps1
./scripts/ralph/ralph-dashboard.ps1 -RefreshInterval 5
```

Keys:
- `q` - Quit
- `r` - Force refresh
- `l` - Show lock details
- `c` - Cleanup dead instances

### ralph-locks.sh / ralph-locks.ps1

Manage story locks.

**Bash:**
```bash
./ralph-locks.sh status         # Show all locks
./ralph-locks.sh release US-001 # Force release a lock
./ralph-locks.sh release-all    # Release all locks
./ralph-locks.sh cleanup        # Remove stale locks
```

**PowerShell:**
```powershell
./scripts/ralph/ralph-locks.ps1 Status
./scripts/ralph/ralph-locks.ps1 Release -StoryId US-001
./scripts/ralph/ralph-locks.ps1 ReleaseAll
./scripts/ralph/ralph-locks.ps1 Cleanup
```

### ralph-cleanup.sh / ralph-cleanup.ps1

Clean up old data.

**Bash:**
```bash
./ralph-cleanup.sh              # Show summary
./ralph-cleanup.sh --dead       # Clean dead instances
./ralph-cleanup.sh --old        # Clean old instances (>7 days)
./ralph-cleanup.sh --all        # Clean both
./ralph-cleanup.sh --dry-run    # Preview without deleting
```

**PowerShell:**
```powershell
./scripts/ralph/ralph-cleanup.ps1          # Show summary
./scripts/ralph/ralph-cleanup.ps1 -Dead    # Clean dead instances
./scripts/ralph/ralph-cleanup.ps1 -Old     # Clean old instances
./scripts/ralph/ralph-cleanup.ps1 -All     # Clean both
./scripts/ralph/ralph-cleanup.ps1 -WhatIf  # Preview without deleting
```

## Directory Structure

```
.claude/ralph/
├── prd.json              # Shared PRD (with flock protection)
├── prd.json.bak          # Backup before modifications
├── .prd.lock             # flock file for PRD
├── prompt.md             # Claude prompt template
├── instances/            # Per-instance data
│   ├── {instance-id}/
│   │   ├── ralph.log     # Instance-specific log
│   │   ├── progress.txt  # Instance progress notes
│   │   └── status.json   # Current status (heartbeat)
│   └── running.pids      # PIDs from ralph-parallel.sh
├── locks/                # Story locks
│   └── {story-id}.lock/
│       ├── owner         # Instance ID holding lock
│       ├── timestamp     # When lock was acquired
│       └── pid           # Process ID
└── archive/              # Archived runs
```

## Status JSON Format

Each instance maintains `instances/{id}/status.json`:

```json
{
  "instanceId": "alice-macbook-12345-1700000000",
  "shortId": "alice-ma",
  "state": "working",
  "currentStory": "US-001",
  "iteration": 3,
  "maxIterations": 10,
  "startTime": "2024-01-01 12:00:00",
  "lastHeartbeat": "2024-01-01 12:15:00",
  "lastHeartbeatEpoch": 1700001234,
  "projectRoot": "/path/to/project",
  "branch": "ralph/alice-ma/US-001",
  "pid": 12345
}
```

States:
- `starting` - Instance initializing
- `idle` - Between iterations
- `claiming` - Trying to claim a story
- `working` - Running Claude on a story
- `merging` - Merging completed story
- `completed` - All stories done
- `terminated` - Graceful shutdown
- `max_iterations` - Hit iteration limit

## Troubleshooting

### Stuck Locks

If a lock appears stuck:

```bash
# Check lock status
./ralph-locks.sh status

# If owner is dead, cleanup will remove it
./ralph-locks.sh cleanup

# Or force release
./ralph-locks.sh release US-001
```

### Dead Instances

Dead instances (no heartbeat >5 min) are automatically detected:

```bash
# View dead instances
./ralph-cleanup.sh

# Clean them up
./ralph-cleanup.sh --dead
```

### PRD Corruption

If PRD gets corrupted:

```bash
# Restore from backup
cp prd.json.bak prd.json

# Validate JSON
jq empty prd.json
```

### Merge Conflicts

If a merge fails:

1. The instance will log the error
2. The feature branch is preserved
3. Manually resolve:
   ```bash
   git checkout ralph/concurrent-instances
   git merge ralph/{short-id}/{story-id}
   # Resolve conflicts
   git commit
   git branch -d ralph/{short-id}/{story-id}
   ```

### Too Many Instances

If system is overloaded:

```bash
# Stop all instances
./ralph-parallel.sh stop

# Launch fewer
./ralph-parallel.sh 2
```

## Best Practices

1. **Start Small** - Begin with 2-3 instances to test
2. **Monitor** - Use dashboard to watch for issues
3. **Clean Regularly** - Run cleanup weekly
4. **Check PRD** - Verify story dependencies don't conflict
5. **Backup** - PRD is automatically backed up, but consider git commits

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `RALPH_DEBUG` | 0 | Enable debug logging |
| `RALPH_LOCK_TIMEOUT` | 7200 | Lock timeout (seconds) |
| `RALPH_CLEANUP_TTL` | 7 | Days to keep old instances |
| `RALPH_MAX_INSTANCES` | 8 | Max parallel instances |
| `RALPH_ITERATIONS` | 10 | Iterations per instance |

## Cross-Platform Usage

Both Bash and PowerShell implementations share the same file formats, enabling mixed environments.

### Running Mixed Instances

```bash
# Terminal 1 - Bash instances
./ralph-parallel.sh 2

# Terminal 2 - PowerShell instances (runs alongside Bash)
pwsh -c "./scripts/ralph/ralph-parallel.ps1 Start -Count 2"
```

All instances will:
- Share the same PRD safely (mutex/flock protected)
- Use compatible lock directory format
- Write compatible status.json files
- Be visible in either dashboard

### Compatibility Notes

| Feature | Bash | PowerShell |
|---------|------|------------|
| PRD Locking | flock | .NET Mutex |
| Story Locks | mkdir atomic | mkdir atomic |
| Status JSON | Same format | Same format |
| Instance ID | Same format | Same format |
| Signal Handling | trap | Register-EngineEvent |

For detailed PowerShell usage, see [PowerShell Guide](./powershell-guide.md)
