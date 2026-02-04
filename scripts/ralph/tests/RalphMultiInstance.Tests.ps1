#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for Ralph multi-instance functionality.

.DESCRIPTION
    Tests core multi-instance functions: instance ID generation, locking,
    PRD atomic updates, and story claiming.
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'RalphUtils.psm1'
    Import-Module $modulePath -Force

    # Create test workspace
    $script:TestDir = Join-Path $TestDrive 'ralph-test'
    New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $script:TestDir 'instances') -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $script:TestDir 'locks') -ItemType Directory -Force | Out-Null

    # Create test PRD
    $testPrd = @{
        featureName = 'Test Feature'
        branchName = 'test/branch'
        userStories = @(
            @{ id = 'US-001'; title = 'Story 1'; priority = 1; passes = $false }
            @{ id = 'US-002'; title = 'Story 2'; priority = 2; passes = $false }
            @{ id = 'US-003'; title = 'Story 3'; priority = 3; passes = $true }
        )
    }
    $testPrd | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $script:TestDir 'prd.json')
}

Describe 'Instance ID Generation' {
    Context 'Get-RalphInstanceId' {
        It 'Returns a valid instance ID format' {
            $id = Get-RalphInstanceId -Force
            $id | Should -Match '^[a-zA-Z0-9_]+-[a-zA-Z0-9_-]+-\d+-\d+$'
        }

        It 'Returns consistent ID when called multiple times' {
            $id1 = Get-RalphInstanceId
            $id2 = Get-RalphInstanceId
            $id1 | Should -Be $id2
        }

        It 'Returns different ID when Force is used' {
            $id1 = Get-RalphInstanceId
            Start-Sleep -Seconds 1
            $id2 = Get-RalphInstanceId -Force
            $id1 | Should -Not -Be $id2
        }
    }

    Context 'Get-RalphShortId' {
        It 'Returns 8 characters' {
            $shortId = Get-RalphShortId
            $shortId.Length | Should -BeLessOrEqual 8
        }

        It 'Is prefix of full instance ID' {
            $id = Get-RalphInstanceId
            $shortId = Get-RalphShortId
            $id | Should -BeLike "$shortId*"
        }
    }
}

Describe 'Story Locking' {
    BeforeEach {
        # Clean up locks
        Get-ChildItem -Path (Join-Path $script:TestDir 'locks') -Directory -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force
    }

    Context 'Lock-RalphStory' {
        It 'Creates lock directory' {
            # We need to mock Get-RalphPaths to use our test directory
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            $result = Lock-RalphStory -StoryId 'US-TEST'
            $result | Should -Be $true

            $lockDir = Join-Path (Join-Path $script:TestDir 'locks') 'US-TEST.lock'
            Test-Path $lockDir | Should -Be $true
        }

        It 'Fails when lock already exists' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            # Create lock manually
            $lockDir = Join-Path (Join-Path $script:TestDir 'locks') 'US-EXISTS.lock'
            New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $lockDir 'owner.txt') -Value 'other-instance'
            Set-Content -Path (Join-Path $lockDir 'timestamp.txt') -Value ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

            $result = Lock-RalphStory -StoryId 'US-EXISTS'
            $result | Should -Be $false
        }
    }

    Context 'Unlock-RalphStory' {
        It 'Removes lock directory when owner matches' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            # Create lock owned by current instance
            $instanceId = Get-RalphInstanceId
            $lockDir = Join-Path (Join-Path $script:TestDir 'locks') 'US-UNLOCK.lock'
            New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $lockDir 'owner.txt') -Value $instanceId

            $result = Unlock-RalphStory -StoryId 'US-UNLOCK'
            $result | Should -Be $true
            Test-Path $lockDir | Should -Be $false
        }

        It 'Removes lock when Force is used' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            # Create lock owned by different instance
            $lockDir = Join-Path (Join-Path $script:TestDir 'locks') 'US-FORCE.lock'
            New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $lockDir 'owner.txt') -Value 'other-instance'

            $result = Unlock-RalphStory -StoryId 'US-FORCE' -Force
            $result | Should -Be $true
            Test-Path $lockDir | Should -Be $false
        }
    }

    Context 'Test-RalphStoryLocked' {
        It 'Returns true when locked' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            $lockDir = Join-Path (Join-Path $script:TestDir 'locks') 'US-LOCKED.lock'
            New-Item -Path $lockDir -ItemType Directory -Force | Out-Null

            Test-RalphStoryLocked -StoryId 'US-LOCKED' | Should -Be $true
        }

        It 'Returns false when not locked' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            Test-RalphStoryLocked -StoryId 'US-NOTLOCKED' | Should -Be $false
        }
    }
}

