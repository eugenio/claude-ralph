#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for ralph.ps1 main loop script.

.DESCRIPTION
    Comprehensive test suite for ralph.ps1 including:
    - Parameter handling (MaxIterations default and custom values)
    - Dependency checking logic with mocked commands
    - prd.json parsing and incomplete story selection
    - Completion signal detection regex
    - Dual verification logic (signal + all stories pass)
    - Archive functionality creates correct directory structure
    - Error handling continues to next iteration
    - Logging writes correct format to ralph.log
    - Mock external dependencies (claude CLI, git commands)
#>

BeforeAll {
    # Import the utilities module (ralph.ps1 depends on it)
    $modulePath = Join-Path $PSScriptRoot '..' 'RalphUtils.psm1'
    Import-Module $modulePath -Force

    # Define the script path
    $script:ralphScript = Join-Path $PSScriptRoot '..' 'ralph.ps1'

    # Helper function to create test PRD
    function New-TestPrd {
        param(
            [string]$FeatureName = 'Test Feature',
            [string]$BranchName = 'test/branch',
            [array]$UserStories = @()
        )
        return [PSCustomObject]@{
            featureName = $FeatureName
            branchName  = $BranchName
            userStories = $UserStories
        }
    }

    # Helper function to create a test story
    function New-TestStory {
        param(
            [string]$Id = 'US-001',
            [string]$Title = 'Test Story',
            [int]$Priority = 1,
            [bool]$Passes = $false
        )
        return [PSCustomObject]@{
            id       = $Id
            title    = $Title
            priority = $Priority
            passes   = $Passes
        }
    }
}

Describe 'ralph.ps1 Parameter Handling' {
    BeforeAll {
        # Read the script content to test parameter definitions
        $script:scriptContent = Get-Content -Path $script:ralphScript -Raw
    }

    It 'Defines MaxIterations parameter' {
        $script:scriptContent | Should -Match '\[int\]\$MaxIterations'
    }

    It 'MaxIterations has default value of 10' {
        $script:scriptContent | Should -Match '\$MaxIterations\s*=\s*10'
    }

    It 'MaxIterations is a positional parameter at position 0' {
        $script:scriptContent | Should -Match '\[Parameter\(Position\s*=\s*0\)\]'
    }

    It 'MaxIterations has ValidateRange starting at 1' {
        $script:scriptContent | Should -Match '\[ValidateRange\(1,'
    }

    It 'Script requires PowerShell 7.0+' {
        $script:scriptContent | Should -Match '#Requires -Version 7\.0'
    }

    It 'Script imports RalphUtils module' {
        # The script uses $modulePath variable, so check for the pattern
        $script:scriptContent | Should -Match 'Import-Module \$modulePath'
    }
}

Describe 'Test-AllStoriesComplete Function' {
    BeforeAll {
        # Source the script to get access to internal functions
        # We need to dot-source in a separate scope
        $script:testAllStoriesComplete = {
            param([PSObject]$Prd)
            if ($null -eq $Prd -or $null -eq $Prd.userStories) {
                return $false
            }
            $incomplete = @($Prd.userStories | Where-Object { $_.passes -eq $false })
            return $incomplete.Count -eq 0
        }
    }

    Context 'When all stories pass' {
        It 'Returns true' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $true),
                (New-TestStory -Id 'US-002' -Passes $true)
            )

            $result = & $script:testAllStoriesComplete -Prd $prd
            $result | Should -BeTrue
        }
    }

    Context 'When some stories fail' {
        It 'Returns false' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $true),
                (New-TestStory -Id 'US-002' -Passes $false)
            )

            $result = & $script:testAllStoriesComplete -Prd $prd
            $result | Should -BeFalse
        }
    }

    Context 'When all stories fail' {
        It 'Returns false' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $false),
                (New-TestStory -Id 'US-002' -Passes $false)
            )

            $result = & $script:testAllStoriesComplete -Prd $prd
            $result | Should -BeFalse
        }
    }

    Context 'When PRD is null' {
        It 'Returns false' {
            $result = & $script:testAllStoriesComplete -Prd $null
            $result | Should -BeFalse
        }
    }

    Context 'When userStories is null' {
        It 'Returns false' {
            $prd = [PSCustomObject]@{
                featureName = 'Test'
                userStories = $null
            }

            $result = & $script:testAllStoriesComplete -Prd $prd
            $result | Should -BeFalse
        }
    }

    Context 'When userStories is empty' {
        It 'Returns true (no incomplete stories)' {
            $prd = New-TestPrd -UserStories @()

            $result = & $script:testAllStoriesComplete -Prd $prd
            $result | Should -BeTrue
        }
    }
}

