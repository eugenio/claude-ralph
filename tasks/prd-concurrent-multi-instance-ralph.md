# PRD: Concurrent Multi-Instance Ralph

## Overview

Enable multiple Ralph instances to run simultaneously in the same repository (parallel story execution) or across different repositories, with proper isolation, automatic work distribution, conflict resolution via feature branches, and a TUI dashboard for monitoring.

## Problem Statement

Currently, Ralph operates as a single-instance process with shared state files (prd.json, progress.txt, ralph.log). When multiple instances run concurrently:
- Race conditions corrupt the PRD file when multiple instances update story status
- Log files become interleaved and unreadable
- Git commits conflict when instances work on the same branch
- No visibility into which instance is working on what
- No coordination mechanism for work distribution

This limits throughput and prevents efficient parallel development workflows.

## Target Users

1. **Power users** running Ralph on multiple projects simultaneously
2. **Teams** wanting to parallelize story implementation within a single PRD
3. **CI/CD pipelines** that spawn multiple Ralph workers for faster feature development

## Goals & Success Metrics

- **Goal 1**: Enable 3+ Ralph instances to work on different stories in the same repo without conflicts
- **Goal 2**: Enable unlimited Ralph instances across different repos with full isolation
- **Goal 3**: Provide real-time visibility into all running instances via TUI dashboard
- **Goal 4**: Zero data corruption or lost work due to race conditions
- **Goal 5**: Automatic recovery when an instance crashes mid-story

## User Stories

### US-001: Instance Identification System
**As a** Ralph user
**I want** each Ralph instance to have a unique identifier
**So that** I can track and distinguish between concurrent instances

**Acceptance Criteria:**
- [ ] Generate unique instance ID at startup: `{user}-{hostname}-{pid}-{timestamp}`
- [ ] Instance ID is logged in all output
- [ ] Instance ID is stored in instance-specific directory
- [ ] Instance can be referenced by short ID (first 8 chars) for convenience

**Priority:** High
**Estimate:** S

---

### US-002: Instance Workspace Isolation
**As a** Ralph user
**I want** each instance to have its own isolated workspace
**So that** log files and progress tracking don't conflict

**Acceptance Criteria:**
- [ ] Create `instances/{instance-id}/` directory for each instance
- [ ] Instance-specific files: `ralph.log`, `progress.txt`, `status.json`
- [ ] Shared files remain in ralph directory: `prd.json` (with locking)
- [ ] Cleanup old instance directories after configurable TTL (default 7 days)
- [ ] `ralph-cleanup.sh` script to manually purge old instances

**Priority:** High
**Estimate:** S

---

### US-003: Story Locking Mechanism
**As a** Ralph instance
**I want** to claim exclusive ownership of a story before working on it
**So that** no other instance works on the same story simultaneously

**Acceptance Criteria:**
- [ ] Create `locks/` directory for story locks
- [ ] Atomic lock acquisition using `mkdir` (POSIX atomic operation)
- [ ] Lock file contains: owner instance ID, timestamp, story ID
- [ ] Lock is released when story completes or instance exits
- [ ] Stale lock detection: locks older than 2 hours can be force-released
- [ ] `ralph-locks.sh status` shows current locks
- [ ] `ralph-locks.sh release {story-id}` forces lock release

**Priority:** High
**Estimate:** M

---

### US-004: Automatic Story Claiming
**As a** Ralph instance
**I want** to automatically claim the next available unclaimed story
**So that** work is distributed without manual intervention

**Acceptance Criteria:**
- [ ] On each iteration, scan PRD for unclaimed incomplete stories
- [ ] Skip stories that are locked by other instances
- [ ] Claim story by priority order (lowest priority number first)
- [ ] If no stories available, wait and retry with backoff
- [ ] Log which story was claimed and by which instance
- [ ] Update PRD with `claimedBy` field when story is claimed

**Priority:** High
**Estimate:** M

---

### US-005: PRD Atomic Updates
**As a** Ralph system
**I want** PRD file updates to be atomic and conflict-free
**So that** concurrent instances don't corrupt the shared state