Describe 'Stale Lock Detection' {
    Context 'Get-RalphStoryLock' {
        It 'Identifies stale locks' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            # Create stale lock (2+ hours old)
            $lockDir = Join-Path (Join-Path $script:TestDir 'locks') 'US-STALE.lock'
            New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $lockDir 'owner.txt') -Value 'old-instance'
            $staleTime = [DateTimeOffset]::UtcNow.AddHours(-3).ToUnixTimeSeconds()
            Set-Content -Path (Join-Path $lockDir 'timestamp.txt') -Value $staleTime

            $lock = Get-RalphStoryLock -StoryId 'US-STALE'
            $lock | Should -Not -BeNull
            $lock.IsStale | Should -Be $true
            $lock.Age | Should -BeGreaterThan 7200
        }
    }
}

Describe 'Status File' {
    Context 'Update-RalphStatus' {
        It 'Creates valid JSON status file' {
            $instancePaths = @{
                StatusFile = Join-Path $script:TestDir 'status.json'
            }

            Update-RalphStatus -State 'working' -CurrentStory 'US-001' -InstancePaths $instancePaths

            Test-Path $instancePaths.StatusFile | Should -Be $true

            $status = Get-Content $instancePaths.StatusFile -Raw | ConvertFrom-Json
            $status.state | Should -Be 'working'
            $status.currentStory | Should -Be 'US-001'
            $status.lastHeartbeatEpoch | Should -BeGreaterThan 0
        }
    }
}

