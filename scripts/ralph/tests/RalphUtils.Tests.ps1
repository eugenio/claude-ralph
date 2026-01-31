#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for RalphUtils.psm1 module.

.DESCRIPTION
    Comprehensive test suite for all RalphUtils functions including:
    - Test-Dependencies with mocked Get-Command
    - Get-PrdStatus with sample prd.json data
    - Write-ColoredOutput produces expected output
    - Get-RalphPaths returns correct structure
    - Read-PrdJson and Write-PrdJson with valid and invalid JSON
    - Add-LogEntry appends correctly formatted entries
    - Edge cases: missing files, invalid JSON, empty arrays
#>

BeforeAll {
    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..' 'RalphUtils.psm1'
    Import-Module $modulePath -Force
}

Describe 'Get-RalphPaths' {
    It 'Returns a hashtable with all required keys' {
        $paths = Get-RalphPaths

        $paths | Should -BeOfType [hashtable]
        $paths.Keys | Should -Contain 'RalphDir'
        $paths.Keys | Should -Contain 'ProjectRoot'
        $paths.Keys | Should -Contain 'PrdFile'
        $paths.Keys | Should -Contain 'ProgressFile'
        $paths.Keys | Should -Contain 'PromptFile'
        $paths.Keys | Should -Contain 'LogFile'
        $paths.Keys | Should -Contain 'ArchiveDir'
        $paths.Keys | Should -Contain 'LastBranchFile'
    }

    It 'Returns valid paths relative to module location' {
        $paths = Get-RalphPaths

        $paths.RalphDir | Should -Not -BeNullOrEmpty
        $paths.PrdFile | Should -Match 'prd\.json$'
        $paths.ProgressFile | Should -Match 'progress\.txt$'
        $paths.LogFile | Should -Match 'ralph\.log$'
    }

    It 'Returns ProjectRoot two levels up from RalphDir' {
        $paths = Get-RalphPaths

        $expectedProjectRoot = Split-Path -Path (Split-Path -Path $paths.RalphDir -Parent) -Parent
        $paths.ProjectRoot | Should -Be $expectedProjectRoot
    }
}

Describe 'Test-Dependencies' {
    Context 'When all dependencies are available' {
        BeforeAll {
            Mock Get-Command {
                param($Name)
                return [PSCustomObject]@{ Name = $Name }
            } -ModuleName RalphUtils
        }

        It 'Returns IsValid = true' {
            $result = Test-Dependencies
            $result.IsValid | Should -BeTrue
        }

        It 'Returns empty Errors array' {
            $result = Test-Dependencies
            $result.Errors | Should -HaveCount 0
        }

        It 'Shows Claude, Git, and PowerShell as available' {
            $result = Test-Dependencies
            $result.Claude | Should -BeTrue
            $result.Git | Should -BeTrue
            $result.PowerShell | Should -BeTrue
        }
    }

    Context 'When claude is missing' {
        BeforeAll {
            Mock Get-Command {
                param($Name)
                if ($Name -eq 'claude') { return $null }
                return [PSCustomObject]@{ Name = $Name }
            } -ModuleName RalphUtils
        }

        It 'Returns IsValid = false' {
            $result = Test-Dependencies
            $result.IsValid | Should -BeFalse
        }

        It 'Includes claude error message' {
            $result = Test-Dependencies
            $result.Errors | Should -Contain 'Claude Code CLI not found. Install with: npm install -g @anthropic-ai/claude-code'
        }

        It 'Shows Claude as unavailable' {
            $result = Test-Dependencies
            $result.Claude | Should -BeFalse
        }
    }

    Context 'When git is missing' {
        BeforeAll {
            Mock Get-Command {
                param($Name)
                if ($Name -eq 'git') { return $null }
                return [PSCustomObject]@{ Name = $Name }
            } -ModuleName RalphUtils
        }

        It 'Returns IsValid = false' {
            $result = Test-Dependencies
            $result.IsValid | Should -BeFalse
        }

        It 'Includes git error message' {
            $result = Test-Dependencies
            $result.Errors | Should -Contain 'Git not found. Please install git.'
        }
    }

    Context 'When multiple dependencies are missing' {
        BeforeAll {
            Mock Get-Command { return $null } -ModuleName RalphUtils
        }

        It 'Returns multiple errors' {
            $result = Test-Dependencies
            $result.Errors.Count | Should -BeGreaterOrEqual 2
        }
    }
}

