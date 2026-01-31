<p align="center">
  <img src="https://github.com/RobinOppenstam/claude-ralph/releases/download/assets/banner.jpg" alt="claude-ralph" width="100%">
</p>

# claude-ralph

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Ship features while you sleep — using your Claude Pro or Max subscription.**

An autonomous AI agent loop that runs **Claude Code** repeatedly until all PRD items are complete. Drop in a PRD, run the loop, wake up to a finished feature branch.

This is a port of [snarktank/ralph](https://github.com/snarktank/ralph) for **Claude Code CLI**, so you can use your existing **Claude Max subscription** instead of Amp credits.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

## Why claude-ralph?

The original Ralph uses [Amp CLI](https://ampcode.com) which requires Amp credits. This port:

- ✅ Uses **Claude Code CLI** (`claude -p`)
- ✅ Works with your Claude Pro or Max subscription
- ✅ Same autonomous loop pattern
- ✅ Same PRD-driven workflow
- ✅ Includes browser verification for UI stories
- ✅ **Multi-instance support** - Run multiple instances concurrently on the same PRD
- ✅ **Cross-platform** - Full PowerShell 7+ support for Windows, macOS, and Linux

## Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed and authenticated
- `jq` installed (`brew install jq` on macOS, `apt install jq` on Linux)
- A git repository for your project
- Claude Max subscription (for token usage)
- [Playwright](https://playwright.dev) for UI verification (optional, for frontend stories)
- **PowerShell 7+** (optional, for cross-platform support) - [Install Guide](https://github.com/PowerShell/PowerShell/releases)

```bash
# Install Playwright for UI story verification
npm install -D playwright
npx playwright install chromium
```

## Installation

### Option 1: Per-Project Installation (Recommended)

Copy the ralph files to your project's scripts directory:

```bash
# From your project root
mkdir -p scripts
cd scripts
git clone https://github.com/RobinOppenstam/claude-ralph ralph
chmod +x ralph/*.sh
cd ..
```

All ralph files (`prd.json`, `progress.txt`, `ralph.log`) stay in `scripts/ralph/`, while your project files (`src/`, `package.json`, etc.) remain in the project root. This keeps ralph self-contained and your project organized.

The skills in `scripts/ralph/skills/` are available automatically when running ralph from your project directory.

### Option 2: Install Skills Globally

To use ralph skills (`prd`, `ralph`, `dev-browser`) across **all projects** in interactive Claude Code sessions:

```bash
# Quick install (recommended)
./scripts/ralph/install-skills.sh

# Or manually copy skills
mkdir -p ~/.claude/skills
cp -r scripts/ralph/skills/prd ~/.claude/skills/
cp -r scripts/ralph/skills/ralph ~/.claude/skills/
cp -r scripts/ralph/skills/dev-browser ~/.claude/skills/
```

Now you can use these skills in **any project** by loading them in Claude Code:

```bash
claude
# Then in the Claude conversation:
# "Load the prd skill and create a PRD for user authentication"
# "Load the ralph skill and convert tasks/prd-auth.md to prd.json"
# "Load the dev-browser skill and verify the login page"
```

**Note:** Global installation is optional. Skills work from `scripts/ralph/skills/` when running ralph autonomously.

## Workflow

### 1. Create a PRD (Interactive)

Use the PRD skill to generate a detailed requirements document. Start Claude Code interactively:

```bash
# From your project root
claude
```

Then in the Claude conversation, explicitly load the skill and request a PRD:

```
Load the prd skill and create a PRD for [your feature description]
```

**Example:**
```
Load the prd skill and create a PRD for user authentication with email and password
```

**Note:** If the skill doesn't load, make sure you've installed skills globally (see [Installation](#option-2-install-skills-globally)).

Claude will ask clarifying questions (framework, UI requirements, etc.). Answer them in the conversation. The skill saves output to `tasks/prd-[feature-name].md`.

### 2. Convert PRD to Ralph Format (if needed)

Use the Ralph skill to convert the markdown PRD to JSON. In the same Claude session (or start a new one with `claude`):

```
Load the ralph skill and convert tasks/prd-[feature-name].md to prd.json
```

**Example:**
```
Load the ralph skill and convert tasks/prd-user-authentication.md to prd.json
```

This creates `scripts/ralph/prd.json` with user stories structured for autonomous execution. Each story has a `passes: false` flag that Ralph will update.

Exit Claude (Ctrl+C or type `exit`).

### 3. Run Ralph (Autonomous)

Now Ralph takes over. From your terminal (not in Claude):

```bash
./scripts/ralph/ralph.sh [max_iterations]
```

**Example:**
```bash
./scripts/ralph/ralph.sh 10
```

Default is 10 iterations. Run this from your project root directory.

Ralph will autonomously:

1. Create a feature branch (from PRD `branchName`)
2. Pick the highest priority story where `passes: false`
3. Spawn a fresh Claude Code instance to implement that single story
4. Run quality checks (typecheck, tests)
5. Commit if checks pass
6. Update `prd.json` to mark story as `passes: true`
7. Append learnings to `progress.txt`
8. Repeat until all stories pass or max iterations reached

**Key difference:** Steps 1-2 are **interactive** (you guide Claude), Step 3 is **autonomous** (Ralph loops without you).

## Multi-Instance Support

Run multiple Ralph instances concurrently to parallelize story execution. Each instance claims and works on different stories simultaneously.

### Quick Start (Multi-Instance)

**Bash:**
```bash
# Launch 3 parallel instances
./ralph-parallel.sh 3

# Monitor with TUI dashboard
./ralph-dashboard.sh

# Stop all instances
./ralph-parallel.sh stop
```

**PowerShell:**
```powershell
# Launch 3 parallel instances
./scripts/ralph/ralph-parallel.ps1 Start -Count 3

# Monitor with TUI dashboard
./scripts/ralph/ralph-dashboard.ps1

# Stop all instances
./scripts/ralph/ralph-parallel.ps1 Stop
```

### How It Works

- Each instance gets a unique ID: `{username}-{hostname}-{pid}-{timestamp}`
- Stories are locked atomically before work begins (via `mkdir`)
- Instances work on separate feature branches: `ralph/{short-id}/{story-id}`
- PRD updates are protected with file locking (flock/mutex)
- Dead instances and stale locks are automatically detected and cleaned

See [Multi-Instance Guide](docs/multi-instance.md) for full documentation.

## Multi-Project Queue

Queue PRDs from multiple projects and process them with workers. Workers automatically pick up the next queued PRD when they complete their current work.

### Queue Management

**Bash:**
```bash
# Add PRDs to the queue
./scripts/ralph/ralph-queue.sh add -p /project1/prd.json -r /project1
./scripts/ralph/ralph-queue.sh add -p /project2/prd.json -r /project2 --priority 1

# Check if PRD is complete before adding
./scripts/ralph/ralph-queue.sh check -p /path/to/prd.json
./scripts/ralph/ralph-queue.sh check -p /path/to/prd.json -q  # Quiet mode (exits 0=complete, 1=incomplete)

# List and manage queue
./scripts/ralph/ralph-queue.sh list              # List all entries
./scripts/ralph/ralph-queue.sh list -s pending   # Filter by status
./scripts/ralph/ralph-queue.sh status            # Show summary
./scripts/ralph/ralph-queue.sh remove -i <id>    # Remove an entry
./scripts/ralph/ralph-queue.sh clear             # Clear completed entries

# Start workers to process queue
./scripts/ralph/ralph-queue.sh start -c 3 -m 10  # 3 workers, 10 max iterations each
```

**PowerShell:**
```powershell
# Add PRDs to the queue
./scripts/ralph/ralph-queue.ps1 add -Prd /project1/prd.json -Project /project1
./scripts/ralph/ralph-queue.ps1 add -Prd /project2/prd.json -Project /project2 -Priority 1

# Check if PRD is complete before adding
./scripts/ralph/ralph-queue.ps1 check -Prd /path/to/prd.json
./scripts/ralph/ralph-queue.ps1 check -Prd /path/to/prd.json -Quiet  # Returns count

# List and manage queue
./scripts/ralph/ralph-queue.ps1 list
./scripts/ralph/ralph-queue.ps1 list -Status pending
./scripts/ralph/ralph-queue.ps1 status
./scripts/ralph/ralph-queue.ps1 remove -Id <id>
./scripts/ralph/ralph-queue.ps1 clear

# Start workers to process queue
./scripts/ralph/ralph-queue.ps1 start -Count 3 -MaxIterations 10
```

### Queue Workers

For dedicated worker management:

```bash
# Bash
./scripts/ralph/ralph-queue-workers.sh start -c 3 -m 10
./scripts/ralph/ralph-queue-workers.sh status
./scripts/ralph/ralph-queue-workers.sh stop
```

```powershell
# PowerShell
./scripts/ralph/ralph-queue-workers.ps1 start -Count 3 -MaxIterations 10
./scripts/ralph/ralph-queue-workers.ps1 status
./scripts/ralph/ralph-queue-workers.ps1 stop
```

## Management Scripts

### Dashboard (`ralph-dashboard.sh` / `ralph-dashboard.ps1`)

TUI dashboard for monitoring all instances in real-time.

```bash
./ralph-dashboard.sh              # Bash
./scripts/ralph/ralph-dashboard.ps1   # PowerShell
```

Keys: `q` quit, `r` refresh, `l` lock details, `c` cleanup dead instances

### Lock Management (`ralph-locks.sh` / `ralph-locks.ps1`)

View and manage story locks.

```bash
./ralph-locks.sh status           # Show all locks
./ralph-locks.sh release US-001   # Force release a lock
./ralph-locks.sh cleanup          # Remove stale locks
```

### Cleanup (`ralph-cleanup.sh` / `ralph-cleanup.ps1`)

Clean up dead and old instances.

```bash
./ralph-cleanup.sh                # Show summary
./ralph-cleanup.sh --dead         # Clean dead instances (no heartbeat >5 min)
./ralph-cleanup.sh --old          # Clean old instances (>7 days)
```

## File Structure

```
your-project/
├── ralph-parallel.sh             # Launch multiple instances (Bash)
├── ralph-dashboard.sh            # TUI monitoring dashboard (Bash)
├── ralph-locks.sh                # Lock management (Bash)
├── ralph-cleanup.sh              # Instance cleanup (Bash)
├── ralph.sh                      # Main loop (single instance, Bash)
│
├── scripts/
│   └── ralph/                    # Ralph files (self-contained)
│       ├── ralph.ps1            # Main loop script (PowerShell)
│       ├── ralph-parallel.ps1   # Launch multiple instances (PowerShell)
│       ├── ralph-dashboard.ps1  # TUI dashboard (PowerShell)
│       ├── ralph-locks.ps1      # Lock management (PowerShell)
│       ├── ralph-cleanup.ps1    # Instance cleanup (PowerShell)
│       ├── ralph-once.sh        # Single iteration script
│       ├── ralph-status.sh      # Status checker
│       ├── RalphUtils.psm1      # Shared PowerShell module (60+ functions)
│       ├── prompt.md            # Instructions for each Claude iteration
│       ├── prd.json             # User stories with passes status
│       ├── prd.json.example     # Example PRD format
│       ├── progress.txt         # Append-only learnings log
│       ├── ralph.log            # Execution log with timestamps
│       ├── .last-branch         # Current branch tracker
│       ├── archive/             # Previous runs
│       ├── instances/           # Per-instance data (multi-instance)
│       │   └── {instance-id}/
│       │       ├── ralph.log    # Instance-specific log
│       │       ├── progress.txt # Instance progress
│       │       └── status.json  # Heartbeat & current state
│       ├── locks/               # Story locks (multi-instance)
│       │   └── {story-id}.lock/ # Atomic lock directory
│       ├── skills/              # Claude Code skills
│       │   ├── prd/             # PRD generation skill
│       │   └── ralph/           # PRD to JSON conversion skill
│       └── tests/               # Pester test suites
│
├── docs/                         # Documentation
│   ├── multi-instance.md        # Multi-instance architecture guide
│   └── powershell-guide.md      # PowerShell usage guide
│
└── [Project root]                # Your project files
    ├── src/                      # Source code (created by Ralph)
    ├── package.json              # Dependencies (created by Ralph)
    ├── tsconfig.json             # Config (created by Ralph)
    └── ...                       # Other project files
```

## Key Differences from Original Ralph

| Feature | Original (Amp) | claude-ralph |
|---------|---------------|--------------|
| CLI | `amp` | `claude` |
| Non-interactive flag | `--dangerously-allow-all` | `-p --dangerously-skip-permissions` |
| Pricing | Amp credits | Claude Max subscription |
| Skills location | `~/.config/amp/skills/` | `~/.claude/skills/` |
| Project config | `AGENTS.md` | `CLAUDE.md` |

## Critical Concepts

### Each Iteration = Fresh Context

Each iteration spawns a **new Claude Code instance** with clean context. The only memory between iterations is:

- Git history (commits from previous iterations)
- `progress.txt` (learnings and context)
- `prd.json` (which stories are done)

### Small Tasks

Each PRD item should be small enough to complete in one context window. If a task is too big, Claude runs out of context before finishing and produces poor code.

**Right-sized stories:**
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

**Too big (split these):**
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

### CLAUDE.md Updates Are Critical

After each iteration, Ralph updates the relevant `CLAUDE.md` files with learnings. This is key because Claude Code automatically reads these files, so future iterations benefit from discovered patterns.

### Stop Condition

When all stories have `passes: true`, Ralph outputs `<promise>COMPLETE</promise>` and the loop exits.

## Debugging

Run these commands from your project root:

**Bash:**
```bash
# See which stories are done
cat scripts/ralph/prd.json | jq '.userStories[] | {id, title, passes}'

# See learnings from previous iterations
cat scripts/ralph/progress.txt

# Check ralph execution log
cat scripts/ralph/ralph.log

# Check git history
git log --oneline -10

# Run single iteration for debugging
./scripts/ralph/ralph-once.sh

# Check status with nice formatting
./scripts/ralph/ralph-status.sh

# Multi-instance: check all instance statuses
./ralph-dashboard.sh

# Multi-instance: view/manage locks
./ralph-locks.sh status
```

**PowerShell:**
```powershell
# See which stories are done
Get-Content scripts/ralph/prd.json | ConvertFrom-Json |
    Select-Object -ExpandProperty userStories |
    Select-Object id, title, passes

# Check status with nice formatting
./scripts/ralph/ralph-status.ps1

# Multi-instance: check all instance statuses
./scripts/ralph/ralph-dashboard.ps1 -Once

# Multi-instance: view/manage locks
./scripts/ralph/ralph-locks.ps1 Status
```

## Customizing prompt.md

Edit `scripts/ralph/prompt.md` to customize Ralph's behavior for your project:

- Add project-specific quality check commands
- Include codebase conventions
- Add common gotchas for your stack

## Archiving

Ralph automatically archives previous runs when you start a new feature (different `branchName`). Archives are saved to `scripts/ralph/archive/YYYY-MM-DD-feature-name/` and include the `prd.json`, `progress.txt`, and `ralph.log` from the previous run.

## Troubleshooting

### Claude Code not found
```bash
# Install Claude Code CLI
npm install -g @anthropic-ai/claude-code
# Authenticate
claude
```

### Permission denied on ralph.sh
```bash
chmod +x scripts/ralph/*.sh
```

### jq not found
```bash
# macOS
brew install jq

# Ubuntu/Debian
apt install jq

# Windows (WSL)
apt install jq
```

### Skills not loading

If Claude Code can't find the skills, make sure they're installed globally:

```bash
# Install skills globally
mkdir -p ~/.claude/skills
cp -r scripts/ralph/skills/prd ~/.claude/skills/
cp -r scripts/ralph/skills/ralph ~/.claude/skills/
cp -r scripts/ralph/skills/dev-browser ~/.claude/skills/

# Verify they're installed
ls -la ~/.claude/skills/
```

Then load them explicitly:
```
Load the prd skill
Load the ralph skill
Load the dev-browser skill
```

### Ralph exits early (stories still incomplete)

**Symptom**: Ralph shows "✅ RALPH COMPLETE!" after only 2/11 tasks, or exits when stories remain incomplete.

**Cause**: Claude mentioned the completion tag `<promise>COMPLETE</promise>` in its reasoning or explanations (e.g., saying "I should NOT output `<promise>COMPLETE</promise>`"), which triggered the grep pattern in older versions.

**Fixed in v1.1.0+**: Ralph now uses dual verification:
1. The prompt explicitly warns Claude not to quote the completion tag
2. Ralph verifies BOTH tag presence AND that all PRD stories are actually complete before exiting

**If you encounter this**:

1. **Update ralph.sh** to the latest version from the repo (includes the dual verification fix)

2. **Check the status**:
   ```bash
   ./scripts/ralph/ralph-status.sh
   ```

3. **Review the log**:
   ```bash
   tail -50 scripts/ralph/ralph.log
   ```
   Look for the warning: "Claude output COMPLETE signal but PRD still has incomplete stories"

4. **Other common causes**:
   - Quality checks failing (typecheck, tests)
   - Story is too large for one iteration
   - PRD file corruption

5. **Debug with a single iteration**:
   ```bash
   ./scripts/ralph/ralph-once.sh
   ```
   This runs one iteration and shows what happened.

6. **Check PRD manually**:
   ```bash
   cat scripts/ralph/prd.json | jq '.userStories[] | {id, title, passes}'
   ```

### Multi-instance issues

**Stuck locks**: If a lock appears stuck (instance died without cleanup):
```bash
./ralph-locks.sh status          # Check lock status
./ralph-locks.sh cleanup         # Remove stale locks
./ralph-locks.sh release US-001  # Force release specific lock
```

**Dead instances**: Clean up instances with no heartbeat:
```bash
./ralph-cleanup.sh --dead
```

**PRD corruption**: Restore from automatic backup:
```bash
cp scripts/ralph/prd.json.bak scripts/ralph/prd.json
```

### PowerShell issues

**Script execution disabled** (Windows):
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**PowerShell 7 not found**: Install from [PowerShell Releases](https://github.com/PowerShell/PowerShell/releases) or via package manager:
```bash
brew install powershell          # macOS
sudo apt install powershell      # Ubuntu/Debian
winget install Microsoft.PowerShell  # Windows
```

**Module not found**: Ensure you're running from the project root where `scripts/ralph/` exists.

## Quick Reference

### Bash

```bash
# Install ralph in a project
mkdir -p scripts && cd scripts
git clone https://github.com/RobinOppenstam/claude-ralph ralph
chmod +x ralph/*.sh && cd ..

# Install skills globally (one-time setup, recommended)
./scripts/ralph/install-skills.sh

# Interactive PRD creation
claude
# "Load the prd skill and create a PRD for [feature]"
# "Load the ralph skill and convert tasks/prd-[name].md to prd.json"

# Run ralph autonomously (single instance)
./scripts/ralph/ralph.sh 10

# Run ralph autonomously (multiple instances)
./ralph-parallel.sh 3

# Monitor with dashboard
./ralph-dashboard.sh

# Check status
./scripts/ralph/ralph-status.sh
cat scripts/ralph/prd.json | jq '.userStories[] | {id, title, passes}'

# Check PRD completion before starting
./scripts/ralph/ralph-parallel.sh check -p /path/to/prd.json
./scripts/ralph/ralph-queue.sh check -p /path/to/prd.json -q  # Quiet mode (returns count)

# Manage locks
./ralph-locks.sh status
./ralph-locks.sh cleanup

# Cleanup instances
./ralph-cleanup.sh --dead

# Debug single iteration
./scripts/ralph/ralph-once.sh

# See learnings
cat scripts/ralph/progress.txt
```

### PowerShell

```powershell
# Install ralph in a project
New-Item -ItemType Directory -Path scripts -Force
Set-Location scripts
git clone https://github.com/RobinOppenstam/claude-ralph ralph
Set-Location ..

# Install skills globally
./scripts/ralph/install-skills.ps1

# Run ralph autonomously (single instance)
./scripts/ralph/ralph.ps1 -MaxIterations 10

# Run ralph autonomously (multiple instances)
./scripts/ralph/ralph-parallel.ps1 Start -Count 3

# Monitor with dashboard
./scripts/ralph/ralph-dashboard.ps1

# Check status
./scripts/ralph/ralph-status.ps1

# Check PRD completion before starting
./scripts/ralph/ralph-parallel.ps1 Check -Prd /path/to/prd.json
./scripts/ralph/ralph-queue.ps1 check -Prd /path/to/prd.json -Quiet  # Quiet mode

# Manage locks
./scripts/ralph/ralph-locks.ps1 Status
./scripts/ralph/ralph-locks.ps1 Cleanup

# Cleanup instances
./scripts/ralph/ralph-cleanup.ps1 -Dead
```

## Cross-Platform Support

Ralph provides full cross-platform compatibility with both Bash and PowerShell implementations.

| Feature | Bash | PowerShell |
|---------|------|------------|
| Single Instance | `ralph.sh` | `ralph.ps1` |
| Multiple Instances | `ralph-parallel.sh` | `ralph-parallel.ps1` |
| Queue Management | `ralph-queue.sh` | `ralph-queue.ps1` |
| Queue Workers | `ralph-queue-workers.sh` | `ralph-queue-workers.ps1` |
| Dashboard | `ralph-dashboard.sh` | `ralph-dashboard.ps1` |
| Lock Management | `ralph-locks.sh` | `ralph-locks.ps1` |
| Cleanup | `ralph-cleanup.sh` | `ralph-cleanup.ps1` |
| Status | `ralph-status.sh` | `ralph-status.ps1` |
| PRD Locking | flock | .NET Mutex |
| Story Locks | mkdir (atomic) | mkdir (atomic) |

Both implementations share the same file formats (status.json, lock directories, PRD), so you can mix Bash and PowerShell instances in the same project.

### Bash vs PowerShell Differences

While both implementations are functionally equivalent, there are intentional differences to match platform conventions:

| Aspect | Bash | PowerShell |
|--------|------|------------|
| Script Location | Project root (`./ralph-*.sh`) | `scripts/ralph/` directory |
| Flag Style | `--dead`, `--old`, `--dry-run` | `-Dead`, `-Old`, `-WhatIf` |
| Command Style | `release-all` (lowercase) | `ReleaseAll` (PascalCase) |
| Release Flag | `release <story-id>` | `Release -StoryId <story-id>` |
| Shared Library | `source ralph-utils.sh` | `Import-Module RalphUtils.psm1` |

**Data Format Compatibility:**
- Lock files: Both use `owner` and `timestamp` files in `.lock/` directories
- Instance status: Both read/write identical `status.json` format
- PRD format: Both parse the same `prd.json` structure

**Empty PRD Handling:**
- Bash: May fail on division by zero for progress calculation
- PowerShell: Handles gracefully with 0% progress display

See [PowerShell Guide](docs/powershell-guide.md) for detailed PowerShell usage.

## Documentation

- [Multi-Instance Guide](docs/multi-instance.md) - Architecture, commands, and troubleshooting for parallel execution
- [PowerShell Guide](docs/powershell-guide.md) - Complete PowerShell reference with module functions

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RALPH_DEBUG` | 0 | Enable debug logging |
| `RALPH_LOCK_TIMEOUT` | 7200 | Lock timeout in seconds (2 hours) |
| `RALPH_CLEANUP_TTL` | 7 | Days to keep old instances |
| `RALPH_MAX_INSTANCES` | 8 | Maximum parallel instances |
| `RALPH_ITERATIONS` | 10 | Default iterations per instance |

## Credits

- Original Ralph: [snarktank/ralph](https://github.com/snarktank/ralph) by [Ryan Carson](https://x.com/ryancarson)
- Ralph Pattern: [Geoffrey Huntley](https://ghuntley.com/ralph/)
- Claude Code: [Anthropic](https://anthropic.com)

## License

MIT License - See [LICENSE](LICENSE) for details.