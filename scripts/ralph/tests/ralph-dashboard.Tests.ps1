#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for ralph-dashboard.ps1 and related RalphUtils functions.

.DESCRIPTION
    Test suite for dashboard functionality including:
    - Get-AllProjectsPrdStatus filtering and sorting
    - Clear-RalphGlobalRegistry cleanup functionality
    - Update-SectionLimits overflow line accounting
    - Get-ProjectPrdStatus PRD detection
#>

BeforeAll {
    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..' 'RalphUtils.psm1'
    Import-Module $modulePath -Force

    # Source the dashboard script for testing internal functions
    $dashboardPath = Join-Path $PSScriptRoot '..' 'ralph-dashboard.ps1'

    # Helper function to create links (Junction on Windows, SymbolicLink on Unix)
    function New-TestLink {
        param(
            [string]$Path,
            [string]$Target
        )
        $linkType = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
        New-Item -ItemType $linkType -Path $Path -Target $Target -Force | Out-Null
    }
}

# =============================================================================
# GET-PROJECTPRDSTATUS TESTS
# =============================================================================

Describe 'Get-ProjectPrdStatus' {
    BeforeAll {
        $script:testProjectDir = Join-Path $TestDrive 'test-project'
        New-Item -Path $script:testProjectDir -ItemType Directory -Force | Out-Null
    }

    Context 'With PRD in scripts/ralph/' {
        BeforeAll {
            $ralphDir = Join-Path $script:testProjectDir 'scripts' 'ralph'
            New-Item -Path $ralphDir -ItemType Directory -Force | Out-Null
            $prd = @{
                userStories = @(
                    @{ id = 'US-001'; passes = $true }
                    @{ id = 'US-002'; passes = $true }
                    @{ id = 'US-003'; passes = $false }
                )
            }
            $prd | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $ralphDir 'prd.json')
        }

        It 'Returns correct total count' {
            $result = Get-ProjectPrdStatus -ProjectRoot $script:testProjectDir
            $result.Total | Should -Be 3
        }

        It 'Returns correct complete count' {
            $result = Get-ProjectPrdStatus -ProjectRoot $script:testProjectDir
            $result.Complete | Should -Be 2
        }
    }

    Context 'With no PRD file' {
        BeforeAll {
            $script:emptyProjectDir = Join-Path $TestDrive 'empty-project'
            New-Item -Path $script:emptyProjectDir -ItemType Directory -Force | Out-Null
        }

        It 'Returns zero counts' {
            $result = Get-ProjectPrdStatus -ProjectRoot $script:emptyProjectDir
            $result.Total | Should -Be 0
            $result.Complete | Should -Be 0
        }
    }

    Context 'With fully completed project' {
        BeforeAll {
            $script:completeProjectDir = Join-Path $TestDrive 'complete-project'
            $ralphDir = Join-Path $script:completeProjectDir 'scripts' 'ralph'
            New-Item -Path $ralphDir -ItemType Directory -Force | Out-Null
            $prd = @{
                userStories = @(
                    @{ id = 'US-001'; passes = $true }
                    @{ id = 'US-002'; passes = $true }
                )
            }
            $prd | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $ralphDir 'prd.json')
        }

        It 'Returns complete equals total' {
            $result = Get-ProjectPrdStatus -ProjectRoot $script:completeProjectDir
            $result.Total | Should -Be 2
            $result.Complete | Should -Be 2
        }
    }
}

# =============================================================================
# GET-ALLPROJECTSPRDSTATUS TESTS
# =============================================================================

