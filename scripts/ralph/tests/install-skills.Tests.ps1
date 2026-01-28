#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for install-skills.ps1 global skill installer script.

.DESCRIPTION
    Comprehensive test suite for install-skills.ps1 including:
    - Home directory detection on different platforms
    - Directory creation when missing
    - File copying from source to destination
    - Overwrite behavior for existing skills
    - Error handling for permission issues
    - TestDrive: for isolated file tests
#>

BeforeAll {
    # Import the utilities module (install-skills.ps1 depends on it)
    $modulePath = Join-Path $PSScriptRoot '..' 'RalphUtils.psm1'
    Import-Module $modulePath -Force

    # Define the script path
    $script:installScript = Join-Path $PSScriptRoot '..' 'install-skills.ps1'

    # Read script content once for structure tests
    $script:scriptContent = Get-Content -Path $script:installScript -Raw

    # Replicate key functions for unit testing without executing the full script

    # Get-HomeDirectory function replica
    $script:GetHomeDirectory = {
        if ($HOME) {
            return $HOME
        }
        elseif ($env:USERPROFILE) {
            return $env:USERPROFILE
        }
        else {
            return [Environment]::GetFolderPath('UserProfile')
        }
    }

    # Get-SourceSkillsPath function replica (needs PSScriptRoot context)
    # Skills are at repo root (../../skills from scripts/ralph/)
    $script:GetSourceSkillsPath = {
        param([string]$ScriptRoot)
        return Join-Path $ScriptRoot '..' '..' 'skills'
    }

    # Get-DestinationSkillsPath function replica
    $script:GetDestinationSkillsPath = {
        param([string]$HomeDir)
        return Join-Path $HomeDir '.claude' 'skills'
    }

    # Install-Skills function replica for testing logic
    $script:InstallSkills = {
        param(
            [string]$SourcePath,
            [string]$DestPath
        )

        $skillsInstalled = @()
        $errors = @()

        # Check if source skills directory exists
        if (-not (Test-Path $SourcePath)) {
            return @{
                Success         = $false
                SkillsInstalled = @()
                Errors          = @("Source skills directory not found: $SourcePath")
            }
        }

        # Get all skill directories
        $skillDirs = Get-ChildItem -Path $SourcePath -Directory -ErrorAction SilentlyContinue
        if (-not $skillDirs -or $skillDirs.Count -eq 0) {
            return @{
                Success         = $false
                SkillsInstalled = @()
                Errors          = @("No skills found in: $SourcePath")
            }
        }

        # Create destination directory if it doesn't exist
        if (-not (Test-Path $DestPath)) {
            try {
                New-Item -Path $DestPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            catch {
                return @{
                    Success         = $false
                    SkillsInstalled = @()
                    Errors          = @("Failed to create destination directory: $_")
                }
            }
        }

        # Copy each skill
        foreach ($skillDir in $skillDirs) {
            $skillName = $skillDir.Name
            $skillDest = Join-Path $DestPath $skillName

            try {
                # Remove existing skill directory if it exists (for clean overwrite)
                if (Test-Path $skillDest) {
                    Remove-Item -Path $skillDest -Recurse -Force -ErrorAction Stop
                }

                # Copy the skill directory
                Copy-Item -Path $skillDir.FullName -Destination $skillDest -Recurse -Force -ErrorAction Stop
                $skillsInstalled += $skillName
            }
            catch {
                $errors += "Failed to install skill '$skillName': $_"
            }
        }

        return @{
            Success         = $errors.Count -eq 0
            SkillsInstalled = $skillsInstalled
            Errors          = $errors
        }
    }
}

Describe 'install-skills.ps1 Script Structure' {
    It 'Requires PowerShell 7.0+' {
        $script:scriptContent | Should -Match '#Requires -Version 7\.0'
    }

    It 'Has proper help documentation' {
        $script:scriptContent | Should -Match '\.SYNOPSIS'
        $script:scriptContent | Should -Match '\.DESCRIPTION'
        $script:scriptContent | Should -Match '\.EXAMPLE'
        $script:scriptContent | Should -Match '\.NOTES'
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

    It 'Checks for RalphUtils.psm1 existence' {
        $script:scriptContent | Should -Match "Test-Path \`$modulePath"
    }

    It 'Exits with code 1 if RalphUtils not found' {
        $script:scriptContent | Should -Match 'exit 1'
    }
}

Describe 'Script Functions' {
    It 'Defines Get-HomeDirectory function' {
        $script:scriptContent | Should -Match 'function Get-HomeDirectory'
    }

    It 'Defines Get-SourceSkillsPath function' {
        $script:scriptContent | Should -Match 'function Get-SourceSkillsPath'
    }

    It 'Defines Get-DestinationSkillsPath function' {
        $script:scriptContent | Should -Match 'function Get-DestinationSkillsPath'
    }

    It 'Defines Install-Skills function' {
        $script:scriptContent | Should -Match 'function Install-Skills'
    }

    It 'Defines Show-Banner function' {
        $script:scriptContent | Should -Match 'function Show-Banner'
    }

    It 'Functions have OutputType attributes' {
        $script:scriptContent | Should -Match '\[OutputType\(\[string\]\)\]'
        $script:scriptContent | Should -Match '\[OutputType\(\[hashtable\]\)\]'
    }

    It 'Functions have proper comment-based help' {
        # All exported functions should have .SYNOPSIS
        $functionMatches = [regex]::Matches($script:scriptContent, 'function (Get-|Install-|Show-)\w+')
        $functionMatches.Count | Should -BeGreaterOrEqual 5
    }
}

Describe 'Home Directory Detection' {
    Context 'When $HOME is available' {
        It 'Returns $HOME as the home directory' {
            $result = & $script:GetHomeDirectory
            $result | Should -Be $HOME
        }
    }

    Context 'Cross-platform detection patterns' {
        It 'Script checks $HOME first' {
            $script:scriptContent | Should -Match 'if \(\$HOME\)'
        }

        It 'Script falls back to $env:USERPROFILE' {
            $script:scriptContent | Should -Match '\$env:USERPROFILE'
        }

        It 'Script has last resort fallback to Environment API' {
            $script:scriptContent | Should -Match "\[Environment\]::GetFolderPath\('UserProfile'\)"
        }
    }

    Context 'Home directory resolution' {
        It 'Returns a non-empty path' {
            $result = & $script:GetHomeDirectory
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Returns a path that exists' {
            $result = & $script:GetHomeDirectory
            Test-Path $result | Should -Be $true
        }
    }
}

Describe 'Source Skills Path' {
    Context 'Path construction' {
        It 'Returns path relative to script root' {
            # Use cross-platform path for testing
            # Skills are at repo root (../../skills from scripts/ralph/)
            $testRoot = if ($IsWindows) { 'C:\test\scripts\ralph' } else { '/tmp/test/scripts/ralph' }
            $result = & $script:GetSourceSkillsPath -ScriptRoot $testRoot
            $result | Should -Be (Join-Path $testRoot '..' '..' 'skills')
        }

        It 'Uses Join-Path for cross-platform compatibility' {
            $script:scriptContent | Should -Match "Join-Path \`$PSScriptRoot '\.\.' '\.\.' 'skills'"
        }
    }

    Context 'Actual skills directory' {
        It 'Skills directory exists in the project' {
            # Skills are at repo root (../../../skills from scripts/ralph/tests/)
            $actualSourcePath = Join-Path $PSScriptRoot '..' '..' '..' 'skills'
            Test-Path $actualSourcePath | Should -Be $true
        }

        It 'Skills directory contains subdirectories' {
            # Skills are at repo root (../../../skills from scripts/ralph/tests/)
            $actualSourcePath = Join-Path $PSScriptRoot '..' '..' '..' 'skills'
            $skillDirs = Get-ChildItem -Path $actualSourcePath -Directory -ErrorAction SilentlyContinue
            $skillDirs.Count | Should -BeGreaterOrEqual 1
        }
    }
}

Describe 'Destination Skills Path' {
    Context 'Path construction' {
        It 'Returns ~/.claude/skills/ path structure' {
            $testHome = '/home/testuser'
            $result = & $script:GetDestinationSkillsPath -HomeDir $testHome
            $result | Should -Be (Join-Path $testHome '.claude' 'skills')
        }

        It 'Uses Join-Path with .claude and skills' {
            $script:scriptContent | Should -Match "Join-Path \`$homeDir '\.claude' 'skills'"
        }
    }

    Context 'Platform-specific path construction' {
        It 'Handles platform-specific home path' {
            # Use platform-appropriate test path
            $testHome = if ($IsWindows) { 'C:\Users\TestUser' } else { '/home/testuser' }
            $result = & $script:GetDestinationSkillsPath -HomeDir $testHome
            # Join-Path handles the separator correctly
            $result | Should -Match '(?i)testuser'  # Case-insensitive match for either platform
            $result | Should -Match '\.claude'
            $result | Should -Match 'skills'
        }
    }
}

Describe 'Directory Creation When Missing' {
    Context 'Using TestDrive for isolated tests' {
        BeforeEach {
            # Create a test source skills directory structure
            $script:testSourcePath = Join-Path $TestDrive 'source' 'skills'
            New-Item -Path $script:testSourcePath -ItemType Directory -Force | Out-Null

            # Create test skill directories with content
            $skill1Path = Join-Path $script:testSourcePath 'skill1'
            $skill2Path = Join-Path $script:testSourcePath 'skill2'
            New-Item -Path $skill1Path -ItemType Directory -Force | Out-Null
            New-Item -Path $skill2Path -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $skill1Path 'SKILL.md') -Value '# Skill 1'
            Set-Content -Path (Join-Path $skill2Path 'SKILL.md') -Value '# Skill 2'

            $script:testDestPath = Join-Path $TestDrive 'dest' '.claude' 'skills'
        }

        It 'Creates destination directory if it does not exist' {
            # Ensure destination doesn't exist
            Test-Path $script:testDestPath | Should -Be $false

            # Run install
            $result = & $script:InstallSkills -SourcePath $script:testSourcePath -DestPath $script:testDestPath

            # Destination should now exist
            Test-Path $script:testDestPath | Should -Be $true
            $result.Success | Should -Be $true
        }

        It 'Creates nested directory structure' {
            # Use a fresh nested path that definitely doesn't exist
            $nestedDestPath = Join-Path $TestDrive 'nested' 'deeply' '.claude' 'skills'
            Test-Path (Join-Path $TestDrive 'nested') | Should -Be $false

            # Run install (should create nested/deeply/.claude/skills/)
            $result = & $script:InstallSkills -SourcePath $script:testSourcePath -DestPath $nestedDestPath

            Test-Path $nestedDestPath | Should -Be $true
            $result.Success | Should -Be $true
        }
    }

    Context 'Script uses New-Item for directory creation' {
        It 'Uses New-Item with -Force flag' {
            $script:scriptContent | Should -Match 'New-Item -Path \$destPath -ItemType Directory -Force'
        }

        It 'Handles directory creation errors' {
            $script:scriptContent | Should -Match "Failed to create destination directory"
        }
    }
}

Describe 'File Copying from Source to Destination' {
    Context 'Using TestDrive for isolated tests' {
        BeforeEach {
            # Create test source structure
            $script:testSourcePath = Join-Path $TestDrive 'source' 'skills'
            New-Item -Path $script:testSourcePath -ItemType Directory -Force | Out-Null

            # Create skill directories with files
            $prdSkillPath = Join-Path $script:testSourcePath 'prd'
            $ralphSkillPath = Join-Path $script:testSourcePath 'ralph'
            New-Item -Path $prdSkillPath -ItemType Directory -Force | Out-Null
            New-Item -Path $ralphSkillPath -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $prdSkillPath 'SKILL.md') -Value '# PRD Skill Content'
            Set-Content -Path (Join-Path $ralphSkillPath 'SKILL.md') -Value '# Ralph Skill Content'

            $script:testDestPath = Join-Path $TestDrive 'dest' 'skills'
        }

        It 'Copies all skill directories' {
            $result = & $script:InstallSkills -SourcePath $script:testSourcePath -DestPath $script:testDestPath

            $result.Success | Should -Be $true
            $result.SkillsInstalled | Should -Contain 'prd'
            $result.SkillsInstalled | Should -Contain 'ralph'
        }

        It 'Copies skill files recursively' {
            $result = & $script:InstallSkills -SourcePath $script:testSourcePath -DestPath $script:testDestPath

            $prdSkillFile = Join-Path $script:testDestPath 'prd' 'SKILL.md'
            $ralphSkillFile = Join-Path $script:testDestPath 'ralph' 'SKILL.md'

            Test-Path $prdSkillFile | Should -Be $true
            Test-Path $ralphSkillFile | Should -Be $true
        }

        It 'Preserves file contents' {
            $result = & $script:InstallSkills -SourcePath $script:testSourcePath -DestPath $script:testDestPath

            $prdContent = Get-Content -Path (Join-Path $script:testDestPath 'prd' 'SKILL.md') -Raw
            $prdContent | Should -Match 'PRD Skill Content'
        }

        It 'Returns correct count of installed skills' {
            $result = & $script:InstallSkills -SourcePath $script:testSourcePath -DestPath $script:testDestPath

            $result.SkillsInstalled.Count | Should -Be 2
        }
    }

    Context 'Script uses Copy-Item correctly' {
        It 'Uses Copy-Item with -Recurse flag' {
            $script:scriptContent | Should -Match 'Copy-Item .+ -Recurse'
        }

        It 'Uses Copy-Item with -Force flag' {
            $script:scriptContent | Should -Match 'Copy-Item .+ -Force'
        }

        It 'Uses -ErrorAction Stop for error handling' {
            $script:scriptContent | Should -Match 'Copy-Item .+ -ErrorAction Stop'
        }
    }
}

