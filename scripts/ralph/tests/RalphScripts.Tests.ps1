#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for Ralph PowerShell scripts.

.DESCRIPTION
    Tests ralph-locks.ps1, ralph-cleanup.ps1, ralph-parallel.ps1,
    ralph-dashboard.ps1, and ralph.ps1.
#>

BeforeAll {
    $script:ScriptsDir = Split-Path $PSScriptRoot -Parent
}

Describe 'ralph-locks.ps1' {
    Context 'Script Exists' {
        It 'Script file exists' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph-locks.ps1'
            Test-Path $scriptPath | Should -Be $true
        }

        It 'Has valid PowerShell syntax' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph-locks.ps1'
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }
    }

    Context 'Commands' {
        It 'Status command runs without error' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph-locks.ps1'
            { & $scriptPath Status } | Should -Not -Throw
        }

        It 'Help command runs without error' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph-locks.ps1'
            { & $scriptPath Help } | Should -Not -Throw
        }
    }
}

Describe 'ralph-cleanup.ps1' {
    Context 'Script Exists' {
        It 'Script file exists' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph-cleanup.ps1'
            Test-Path $scriptPath | Should -Be $true
        }

        It 'Has valid PowerShell syntax' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph-cleanup.ps1'
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }
    }

    Context 'Commands' {
        It 'Default command (summary) runs without error' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph-cleanup.ps1'
            { & $scriptPath } | Should -Not -Throw
        }

        It 'WhatIf mode runs without making changes' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph-cleanup.ps1'
            { & $scriptPath -Dead -WhatIf } | Should -Not -Throw
        }
    }
}

Describe 'ralph-parallel.ps1' {
    Context 'Script Exists' {
        It 'Script file exists' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph-parallel.ps1'
            Test-Path $scriptPath | Should -Be $true
        }

        It 'Has valid PowerShell syntax' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph-parallel.ps1'
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }
    }

    Context 'Commands' {
        It 'Status command runs without error' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph-parallel.ps1'
            { & $scriptPath Status } | Should -Not -Throw
        }

        It 'Help command runs without error' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph-parallel.ps1'
            { & $scriptPath Help } | Should -Not -Throw
        }
    }
}

Describe 'ralph-dashboard.ps1' {
    Context 'Script Exists' {
        It 'Script file exists' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph-dashboard.ps1'
            Test-Path $scriptPath | Should -Be $true
        }

        It 'Has valid PowerShell syntax' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph-dashboard.ps1'
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }
    }
}

Describe 'ralph.ps1' {
    Context 'Script Exists' {
        It 'Script file exists' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph.ps1'
            Test-Path $scriptPath | Should -Be $true
        }

        It 'Has valid PowerShell syntax' {
            $scriptPath = Join-Path $script:ScriptsDir 'ralph.ps1'
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }
    }

    Context 'Module Integration' {
        BeforeAll {
            $modulePath = Join-Path $script:ScriptsDir 'RalphUtils.psm1'
            Import-Module $modulePath -Force
        }

        It 'Can generate instance ID' {
            $id = Get-RalphInstanceId -Force
            $id | Should -Not -BeNullOrEmpty
        }

        It 'Can get short ID' {
            $shortId = Get-RalphShortId
            $shortId | Should -Not -BeNullOrEmpty
            $shortId.Length | Should -BeLessOrEqual 8
        }
    }
}

Describe 'RalphUtils.psm1' {
    BeforeAll {
        $modulePath = Join-Path $script:ScriptsDir 'RalphUtils.psm1'
        Import-Module $modulePath -Force
    }

    Context 'Module Exports' {
        It 'Exports Get-RalphPaths' {
            Get-Command Get-RalphPaths -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Get-RalphInstanceId' {
            Get-Command Get-RalphInstanceId -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Lock-RalphStory' {
            Get-Command Lock-RalphStory -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Update-RalphPrd' {
            Get-Command Update-RalphPrd -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Request-RalphStoryClaim' {
            Get-Command Request-RalphStoryClaim -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports New-RalphStoryBranch' {
            Get-Command New-RalphStoryBranch -Module RalphUtils | Should -Not -BeNull
        }

        It 'Exports Register-RalphCleanup' {
            Get-Command Register-RalphCleanup -Module RalphUtils | Should -Not -BeNull
        }
    }
}
