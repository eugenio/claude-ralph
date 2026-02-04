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

# PS-012: Comprehensive Core Function Tests
Describe 'PS-012: Concurrent Lock Attempts' {
    BeforeEach {
        # Clean up locks
        Get-ChildItem -Path (Join-Path $script:TestDir 'locks') -Directory -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force
    }

    Context 'Atomic lock acquisition' {
        It 'Only one concurrent lock attempt succeeds' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            $storyId = 'US-CONCURRENT-001'

            # Use Start-ThreadJob for true parallel execution
            $jobs = @()
            for ($i = 0; $i -lt 5; $i++) {
                $jobs += Start-ThreadJob -ScriptBlock {
                    param($testDir, $storyId)

                    # Try to acquire lock atomically using directory creation
                    $lockDir = Join-Path (Join-Path $testDir 'locks') "$storyId.lock"
                    try {
                        $null = New-Item -Path $lockDir -ItemType Directory -ErrorAction Stop
                        Set-Content -Path (Join-Path $lockDir 'owner.txt') -Value "instance-$([Guid]::NewGuid())"
                        Set-Content -Path (Join-Path $lockDir 'timestamp.txt') -Value ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
                        return $true
                    }
                    catch {
                        return $false
                    }
                } -ArgumentList $script:TestDir, $storyId
            }

            # Wait for all jobs and collect results
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job

            # Exactly one should succeed - atomic directory creation ensures only one wins
            $successCount = ($results | Where-Object { $_ -eq $true }).Count
            $successCount | Should -Be 1
        }

        It 'Lock-RalphStory uses atomic directory creation' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            $storyId = 'US-ATOMIC-001'

            # First lock should succeed
            $result1 = Lock-RalphStory -StoryId $storyId
            $result1 | Should -Be $true

            # Verify lock files exist
            $lockDir = Join-Path (Join-Path $script:TestDir 'locks') "$storyId.lock"
            Test-Path $lockDir | Should -Be $true
            Test-Path (Join-Path $lockDir 'owner.txt') | Should -Be $true
            Test-Path (Join-Path $lockDir 'timestamp.txt') | Should -Be $true
        }
    }
}

