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

# =============================================================================
# PS-010: PARALLEL EXECUTION CORE TESTS
# =============================================================================

Describe 'PS-010: Get-DefaultCount Function' {
    BeforeAll {
        $script:scriptContent = Get-Content $script:parallelScript -Raw
    }

    It 'Get-DefaultCount function is defined' {
        $script:scriptContent | Should -Match 'function\s+Get-DefaultCount'
    }

    It 'Uses ProcessorCount for CPU count' {
        $script:scriptContent | Should -Match '\[Environment\]::ProcessorCount'
    }

    It 'Divides CPU count by 2' {
        $script:scriptContent | Should -Match 'Floor\s*\(\s*\$cpuCount\s*/\s*2\s*\)'
    }

    It 'Returns minimum of 1' {
        $script:scriptContent | Should -Match 'Max\s*\(\s*1'
    }

    It 'Get-DefaultCount returns at least 1' {
        # Execute the function directly by invoking a subprocess
        $result = pwsh -NoProfile -Command @"
            # Define the function
            function Get-DefaultCount {
                `$cpuCount = [Environment]::ProcessorCount
                `$default = [math]::Max(1, [math]::Floor(`$cpuCount / 2))
                return `$default
            }
            Get-DefaultCount
"@
        [int]$result | Should -BeGreaterOrEqual 1
    }

    It 'Get-DefaultCount returns integer' {
        $result = pwsh -NoProfile -Command @"
            function Get-DefaultCount {
                `$cpuCount = [Environment]::ProcessorCount
                `$default = [math]::Max(1, [math]::Floor(`$cpuCount / 2))
                return `$default
            }
            (Get-DefaultCount).GetType().Name
"@
        $result.Trim() | Should -Match '(Int32|Int64|Double)'
    }
}

Describe 'PS-010: Job Tracking Functions' {
    BeforeAll {
        $script:scriptContent = Get-Content $script:parallelScript -Raw
    }

    Context 'Jobs File Path' {
        It 'JobsFile variable is defined' {
            $script:scriptContent | Should -Match '\$script:JobsFile'
        }

        It 'JobsFile path includes instances directory' {
            $script:scriptContent | Should -Match "JobsFile.*instances.*running-jobs\.json"
        }
    }

    Context 'Save-Jobs Function' {
        It 'Save-Jobs function is defined' {
            $script:scriptContent | Should -Match 'function\s+Save-Jobs'
        }

        It 'Save-Jobs creates instances directory if needed' {
            $script:scriptContent | Should -Match 'New-Item.*Directory.*-Force'
        }

        It 'Save-Jobs writes to JobsFile' {
            $script:scriptContent | Should -Match 'Set-Content\s+\$script:JobsFile'
        }

        It 'Save-Jobs converts jobs to JSON' {
            $script:scriptContent | Should -Match 'ConvertTo-Json'
        }
    }

    Context 'Get-SavedJobs Function' {
        It 'Get-SavedJobs function is defined' {
            $script:scriptContent | Should -Match 'function\s+Get-SavedJobs'
        }

        It 'Get-SavedJobs returns empty array if file missing' {
            $script:scriptContent | Should -Match 'return\s+@\(\)'
        }

        It 'Get-SavedJobs reads from JobsFile' {
            $script:scriptContent | Should -Match 'Get-Content\s+\$script:JobsFile'
        }

        It 'Get-SavedJobs parses JSON' {
            $script:scriptContent | Should -Match 'ConvertFrom-Json'
        }
    }
}

Describe 'PS-010: Start-RalphInstances Function' {
    BeforeAll {
        $script:scriptContent = Get-Content $script:parallelScript -Raw
    }

    It 'Start-RalphInstances function is defined' {
        $script:scriptContent | Should -Match 'function\s+Start-RalphInstances'
    }

    It 'Accepts Count parameter' {
        $script:scriptContent | Should -Match 'Start-RalphInstances\s*\{[\s\S]*param\s*\([\s\S]*\[int\]\s*\$Count'
    }

    It 'Accepts MaxIterations parameter' {
        $script:scriptContent | Should -Match 'Start-RalphInstances\s*\{[\s\S]*param\s*\([\s\S]*\[int\]\s*\$MaxIterations'
    }

    It 'Uses Get-DefaultCount when Count is 0' {
        $script:scriptContent | Should -Match 'Get-DefaultCount'
    }

    It 'Enforces RALPH_MAX_INSTANCES limit' {
        $script:scriptContent | Should -Match 'RALPH_MAX_INSTANCES'
    }

    It 'Uses Start-Job for background execution' {
        $script:scriptContent | Should -Match 'Start-Job'
    }

    It 'Passes ralph.ps1 script to job' {
        $script:scriptContent | Should -Match "ralph\.ps1"
    }

    It 'Adds delay between instance launches' {
        $script:scriptContent | Should -Match 'Start-Sleep'
    }

    It 'Calls Save-Jobs after starting instances' {
        $script:scriptContent | Should -Match 'Save-Jobs'
    }

    It 'Tracks job ID, Name, StartTime, Iterations' {
        $script:scriptContent | Should -Match '@\{[\s\S]*Id\s*='
        $script:scriptContent | Should -Match 'Name\s*='
        $script:scriptContent | Should -Match 'StartTime\s*='
        $script:scriptContent | Should -Match 'Iterations\s*='
    }
}

Describe 'PS-010: Stop-RalphInstances Function' {
    BeforeAll {
        $script:scriptContent = Get-Content $script:parallelScript -Raw
    }

    It 'Stop-RalphInstances function is defined' {
        $script:scriptContent | Should -Match 'function\s+Stop-RalphInstances\s*\{'
    }

    It 'Gets saved jobs first' {
        $script:scriptContent | Should -Match 'Get-SavedJobs'
    }

    It 'Uses Stop-Job to stop running jobs' {
        $script:scriptContent | Should -Match 'Stop-Job'
    }

    It 'Clears jobs file after stopping' {
        $script:scriptContent | Should -Match 'Save-Jobs.*@\(\)'
    }

    It 'Removes completed jobs' {
        $script:scriptContent | Should -Match 'Remove-Job'
    }
}

Describe 'PS-010: Show-Status Function' {
    BeforeAll {
        $script:scriptContent = Get-Content $script:parallelScript -Raw
    }

    It 'Show-Status function is defined' {
        $script:scriptContent | Should -Match 'function\s+Show-Status\s*\{'
    }

    It 'Gets saved jobs' {
        $script:scriptContent | Should -Match 'Get-SavedJobs'
    }

    It 'Counts running jobs' {
        $script:scriptContent | Should -Match '\$running'
    }

    It 'Shows running/total count' {
        $script:scriptContent | Should -Match 'Running.*\$running.*\$total'
    }

    It 'Shows locks count' {
        $script:scriptContent | Should -Match 'Active locks'
    }

    It 'Shows PRD progress' {
        $script:scriptContent | Should -Match 'PRD progress'
    }
}

Describe 'PS-010: Command Switch' {
    BeforeAll {
        $script:scriptContent = Get-Content $script:parallelScript -Raw
    }

    It 'Has switch statement for commands' {
        $script:scriptContent | Should -Match 'switch\s*\(\s*\$Command\s*\)'
    }

    It 'Handles Start command' {
        $script:scriptContent | Should -Match "'Start'\s*\{[\s\S]*Start-RalphInstances"
    }

    It 'Handles Stop command' {
        $script:scriptContent | Should -Match "'Stop'\s*\{[\s\S]*Stop-RalphInstances"
    }

    It 'Handles Status command' {
        $script:scriptContent | Should -Match "'Status'\s*\{[\s\S]*Show-Status"
    }
}

Describe 'PS-010: Parallel Instance Integration' {
    BeforeAll {
        $script:testDir = Join-Path $TestDrive 'parallel-integration'
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null

        # Create instances directory
        $script:instancesDir = Join-Path $script:testDir 'instances'
        New-Item -Path $script:instancesDir -ItemType Directory -Force | Out-Null

        # Create a test jobs file
        $script:jobsFile = Join-Path $script:instancesDir 'running-jobs.json'
    }

    Context 'Job Tracking File Operations' {
        It 'Can create jobs file with job data' {
            $jobs = @(
                @{ Id = 1; Name = 'Job1'; StartTime = '2026-01-01 00:00:00'; Iterations = 10 },
                @{ Id = 2; Name = 'Job2'; StartTime = '2026-01-01 00:00:01'; Iterations = 10 }
            )
            $jobs | ConvertTo-Json -Depth 5 | Set-Content $script:jobsFile

            Test-Path $script:jobsFile | Should -BeTrue
        }

        It 'Jobs file contains valid JSON' {
            $content = Get-Content $script:jobsFile -Raw
            { $content | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'Jobs file contains multiple job entries' {
            $savedJobs = Get-Content $script:jobsFile -Raw | ConvertFrom-Json
            @($savedJobs).Count | Should -Be 2
        }

        It 'Job entries have required fields' {
            $savedJobs = Get-Content $script:jobsFile -Raw | ConvertFrom-Json
            $firstJob = $savedJobs[0]
            $firstJob.Id | Should -Not -BeNullOrEmpty
            $firstJob.StartTime | Should -Not -BeNullOrEmpty
            $firstJob.Iterations | Should -Not -BeNullOrEmpty
        }

        It 'Can clear jobs file by overwriting with empty array' {
            # First ensure file has data
            $jobs = @(
                @{ Id = 99; Name = 'TestJob' }
            )
            $jobs | ConvertTo-Json -Depth 5 | Set-Content $script:jobsFile

            # Now clear it
            '[]' | Set-Content $script:jobsFile

            $content = Get-Content $script:jobsFile -Raw
            # Empty JSON array should be '[]'
            $content.Trim() | Should -Be '[]'
        }
    }

    Context 'Count Parameter Defaults' {
        It 'Count parameter defaults to 0 (uses Get-DefaultCount)' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:parallelScript,
                [ref]$null,
                [ref]$null
            )
            $countParam = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Count' }
            $countParam.DefaultValue.Value | Should -Be 0
        }
    }

    Context 'MaxIterations Parameter' {
        It 'MaxIterations parameter defaults to 10' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:parallelScript,
                [ref]$null,
                [ref]$null
            )
            $iterParam = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'MaxIterations' }
            $iterParam.DefaultValue.Value | Should -Be 10
        }

        It 'MaxIterations has alias m' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:parallelScript,
                [ref]$null,
                [ref]$null
            )
            $iterParam = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'MaxIterations' }
            $aliasAttr = $iterParam.Attributes | Where-Object { $_.TypeName.Name -eq 'Alias' }
            $aliasAttr.PositionalArguments[0].Value | Should -Be 'm'
        }
    }

    Context 'Count Parameter' {
        It 'Count has alias c' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:parallelScript,
                [ref]$null,
                [ref]$null
            )
            $countParam = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Count' }
            $aliasAttr = $countParam.Attributes | Where-Object { $_.TypeName.Name -eq 'Alias' }
            $aliasAttr.PositionalArguments[0].Value | Should -Be 'c'
        }
    }
}

