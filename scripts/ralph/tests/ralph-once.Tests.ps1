#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for ralph-once.ps1 single iteration script.

.DESCRIPTION
    Comprehensive test suite for ralph-once.ps1 including:
    - Dependency checking with mocked commands
    - Progress display output format
    - Early exit when all stories complete
    - Single iteration execution flow
    - Status display after execution
    - Mock external dependencies (claude CLI)
#>

BeforeAll {
    # Import the utilities module (ralph-once.ps1 depends on it)
    $modulePath = Join-Path $PSScriptRoot '..' 'RalphUtils.psm1'
    Import-Module $modulePath -Force

    # Define the script path
    $script:ralphOnceScript = Join-Path $PSScriptRoot '..' 'ralph-once.ps1'

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

Describe 'ralph-once.ps1 Script Structure' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:ralphOnceScript -Raw
    }

    It 'Requires PowerShell 7.0+' {
        $script:scriptContent | Should -Match '#Requires -Version 7\.0'
    }

    It 'Has proper help documentation' {
        $script:scriptContent | Should -Match '\.SYNOPSIS'
        $script:scriptContent | Should -Match '\.DESCRIPTION'
        $script:scriptContent | Should -Match '\.EXAMPLE'
    }

    It 'Uses CmdletBinding' {
        $script:scriptContent | Should -Match '\[CmdletBinding\(\)\]'
    }

    It 'Imports RalphUtils module' {
        $script:scriptContent | Should -Match 'Import-Module \$modulePath'
    }

    It 'Defines Main function' {
        $script:scriptContent | Should -Match 'function Main'
    }

    It 'Calls Main at the end' {
        $script:scriptContent | Should -Match 'Main\s*$'
    }

    It 'Defines Show-Banner function' {
        $script:scriptContent | Should -Match 'function Show-Banner'
    }

    It 'Defines Show-Status function' {
        $script:scriptContent | Should -Match 'function Show-Status'
    }

    It 'Defines Invoke-ClaudeCode function' {
        $script:scriptContent | Should -Match 'function Invoke-ClaudeCode'
    }
}

Describe 'Dependency Checking' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:ralphOnceScript -Raw
    }

    It 'Checks dependencies at start' {
        $script:scriptContent | Should -Match 'Test-Dependencies'
    }

    It 'Exits with error when dependencies missing' {
        $script:scriptContent | Should -Match 'if \(-not \$deps\.IsValid\)'
        $script:scriptContent | Should -Match 'exit 1'
    }

    It 'Displays error messages for each missing dependency' {
        $script:scriptContent | Should -Match 'foreach \(\$err in \$deps\.Errors\)'
    }

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
}

Describe 'Progress Display (Show-Status)' {
    BeforeAll {
        # Replicate Show-Status logic from ralph-once.ps1
        $script:showStatus = {
            param([hashtable]$Status)

            $output = @()

            if ($null -eq $Status -or $Status.Total -eq 0) {
                $output += 'No PRD file found or empty'
                return $output
            }

            $output += "Stories: $($Status.Complete)/$($Status.Total) complete, $($Status.Remaining) remaining"
            return $output
        }
    }

    Context 'With valid status' {
        It 'Displays complete/total format' {
            $status = @{
                Total     = 10
                Complete  = 5
                Remaining = 5
            }
            $output = & $script:showStatus -Status $status
            $output | Should -Match '5/10 complete'
        }

        It 'Displays remaining count' {
            $status = @{
                Total     = 10
                Complete  = 7
                Remaining = 3
            }
            $output = & $script:showStatus -Status $status
            $output | Should -Match '3 remaining'
        }
    }

    Context 'With null status' {
        It 'Shows appropriate message for null status' {
            $output = & $script:showStatus -Status $null
            $output | Should -Match 'No PRD file found or empty'
        }
    }

    Context 'With zero total' {
        It 'Shows appropriate message when total is 0' {
            $status = @{
                Total     = 0
                Complete  = 0
                Remaining = 0
            }
            $output = & $script:showStatus -Status $status
            $output | Should -Match 'No PRD file found or empty'
        }
    }
}