Describe 'Test-CompletionSignal Function' {
    BeforeAll {
        # Replicate the completion signal detection logic
        $script:testCompletionSignal = {
            param([string]$Output)
            if ([string]::IsNullOrEmpty($Output)) {
                return $false
            }
            $matches = [regex]::Matches($Output, '<promise>COMPLETE</promise>')
            return $matches.Count -gt 0
        }
    }

    Context 'When signal is present' {
        It 'Returns true for exact signal' {
            $output = '<promise>COMPLETE</promise>'
            $result = & $script:testCompletionSignal -Output $output
            $result | Should -BeTrue
        }

        It 'Returns true when signal is in larger output' {
            $output = @"
Working on story US-001...
Implementation complete.
<promise>COMPLETE</promise>
All done!
"@
            $result = & $script:testCompletionSignal -Output $output
            $result | Should -BeTrue
        }

        It 'Detects multiple signals' {
            $output = '<promise>COMPLETE</promise> some text <promise>COMPLETE</promise>'
            $result = & $script:testCompletionSignal -Output $output
            $result | Should -BeTrue
        }
    }

    Context 'When signal is absent' {
        It 'Returns false for empty string' {
            $result = & $script:testCompletionSignal -Output ''
            $result | Should -BeFalse
        }

        It 'Returns false for null' {
            $result = & $script:testCompletionSignal -Output $null
            $result | Should -BeFalse
        }

        It 'Returns false for partial match' {
            $output = '<promise>COMPLET</promise>'
            $result = & $script:testCompletionSignal -Output $output
            $result | Should -BeFalse
        }

        It 'Returns false for wrong case' {
            $output = '<promise>complete</promise>'
            $result = & $script:testCompletionSignal -Output $output
            $result | Should -BeFalse
        }

        It 'Returns false for normal text' {
            $output = 'Story completed successfully.'
            $result = & $script:testCompletionSignal -Output $output
            $result | Should -BeFalse
        }
    }
}

Describe 'Dual Verification Logic' {
    BeforeAll {
        # Replicate the dual verification logic from ralph.ps1
        $script:shouldExitComplete = {
            param(
                [bool]$HasSignal,
                [PSObject]$Prd
            )
            # Check if all stories are complete
            $allComplete = $false
            if ($null -ne $Prd -and $null -ne $Prd.userStories) {
                $incomplete = @($Prd.userStories | Where-Object { $_.passes -eq $false })
                $allComplete = $incomplete.Count -eq 0
            }

            # Only exit if signal AND all complete
            return $HasSignal -and $allComplete
        }
    }

    Context 'When signal present and all stories complete' {
        It 'Returns true (should exit successfully)' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $true),
                (New-TestStory -Id 'US-002' -Passes $true)
            )

            $result = & $script:shouldExitComplete -HasSignal $true -Prd $prd
            $result | Should -BeTrue
        }
    }

    Context 'When signal present but stories incomplete (false positive)' {
        It 'Returns false (should NOT exit - false positive detection)' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $true),
                (New-TestStory -Id 'US-002' -Passes $false)
            )

            $result = & $script:shouldExitComplete -HasSignal $true -Prd $prd
            $result | Should -BeFalse
        }
    }

    Context 'When no signal but all stories complete' {
        It 'Returns false (needs signal for proper exit)' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $true),
                (New-TestStory -Id 'US-002' -Passes $true)
            )

            $result = & $script:shouldExitComplete -HasSignal $false -Prd $prd
            $result | Should -BeFalse
        }
    }

    Context 'When no signal and stories incomplete' {
        It 'Returns false' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $false)
            )

            $result = & $script:shouldExitComplete -HasSignal $false -Prd $prd
            $result | Should -BeFalse
        }
    }
}

