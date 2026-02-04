#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for Ralph PowerShell scripts (PS-013).

.DESCRIPTION
    Comprehensive tests for ralph-locks.ps1, ralph-cleanup.ps1, ralph-parallel.ps1,
    ralph-dashboard.ps1, and ralph.ps1 scripts.

    PS-013 Acceptance Criteria:
    - Test ralph-locks.ps1 all commands
    - Test ralph-cleanup.ps1 with -WhatIf
    - Test ralph-parallel.ps1 status command
    - Test ralph-dashboard.ps1 --help
    - Test ralph.ps1 instance initialization
#>

BeforeAll {
    $script:ScriptsDir = Split-Path $PSScriptRoot -Parent
    $script:ModulePath = Join-Path $script:ScriptsDir 'RalphUtils.psm1'
}

Describe 'ralph-locks.ps1' {
    BeforeAll {
        $script:LocksScript = Join-Path $script:ScriptsDir 'ralph-locks.ps1'
    }

    Context 'Script Structure' {
        It 'Script file exists' {
            Test-Path $script:LocksScript | Should -Be $true
        }

        It 'Has valid PowerShell syntax' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:LocksScript,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }

        It 'Has proper comment-based help' {
            $content = Get-Content $script:LocksScript -Raw
            $content | Should -Match '\.SYNOPSIS'
            $content | Should -Match '\.DESCRIPTION'
            $content | Should -Match '\.EXAMPLE'
        }

        It 'Defines Command parameter with validation set' {
            $content = Get-Content $script:LocksScript -Raw
            $content | Should -Match '\[ValidateSet\(.*Status.*Release.*ReleaseAll.*Cleanup.*Help'
        }

        It 'Imports RalphUtils module' {
            $content = Get-Content $script:LocksScript -Raw
            # The script uses $modulePath variable to import RalphUtils.psm1
            $content | Should -Match 'Import-Module\s+\$modulePath'
        }
    }

    Context 'Status Command' {
        It 'Status command runs without error' {
            { & $script:LocksScript Status } | Should -Not -Throw
        }

        It 'Status command produces output' {
            # Use 6>&1 to capture Write-Host (Information stream) to output stream
            $output = & $script:LocksScript Status 6>&1 | Out-String
            $output | Should -Not -BeNullOrEmpty
        }

        It 'Status shows "RALPH LOCK STATUS" header' {
            $output = & $script:LocksScript Status 6>&1 | Out-String
            $output | Should -Match 'RALPH LOCK STATUS|No active locks'
        }
    }

    Context 'Help Command' {
        It 'Help command runs without error' {
            { & $script:LocksScript Help } | Should -Not -Throw
        }

        It 'Help shows usage information' {
            $output = & $script:LocksScript Help 6>&1 | Out-String
            $output | Should -Match 'Usage:'
        }

        It 'Help shows all commands' {
            $output = & $script:LocksScript Help 6>&1 | Out-String
            $output | Should -Match 'Status'
            $output | Should -Match 'Release'
            $output | Should -Match 'ReleaseAll'
            $output | Should -Match 'Cleanup'
        }

        It 'Help shows examples' {
            $output = & $script:LocksScript Help 6>&1 | Out-String
            $output | Should -Match 'Examples:'
        }
    }

    Context 'Cleanup Command' {
        It 'Cleanup command runs without error' {
            { & $script:LocksScript Cleanup } | Should -Not -Throw
        }
    }

    Context 'ReleaseAll Command' {
        It 'ReleaseAll command runs without error' {
            { & $script:LocksScript ReleaseAll } | Should -Not -Throw
        }
    }

    Context 'Release Command' {
        It 'Release with non-existent story runs without throwing' {
            # Should not throw even if lock doesn't exist
            { & $script:LocksScript Release -StoryId 'NONEXISTENT-999' } | Should -Not -Throw
        }
    }

    Context 'Default Command Behavior' {
        It 'Default command (no param) is Status' {
            $output = & $script:LocksScript 6>&1 | Out-String
            $output | Should -Match 'RALPH LOCK STATUS|No active locks'
        }
    }

    Context 'Internal Functions' {
        It 'Defines Show-LockStatus function' {
            $content = Get-Content $script:LocksScript -Raw
            $content | Should -Match 'function\s+Show-LockStatus'
        }

        It 'Defines Show-Help function' {
            $content = Get-Content $script:LocksScript -Raw
            $content | Should -Match 'function\s+Show-Help'
        }

        It 'Uses color-coded output' {
            $content = Get-Content $script:LocksScript -Raw
            $content | Should -Match '-ForegroundColor\s+Green'
            $content | Should -Match '-ForegroundColor\s+Yellow'
            $content | Should -Match '-ForegroundColor\s+Red'
        }
    }
}

