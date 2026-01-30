#Requires -Modules Pester

<#
.SYNOPSIS
    Pester test suite for Ralph Loop Supervisor PowerShell scripts

.DESCRIPTION
    Run with: Invoke-Pester -Path .\test-supervisor.tests.ps1 -Output Detailed

.NOTES
    Requires Pester v5+
    Install with: Install-Module -Name Pester -Force -SkipPublisherCheck
#>

BeforeAll {
    $ScriptRoot = Split-Path -Parent $PSScriptRoot
    $ScriptsDir = Join-Path $ScriptRoot "scripts"

    # Helper to create test environment
    function New-TestEnvironment {
        $testDir = Join-Path $env:TEMP "ralph-test-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $testDir ".claude") -Force | Out-Null
        Push-Location $testDir
        return $testDir
    }

    # Helper to clean up test environment
    function Remove-TestEnvironment {
        param([string]$TestDir)
        Pop-Location
        if ($TestDir -and (Test-Path $TestDir)) {
            Remove-Item -Path $TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Helper to create state file
    function New-StateFile {
        param(
            [int]$ProcessId = 999999,
            [int]$ClaudePid = 999998,
            [string]$Status = "running",
            [int]$Iteration = 1,
            [int]$MaxIterations = 0,
            [int]$RestartCount = 0
        )

        $state = @{
            pid = $ProcessId
            claude_pid = $ClaudePid
            status = $Status
            iteration = $Iteration
            max_iterations = $MaxIterations
            restart_count = $RestartCount
            prompt = "Test prompt"
            started_at = (Get-Date -Format "o")
        }

        $state | ConvertTo-Json | Set-Content -Path ".claude\ralph-supervisor.local.json"
    }

    # Helper to create in-session loop state file
    function New-LoopStateFile {
        param(
            [string]$Active = "true",
            [int]$Iteration = 1,
            [int]$MaxIterations = 0,
            [string]$CompletionPromise = "null",
            [string]$Prompt = "Test loop prompt"
        )

        $content = @"
---
active: $Active
iteration: $Iteration
max_iterations: $MaxIterations
completion_promise: $CompletionPromise
started_at: "$(Get-Date -Format "o")"
---
$Prompt
"@
        $content | Set-Content -Path ".claude\ralph-loop.local.md"
    }
}

Describe "ralph-status.ps1" {

    Describe "Unit Tests" {

        Context "When no supervisor is running" {
            BeforeEach {
                $script:testDir = New-TestEnvironment
            }

            AfterEach {
                Remove-TestEnvironment -TestDir $script:testDir
            }

            It "Should indicate no supervisor or loop is running" {
                $output = & "$ScriptsDir\ralph-status.ps1" *>&1 | Out-String
                $output | Should -Match "No Ralph supervisor or loop is currently running"
            }
        }

        Context "When in-session loop state exists" {
            BeforeEach {
                $script:testDir = New-TestEnvironment
                New-LoopStateFile -Iteration 42
            }

            AfterEach {
                Remove-TestEnvironment -TestDir $script:testDir
            }

            It "Should detect in-session loop state" {
                $output = & "$ScriptsDir\ralph-status.ps1" *>&1 | Out-String
                $output | Should -Match "In-Session Loop State"
            }

            It "Should display iteration count from loop state" {
                $output = & "$ScriptsDir\ralph-status.ps1" *>&1 | Out-String
                $output | Should -Match "42"
            }

            It "Should indicate loop state is stale" {
                $output = & "$ScriptsDir\ralph-status.ps1" *>&1 | Out-String
                $output | Should -Match "stale"
            }
        }

        Context "When state file exists with dead process" {
            BeforeEach {
                $script:testDir = New-TestEnvironment
                New-StateFile -ProcessId 999999
            }

            AfterEach {
                Remove-TestEnvironment -TestDir $script:testDir
            }

            It "Should detect stale state file" {
                $output = & "$ScriptsDir\ralph-status.ps1" *>&1 | Out-String
                $output | Should -Match "NOT RUNNING"
                $output | Should -Match "stale"
            }

            It "Should suggest cleanup option" {
                $output = & "$ScriptsDir\ralph-status.ps1" *>&1 | Out-String
                $output | Should -Match "-Clean"
            }
        }

        Context "State file parsing" {
            BeforeEach {
                $script:testDir = New-TestEnvironment
            }

            AfterEach {
                Remove-TestEnvironment -TestDir $script:testDir
            }

            It "Should display iteration count" {
                New-StateFile -Iteration 42
                $output = & "$ScriptsDir\ralph-status.ps1" *>&1 | Out-String
                $output | Should -Match "42"
            }

            It "Should display restart count" {
                New-StateFile -RestartCount 3
                $output = & "$ScriptsDir\ralph-status.ps1" *>&1 | Out-String
                $output | Should -Match "3"
            }

            It "Should show max iterations when set" {
                New-StateFile -MaxIterations 100
                $output = & "$ScriptsDir\ralph-status.ps1" *>&1 | Out-String
                $output | Should -Match "100"
            }
        }
    }

    Describe "Cleanup Tests" {

        Context "With -Clean flag for supervisor state" {
            BeforeEach {
                $script:testDir = New-TestEnvironment
                New-StateFile
            }

            AfterEach {
                Remove-TestEnvironment -TestDir $script:testDir
            }

            It "Should remove state file" {
                & "$ScriptsDir\ralph-status.ps1" -Clean *>&1 | Out-Null
                ".claude\ralph-supervisor.local.json" | Should -Not -Exist
            }

            It "Should remove PID file if exists" {
                "999999" | Set-Content ".claude\ralph-supervisor.pid"
                & "$ScriptsDir\ralph-status.ps1" -Clean *>&1 | Out-Null
                ".claude\ralph-supervisor.pid" | Should -Not -Exist
            }

            It "Should remove Claude PID file if exists" {
                "999998" | Set-Content ".claude\ralph-supervisor-claude.pid"
                & "$ScriptsDir\ralph-status.ps1" -Clean *>&1 | Out-Null
                ".claude\ralph-supervisor-claude.pid" | Should -Not -Exist
            }

            It "Should preserve log file" {
                "test log entry" | Set-Content ".claude\ralph-supervisor.log"
                & "$ScriptsDir\ralph-status.ps1" -Clean *>&1 | Out-Null
                ".claude\ralph-supervisor.log" | Should -Exist
            }

            It "Should show cleanup confirmation" {
                $output = & "$ScriptsDir\ralph-status.ps1" -Clean *>&1 | Out-String
                $output | Should -Match "Cleaning"
            }
        }

        Context "With -Clean flag for in-session loop state" {
            BeforeEach {
                $script:testDir = New-TestEnvironment
                New-LoopStateFile
            }

            AfterEach {
                Remove-TestEnvironment -TestDir $script:testDir
            }

            It "Should remove in-session loop state file" {
                & "$ScriptsDir\ralph-status.ps1" -Clean *>&1 | Out-Null
                ".claude\ralph-loop.local.md" | Should -Not -Exist
            }

            It "Should show cleanup confirmation for loop state" {
                $output = & "$ScriptsDir\ralph-status.ps1" -Clean *>&1 | Out-String
                $output | Should -Match "Cleaning"
            }
        }

        Context "With -Clean flag for both state types" {
            BeforeEach {
                $script:testDir = New-TestEnvironment
                New-StateFile
                New-LoopStateFile
            }

            AfterEach {
                Remove-TestEnvironment -TestDir $script:testDir
            }

            It "Should remove both state files" {
                & "$ScriptsDir\ralph-status.ps1" -Clean *>&1 | Out-Null
                ".claude\ralph-supervisor.local.json" | Should -Not -Exist
                ".claude\ralph-loop.local.md" | Should -Not -Exist
            }
        }

        Context "Cleanup without state file" {
            BeforeEach {
                $script:testDir = New-TestEnvironment
            }

            AfterEach {
                Remove-TestEnvironment -TestDir $script:testDir
            }

            It "Should handle missing state file gracefully" {
                { & "$ScriptsDir\ralph-status.ps1" -Clean *>&1 } | Should -Not -Throw
            }
        }
    }

    Describe "-All Flag Tests" {
        BeforeEach {
            $script:testDir = New-TestEnvironment
        }

        AfterEach {
            Remove-TestEnvironment -TestDir $script:testDir
        }

        It "Should not throw with -All flag" {
            { & "$ScriptsDir\ralph-status.ps1" -All *>&1 } | Should -Not -Throw
        }

        It "Should accept -All -Clean together" {
            { & "$ScriptsDir\ralph-status.ps1" -All -Clean *>&1 } | Should -Not -Throw
        }

        It "Should show in-session loop state files section" {
            $output = & "$ScriptsDir\ralph-status.ps1" -All *>&1 | Out-String
            $output | Should -Match "In-Session Loop State Files"
        }

        It "Should show supervisor state files section" {
            $output = & "$ScriptsDir\ralph-status.ps1" -All *>&1 | Out-String
            $output | Should -Match "Supervisor State Files"
        }

        It "Should detect in-session loop with -All flag" {
            New-LoopStateFile -Iteration 100
            $output = & "$ScriptsDir\ralph-status.ps1" -All *>&1 | Out-String
            $output | Should -Match "in-session loop"
            $output | Should -Match "100"
        }

        It "Should clean in-session loop with -All -Clean" {
            New-LoopStateFile
            & "$ScriptsDir\ralph-status.ps1" -All -Clean *>&1 | Out-Null
            ".claude\ralph-loop.local.md" | Should -Not -Exist
        }
    }
}

Describe "ralph-stop.ps1" {

    Describe "Unit Tests" {

        Context "When no supervisor is running" {
            BeforeEach {
                $script:testDir = New-TestEnvironment
            }

            AfterEach {
                Remove-TestEnvironment -TestDir $script:testDir
            }

            It "Should indicate no supervisor to stop" {
                $output = & "$ScriptsDir\ralph-stop.ps1" *>&1 | Out-String
                $output | Should -Match "No Ralph supervisor"
            }

            It "Should not throw" {
                { & "$ScriptsDir\ralph-stop.ps1" *>&1 } | Should -Not -Throw
            }
        }

        Context "When state file exists" {
            BeforeEach {
                $script:testDir = New-TestEnvironment
                New-StateFile
                "999999" | Set-Content ".claude\ralph-supervisor.pid"
            }

            AfterEach {
                Remove-TestEnvironment -TestDir $script:testDir
            }

            It "Should clean up state file" {
                & "$ScriptsDir\ralph-stop.ps1" *>&1 | Out-Null
                ".claude\ralph-supervisor.local.json" | Should -Not -Exist
            }

            It "Should clean up PID file" {
                & "$ScriptsDir\ralph-stop.ps1" *>&1 | Out-Null
                ".claude\ralph-supervisor.pid" | Should -Not -Exist
            }

            It "Should show stopped confirmation" {
                $output = & "$ScriptsDir\ralph-stop.ps1" *>&1 | Out-String
                $output | Should -Match "stopped"
            }
        }

        Context "Force flag" {
            BeforeEach {
                $script:testDir = New-TestEnvironment
                New-StateFile
            }

            AfterEach {
                Remove-TestEnvironment -TestDir $script:testDir
            }

            It "Should accept -Force flag" {
                { & "$ScriptsDir\ralph-stop.ps1" -Force *>&1 } | Should -Not -Throw
            }
        }
    }
}

Describe "ralph-supervisor.ps1" {

    Describe "Parameter Validation" {

        Context "Help parameter" {
            It "Should not throw when showing help" {
                # PowerShell's built-in help
                { Get-Help "$ScriptsDir\ralph-supervisor.ps1" } | Should -Not -Throw
            }
        }

        Context "Required parameters" {
            BeforeEach {
                $script:testDir = New-TestEnvironment
            }

            AfterEach {
                Remove-TestEnvironment -TestDir $script:testDir
            }

            It "Should require Prompt parameter" {
                {
                    # This should fail because Prompt is mandatory
                    & "$ScriptsDir\ralph-supervisor.ps1" *>&1
                } | Should -Throw
            }
        }
    }

    Describe "Background Mode Detection" {
        BeforeEach {
            $script:testDir = New-TestEnvironment
        }

        AfterEach {
            Remove-TestEnvironment -TestDir $script:testDir
        }

        It "Should detect already running supervisor" {
            # Create PID file with current process ID
            $PID | Set-Content ".claude\ralph-supervisor.pid"

            $output = & "$ScriptsDir\ralph-supervisor.ps1" -Prompt "test" -Background *>&1 | Out-String
            $output | Should -Match "already running"
        }
    }
}

Describe "Edge Cases" {

    Context "Malformed state files" {
        BeforeEach {
            $script:testDir = New-TestEnvironment
        }

        AfterEach {
            Remove-TestEnvironment -TestDir $script:testDir
        }

        It "Should handle malformed JSON" {
            "not valid json {{{" | Set-Content ".claude\ralph-supervisor.local.json"
            { & "$ScriptsDir\ralph-status.ps1" *>&1 } | Should -Not -Throw
        }

        It "Should handle empty state file" {
            "" | Set-Content ".claude\ralph-supervisor.local.json"
            { & "$ScriptsDir\ralph-status.ps1" *>&1 } | Should -Not -Throw
        }

        It "Should handle state file with null values" {
            @{
                pid = $null
                claude_pid = $null
                status = $null
                iteration = $null
            } | ConvertTo-Json | Set-Content ".claude\ralph-supervisor.local.json"

            { & "$ScriptsDir\ralph-status.ps1" *>&1 } | Should -Not -Throw
        }
    }

    Context "Missing directories" {
        BeforeEach {
            $script:testDir = New-TestEnvironment
            Remove-Item ".claude" -Recurse -Force
        }

        AfterEach {
            Remove-TestEnvironment -TestDir $script:testDir
        }

        It "Should handle missing .claude directory" {
            $output = & "$ScriptsDir\ralph-status.ps1" *>&1 | Out-String
            $output | Should -Match "No Ralph supervisor"
        }
    }

    Context "Large values" {
        BeforeEach {
            $script:testDir = New-TestEnvironment
        }

        AfterEach {
            Remove-TestEnvironment -TestDir $script:testDir
        }

        It "Should handle large iteration numbers" {
            @{
                pid = 999999
                status = "running"
                iteration = 999999999
                max_iterations = 0
            } | ConvertTo-Json | Set-Content ".claude\ralph-supervisor.local.json"

            $output = & "$ScriptsDir\ralph-status.ps1" *>&1 | Out-String
            $output | Should -Match "999999999"
        }
    }

    Context "Special characters" {
        BeforeEach {
            $script:testDir = New-TestEnvironment
        }

        AfterEach {
            Remove-TestEnvironment -TestDir $script:testDir
        }

        It "Should handle special characters in prompt" {
            @{
                pid = 999999
                status = "running"
                iteration = 1
                prompt = 'Test with "quotes" and $variables and <tags>'
            } | ConvertTo-Json | Set-Content ".claude\ralph-supervisor.local.json"

            { & "$ScriptsDir\ralph-status.ps1" *>&1 } | Should -Not -Throw
        }
    }

    Context "Idempotency" {
        BeforeEach {
            $script:testDir = New-TestEnvironment
            New-StateFile
        }

        AfterEach {
            Remove-TestEnvironment -TestDir $script:testDir
        }

        It "Should handle double cleanup" {
            & "$ScriptsDir\ralph-status.ps1" -Clean *>&1 | Out-Null
            # Second cleanup should not fail
            { & "$ScriptsDir\ralph-status.ps1" -Clean *>&1 } | Should -Not -Throw
        }

        It "Should handle double stop" {
            & "$ScriptsDir\ralph-stop.ps1" *>&1 | Out-Null
            # Second stop should not fail
            { & "$ScriptsDir\ralph-stop.ps1" *>&1 } | Should -Not -Throw
        }
    }
}

Describe "Integration Tests" {

    Context "Status after cleanup" {
        BeforeEach {
            $script:testDir = New-TestEnvironment
            New-StateFile
        }

        AfterEach {
            Remove-TestEnvironment -TestDir $script:testDir
        }

        It "Should show no supervisor after cleanup" {
            & "$ScriptsDir\ralph-status.ps1" -Clean *>&1 | Out-Null
            $output = & "$ScriptsDir\ralph-status.ps1" *>&1 | Out-String
            $output | Should -Match "No Ralph supervisor or loop is currently running"
        }
    }

    Context "Status after stop" {
        BeforeEach {
            $script:testDir = New-TestEnvironment
            New-StateFile
        }

        AfterEach {
            Remove-TestEnvironment -TestDir $script:testDir
        }

        It "Should show no supervisor after stop" {
            & "$ScriptsDir\ralph-stop.ps1" *>&1 | Out-Null
            $output = & "$ScriptsDir\ralph-status.ps1" *>&1 | Out-String
            $output | Should -Match "No Ralph supervisor or loop is currently running"
        }
    }
}