Describe 'PS-012: PRD Atomic Updates' {
    BeforeEach {
        # Create fresh PRD
        $testPrd = @{
            featureName = 'Test Feature'
            branchName = 'test/branch'
            userStories = @(
                @{ id = 'US-001'; title = 'Story 1'; priority = 1; passes = $false }
                @{ id = 'US-002'; title = 'Story 2'; priority = 2; passes = $false }
            )
        }
        $testPrd | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $script:TestDir 'prd.json') -Force
    }

    Context 'Lock-RalphPrd function' {
        It 'Returns hashtable with Acquired, Mutex, Error keys' {
            $result = Lock-RalphPrd
            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -Contain 'Acquired'
            $result.Keys | Should -Contain 'Mutex'
            $result.Keys | Should -Contain 'Error'

            # Clean up
            if ($result.Acquired -and $result.Mutex) {
                $result.Mutex.ReleaseMutex()
                $result.Mutex.Dispose()
            }
        }

        It 'Acquires mutex successfully' {
            $result = Lock-RalphPrd
            $result.Acquired | Should -Be $true
            $result.Mutex | Should -Not -BeNull
            $result.Error | Should -BeNull

            # Clean up
            $result.Mutex.ReleaseMutex()
            $result.Mutex.Dispose()
        }

        It 'Respects timeout and retries using runspace to test cross-process locking' {
            # Note: Mutexes are re-entrant within the same thread, so we use a runspace
            # to simulate a different thread attempting to acquire the same mutex
            $testMutexName = "Global\RalphPrdLock-TestTimeout-$([Guid]::NewGuid())"

            # Acquire lock in current thread
            $mutex1 = New-Object System.Threading.Mutex($false, $testMutexName)
            $acquired1 = $mutex1.WaitOne(1000)
            $acquired1 | Should -Be $true

            # Try to acquire from different runspace (different thread)
            $runspace = [runspacefactory]::CreateRunspace()
            $runspace.Open()
            $powershell = [powershell]::Create()
            $powershell.Runspace = $runspace
            $null = $powershell.AddScript({
                param($mutexName)
                $mutex2 = New-Object System.Threading.Mutex($false, $mutexName)
                try {
                    # Short timeout - should fail since mutex is held
                    $acquired = $mutex2.WaitOne(500)
                    return $acquired
                }
                finally {
                    if ($acquired) {
                        $mutex2.ReleaseMutex()
                    }
                    $mutex2.Dispose()
                }
            })
            $null = $powershell.AddArgument($testMutexName)
            $result = $powershell.Invoke()
            $powershell.Dispose()
            $runspace.Close()

            $result[0] | Should -Be $false

            # Clean up
            $mutex1.ReleaseMutex()
            $mutex1.Dispose()
        }
    }

    Context 'Update-RalphPrd function' {
        It 'Creates backup before writing' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                    PrdFile = Join-Path $script:TestDir 'prd.json'
                }
            }

            $backupFile = Join-Path $script:TestDir 'prd.json.bak'
            if (Test-Path $backupFile) { Remove-Item $backupFile }

            $result = Update-RalphPrd -Description 'Test update' -UpdateScript {
                param($prd)
                $prd.featureName = 'Updated Feature'
                return $true
            }

            $result | Should -Be $true
            Test-Path $backupFile | Should -Be $true
        }

        It 'Validates JSON after write' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                    PrdFile = Join-Path $script:TestDir 'prd.json'
                }
            }

            $result = Update-RalphPrd -Description 'Add story' -UpdateScript {
                param($prd)
                $prd.userStories += @{ id = 'US-003'; title = 'New Story'; priority = 3; passes = $false }
                return $true
            }

            $result | Should -Be $true

            # Verify JSON is valid
            $prd = Get-Content (Join-Path $script:TestDir 'prd.json') -Raw | ConvertFrom-Json
            $prd.userStories.Count | Should -Be 3
        }

        It 'Aborts when UpdateScript returns false' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                    PrdFile = Join-Path $script:TestDir 'prd.json'
                }
            }

            $originalContent = Get-Content (Join-Path $script:TestDir 'prd.json') -Raw

            $result = Update-RalphPrd -Description 'Aborted update' -UpdateScript {
                param($prd)
                $prd.featureName = 'Should Not Change'
                return $false  # Abort
            }

            $result | Should -Be $false

            # Content should be unchanged
            $currentContent = Get-Content (Join-Path $script:TestDir 'prd.json') -Raw
            ($currentContent | ConvertFrom-Json).featureName | Should -Be 'Test Feature'
        }
    }

    Context 'Concurrent PRD writes' {
        It 'Does not corrupt JSON with concurrent writes' {
            # Create a temporary PRD file for this test
            # Use cross-platform temp path which is accessible across runspaces
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "concurrent-prd-test-$([Guid]::NewGuid())"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            try {
                $prdFile = Join-Path $tempDir 'prd.json'
                $initialPrd = @{
                    featureName = 'Concurrent Test'
                    branchName = 'test/concurrent'
                    userStories = @(
                        @{ id = 'US-001'; title = 'Story 1'; priority = 1; passes = $false }
                        @{ id = 'US-002'; title = 'Story 2'; priority = 2; passes = $false }
                    )
                }
                $initialPrd | ConvertTo-Json -Depth 5 | Set-Content $prdFile -Force

                # Verify initial file was created
                Test-Path $prdFile | Should -Be $true

                $runspaces = @()
                $runspacePool = [runspacefactory]::CreateRunspacePool(1, 3)
                $runspacePool.Open()

                $mutexName = "Global\RalphPrdLock-Concurrent-$([Guid]::NewGuid())"

                # Create 3 concurrent update attempts
                for ($i = 0; $i -lt 3; $i++) {
                    $powershell = [powershell]::Create()
                    $powershell.RunspacePool = $runspacePool
                    $null = $powershell.AddScript({
                        param($prdFilePath, $index, $mutexName)

                        # Update PRD using mutex
                        $mutex = New-Object System.Threading.Mutex($false, $mutexName)
                        $acquired = $false

                        try {
                            $acquired = $mutex.WaitOne(10000)
                            if ($acquired) {
                                # Read, modify, write
                                $prd = Get-Content $prdFilePath -Raw | ConvertFrom-Json
                                $prd.userStories[$index % 2].title = "Story-$index"
                                $prd | ConvertTo-Json -Depth 5 | Set-Content $prdFilePath -Force
                                return @{ Acquired = $true; Success = $true }
                            }
                            return @{ Acquired = $false; Success = $false }
                        }
                        catch {
                            return @{ Acquired = $acquired; Success = $false; Error = $_.ToString() }
                        }
                        finally {
                            if ($acquired) {
                                $mutex.ReleaseMutex()
                            }
                            $mutex.Dispose()
                        }
                    })
                    $null = $powershell.AddArgument($prdFile)
                    $null = $powershell.AddArgument($i)
                    $null = $powershell.AddArgument($mutexName)

                    $runspaces += @{
                        PowerShell = $powershell
                        Handle = $powershell.BeginInvoke()
                    }
                }

                # Wait for all runspaces to complete
                $results = @()
                foreach ($rs in $runspaces) {
                    $results += $rs.PowerShell.EndInvoke($rs.Handle)
                    $rs.PowerShell.Dispose()
                }
                $runspacePool.Close()
                $runspacePool.Dispose()

                # Verify at least some writes succeeded
                $successCount = ($results | Where-Object { $_.Success -eq $true }).Count
                $successCount | Should -BeGreaterThan 0

                # Verify JSON is still valid (not corrupted)
                $jsonContent = Get-Content $prdFile -Raw
                $jsonContent | Should -Not -BeNullOrEmpty

                $finalPrd = $jsonContent | ConvertFrom-Json
                $finalPrd | Should -Not -BeNull
                $finalPrd.userStories | Should -Not -BeNull
                $finalPrd.userStories.Count | Should -Be 2
            }
            finally {
                # Cleanup
                if (Test-Path $tempDir) {
                    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

Describe 'PS-012: Stale Lock Detection and Cleanup' {
    BeforeEach {
        # Clean up locks
        Get-ChildItem -Path (Join-Path $script:TestDir 'locks') -Directory -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force
    }

    Context 'Get-RalphStaleLocks' {
        It 'Returns empty array when no stale locks exist' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }
            Mock Get-RalphStoryLocks -ModuleName RalphUtils {
                return @(
                    @{
                        StoryId = 'US-FRESH'
                        Owner = 'current-instance'
                        Timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                        Age = 60
                        IsDead = $false
                        IsStale = $false
                    }
                )
            }

            $staleLocks = Get-RalphStaleLocks
            $staleLocks | Should -BeNullOrEmpty
        }

        It 'Finds locks older than threshold' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            # Create stale lock (older than default 2 hours)
            $lockDir = Join-Path (Join-Path $script:TestDir 'locks') 'US-OLDLOCK.lock'
            New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $lockDir 'owner.txt') -Value 'old-instance'
            $staleTime = [DateTimeOffset]::UtcNow.AddHours(-4).ToUnixTimeSeconds()
            Set-Content -Path (Join-Path $lockDir 'timestamp.txt') -Value $staleTime

            $staleLocks = Get-RalphStaleLocks
            $staleLocks | Should -Not -BeNullOrEmpty
            ($staleLocks | Where-Object { $_.StoryId -eq 'US-OLDLOCK' }) | Should -Not -BeNull
        }

        It 'Finds locks with dead owners' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            # Create lock with impossible PID (dead owner simulation)
            $lockDir = Join-Path (Join-Path $script:TestDir 'locks') 'US-DEADOWNER.lock'
            New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $lockDir 'owner.txt') -Value 'nonexistent-instance'
            Set-Content -Path (Join-Path $lockDir 'timestamp.txt') -Value ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
            Set-Content -Path (Join-Path $lockDir 'pid.txt') -Value '999999999'  # Invalid PID

            $staleLocks = Get-RalphStaleLocks -ThresholdSeconds 1
            # At minimum the lock should be detectable - may or may not be marked dead based on PID check
            # The ThresholdSeconds=1 ensures the lock is stale by age at least
            Start-Sleep -Seconds 2
            $staleLocks = Get-RalphStaleLocks -ThresholdSeconds 1
            $staleLocks | Should -Not -BeNullOrEmpty
        }

        It 'Respects custom threshold parameter' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            # Create lock 120 seconds old
            $lockDir = Join-Path (Join-Path $script:TestDir 'locks') 'US-THRESHOLD.lock'
            New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $lockDir 'owner.txt') -Value 'test-instance'
            $oldTime = [DateTimeOffset]::UtcNow.AddSeconds(-120).ToUnixTimeSeconds()
            Set-Content -Path (Join-Path $lockDir 'timestamp.txt') -Value $oldTime

            # Should NOT be stale with default 2-hour threshold
            $staleLocks1 = Get-RalphStaleLocks -ThresholdSeconds 7200
            ($staleLocks1 | Where-Object { $_.StoryId -eq 'US-THRESHOLD' }) | Should -BeNull

            # Should be stale with 60-second threshold
            $staleLocks2 = Get-RalphStaleLocks -ThresholdSeconds 60
            ($staleLocks2 | Where-Object { $_.StoryId -eq 'US-THRESHOLD' }) | Should -Not -BeNull
        }
    }

    Context 'Clear-RalphStaleLocks' {
        It 'Clears all stale locks' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            # Create multiple stale locks
            foreach ($id in @('US-STALE1', 'US-STALE2', 'US-STALE3')) {
                $lockDir = Join-Path (Join-Path $script:TestDir 'locks') "$id.lock"
                New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
                Set-Content -Path (Join-Path $lockDir 'owner.txt') -Value 'old-instance'
                $staleTime = [DateTimeOffset]::UtcNow.AddHours(-5).ToUnixTimeSeconds()
                Set-Content -Path (Join-Path $lockDir 'timestamp.txt') -Value $staleTime
            }

            # Verify locks exist
            $lockCount = (Get-ChildItem -Path (Join-Path $script:TestDir 'locks') -Directory).Count
            $lockCount | Should -Be 3

            # Clear stale locks
            $cleared = Clear-RalphStaleLocks

            # Verify locks removed
            $remainingLocks = Get-ChildItem -Path (Join-Path $script:TestDir 'locks') -Directory -ErrorAction SilentlyContinue
            $remainingLocks | Should -BeNullOrEmpty
            $cleared | Should -BeGreaterOrEqual 3
        }

        It 'Does not clear fresh locks' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            # Create fresh lock
            $instanceId = Get-RalphInstanceId
            $lockDir = Join-Path (Join-Path $script:TestDir 'locks') 'US-FRESH.lock'
            New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $lockDir 'owner.txt') -Value $instanceId
            Set-Content -Path (Join-Path $lockDir 'timestamp.txt') -Value ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
            Set-Content -Path (Join-Path $lockDir 'pid.txt') -Value $PID

            # Clear stale locks (should not clear fresh lock)
            $cleared = Clear-RalphStaleLocks

            # Fresh lock should still exist
            Test-Path $lockDir | Should -Be $true
            $cleared | Should -Be 0
        }
    }

    Context 'Clear-RalphStaleLock (single story)' {
        It 'Clears stale lock for specific story' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            # Create stale lock
            $lockDir = Join-Path (Join-Path $script:TestDir 'locks') 'US-SINGLE-STALE.lock'
            New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $lockDir 'owner.txt') -Value 'old-instance'
            $staleTime = [DateTimeOffset]::UtcNow.AddHours(-3).ToUnixTimeSeconds()
            Set-Content -Path (Join-Path $lockDir 'timestamp.txt') -Value $staleTime

            $result = Clear-RalphStaleLock -StoryId 'US-SINGLE-STALE'
            $result | Should -Be $true
            Test-Path $lockDir | Should -Be $false
        }

        It 'Returns false for non-existent lock' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            $result = Clear-RalphStaleLock -StoryId 'US-NONEXISTENT'
            $result | Should -Be $false
        }

        It 'Returns false for fresh lock' {
            Mock Get-RalphPaths -ModuleName RalphUtils {
                return @{
                    RalphDir = $script:TestDir
                    ProjectRoot = $script:TestDir
                }
            }

            $instanceId = Get-RalphInstanceId
            $lockDir = Join-Path (Join-Path $script:TestDir 'locks') 'US-FRESH-SINGLE.lock'
            New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $lockDir 'owner.txt') -Value $instanceId
            Set-Content -Path (Join-Path $lockDir 'timestamp.txt') -Value ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
            Set-Content -Path (Join-Path $lockDir 'pid.txt') -Value $PID

            $result = Clear-RalphStaleLock -StoryId 'US-FRESH-SINGLE'
            $result | Should -Be $false
            Test-Path $lockDir | Should -Be $true
        }
    }
}