**Acceptance Criteria:**
- [ ] Use `flock` for exclusive file locking during PRD updates
- [ ] Read-modify-write pattern with lock held
- [ ] Timeout on lock acquisition (5 seconds) with retry
- [ ] Validate JSON integrity after write
- [ ] Backup PRD before each modification (`prd.json.bak`)
- [ ] Log all PRD modifications with instance ID and change description

**Priority:** High
**Estimate:** M

---

### US-006: Feature Branch Isolation
**As a** Ralph instance
**I want** to work on my own feature branch for each story
**So that** git commits don't conflict with other instances

**Acceptance Criteria:**
- [ ] Create branch `ralph/{instance-short-id}/{story-id}` when claiming story
- [ ] All commits go to instance-specific branch
- [ ] On story completion, merge to main ralph branch (or create PR)
- [ ] Handle merge conflicts by rebasing before merge
- [ ] Option to use git worktrees for full filesystem isolation
- [ ] Clean up merged branches automatically

**Priority:** High
**Estimate:** M

---

### US-007: Instance Status Tracking
**As a** Ralph user
**I want** each instance to maintain a status file
**So that** monitoring tools can track progress

**Acceptance Criteria:**
- [ ] `instances/{id}/status.json` updated every 30 seconds
- [ ] Status includes: instance ID, current story, iteration, start time, last activity
- [ ] Status includes: stories completed, stories failed, current state (idle/working/blocked)
- [ ] Heartbeat timestamp for detecting dead instances
- [ ] Status file is valid JSON at all times (atomic writes)

**Priority:** Medium
**Estimate:** S

---

### US-008: TUI Dashboard - Basic Display
**As a** Ralph user
**I want** a terminal dashboard showing all running instances
**So that** I can monitor parallel execution in real-time

**Acceptance Criteria:**
- [ ] `ralph-dashboard.sh` launches TUI using `dialog` or pure bash
- [ ] Display table: Instance ID | Story | Status | Iteration | Runtime
- [ ] Auto-refresh every 2 seconds
- [ ] Color coding: green=working, yellow=idle, red=error
- [ ] Show overall PRD progress bar
- [ ] Exit with 'q' key

**Priority:** Medium
**Estimate:** M

---

### US-009: TUI Dashboard - Instance Details
**As a** Ralph user
**I want** to drill down into a specific instance
**So that** I can see detailed logs and status

**Acceptance Criteria:**
- [ ] Arrow keys to select instance in dashboard
- [ ] Enter key shows instance detail view
- [ ] Detail view shows: last 20 log lines, current story details, branch info
- [ ] 'l' key opens full log in less/tail
- [ ] 'b' key shows git branch status
- [ ] ESC returns to main dashboard

**Priority:** Medium
**Estimate:** M

---

### US-010: Multi-Repo Support
**As a** Ralph user
**I want** to run Ralph on multiple different repositories
**So that** I can work on several projects simultaneously

**Acceptance Criteria:**
- [ ] Global lock directory: `/tmp/ralph-global/` or `~/.ralph/`
- [ ] Repo-specific namespace using repo path hash
- [ ] Dashboard can show instances across all repos
- [ ] `ralph-dashboard.sh --all` shows all repos
- [ ] `ralph-dashboard.sh --repo /path/to/repo` filters to one repo
- [ ] No interference between repos even with same story IDs

**Priority:** Medium
**Estimate:** M

---

### US-011: Graceful Shutdown
**As a** Ralph instance
**I want** to clean up properly when terminated
**So that** locks are released and state is consistent

**Acceptance Criteria:**
- [ ] Trap SIGINT, SIGTERM, SIGHUP signals
- [ ] On shutdown: release all held locks
- [ ] On shutdown: update status to "terminated"
- [ ] On shutdown: commit or stash any uncommitted changes
- [ ] On shutdown: log clean termination message
- [ ] Other instances detect termination within 60 seconds

**Priority:** Medium
**Estimate:** S

---

### US-012: Dead Instance Detection
**As a** Ralph system
**I want** to detect and clean up dead instances
**So that** stuck locks don't block progress

