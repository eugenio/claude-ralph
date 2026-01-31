# claude-ralph

An autonomous AI agent loop that runs Claude Code repeatedly until all PRD items are complete.
Each iteration is a fresh Claude Code instance with clean context.
Memory persists via git history, `progress.txt`, and `prd.json`.

## Quick Start (Bash)

```bash
# 1. Install ralph in scripts directory
mkdir -p scripts && cd scripts
git clone https://github.com/RobinOppenstam/claude-ralph ralph
chmod +x ralph/*.sh
cd ..

# 2. (Optional) Install skills globally for interactive use
./scripts/ralph/install-skills.sh

# 3. Create your prd.json (copy from example and edit)
cp scripts/ralph/prd.json.example scripts/ralph/prd.json

# 4. Run ralph from project root
./scripts/ralph/ralph.sh [max_iterations]
```

## Quick Start (PowerShell)

Ralph includes cross-platform PowerShell 7+ equivalents for all bash scripts.

### Prerequisites

PowerShell 7+ is required. Install it based on your platform:

```bash
# macOS (Homebrew)
brew install powershell/tap/powershell

# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y powershell

# Windows (winget)
winget install Microsoft.PowerShell

# Or download from: https://github.com/PowerShell/PowerShell/releases
```

Verify installation:
```powershell
pwsh --version  # Should show 7.x or higher
```

### Running Ralph with PowerShell

```powershell
# 1. Install ralph in scripts directory
New-Item -ItemType Directory -Path scripts -Force
Set-Location scripts
git clone https://github.com/RobinOppenstam/claude-ralph ralph
Set-Location ..

# 2. (Optional) Install skills globally for interactive use
pwsh ./scripts/ralph/install-skills.ps1

# 3. Create your prd.json (copy from example and edit)
Copy-Item ./scripts/ralph/prd.json.example ./scripts/ralph/prd.json

# 4. Run ralph from project root
pwsh ./scripts/ralph/ralph.ps1 -MaxIterations 10
```

### Windows Execution Policy

On Windows, you may need to allow script execution:

```powershell
# Check current policy
Get-ExecutionPolicy

# Allow local scripts (run as Administrator or for current user)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## File Structure

```
your-project/
├── scripts/
│   └── ralph/                    # Ralph files (self-contained)
│       ├── ralph.sh             # Main loop script (Bash)
│       ├── ralph.ps1            # Main loop script (PowerShell)
│       ├── ralph-once.sh        # Single iteration script (Bash)
│       ├── ralph-once.ps1       # Single iteration script (PowerShell)
│       ├── ralph-parallel.sh    # Parallel launcher (Bash)
│       ├── ralph-parallel.ps1   # Parallel launcher (PowerShell)
│       ├── ralph-status.sh      # Status checker (Bash)
│       ├── ralph-status.ps1     # Status checker (PowerShell)
│       ├── ralph-dashboard.sh   # TUI dashboard (Bash)
│       ├── ralph-dashboard.ps1  # TUI dashboard (PowerShell)
│       ├── ralph-cleanup.sh     # Instance cleanup (Bash)
│       ├── ralph-cleanup.ps1    # Instance cleanup (PowerShell)
│       ├── ralph-locks.sh       # Lock management (Bash)
│       ├── ralph-locks.ps1      # Lock management (PowerShell)
│       ├── install-skills.sh    # Skill installer (Bash)
│       ├── install-skills.ps1   # Skill installer (PowerShell)
│       ├── ralph-utils.sh       # Shared Bash utilities
│       ├── RalphUtils.psm1      # Shared PowerShell module
│       ├── prompt.md            # Instructions for each iteration
│       ├── prd.json             # User stories with passes status
│       ├── progress.txt         # Append-only learnings log
│       ├── .last-branch         # Current branch tracker
│       ├── instances/           # Instance directories (auto-created)
│       ├── locks/               # Story lock files (auto-created)
│       ├── archive/             # Previous runs
│       ├── skills/              # Claude Code skills
│       └── tests/               # Pester test suites
│
└── [Project root]                # Your project files
    ├── src/                      # Source code (created by Ralph)
    ├── package.json              # Dependencies (created by Ralph)
    └── ...                       # Other project files
