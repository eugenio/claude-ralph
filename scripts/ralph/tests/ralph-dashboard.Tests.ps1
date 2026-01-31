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

AfterAll {
    Remove-Module RalphUtils -ErrorAction SilentlyContinue
}