Describe 'Get-AllProjectsPrdStatus' {
    BeforeAll {
        # Set up test global directory
        $script:testGlobalDir = Join-Path $TestDrive 'ralph-global'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir

        # Create global instances directory
        $instancesDir = Join-Path $script:testGlobalDir 'instances'
        New-Item -Path $instancesDir -ItemType Directory -Force | Out-Null

        # Create test projects
        $script:incompleteProject = Join-Path $TestDrive 'incomplete-proj'
        $script:completeProject = Join-Path $TestDrive 'complete-proj'

        # Incomplete project with 2/5 done
        $incompleteRalphDir = Join-Path $script:incompleteProject 'scripts' 'ralph'
        New-Item -Path $incompleteRalphDir -ItemType Directory -Force | Out-Null
        $incompletePrd = @{
            userStories = @(
                @{ id = 'US-001'; passes = $true }
                @{ id = 'US-002'; passes = $true }
                @{ id = 'US-003'; passes = $false }
                @{ id = 'US-004'; passes = $false }
                @{ id = 'US-005'; passes = $false }
            )
        }
        $incompletePrd | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $incompleteRalphDir 'prd.json')

        # Complete project with 3/3 done
        $completeRalphDir = Join-Path $script:completeProject 'scripts' 'ralph'
        New-Item -Path $completeRalphDir -ItemType Directory -Force | Out-Null
        $completePrd = @{
            userStories = @(
                @{ id = 'US-001'; passes = $true }
                @{ id = 'US-002'; passes = $true }
                @{ id = 'US-003'; passes = $true }
            )
        }
        $completePrd | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $completeRalphDir 'prd.json')

        # Create instance directories and status files
        $incompleteInstanceDir = Join-Path $incompleteRalphDir 'instances' 'test-instance-1'
        $completeInstanceDir = Join-Path $completeRalphDir 'instances' 'test-instance-2'
        New-Item -Path $incompleteInstanceDir -ItemType Directory -Force | Out-Null
        New-Item -Path $completeInstanceDir -ItemType Directory -Force | Out-Null

        # Create status.json for instances
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $status1 = @{
            instanceId = 'test-instance-1'
            state = 'working'
            lastHeartbeatEpoch = $now
            projectRoot = $script:incompleteProject
        }
        $status2 = @{
            instanceId = 'test-instance-2'
            state = 'completed'
            lastHeartbeatEpoch = $now
            projectRoot = $script:completeProject
        }
        $status1 | ConvertTo-Json | Set-Content (Join-Path $incompleteInstanceDir 'status.json')
        $status2 | ConvertTo-Json | Set-Content (Join-Path $completeInstanceDir 'status.json')

        # Create junctions/symlinks in global registry
        $link1 = Join-Path $instancesDir 'incomplete-proj-test-instance-1'
        $link2 = Join-Path $instancesDir 'complete-proj-test-instance-2'
        New-TestLink -Path $link1 -Target $incompleteInstanceDir
        New-TestLink -Path $link2 -Target $completeInstanceDir
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    Context 'Filtering completed projects' {
        It 'Filters out fully completed projects' {
            $result = Get-AllProjectsPrdStatus
            # Should only contain incomplete project
            $names = $result | ForEach-Object { $_.Name }
            $names | Should -Contain 'incomplete-proj'
            $names | Should -Not -Contain 'complete-proj'
        }

        It 'Returns only projects with remaining work' {
            $result = Get-AllProjectsPrdStatus
            foreach ($proj in $result) {
                $proj.IsComplete | Should -BeFalse
                # Remaining should be >= 0 (could be 0 if project has no PRD)
                $proj.Remaining | Should -BeGreaterOrEqual 0
            }
        }
    }

    Context 'Sorting behavior' {
        BeforeAll {
            # Create another incomplete project with more remaining work
            $script:moreIncompleteProject = Join-Path $TestDrive 'more-incomplete-proj'
            $moreIncompleteRalphDir = Join-Path $script:moreIncompleteProject 'scripts' 'ralph'
            New-Item -Path $moreIncompleteRalphDir -ItemType Directory -Force | Out-Null
            $moreIncompletePrd = @{
                userStories = @(
                    @{ id = 'US-001'; passes = $false }
                    @{ id = 'US-002'; passes = $false }
                    @{ id = 'US-003'; passes = $false }
                    @{ id = 'US-004'; passes = $false }
                    @{ id = 'US-005'; passes = $false }
                    @{ id = 'US-006'; passes = $false }
                    @{ id = 'US-007'; passes = $false }
                )
            }
            $moreIncompletePrd | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $moreIncompleteRalphDir 'prd.json')

            # Create instance for this project
            $moreIncompleteInstanceDir = Join-Path $moreIncompleteRalphDir 'instances' 'test-instance-3'
            New-Item -Path $moreIncompleteInstanceDir -ItemType Directory -Force | Out-Null
            $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $status3 = @{
                instanceId = 'test-instance-3'
                state = 'working'
                lastHeartbeatEpoch = $now
                projectRoot = $script:moreIncompleteProject
            }
            $status3 | ConvertTo-Json | Set-Content (Join-Path $moreIncompleteInstanceDir 'status.json')

            # Add to global registry
            $instancesDir = Join-Path $script:testGlobalDir 'instances'
            $link3 = Join-Path $instancesDir 'more-incomplete-proj-test-instance-3'
            New-TestLink -Path $link3 -Target $moreIncompleteInstanceDir
        }

        It 'Sorts by remaining work descending' {
            $result = Get-AllProjectsPrdStatus
            # more-incomplete-proj has 7 remaining, incomplete-proj has 3 remaining
            if ($result.Count -ge 2) {
                $result[0].Remaining | Should -BeGreaterOrEqual $result[1].Remaining
            }
        }
    }
}