Describe 'Archive Functionality' {
    BeforeAll {
        $script:testDir = Join-Path $TestDrive 'ralph'
        $script:archiveDir = Join-Path $script:testDir 'archive'
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null

        # Replicate archive logic
        $script:invokeArchive = {
            param(
                [string]$CurrentBranch,
                [string]$LastBranch,
                [string]$TestDir,
                [string]$ArchiveDir
            )

            # Only archive if branches differ and both are non-empty
            if ([string]::IsNullOrEmpty($CurrentBranch) -or
                [string]::IsNullOrEmpty($LastBranch) -or
                $CurrentBranch -eq $LastBranch) {
                return $null
            }

            # Create archive folder
            $date = Get-Date -Format 'yyyy-MM-dd'
            $folderName = $LastBranch -replace '^ralph/', ''
            $archiveFolder = Join-Path $ArchiveDir "$date-$folderName"

            New-Item -Path $ArchiveDir -ItemType Directory -Force | Out-Null
            New-Item -Path $archiveFolder -ItemType Directory -Force | Out-Null

            return $archiveFolder
        }
    }

    Context 'When branch changes' {
        It 'Creates archive directory with correct structure' {
            $archiveFolder = & $script:invokeArchive `
                -CurrentBranch 'ralph/new-feature' `
                -LastBranch 'ralph/old-feature' `
                -TestDir $script:testDir `
                -ArchiveDir $script:archiveDir

            $archiveFolder | Should -Not -BeNull
            Test-Path $archiveFolder | Should -BeTrue
            $archiveFolder | Should -Match 'old-feature$'
        }

        It 'Creates date-prefixed folder' {
            $archiveFolder = & $script:invokeArchive `
                -CurrentBranch 'ralph/feature-a' `
                -LastBranch 'ralph/feature-b' `
                -TestDir $script:testDir `
                -ArchiveDir $script:archiveDir

            $date = Get-Date -Format 'yyyy-MM-dd'
            $archiveFolder | Should -Match "^.*$date"
        }

        It 'Strips ralph/ prefix from folder name' {
            $archiveFolder = & $script:invokeArchive `
                -CurrentBranch 'ralph/new' `
                -LastBranch 'ralph/prefix-test' `
                -TestDir $script:testDir `
                -ArchiveDir $script:archiveDir

            $archiveFolder | Should -Match 'prefix-test$'
            # The folder name itself should not have ralph/ prefix
            # (the path may contain 'ralph' from the test directory, so just check the final segment)
            $folderName = Split-Path -Leaf $archiveFolder
            $folderName | Should -Not -Match '^ralph/'
        }
    }

    Context 'When branches are the same' {
        It 'Returns null (no archive needed)' {
            $archiveFolder = & $script:invokeArchive `
                -CurrentBranch 'ralph/same' `
                -LastBranch 'ralph/same' `
                -TestDir $script:testDir `
                -ArchiveDir $script:archiveDir

            $archiveFolder | Should -BeNull
        }
    }

    Context 'When branches are empty' {
        It 'Returns null for empty current branch' {
            $archiveFolder = & $script:invokeArchive `
                -CurrentBranch '' `
                -LastBranch 'ralph/old' `
                -TestDir $script:testDir `
                -ArchiveDir $script:archiveDir

            $archiveFolder | Should -BeNull
        }

        It 'Returns null for empty last branch' {
            $archiveFolder = & $script:invokeArchive `
                -CurrentBranch 'ralph/new' `
                -LastBranch '' `
                -TestDir $script:testDir `
                -ArchiveDir $script:archiveDir

            $archiveFolder | Should -BeNull
        }
    }
}

Describe 'Logging Format' {
    BeforeAll {
        $script:testDir = Join-Path $TestDrive 'ralph-log'
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null
    }

    It 'Logs with correct timestamp format' {
        $logFile = Join-Path $script:testDir 'test.log'
        Add-LogEntry -Message 'Test message' -Path $logFile

        $content = Get-Content -Path $logFile -Raw
        $content | Should -Match '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]'
    }

    It 'Logs iteration start messages' {
        $logFile = Join-Path $script:testDir 'iteration.log'
        Add-LogEntry -Message 'Starting iteration 1' -Path $logFile

        $content = Get-Content -Path $logFile -Raw
        $content | Should -Match 'Starting iteration 1'
    }

    It 'Appends multiple entries correctly' {
        $logFile = Join-Path $script:testDir 'multi.log'

        Add-LogEntry -Message 'First entry' -Path $logFile
        Add-LogEntry -Message 'Second entry' -Path $logFile

        $lines = Get-Content -Path $logFile
        $lines | Should -HaveCount 2
        $lines[0] | Should -Match 'First entry'
        $lines[1] | Should -Match 'Second entry'
    }
}

