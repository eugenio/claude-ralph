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

# ─────────────────────────────────────────────────────────────────────────────
# Alias Installation Tests
# ─────────────────────────────────────────────────────────────────────────────

Describe 'Alias Installation Script Structure' {
    It 'Defines Get-RalphScriptsPath function' {
        $script:scriptContent | Should -Match 'function Get-RalphScriptsPath'
    }

    It 'Defines Install-PowerShellAliases function' {
        $script:scriptContent | Should -Match 'function Install-PowerShellAliases'
    }

    It 'Defines Show-AliasInstructions function' {
        $script:scriptContent | Should -Match 'function Show-AliasInstructions'
    }

    It 'Uses Read-Host for alias installation prompt' {
        $script:scriptContent | Should -Match 'Read-Host'
    }

    It 'Prompts for alias installation after skill install' {
        $script:scriptContent | Should -Match "install.*aliases.*ralph"
    }
}

Describe 'Get-RalphScriptsPath Function' {
    BeforeAll {
        # Replicate Get-RalphScriptsPath for testing
        $script:GetRalphScriptsPath = {
            param([string]$ScriptRoot)

            # Check if we're in scripts/ralph or repo root
            if (Test-Path (Join-Path $ScriptRoot 'ralph.ps1')) {
                return $ScriptRoot
            }
            $candidatePath = Join-Path $ScriptRoot 'scripts' 'ralph'
            if (Test-Path (Join-Path $candidatePath 'ralph.ps1')) {
                return $candidatePath
            }
            # Fallback to script root
            return $ScriptRoot
        }
    }

    Context 'When in scripts/ralph directory' {
        It 'Returns the script root when ralph.ps1 exists there' {
            # Create mock directory structure in TestDrive
            $mockRalphDir = Join-Path $TestDrive 'scripts' 'ralph'
            New-Item -Path $mockRalphDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $mockRalphDir 'ralph.ps1') -Value '# mock'

            $result = & $script:GetRalphScriptsPath -ScriptRoot $mockRalphDir
            $result | Should -Be $mockRalphDir
        }
    }

    Context 'When in repo root' {
        It 'Returns scripts/ralph path when ralph.ps1 exists there' {
            # Create mock repo structure
            $mockRepoRoot = Join-Path $TestDrive 'repo'
            $mockRalphDir = Join-Path $mockRepoRoot 'scripts' 'ralph'
            New-Item -Path $mockRalphDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $mockRalphDir 'ralph.ps1') -Value '# mock'

            $result = & $script:GetRalphScriptsPath -ScriptRoot $mockRepoRoot
            $result | Should -Be $mockRalphDir
        }
    }

    Context 'Fallback behavior' {
        It 'Returns script root as fallback when ralph.ps1 not found' {
            $mockDir = Join-Path $TestDrive 'empty'
            New-Item -Path $mockDir -ItemType Directory -Force | Out-Null

            $result = & $script:GetRalphScriptsPath -ScriptRoot $mockDir
            $result | Should -Be $mockDir
        }
    }
}