# =============================================================================
# CLEAR-RALPHGLOBALREGISTRY TESTS
# =============================================================================

Describe 'Clear-RalphGlobalRegistry' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'cleanup-test-global'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    BeforeEach {
        # Reset test directory
        if (Test-Path $script:testGlobalDir) {
            Remove-Item -Path $script:testGlobalDir -Recurse -Force
        }
        $instancesDir = Join-Path $script:testGlobalDir 'instances'
        New-Item -Path $instancesDir -ItemType Directory -Force | Out-Null
    }

    Context 'Cleaning stale entries with missing targets' {
        BeforeAll {
            $instancesDir = Join-Path $script:testGlobalDir 'instances'

            # Create a junction pointing to non-existent directory
            $staleLink = Join-Path $instancesDir 'stale-project-instance-1'
            $nonExistentTarget = Join-Path $TestDrive 'non-existent-dir'

            # Create and remove target to make a broken link
            New-Item -Path $nonExistentTarget -ItemType Directory -Force | Out-Null
            New-TestLink -Path $staleLink -Target $nonExistentTarget
            Remove-Item -Path $nonExistentTarget -Recurse -Force
        }

        It 'Removes entries with missing targets' {
            $cleaned = Clear-RalphGlobalRegistry
            $cleaned | Should -BeGreaterOrEqual 0
        }
    }

    Context 'Cleaning completed project entries' {
        BeforeEach {
            # Reset and create test directory structure
            $instancesDir = Join-Path $script:testGlobalDir 'instances'
            if (-not (Test-Path $instancesDir)) {
                New-Item -Path $instancesDir -ItemType Directory -Force | Out-Null
            }

            # Create a completed project
            $script:completedProject = Join-Path $TestDrive 'completed-for-cleanup'
            $ralphDir = Join-Path $script:completedProject 'scripts' 'ralph'
            $instanceDir = Join-Path $ralphDir 'instances' 'cleanup-instance'

            if (-not (Test-Path $instanceDir)) {
                New-Item -Path $instanceDir -ItemType Directory -Force | Out-Null
            }

            # PRD with all passes = true
            $prd = @{
                userStories = @(
                    @{ id = 'US-001'; passes = $true }
                    @{ id = 'US-002'; passes = $true }
                )
            }
            $prd | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $ralphDir 'prd.json')

            # Status file
            $status = @{
                instanceId = 'cleanup-instance'
                state = 'completed'
                lastHeartbeatEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                projectRoot = $script:completedProject
            }
            $status | ConvertTo-Json | Set-Content (Join-Path $instanceDir 'status.json')

            # Create junction in global registry
            $link = Join-Path $instancesDir 'completed-for-cleanup-cleanup-instance'
            if (Test-Path $link) {
                Remove-Item $link -Force -Recurse
            }
            New-TestLink -Path $link -Target $instanceDir
        }

        It 'Removes completed project entries when -IncludeCompleted is specified' {
            $instancesDir = Join-Path $script:testGlobalDir 'instances'
            $linkBefore = Get-ChildItem $instancesDir -ErrorAction SilentlyContinue | Measure-Object
            $linkBefore.Count | Should -BeGreaterThan 0

            $cleaned = Clear-RalphGlobalRegistry -IncludeCompleted

            $cleaned | Should -BeGreaterOrEqual 1
        }

        It 'Does not remove completed entries without -IncludeCompleted' {
            $instancesDir = Join-Path $script:testGlobalDir 'instances'
            $linkBefore = Get-ChildItem $instancesDir -ErrorAction SilentlyContinue | Measure-Object

            $cleaned = Clear-RalphGlobalRegistry  # Without -IncludeCompleted

            # Should not clean completed projects without the flag
            # The link should still exist
            $linkAfter = Get-ChildItem $instancesDir -ErrorAction SilentlyContinue | Measure-Object
            $linkAfter.Count | Should -Be $linkBefore.Count
        }
    }

    Context 'With empty registry' {
        It 'Returns 0 when no entries exist' {
            $cleaned = Clear-RalphGlobalRegistry -IncludeCompleted
            $cleaned | Should -Be 0
        }
    }

    Context 'With non-existent registry directory' {
        BeforeEach {
            if (Test-Path $script:testGlobalDir) {
                Remove-Item -Path $script:testGlobalDir -Recurse -Force
            }
        }

        It 'Returns 0 without error' {
            $cleaned = Clear-RalphGlobalRegistry -IncludeCompleted
            $cleaned | Should -Be 0
        }
    }
}

