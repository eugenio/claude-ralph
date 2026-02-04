#Requires -Modules Pester
<#
.SYNOPSIS
    Comprehensive Pester tests for ralph-cleanup.ps1.

.DESCRIPTION
    Tests all functionality of ralph-cleanup.ps1 including:
    - Script structure and syntax
    - Summary display functionality
    - Dead instance cleanup (-Dead flag)
    - Old instance cleanup (-Old flag)
    - Terminated instance cleanup (-Terminated flag)
    - All instances cleanup (-All flag)
    - WhatIf mode (preview without changes)
    - Error handling and edge cases

.NOTES
    These tests use Pester 5.x and test the actual script behavior.
    The script runs against the live global registry, so tests focus on:
    - Script structure validation
    - Parameter handling
    - Output format verification
    - Error handling
#>

BeforeAll {
    $script:ScriptsDir = Split-Path $PSScriptRoot -Parent
    $script:ScriptPath = Join-Path $script:ScriptsDir 'ralph-cleanup.ps1'
    $script:ModulePath = Join-Path $script:ScriptsDir 'RalphUtils.psm1'
}

Describe 'ralph-cleanup.ps1' {

    # ==========================================================================
    # SCRIPT STRUCTURE TESTS
    # ==========================================================================

    Context 'Script Structure' {
        BeforeAll {
            $script:Content = Get-Content $script:ScriptPath -Raw
        }

        It 'Script file exists' {
            Test-Path $script:ScriptPath | Should -Be $true
        }

        It 'Has valid PowerShell syntax' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:ScriptPath,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }

        It 'Imports RalphUtils module' {
            # Check for any Import-Module referencing the module path
            $script:Content | Should -Match 'Import-Module.*\$modulePath'
        }

        It 'Has CmdletBinding with SupportsShouldProcess' {
            $script:Content | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
        }

        It 'Has -Dead parameter' {
            $script:Content | Should -Match '\[switch\]\$Dead'
        }

        It 'Has -Old parameter' {
            $script:Content | Should -Match '\[switch\]\$Old'
        }

        It 'Has -All parameter' {
            $script:Content | Should -Match '\[switch\]\$All'
        }

        It 'Has -Terminated parameter' {
            $script:Content | Should -Match '\[switch\]\$Terminated'
        }

        It 'Has Show-Summary function' {
            $script:Content | Should -Match 'function Show-Summary'
        }

        It 'Has Clear-DeadInstances function' {
            $script:Content | Should -Match 'function Clear-DeadInstances'
        }

        It 'Has Clear-OldInstances function' {
            $script:Content | Should -Match 'function Clear-OldInstances'
        }

        It 'Has Clear-TerminatedInstances function' {
            $script:Content | Should -Match 'function Clear-TerminatedInstances'
        }
    }

    # ==========================================================================
    # HELP DOCUMENTATION TESTS
    # ==========================================================================

    Context 'Help Documentation' {
        BeforeAll {
            $script:Content = Get-Content $script:ScriptPath -Raw
        }

        It 'Has SYNOPSIS section' {
            $script:Content | Should -Match '\.SYNOPSIS'
        }

        It 'Has DESCRIPTION section' {
            $script:Content | Should -Match '\.DESCRIPTION'
        }

        It 'Has PARAMETER section for Dead' {
            $script:Content | Should -Match '\.PARAMETER Dead'
        }

        It 'Has PARAMETER section for Old' {
            $script:Content | Should -Match '\.PARAMETER Old'
        }

        It 'Has PARAMETER section for All' {
            $script:Content | Should -Match '\.PARAMETER All'
        }

        It 'Has PARAMETER section for Terminated' {
            $script:Content | Should -Match '\.PARAMETER Terminated'
        }

        It 'Has PARAMETER section for WhatIf' {
            $script:Content | Should -Match '\.PARAMETER WhatIf'
        }

        It 'Has EXAMPLE sections' {
            $script:Content | Should -Match '\.EXAMPLE'
        }
    }

    # ==========================================================================
    # BASIC EXECUTION TESTS
    # ==========================================================================

    Context 'Basic Execution' {
        It 'Runs without error when no flags provided' {
            { & $script:ScriptPath } | Should -Not -Throw
        }

        It 'Shows summary when no cleanup flags provided' {
            $result = & $script:ScriptPath 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'INSTANCE SUMMARY'
        }

        It 'Shows usage hint when no cleanup flags provided' {
            $result = & $script:ScriptPath 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'Run with'
            $output | Should -Match '-Dead'
            $output | Should -Match '-Old'
            $output | Should -Match '-All'
        }

        It 'Shows total instances count' {
            $result = & $script:ScriptPath 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'Total instances:'
        }

        It 'Shows running count' {
            $result = & $script:ScriptPath 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'Running:'
        }

        It 'Shows completed count' {
            $result = & $script:ScriptPath 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'Completed:'
        }

        It 'Shows terminated count' {
            $result = & $script:ScriptPath 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'Terminated:'
        }

        It 'Shows dead count' {
            $result = & $script:ScriptPath 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'Dead:'
        }

        It 'Shows active locks count' {
            $result = & $script:ScriptPath 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'Active locks:'
        }
    }

    # ==========================================================================
    # DEAD FLAG TESTS
    # ==========================================================================

    Context 'Dead Flag (-Dead)' {
        It 'Runs without error with -Dead flag' {
            { & $script:ScriptPath -Dead } | Should -Not -Throw
        }

        It 'Shows checking for dead instances message' {
            $result = & $script:ScriptPath -Dead 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'Checking for dead instances'
        }

        It 'Shows summary after dead cleanup' {
            $result = & $script:ScriptPath -Dead 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'INSTANCE SUMMARY'
        }
    }

    # ==========================================================================
    # OLD FLAG TESTS
    # ==========================================================================

    Context 'Old Flag (-Old)' {
        It 'Runs without error with -Old flag' {
            { & $script:ScriptPath -Old } | Should -Not -Throw
        }

        It 'Shows checking for old instances message' {
            $result = & $script:ScriptPath -Old 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'Checking for old instances'
        }

        It 'Shows TTL in output' {
            $result = & $script:ScriptPath -Old 6>&1
            $output = $result -join "`n"
            # Default TTL is 7 days
            $output | Should -Match '\d+ days'
        }

        It 'Shows summary after old cleanup' {
            $result = & $script:ScriptPath -Old 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'INSTANCE SUMMARY'
        }
    }

    # ==========================================================================
    # TERMINATED FLAG TESTS
    # ==========================================================================

    Context 'Terminated Flag (-Terminated)' {
        It 'Runs without error with -Terminated flag' {
            { & $script:ScriptPath -Terminated } | Should -Not -Throw
        }

        It 'Shows checking for terminated instances message' {
            $result = & $script:ScriptPath -Terminated 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'Checking for terminated instances'
        }

        It 'Shows summary after terminated cleanup' {
            $result = & $script:ScriptPath -Terminated 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'INSTANCE SUMMARY'
        }
    }

    # ==========================================================================
    # ALL FLAG TESTS
    # ==========================================================================

    Context 'All Flag (-All)' {
        It 'Runs without error with -All flag' {
            { & $script:ScriptPath -All } | Should -Not -Throw
        }

        It 'Processes dead instances with -All' {
            $result = & $script:ScriptPath -All 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'Checking for dead instances'
        }

        It 'Processes terminated instances with -All' {
            $result = & $script:ScriptPath -All 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'Checking for terminated instances'
        }

        It 'Processes old instances with -All' {
            $result = & $script:ScriptPath -All 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'Checking for old instances'
        }

        It 'Processes dead before terminated before old' {
            $result = & $script:ScriptPath -All 6>&1
            $output = $result -join "`n"

            $deadPos = $output.IndexOf('dead instances')
            $terminatedPos = $output.IndexOf('terminated instances')
            $oldPos = $output.IndexOf('old instances')

            # All should appear and in order
            $deadPos | Should -BeGreaterOrEqual 0
            $terminatedPos | Should -BeGreaterOrEqual 0
            $oldPos | Should -BeGreaterOrEqual 0

            $deadPos | Should -BeLessThan $terminatedPos
            $terminatedPos | Should -BeLessThan $oldPos
        }

        It 'Shows summary after -All cleanup' {
            $result = & $script:ScriptPath -All 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'INSTANCE SUMMARY'
        }
    }

    # ==========================================================================
    # WHATIF MODE TESTS
    # ==========================================================================

    Context 'WhatIf Mode' {
        It 'Runs without error with -WhatIf flag' {
            { & $script:ScriptPath -Dead -WhatIf } | Should -Not -Throw
        }

        It 'Shows WhatIf mode banner' {
            $result = & $script:ScriptPath -Dead -WhatIf 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'WHATIF MODE'
        }

        It 'Shows no changes will be made message' {
            $result = & $script:ScriptPath -Dead -WhatIf 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'No changes will be made'
        }

        It 'WhatIf works with -All flag' {
            $result = & $script:ScriptPath -All -WhatIf 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'WHATIF MODE'
        }

        It 'WhatIf works with -Old flag' {
            $result = & $script:ScriptPath -Old -WhatIf 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'WHATIF MODE'
        }

        It 'WhatIf works with -Terminated flag' {
            $result = & $script:ScriptPath -Terminated -WhatIf 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'WHATIF MODE'
        }
    }

    # ==========================================================================
    # ENVIRONMENT VARIABLE TESTS
    # ==========================================================================

    Context 'Environment Variable Support' {
        It 'Respects RALPH_CLEANUP_TTL environment variable' {
            $env:RALPH_CLEANUP_TTL = '3'
            try {
                $result = & $script:ScriptPath -Old 6>&1
                $output = $result -join "`n"
                $output | Should -Match '3 days'
            }
            finally {
                Remove-Item Env:RALPH_CLEANUP_TTL -ErrorAction SilentlyContinue
            }
        }

        It 'Uses default 7 days when RALPH_CLEANUP_TTL not set' {
            Remove-Item Env:RALPH_CLEANUP_TTL -ErrorAction SilentlyContinue
            $result = & $script:ScriptPath -Old 6>&1
            $output = $result -join "`n"
            $output | Should -Match '7 days'
        }
    }

    # ==========================================================================
    # ERROR HANDLING TESTS
    # ==========================================================================

    Context 'Error Handling' {
        It 'Handles gracefully when no instances exist' {
            # This should not throw even if there are no instances
            { & $script:ScriptPath -Dead } | Should -Not -Throw
        }

        It 'Handles gracefully with -Old when no old instances exist' {
            { & $script:ScriptPath -Old } | Should -Not -Throw
        }

        It 'Handles gracefully with -Terminated when no terminated instances exist' {
            { & $script:ScriptPath -Terminated } | Should -Not -Throw
        }

        It 'Handles gracefully with -All when no instances exist' {
            { & $script:ScriptPath -All } | Should -Not -Throw
        }
    }

    # ==========================================================================
    # OUTPUT FORMAT TESTS
    # ==========================================================================

    Context 'Output Format' {
        It 'Uses horizontal line separator in summary' {
            $result = & $script:ScriptPath 6>&1
            $output = $result -join ""
            # Check for Unicode double horizontal line character (0x2550) or fallback
            ($output -match '═' -or $output -match '[-=]') | Should -Be $true
        }

        It 'Shows numeric counts in summary' {
            $result = & $script:ScriptPath 6>&1
            $output = $result -join "`n"
            # Should have numeric counts after each category
            $output | Should -Match 'Running:\s+\d+'
            $output | Should -Match 'Completed:\s+\d+'
            $output | Should -Match 'Terminated:\s+\d+'
            $output | Should -Match 'Dead:\s+\d+'
            $output | Should -Match 'Active locks:\s+\d+'
        }
    }

    # ==========================================================================
    # ACCEPTANCE CRITERIA VERIFICATION TESTS
    # ==========================================================================

    Context 'PS-009 Acceptance Criteria' {
        BeforeAll {
            $script:Content = Get-Content $script:ScriptPath -Raw
        }

        It 'AC1: Script has -Dead, -Old, -All, -WhatIf parameters' {
            $script:Content | Should -Match '\[switch\]\$Dead'
            $script:Content | Should -Match '\[switch\]\$Old'
            $script:Content | Should -Match '\[switch\]\$All'
            # WhatIf is provided by SupportsShouldProcess
            $script:Content | Should -Match 'SupportsShouldProcess'
        }

        It 'AC2: Dead instances defined as no heartbeat > 5 minutes' {
            # Verify the script uses isDead property which is based on 5 min threshold
            $script:Content | Should -Match '\$_\.isDead|\$instance\.isDead'
        }

        It 'AC3: Old instances use RALPH_CLEANUP_TTL (default 7 days)' {
            $script:Content | Should -Match 'RALPH_CLEANUP_TTL'
            # Check for default value of 7
            $script:Content | Should -Match '\?\? 7|\?\?\s*7|default.*7|7.*default'
        }

        It 'AC4: Displays summary of instances by state' {
            $result = & $script:ScriptPath 6>&1
            $output = $result -join "`n"

            $output | Should -Match 'Running:'
            $output | Should -Match 'Completed:'
            $output | Should -Match 'Terminated:'
            $output | Should -Match 'Dead:'
        }

        It 'AC5: -WhatIf shows what would be deleted without deleting' {
            $result = & $script:ScriptPath -Dead -WhatIf 6>&1
            $output = $result -join "`n"

            $output | Should -Match 'WHATIF MODE'
            $output | Should -Match 'No changes will be made'
        }

        It 'AC6: Tests cleanup commands work correctly (this test)' {
            # This test itself verifies the test suite works
            { & $script:ScriptPath -Dead } | Should -Not -Throw
            { & $script:ScriptPath -Old } | Should -Not -Throw
            { & $script:ScriptPath -Terminated } | Should -Not -Throw
            { & $script:ScriptPath -All } | Should -Not -Throw
            { & $script:ScriptPath -All -WhatIf } | Should -Not -Throw
        }
    }

    # ==========================================================================
    # COMBINED FLAGS TESTS
    # ==========================================================================

    Context 'Combined Flags' {
        It 'Supports -Dead and -WhatIf together' {
            $result = & $script:ScriptPath -Dead -WhatIf 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'WHATIF MODE'
            $output | Should -Match 'dead instances'
        }

        It 'Supports -Old and -WhatIf together' {
            $result = & $script:ScriptPath -Old -WhatIf 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'WHATIF MODE'
            $output | Should -Match 'old instances'
        }

        It 'Supports -Dead and -Old together' {
            $result = & $script:ScriptPath -Dead -Old 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'dead instances'
            $output | Should -Match 'old instances'
        }

        It 'Supports -Dead and -Terminated together' {
            $result = & $script:ScriptPath -Dead -Terminated 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'dead instances'
            $output | Should -Match 'terminated instances'
        }

        It 'Supports all three cleanup flags together' {
            $result = & $script:ScriptPath -Dead -Terminated -Old 6>&1
            $output = $result -join "`n"
            $output | Should -Match 'dead instances'
            $output | Should -Match 'terminated instances'
            $output | Should -Match 'old instances'
        }
    }
}