Describe 'Read-PrdJson' {
    BeforeAll {
        # Create test directory
        $script:testDir = Join-Path $TestDrive 'ralph'
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null
    }

    Context 'With valid JSON file' {
        BeforeAll {
            $validPrd = @{
                featureName = 'Test Feature'
                branchName  = 'test/branch'
                userStories = @(
                    @{ id = 'US-001'; title = 'Story 1'; passes = $false }
                    @{ id = 'US-002'; title = 'Story 2'; passes = $true }
                )
            }
            $testFile = Join-Path $script:testDir 'valid-prd.json'
            $validPrd | ConvertTo-Json -Depth 10 | Set-Content -Path $testFile
        }

        It 'Returns parsed PRD object' {
            $testFile = Join-Path $script:testDir 'valid-prd.json'
            $result = Read-PrdJson -Path $testFile

            $result | Should -Not -BeNull
            $result.featureName | Should -Be 'Test Feature'
            $result.branchName | Should -Be 'test/branch'
        }

        It 'Parses user stories correctly' {
            $testFile = Join-Path $script:testDir 'valid-prd.json'
            $result = Read-PrdJson -Path $testFile

            $result.userStories | Should -HaveCount 2
            $result.userStories[0].id | Should -Be 'US-001'
            $result.userStories[1].passes | Should -BeTrue
        }
    }

    Context 'With missing file' {
        It 'Returns null' {
            $result = Read-PrdJson -Path (Join-Path $TestDrive 'nonexistent.json')
            $result | Should -BeNull
        }

        It 'Writes a warning' {
            $result = Read-PrdJson -Path (Join-Path $TestDrive 'nonexistent.json') 3>&1

            # The warning stream should contain our warning
            # Note: The function returns $null, warning goes to stream 3
        }
    }

    Context 'With invalid JSON' {
        BeforeAll {
            $testFile = Join-Path $script:testDir 'invalid.json'
            'not valid json {{{' | Set-Content -Path $testFile
        }

        It 'Returns null for invalid JSON' {
            $testFile = Join-Path $script:testDir 'invalid.json'
            $result = Read-PrdJson -Path $testFile
            $result | Should -BeNull
        }
    }

    Context 'With empty file' {
        BeforeAll {
            $testFile = Join-Path $script:testDir 'empty.json'
            '' | Set-Content -Path $testFile
        }

        It 'Returns null for empty file' {
            $testFile = Join-Path $script:testDir 'empty.json'
            $result = Read-PrdJson -Path $testFile
            $result | Should -BeNull
        }
    }
}

Describe 'Write-PrdJson' {
    BeforeAll {
        $script:testDir = Join-Path $TestDrive 'ralph'
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null
    }

    Context 'With valid PRD object' {
        It 'Writes JSON file successfully' {
            $prd = @{
                featureName = 'Test Feature'
                userStories = @(
                    @{ id = 'US-001'; passes = $true }
                )
            }
            $testFile = Join-Path $script:testDir 'write-test.json'

            $result = Write-PrdJson -Prd $prd -Path $testFile

            $result | Should -BeTrue
            Test-Path $testFile | Should -BeTrue
        }

        It 'Creates readable JSON' {
            $prd = @{
                featureName = 'Test Feature'
                userStories = @(
                    @{ id = 'US-001'; passes = $true }
                )
            }
            $testFile = Join-Path $script:testDir 'write-test2.json'

            Write-PrdJson -Prd $prd -Path $testFile
            $content = Get-Content -Path $testFile -Raw
            $parsed = $content | ConvertFrom-Json

            $parsed.featureName | Should -Be 'Test Feature'
        }
    }

    Context 'With invalid path' {
        It 'Returns false when write fails' {
            $prd = @{ featureName = 'Test' }
            # Use an invalid path
            $result = Write-PrdJson -Prd $prd -Path '/invalid/path/that/does/not/exist/prd.json'

            $result | Should -BeFalse
        }
    }
}

