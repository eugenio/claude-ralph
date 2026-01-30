# TODO - Pending Branch Review

## Unmerged Branches to Review

### 1. `ralph/eugen-FR/PS-005`
- **Commit:** feat: PS-005 - Audit ralph-cleanup.ps1 vs ralph-cleanup.sh
- **Description:** PowerShell/Bash parity audit for ralph-cleanup scripts
- **Action needed:** Review and merge if complete

### 2. `ralph/eugen-FR/PS-006`
- **Commits:**
  - feat: PS-006 - Audit ralph-dashboard.ps1 vs ralph-dashboard.sh
  - chore: Update PRD and progress.txt for PS-006 completion
- **Description:** PowerShell/Bash parity audit for ralph-dashboard scripts
- **Note:** Includes PS-005 changes (branch based on PS-005)
- **Action needed:** Review and merge if complete

### 3. `ralph/eugen-FR/US-001`
- **Commit:** feat: US-001 - Detect outdated Ralph functions in profile
- **Description:** Feature to detect outdated Ralph functions in user's shell profile
- **Action needed:** Review and merge if complete

## Commands to Review

```bash
# View branch differences
git log main..ralph/eugen-FR/PS-005 --oneline
git log main..ralph/eugen-FR/PS-006 --oneline
git log main..ralph/eugen-FR/US-001 --oneline

# Merge a branch
git merge ralph/eugen-FR/PS-006  # This includes PS-005

# Or delete if no longer needed
git branch -D ralph/eugen-FR/PS-005
git branch -D ralph/eugen-FR/PS-006
git branch -D ralph/eugen-FR/US-001
```

## Recently Completed

- [x] Process supervisor with crash recovery (ralph-supervisor.sh/.ps1)
- [x] Graceful shutdown scripts (ralph-stop.sh/.ps1)
- [x] Shell alias installation (install-aliases.sh)
- [x] Comprehensive test suites (56 Bash + 43 Pester tests)
- [x] Cleanup functionality for stale state files (both supervisor and in-session loop states)