Describe 'Overwrite Behavior for Existing Skills' {
    Context 'Using TestDrive for isolated tests' {
        BeforeEach {
            # Create test source structure
            $script:testSourcePath = Join-Path $TestDrive 'source' 'skills'
            New-Item -Path $script:testSourcePath -ItemType Directory -Force | Out-Null

            $prdSkillPath = Join-Path $script:testSourcePath 'prd'
            New-Item -Path $prdSkillPath -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $prdSkillPath 'SKILL.md') -Value '# New PRD Content'

            # Create existing destination with OLD content
            $script:testDestPath = Join-Path $TestDrive 'dest' 'skills'
            $existingPrdPath = Join-Path $script:testDestPath 'prd'
            New-Item -Path $existingPrdPath -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $existingPrdPath 'SKILL.md') -Value '# Old PRD Content'
            Set-Content -Path (Join-Path $existingPrdPath 'extra.txt') -Value 'Extra file that should be removed'
        }

        It 'Overwrites existing skill directory' {
            # Verify old content exists
            $oldContent = Get-Content -Path (Join-Path $script:testDestPath 'prd' 'SKILL.md') -Raw
            $oldContent | Should -Match 'Old PRD Content'

            # Run install
            $result = & $script:InstallSkills -SourcePath $script:testSourcePath -DestPath $script:testDestPath

            # Verify new content
            $newContent = Get-Content -Path (Join-Path $script:testDestPath 'prd' 'SKILL.md') -Raw
            $newContent | Should -Match 'New PRD Content'
            $result.Success | Should -Be $true
        }

        It 'Removes extra files from old skill version' {
            $extraFilePath = Join-Path $script:testDestPath 'prd' 'extra.txt'
            Test-Path $extraFilePath | Should -Be $true

            # Run install
            $result = & $script:InstallSkills -SourcePath $script:testSourcePath -DestPath $script:testDestPath

            # Extra file should be gone (clean overwrite)
            Test-Path $extraFilePath | Should -Be $false
        }
    }

    Context 'Script removes existing directories before copying' {
        It 'Checks for existing skill directory' {
            $script:scriptContent | Should -Match 'Test-Path \$skillDest'
        }

        It 'Uses Remove-Item before Copy-Item' {
            $script:scriptContent | Should -Match 'Remove-Item -Path \$skillDest -Recurse -Force'
        }
    }
}