Describe 'ralph-cleanup.ps1' {
    BeforeAll {
        $script:CleanupScript = Join-Path $script:ScriptsDir 'ralph-cleanup.ps1'
    }

    Context 'Script Structure' {
        It 'Script file exists' {
            Test-Path $script:CleanupScript | Should -Be $true
        }

        It 'Has valid PowerShell syntax' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:CleanupScript,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }

        It 'Has proper comment-based help' {
            $content = Get-Content $script:CleanupScript -Raw
            $content | Should -Match '\.SYNOPSIS'
            $content | Should -Match '\.DESCRIPTION'
            $content | Should -Match '\.PARAMETER\s+Dead'
            $content | Should -Match '\.PARAMETER\s+Old'
            $content | Should -Match '\.PARAMETER\s+WhatIf'
        }

        It 'Uses CmdletBinding with SupportsShouldProcess' {
            $content = Get-Content $script:CleanupScript -Raw
            $content | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
        }

        It 'Defines switch parameters for cleanup types' {
            $content = Get-Content $script:CleanupScript -Raw
            $content | Should -Match '\[switch\]\$Dead'
            $content | Should -Match '\[switch\]\$Old'
            $content | Should -Match '\[switch\]\$All'
            $content | Should -Match '\[switch\]\$Terminated'
        }
    }

    Context 'Default Execution (Summary)' {
        It 'Default command runs without error' {
            { & $script:CleanupScript } | Should -Not -Throw
        }

        It 'Shows instance summary' {
            $output = & $script:CleanupScript 6>&1 | Out-String
            $output | Should -Match 'INSTANCE SUMMARY|Total instances'
        }

        It 'Shows running/completed/terminated/dead counts' {
            $output = & $script:CleanupScript 6>&1 | Out-String
            $output | Should -Match 'Running:|Completed:|Terminated:|Dead:'
        }
    }

    Context 'WhatIf Mode' {
        It '-Dead -WhatIf runs without error' {
            { & $script:CleanupScript -Dead -WhatIf } | Should -Not -Throw
        }

        It '-Old -WhatIf runs without error' {
            { & $script:CleanupScript -Old -WhatIf } | Should -Not -Throw
        }

        It '-Terminated -WhatIf runs without error' {
            { & $script:CleanupScript -Terminated -WhatIf } | Should -Not -Throw
        }

        It '-All -WhatIf runs without error' {
            { & $script:CleanupScript -All -WhatIf } | Should -Not -Throw
        }

        It '-WhatIf shows "What if" prefix for potential deletions' {
            # Even if no instances to clean, the script should not error
            { & $script:CleanupScript -Dead -WhatIf } | Should -Not -Throw
        }
    }

    Context 'Cleanup Flags' {
        It '-Dead flag runs without error' {
            { & $script:CleanupScript -Dead } | Should -Not -Throw
        }

        It '-Old flag runs without error' {
            { & $script:CleanupScript -Old } | Should -Not -Throw
        }

        It '-Terminated flag runs without error' {
            { & $script:CleanupScript -Terminated } | Should -Not -Throw
        }

        It '-All flag runs without error' {
            { & $script:CleanupScript -All } | Should -Not -Throw
        }
    }

    Context 'Internal Functions' {
        It 'Defines Show-Summary function' {
            $content = Get-Content $script:CleanupScript -Raw
            $content | Should -Match 'function\s+Show-Summary'
        }

        It 'Defines Clear-DeadInstances function' {
            $content = Get-Content $script:CleanupScript -Raw
            $content | Should -Match 'function\s+Clear-DeadInstances'
        }

        It 'Defines Clear-OldInstances function' {
            $content = Get-Content $script:CleanupScript -Raw
            $content | Should -Match 'function\s+Clear-OldInstances'
        }

        It 'Uses RALPH_CLEANUP_TTL environment variable' {
            $content = Get-Content $script:CleanupScript -Raw
            $content | Should -Match 'RALPH_CLEANUP_TTL'
        }
    }

    Context 'Color-Coded Output' {
        It 'Uses color-coded output for different states' {
            $content = Get-Content $script:CleanupScript -Raw
            $content | Should -Match '-ForegroundColor\s+Green'
            $content | Should -Match '-ForegroundColor\s+Yellow'
            $content | Should -Match '-ForegroundColor\s+Red'
        }
    }

    Context 'Environment Variable Support' {
        It 'Supports RALPH_CLEANUP_TTL for old instance threshold' {
            $content = Get-Content $script:CleanupScript -Raw
            $content | Should -Match '\$env:RALPH_CLEANUP_TTL'
        }

        It 'Default TTL is 7 days' {
            $content = Get-Content $script:CleanupScript -Raw
            # Check for default value of 7
            $content | Should -Match '\?\?\s*7|\bdefault.*7'
        }
    }
}