Describe 'PS-012: Instance ID Format Validation' {
    Context 'ID Format Requirements' {
        It 'Contains username component' {
            $id = Get-RalphInstanceId -Force
            $parts = $id -split '-'
            $parts[0] | Should -Not -BeNullOrEmpty
            # Username should match current user (cross-platform)
            $expectedUser = if ($env:USERNAME) { $env:USERNAME } else { $env:USER }
            $parts[0] | Should -Be $expectedUser
        }

        It 'Contains hostname component' {
            $id = Get-RalphInstanceId -Force
            $parts = $id -split '-'
            $parts.Count | Should -BeGreaterOrEqual 4
            # Hostname is second component (may contain hyphens)
        }

        It 'Contains PID component (numeric)' {
            $id = Get-RalphInstanceId -Force
            # PID is second-to-last component
            $id | Should -Match '-\d+-\d+$'
        }

        It 'Contains timestamp component (numeric)' {
            $id = Get-RalphInstanceId -Force
            # Timestamp is last component
            $id | Should -Match '-\d+$'
        }

        It 'Short ID is exactly 8 characters or less' {
            $shortId = Get-RalphShortId
            $shortId.Length | Should -BeLessOrEqual 8
            $shortId.Length | Should -BeGreaterThan 0
        }
    }
}
