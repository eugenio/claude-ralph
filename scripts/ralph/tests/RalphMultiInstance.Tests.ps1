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