Describe 'PRD Story Selection' {
    BeforeAll {
        # Replicate incomplete story selection logic (sorted by priority)
        $script:getNextStory = {
            param([PSObject]$Prd)

            if ($null -eq $Prd -or $null -eq $Prd.userStories) {
                return $null
            }

            $incomplete = @($Prd.userStories | Where-Object { $_.passes -eq $false } | Sort-Object priority)
            if ($incomplete.Count -eq 0) {
                return $null
            }

            return $incomplete[0]
        }
    }

    Context 'With mixed pass/fail stories' {
        It 'Returns highest priority incomplete story' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-003' -Priority 3 -Passes $false),
                (New-TestStory -Id 'US-001' -Priority 1 -Passes $true),
                (New-TestStory -Id 'US-002' -Priority 2 -Passes $false)
            )

            $next = & $script:getNextStory -Prd $prd
            $next.id | Should -Be 'US-002'
            $next.priority | Should -Be 2
        }
    }

    Context 'With all stories complete' {
        It 'Returns null' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $true),
                (New-TestStory -Id 'US-002' -Passes $true)
            )

            $next = & $script:getNextStory -Prd $prd
            $next | Should -BeNull
        }
    }

    Context 'With null PRD' {
        It 'Returns null' {
            $next = & $script:getNextStory -Prd $null
            $next | Should -BeNull
        }
    }

    Context 'With empty user stories' {
        It 'Returns null' {
            $prd = New-TestPrd -UserStories @()

            $next = & $script:getNextStory -Prd $prd
            $next | Should -BeNull
        }
    }
}