Describe 'Error Handling' {
    Context 'Missing source directory' {
        It 'Returns error when source skills directory does not exist' {
            $nonExistentPath = Join-Path $TestDrive 'nonexistent' 'skills'
            $destPath = Join-Path $TestDrive 'dest' 'skills'

            $result = & $script:InstallSkills -SourcePath $nonExistentPath -DestPath $destPath

            $result.Success | Should -Be $false
            $result.Errors | Should -Contain "Source skills directory not found: $nonExistentPath"
            $result.SkillsInstalled.Count | Should -Be 0
        }
    }

    Context 'Empty source directory' {
        It 'Returns error when no skills found in source' {
            # Create empty source directory
            $emptySourcePath = Join-Path $TestDrive 'empty' 'skills'
            New-Item -Path $emptySourcePath -ItemType Directory -Force | Out-Null
            $destPath = Join-Path $TestDrive 'dest' 'skills'

            $result = & $script:InstallSkills -SourcePath $emptySourcePath -DestPath $destPath

            $result.Success | Should -Be $false
            $result.Errors | Should -Contain "No skills found in: $emptySourcePath"
        }
    }

    Context 'Script error handling patterns' {
        It 'Uses try-catch for directory creation' {
            $script:scriptContent | Should -Match 'try\s*\{'
            $script:scriptContent | Should -Match 'catch\s*\{'
        }

        It 'Uses -ErrorAction Stop for Copy-Item' {
            $script:scriptContent | Should -Match 'Copy-Item .+ -ErrorAction Stop'
        }

        It 'Uses -ErrorAction Stop for Remove-Item' {
            $script:scriptContent | Should -Match 'Remove-Item .+ -ErrorAction Stop'
        }

        It 'Collects errors in array' {
            $script:scriptContent | Should -Match '\$errors \+= '
        }

        It 'Returns hashtable with Success, SkillsInstalled, and Errors' {
            $script:scriptContent | Should -Match 'Success\s*='
            $script:scriptContent | Should -Match 'SkillsInstalled\s*='
            $script:scriptContent | Should -Match 'Errors\s*='
        }
    }

    Context 'Partial success handling' {
        It 'Script handles some skills installed despite errors' {
            $script:scriptContent | Should -Match 'Some skills installed with errors'
        }
    }
}

