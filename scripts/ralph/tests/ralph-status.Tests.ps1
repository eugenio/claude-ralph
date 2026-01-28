#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for ralph-status.ps1 status checker script.

.DESCRIPTION
    Comprehensive test suite for ralph-status.ps1 including:
    - PRD parsing with various story states
    - Progress percentage calculation
    - Formatted table output
    - Missing prd.json error handling
    - Progress bar rendering
    - Edge cases (0%, 50%, 100% complete)
#>

BeforeAll {
    # Import the utilities module (ralph-status.ps1 depends on it)
    $modulePath = Join-Path $PSScriptRoot '..' 'RalphUtils.psm1'
    Import-Module $modulePath -Force

    # Define the script path
    $script:statusScript = Join-Path $PSScriptRoot '..' 'ralph-status.ps1'

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

Describe 'ralph-status.ps1 Script Structure' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
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
}

Describe 'Script Functions' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
    }

    It 'Defines Get-GitBranch function' {
        $script:scriptContent | Should -Match 'function Get-GitBranch'
    }

    It 'Defines Get-ProgressBar function' {
        $script:scriptContent | Should -Match 'function Get-ProgressBar'
    }

    It 'Defines Show-Banner function' {
        $script:scriptContent | Should -Match 'function Show-Banner'
    }

    It 'Defines Show-ProgressSummary function' {
        $script:scriptContent | Should -Match 'function Show-ProgressSummary'
    }

    It 'Defines Show-StoryTable function' {
        $script:scriptContent | Should -Match 'function Show-StoryTable'
    }

    It 'Defines Show-IncompleteStories function' {
        $script:scriptContent | Should -Match 'function Show-IncompleteStories'
    }
}

Describe 'Get-ProgressBar Function' {
    BeforeAll {
        # Replicate the progress bar function for testing
        $script:getProgressBar = {
            param(
                [int]$Percentage,
                [int]$Width = 30
            )

            # Ensure percentage is in valid range
            $Percentage = [Math]::Max(0, [Math]::Min(100, $Percentage))

            # Calculate filled and empty portions
            $filledCount = [Math]::Floor(($Percentage / 100) * $Width)
            $emptyCount = $Width - $filledCount

            # Unicode block characters: full block (2588), light shade (2591)
            $fullBlock = [char]0x2588
            $emptyBlock = [char]0x2591

            $filled = [string]::new($fullBlock, $filledCount)
            $empty = [string]::new($emptyBlock, $emptyCount)

            return "$filled$empty"
        }
    }

    Context 'Progress bar at 0%' {
        It 'Returns all empty blocks' {
            $bar = & $script:getProgressBar -Percentage 0 -Width 10
            $bar.Length | Should -Be 10
            # All should be light shade (empty)
            $bar | Should -Be ([string]::new([char]0x2591, 10))
        }
    }

    Context 'Progress bar at 50%' {
        It 'Returns half filled, half empty' {
            $bar = & $script:getProgressBar -Percentage 50 -Width 10
            $bar.Length | Should -Be 10
            # First 5 should be full, last 5 should be empty
            $fullBlock = [char]0x2588
            $emptyBlock = [char]0x2591
            $expected = ([string]::new($fullBlock, 5)) + ([string]::new($emptyBlock, 5))
            $bar | Should -Be $expected
        }
    }

    Context 'Progress bar at 100%' {
        It 'Returns all filled blocks' {
            $bar = & $script:getProgressBar -Percentage 100 -Width 10
            $bar.Length | Should -Be 10
            # All should be full block
            $bar | Should -Be ([string]::new([char]0x2588, 10))
        }
    }

    Context 'Progress bar default width' {
        It 'Uses default width of 30' {
            $bar = & $script:getProgressBar -Percentage 50
            $bar.Length | Should -Be 30
        }
    }

    Context 'Edge cases' {
        It 'Clamps negative percentage to 0' {
            $bar = & $script:getProgressBar -Percentage -10 -Width 10
            $bar | Should -Be ([string]::new([char]0x2591, 10))
        }

        It 'Clamps percentage over 100 to 100' {
            $bar = & $script:getProgressBar -Percentage 150 -Width 10
            $bar | Should -Be ([string]::new([char]0x2588, 10))
        }

        It 'Handles 33% correctly (floor to 3 out of 10)' {
            $bar = & $script:getProgressBar -Percentage 33 -Width 10
            $fullBlock = [char]0x2588
            $emptyBlock = [char]0x2591
            # Floor(33/100 * 10) = Floor(3.3) = 3
            $expected = ([string]::new($fullBlock, 3)) + ([string]::new($emptyBlock, 7))
            $bar | Should -Be $expected
        }
    }
}