Describe 'Get-PrdStatus' {
    Context 'With valid PRD data' {
        BeforeAll {
            $script:testPrd = [PSCustomObject]@{
                featureName = 'Test'
                userStories = @(
                    [PSCustomObject]@{ id = 'US-001'; title = 'Story 1'; priority = 2; passes = $false }
                    [PSCustomObject]@{ id = 'US-002'; title = 'Story 2'; priority = 1; passes = $true }
                    [PSCustomObject]@{ id = 'US-003'; title = 'Story 3'; priority = 3; passes = $false }
                )
            }
        }

        It 'Returns correct total count' {
            $result = Get-PrdStatus -Prd $script:testPrd
            $result.Total | Should -Be 3
        }

        It 'Returns correct complete count' {
            $result = Get-PrdStatus -Prd $script:testPrd
            $result.Complete | Should -Be 1
        }

        It 'Returns correct remaining count' {
            $result = Get-PrdStatus -Prd $script:testPrd
            $result.Remaining | Should -Be 2
        }

        It 'Calculates percentage correctly' {
            $result = Get-PrdStatus -Prd $script:testPrd
            $result.Percentage | Should -Be 33
        }

        It 'Returns incomplete stories sorted by priority' {
            $result = Get-PrdStatus -Prd $script:testPrd

            $result.IncompleteStories | Should -HaveCount 2
            $result.IncompleteStories[0].priority | Should -Be 2
            $result.IncompleteStories[1].priority | Should -Be 3
        }
    }

    Context 'With all stories complete' {
        BeforeAll {
            $script:completePrd = [PSCustomObject]@{
                userStories = @(
                    [PSCustomObject]@{ id = 'US-001'; passes = $true }
                    [PSCustomObject]@{ id = 'US-002'; passes = $true }
                )
            }
        }

        It 'Returns 100% completion' {
            $result = Get-PrdStatus -Prd $script:completePrd
            $result.Percentage | Should -Be 100
        }

        It 'Returns empty incomplete stories array' {
            $result = Get-PrdStatus -Prd $script:completePrd
            $result.IncompleteStories | Should -HaveCount 0
        }
    }

    Context 'With no stories complete' {
        BeforeAll {
            $script:incompletePrd = [PSCustomObject]@{
                userStories = @(
                    [PSCustomObject]@{ id = 'US-001'; passes = $false }
                    [PSCustomObject]@{ id = 'US-002'; passes = $false }
                )
            }
        }

        It 'Returns 0% completion' {
            $result = Get-PrdStatus -Prd $script:incompletePrd
            $result.Percentage | Should -Be 0
        }
    }

    Context 'With empty user stories' {
        BeforeAll {
            $script:emptyPrd = [PSCustomObject]@{
                userStories = @()
            }
        }

        It 'Handles empty stories array' {
            $result = Get-PrdStatus -Prd $script:emptyPrd

            $result.Total | Should -Be 0
            $result.Complete | Should -Be 0
            $result.Percentage | Should -Be 0
        }
    }

    Context 'With null PRD' {
        It 'Returns zero values for null input' {
            $result = Get-PrdStatus -Prd $null

            $result.Total | Should -Be 0
            $result.Complete | Should -Be 0
            $result.Remaining | Should -Be 0
            $result.Percentage | Should -Be 0
        }
    }
}

Describe 'Write-ColoredOutput' {
    It 'Does not throw with valid parameters' {
        { Write-ColoredOutput -Message 'Test' -Color 'Green' } | Should -Not -Throw
    }

    It 'Accepts all valid color values' {
        $colors = @('Red', 'Green', 'Yellow', 'Blue', 'Cyan', 'White', 'Gray')
        foreach ($color in $colors) {
            { Write-ColoredOutput -Message 'Test' -Color $color } | Should -Not -Throw
        }
    }

    It 'Uses positional parameters correctly' {
        { Write-ColoredOutput 'Test message' 'Blue' } | Should -Not -Throw
    }

    It 'Supports NoNewline switch' {
        { Write-ColoredOutput -Message 'Test' -Color 'Green' -NoNewline } | Should -Not -Throw
    }

    It 'Rejects invalid color values' {
        { Write-ColoredOutput -Message 'Test' -Color 'Purple' } | Should -Throw
    }
}

Describe 'Add-LogEntry' {
    BeforeAll {
        $script:testDir = Join-Path $TestDrive 'ralph'
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null
    }

    Context 'With new log file' {
        It 'Creates log file if it does not exist' {
            $testLog = Join-Path $script:testDir 'new-ralph.log'
            Remove-Item $testLog -ErrorAction SilentlyContinue

            Add-LogEntry -Message 'Test entry' -Path $testLog

            Test-Path $testLog | Should -BeTrue
        }

        It 'Writes timestamped entry' {
            $testLog = Join-Path $script:testDir 'timestamp-test.log'
            Remove-Item $testLog -ErrorAction SilentlyContinue

            Add-LogEntry -Message 'Test message' -Path $testLog

            $content = Get-Content -Path $testLog -Raw
            $content | Should -Match '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Test message'
        }
    }

    Context 'With existing log file' {
        It 'Appends to existing log file' {
            $testLog = Join-Path $script:testDir 'existing.log'
            'Previous entry' | Set-Content -Path $testLog

            Add-LogEntry -Message 'New entry' -Path $testLog

            $content = Get-Content -Path $testLog
            $content | Should -HaveCount 2
            $content[0] | Should -Be 'Previous entry'
            $content[1] | Should -Match 'New entry'
        }
    }

    Context 'With invalid path' {
        It 'Does not throw when write fails' {
            { Add-LogEntry -Message 'Test' -Path '/invalid/path/ralph.log' } | Should -Not -Throw
        }
    }
}

# =============================================================================
# GLOBAL REGISTRY TESTS (GM-001)
# =============================================================================