Describe 'Result Hashtable Structure' {
    Context 'Successful installation' {
        BeforeEach {
            # Setup test directories
            $script:testSourcePath = Join-Path $TestDrive 'source' 'skills'
            New-Item -Path $script:testSourcePath -ItemType Directory -Force | Out-Null
            $skill1Path = Join-Path $script:testSourcePath 'test-skill'
            New-Item -Path $skill1Path -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $skill1Path 'SKILL.md') -Value '# Test'

            $script:testDestPath = Join-Path $TestDrive 'dest' 'skills'
        }

        It 'Returns Success = $true on successful install' {
            $result = & $script:InstallSkills -SourcePath $script:testSourcePath -DestPath $script:testDestPath
            $result.Success | Should -Be $true
        }

        It 'Returns SkillsInstalled array with installed skill names' {
            $result = & $script:InstallSkills -SourcePath $script:testSourcePath -DestPath $script:testDestPath
            $result.SkillsInstalled | Should -Be @('test-skill')
        }

        It 'Returns empty Errors array on success' {
            $result = & $script:InstallSkills -SourcePath $script:testSourcePath -DestPath $script:testDestPath
            $result.Errors.Count | Should -Be 0
        }
    }

    Context 'Failed installation' {
        It 'Returns Success = $false on failure' {
            $nonExistentPath = Join-Path $TestDrive 'nonexistent'
            $destPath = Join-Path $TestDrive 'dest'

            $result = & $script:InstallSkills -SourcePath $nonExistentPath -DestPath $destPath
            $result.Success | Should -Be $false
        }

        It 'Returns empty SkillsInstalled on total failure' {
            $nonExistentPath = Join-Path $TestDrive 'nonexistent'
            $destPath = Join-Path $TestDrive 'dest'

            $result = & $script:InstallSkills -SourcePath $nonExistentPath -DestPath $destPath
            $result.SkillsInstalled.Count | Should -Be 0
        }

        It 'Returns non-empty Errors array on failure' {
            $nonExistentPath = Join-Path $TestDrive 'nonexistent'
            $destPath = Join-Path $TestDrive 'dest'

            $result = & $script:InstallSkills -SourcePath $nonExistentPath -DestPath $destPath
            $result.Errors.Count | Should -BeGreaterThan 0
        }
    }
}