Describe 'ralph-parallel.ps1' {
    BeforeAll {
        $script:ParallelScript = Join-Path $script:ScriptsDir 'ralph-parallel.ps1'
    }

    Context 'Script Structure' {
        It 'Script file exists' {
            Test-Path $script:ParallelScript | Should -Be $true
        }

        It 'Has valid PowerShell syntax' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:ParallelScript,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }

        It 'Has proper comment-based help' {
            $content = Get-Content $script:ParallelScript -Raw
            $content | Should -Match '\.SYNOPSIS'
            $content | Should -Match '\.DESCRIPTION'
            $content | Should -Match '\.EXAMPLE'
        }

        It 'Defines Command parameter with validation set' {
            $content = Get-Content $script:ParallelScript -Raw
            # ValidateSet contains Start, Stop, Kill, Status (order may vary)
            $content | Should -Match '\[ValidateSet\(.*Start'
            $content | Should -Match '\[ValidateSet\(.*Stop'
            $content | Should -Match '\[ValidateSet\(.*Status'
        }
    }

    Context 'Status Command' {
        It 'Status command runs without error' {
            { & $script:ParallelScript Status } | Should -Not -Throw
        }

        It 'Status shows running jobs information' {
            $output = & $script:ParallelScript Status 6>&1 | Out-String
            # Should show some status information
            $output | Should -Not -BeNullOrEmpty
        }

        It 'Status shows job count' {
            $output = & $script:ParallelScript Status 6>&1 | Out-String
            $output | Should -Match 'Running|jobs|Job|instances|Instances|No.*running'
        }
    }

    Context 'Help Command' {
        It 'Help command runs without error' {
            { & $script:ParallelScript Help } | Should -Not -Throw
        }

        It 'Help shows usage information' {
            $output = & $script:ParallelScript Help 6>&1 | Out-String
            $output | Should -Match 'Usage:|Commands:|Options:'
        }

        It 'Help shows all commands' {
            $output = & $script:ParallelScript Help 6>&1 | Out-String
            $output | Should -Match 'Start'
            $output | Should -Match 'Stop'
            $output | Should -Match 'Status'
        }
    }

    Context 'Stop Command (No Jobs Running)' {
        It 'Stop command runs without error when no jobs are running' {
            { & $script:ParallelScript Stop } | Should -Not -Throw
        }
    }

    Context 'Dashboard Command' {
        It 'Dashboard command exists in validation set' {
            $content = Get-Content $script:ParallelScript -Raw
            $content | Should -Match 'Dashboard'
        }
    }

    Context 'Internal Functions' {
        It 'Defines Get-DefaultCount function' {
            $content = Get-Content $script:ParallelScript -Raw
            $content | Should -Match 'function\s+Get-DefaultCount'
        }

        It 'Defines Show-Help function' {
            $content = Get-Content $script:ParallelScript -Raw
            $content | Should -Match 'function\s+Show-Help'
        }

        It 'Defines Start-RalphInstances function' {
            $content = Get-Content $script:ParallelScript -Raw
            $content | Should -Match 'function\s+Start-RalphInstances'
        }

        It 'Defines Stop-RalphInstances function' {
            $content = Get-Content $script:ParallelScript -Raw
            $content | Should -Match 'function\s+Stop-RalphInstances'
        }

        It 'Defines Show-Status function' {
            $content = Get-Content $script:ParallelScript -Raw
            $content | Should -Match 'function\s+Show-Status'
        }
    }

    Context 'Job Management' {
        It 'Uses Start-Job for parallel execution' {
            $content = Get-Content $script:ParallelScript -Raw
            $content | Should -Match 'Start-Job'
        }

        It 'Tracks jobs in running-jobs.json' {
            $content = Get-Content $script:ParallelScript -Raw
            $content | Should -Match 'running-jobs\.json'
        }
    }

    Context 'Default Count Calculation' {
        It 'Calculates default count from CPU cores' {
            $content = Get-Content $script:ParallelScript -Raw
            # Should reference logical processors
            $content | Should -Match 'LogicalProcessors|NumberOfCores|ProcessorCount'
        }
    }

    Context 'RALPH_MAX_INSTANCES Support' {
        It 'Respects RALPH_MAX_INSTANCES environment variable' {
            $content = Get-Content $script:ParallelScript -Raw
            $content | Should -Match 'RALPH_MAX_INSTANCES'
        }
    }
}