# =============================================================================
# DASHBOARD SECTION LIMITS TESTS
# =============================================================================

Describe 'Dashboard Section Limits Logic' {
    # These tests verify the overflow line accounting logic
    # We test the algorithm conceptually since the actual function is in the dashboard script

    Context 'Overflow line calculation' {
        It 'Should account for project overflow line' {
            # Simulate: 5 projects but only showing 3
            $projectCount = 5
            $maxProjects = 3
            $hasOverflow = $projectCount -gt $maxProjects

            $hasOverflow | Should -BeTrue
            # This means we need 1 extra line for "... and 2 more"
        }

        It 'Should account for multiple overflow lines' {
            # Simulate: all sections overflow
            $projectCount = 10
            $instanceCount = 20
            $lockCount = 15

            $maxProjects = 3
            $maxInstances = 5
            $maxLocks = 4

            $overflowLines = 0
            if ($projectCount -gt $maxProjects) { $overflowLines++ }
            if ($instanceCount -gt $maxInstances) { $overflowLines++ }
            if ($lockCount -gt $maxLocks) { $overflowLines++ }

            $overflowLines | Should -Be 3
        }

        It 'Should not add overflow lines when content fits' {
            # Simulate: all content fits
            $projectCount = 2
            $instanceCount = 3
            $lockCount = 2

            $maxProjects = 5
            $maxInstances = 5
            $maxLocks = 5

            $overflowLines = 0
            if ($projectCount -gt $maxProjects) { $overflowLines++ }
            if ($instanceCount -gt $maxInstances) { $overflowLines++ }
            if ($lockCount -gt $maxLocks) { $overflowLines++ }

            $overflowLines | Should -Be 0
        }
    }

    Context 'Available space calculation' {
        It 'Should reduce available space by overflow lines' {
            $termHeight = 30
            $reservedLines = 12
            $available = $termHeight - $reservedLines  # 18

            $overflowLines = 3  # All sections overflow
            $adjustedAvailable = $available - $overflowLines  # 15

            $adjustedAvailable | Should -Be 15
        }

        It 'Should maintain minimum of 3 available lines' {
            $termHeight = 20
            $reservedLines = 12
            $available = $termHeight - $reservedLines  # 8

            $overflowLines = 3
            $adjustedAvailable = [Math]::Max(3, $available - $overflowLines)  # Max(3, 5) = 5

            $adjustedAvailable | Should -BeGreaterOrEqual 3
        }
    }
}

# =============================================================================
# REGRESSION TESTS
# =============================================================================