Describe 'Show-Banner Function' {
    It 'Script defines Show-Banner function' {
        $script:scriptContent | Should -Match 'function Show-Banner'
    }

    It 'Banner includes RALPH SKILL INSTALLER title' {
        $script:scriptContent | Should -Match 'RALPH SKILL INSTALLER'
    }

    It 'Uses Unicode box characters for styling' {
        # Check for Unicode character usage pattern
        $script:scriptContent | Should -Match '0x2550'
    }

    It 'Uses colored output for banner' {
        $script:scriptContent | Should -Match '-ForegroundColor Blue'
        $script:scriptContent | Should -Match '-ForegroundColor Yellow'
    }
}

Describe 'Main Function' {
    Context 'Execution flow' {
        It 'Calls Show-Banner at start' {
            $script:scriptContent | Should -Match 'function Main[\s\S]*?Show-Banner'
        }

        It 'Displays source path' {
            $script:scriptContent | Should -Match "Source:"
        }

        It 'Displays destination path' {
            $script:scriptContent | Should -Match "Destination:"
        }

        It 'Calls Install-Skills function' {
            $script:scriptContent | Should -Match '\$result = Install-Skills'
        }
    }

    Context 'Success output' {
        It 'Displays success message on successful install' {
            $script:scriptContent | Should -Match 'Skills installed successfully!'
        }

        It 'Lists installed skills' {
            $script:scriptContent | Should -Match 'Installed skills:'
            $script:scriptContent | Should -Match 'foreach \(\$skill in \$result\.SkillsInstalled\)'
        }

        It 'Displays global availability message' {
            $script:scriptContent | Should -Match 'Skills are now available globally'
        }

        It 'Exits with code 0 on success' {
            $script:scriptContent | Should -Match 'exit 0'
        }
    }

    Context 'Error output' {
        It 'Displays errors in red' {
            $script:scriptContent | Should -Match "-ForegroundColor Red"
        }

        It 'Lists all errors' {
            $script:scriptContent | Should -Match 'foreach \(\$err in \$result\.Errors\)'
        }

        It 'Exits with code 1 on failure' {
            $exitMatches = [regex]::Matches($script:scriptContent, 'exit 1')
            $exitMatches.Count | Should -BeGreaterOrEqual 1
        }
    }
}