```

### Global Registry

Ralph can register instances in a global registry for cross-project monitoring:

```
~/.ralph/global/                   # Global registry directory
├── instances/                     # Symlinks to active instances
│   ├── projectA-user-host-123-*  # Symlink to project A instance
│   └── projectB-user-host-456-*  # Symlink to project B instance
└── locks/                         # Global lock files (reserved)
```

## How It Works

1. **Loop starts** - Ralph reads `prd.json`
2. **Pick story** - Selects highest priority story where `passes: false`
3. **Implement** - Claude Code implements the story
4. **Quality check** - Runs typecheck, tests, lint
5. **Commit** - If checks pass, commits changes
6. **Update PRD** - Marks story as `passes: true`
7. **Log learnings** - Appends to `progress.txt`
8. **Repeat** - Until all stories pass or max iterations reached

## Key Concepts

### Fresh Context Each Iteration
Each iteration spawns a NEW Claude Code instance with clean context.
Memory persists only through:
- Git history (commits from previous iterations)
- `progress.txt` (learnings and context)
- `prd.json` (which stories are done)

### Small Stories
Each story must be small enough to complete in one context window.
Right-sized examples:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

Too big (split these):
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

### CLAUDE.md Updates
Ralph updates CLAUDE.md files with learnings so future iterations benefit.
These are automatically read by Claude Code in subsequent runs.

## Commands

Run these from your project root:

### Bash Commands

```bash
# Run Ralph loop (10 iterations max)
./scripts/ralph/ralph.sh 10

# Run single iteration (no loop, no archive)
./scripts/ralph/ralph-once.sh

# Check status
./scripts/ralph/ralph-status.sh
# Or manually
cat scripts/ralph/prd.json | jq '.userStories[] | {id, title, passes}'

# Parallel execution (see below)
./scripts/ralph/ralph-parallel.sh start -c 3 -m 10

# See learnings
cat scripts/ralph/progress.txt

# Check execution log
cat scripts/ralph/ralph.log

# Check git history
git log --oneline -10
```

### PowerShell Commands

```powershell
# Run Ralph loop (10 iterations max)
pwsh ./scripts/ralph/ralph.ps1 -MaxIterations 10

# Run single iteration (no loop, no archive)
pwsh ./scripts/ralph/ralph-once.ps1

# Check status
pwsh ./scripts/ralph/ralph-status.ps1
# Or manually
Get-Content ./scripts/ralph/prd.json | ConvertFrom-Json |
    Select-Object -ExpandProperty userStories |
    Select-Object id, title, passes

# Parallel execution (see below)
pwsh ./scripts/ralph/ralph-parallel.ps1 Start -Count 3 -MaxIterations 10

# See learnings
Get-Content ./scripts/ralph/progress.txt

# Check execution log
Get-Content ./scripts/ralph/ralph.log

# Check git history
git log --oneline -10
```

## Parallel Execution

Ralph supports running multiple instances in parallel to speed up PRD completion. Each instance works on different stories using file-based locking.

### Bash (ralph-parallel.sh)

```bash
# Start 3 parallel instances, each with max 10 iterations
./scripts/ralph/ralph-parallel.sh start -c 3 -m 10

# Use external PRD file and project root (for running from different directory)
./scripts/ralph/ralph-parallel.sh start -p /path/to/prd.json -r /path/to/project -c 3

# Check status of running instances
./scripts/ralph/ralph-parallel.sh status

# Stop all instances gracefully (SIGTERM)
./scripts/ralph/ralph-parallel.sh stop

# Force kill all instances (SIGKILL)
./scripts/ralph/ralph-parallel.sh kill