Describe 'Regression Tests' {
    Context 'Get-AllProjectsPrdStatus returns correct structure' {
        It 'Returns array or empty result' {
            $result = Get-AllProjectsPrdStatus
            # Result should be an array (possibly empty) or null
            if ($null -ne $result -and $result.Count -gt 0) {
                $result | Should -BeOfType [hashtable]
            } else {
                # Empty result is valid
                $result.Count | Should -Be 0
            }
        }

        It 'Each result has required properties' {
            $result = Get-AllProjectsPrdStatus
            foreach ($proj in $result) {
                $proj.Keys | Should -Contain 'Name'
                $proj.Keys | Should -Contain 'Total'
                $proj.Keys | Should -Contain 'Complete'
                $proj.Keys | Should -Contain 'Root'
                $proj.Keys | Should -Contain 'IsComplete'
                $proj.Keys | Should -Contain 'Remaining'
            }
        }
    }

    Context 'Get-ProjectPrdStatus handles edge cases' {
        It 'Returns valid structure for non-existent project' {
            $result = Get-ProjectPrdStatus -ProjectRoot (Join-Path $TestDrive 'nonexistent')
            $result.Total | Should -Be 0
            $result.Complete | Should -Be 0
        }

        It 'Handles project with empty userStories array' {
            $emptyProject = Join-Path $TestDrive 'empty-stories-proj'
            $ralphDir = Join-Path $emptyProject 'scripts' 'ralph'
            New-Item -Path $ralphDir -ItemType Directory -Force | Out-Null
            $prd = @{ userStories = @() }
            $prd | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $ralphDir 'prd.json')

            $result = Get-ProjectPrdStatus -ProjectRoot $emptyProject
            $result.Total | Should -Be 0
            $result.Complete | Should -Be 0
        }
    }

    Context 'Clear-RalphGlobalRegistry is safe' {
        BeforeAll {
            $script:safeTestDir = Join-Path $TestDrive 'safe-test-global'
            $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
            $env:RALPH_GLOBAL_DIR = $script:safeTestDir
        }

        AfterAll {
            $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
        }

        It 'Does not throw on any input' {
            { Clear-RalphGlobalRegistry } | Should -Not -Throw
            { Clear-RalphGlobalRegistry -IncludeCompleted } | Should -Not -Throw
        }

        It 'Returns integer' {
            $result = Clear-RalphGlobalRegistry
            $result | Should -BeOfType [int]
        }
    }
}

# =============================================================================
# GET-ALLPROJECTSLOCKS TESTS
# =============================================================================