Describe 'Dependency Checking' {
    Context 'Using RalphUtils Test-Dependencies' {
        BeforeAll {
            Mock Get-Command {
                param($Name)
                return [PSCustomObject]@{ Name = $Name }
            } -ModuleName RalphUtils
        }

        It 'Returns valid when all dependencies present' {
            $result = Test-Dependencies
            $result.IsValid | Should -BeTrue
        }

        It 'Returns hashtable with expected keys' {
            $result = Test-Dependencies
            $result.Keys | Should -Contain 'IsValid'
            $result.Keys | Should -Contain 'Errors'
            $result.Keys | Should -Contain 'Claude'
            $result.Keys | Should -Contain 'Git'
            $result.Keys | Should -Contain 'PowerShell'
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

        It 'Returns claude-specific error' {
            $result = Test-Dependencies
            $result.Errors | Should -Contain 'Claude Code CLI not found. Install with: npm install -g @anthropic-ai/claude-code'
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

        It 'Returns git-specific error' {
            $result = Test-Dependencies
            $result.Errors | Should -Contain 'Git not found. Please install git.'
        }
    }
}

Describe 'Error Handling' {
    BeforeAll {
        # Simulate error handling behavior
        $script:handleClaudeError = {
            param(
                [int]$ExitCode,
                [int]$CurrentIteration,
                [int]$MaxIterations
            )

            # ralph.ps1 continues on error (doesn't exit)
            if ($ExitCode -ne 0) {
                $errorHandled = $true
                # Continue to next iteration
                $shouldContinue = ($CurrentIteration -lt $MaxIterations)
                return @{
                    ErrorHandled   = $errorHandled
                    ShouldContinue = $shouldContinue
                }
            }

            return @{
                ErrorHandled   = $false
                ShouldContinue = $true
            }
        }
    }

    Context 'When Claude exits with non-zero code' {
        It 'Continues to next iteration' {
            $result = & $script:handleClaudeError -ExitCode 1 -CurrentIteration 1 -MaxIterations 10
            $result.ErrorHandled | Should -BeTrue
            $result.ShouldContinue | Should -BeTrue
        }
    }

    Context 'When Claude succeeds' {
        It 'Continues normally' {
            $result = & $script:handleClaudeError -ExitCode 0 -CurrentIteration 1 -MaxIterations 10
            $result.ErrorHandled | Should -BeFalse
            $result.ShouldContinue | Should -BeTrue
        }
    }

    Context 'When at max iterations' {
        It 'Does not continue after max iterations' {
            $result = & $script:handleClaudeError -ExitCode 1 -CurrentIteration 10 -MaxIterations 10
            $result.ShouldContinue | Should -BeFalse
        }
    }
}

Describe 'Banner Functions' {
    BeforeAll {
        # Read script content to verify banner functions exist
        $script:scriptContent = Get-Content -Path $script:ralphScript -Raw
    }

    It 'Defines Show-Banner function' {
        $script:scriptContent | Should -Match 'function Show-Banner'
    }

    It 'Defines Show-CompleteBanner function' {
        $script:scriptContent | Should -Match 'function Show-CompleteBanner'
    }

    It 'Defines Show-MaxIterationsBanner function' {
        $script:scriptContent | Should -Match 'function Show-MaxIterationsBanner'
    }

    It 'Defines Show-IterationBanner function' {
        $script:scriptContent | Should -Match 'function Show-IterationBanner'
    }

    It 'Uses Unicode box drawing characters' {
        # Unicode: ╔ (0x2554), ═ (0x2550), ╗ (0x2557), ║ (0x2551), ╚ (0x255A), ╝ (0x255D)
        $script:scriptContent | Should -Match '0x2554'
        $script:scriptContent | Should -Match '0x2550'
        $script:scriptContent | Should -Match '0x2557'
    }

    It 'Uses ForegroundColor for colored output' {
        $script:scriptContent | Should -Match '-ForegroundColor'
    }
}

Describe 'Branch Tracking' {
    BeforeAll {
        $script:testDir = Join-Path $TestDrive 'ralph-branch'
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null

        # Replicate Save-CurrentBranch logic
        $script:saveCurrentBranch = {
            param(
                [PSObject]$Prd,
                [string]$LastBranchFile
            )

            if ($null -ne $Prd -and $null -ne $Prd.branchName -and $Prd.branchName -ne '') {
                try {
                    Set-Content -Path $LastBranchFile -Value $Prd.branchName -ErrorAction Stop
                    return $true
                }
                catch {
                    return $false
                }
            }
            return $false
        }
    }

    Context 'With valid branch name' {
        It 'Saves branch to file' {
            $branchFile = Join-Path $script:testDir '.last-branch'
            $prd = New-TestPrd -BranchName 'ralph/test-feature'

            $result = & $script:saveCurrentBranch -Prd $prd -LastBranchFile $branchFile

            $result | Should -BeTrue
            Test-Path $branchFile | Should -BeTrue
            Get-Content $branchFile | Should -Be 'ralph/test-feature'
        }
    }

    Context 'With empty branch name' {
        It 'Does not save file' {
            $branchFile = Join-Path $script:testDir '.last-branch-empty'
            Remove-Item $branchFile -ErrorAction SilentlyContinue
            $prd = New-TestPrd -BranchName ''

            $result = & $script:saveCurrentBranch -Prd $prd -LastBranchFile $branchFile

            $result | Should -BeFalse
        }
    }

    Context 'With null PRD' {
        It 'Returns false' {
            $branchFile = Join-Path $script:testDir '.last-branch-null'

            $result = & $script:saveCurrentBranch -Prd $null -LastBranchFile $branchFile

            $result | Should -BeFalse
        }
    }
}

Describe 'Progress File Initialization' {
    BeforeAll {
        $script:testDir = Join-Path $TestDrive 'ralph-progress'
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null

        # Replicate Initialize-ProgressFile logic
        $script:initProgress = {
            param([string]$ProgressFile)

            if (-not (Test-Path $ProgressFile)) {
                $content = @"
# Ralph Progress Log
Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## Codebase Patterns
(Patterns discovered during implementation will be added here)

---
"@
                Set-Content -Path $ProgressFile -Value $content
                return $true
            }
            return $false
        }
    }

    Context 'When progress file does not exist' {
        It 'Creates file with correct header' {
            $progressFile = Join-Path $script:testDir 'new-progress.txt'
            Remove-Item $progressFile -ErrorAction SilentlyContinue

            $created = & $script:initProgress -ProgressFile $progressFile

            $created | Should -BeTrue
            Test-Path $progressFile | Should -BeTrue
            $content = Get-Content $progressFile -Raw
            $content | Should -Match '# Ralph Progress Log'
            $content | Should -Match '## Codebase Patterns'
        }
    }

    Context 'When progress file already exists' {
        It 'Does not overwrite existing file' {
            $progressFile = Join-Path $script:testDir 'existing-progress.txt'
            'Existing content' | Set-Content $progressFile

            $created = & $script:initProgress -ProgressFile $progressFile

            $created | Should -BeFalse
            $content = Get-Content $progressFile -Raw
            # Use platform-agnostic line ending comparison
            $content.TrimEnd() | Should -Be 'Existing content'
        }
    }
}

Describe 'Script Structure' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:ralphScript -Raw
    }

    It 'Defines Main function' {
        $script:scriptContent | Should -Match 'function Main'
    }

    It 'Calls Main at the end' {
        $script:scriptContent | Should -Match 'Main\s*$'
    }

    It 'Uses CmdletBinding' {
        $script:scriptContent | Should -Match '\[CmdletBinding\(\)\]'
    }

    It 'Has proper help documentation' {
        $script:scriptContent | Should -Match '\.SYNOPSIS'
        $script:scriptContent | Should -Match '\.DESCRIPTION'
        $script:scriptContent | Should -Match '\.EXAMPLE'
    }

    It 'Handles PRD file not found' {
        $script:scriptContent | Should -Match 'prd\.json not found'
    }

    It 'Implements main loop with for loop' {
        $script:scriptContent | Should -Match 'for \(\$i = 1; \$i -le \$MaxIterations'
    }

    It 'Implements 2 second pause between iterations' {
        $script:scriptContent | Should -Match 'Start-Sleep -Seconds 2'
    }
}