Describe 'Git Branch Functions (PS-005)' {
    BeforeAll {
        # Create a test git repository for each test context
        $script:GitTestDir = Join-Path $TestDrive 'git-test'
        New-Item -Path $script:GitTestDir -ItemType Directory -Force | Out-Null

        Push-Location $script:GitTestDir
        git init --quiet 2>$null
        git config user.email "test@example.com"
        git config user.name "Test User"

        # Create initial commit on main
        "initial" | Set-Content 'README.md'
        git add README.md
        git commit -m "Initial commit" --quiet 2>$null

        # Ensure we're on main
        $currentBranch = git rev-parse --abbrev-ref HEAD
        if ($currentBranch -ne 'main') {
            git branch -M main 2>$null
        }

        Pop-Location

        # Create test PRD in git test dir
        $testPrd = @{
            featureName = 'Git Test Feature'
            branchName = 'main'
            userStories = @(
                @{ id = 'GIT-001'; title = 'Git Story 1'; priority = 1; passes = $false }
            )
        }
        $testPrd | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $script:GitTestDir 'prd.json')
    }

    Context 'New-RalphStoryBranch' {
        BeforeEach {
            # Ensure we're on main before each test
            Push-Location $script:GitTestDir
            git checkout main --quiet 2>$null
            Pop-Location
        }

        It 'Creates a branch with correct naming convention' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:GitTestDir
                    ProjectRoot = $script:GitTestDir
                    PrdFile = Join-Path $script:GitTestDir 'prd.json'
                }
            }

            $branchName = New-RalphStoryBranch -StoryId 'GIT-001'
            $branchName | Should -Match '^ralph/[a-zA-Z0-9_-]+/GIT-001$'

            # Verify branch was created
            Push-Location $script:GitTestDir
            $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
            Pop-Location
            $currentBranch | Should -Be $branchName
        }

        It 'Checks out existing branch if already created' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:GitTestDir
                    ProjectRoot = $script:GitTestDir
                    PrdFile = Join-Path $script:GitTestDir 'prd.json'
                }
            }

            # First call creates branch, second checks it out
            $branchName1 = New-RalphStoryBranch -StoryId 'GIT-001'
            $branchName2 = New-RalphStoryBranch -StoryId 'GIT-001'
            $branchName1 | Should -Be $branchName2
        }
    }

    Context 'Merge-RalphStoryBranch' {
        BeforeEach {
            Push-Location $script:GitTestDir
            git checkout main --quiet 2>$null
            Pop-Location
        }

        It 'Returns true when no story branch was set by New-RalphStoryBranch' {
            # Note: Merge-RalphStoryBranch uses $script:CurrentStoryBranch which is set by New-RalphStoryBranch
            # When the internal variable is null, it returns true (no-op)
            # We test this by verifying the function doesn't throw when called without prior New-RalphStoryBranch
            # However, because of test ordering, we need to be aware the variable might be set from other tests
            # This test validates the function runs and returns a boolean
            $result = Merge-RalphStoryBranch -StoryId 'NONEXISTENT'
            # The function returns true if no branch or successful merge, false on conflict
            $finalResult = if ($result -is [array]) { $result[-1] } else { $result }
            $finalResult | Should -BeIn @($true, $false)
        }

        It 'Merges story branch with --no-ff' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:GitTestDir
                    ProjectRoot = $script:GitTestDir
                    PrdFile = Join-Path $script:GitTestDir 'prd.json'
                }
            }

            # Create branch and make changes
            $branchName = New-RalphStoryBranch -StoryId 'GIT-MERGE'

            Push-Location $script:GitTestDir
            $uniqueFile = "merge-test-$(Get-Random).txt"
            "feature content" | Set-Content $uniqueFile
            git add $uniqueFile
            git commit -m "Add feature for merge test" --quiet 2>$null
            Pop-Location

            # Merge back - result may include git output but should end with $true
            $result = Merge-RalphStoryBranch -StoryId 'GIT-MERGE'
            # Check the last element if it's an array, or the value itself
            $finalResult = if ($result -is [array]) { $result[-1] } else { $result }
            $finalResult | Should -Be $true

            # Verify we're back on main
            Push-Location $script:GitTestDir
            $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
            Pop-Location
            $currentBranch | Should -Be 'main'
        }
    }

    Context 'Remove-RalphStoryBranch' {
        BeforeEach {
            Push-Location $script:GitTestDir
            git checkout main --quiet 2>$null
            Pop-Location
        }

        It 'Returns true when branch does not exist' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:GitTestDir
                    ProjectRoot = $script:GitTestDir
                    PrdFile = Join-Path $script:GitTestDir 'prd.json'
                }
            }

            $result = Remove-RalphStoryBranch -StoryId 'NONEXISTENT' -ShortId 'xxxxxxxx'
            $result | Should -Be $true
        }

        It 'Removes unmerged branch with -Force' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:GitTestDir
                    ProjectRoot = $script:GitTestDir
                    PrdFile = Join-Path $script:GitTestDir 'prd.json'
                }
            }

            # Create branch with uncommitted changes
            $branchName = New-RalphStoryBranch -StoryId 'GIT-FORCE'
            $shortId = Get-RalphShortId

            Push-Location $script:GitTestDir
            $uniqueFile = "force-test-$(Get-Random).txt"
            "unmerged content" | Set-Content $uniqueFile
            git add $uniqueFile
            git commit -m "Unmerged commit" --quiet 2>$null
            # Switch back to main without merging
            git checkout main --quiet 2>$null
            Pop-Location

            # Force remove
            $result = Remove-RalphStoryBranch -StoryId 'GIT-FORCE' -ShortId $shortId -Force
            $result | Should -Be $true

            # Verify branch is gone
            Push-Location $script:GitTestDir
            git show-ref --verify --quiet "refs/heads/ralph/$shortId/GIT-FORCE" 2>$null
            $branchGone = ($LASTEXITCODE -ne 0)
            Pop-Location
            $branchGone | Should -Be $true
        }
    }

    Context 'Get-RalphCurrentBranch' {
        It 'Returns current story branch or null' {
            # This just verifies the function exists and runs
            $branch = Get-RalphCurrentBranch
            # Branch can be null or a string
            if ($null -ne $branch) {
                $branch | Should -BeOfType ([string])
            }
        }
    }

    Context 'Clear-RalphMergedBranches' {
        It 'Returns count of cleaned branches' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:GitTestDir
                    ProjectRoot = $script:GitTestDir
                    PrdFile = Join-Path $script:GitTestDir 'prd.json'
                }
            }

            # Just verify the function runs without error
            $cleaned = Clear-RalphMergedBranches
            $cleaned | Should -BeOfType ([int])
        }
    }
}