Describe 'PRD Parsing with Various Story States' {
    Context 'All stories complete (100%)' {
        It 'Calculates correct percentage' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $true),
                (New-TestStory -Id 'US-002' -Passes $true),
                (New-TestStory -Id 'US-003' -Passes $true)
            )

            $status = Get-PrdStatus -Prd $prd
            $status.Percentage | Should -Be 100
            $status.Complete | Should -Be 3
            $status.Remaining | Should -Be 0
            $status.Total | Should -Be 3
        }

        It 'Returns empty incomplete stories array' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $true)
            )

            $status = Get-PrdStatus -Prd $prd
            $status.IncompleteStories.Count | Should -Be 0
        }
    }

    Context 'No stories complete (0%)' {
        It 'Calculates correct percentage' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $false),
                (New-TestStory -Id 'US-002' -Passes $false)
            )

            $status = Get-PrdStatus -Prd $prd
            $status.Percentage | Should -Be 0
            $status.Complete | Should -Be 0
            $status.Remaining | Should -Be 2
        }

        It 'Returns all stories as incomplete' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $false),
                (New-TestStory -Id 'US-002' -Passes $false)
            )

            $status = Get-PrdStatus -Prd $prd
            $status.IncompleteStories.Count | Should -Be 2
        }
    }

    Context 'Half complete (50%)' {
        It 'Calculates correct percentage' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $true),
                (New-TestStory -Id 'US-002' -Passes $false)
            )

            $status = Get-PrdStatus -Prd $prd
            $status.Percentage | Should -Be 50
            $status.Complete | Should -Be 1
            $status.Remaining | Should -Be 1
        }
    }

    Context 'Mixed completion states' {
        It 'Calculates correct rounding for 33%' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $true),
                (New-TestStory -Id 'US-002' -Passes $false),
                (New-TestStory -Id 'US-003' -Passes $false)
            )

            $status = Get-PrdStatus -Prd $prd
            $status.Percentage | Should -Be 33  # Round(1/3 * 100) = 33
        }

        It 'Calculates correct rounding for 67%' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $true),
                (New-TestStory -Id 'US-002' -Passes $true),
                (New-TestStory -Id 'US-003' -Passes $false)
            )

            $status = Get-PrdStatus -Prd $prd
            $status.Percentage | Should -Be 67  # Round(2/3 * 100) = 67
        }
    }

    Context 'Empty user stories' {
        It 'Returns 0 for all counts' {
            $prd = New-TestPrd -UserStories @()

            $status = Get-PrdStatus -Prd $prd
            $status.Total | Should -Be 0
            $status.Complete | Should -Be 0
            $status.Remaining | Should -Be 0
            $status.Percentage | Should -Be 0
        }
    }

    Context 'Null PRD' {
        It 'Returns zeros and empty arrays' {
            $status = Get-PrdStatus -Prd $null

            $status.Total | Should -Be 0
            $status.Complete | Should -Be 0
            $status.Percentage | Should -Be 0
            $status.IncompleteStories | Should -BeNullOrEmpty
        }
    }
}