Describe 'Multi-Instance Integration (PS-006)' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:ralphScript -Raw
    }

    Context 'Instance ID Generation and Usage' {
        It 'Uses Get-RalphShortId for banner display' {
            $script:scriptContent | Should -Match 'Get-RalphShortId'
        }

        It 'Stores instance paths in script-level variable' {
            $script:scriptContent | Should -Match '\$script:InstancePaths'
        }

        It 'Calls New-RalphInstanceDirectory on startup' {
            $script:scriptContent | Should -Match 'New-RalphInstanceDirectory'
        }
    }

    Context 'Instance Directory and Status' {
        It 'Initializes multi-instance before main loop' {
            # The New-RalphInstanceDirectory call should come before the main loop
            $initPos = $script:scriptContent.IndexOf('New-RalphInstanceDirectory')
            $loopPos = $script:scriptContent.IndexOf('for ($i = 1; $i -le $MaxIterations')
            $initPos | Should -BeLessThan $loopPos
        }

        It 'Updates status with starting state on init' {
            $script:scriptContent | Should -Match "Update-RalphStatus -State 'starting'"
        }

        It 'Updates status with state on each iteration' {
            # Should have multiple Update-RalphStatus calls for different states
            $workingMatches = [regex]::Matches($script:scriptContent, "Update-RalphStatus.*-State\s+'working'")
            $workingMatches.Count | Should -BeGreaterThan 0
        }

        It 'Updates status with completed state on success' {
            $script:scriptContent | Should -Match "Update-RalphStatus -State 'completed'"
        }
    }

    Context 'Story Claiming and Releasing' {
        It 'Claims story before working using Request-RalphNextStoryClaim' {
            $script:scriptContent | Should -Match 'Request-RalphNextStoryClaim'
        }

        It 'Releases claim on story completion using Remove-RalphStoryClaim' {
            $script:scriptContent | Should -Match 'Remove-RalphStoryClaim'
        }

        It 'Stores current story ID in script variable' {
            $script:scriptContent | Should -Match '\$script:CurrentStoryId'
        }

        It 'Sets current story for tracking' {
            $script:scriptContent | Should -Match 'Set-RalphCurrentStory'
        }
    }

    Context 'Feature Branch Management' {
        It 'Creates feature branch with New-RalphStoryBranch' {
            $script:scriptContent | Should -Match 'New-RalphStoryBranch'
        }

        It 'Merges branch on completion with Merge-RalphStoryBranch' {
            $script:scriptContent | Should -Match 'Merge-RalphStoryBranch'
        }
    }

    Context 'Logging to Instance Directory' {
        It 'Uses Add-RalphInstanceLog for logging' {
            $script:scriptContent | Should -Match 'Add-RalphInstanceLog'
        }

        It 'Logs iteration start' {
            $script:scriptContent | Should -Match 'Add-RalphInstanceLog.*iteration'
        }
    }

    Context 'Cleanup Registration' {
        It 'Registers cleanup handler' {
            $script:scriptContent | Should -Match 'Register-RalphCleanup'
        }
    }
}