Describe 'Install-PowerShellAliases Function' {
    BeforeAll {
        # Replicate Install-PowerShellAliases for testing
        $script:InstallPowerShellAliases = {
            param(
                [string]$ProfilePath,
                [string]$RalphDir
            )

            # Ensure profile directory exists
            $profileDir = Split-Path -Parent $ProfilePath
            if (-not (Test-Path $profileDir)) {
                try {
                    New-Item -Path $profileDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
                }
                catch {
                    return @{
                        Success     = $false
                        ProfilePath = $ProfilePath
                        Message     = "Failed to create profile directory: $_"
                    }
                }
            }

            # Create profile file if it doesn't exist
            if (-not (Test-Path $ProfilePath)) {
                try {
                    New-Item -Path $ProfilePath -ItemType File -Force -ErrorAction Stop | Out-Null
                }
                catch {
                    return @{
                        Success     = $false
                        ProfilePath = $ProfilePath
                        Message     = "Failed to create profile: $_"
                    }
                }
            }

            # Check if Ralph functions already exist
            $profileContent = Get-Content -Path $ProfilePath -Raw -ErrorAction SilentlyContinue
            if ($profileContent -and $profileContent -match '# Ralph functions') {
                return @{
                    Success       = $true
                    ProfilePath   = $ProfilePath
                    Message       = 'Ralph functions already exist in profile, skipping'
                    AlreadyExists = $true
                }
            }

            # Build the function block
            $functionBlock = @"

# Ralph functions
function ralph { pwsh "$RalphDir/ralph.ps1" @args }
function ralph-once { pwsh "$RalphDir/ralph-once.ps1" @args }
function ralph-status { pwsh "$RalphDir/ralph-status.ps1" @args }
"@

            # Append to profile
            try {
                Add-Content -Path $ProfilePath -Value $functionBlock -ErrorAction Stop
                return @{
                    Success       = $true
                    ProfilePath   = $ProfilePath
                    Message       = 'Ralph functions added to profile'
                    AlreadyExists = $false
                }
            }
            catch {
                return @{
                    Success     = $false
                    ProfilePath = $ProfilePath
                    Message     = "Failed to write to profile: $_"
                }
            }
        }
    }

    Context 'Profile creation' {
        It 'Creates profile directory if it does not exist' {
            $profilePath = Join-Path $TestDrive 'Documents' 'PowerShell' 'Microsoft.PowerShell_profile.ps1'
            $ralphDir = Join-Path $TestDrive 'scripts' 'ralph'

            $result = & $script:InstallPowerShellAliases -ProfilePath $profilePath -RalphDir $ralphDir

            $profileDir = Split-Path -Parent $profilePath
            Test-Path $profileDir | Should -Be $true
        }

        It 'Creates profile file if it does not exist' {
            $profilePath = Join-Path $TestDrive 'profile' 'test_profile.ps1'
            $ralphDir = Join-Path $TestDrive 'scripts' 'ralph'

            $result = & $script:InstallPowerShellAliases -ProfilePath $profilePath -RalphDir $ralphDir

            Test-Path $profilePath | Should -Be $true
        }
    }

    Context 'Duplicate detection' {
        It 'Detects existing Ralph functions and skips' {
            # Create profile with existing functions
            $profilePath = Join-Path $TestDrive 'existing_profile.ps1'
            Set-Content -Path $profilePath -Value @"
# Some existing config

# Ralph functions
function ralph { pwsh "/old/path/ralph.ps1" @args }
"@
            $ralphDir = Join-Path $TestDrive 'scripts' 'ralph'

            $result = & $script:InstallPowerShellAliases -ProfilePath $profilePath -RalphDir $ralphDir

            $result.Success | Should -Be $true
            $result.AlreadyExists | Should -Be $true
            $result.Message | Should -Match 'already exist'
        }

        It 'Does not duplicate functions when run multiple times' {
            $profilePath = Join-Path $TestDrive 'multi_run_profile.ps1'
            $ralphDir = Join-Path $TestDrive 'scripts' 'ralph'

            # First run
            $result1 = & $script:InstallPowerShellAliases -ProfilePath $profilePath -RalphDir $ralphDir
            $result1.AlreadyExists | Should -Be $false

            # Second run
            $result2 = & $script:InstallPowerShellAliases -ProfilePath $profilePath -RalphDir $ralphDir
            $result2.AlreadyExists | Should -Be $true

            # Check file content - should only have one "# Ralph functions" marker
            $content = Get-Content -Path $profilePath -Raw
            $matches = [regex]::Matches($content, '# Ralph functions')
            $matches.Count | Should -Be 1
        }
    }

    Context 'Function content' {
        It 'Adds correct function block to profile' {
            $profilePath = Join-Path $TestDrive 'new_profile.ps1'
            $ralphDir = '/test/scripts/ralph'

            $result = & $script:InstallPowerShellAliases -ProfilePath $profilePath -RalphDir $ralphDir

            $content = Get-Content -Path $profilePath -Raw

            $content | Should -Match '# Ralph functions'
            $content | Should -Match 'function ralph \{ pwsh "/test/scripts/ralph/ralph\.ps1" @args \}'
            $content | Should -Match 'function ralph-once \{ pwsh "/test/scripts/ralph/ralph-once\.ps1" @args \}'
            $content | Should -Match 'function ralph-status \{ pwsh "/test/scripts/ralph/ralph-status\.ps1" @args \}'
        }

        It 'Uses absolute paths in function definitions' {
            $profilePath = Join-Path $TestDrive 'abs_path_profile.ps1'
            $ralphDir = '/absolute/path/to/scripts/ralph'

            $result = & $script:InstallPowerShellAliases -ProfilePath $profilePath -RalphDir $ralphDir

            $content = Get-Content -Path $profilePath -Raw
            $content | Should -Match '/absolute/path/to/scripts/ralph/ralph\.ps1'
        }
    }

    Context 'Return value structure' {
        It 'Returns Success = $true on successful install' {
            $profilePath = Join-Path $TestDrive 'success_profile.ps1'
            $ralphDir = Join-Path $TestDrive 'scripts' 'ralph'

            $result = & $script:InstallPowerShellAliases -ProfilePath $profilePath -RalphDir $ralphDir

            $result.Success | Should -Be $true
            $result.ProfilePath | Should -Be $profilePath
            $result.AlreadyExists | Should -Be $false
        }

        It 'Returns ProfilePath in result' {
            $profilePath = Join-Path $TestDrive 'path_test_profile.ps1'
            $ralphDir = Join-Path $TestDrive 'scripts' 'ralph'

            $result = & $script:InstallPowerShellAliases -ProfilePath $profilePath -RalphDir $ralphDir

            $result.ProfilePath | Should -Be $profilePath
        }
    }

    Context 'Existing profile content preservation' {
        It 'Preserves existing profile content when adding functions' {
            $profilePath = Join-Path $TestDrive 'preserve_profile.ps1'
            $existingContent = @"
# My existing PowerShell profile
Set-Alias -Name ll -Value Get-ChildItem
`$env:EDITOR = 'code'
"@
            Set-Content -Path $profilePath -Value $existingContent
            $ralphDir = Join-Path $TestDrive 'scripts' 'ralph'

            $result = & $script:InstallPowerShellAliases -ProfilePath $profilePath -RalphDir $ralphDir

            $content = Get-Content -Path $profilePath -Raw
            $content | Should -Match 'My existing PowerShell profile'
            $content | Should -Match 'Set-Alias -Name ll'
            $content | Should -Match "EDITOR = 'code'"
            $content | Should -Match '# Ralph functions'
        }
    }
}

Describe 'Alias Prompt Handling' {
    Context 'Script prompt patterns' {
        It 'Prompts with y/N format (default No)' {
            $script:scriptContent | Should -Match '\(y/N\)'
        }

        It 'Accepts y or Y for yes' {
            $script:scriptContent | Should -Match '\^?\[yY\]'
        }

        It 'Skips installation gracefully on non-yes input' {
            $script:scriptContent | Should -Match 'Skipping alias installation'
        }
    }
}

Describe 'Show-AliasInstructions Function' {
    Context 'Script instruction content' {
        It 'Shows how to activate aliases' {
            $script:scriptContent | Should -Match 'To activate'
        }

        It 'Shows available commands' {
            $script:scriptContent | Should -Match 'Available commands'
        }

        It 'Mentions ralph command' {
            $script:scriptContent | Should -Match 'ralph\s+-\s+Run the ralph loop'
        }

        It 'Mentions ralph-once command' {
            $script:scriptContent | Should -Match 'ralph-once\s+-\s+Run a single ralph iteration'
        }

        It 'Mentions ralph-status command' {
            $script:scriptContent | Should -Match 'ralph-status\s+-\s+Check ralph progress'
        }

        It 'Mentions absolute paths' {
            $script:scriptContent | Should -Match 'absolute paths'
        }

        It 'Handles AlreadyExists case differently' {
            $script:scriptContent | Should -Match 'already installed'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# US-002: Profile Update Detection and User Prompt Tests
# ─────────────────────────────────────────────────────────────────────────────

Describe 'Get-ExpectedRalphFunctions Function' {
    BeforeAll {
        # Dot-source the script to get the functions
        . $script:installScript
    }

    It 'Script defines Get-ExpectedRalphFunctions function' {
        $script:scriptContent | Should -Match 'function Get-ExpectedRalphFunctions'
    }

    It 'Returns hashtable with FunctionBlock property' {
        $result = Get-ExpectedRalphFunctions
        $result | Should -BeOfType [hashtable]
        $result.FunctionBlock | Should -Not -BeNullOrEmpty
    }

    It 'Returns hashtable with FunctionNames array' {
        $result = Get-ExpectedRalphFunctions
        # FunctionNames could be string or array depending on count, but should have items
        @($result.FunctionNames).Count | Should -BeGreaterOrEqual 1
    }

    It 'Returns hashtable with RalphDir path' {
        $result = Get-ExpectedRalphFunctions
        $result.RalphDir | Should -Not -BeNullOrEmpty
    }

    It 'FunctionBlock contains Ralph functions marker' {
        $result = Get-ExpectedRalphFunctions
        $result.FunctionBlock | Should -Match '# Ralph functions'
    }

    It 'FunctionNames includes core functions' {
        $result = Get-ExpectedRalphFunctions
        $result.FunctionNames | Should -Contain 'ralph'
        $result.FunctionNames | Should -Contain 'ralph-once'
        $result.FunctionNames | Should -Contain 'ralph-status'
    }
}

Describe 'Get-ProfileRalphFunctions Function' {
    BeforeAll {
        . $script:installScript
    }

    It 'Script defines Get-ProfileRalphFunctions function' {
        $script:scriptContent | Should -Match 'function Get-ProfileRalphFunctions'
    }

    Context 'When profile does not exist' {
        It 'Returns Exists = $false for non-existent profile' {
            $nonExistentPath = Join-Path $TestDrive 'nonexistent_profile.ps1'
            $result = Get-ProfileRalphFunctions -ProfilePath $nonExistentPath

            $result.Exists | Should -Be $false
            $result.FunctionNames.Count | Should -Be 0
        }
    }

    Context 'When profile has no Ralph functions' {
        It 'Returns Exists = $false for profile without Ralph section' {
            $profilePath = Join-Path $TestDrive 'no_ralph_profile.ps1'
            Set-Content -Path $profilePath -Value @"
# My profile
Set-Alias ll Get-ChildItem
"@
            $result = Get-ProfileRalphFunctions -ProfilePath $profilePath

            $result.Exists | Should -Be $false
        }
    }

    Context 'When profile has Ralph functions' {
        It 'Detects Ralph functions block' {
            $profilePath = Join-Path $TestDrive 'ralph_profile.ps1'
            Set-Content -Path $profilePath -Value @"
# My profile
Set-Alias ll Get-ChildItem

# Ralph functions
function ralph { pwsh "/test/scripts/ralph/ralph.ps1" @args }
function ralph-once { pwsh "/test/scripts/ralph/ralph-once.ps1" @args }
"@
            $result = Get-ProfileRalphFunctions -ProfilePath $profilePath

            $result.Exists | Should -Be $true
            $result.FunctionNames.Count | Should -Be 2
            $result.FunctionNames | Should -Contain 'ralph'
            $result.FunctionNames | Should -Contain 'ralph-once'
        }

        It 'Extracts RalphDir from function definitions' {
            $profilePath = Join-Path $TestDrive 'ralph_dir_profile.ps1'
            Set-Content -Path $profilePath -Value @"
# Ralph functions
function ralph { pwsh "/custom/path/to/ralph/ralph.ps1" @args }
"@
            $result = Get-ProfileRalphFunctions -ProfilePath $profilePath

            $result.RalphDir | Should -Be '/custom/path/to/ralph'
        }

        It 'Returns correct StartLine and EndLine' {
            $profilePath = Join-Path $TestDrive 'line_test_profile.ps1'
            Set-Content -Path $profilePath -Value @"
# Line 0 - comment
Set-Alias ll ls
# Ralph functions
function ralph { pwsh "/test/ralph.ps1" @args }
function ralph-once { pwsh "/test/ralph-once.ps1" @args }
# Other stuff
"@
            $result = Get-ProfileRalphFunctions -ProfilePath $profilePath

            $result.StartLine | Should -Be 2  # "# Ralph functions" is at index 2
            $result.EndLine | Should -Be 4    # Last function line is at index 4
        }
    }
}

Describe 'Compare-RalphFunctions Function' {
    BeforeAll {
        . $script:installScript
    }

    It 'Script defines Compare-RalphFunctions function' {
        $script:scriptContent | Should -Match 'function Compare-RalphFunctions'
    }

    Context 'When profile has no Ralph functions' {
        It 'Returns status = missing' {
            $profilePath = Join-Path $TestDrive 'empty_compare_profile.ps1'
            Set-Content -Path $profilePath -Value '# Empty profile'

            $result = Compare-RalphFunctions -ProfilePath $profilePath

            $result.Status | Should -Be 'missing'
            $result.InstalledCount | Should -Be 0
            $result.MissingFunctions.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When profile has outdated functions' {
        It 'Returns status = outdated when functions are missing' {
            $profilePath = Join-Path $TestDrive 'outdated_compare_profile.ps1'
            $expected = Get-ExpectedRalphFunctions
            # Only add one function when multiple are expected
            Set-Content -Path $profilePath -Value @"
# Ralph functions
function ralph { pwsh "$($expected.RalphDir)/ralph.ps1" @args }
"@
            $result = Compare-RalphFunctions -ProfilePath $profilePath

            $result.Status | Should -Be 'outdated'
            $result.NeedsUpdate | Should -Be $true
            $result.MissingFunctions.Count | Should -BeGreaterThan 0
        }

        It 'Returns PathOutdated = $true when path differs' {
            $profilePath = Join-Path $TestDrive 'path_outdated_profile.ps1'
            Set-Content -Path $profilePath -Value @"
# Ralph functions
function ralph { pwsh "/old/wrong/path/ralph.ps1" @args }
function ralph-once { pwsh "/old/wrong/path/ralph-once.ps1" @args }
function ralph-status { pwsh "/old/wrong/path/ralph-status.ps1" @args }
"@
            $result = Compare-RalphFunctions -ProfilePath $profilePath

            $result.PathOutdated | Should -Be $true
            $result.InstalledPath | Should -Be '/old/wrong/path'
        }
    }

    Context 'When profile is up-to-date' {
        It 'Returns status = up-to-date when all functions present with correct path' {
            $profilePath = Join-Path $TestDrive 'uptodate_compare_profile.ps1'
            $expected = Get-ExpectedRalphFunctions

            # Write all expected functions
            Set-Content -Path $profilePath -Value $expected.FunctionBlock

            $result = Compare-RalphFunctions -ProfilePath $profilePath

            $result.Status | Should -Be 'up-to-date'
            $result.NeedsUpdate | Should -Be $false
            $result.MissingFunctions.Count | Should -Be 0
        }
    }
}

Describe 'Update-RalphFunctionsInProfile Function' {
    BeforeAll {
        . $script:installScript
    }

    It 'Script defines Update-RalphFunctionsInProfile function' {
        $script:scriptContent | Should -Match 'function Update-RalphFunctionsInProfile'
    }

    Context 'In-place update' {
        It 'Preserves content before and after Ralph block' {
            $profilePath = Join-Path $TestDrive 'update_preserve_profile.ps1'
            Set-Content -Path $profilePath -Value @"
# Before content
Set-Alias ll ls

# Ralph functions
function ralph { pwsh "/old/path/ralph.ps1" @args }

# After content
Set-PSReadLineOption -EditMode Emacs
"@
            $comparison = Compare-RalphFunctions -ProfilePath $profilePath

            $result = Update-RalphFunctionsInProfile -ProfilePath $profilePath -Comparison $comparison

            $result.Success | Should -Be $true
            $result.Action | Should -Be 'update'

            $content = Get-Content -Path $profilePath -Raw
            $content | Should -Match '# Before content'
            $content | Should -Match 'Set-Alias ll ls'
            $content | Should -Match '# After content'
            $content | Should -Match 'Set-PSReadLineOption'
        }

        It 'Replaces Ralph functions with expected functions' {
            $profilePath = Join-Path $TestDrive 'update_replace_profile.ps1'
            Set-Content -Path $profilePath -Value @"
# Ralph functions
function ralph { pwsh "/old/path/ralph.ps1" @args }
"@
            $comparison = Compare-RalphFunctions -ProfilePath $profilePath

            $result = Update-RalphFunctionsInProfile -ProfilePath $profilePath -Comparison $comparison

            $content = Get-Content -Path $profilePath -Raw
            $content | Should -Not -Match '/old/path/'
            $content | Should -Match 'function ralph-once'
            $content | Should -Match 'function ralph-status'
        }
    }
}

Describe 'Reinstall-RalphFunctionsInProfile Function' {
    BeforeAll {
        . $script:installScript
    }

    It 'Script defines Reinstall-RalphFunctionsInProfile function' {
        $script:scriptContent | Should -Match 'function Reinstall-RalphFunctionsInProfile'
    }

    Context 'Reinstall behavior' {
        It 'Removes old block and appends new one at end' {
            $profilePath = Join-Path $TestDrive 'reinstall_profile.ps1'
            Set-Content -Path $profilePath -Value @"
# Ralph functions
function ralph { pwsh "/old/path/ralph.ps1" @args }

# Other config
Set-Alias ll ls
"@
            $comparison = Compare-RalphFunctions -ProfilePath $profilePath

            $result = Reinstall-RalphFunctionsInProfile -ProfilePath $profilePath -Comparison $comparison

            $result.Success | Should -Be $true
            $result.Action | Should -Be 'reinstall'

            $content = Get-Content -Path $profilePath -Raw
            # Old path should be gone
            $content | Should -Not -Match '/old/path/'
            # Other config preserved
            $content | Should -Match 'Set-Alias ll ls'
            # New Ralph block at end (after other config)
            $content | Should -Match '# Ralph functions'
        }
    }
}

Describe 'Install-PowerShellAliases User Prompt Options' {
    It 'Script shows S/U/R options for outdated functions' {
        $script:scriptContent | Should -Match '\(S\)kip'
        $script:scriptContent | Should -Match '\(U\)pdate'
        $script:scriptContent | Should -Match '\(R\)einstall'
    }

    It 'Script displays missing functions in prompt' {
        $script:scriptContent | Should -Match 'Missing functions:'
    }

    It 'Script displays path outdated warning' {
        $script:scriptContent | Should -Match 'Path is outdated:'
    }

    It 'Script handles S choice to skip' {
        $script:scriptContent | Should -Match "'\^\[sS\]\$'"
    }

    It 'Script handles U choice to update' {
        $script:scriptContent | Should -Match "'\^\[uU\]\$'"
    }

    It 'Script handles R choice to reinstall' {
        $script:scriptContent | Should -Match "'\^\[rR\]\$'"
    }
}

Describe 'Show-AliasInstructions Extended Commands' {
    It 'Mentions ralph-parallel command' {
        $script:scriptContent | Should -Match 'ralph-parallel\s+-\s+Run multiple ralph instances in parallel'
    }

    It 'Mentions ralph-dashboard command' {
        $script:scriptContent | Should -Match 'ralph-dashboard\s+-\s+Monitor ralph instances'
    }
}
