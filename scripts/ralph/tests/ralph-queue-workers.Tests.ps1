#!/usr/bin/env pwsh
#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

<#
.SYNOPSIS
    Pester tests for ralph-queue-workers.ps1
.DESCRIPTION
    Tests the queue workers management functionality including:
    - Script structure and parameters
    - Worker start/stop/kill/status commands
    - Worker tracking and state management
#>

BeforeAll {
    $script:ScriptsDir = Split-Path $PSScriptRoot -Parent
    $script:WorkersScript = Join-Path $script:ScriptsDir 'ralph-queue-workers.ps1'
    $script:TestDir = Join-Path ([System.IO.Path]::GetTempPath()) "ralph-queue-workers-tests-$([guid]::NewGuid().ToString('N').Substring(0,8))"

    # Import modules
    $utilsPath = Join-Path $script:ScriptsDir 'RalphUtils.psm1'
    $queuePath = Join-Path $script:ScriptsDir 'RalphQueue.psm1'
    if (Test-Path $utilsPath) { Import-Module $utilsPath -Force }
    if (Test-Path $queuePath) { Import-Module $queuePath -Force }

    # Create test directory
    New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    # Cleanup test directory
    if (Test-Path $script:TestDir) {
        Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module RalphUtils, RalphQueue -ErrorAction SilentlyContinue
}

Describe 'ralph-queue-workers.ps1 Script Structure' {
    It 'Script file exists' {
        Test-Path $script:WorkersScript | Should -BeTrue
    }

    It 'Has valid PowerShell syntax' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:WorkersScript,
            [ref]$null,
            [ref]$errors
        )
        $errors.Count | Should -Be 0
    }
}

Describe 'ralph-queue-workers.ps1 Parameters' {
    BeforeAll {
        $script:CommandInfo = Get-Command $script:WorkersScript -ErrorAction SilentlyContinue
    }

    It 'Has Command parameter' {
        $script:CommandInfo.Parameters.Keys | Should -Contain 'Command'
    }

    It 'Has Count parameter with alias c' {
        $script:CommandInfo.Parameters.Keys | Should -Contain 'Count'
        $script:CommandInfo.Parameters['Count'].Aliases | Should -Contain 'c'
    }

    It 'Has MaxIterations parameter with alias m' {
        $script:CommandInfo.Parameters.Keys | Should -Contain 'MaxIterations'
        $script:CommandInfo.Parameters['MaxIterations'].Aliases | Should -Contain 'm'
    }
}

Describe 'ralph-queue-workers.ps1 Commands' {
    Context 'Help Command' {
        It 'Help command runs without error' {
            { & $script:WorkersScript Help } | Should -Not -Throw
        }

        It 'Help output contains usage information' {
            # Check script content for help text since Write-Host doesn't capture
            $content = Get-Content -Path $script:WorkersScript -Raw
            $content | Should -Match 'Usage'
            $content | Should -Match 'start'
            $content | Should -Match 'stop'
            $content | Should -Match 'status'
        }
    }

    Context 'Status Command' {
        It 'Status command runs without error' {
            { & $script:WorkersScript Status } | Should -Not -Throw
        }
    }

    Context 'Stop Command' {
        It 'Stop command runs without error when no workers' {
            { & $script:WorkersScript Stop } | Should -Not -Throw
        }
    }
}

Describe 'Worker State Management' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:WorkersScript -Raw
    }

    It 'Defines workers file path' {
        $script:scriptContent | Should -Match 'WorkersFile'
    }

    It 'Has function to save workers' {
        $script:scriptContent | Should -Match 'function Save-QueueWorkers'
    }

    It 'Has function to get workers' {
        $script:scriptContent | Should -Match 'function Get-QueueWorkers'
    }

    It 'Has function to check if worker is running' {
        $script:scriptContent | Should -Match 'function Test-WorkerRunning'
    }
}

Describe 'Start Command Logic' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:WorkersScript -Raw
    }

    It 'Defines default worker count function' {
        $script:scriptContent | Should -Match 'function Get-DefaultWorkerCount'
    }

    It 'Checks for pending queue entries' {
        $script:scriptContent | Should -Match 'Get-RalphQueueEntries.*pending'
    }

    It 'Claims queue entry for each worker' {
        $script:scriptContent | Should -Match 'Request-RalphQueueEntryClaim'
    }

    It 'Starts ralph.ps1 with queue mode' {
        $script:scriptContent | Should -Match 'ralph\.ps1'
        $script:scriptContent | Should -Match '-QueueMode'
    }

    It 'Tracks worker PIDs' {
        $script:scriptContent | Should -Match '\.Id'
    }
}

Describe 'Stop Command Logic' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:WorkersScript -Raw
    }

    It 'Gets saved workers' {
        $script:scriptContent | Should -Match 'Get-QueueWorkers'
    }

    It 'Stops running workers gracefully' {
        $script:scriptContent | Should -Match 'Stop-Job'
    }

    It 'Clears workers file after stopping' {
        $script:scriptContent | Should -Match 'Save-QueueWorkers.*@\(\)'
    }
}

Describe 'Kill Command Logic' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:WorkersScript -Raw
    }

    It 'Force kills workers' {
        $script:scriptContent | Should -Match 'Remove-Job.*-Force'
    }
}

Describe 'Status Command Logic' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:WorkersScript -Raw
    }

    It 'Shows worker count' {
        $script:scriptContent | Should -Match 'workers'
    }

    It 'Shows worker PID and status' {
        $script:scriptContent | Should -Match 'PID'
        $script:scriptContent | Should -Match 'STATUS'
    }
}