# Open monitoring dashboard
./scripts/ralph/ralph-parallel.sh dashboard
```

**Options:**
- `-c COUNT` or `--count COUNT` - Number of instances (default: CPU cores / 2)
- `-m ITERATIONS` or `--max-iterations ITERATIONS` - Max iterations per instance (default: 10)
- `-p PATH` or `--prd PATH` - Path to prd.json file (for external PRD locations)
- `-r PATH` or `--project PATH` - Project root directory (for running from different directory)

### PowerShell (ralph-parallel.ps1)

```powershell
# Start 3 parallel instances, each with max 10 iterations
pwsh ./scripts/ralph/ralph-parallel.ps1 Start -Count 3 -MaxIterations 10

# Use external PRD file and project root
pwsh ./scripts/ralph/ralph-parallel.ps1 Start -Prd /path/to/prd.json -ProjectRoot /path/to/project -Count 3

# Check status of running instances
pwsh ./scripts/ralph/ralph-parallel.ps1 Status

# Stop all instances gracefully
pwsh ./scripts/ralph/ralph-parallel.ps1 Stop

# Force kill all instances
pwsh ./scripts/ralph/ralph-parallel.ps1 Kill

# Open monitoring dashboard
pwsh ./scripts/ralph/ralph-parallel.ps1 Dashboard
```

**Options:**
- `-Count N` or `-c N` - Number of instances (default: CPU cores / 2)
- `-MaxIterations M` or `-m M` - Max iterations per instance (default: 10)
- `-Prd PATH` or `-p PATH` - Path to prd.json file
- `-ProjectRoot PATH` or `-r PATH` - Project root directory

### Environment Variables

Control parallel execution behavior:

```bash
# Maximum allowed instances (default: 8)
export RALPH_MAX_INSTANCES=4

# Disable global registry for this instance
export RALPH_GLOBAL_DISABLE=1

# Custom global registry directory (default: ~/.ralph/global)
export RALPH_GLOBAL_DIR=/custom/path

# Cleanup TTL in days (default: 7)
export RALPH_CLEANUP_TTL=14

# Lock timeout in seconds (default: 7200 = 2 hours)
export RALPH_LOCK_TIMEOUT=3600

# Enable debug logging
export RALPH_DEBUG=1
```

## Skills

Ralph includes three Claude Code skills for interactive use:

### Installing Skills Globally

```bash
# Bash
./scripts/ralph/install-skills.sh

# PowerShell
pwsh ./scripts/ralph/install-skills.ps1
```

This installs skills to `~/.claude/skills/` so you can use them in any project.

### Available Skills

1. **prd skill** - Generate detailed PRDs from natural language
   ```
   Load the prd skill and create a PRD for user authentication
   ```

2. **ralph skill** - Convert markdown PRDs to ralph's JSON format
   ```
   Load the ralph skill and convert tasks/prd-auth.md to prd.json
   ```

3. **dev-browser skill** - Browser automation for UI verification
   ```
   Load the dev-browser skill and verify the login page
   ```

Skills are automatically available when running ralph autonomously. Global installation is only needed for interactive Claude Code sessions.

## Troubleshooting

### Ralph exits too early (e.g., after 2/11 tasks)

**Symptom**: Ralph shows "✅ RALPH COMPLETE!" when there are still incomplete stories.

**Cause**: Claude mentioned the completion tag `<promise>COMPLETE</promise>` in its explanations or reasoning (e.g., "I should NOT output `<promise>COMPLETE</promise>`"), which triggered the grep pattern.

**Fixed in**: v1.1.0+ with dual verification:
1. The prompt now explicitly warns Claude not to quote the completion tag
2. Ralph verifies both the tag presence AND that all PRD stories are actually complete

**If you see this on older versions**:
- Update to the latest ralph.sh from the repo
- The fix adds a double-check: even if the tag is detected, ralph now verifies the PRD before exiting

### Parallel Instances Stuck in "waiting" State

**Symptom**: Dashboard shows instances with state "waiting" but no stories are being claimed.

**Cause**: All incomplete stories have stale `claimedBy` values from dead instances. The claiming logic filters out stories where `claimedBy` is not null, even if the claiming instance is gone.

**Fix**: Clear stale claims from the PRD:
```bash
# Check which stories have stale claims
cat scripts/ralph/prd.json | jq '.userStories[] | select(.passes == false) | {id, claimedBy}'

