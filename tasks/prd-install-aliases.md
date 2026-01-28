# PRD: Optional Alias Installation for Ralph Tools

## Overview
Extend the install-skills scripts (install-skills.ps1 and install-skills.sh) to optionally install shell aliases for ralph tools, allowing users to run `ralph`, `ralph-once`, and `ralph-status` from any directory.

## Problem Statement
Currently, users must type full paths like `./scripts/ralph/ralph.sh` or `pwsh ./scripts/ralph/ralph.ps1` to run ralph tools. This is cumbersome and error-prone. Shell aliases would provide a streamlined developer experience with simple commands like `ralph` that work from any directory.

## Target Users
- Developers who use ralph regularly across multiple projects
- Users who prefer command-line shortcuts over full paths
- Cross-platform developers who work in both bash/zsh and PowerShell

## Goals & Success Metrics
- Goal 1: Users can optionally install aliases during skill installation
- Goal 2: Aliases work from any directory using absolute paths
- Goal 3: Support all common shells (.bashrc, .zshrc, .profile, PowerShell profile)
- Goal 4: Non-destructive - existing aliases are preserved, duplicates avoided

## User Stories

### US-001: Prompt User for Alias Installation (Bash)
**As a** developer running install-skills.sh
**I want to** be asked if I want to install shell aliases
**So that** I can choose whether to add ralph shortcuts to my shell

**Acceptance Criteria:**
- [ ] After installing skills, script prompts "Would you like to install shell aliases for ralph tools? (y/N)"
- [ ] Default is No (pressing Enter skips alias installation)
- [ ] If user enters 'y' or 'Y', proceed to alias installation
- [ ] If user enters anything else, skip alias installation gracefully
- [ ] Script runs without errors (shellcheck passes)

**Priority:** High
**Estimate:** S

### US-002: Install Bash/Zsh Aliases
**As a** developer who chose to install aliases
**I want to** have aliases added to my shell config files
**So that** I can use `ralph`, `ralph-once`, `ralph-status` commands

**Acceptance Criteria:**
- [ ] Detect which shell config files exist (.bashrc, .zshrc, .profile)
- [ ] Add aliases to all detected config files
- [ ] Aliases use absolute paths to the ralph scripts in scripts/ralph/
- [ ] Aliases added: `ralph`, `ralph-once`, `ralph-status`
- [ ] Skip adding if alias already exists in file (avoid duplicates)
- [ ] Add a comment marker `# Ralph aliases` before the alias block
- [ ] Print which files were modified
- [ ] Script runs without errors (shellcheck passes)

**Priority:** High
**Estimate:** M

### US-003: Prompt User for Alias Installation (PowerShell)
**As a** developer running install-skills.ps1
**I want to** be asked if I want to install PowerShell aliases
**So that** I can choose whether to add ralph shortcuts to my PowerShell profile

**Acceptance Criteria:**
- [ ] After installing skills, script prompts for alias installation
- [ ] Use Read-Host with clear prompt text
- [ ] Default is No (empty input skips alias installation)
- [ ] If user enters 'y' or 'Y', proceed to alias installation
- [ ] If user enters anything else, skip alias installation gracefully
- [ ] Script passes PSScriptAnalyzer checks

**Priority:** High
**Estimate:** S

### US-004: Install PowerShell Aliases
**As a** developer who chose to install PowerShell aliases
**I want to** have functions added to my PowerShell profile
**So that** I can use `ralph`, `ralph-once`, `ralph-status` commands in PowerShell

**Acceptance Criteria:**
- [ ] Create PowerShell profile if it doesn't exist ($PROFILE path)
- [ ] Add PowerShell functions (not aliases, since aliases can't take arguments well)
- [ ] Functions use absolute paths to the .ps1 scripts
- [ ] Functions: `ralph`, `ralph-once`, `ralph-status` that call pwsh with the scripts
- [ ] Skip adding if function already exists in profile (avoid duplicates)
- [ ] Add a comment marker `# Ralph functions` before the function block
- [ ] Print the profile path that was modified
- [ ] Script passes PSScriptAnalyzer checks

**Priority:** High
**Estimate:** M

### US-005: Show Post-Installation Instructions
**As a** developer who installed aliases
**I want to** see clear instructions on how to use the new aliases
**So that** I know how to activate and use them

**Acceptance Criteria:**
- [ ] After alias installation, show which aliases were installed
- [ ] Show command to reload shell config (e.g., `source ~/.bashrc` or restart PowerShell)
- [ ] Show example usage: `ralph`, `ralph-once`, `ralph-status`
- [ ] Mention that aliases use absolute paths and work from any directory

**Priority:** Medium
**Estimate:** S

### US-006: Add Pester Tests for PowerShell Alias Installation
**As a** maintainer
**I want to** have tests for the alias installation functionality
**So that** I can verify the feature works correctly

**Acceptance Criteria:**
- [ ] Add tests to install-skills.Tests.ps1
- [ ] Test prompt handling (y/n responses)
- [ ] Test profile detection and creation
- [ ] Test duplicate detection (don't add if exists)
- [ ] Test function content is correct
- [ ] All tests pass with `Invoke-Pester`

**Priority:** Medium
**Estimate:** M

## Technical Considerations

### Bash Implementation
- Use `read -p` for prompting with default No
- Check for file existence before modifying
- Use `grep` to check if alias already exists
- Append to files, don't overwrite
- Store absolute path at script execution time using `$(cd ... && pwd)`

### PowerShell Implementation
- Use `Read-Host` for prompting
- Use `$PROFILE` automatic variable for profile path
- Create parent directories if needed with `New-Item -Force`
- Use `Select-String` to check for existing functions
- Add functions, not aliases (better argument handling)

### Alias/Function Definitions

**Bash aliases:**
```bash
# Ralph aliases
alias ralph='/absolute/path/to/scripts/ralph/ralph.sh'
alias ralph-once='/absolute/path/to/scripts/ralph/ralph-once.sh'
alias ralph-status='/absolute/path/to/scripts/ralph/ralph-status.sh'
```

**PowerShell functions:**
```powershell
# Ralph functions
function ralph { pwsh "/absolute/path/to/scripts/ralph/ralph.ps1" @args }
function ralph-once { pwsh "/absolute/path/to/scripts/ralph/ralph-once.ps1" @args }
function ralph-status { pwsh "/absolute/path/to/scripts/ralph/ralph-status.ps1" @args }
```

## Out of Scope
- Automatic shell reload (user must manually source or restart)
- Uninstall/remove aliases command
- Custom alias names (always uses ralph, ralph-once, ralph-status)
- Fish shell support
- Windows CMD support (PowerShell only for Windows)

## Dependencies
- Existing install-skills.ps1 and install-skills.sh scripts
- RalphUtils.psm1 for shared PowerShell functions
- User's shell config files must be writable

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Alias conflicts with existing commands | Medium | Check if alias exists before adding, warn user |
| Profile file doesn't exist | Low | Create profile with proper parent directories |
| Path changes after installation | Medium | Document that reinstall is needed if scripts move |
| Permission denied on config files | Low | Handle errors gracefully, inform user |

## Timeline
1. US-001 + US-002: Bash implementation
2. US-003 + US-004: PowerShell implementation
3. US-005: Post-installation instructions
4. US-006: Pester tests