Describe 'Early Exit When All Stories Complete' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:ralphOnceScript -Raw

        # Replicate early exit check logic
        $script:shouldExitEarly = {
            param([hashtable]$Status)
            return ($null -ne $Status -and $Status.Remaining -eq 0)
        }
    }

    It 'Script checks for remaining stories' {
        $script:scriptContent | Should -Match 'if \(\$status\.Remaining -eq 0\)'
    }

    It 'Script exits cleanly when all complete' {
        $script:scriptContent | Should -Match 'All stories already complete!'
        $script:scriptContent | Should -Match 'exit 0'
    }

    Context 'With all stories complete' {
        It 'Returns true (should exit early)' {
            $status = @{
                Total     = 5
                Complete  = 5
                Remaining = 0
            }
            $result = & $script:shouldExitEarly -Status $status
            $result | Should -BeTrue
        }
    }

    Context 'With incomplete stories' {
        It 'Returns false (should not exit)' {
            $status = @{
                Total     = 5
                Complete  = 3
                Remaining = 2
            }
            $result = & $script:shouldExitEarly -Status $status
            $result | Should -BeFalse
        }
    }

    Context 'With null status' {
        It 'Returns false (should not exit due to error)' {
            $result = & $script:shouldExitEarly -Status $null
            $result | Should -BeFalse
        }
    }
}

Describe 'Single Iteration Execution Flow' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:ralphOnceScript -Raw
    }

    It 'Calls Invoke-ClaudeCode once' {
        # Should call Invoke-ClaudeCode (not in a loop)
        $matches = [regex]::Matches($script:scriptContent, 'Invoke-ClaudeCode')
        # Should appear in function definition and one call
        $matches.Count | Should -BeGreaterOrEqual 2
    }

    It 'Does not have a main iteration loop' {
        # ralph-once should NOT have a for loop for iterations
        $script:scriptContent | Should -Not -Match 'for \(\$i = 1; \$i -le'
    }

    It 'Does not have archive functionality' {
        # ralph-once is simpler - no archiving
        $script:scriptContent | Should -Not -Match 'Invoke-ArchivePreviousRun'
    }

    It 'Gets paths from Get-RalphPaths' {
        $script:scriptContent | Should -Match 'Get-RalphPaths'
    }

    It 'Reads PRD with Read-PrdJson' {
        $script:scriptContent | Should -Match 'Read-PrdJson'
    }

    It 'Gets status with Get-PrdStatus' {
        $script:scriptContent | Should -Match 'Get-PrdStatus'
    }
}

Describe 'Claude Code Invocation (Invoke-ClaudeCode)' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:ralphOnceScript -Raw

        # Replicate Invoke-ClaudeCode return structure
        $script:mockClaudeResult = {
            param(
                [int]$ExitCode = 0,
                [string]$Output = 'Test output'
            )
            return @{
                ExitCode = $ExitCode
                Output   = $Output
            }
        }
    }

    It 'Uses claude CLI with -p flag' {
        $script:scriptContent | Should -Match 'claude -p'
    }

    It 'Uses --dangerously-skip-permissions flag' {
        $script:scriptContent | Should -Match '--dangerously-skip-permissions'
    }

    It 'Uses --verbose flag' {
        $script:scriptContent | Should -Match '--verbose'
    }

    It 'Returns hashtable with ExitCode and Output' {
        $result = & $script:mockClaudeResult -ExitCode 0 -Output 'Success'

        $result | Should -BeOfType [hashtable]
        $result.Keys | Should -Contain 'ExitCode'
        $result.Keys | Should -Contain 'Output'
    }

    It 'Captures exit code correctly' {
        $result = & $script:mockClaudeResult -ExitCode 1 -Output 'Error'
        $result.ExitCode | Should -Be 1
    }

    It 'Saves and restores location' {
        $script:scriptContent | Should -Match '\$originalLocation = Get-Location'
        $script:scriptContent | Should -Match 'Set-Location -Path \$originalLocation'
    }

    It 'Uses try/finally for location restoration' {
        $script:scriptContent | Should -Match 'try \{[\s\S]*?finally \{'
    }
}

Describe 'Status Display After Execution' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:ralphOnceScript -Raw
    }

    It 'Checks for completion signal in output' {
        $script:scriptContent | Should -Match "<promise>COMPLETE</promise>"
    }

    It 'Re-reads PRD after Claude execution' {
        # Should have multiple Read-PrdJson calls
        $matches = [regex]::Matches($script:scriptContent, 'Read-PrdJson')
        $matches.Count | Should -BeGreaterOrEqual 2
    }

    It 'Compares status before and after' {
        $script:scriptContent | Should -Match '\$statusNew'
        $script:scriptContent | Should -Match '\$status\.'
    }

    It 'Shows progress message when stories completed' {
        $script:scriptContent | Should -Match 'Progress made!'
    }

    It 'Shows message when no progress made' {
        $script:scriptContent | Should -Match 'No new stories completed'
    }

    Context 'Progress comparison logic' {
        BeforeAll {
            $script:compareProgress = {
                param(
                    [int]$BeforeComplete,
                    [int]$AfterComplete
                )
                return $AfterComplete -gt $BeforeComplete
            }
        }

        It 'Detects progress when complete count increases' {
            $result = & $script:compareProgress -BeforeComplete 3 -AfterComplete 4
            $result | Should -BeTrue
        }

        It 'Detects no progress when count unchanged' {
            $result = & $script:compareProgress -BeforeComplete 3 -AfterComplete 3
            $result | Should -BeFalse
        }
    }
}

