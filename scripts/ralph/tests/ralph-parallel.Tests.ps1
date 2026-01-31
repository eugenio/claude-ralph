#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for ralph-parallel.ps1.

.DESCRIPTION
    Test suite for ralph-parallel.ps1 functionality including:
    - Parameter definitions and aliases (-p/--prd, -r/--project)
    - Help output documentation
    - Path validation logic
    - Job argument building with paths
#>

BeforeAll {
    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..' 'RalphUtils.psm1'
    Import-Module $modulePath -Force

    # Script path
    $script:parallelScript = Join-Path $PSScriptRoot '..' 'ralph-parallel.ps1'
}

# =============================================================================
# SCRIPT STRUCTURE TESTS
# =============================================================================

Describe 'ralph-parallel.ps1 Script Structure' {
    It 'Script file exists' {
        Test-Path $script:parallelScript | Should -BeTrue
    }

    It 'Has valid PowerShell syntax' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:parallelScript,
            [ref]$null,
            [ref]$errors
        ) | Out-Null
        $errors.Count | Should -Be 0
    }
}

# =============================================================================
# PARAMETER DEFINITION TESTS
# =============================================================================

Describe 'Parameter Definitions' {
    BeforeAll {
        $script:ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:parallelScript,
            [ref]$null,
            [ref]$null
        )
        $script:paramBlock = $script:ast.ParamBlock
    }

    Context 'Prd Parameter' {
        It 'Has Prd parameter defined' {
            $prdParam = $script:paramBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Prd' }
            $prdParam | Should -Not -BeNullOrEmpty
        }

        It 'Prd parameter has alias "p"' {
            $prdParam = $script:paramBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Prd' }
            $aliasAttr = $prdParam.Attributes | Where-Object { $_.TypeName.Name -eq 'Alias' }
            $aliasAttr | Should -Not -BeNullOrEmpty
            $aliasAttr.PositionalArguments[0].Value | Should -Be 'p'
        }

        It 'Prd parameter is string type' {
            $prdParam = $script:paramBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Prd' }
            $typeConstraint = $prdParam.Attributes | Where-Object { $_ -is [System.Management.Automation.Language.TypeConstraintAst] }
            $typeConstraint.TypeName.Name | Should -Be 'string'
        }
    }

    Context 'ProjectRoot Parameter' {
        It 'Has ProjectRoot parameter defined' {
            $projectParam = $script:paramBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'ProjectRoot' }
            $projectParam | Should -Not -BeNullOrEmpty
        }

        It 'ProjectRoot parameter has alias "r"' {
            $projectParam = $script:paramBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'ProjectRoot' }
            $aliasAttr = $projectParam.Attributes | Where-Object { $_.TypeName.Name -eq 'Alias' }
            $aliasAttr | Should -Not -BeNullOrEmpty
            $aliasAttr.PositionalArguments[0].Value | Should -Be 'r'
        }

        It 'ProjectRoot parameter is string type' {
            $projectParam = $script:paramBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'ProjectRoot' }
            $typeConstraint = $projectParam.Attributes | Where-Object { $_ -is [System.Management.Automation.Language.TypeConstraintAst] }
            $typeConstraint.TypeName.Name | Should -Be 'string'
        }
    }
}

# =============================================================================
# HELP OUTPUT TESTS
# =============================================================================

Describe 'Help Output' {
    BeforeAll {
        # Capture help output by running in a child process with transcript
        $script:helpOutput = pwsh -NoProfile -Command "& '$($script:parallelScript)' Help" 2>&1 | Out-String
    }

    It 'Displays usage information' {
        $script:helpOutput | Should -Match 'Usage:'
    }

    It 'Documents -p/--prd option' {
        $script:helpOutput | Should -Match '-p'
        $script:helpOutput | Should -Match '(--prd|Prd)'
    }

    It 'Documents -r/--project option' {
        $script:helpOutput | Should -Match '-r'
        $script:helpOutput | Should -Match '(--project|ProjectRoot|project)'
    }

    It 'Mentions prd.json in help' {
        $script:helpOutput | Should -Match 'prd'
    }

    It 'Mentions project directory in help' {
        $script:helpOutput | Should -Match '(project|Project)'
    }
}

# =============================================================================
# PATH VALIDATION TESTS
# =============================================================================