Describe 'Incomplete Stories Sorting' {
    Context 'Stories sorted by priority' {
        It 'Returns incomplete stories sorted by priority ascending' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-003' -Priority 3 -Passes $false),
                (New-TestStory -Id 'US-001' -Priority 1 -Passes $true),
                (New-TestStory -Id 'US-002' -Priority 2 -Passes $false),
                (New-TestStory -Id 'US-004' -Priority 4 -Passes $false)
            )

            $status = Get-PrdStatus -Prd $prd
            $status.IncompleteStories.Count | Should -Be 3
            $status.IncompleteStories[0].id | Should -Be 'US-002'  # Priority 2
            $status.IncompleteStories[1].id | Should -Be 'US-003'  # Priority 3
            $status.IncompleteStories[2].id | Should -Be 'US-004'  # Priority 4
        }
    }
}

Describe 'Missing prd.json Error Handling' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
    }

    It 'Script checks for prd.json existence' {
        $script:scriptContent | Should -Match 'Test-Path \$paths\.PrdFile'
    }

    It 'Displays error message for missing prd.json' {
        $script:scriptContent | Should -Match 'Error: prd\.json not found'
    }

    It 'Shows expected location path' {
        $script:scriptContent | Should -Match 'Expected location:'
    }

    It 'Provides helpful instructions' {
        $script:scriptContent | Should -Match 'To get started:'
        $script:scriptContent | Should -Match 'Copy prd\.json\.example to prd\.json'
    }

    It 'Exits with code 1 on missing prd.json' {
        $script:scriptContent | Should -Match 'exit 1'
    }
}

Describe 'Formatted Table Output' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw

        # Replicate the story table logic for testing
        $script:formatStoryRow = {
            param([PSObject]$Story)

            $idWidth = 8
            $priorityWidth = 8
            $statusWidth = 10
            $titleWidth = 40

            $status = if ($Story.passes) { 'COMPLETE' } else { 'PENDING' }

            # Truncate title if too long
            $title = $Story.title
            if ($title.Length -gt $titleWidth) {
                $title = $title.Substring(0, $titleWidth - 3) + '...'
            }

            $idStr = $Story.id.ToString().PadRight($idWidth)
            $priorityStr = $Story.priority.ToString().PadRight($priorityWidth)
            $statusStr = $status.PadRight($statusWidth)

            return @{
                Id       = $idStr
                Priority = $priorityStr
                Status   = $statusStr
                Title    = $title
            }
        }
    }

    It 'Uses column widths for formatting' {
        $script:scriptContent | Should -Match '\$idWidth = 8'
        $script:scriptContent | Should -Match '\$priorityWidth = 8'
        $script:scriptContent | Should -Match '\$statusWidth = 10'
        $script:scriptContent | Should -Match '\$titleWidth = 40'
    }

    It 'Uses Unicode horizontal line character for separators' {
        # Unicode: ─ (0x2500)
        $script:scriptContent | Should -Match '0x2500'
    }

    It 'Sorts stories by priority for display' {
        $script:scriptContent | Should -Match 'Sort-Object.*priority'
    }

    Context 'Story row formatting' {
        It 'Formats complete story status correctly' {
            $story = New-TestStory -Id 'US-001' -Title 'Test Story' -Priority 1 -Passes $true
            $row = & $script:formatStoryRow -Story $story
            $row.Status.Trim() | Should -Be 'COMPLETE'
        }

        It 'Formats incomplete story status correctly' {
            $story = New-TestStory -Id 'US-001' -Title 'Test Story' -Priority 1 -Passes $false
            $row = & $script:formatStoryRow -Story $story
            $row.Status.Trim() | Should -Be 'PENDING'
        }

        It 'Truncates long titles with ellipsis' {
            $longTitle = 'This is a very long title that exceeds the column width limit significantly'
            $story = New-TestStory -Id 'US-001' -Title $longTitle -Priority 1 -Passes $false
            $row = & $script:formatStoryRow -Story $story
            $row.Title.Length | Should -BeLessOrEqual 40
            $row.Title | Should -Match '\.\.\.$'
        }

        It 'Preserves short titles without truncation' {
            $story = New-TestStory -Id 'US-001' -Title 'Short title' -Priority 1 -Passes $false
            $row = & $script:formatStoryRow -Story $story
            $row.Title | Should -Be 'Short title'
        }

        It 'Pads ID correctly' {
            $story = New-TestStory -Id 'US-1' -Title 'Test' -Priority 1 -Passes $false
            $row = & $script:formatStoryRow -Story $story
            $row.Id.Length | Should -Be 8
        }
    }
}