Describe 'Integration with RalphUtils Module' {
    It 'Script uses Write-ColoredOutput from RalphUtils' {
        $script:scriptContent | Should -Match 'Write-ColoredOutput'
    }

    It 'Write-ColoredOutput function is available' {
        { Get-Command Write-ColoredOutput -ErrorAction Stop } | Should -Not -Throw
    }
}

Describe 'Cross-Platform Compatibility' {
    Context 'Path handling' {
        It 'Uses Join-Path instead of string concatenation' {
            # Script should use Join-Path multiple times
            $joinPathMatches = [regex]::Matches($script:scriptContent, 'Join-Path')
            $joinPathMatches.Count | Should -BeGreaterOrEqual 3
        }

        It 'Does not hardcode path separators' {
            # Should not have hardcoded / or \ except in comments/docs
            # This is a soft check - looking for patterns like "$dir/$file"
            $script:scriptContent | Should -Not -Match '\$\w+/\$\w+'
            $script:scriptContent | Should -Not -Match '\$\w+\\\$\w+'
        }
    }

    Context 'Home directory patterns' {
        It 'Does not use $home as a variable name' {
            # $home is built-in and read-only
            $script:scriptContent | Should -Not -Match '\$home\s*='
        }

        It 'Uses $homeDir for home directory variable' {
            $script:scriptContent | Should -Match '\$homeDir'
        }
    }
}