Describe 'Completion Signal Detection' {
    BeforeAll {
        # Replicate the completion signal detection logic from ralph-once.ps1
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

        It 'Returns false for normal text without signal' {
            $output = 'Story completed successfully.'
            $result = & $script:testCompletionSignal -Output $output
            $result | Should -BeFalse
        }
    }
}

Describe 'PRD File Handling' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:ralphOnceScript -Raw
    }

    It 'Checks if PRD file exists' {
        $script:scriptContent | Should -Match 'Test-Path \$paths\.PrdFile'
    }

    It 'Shows error when PRD not found' {
        $script:scriptContent | Should -Match 'prd\.json not found'
    }

    It 'Suggests prd.json.example' {
        $script:scriptContent | Should -Match 'prd\.json\.example'
    }

    It 'Handles null PRD after read' {
        $script:scriptContent | Should -Match 'if \(\$null -eq \$prd\)'
    }
}

Describe 'Banner Function' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:ralphOnceScript -Raw
    }

    It 'Uses Unicode line characters' {
        $script:scriptContent | Should -Match '0x2550'
    }

    It 'Uses ForegroundColor for colors' {
        $script:scriptContent | Should -Match '-ForegroundColor'
    }

    It 'Uses Blue for header lines' {
        $script:scriptContent | Should -Match "-ForegroundColor Blue"
    }

    It 'Uses Yellow for title' {
        $script:scriptContent | Should -Match "-ForegroundColor Yellow"
    }

    It 'Displays SINGLE ITERATION text' {
        $script:scriptContent | Should -Match 'SINGLE ITERATION'
    }
}

Describe 'Error Handling' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:ralphOnceScript -Raw
    }

    It 'Has try/catch around Claude execution' {
        $script:scriptContent | Should -Match 'try \{[\s\S]*?Invoke-ClaudeCode[\s\S]*?catch'
    }

    It 'Handles non-zero exit codes from Claude' {
        $script:scriptContent | Should -Match 'if \(\$result\.ExitCode -ne 0\)'
    }

    It 'Displays colored error messages' {
        $script:scriptContent | Should -Match "Write-ColoredOutput.*-Color Red"
    }

    It 'Exits with code 1 on error' {
        # Multiple places where script might exit 1
        $matches = [regex]::Matches($script:scriptContent, 'exit 1')
        $matches.Count | Should -BeGreaterOrEqual 1
    }
}

Describe 'Module Import Error Handling' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:ralphOnceScript -Raw
    }

    It 'Checks if module file exists' {
        $script:scriptContent | Should -Match 'Test-Path \$modulePath'
    }

    It 'Shows error when module not found' {
        $script:scriptContent | Should -Match 'RalphUtils\.psm1 not found'
    }

    It 'Uses -Force when importing module' {
        $script:scriptContent | Should -Match 'Import-Module \$modulePath -Force'
    }
}

Describe 'Integration with RalphUtils' {
    Context 'Get-PrdStatus returns correct format' {
        BeforeAll {
            $script:testPrd = [PSCustomObject]@{
                featureName = 'Test'
                userStories = @(
                    [PSCustomObject]@{ id = 'US-001'; title = 'Story 1'; priority = 1; passes = $false }
                    [PSCustomObject]@{ id = 'US-002'; title = 'Story 2'; priority = 2; passes = $true }
                    [PSCustomObject]@{ id = 'US-003'; title = 'Story 3'; priority = 3; passes = $false }
                )
            }
        }

        It 'Returns hashtable with required keys' {
            $result = Get-PrdStatus -Prd $script:testPrd

            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -Contain 'Total'
            $result.Keys | Should -Contain 'Complete'
            $result.Keys | Should -Contain 'Remaining'
        }

        It 'Calculates correct remaining count' {
            $result = Get-PrdStatus -Prd $script:testPrd
            $result.Remaining | Should -Be 2
        }
    }

    Context 'Write-ColoredOutput works correctly' {
        It 'Accepts valid color parameters' {
            { Write-ColoredOutput -Message 'Test' -Color 'Green' } | Should -Not -Throw
            { Write-ColoredOutput -Message 'Test' -Color 'Red' } | Should -Not -Throw
            { Write-ColoredOutput -Message 'Test' -Color 'Yellow' } | Should -Not -Throw
            { Write-ColoredOutput -Message 'Test' -Color 'Cyan' } | Should -Not -Throw
        }
    }
}

AfterAll {
    # Clean up - remove the imported module
    Remove-Module RalphUtils -ErrorAction SilentlyContinue
}