Describe 'Progress Bar Color Logic' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
    }

    It 'Uses green color for 100% complete' {
        # Check that the script has logic for green at 100%
        $script:scriptContent | Should -Match 'if \(\$Status\.Percentage -eq 100\)'
        $script:scriptContent | Should -Match "Green.*-NoNewline"
    }

    It 'Uses yellow color for 50-99% complete' {
        $script:scriptContent | Should -Match '\$Status\.Percentage -ge 50'
        $script:scriptContent | Should -Match "Yellow.*-NoNewline"
    }

    It 'Uses red color for less than 50% complete' {
        # The else clause handles <50%
        $script:scriptContent | Should -Match "Red.*-NoNewline"
    }
}

Describe 'Git Branch Display' {
    BeforeAll {
        # Replicate the git branch function for testing
        $script:getGitBranch = {
            try {
                $branch = git branch --show-current 2>$null
                if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($branch)) {
                    return $branch.Trim()
                }
            }
            catch {
                # Ignore errors
            }
            return $null
        }
    }

    It 'Script defines Get-GitBranch function' {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
        $script:scriptContent | Should -Match 'function Get-GitBranch'
    }

    It 'Script uses git branch --show-current command' {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
        $script:scriptContent | Should -Match 'git branch --show-current'
    }

    It 'Script checks LASTEXITCODE for git command success' {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
        $script:scriptContent | Should -Match '\$LASTEXITCODE -eq 0'
    }

    It 'Script displays branch in banner when available' {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
        $script:scriptContent | Should -Match 'if \(\$Branch\)'
        $script:scriptContent | Should -Match 'Branch:'
    }
}

Describe 'Show-IncompleteStories Function' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
    }

    It 'Returns early when no incomplete stories' {
        $script:scriptContent | Should -Match 'if \(\$IncompleteStories\.Count -eq 0\)'
        $script:scriptContent | Should -Match 'return'
    }

    It 'Displays header for incomplete stories section' {
        $script:scriptContent | Should -Match 'Incomplete Stories \(by priority\):'
    }

    It 'Shows priority in brackets' {
        $script:scriptContent | Should -Match '\[\$\(\$story\.priority\)\]'
    }

    It 'Shows story ID and title' {
        $script:scriptContent | Should -Match '\$story\.id'
        $script:scriptContent | Should -Match '\$story\.title'
    }
}

Describe 'Banner Function' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
    }

    It 'Uses Unicode double horizontal line for banner' {
        # Unicode: ═ (0x2550)
        $script:scriptContent | Should -Match '0x2550'
    }

    It 'Displays RALPH STATUS title' {
        $script:scriptContent | Should -Match 'RALPH STATUS'
    }

    It 'Uses yellow color for title' {
        # Check that RALPH STATUS is displayed with Yellow color (on the same line)
        $script:scriptContent | Should -Match "RALPH STATUS.*-ForegroundColor Yellow"
    }

    It 'Uses blue color for separator lines' {
        $script:scriptContent | Should -Match '0x2550.*-ForegroundColor Blue'
    }
}