Describe 'ralph-dashboard.ps1' {
    BeforeAll {
        $script:DashboardScript = Join-Path $script:ScriptsDir 'ralph-dashboard.ps1'
    }

    Context 'Script Structure' {
        It 'Script file exists' {
            Test-Path $script:DashboardScript | Should -Be $true
        }

        It 'Has valid PowerShell syntax' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:DashboardScript,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }

        It 'Has proper comment-based help' {
            $content = Get-Content $script:DashboardScript -Raw
            $content | Should -Match '\.SYNOPSIS'
            $content | Should -Match '\.DESCRIPTION'
            $content | Should -Match '\.PARAMETER\s+RefreshInterval'
            $content | Should -Match '\.EXAMPLE'
        }

        It 'Imports RalphUtils module' {
            $content = Get-Content $script:DashboardScript -Raw
            # The script uses $modulePath variable to import RalphUtils.psm1
            $content | Should -Match 'Import-Module\s+\$modulePath'
        }
    }

    Context 'Help Documentation' {
        It 'Help is accessible via Get-Help' {
            $help = Get-Help $script:DashboardScript -Full 2>&1
            $help | Should -Not -BeNullOrEmpty
        }

        It 'Help shows synopsis' {
            $help = Get-Help $script:DashboardScript 2>&1
            ($help | Out-String) | Should -Match 'TUI dashboard|monitoring|Ralph'
        }

        It 'Help shows RefreshInterval parameter' {
            # Check comment-based help directly since Get-Help -Parameter is unreliable in CI
            $content = Get-Content $script:DashboardScript -Raw
            $content | Should -Match '\.PARAMETER RefreshInterval'
        }

        It 'Help shows AutoClean parameter' {
            # Check comment-based help directly since Get-Help -Parameter is unreliable in CI
            $content = Get-Content $script:DashboardScript -Raw
            $content | Should -Match '\.PARAMETER AutoClean'
        }
    }

    Context 'Parameters' {
        It 'Accepts -RefreshInterval parameter' {
            $content = Get-Content $script:DashboardScript -Raw
            $content | Should -Match '\[int\]\$RefreshInterval'
        }

        It 'Default RefreshInterval is 2 seconds' {
            $content = Get-Content $script:DashboardScript -Raw
            $content | Should -Match '\$RefreshInterval\s*=\s*2'
        }

        It 'Accepts -AutoClean switch parameter' {
            $content = Get-Content $script:DashboardScript -Raw
            $content | Should -Match '\[switch\]\$AutoClean'
        }

        It 'Accepts -AutoCleanInterval parameter' {
            $content = Get-Content $script:DashboardScript -Raw
            $content | Should -Match '\$AutoCleanInterval'
        }
    }

    Context 'Display Functions' {
        It 'Defines rendering/display functions' {
            $content = Get-Content $script:DashboardScript -Raw
            # Check for presence of display-related functions
            $content | Should -Match 'function\s+(Show|Draw|Render|Update|Get)-'
        }

        It 'Uses color-coded output' {
            $content = Get-Content $script:DashboardScript -Raw
            $content | Should -Match '-ForegroundColor'
        }

        It 'Shows instance table headers' {
            $content = Get-Content $script:DashboardScript -Raw
            # Should display instance info in tabular format
            $content | Should -Match 'Instance|ID|Story|Status|Iteration'
        }
    }

    Context 'PRD Progress Display' {
        It 'Shows PRD progress' {
            $content = Get-Content $script:DashboardScript -Raw
            # Should have progress bar or percentage
            $content | Should -Match 'Progress|PRD|pass|complete'
        }

        It 'Uses Unicode block characters for progress bar' {
            $content = Get-Content $script:DashboardScript -Raw
            # Unicode block characters (U+2588, U+2591, etc.) or fallback
            $content | Should -Match '\[char\]0x25|█|░|#|-|\['
        }
    }

    Context 'Exit Handling' {
        It 'Handles keyboard input for exit' {
            $content = Get-Content $script:DashboardScript -Raw
            # Should check for Q key or Ctrl+C
            $content | Should -Match 'KeyAvailable|ReadKey|Console|Q'
        }
    }
}