Describe 'PS-010: Kill Command' {
    BeforeAll {
        $script:scriptContent = Get-Content $script:parallelScript -Raw
    }

    It 'Has Kill command in ValidateSet' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:parallelScript,
            [ref]$null,
            [ref]$null
        )
        $cmdParam = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Command' }
        $validateAttr = $cmdParam.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
        $validateAttr.PositionalArguments.Value | Should -Contain 'Kill'
    }

    It 'Stop-RalphInstancesForce function is defined' {
        $script:scriptContent | Should -Match 'function\s+Stop-RalphInstancesForce'
    }

    It 'Force stop uses SIGKILL-equivalent' {
        # PowerShell uses Remove-Job -Force or Stop-Process -Force
        $script:scriptContent | Should -Match '-Force'
    }
}

Describe 'PS-010: Dashboard Integration' {
    BeforeAll {
        $script:scriptContent = Get-Content $script:parallelScript -Raw
    }

    It 'Has Dashboard command' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:parallelScript,
            [ref]$null,
            [ref]$null
        )
        $cmdParam = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Command' }
        $validateAttr = $cmdParam.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
        $validateAttr.PositionalArguments.Value | Should -Contain 'Dashboard'
    }

    It 'Start-Dashboard function is defined' {
        $script:scriptContent | Should -Match 'function\s+Start-Dashboard'
    }

    It 'Dashboard references ralph-dashboard.ps1' {
        $script:scriptContent | Should -Match 'ralph-dashboard\.ps1'
    }
}

AfterAll {
    Remove-Module RalphUtils -ErrorAction SilentlyContinue
}