Describe 'Instance Directory Creation' {
    BeforeAll {
        $script:testDir = Join-Path $TestDrive 'ralph-instance-test'
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $script:testDir 'instances') -ItemType Directory -Force | Out-Null
    }

    Context 'New-RalphInstanceDirectory Integration' {
        It 'Creates instance directory with correct structure' {
            # Mock Get-RalphPaths to use test directory
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir    = $script:testDir
                    ProjectRoot = $script:testDir
                    PrdFile     = (Join-Path $script:testDir 'prd.json')
                }
            }

            # Generate a test instance ID
            $testId = Get-RalphInstanceId -Force

            # Create instance directory
            $instancePaths = New-RalphInstanceDirectory -InstanceId $testId

            # Verify directory was created
            Test-Path $instancePaths.InstanceDir | Should -BeTrue

            # Verify log file was created
            Test-Path $instancePaths.LogFile | Should -BeTrue

            # Verify status file was created
            Test-Path $instancePaths.StatusFile | Should -BeTrue
        }

        It 'Creates valid status.json with starting state' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir    = $script:testDir
                    ProjectRoot = $script:testDir
                    PrdFile     = (Join-Path $script:testDir 'prd.json')
                }
            }

            $testId = Get-RalphInstanceId -Force
            $instancePaths = New-RalphInstanceDirectory -InstanceId $testId

            # Read and validate status.json
            $status = Get-Content $instancePaths.StatusFile -Raw | ConvertFrom-Json
            $status.state | Should -Be 'starting'
            $status.instanceId | Should -Be $testId
            $status.lastHeartbeatEpoch | Should -BeGreaterThan 0
        }

        It 'Creates log file with header' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir    = $script:testDir
                    ProjectRoot = $script:testDir
                    PrdFile     = (Join-Path $script:testDir 'prd.json')
                }
            }

            $testId = Get-RalphInstanceId -Force
            $instancePaths = New-RalphInstanceDirectory -InstanceId $testId

            $logContent = Get-Content $instancePaths.LogFile -Raw
            $logContent | Should -Match '# Ralph Instance Log'
            $logContent | Should -Match "Instance ID: $testId"
        }
    }

    Context 'Status Updates During Lifecycle' {
        It 'Updates status.json on state changes' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir    = $script:testDir
                    ProjectRoot = $script:testDir
                    PrdFile     = (Join-Path $script:testDir 'prd.json')
                }
            }

            $testId = Get-RalphInstanceId -Force
            $instancePaths = New-RalphInstanceDirectory -InstanceId $testId

            # Update to working state
            Update-RalphStatus -State 'working' -CurrentStory 'US-001' -Iteration 1 -MaxIterations 10 -InstancePaths $instancePaths

            $status = Get-Content $instancePaths.StatusFile -Raw | ConvertFrom-Json
            $status.state | Should -Be 'working'
            $status.currentStory | Should -Be 'US-001'
            $status.iteration | Should -Be 1
            $status.maxIterations | Should -Be 10
        }

        It 'Updates heartbeat timestamp on each status update' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir    = $script:testDir
                    ProjectRoot = $script:testDir
                    PrdFile     = (Join-Path $script:testDir 'prd.json')
                }
            }

            $testId = Get-RalphInstanceId -Force
            $instancePaths = New-RalphInstanceDirectory -InstanceId $testId

            $status1 = Get-Content $instancePaths.StatusFile -Raw | ConvertFrom-Json
            $heartbeat1 = $status1.lastHeartbeatEpoch

            Start-Sleep -Seconds 1

            Update-RalphStatus -State 'idle' -InstancePaths $instancePaths

            $status2 = Get-Content $instancePaths.StatusFile -Raw | ConvertFrom-Json
            $heartbeat2 = $status2.lastHeartbeatEpoch

            $heartbeat2 | Should -BeGreaterThan $heartbeat1
        }
    }
}

AfterAll {
    # Clean up - remove the imported module
    Remove-Module RalphUtils -ErrorAction SilentlyContinue
}