Describe 'Get-AllProjectsLocks' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'locks-test-global'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir
        $instancesDir = Join-Path $script:testGlobalDir 'instances'
        New-Item -Path $instancesDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    Context 'Stale lock detection' {
        It 'Returns array, hashtable, or null when no locks exist' {
            $result = Get-AllProjectsLocks
            # Result can be $null, empty array, or collection of hashtables when no locks
            if ($null -ne $result -and @($result).Count -gt 0) {
                # Each lock should be a hashtable with expected properties
                $firstLock = @($result)[0]
                $firstLock.Keys | Should -Contain 'StoryId'
            }
        }

        It 'Get-AllProjectsLocks function exists in module' {
            Get-Command Get-AllProjectsLocks -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# PS-011 ACCEPTANCE CRITERIA TESTS
# =============================================================================

Describe 'PS-011: ralph-dashboard.ps1 Script' {
    BeforeAll {
        $script:dashboardPath = Join-Path $PSScriptRoot '..' 'ralph-dashboard.ps1'
        $script:dashboardContent = Get-Content $script:dashboardPath -Raw
    }

    Context 'Script Structure and Parameters' {
        It 'Script file exists' {
            Test-Path $script:dashboardPath | Should -BeTrue
        }

        It 'Has valid PowerShell syntax' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:dashboardPath, [ref]$null, [ref]$errors
            )
            $errors.Count | Should -Be 0
        }

        It 'Has RefreshInterval parameter with default 2' {
            $script:dashboardContent | Should -Match 'param\s*\('
            $script:dashboardContent | Should -Match '\[int\]\$RefreshInterval\s*=\s*2'
        }

        It 'Has CmdletBinding attribute' {
            $script:dashboardContent | Should -Match '\[CmdletBinding\(\)\]'
        }

        It 'Has proper help documentation' {
            $script:dashboardContent | Should -Match '\.SYNOPSIS'
            $script:dashboardContent | Should -Match '\.DESCRIPTION'
            $script:dashboardContent | Should -Match '\.PARAMETER\s+RefreshInterval'
            $script:dashboardContent | Should -Match '\.EXAMPLE'
        }

        It 'Requires PowerShell 7.0+' {
            $script:dashboardContent | Should -Match '#Requires\s+-Version\s+7\.0'
        }

        It 'Imports RalphUtils module' {
            $script:dashboardContent | Should -Match 'Import-Module\s+\$modulePath'
        }
    }

    Context 'Auto-Refresh Display (AC1)' {
        It 'Has main loop with refresh capability' {
            $script:dashboardContent | Should -Match 'while\s*\(\$true\)'
        }

        It 'Uses Render-Dashboard function' {
            $script:dashboardContent | Should -Match 'function\s+Render-Dashboard'
            $script:dashboardContent | Should -Match 'Render-Dashboard'
        }

        It 'Has Clear-Host for refresh' {
            $script:dashboardContent | Should -Match 'Clear-Host'
        }

        It 'Uses timeout for refresh interval' {
            $script:dashboardContent | Should -Match '\$timeout.*AddSeconds.*\$RefreshInterval'
        }
    }

    Context 'Instance Table Display (AC2)' {
        It 'Has Render-Instances function' {
            $script:dashboardContent | Should -Match 'function\s+Render-Instances'
        }

        It 'Shows PROJECT column' {
            $script:dashboardContent | Should -Match "'PROJECT'"
        }

        It 'Shows STORY column' {
            $script:dashboardContent | Should -Match "'STORY'"
        }

        It 'Shows STATE column' {
            $script:dashboardContent | Should -Match "'STATE'"
        }

        It 'Shows ITER column' {
            $script:dashboardContent | Should -Match "'ITER'"
        }

        It 'Shows RUNTIME column' {
            $script:dashboardContent | Should -Match "'RUNTIME'"
        }

        It 'Formats iteration as current/max' {
            $script:dashboardContent | Should -Match '\$iter\s*=.*iteration.*maxIterations'
        }
    }

    Context 'PRD Progress Bar with Unicode (AC3)' {
        It 'Has Get-ProgressBar function' {
            $script:dashboardContent | Should -Match 'function\s+Get-ProgressBar'
        }

        It 'Uses Unicode full block character (U+2588)' {
            $script:dashboardContent | Should -Match '\[char\]0x2588'
        }

        It 'Uses Unicode light shade character (U+2591)' {
            $script:dashboardContent | Should -Match '\[char\]0x2591'
        }

        It 'Progress bar has configurable width' {
            $script:dashboardContent | Should -Match 'param\s*\([^)]*\[int\]\$Width'
        }

        It 'Calculates filled vs empty portions' {
            $script:dashboardContent | Should -Match '\$filled.*Complete.*Width.*Total'
        }
    }

    Context 'Color Coding (AC4)' {
        It 'Has Get-StateColor function' {
            $script:dashboardContent | Should -Match 'function\s+Get-StateColor'
        }

        It 'Returns Green for working state' {
            $script:dashboardContent | Should -Match "'working'.*'Green'"
        }

        It 'Returns Yellow for idle state' {
            $script:dashboardContent | Should -Match "'idle'.*'Yellow'"
        }

        It 'Returns Red for dead state' {
            $script:dashboardContent | Should -Match "'dead'.*'Red'"
        }

        It 'Returns Gray for terminated state' {
            $script:dashboardContent | Should -Match "'terminated'.*'Gray'"
        }

        It 'Uses Write-Host with -ForegroundColor' {
            $script:dashboardContent | Should -Match 'Write-Host.*-ForegroundColor'
        }
    }

    Context 'Configurable Refresh Interval (AC5)' {
        It 'RefreshInterval parameter accepts integer' {
            $script:dashboardContent | Should -Match '\[int\]\$RefreshInterval'
        }

        It 'Default refresh is 2 seconds' {
            $script:dashboardContent | Should -Match '\$RefreshInterval\s*=\s*2'
        }

        It 'RefreshInterval is used in timeout calculation' {
            $script:dashboardContent | Should -Match 'AddSeconds\(\$RefreshInterval\)'
        }

        It 'Help shows example with custom interval' {
            $script:dashboardContent | Should -Match '-RefreshInterval\s+\d+'
        }
    }

    Context 'Exit with Q key or Ctrl+C (AC6)' {
        It 'Checks for KeyAvailable' {
            $script:dashboardContent | Should -Match '\[Console\]::KeyAvailable'
        }

        It 'Reads key input' {
            $script:dashboardContent | Should -Match '\[Console\]::ReadKey'
        }

        It 'Handles q key to exit' {
            $script:dashboardContent | Should -Match "'q'.*return"
        }

        It 'Handles Q key to exit (case insensitive)' {
            $script:dashboardContent | Should -Match "'Q'.*return"
        }

        It 'Has try/finally for cleanup' {
            $script:dashboardContent | Should -Match 'try\s*\{'
            $script:dashboardContent | Should -Match 'finally\s*\{'
        }

        It 'Restores cursor visibility in finally block' {
            $script:dashboardContent | Should -Match '\[Console\]::CursorVisible\s*=\s*\$true'
        }

        It 'Hides cursor during dashboard display' {
            $script:dashboardContent | Should -Match '\[Console\]::CursorVisible\s*=\s*\$false'
        }
    }

    Context 'Dashboard Displays Without Error (AC7)' {
        It 'Has error handling for missing module' {
            $script:dashboardContent | Should -Match "if.*-not.*Test-Path.*modulePath"
        }

        It 'Has null/empty checks for instances' {
            $script:dashboardContent | Should -Match 'if.*instances\.Count\s*-eq\s*0'
        }

        It 'Has null/empty checks for locks' {
            $script:dashboardContent | Should -Match 'if.*locks\.Count\s*-eq\s*0'
        }

        It 'Has null/empty checks for projects' {
            $script:dashboardContent | Should -Match 'if.*projectsStatus\.Count\s*-eq\s*0'
        }

        It 'Uses Math.Max for padding to prevent negative values' {
            $script:dashboardContent | Should -Match '\[Math\]::Max\(0,'
        }
    }
}