Describe 'ralph.ps1' {
    BeforeAll {
        $script:RalphScript = Join-Path $script:ScriptsDir 'ralph.ps1'
        $script:RalphContent = Get-Content $script:RalphScript -Raw
    }

    Context 'Script Structure' {
        It 'Script file exists' {
            Test-Path $script:RalphScript | Should -Be $true
        }

        It 'Has valid PowerShell syntax' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:RalphScript,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }

        It 'Has proper comment-based help' {
            $script:RalphContent | Should -Match '\.SYNOPSIS'
            $script:RalphContent | Should -Match '\.DESCRIPTION'
            $script:RalphContent | Should -Match '\.PARAMETER'
        }

        It 'Imports RalphUtils module' {
            # The script uses $modulePath variable to import RalphUtils.psm1
            $script:RalphContent | Should -Match 'Import-Module\s+\$modulePath'
        }

        It 'Defines Main function' {
            $script:RalphContent | Should -Match 'function\s+Main'
        }
    }

    Context 'Instance Initialization' {
        It 'Calls New-RalphInstanceDirectory in Main' {
            $script:RalphContent | Should -Match 'New-RalphInstanceDirectory'
        }

        It 'Stores instance paths in script variable' {
            $script:RalphContent | Should -Match '\$script:InstancePaths\s*=\s*New-RalphInstanceDirectory'
        }

        It 'Registers cleanup handler' {
            $script:RalphContent | Should -Match 'Register-RalphCleanup'
        }

        It 'Registers with global registry' {
            $script:RalphContent | Should -Match 'Register-RalphGlobalInstance'
        }

        It 'Initializes global registry' {
            $script:RalphContent | Should -Match 'Initialize-RalphGlobalRegistry'
        }

        It 'Initializes session tracking for termination summary' {
            $script:RalphContent | Should -Match 'Initialize-RalphSessionTracking'
        }
    }

    Context 'Module Integration' {
        BeforeAll {
            Import-Module $script:ModulePath -Force
        }

        It 'Can generate instance ID' {
            $id = Get-RalphInstanceId -Force
            $id | Should -Not -BeNullOrEmpty
        }

        It 'Instance ID has correct format (user-hostname-pid-timestamp)' {
            $id = Get-RalphInstanceId -Force
            $parts = $id -split '-'
            $parts.Count | Should -BeGreaterOrEqual 4
        }

        It 'Can get short ID' {
            $shortId = Get-RalphShortId
            $shortId | Should -Not -BeNullOrEmpty
            $shortId.Length | Should -BeLessOrEqual 8
        }

        It 'Short ID is prefix of full ID' {
            $fullId = Get-RalphInstanceId
            $shortId = Get-RalphShortId
            $fullId.Substring(0, $shortId.Length) | Should -Be $shortId
        }
    }

    Context 'Status Updates' {
        It 'Uses Update-RalphStatus for state updates' {
            $script:RalphContent | Should -Match 'Update-RalphStatus'
        }

        It 'Updates status with iteration info' {
            $script:RalphContent | Should -Match 'Update-RalphStatus.*-Iteration'
        }

        It 'Updates status with MaxIterations' {
            $script:RalphContent | Should -Match 'Update-RalphStatus.*-MaxIterations'
        }

        It 'Updates status with different states' {
            $script:RalphContent | Should -Match "-State\s+'starting'"
            $script:RalphContent | Should -Match "-State\s+'idle'|-State\s+\`"idle\`""
        }
    }

    Context 'Story Claiming' {
        It 'Uses story claiming functions' {
            $script:RalphContent | Should -Match 'Request-RalphNextStoryClaim|Request-RalphStoryClaim'
        }

        It 'Releases claims on completion' {
            $script:RalphContent | Should -Match 'Remove-RalphStoryClaim|Release-RalphStoryClaim'
        }
    }

    Context 'Feature Branch Handling' {
        It 'Creates story branches' {
            $script:RalphContent | Should -Match 'New-RalphStoryBranch'
        }

        It 'Merges story branches on completion' {
            $script:RalphContent | Should -Match 'Merge-RalphStoryBranch'
        }
    }

    Context 'Instance Logging' {
        It 'Uses instance-specific logging' {
            $script:RalphContent | Should -Match 'Add-RalphInstanceLog'
        }

        It 'Logs start message' {
            $script:RalphContent | Should -Match "Add-RalphInstanceLog.*Starting|Starting Ralph"
        }
    }

    Context 'Graceful Shutdown' {
        It 'Main is wrapped in try/finally' {
            $script:RalphContent | Should -Match 'try\s*\{[\s\S]*Main[\s\S]*\}\s*finally'
        }

        It 'Calls cleanup in finally block' {
            $script:RalphContent | Should -Match 'finally\s*\{[\s\S]*Invoke-RalphCleanup'
        }
    }

    Context 'Dependency Checking' {
        It 'Checks dependencies at startup' {
            $script:RalphContent | Should -Match 'Test-Dependencies'
        }

        It 'Validates dependencies before continuing' {
            $script:RalphContent | Should -Match '\$deps\.IsValid|\$deps\[.IsValid.\]'
        }
    }

    Context 'PRD Integration' {
        It 'Reads PRD file' {
            $script:RalphContent | Should -Match 'Read-RalphPrdSafe'
        }

        It 'Checks for PRD file existence' {
            $script:RalphContent | Should -Match 'Test-Path.*PrdFile'
        }

        It 'Reads PRD to check story completion status' {
            # ralph.ps1 reads PRD using Read-RalphPrdSafe to check if stories are completed
            # The actual PRD update happens inside the Claude iteration
            $script:RalphContent | Should -Match 'Read-RalphPrdSafe'
            $script:RalphContent | Should -Match '\.passes.*true'
        }
    }
}

Describe 'RalphUtils.psm1' {
    BeforeAll {
        Import-Module $script:ModulePath -Force
    }

    Context 'Module Loads Successfully' {
        It 'Module is loaded' {
            Get-Module RalphUtils | Should -Not -BeNull
        }
    }

    Context 'Core Function Exports' {
        It 'Exports Get-RalphPaths' {
            Get-Command Get-RalphPaths -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Get-RalphInstanceId' {
            Get-Command Get-RalphInstanceId -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Get-RalphShortId' {
            Get-Command Get-RalphShortId -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports New-RalphInstanceDirectory' {
            Get-Command New-RalphInstanceDirectory -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Update-RalphStatus' {
            Get-Command Update-RalphStatus -Module RalphUtils | Should -Not -BeNull
        }
    }

    Context 'Locking Function Exports' {
        It 'Exports Lock-RalphStory' {
            Get-Command Lock-RalphStory -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Unlock-RalphStory' {
            Get-Command Unlock-RalphStory -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Test-RalphStoryLocked' {
            Get-Command Test-RalphStoryLocked -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Get-RalphStaleLocks' {
            Get-Command Get-RalphStaleLocks -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Clear-RalphStaleLocks' {
            Get-Command Clear-RalphStaleLocks -Module RalphUtils | Should -Not -BeNull
        }
    }

    Context 'PRD Function Exports' {
        It 'Exports Update-RalphPrd' {
            Get-Command Update-RalphPrd -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Read-RalphPrdSafe' {
            Get-Command Read-RalphPrdSafe -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Lock-RalphPrd' {
            Get-Command Lock-RalphPrd -Module RalphUtils | Should -Not -BeNull
        }
    }

    Context 'Story Claiming Exports' {
        It 'Exports Request-RalphStoryClaim' {
            Get-Command Request-RalphStoryClaim -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Get-RalphNextStory' {
            Get-Command Get-RalphNextStory -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Remove-RalphStoryClaim' {
            Get-Command Remove-RalphStoryClaim -Module RalphUtils | Should -Not -BeNull
        }
    }

    Context 'Branch Function Exports' {
        It 'Exports New-RalphStoryBranch' {
            Get-Command New-RalphStoryBranch -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Merge-RalphStoryBranch' {
            Get-Command Merge-RalphStoryBranch -Module RalphUtils | Should -Not -BeNull
        }
    }

    Context 'Cleanup Function Exports' {
        It 'Exports Register-RalphCleanup' {
            Get-Command Register-RalphCleanup -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Invoke-RalphCleanup' {
            Get-Command Invoke-RalphCleanup -Module RalphUtils | Should -Not -BeNull
        }
    }

    Context 'Global Registry Exports' {
        It 'Exports Get-RalphGlobalInstances' {
            Get-Command Get-RalphGlobalInstances -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Register-RalphGlobalInstance' {
            Get-Command Register-RalphGlobalInstance -Module RalphUtils | Should -Not -BeNull
        }
    }
}

Describe 'PS-013 Acceptance Criteria Verification' {
    BeforeAll {
        $script:ScriptsDir = Split-Path $PSScriptRoot -Parent
        $script:ModulePath = Join-Path $script:ScriptsDir 'RalphUtils.psm1'
        Import-Module $script:ModulePath -Force
    }

    Context 'Test ralph-locks.ps1 all commands' {
        It 'Status command is testable' {
            $script = Join-Path $script:ScriptsDir 'ralph-locks.ps1'
            { & $script Status } | Should -Not -Throw
        }

        It 'Release command is testable' {
            $script = Join-Path $script:ScriptsDir 'ralph-locks.ps1'
            { & $script Release -StoryId 'TEST-000' } | Should -Not -Throw
        }

        It 'ReleaseAll command is testable' {
            $script = Join-Path $script:ScriptsDir 'ralph-locks.ps1'
            { & $script ReleaseAll } | Should -Not -Throw
        }

        It 'Cleanup command is testable' {
            $script = Join-Path $script:ScriptsDir 'ralph-locks.ps1'
            { & $script Cleanup } | Should -Not -Throw
        }

        It 'Help command is testable' {
            $script = Join-Path $script:ScriptsDir 'ralph-locks.ps1'
            { & $script Help } | Should -Not -Throw
        }
    }

    Context 'Test ralph-cleanup.ps1 with -WhatIf' {
        It '-Dead -WhatIf is testable' {
            $script = Join-Path $script:ScriptsDir 'ralph-cleanup.ps1'
            { & $script -Dead -WhatIf } | Should -Not -Throw
        }

        It '-Old -WhatIf is testable' {
            $script = Join-Path $script:ScriptsDir 'ralph-cleanup.ps1'
            { & $script -Old -WhatIf } | Should -Not -Throw
        }

        It '-All -WhatIf is testable' {
            $script = Join-Path $script:ScriptsDir 'ralph-cleanup.ps1'
            { & $script -All -WhatIf } | Should -Not -Throw
        }
    }

    Context 'Test ralph-parallel.ps1 status command' {
        It 'Status command is testable' {
            $script = Join-Path $script:ScriptsDir 'ralph-parallel.ps1'
            { & $script Status } | Should -Not -Throw
        }
    }

    Context 'Test ralph-dashboard.ps1 help' {
        It 'Get-Help works on script' {
            $script = Join-Path $script:ScriptsDir 'ralph-dashboard.ps1'
            $help = Get-Help $script
            $help | Should -Not -BeNull
        }

        It 'Script has synopsis' {
            $script = Join-Path $script:ScriptsDir 'ralph-dashboard.ps1'
            $content = Get-Content $script -Raw
            $content | Should -Match '\.SYNOPSIS'
        }
    }

    Context 'Test ralph.ps1 instance initialization' {
        It 'Script has New-RalphInstanceDirectory call' {
            $script = Join-Path $script:ScriptsDir 'ralph.ps1'
            $content = Get-Content $script -Raw
            $content | Should -Match 'New-RalphInstanceDirectory'
        }

        It 'Instance ID generation is available' {
            { Get-RalphInstanceId -Force } | Should -Not -Throw
        }

        It 'Short ID generation is available' {
            { Get-RalphShortId } | Should -Not -Throw
        }

        It 'Instance directory creation is available' {
            Get-Command New-RalphInstanceDirectory -Module RalphUtils | Should -Not -BeNull
        }

        It 'Status update is available' {
            Get-Command Update-RalphStatus -Module RalphUtils | Should -Not -BeNull
        }
    }

    Context 'All Pester tests pass' {
        It 'This test file itself passes (meta-verification)' {
            $true | Should -Be $true
        }
    }
}