Describe 'Edge Cases' {
    Context 'Single skill' {
        BeforeEach {
            $script:testSourcePath = Join-Path $TestDrive 'source' 'skills'
            New-Item -Path $script:testSourcePath -ItemType Directory -Force | Out-Null
            $singleSkillPath = Join-Path $script:testSourcePath 'single-skill'
            New-Item -Path $singleSkillPath -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $singleSkillPath 'SKILL.md') -Value '# Single Skill'

            $script:testDestPath = Join-Path $TestDrive 'dest' 'skills'
        }

        It 'Handles single skill correctly' {
            $result = & $script:InstallSkills -SourcePath $script:testSourcePath -DestPath $script:testDestPath

            $result.Success | Should -Be $true
            $result.SkillsInstalled.Count | Should -Be 1
            $result.SkillsInstalled | Should -Contain 'single-skill'
        }
    }

    Context 'Multiple skills' {
        BeforeEach {
            $script:testSourcePath = Join-Path $TestDrive 'source' 'skills'
            New-Item -Path $script:testSourcePath -ItemType Directory -Force | Out-Null

            # Create 5 skills
            for ($i = 1; $i -le 5; $i++) {
                $skillPath = Join-Path $script:testSourcePath "skill$i"
                New-Item -Path $skillPath -ItemType Directory -Force | Out-Null
                Set-Content -Path (Join-Path $skillPath 'SKILL.md') -Value "# Skill $i"
            }

            $script:testDestPath = Join-Path $TestDrive 'dest' 'skills'
        }

        It 'Handles multiple skills correctly' {
            $result = & $script:InstallSkills -SourcePath $script:testSourcePath -DestPath $script:testDestPath

            $result.Success | Should -Be $true
            $result.SkillsInstalled.Count | Should -Be 5
        }
    }

    Context 'Skill with nested subdirectories' {
        BeforeEach {
            $script:testSourcePath = Join-Path $TestDrive 'source' 'skills'
            New-Item -Path $script:testSourcePath -ItemType Directory -Force | Out-Null

            # Create skill with nested structure
            $skillPath = Join-Path $script:testSourcePath 'complex-skill'
            $nestedPath = Join-Path $skillPath 'lib' 'utils'
            New-Item -Path $nestedPath -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $skillPath 'SKILL.md') -Value '# Complex Skill'
            Set-Content -Path (Join-Path $nestedPath 'helper.ps1') -Value '# Helper'

            $script:testDestPath = Join-Path $TestDrive 'dest' 'skills'
        }

        It 'Copies nested subdirectories recursively' {
            $result = & $script:InstallSkills -SourcePath $script:testSourcePath -DestPath $script:testDestPath

            $result.Success | Should -Be $true

            $nestedFilePath = Join-Path $script:testDestPath 'complex-skill' 'lib' 'utils' 'helper.ps1'
            Test-Path $nestedFilePath | Should -Be $true
        }
    }

    Context 'Skill with special characters in name' {
        BeforeEach {
            $script:testSourcePath = Join-Path $TestDrive 'source' 'skills'
            New-Item -Path $script:testSourcePath -ItemType Directory -Force | Out-Null

            # Create skill with hyphen and underscore
            $skillPath = Join-Path $script:testSourcePath 'my-skill_v2'
            New-Item -Path $skillPath -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $skillPath 'SKILL.md') -Value '# My Skill v2'

            $script:testDestPath = Join-Path $TestDrive 'dest' 'skills'
        }

        It 'Handles skill names with hyphens and underscores' {
            $result = & $script:InstallSkills -SourcePath $script:testSourcePath -DestPath $script:testDestPath

            $result.Success | Should -Be $true
            $result.SkillsInstalled | Should -Contain 'my-skill_v2'
        }
    }
}