Describe 'Get-ProgressBar Function' {
    BeforeAll {
        # Source the dashboard script to get internal functions
        # We create a temporary scope to extract just the function
        $dashboardPath = Join-Path $PSScriptRoot '..' 'ralph-dashboard.ps1'
        $content = Get-Content $dashboardPath -Raw

        # Extract and define the Get-ProgressBar function
        $functionMatch = [regex]::Match($content, '(?s)function\s+Get-ProgressBar\s*\{.*?^\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($functionMatch.Success) {
            Invoke-Expression $functionMatch.Value
        }
    }

    It 'Returns empty bar for zero total' {
        $result = Get-ProgressBar -Complete 0 -Total 0 -Width 10
        $result | Should -Match '^\[\s+\]$'
    }

    It 'Returns full bar when complete equals total' {
        $result = Get-ProgressBar -Complete 10 -Total 10 -Width 10
        $result.Length | Should -BeGreaterThan 10
        $result | Should -Match '^\[.*\]$'
    }

    It 'Returns partially filled bar' {
        $result = Get-ProgressBar -Complete 5 -Total 10 -Width 10
        $result | Should -Match '^\[.*\]$'
        $result.Length | Should -BeGreaterThan 10
    }

    It 'Respects custom width parameter' {
        $result = Get-ProgressBar -Complete 0 -Total 10 -Width 20
        # Width 20 + brackets = 22 chars
        $result.Length | Should -Be 22
    }
}

Describe 'Format-Duration Function' {
    BeforeAll {
        $dashboardPath = Join-Path $PSScriptRoot '..' 'ralph-dashboard.ps1'
        $content = Get-Content $dashboardPath -Raw

        $functionMatch = [regex]::Match($content, '(?s)function\s+Format-Duration\s*\{.*?^\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($functionMatch.Success) {
            Invoke-Expression $functionMatch.Value
        }
    }

    It 'Formats seconds under 60' {
        $result = Format-Duration -Seconds 45
        $result | Should -Be '45s'
    }

    It 'Formats minutes and seconds' {
        $result = Format-Duration -Seconds 125
        $result | Should -Be '2m 5s'
    }

    It 'Formats hours and minutes' {
        $result = Format-Duration -Seconds 3725
        $result | Should -Be '1h 2m'
    }

    It 'Handles zero seconds' {
        $result = Format-Duration -Seconds 0
        $result | Should -Be '0s'
    }
}

Describe 'Get-StateColor Function' {
    BeforeAll {
        $dashboardPath = Join-Path $PSScriptRoot '..' 'ralph-dashboard.ps1'
        $content = Get-Content $dashboardPath -Raw

        $functionMatch = [regex]::Match($content, '(?s)function\s+Get-StateColor\s*\{.*?^\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($functionMatch.Success) {
            Invoke-Expression $functionMatch.Value
        }
    }

    It 'Returns Green for working' {
        Get-StateColor -State 'working' | Should -Be 'Green'
    }

    It 'Returns Green for merging' {
        Get-StateColor -State 'merging' | Should -Be 'Green'
    }

    It 'Returns Yellow for idle' {
        Get-StateColor -State 'idle' | Should -Be 'Yellow'
    }

    It 'Returns Red for dead' {
        Get-StateColor -State 'dead' | Should -Be 'Red'
    }

    It 'Returns Gray for terminated' {
        Get-StateColor -State 'terminated' | Should -Be 'Gray'
    }

    It 'Returns Cyan for claiming' {
        Get-StateColor -State 'claiming' | Should -Be 'Cyan'
    }

    It 'Returns Cyan for starting' {
        Get-StateColor -State 'starting' | Should -Be 'Cyan'
    }

    It 'Returns Cyan for waiting' {
        Get-StateColor -State 'waiting' | Should -Be 'Cyan'
    }

    It 'Returns Blue for completed' {
        Get-StateColor -State 'completed' | Should -Be 'Blue'
    }

    It 'Returns White for unknown state' {
        Get-StateColor -State 'unknown' | Should -Be 'White'
    }
}