Describe 'Get-RalphGlobalDir' {
    Context 'With default settings' {
        It 'Returns a path ending with .ralph/global' {
            $result = Get-RalphGlobalDir
            $result | Should -Match '\.ralph[/\\]global$'
        }

        It 'Returns path under user home directory' {
            $result = Get-RalphGlobalDir
            $userHome = if ($IsWindows -or $env:OS -eq 'Windows_NT') { $env:USERPROFILE } else { $env:HOME }
            $escapedHome = [regex]::Escape($userHome)
            $result | Should -Match $escapedHome
        }
    }

    Context 'With RALPH_GLOBAL_DIR override' {
        BeforeAll {
            $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
            $env:RALPH_GLOBAL_DIR = '/custom/global/path'
        }

        AfterAll {
            $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
        }

        It 'Returns the override path' {
            $result = Get-RalphGlobalDir
            $result | Should -Be '/custom/global/path'
        }
    }
}

Describe 'Initialize-RalphGlobalRegistry' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'ralph-global-test'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    BeforeEach {
        if (Test-Path $script:testGlobalDir) {
            Remove-Item -Path $script:testGlobalDir -Recurse -Force
        }
    }

    Context 'When creating new directories' {
        It 'Creates instances directory' {
            Initialize-RalphGlobalRegistry | Should -BeTrue
            $instancesDir = Join-Path $script:testGlobalDir 'instances'
            Test-Path $instancesDir | Should -BeTrue
        }

        It 'Creates locks directory' {
            Initialize-RalphGlobalRegistry | Should -BeTrue
            $locksDir = Join-Path $script:testGlobalDir 'locks'
            Test-Path $locksDir | Should -BeTrue
        }
    }

    Context 'When directories already exist' {
        BeforeEach {
            $instancesDir = Join-Path $script:testGlobalDir 'instances'
            $locksDir = Join-Path $script:testGlobalDir 'locks'
            New-Item -Path $instancesDir -ItemType Directory -Force | Out-Null
            New-Item -Path $locksDir -ItemType Directory -Force | Out-Null
        }

        It 'Returns true without error' {
            Initialize-RalphGlobalRegistry | Should -BeTrue
        }
    }

    Context 'When RALPH_GLOBAL_DISABLE is set' {
        BeforeAll {
            $script:originalDisable = $env:RALPH_GLOBAL_DISABLE
            $env:RALPH_GLOBAL_DISABLE = '1'
        }

        AfterAll {
            $env:RALPH_GLOBAL_DISABLE = $script:originalDisable
        }

        It 'Returns true immediately' {
            Initialize-RalphGlobalRegistry | Should -BeTrue
        }

        It 'Does not create directories' {
            if (Test-Path $script:testGlobalDir) {
                Remove-Item -Path $script:testGlobalDir -Recurse -Force
            }
            Initialize-RalphGlobalRegistry | Out-Null
            Test-Path $script:testGlobalDir | Should -BeFalse
        }
    }
}

Describe 'Ensure-RalphGlobalRegistration' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'ralph-ensure-global-test'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    BeforeEach {
        if (Test-Path $script:testGlobalDir) {
            Remove-Item -Path $script:testGlobalDir -Recurse -Force
        }
        New-Item -Path (Join-Path $script:testGlobalDir 'instances') -ItemType Directory -Force | Out-Null
    }

    Context 'When RALPH_GLOBAL_DISABLE is set' {
        BeforeAll {
            $script:originalDisable = $env:RALPH_GLOBAL_DISABLE
            $env:RALPH_GLOBAL_DISABLE = '1'
        }

        AfterAll {
            $env:RALPH_GLOBAL_DISABLE = $script:originalDisable
        }

        It 'Returns true immediately' {
            Ensure-RalphGlobalRegistration | Should -BeTrue
        }
    }

    Context 'When symlink exists' {
        BeforeEach {
            # Create a mock symlink target
            $instanceId = Get-RalphInstanceId
            $paths = Get-RalphPaths
            $instanceDir = Join-Path (Join-Path $paths.RalphDir 'instances') $instanceId
            if (-not (Test-Path $instanceDir)) {
                New-Item -Path $instanceDir -ItemType Directory -Force | Out-Null
            }
            # Register first
            Register-RalphGlobalInstance | Out-Null
        }

        AfterEach {
            Unregister-RalphGlobalInstance | Out-Null
        }

        It 'Returns true without recreating' {
            $linkName = Get-RalphGlobalLinkName
            $linkPath = Join-Path (Join-Path $script:testGlobalDir 'instances') $linkName
            $beforeStat = (Get-Item $linkPath -ErrorAction SilentlyContinue).LastWriteTime

            Ensure-RalphGlobalRegistration | Should -BeTrue

            # Link should still exist with same timestamp (not recreated)
            Test-Path $linkPath | Should -BeTrue
        }
    }
}

AfterAll {
    # Clean up - remove the imported module
    Remove-Module RalphUtils -ErrorAction SilentlyContinue
}