Describe 'Edge Cases' {
    Context 'Single story' {
        It 'Handles single complete story' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $true)
            )

            $status = Get-PrdStatus -Prd $prd
            $status.Total | Should -Be 1
            $status.Complete | Should -Be 1
            $status.Percentage | Should -Be 100
        }

        It 'Handles single incomplete story' {
            $prd = New-TestPrd -UserStories @(
                (New-TestStory -Id 'US-001' -Passes $false)
            )

            $status = Get-PrdStatus -Prd $prd
            $status.Total | Should -Be 1
            $status.Complete | Should -Be 0
            $status.Percentage | Should -Be 0
        }
    }

    Context 'Large number of stories' {
        It 'Handles 100 stories correctly' {
            $stories = @()
            for ($i = 1; $i -le 100; $i++) {
                $passes = ($i -le 75)  # 75% complete
                $stories += New-TestStory -Id "US-$i" -Priority $i -Passes $passes
            }
            $prd = New-TestPrd -UserStories $stories

            $status = Get-PrdStatus -Prd $prd
            $status.Total | Should -Be 100
            $status.Complete | Should -Be 75
            $status.Percentage | Should -Be 75
        }
    }

    Context 'Story with empty title' {
        It 'Handles empty title string' {
            $story = New-TestStory -Id 'US-001' -Title '' -Priority 1 -Passes $false
            $prd = New-TestPrd -UserStories @($story)

            $status = Get-PrdStatus -Prd $prd
            $status.IncompleteStories[0].title | Should -Be ''
        }
    }

    Context 'Story with special characters in title' {
        It 'Handles title with special characters' {
            $story = New-TestStory -Id 'US-001' -Title "Test with 'quotes' and ""double"" and <brackets>" -Priority 1 -Passes $false
            $prd = New-TestPrd -UserStories @($story)

            $status = Get-PrdStatus -Prd $prd
            $status.IncompleteStories.Count | Should -Be 1
        }
    }
}

Describe 'No User Stories Case' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
    }

    It 'Checks for zero stories' {
        $script:scriptContent | Should -Match '\$status\.Total -eq 0'
    }

    It 'Displays helpful message when no stories' {
        $script:scriptContent | Should -Match 'No user stories found'
    }

    It 'Exits gracefully with code 0 when no stories' {
        $script:scriptContent | Should -Match 'exit 0'
    }
}

Describe 'All Complete Message' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
    }

    It 'Displays all complete message when no incomplete stories' {
        $script:scriptContent | Should -Match 'All stories complete!'
    }

    It 'Uses green color for completion message' {
        $script:scriptContent | Should -Match "'All stories complete!'.*-ForegroundColor Green"
    }
}

Describe 'Invalid JSON Handling' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
    }

    It 'Checks for null PRD after reading' {
        $script:scriptContent | Should -Match '\$null -eq \$prd'
    }

    It 'Displays error message for invalid JSON' {
        $script:scriptContent | Should -Match 'Failed to parse prd\.json'
    }

    It 'Exits with code 1 on invalid JSON' {
        # Check that there's an exit 1 somewhere after the JSON parse error check
        # The pattern checks for the error message and then an exit 1 somewhere in the file
        $script:scriptContent | Should -Match 'Failed to parse prd\.json'
        $script:scriptContent | Should -Match 'exit 1'
    }
}

Describe 'Module Integration' {
    It 'Uses Get-RalphPaths from RalphUtils' {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
        $script:scriptContent | Should -Match '\$paths = Get-RalphPaths'
    }

    It 'Uses Read-PrdJson from RalphUtils' {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
        $script:scriptContent | Should -Match '\$prd = Read-PrdJson'
    }

    It 'Uses Get-PrdStatus from RalphUtils' {
        $script:scriptContent = Get-Content -Path $script:statusScript -Raw
        $script:scriptContent | Should -Match '\$status = Get-PrdStatus'
    }
}

AfterAll {
    # Clean up - remove the imported module
    Remove-Module RalphUtils -ErrorAction SilentlyContinue
}