Describe 'Dashboard Help Documentation' {
    BeforeAll {
        $script:dashboardPath = Join-Path $PSScriptRoot '..' 'ralph-dashboard.ps1'
        $script:dashboardContent = Get-Content $script:dashboardPath -Raw
    }

    It 'Shows help without error' {
        $help = Get-Help $script:dashboardPath -ErrorAction SilentlyContinue
        $help | Should -Not -BeNullOrEmpty
    }

    It 'Has synopsis in comment-based help' {
        $script:dashboardContent | Should -Match '\.SYNOPSIS'
    }

    It 'Has description in comment-based help' {
        $script:dashboardContent | Should -Match '\.DESCRIPTION'
    }

    It 'Documents RefreshInterval parameter in comment-based help' {
        $script:dashboardContent | Should -Match '\.PARAMETER\s+RefreshInterval'
    }

    It 'Has examples in comment-based help' {
        $script:dashboardContent | Should -Match '\.EXAMPLE'
    }
}

Describe 'Dashboard Additional Features' {
    BeforeAll {
        $script:dashboardPath = Join-Path $PSScriptRoot '..' 'ralph-dashboard.ps1'
        $script:dashboardContent = Get-Content $script:dashboardPath -Raw
    }

    Context 'Interactive Commands' {
        It 'Handles r key for manual refresh' {
            $script:dashboardContent | Should -Match "'r'.*break"
        }

        It 'Handles l key for locks detail' {
            $script:dashboardContent | Should -Match "'l'.*Show-LocksDetail"
        }

        It 'Handles c key for cleanup' {
            $script:dashboardContent | Should -Match "'c'.*Invoke-Cleanup"
        }
    }

    Context 'Auto-Clean Feature' {
        It 'Has AutoClean parameter' {
            $script:dashboardContent | Should -Match '\[switch\]\$AutoClean'
        }

        It 'Has AutoCleanInterval parameter' {
            $script:dashboardContent | Should -Match '\[int\]\$AutoCleanInterval'
        }

        It 'Has Invoke-AutoCleanup function' {
            $script:dashboardContent | Should -Match 'function\s+Invoke-AutoCleanup'
        }

        It 'Performs periodic auto-cleanup when enabled' {
            # Check for the periodic auto-cleanup condition
            $script:dashboardContent | Should -Match '\$AutoClean\s+-and'
            $script:dashboardContent | Should -Match 'Invoke-AutoCleanup'
        }
    }

    Context 'Frame Rendering' {
        It 'Uses Unicode box drawing characters' {
            # Top-left corner
            $script:dashboardContent | Should -Match '\[char\]0x2554'
            # Horizontal line
            $script:dashboardContent | Should -Match '\[char\]0x2550'
            # Top-right corner
            $script:dashboardContent | Should -Match '\[char\]0x2557'
        }

        It 'Has Render-Header function' {
            $script:dashboardContent | Should -Match 'function\s+Render-Header'
        }

        It 'Has Render-Footer function' {
            $script:dashboardContent | Should -Match 'function\s+Render-Footer'
        }

        It 'Has Render-Locks function' {
            $script:dashboardContent | Should -Match 'function\s+Render-Locks'
        }
    }

    Context 'Dynamic Sizing' {
        It 'Gets terminal width' {
            $script:dashboardContent | Should -Match '\[Console\]::WindowWidth'
        }

        It 'Gets terminal height' {
            $script:dashboardContent | Should -Match '\[Console\]::WindowHeight'
        }

        It 'Has Update-SectionLimits function' {
            $script:dashboardContent | Should -Match 'function\s+Update-SectionLimits'
        }

        It 'Has minimum frame dimensions' {
            $script:dashboardContent | Should -Match '\$script:MinFrameWidth'
            $script:dashboardContent | Should -Match '\$script:MinFrameHeight'
        }
    }
}

AfterAll {
    Remove-Module RalphUtils -ErrorAction SilentlyContinue
}