# Clear all claims
jq '.userStories |= map(.claimedBy = null)' scripts/ralph/prd.json > /tmp/prd-clean.json && mv /tmp/prd-clean.json scripts/ralph/prd.json

# Also clear any stale lock files
rm -rf scripts/ralph/locks/*.lock
```

**Prevention**: Use `ralph-locks.sh cleanup` periodically to remove stale locks:
```bash
./scripts/ralph/ralph-locks.sh cleanup
```

### PowerShell Troubleshooting

**"cannot be loaded because running scripts is disabled"**

Windows restricts script execution by default. Fix with:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**"The term 'pwsh' is not recognized"**

PowerShell 7+ is not installed or not in PATH. Install from:
- https://github.com/PowerShell/PowerShell/releases
- Or use your package manager (brew, apt, winget)

**"Module 'Pester' not found"**

Install Pester for running tests:
```powershell
Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck -Scope CurrentUser
```

**"Module 'RalphUtils' not found"**

The script must be run from the project root directory where `scripts/ralph/` exists. The scripts use `$PSScriptRoot` to locate the module.

**Tests fail with "access denied" or permission errors**

On Windows, ensure you have write access to the target directories. On Linux/macOS, check file permissions with `ls -la`.

## Running Pester Tests

Ralph includes comprehensive Pester test suites for all PowerShell scripts.

### Installing Pester

```powershell
# Install Pester 5.x (required)
Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck -Scope CurrentUser

# Verify installation
Get-Module -ListAvailable Pester
```

### Running All Tests

```powershell
# Run all tests from project root
pwsh -Command "Invoke-Pester ./scripts/ralph/tests/ -Output Detailed"

# Run with code coverage
pwsh -Command "Invoke-Pester ./scripts/ralph/tests/ -CodeCoverage ./scripts/ralph/*.ps1 -Output Detailed"
```

### Running Individual Test Files

```powershell
# Test the shared module
Invoke-Pester ./scripts/ralph/tests/RalphUtils.Tests.ps1 -Output Detailed

# Test the main loop script
Invoke-Pester ./scripts/ralph/tests/ralph.Tests.ps1 -Output Detailed

# Test the single iteration script
Invoke-Pester ./scripts/ralph/tests/ralph-once.Tests.ps1 -Output Detailed

# Test the status checker
Invoke-Pester ./scripts/ralph/tests/ralph-status.Tests.ps1 -Output Detailed

# Test the skill installer
Invoke-Pester ./scripts/ralph/tests/install-skills.Tests.ps1 -Output Detailed
```

### Test Structure

Each test file covers:
- **Script structure validation** - Functions defined, proper imports
- **Unit tests** - Individual function behavior with mocked dependencies
- **Edge cases** - Missing files, invalid input, empty data
- **Integration patterns** - Module interactions, path handling

## Tips

- **Start small**: Begin with 3-4 iterations, review, then continue
- **Clear criteria**: Vague acceptance criteria = vague code
- **Include quality checks**: Always have typecheck/test in criteria
- **Browser verify UI**: Frontend stories need visual verification
- **Review progress.txt**: See what Ralph learned
- **Install skills globally**: Run `./scripts/ralph/install-skills.sh` (or `.ps1`) once for better interactive experience
- **Cross-platform**: Use PowerShell scripts on Windows, bash or PowerShell on macOS/Linux
- **Use pwsh**: Always invoke PowerShell scripts with `pwsh` command for cross-platform compatibility