**Acceptance Criteria:**
- [ ] Heartbeat check: instance dead if no update in 5 minutes
- [ ] Dead instance locks are automatically released
- [ ] Dead instance stories are marked as unclaimed
- [ ] Warning logged when dead instance detected
- [ ] `ralph-cleanup.sh --dead` removes dead instance data
- [ ] Dashboard shows dead instances in gray/strikethrough

**Priority:** Medium
**Estimate:** S

---

### US-013: Parallel Launch Script
**As a** Ralph user
**I want** a script to launch multiple instances at once
**So that** I can easily start parallel execution

**Acceptance Criteria:**
- [ ] `ralph-parallel.sh {count}` launches N instances
- [ ] Each instance runs in background with output to its log
- [ ] PIDs are tracked in `instances/running.pid`
- [ ] `ralph-parallel.sh stop` gracefully stops all instances
- [ ] `ralph-parallel.sh status` shows running instance count
- [ ] Respects system resources (CPU count awareness)

**Priority:** Low
**Estimate:** S

---

### US-014: Merge Queue
**As a** Ralph system
**I want** completed stories to be merged in order
**So that** the git history remains clean and linear

**Acceptance Criteria:**
- [ ] Completed stories queue for merge by completion time
- [ ] Merge process runs sequentially (one at a time)
- [ ] Automatic rebase before merge if needed
- [ ] Failed merges are flagged for manual resolution
- [ ] Merge queue status visible in dashboard
- [ ] Option to auto-create PRs instead of direct merge

**Priority:** Low
**Estimate:** M

---

### US-015: Configuration File
**As a** Ralph user
**I want** configurable settings for multi-instance behavior
**So that** I can tune the system for my environment

**Acceptance Criteria:**
- [ ] `ralph.config.json` or environment variables
- [ ] Configurable: max instances per repo, lock timeout, heartbeat interval
- [ ] Configurable: cleanup TTL, merge strategy, dashboard refresh rate
- [ ] Configurable: branch naming pattern, worktree usage
- [ ] Defaults work out of the box (zero config required)
- [ ] Config validation on startup with helpful errors

**Priority:** Low
**Estimate:** S

---

### US-016: Documentation
**As a** Ralph user
**I want** documentation for multi-instance features
**So that** I can understand and use the new capabilities

**Acceptance Criteria:**
- [ ] README updated with multi-instance section
- [ ] New file: `docs/multi-instance.md` with detailed guide
- [ ] Architecture diagram showing component interaction
- [ ] Troubleshooting section for common issues
- [ ] Examples for: parallel launch, dashboard usage, lock management

**Priority:** Low
**Estimate:** S

## Technical Considerations

### Architecture
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

### File Locking Strategy
- **PRD file**: `flock` exclusive lock for read-modify-write
- **Story locks**: `mkdir` atomic directory creation (POSIX portable)
- **Status files**: Atomic write via temp file + rename

### Git Strategy
- Each instance creates branch: `ralph/{short-id}/{story-id}`
- Work committed to instance branch
- On completion, merge to main ralph branch with `--no-ff`
- Merge conflicts resolved by rebasing instance branch

### Dependencies
- `jq` - JSON processing
- `flock` - File locking (part of util-linux)
- `dialog` or `whiptail` - TUI dashboard (optional, fallback to plain text)
- Standard POSIX utilities: mkdir, rm, cat, grep, etc.

## Out of Scope

- GUI/web dashboard (TUI only for v1)
- Distributed execution across multiple machines
- Cloud-based coordination (Redis, etc.)
- Automatic scaling based on workload
- Story dependency graph resolution (handled by priority order)

## Dependencies

- Existing ralph.sh infrastructure
- Claude Code CLI
- Git repository with initialized ralph setup

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Lock deadlocks | High | Timeout + stale lock detection |
| PRD corruption | High | flock + JSON validation + backups |
| Git merge conflicts | Medium | Feature branches + rebase strategy |
| Resource exhaustion | Medium | Max instance limits + CPU awareness |
| Claude API rate limits | Medium | Backoff between instances |

## Timeline

Phase 1 (Core): US-001 through US-006 - Instance isolation and locking
Phase 2 (Monitoring): US-007 through US-009 - Status tracking and dashboard
Phase 3 (Polish): US-010 through US-016 - Multi-repo, cleanup, docs