Describe 'Path Validation' {
    BeforeAll {
        $script:testDir = Join-Path $TestDrive 'parallel-test'
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null
    }

    Context 'PRD Path Validation' {
        It 'Errors when PRD file does not exist' {
            $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Start -Prd '/nonexistent/prd.json'" 2>&1 | Out-String
            $result | Should -Match '(not found|does not exist|Error)'
        }

        It 'Errors when PRD path is a directory' {
            $dirPath = Join-Path $script:testDir 'not-a-file'
            New-Item -Path $dirPath -ItemType Directory -Force | Out-Null

            $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Start -Prd '$dirPath'" 2>&1 | Out-String
            $result | Should -Match '(not|Error|file)'
        }

        It 'Accepts valid PRD file path' {
            $prdPath = Join-Path $script:testDir 'valid-prd.json'
            $prd = @{
                featureName = 'Test'
                userStories = @()
            }
            $prd | ConvertTo-Json | Set-Content $prdPath

            # Should not error on validation (may error later on actual start)
            # We're testing that validation passes, not that start succeeds
            $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Help -Prd '$prdPath'" 2>&1 | Out-String
            $result | Should -Not -Match 'PRD file not found'
        }
    }

    Context 'Project Path Validation' {
        It 'Errors when project directory does not exist' {
            $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Start -ProjectRoot '/nonexistent/project'" 2>&1 | Out-String
            $result | Should -Match '(not found|does not exist|Error)'
        }

        It 'Errors when project path is a file' {
            $filePath = Join-Path $script:testDir 'not-a-dir.txt'
            'test content' | Set-Content $filePath

            $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Start -ProjectRoot '$filePath'" 2>&1 | Out-String
            $result | Should -Match '(not|Error|directory)'
        }

        It 'Accepts valid project directory path' {
            $projectPath = Join-Path $script:testDir 'valid-project'
            New-Item -Path $projectPath -ItemType Directory -Force | Out-Null

            # Should not error on validation
            $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Help -ProjectRoot '$projectPath'" 2>&1 | Out-String
            $result | Should -Not -Match 'Project directory not found'
        }
    }

    Context 'Combined Path Validation' {
        It 'Validates both PRD and project paths' {
            $prdPath = Join-Path $script:testDir 'combined-prd.json'
            $projectPath = Join-Path $script:testDir 'combined-project'

            $prd = @{
                featureName = 'Test'
                userStories = @()
            }
            $prd | ConvertTo-Json | Set-Content $prdPath
            New-Item -Path $projectPath -ItemType Directory -Force | Out-Null

            # Should not error on validation
            $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Help -Prd '$prdPath' -ProjectRoot '$projectPath'" 2>&1 | Out-String
            $result | Should -Not -Match 'not found'
        }
    }
}

# =============================================================================
# START-RALPHINSTANCES FUNCTION TESTS
# =============================================================================

Describe 'Start-RalphInstances Function' {
    BeforeAll {
        # Read the script content to check function definition
        $script:scriptContent = Get-Content $script:parallelScript -Raw
    }

    It 'Function accepts PrdPath parameter' {
        $script:scriptContent | Should -Match 'Start-RalphInstances.*\$Prd|\$PrdPath'
    }

    It 'Function accepts ProjectPath parameter' {
        $script:scriptContent | Should -Match 'Start-RalphInstances.*\$Project|\$ProjectPath|\$ProjectRoot'
    }
}

# =============================================================================
# COMMAND INTEGRATION TESTS
# =============================================================================

Describe 'Command Integration' {
    Context 'Status Command' {
        It 'Status command works without path options' {
            # Status should work even without PRD
            $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Status" 2>&1 | Out-String
            # Should not error on missing path options
            $result | Should -Not -Match 'PRD file not found'
            $result | Should -Not -Match 'Project directory not found'
        }
    }

    Context 'Stop Command' {
        It 'Stop command works without path options' {
            $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Stop" 2>&1 | Out-String
            # Should not error on missing path options
            $result | Should -Not -Match 'PRD file not found'
        }
    }

    Context 'Help Command' {
        It 'Help command works with path options' {
            $prdPath = Join-Path $TestDrive 'help-test-prd.json'
            @{ featureName = 'Test'; userStories = @() } | ConvertTo-Json | Set-Content $prdPath

            $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Help -Prd '$prdPath'" 2>&1 | Out-String
            $result | Should -Match 'Usage:'
        }
    }
}

# =============================================================================
# ALIAS USAGE TESTS
# =============================================================================

Describe 'Alias Usage' {
    BeforeAll {
        $script:testDir = Join-Path $TestDrive 'alias-test'
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null

        $script:prdPath = Join-Path $script:testDir 'alias-prd.json'
        @{ featureName = 'Test'; userStories = @() } | ConvertTo-Json | Set-Content $script:prdPath
    }

    It 'Short alias -p works for Prd' {
        $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Help -p '$($script:prdPath)'" 2>&1 | Out-String
        $result | Should -Match 'Usage:'
    }

    It 'Short alias -r works for ProjectRoot' {
        $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Help -r '$($script:testDir)'" 2>&1 | Out-String
        $result | Should -Match 'Usage:'
    }

    It 'Combined short aliases work' {
        $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Help -p '$($script:prdPath)' -r '$($script:testDir)'" 2>&1 | Out-String
        $result | Should -Match 'Usage:'
    }
}

# =============================================================================
# REGRESSION TESTS
# =============================================================================

Describe 'Regression Tests' {
    It 'Existing Count parameter still works' {
        $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Help -Count 3" 2>&1 | Out-String
        $result | Should -Match 'Usage:'
    }

    It 'Existing MaxIterations parameter still works' {
        $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Help -MaxIterations 5" 2>&1 | Out-String
        $result | Should -Match 'Usage:'
    }

    It 'Combined existing and new parameters work' {
        $prdPath = Join-Path $TestDrive 'regression-prd.json'
        @{ featureName = 'Test'; userStories = @() } | ConvertTo-Json | Set-Content $prdPath

        $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Help -Count 2 -MaxIterations 5 -Prd '$prdPath'" 2>&1 | Out-String
        $result | Should -Match 'Usage:'
    }
}

# =============================================================================
# CHECK COMMAND TESTS
# =============================================================================

Describe 'ralph-parallel.ps1 check command' {
    BeforeAll {
        $script:testDir = Join-Path $TestDrive 'check-test'
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null
    }

    Context 'Complete PRD' {
        BeforeAll {
            $script:completePrd = Join-Path $script:testDir 'complete.json'
            @{
                featureName = 'Complete Feature'
                userStories = @(
                    @{ id = 'US-001'; title = 'Story 1'; passes = $true },
                    @{ id = 'US-002'; title = 'Story 2'; passes = $true },
                    @{ id = 'US-003'; title = 'Story 3'; passes = $true }
                )
            } | ConvertTo-Json -Depth 5 | Set-Content $script:completePrd
        }

        It 'Returns 0 incomplete in quiet mode' {
            $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Check -Prd '$($script:completePrd)' -Quiet" 2>&1
            $result | Should -Contain '0'
        }

        It 'Returns exit code 0 for complete PRD' {
            pwsh -NoProfile -Command "& '$($script:parallelScript)' Check -Prd '$($script:completePrd)' -Quiet; exit `$LASTEXITCODE"
            $LASTEXITCODE | Should -Be 0
        }

        It 'Shows STATUS: COMPLETE in verbose mode' {
            $output = pwsh -NoProfile -Command "& '$($script:parallelScript)' Check -Prd '$($script:completePrd)'" 2>&1 | Out-String
            $output | Should -Match 'STATUS: COMPLETE'
        }
    }

    Context 'Incomplete PRD' {
        BeforeAll {
            $script:incompletePrd = Join-Path $script:testDir 'incomplete.json'
            @{
                featureName = 'Incomplete Feature'
                userStories = @(
                    @{ id = 'US-001'; title = 'Story 1'; passes = $true },
                    @{ id = 'US-002'; title = 'Story 2'; passes = $false },
                    @{ id = 'US-003'; title = 'Story 3'; passes = $false }
                )
            } | ConvertTo-Json -Depth 5 | Set-Content $script:incompletePrd
        }

        It 'Returns correct incomplete count in quiet mode' {
            $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Check -Prd '$($script:incompletePrd)' -Quiet" 2>&1
            $result | Should -Contain '2'
        }

        It 'Returns exit code 1 for incomplete PRD' {
            pwsh -NoProfile -Command "& '$($script:parallelScript)' Check -Prd '$($script:incompletePrd)' -Quiet; exit `$LASTEXITCODE"
            $LASTEXITCODE | Should -Be 1
        }

        It 'Shows STATUS: INCOMPLETE in verbose mode' {
            $output = pwsh -NoProfile -Command "& '$($script:parallelScript)' Check -Prd '$($script:incompletePrd)'" 2>&1 | Out-String
            $output | Should -Match 'STATUS: INCOMPLETE'
        }

        It 'Shows remaining story count' {
            $output = pwsh -NoProfile -Command "& '$($script:parallelScript)' Check -Prd '$($script:incompletePrd)'" 2>&1 | Out-String
            $output | Should -Match 'Remaining: 2'
        }

        It 'Lists incomplete stories' {
            $output = pwsh -NoProfile -Command "& '$($script:parallelScript)' Check -Prd '$($script:incompletePrd)'" 2>&1 | Out-String
            $output | Should -Match 'US-002'
            $output | Should -Match 'US-003'
        }
    }

    Context 'Missing PRD file' {
        It 'Returns error for non-existent file' {
            pwsh -NoProfile -Command "& '$($script:parallelScript)' Check -Prd '/nonexistent/prd.json' -Quiet; exit `$LASTEXITCODE"
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'Empty PRD' {
        BeforeAll {
            $script:emptyPrd = Join-Path $script:testDir 'empty.json'
            @{
                featureName = 'Empty Feature'
                userStories = @()
            } | ConvertTo-Json -Depth 5 | Set-Content $script:emptyPrd
        }

        It 'Returns 0 incomplete for empty PRD' {
            $result = pwsh -NoProfile -Command "& '$($script:parallelScript)' Check -Prd '$($script:emptyPrd)' -Quiet" 2>&1
            $result | Should -Contain '0'
        }

        It 'Returns exit code 1 for empty PRD' {
            pwsh -NoProfile -Command "& '$($script:parallelScript)' Check -Prd '$($script:emptyPrd)' -Quiet; exit `$LASTEXITCODE"
            $LASTEXITCODE | Should -Be 1
        }
    }
}

AfterAll {
    Remove-Module RalphUtils -ErrorAction SilentlyContinue
}
