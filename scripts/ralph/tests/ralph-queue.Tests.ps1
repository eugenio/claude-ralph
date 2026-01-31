#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for Ralph Queue functions in RalphUtils.psm1.

.DESCRIPTION
    Comprehensive TDD test suite for multi-project PRD queue functionality:
    - Initialize-RalphQueue
    - Add-RalphQueueEntry
    - Get-RalphQueueEntries
    - Get-RalphQueueEntry
    - Request-RalphQueueEntryClaim
    - Complete-RalphQueueEntry
    - Remove-RalphQueueEntry
    - Clear-RalphQueueCompleted
    - Get-RalphQueueSummary
    - Get-RalphNextQueuedPrd

.NOTES
    Tests follow TDD methodology - write tests first, then implement.
#>

BeforeAll {
    # Import the modules under test
    $utilsPath = Join-Path $PSScriptRoot '..' 'RalphUtils.psm1'
    $queuePath = Join-Path $PSScriptRoot '..' 'RalphQueue.psm1'
    Import-Module $utilsPath -Force
    Import-Module $queuePath -Force

    # Helper function to create test PRD
    function New-TestPrd {
        param(
            [string]$FeatureName = 'Test Feature',
            [int]$StoryCount = 3
        )
        $stories = @()
        for ($i = 1; $i -le $StoryCount; $i++) {
            $stories += @{
                id       = "US-$('{0:D3}' -f $i)"
                title    = "Story $i"
                passes   = $false
                priority = $i
            }
        }
        return @{
            featureName = $FeatureName
            branchName  = 'feature/test'
            userStories = $stories
        }
    }
}

# =============================================================================
# GET-RALPHQUEUEFILE TESTS
# =============================================================================

Describe 'Get-RalphQueueFile' {
    Context 'With default global directory' {
        It 'Returns path ending with queue.json' {
            $result = Get-RalphQueueFile
            $result | Should -Match 'queue\.json$'
        }

        It 'Returns path under global directory' {
            $result = Get-RalphQueueFile
            $globalDir = Get-RalphGlobalDir
            $result | Should -Match ([regex]::Escape($globalDir))
        }
    }

    Context 'With custom RALPH_GLOBAL_DIR' {
        BeforeAll {
            $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
            $env:RALPH_GLOBAL_DIR = Join-Path $TestDrive 'custom-global'
        }

        AfterAll {
            $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
        }

        It 'Returns path under custom directory' {
            $result = Get-RalphQueueFile
            $result | Should -Match ([regex]::Escape((Join-Path $TestDrive 'custom-global')))
        }
    }
}

# =============================================================================
# INITIALIZE-RALPHQUEUE TESTS
# =============================================================================

Describe 'Initialize-RalphQueue' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'ralph-queue-test'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    BeforeEach {
        if (Test-Path $script:testGlobalDir) {
            Remove-Item -Path $script:testGlobalDir -Recurse -Force
        }
    }

    Context 'Creating new queue' {
        It 'Creates queue.json file' {
            Initialize-RalphQueue | Should -BeTrue
            $queueFile = Join-Path $script:testGlobalDir 'queue.json'
            Test-Path $queueFile | Should -BeTrue
        }

        It 'Creates valid JSON with entries array' {
            Initialize-RalphQueue | Out-Null
            $queueFile = Join-Path $script:testGlobalDir 'queue.json'
            $content = Get-Content $queueFile -Raw | ConvertFrom-Json
            # Empty arrays in PowerShell can be null-ish, so check PSObject.Properties
            $content.PSObject.Properties.Name | Should -Contain 'entries'
        }

        It 'Creates empty entries array' {
            Initialize-RalphQueue | Out-Null
            $queueFile = Join-Path $script:testGlobalDir 'queue.json'
            $content = Get-Content $queueFile -Raw | ConvertFrom-Json
            $content.entries.Count | Should -Be 0
        }
    }

    Context 'With existing queue' {
        BeforeEach {
            New-Item -Path $script:testGlobalDir -ItemType Directory -Force | Out-Null
            $queueFile = Join-Path $script:testGlobalDir 'queue.json'
            @{ entries = @(@{ id = 'existing'; status = 'pending' }) } |
                ConvertTo-Json -Depth 10 |
                Set-Content -Path $queueFile
        }

        It 'Does not overwrite existing queue' {
            Initialize-RalphQueue | Out-Null
            $queueFile = Join-Path $script:testGlobalDir 'queue.json'
            $content = Get-Content $queueFile -Raw | ConvertFrom-Json
            $content.entries.Count | Should -Be 1
            $content.entries[0].id | Should -Be 'existing'
        }
    }
}

# =============================================================================
# ADD-RALPHQUEUEENTRY TESTS
# =============================================================================

Describe 'Add-RalphQueueEntry' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'ralph-queue-add'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir

        # Create test project directories
        $script:testProject1 = Join-Path $TestDrive 'project1'
        $script:testProject2 = Join-Path $TestDrive 'project2'
        New-Item -Path $script:testProject1 -ItemType Directory -Force | Out-Null
        New-Item -Path $script:testProject2 -ItemType Directory -Force | Out-Null

        # Create PRD files
        $prd1 = New-TestPrd -FeatureName 'Project 1 Feature'
        $prd2 = New-TestPrd -FeatureName 'Project 2 Feature'
        $prd1 | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testProject1 'prd.json')
        $prd2 | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testProject2 'prd.json')
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    BeforeEach {
        if (Test-Path $script:testGlobalDir) {
            Remove-Item -Path $script:testGlobalDir -Recurse -Force
        }
        Initialize-RalphQueue | Out-Null
    }

    Context 'Adding valid entry' {
        It 'Returns entry ID' {
            $prdPath = Join-Path $script:testProject1 'prd.json'
            $result = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject1
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match '^q-\d+-[a-f0-9]+$'
        }

        It 'Creates entry with pending status' {
            $prdPath = Join-Path $script:testProject1 'prd.json'
            $entryId = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject1
            $entry = Get-RalphQueueEntry -EntryId $entryId
            $entry.status | Should -Be 'pending'
        }

        It 'Stores correct prdPath' {
            $prdPath = Join-Path $script:testProject1 'prd.json'
            $entryId = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject1
            $entry = Get-RalphQueueEntry -EntryId $entryId
            $entry.prdPath | Should -Be $prdPath
        }

        It 'Stores correct projectRoot' {
            $prdPath = Join-Path $script:testProject1 'prd.json'
            $entryId = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject1
            $entry = Get-RalphQueueEntry -EntryId $entryId
            $entry.projectRoot | Should -Be $script:testProject1
        }

        It 'Sets default priority of 10' {
            $prdPath = Join-Path $script:testProject1 'prd.json'
            $entryId = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject1
            $entry = Get-RalphQueueEntry -EntryId $entryId
            $entry.priority | Should -Be 10
        }

        It 'Accepts custom priority' {
            $prdPath = Join-Path $script:testProject1 'prd.json'
            $entryId = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject1 -Priority 5
            $entry = Get-RalphQueueEntry -EntryId $entryId
            $entry.priority | Should -Be 5
        }

        It 'Sets addedAt timestamp' {
            $prdPath = Join-Path $script:testProject1 'prd.json'
            $entryId = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject1
            $entry = Get-RalphQueueEntry -EntryId $entryId
            $entry.addedAt | Should -Not -BeNullOrEmpty
        }

        It 'Sets claimedBy to null' {
            $prdPath = Join-Path $script:testProject1 'prd.json'
            $entryId = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject1
            $entry = Get-RalphQueueEntry -EntryId $entryId
            $entry.claimedBy | Should -BeNullOrEmpty
        }
    }

    Context 'Adding multiple entries' {
        It 'Creates unique IDs for each entry' {
            $prdPath1 = Join-Path $script:testProject1 'prd.json'
            $prdPath2 = Join-Path $script:testProject2 'prd.json'

            $id1 = Add-RalphQueueEntry -PrdPath $prdPath1 -ProjectRoot $script:testProject1
            $id2 = Add-RalphQueueEntry -PrdPath $prdPath2 -ProjectRoot $script:testProject2

            $id1 | Should -Not -Be $id2
        }

        It 'Stores multiple entries in queue' {
            $prdPath1 = Join-Path $script:testProject1 'prd.json'
            $prdPath2 = Join-Path $script:testProject2 'prd.json'

            Add-RalphQueueEntry -PrdPath $prdPath1 -ProjectRoot $script:testProject1 | Out-Null
            Add-RalphQueueEntry -PrdPath $prdPath2 -ProjectRoot $script:testProject2 | Out-Null

            $entries = Get-RalphQueueEntries
            $entries.Count | Should -Be 2
        }
    }

    Context 'Error handling' {
        It 'Throws when PRD file does not exist' {
            { Add-RalphQueueEntry -PrdPath '/nonexistent/prd.json' -ProjectRoot $script:testProject1 } |
                Should -Throw
        }

        It 'Throws when project root does not exist' {
            $prdPath = Join-Path $script:testProject1 'prd.json'
            { Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot '/nonexistent/project' } |
                Should -Throw
        }
    }
}

# =============================================================================
# GET-RALPHQUEUEENTRIES TESTS
# =============================================================================

Describe 'Get-RalphQueueEntries' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'ralph-queue-get'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir

        $script:testProject = Join-Path $TestDrive 'project'
        New-Item -Path $script:testProject -ItemType Directory -Force | Out-Null
        $prd = New-TestPrd
        $prd | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testProject 'prd.json')
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    BeforeEach {
        if (Test-Path $script:testGlobalDir) {
            Remove-Item -Path $script:testGlobalDir -Recurse -Force
        }
        Initialize-RalphQueue | Out-Null
    }

    Context 'Empty queue' {
        It 'Returns empty array' {
            $result = @(Get-RalphQueueEntries)
            $result.Count | Should -Be 0
        }
    }

    Context 'With entries' {
        BeforeEach {
            $prdPath = Join-Path $script:testProject 'prd.json'
            Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject | Out-Null
            Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject | Out-Null
        }

        It 'Returns all entries by default' {
            $result = Get-RalphQueueEntries
            $result.Count | Should -Be 2
        }

        It 'Returns entries with status filter - pending' {
            $result = Get-RalphQueueEntries -Status 'pending'
            $result.Count | Should -Be 2
        }

        It 'Returns empty for non-matching status' {
            $result = Get-RalphQueueEntries -Status 'completed'
            $result.Count | Should -Be 0
        }
    }

    Context 'Status filtering' {
        BeforeEach {
            $prdPath = Join-Path $script:testProject 'prd.json'
            $id1 = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject
            $id2 = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject
            $id3 = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject

            # Set different statuses
            Complete-RalphQueueEntry -EntryId $id2 -Status 'completed'
            Complete-RalphQueueEntry -EntryId $id3 -Status 'failed'
        }

        It 'Filters by pending status' {
            $result = Get-RalphQueueEntries -Status 'pending'
            $result.Count | Should -Be 1
        }

        It 'Filters by completed status' {
            $result = Get-RalphQueueEntries -Status 'completed'
            $result.Count | Should -Be 1
        }

        It 'Filters by failed status' {
            $result = Get-RalphQueueEntries -Status 'failed'
            $result.Count | Should -Be 1
        }

        It 'Returns all with status all' {
            $result = Get-RalphQueueEntries -Status 'all'
            $result.Count | Should -Be 3
        }
    }
}

# =============================================================================
# GET-RALPHQUEUEENTRY TESTS
# =============================================================================

Describe 'Get-RalphQueueEntry' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'ralph-queue-entry'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir

        $script:testProject = Join-Path $TestDrive 'project'
        New-Item -Path $script:testProject -ItemType Directory -Force | Out-Null
        $prd = New-TestPrd
        $prd | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testProject 'prd.json')
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    BeforeEach {
        if (Test-Path $script:testGlobalDir) {
            Remove-Item -Path $script:testGlobalDir -Recurse -Force
        }
        Initialize-RalphQueue | Out-Null
    }

    Context 'Valid entry ID' {
        It 'Returns entry object' {
            $prdPath = Join-Path $script:testProject 'prd.json'
            $entryId = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject
            $result = Get-RalphQueueEntry -EntryId $entryId
            $result | Should -Not -BeNull
        }

        It 'Returns entry with correct ID' {
            $prdPath = Join-Path $script:testProject 'prd.json'
            $entryId = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject
            $result = Get-RalphQueueEntry -EntryId $entryId
            $result.id | Should -Be $entryId
        }
    }

    Context 'Invalid entry ID' {
        It 'Returns null for non-existent ID' {
            $result = Get-RalphQueueEntry -EntryId 'nonexistent-id'
            $result | Should -BeNull
        }
    }
}

# =============================================================================
# REQUEST-RALPHQUEUEENTRYCLAIM TESTS
# =============================================================================

Describe 'Request-RalphQueueEntryClaim' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'ralph-queue-claim'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir

        $script:testProject1 = Join-Path $TestDrive 'project1'
        $script:testProject2 = Join-Path $TestDrive 'project2'
        New-Item -Path $script:testProject1 -ItemType Directory -Force | Out-Null
        New-Item -Path $script:testProject2 -ItemType Directory -Force | Out-Null

        $prd = New-TestPrd
        $prd | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testProject1 'prd.json')
        $prd | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testProject2 'prd.json')
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    BeforeEach {
        if (Test-Path $script:testGlobalDir) {
            Remove-Item -Path $script:testGlobalDir -Recurse -Force
        }
        Initialize-RalphQueue | Out-Null
    }

    Context 'Claiming from non-empty queue' {
        BeforeEach {
            $prdPath = Join-Path $script:testProject1 'prd.json'
            Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject1 | Out-Null
        }

        It 'Returns claimed entry' {
            $result = Request-RalphQueueEntryClaim -InstanceId 'test-instance-1'
            $result | Should -Not -BeNull
        }

        It 'Sets claimedBy to instance ID' {
            $result = Request-RalphQueueEntryClaim -InstanceId 'test-instance-1'
            $result.claimedBy | Should -Be 'test-instance-1'
        }

        It 'Sets status to active' {
            $result = Request-RalphQueueEntryClaim -InstanceId 'test-instance-1'
            $result.status | Should -Be 'active'
        }

        It 'Sets claimedAt timestamp' {
            $result = Request-RalphQueueEntryClaim -InstanceId 'test-instance-1'
            $result.claimedAt | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Priority ordering' {
        BeforeEach {
            $prdPath1 = Join-Path $script:testProject1 'prd.json'
            $prdPath2 = Join-Path $script:testProject2 'prd.json'
            Add-RalphQueueEntry -PrdPath $prdPath1 -ProjectRoot $script:testProject1 -Priority 5 | Out-Null
            Add-RalphQueueEntry -PrdPath $prdPath2 -ProjectRoot $script:testProject2 -Priority 1 | Out-Null
        }

        It 'Claims highest priority entry first (lowest number)' {
            $result = Request-RalphQueueEntryClaim -InstanceId 'test-instance-1'
            $result.projectRoot | Should -Be $script:testProject2
        }
    }

    Context 'Empty queue' {
        It 'Returns null when queue is empty' {
            $result = Request-RalphQueueEntryClaim -InstanceId 'test-instance-1'
            $result | Should -BeNull
        }
    }

    Context 'All entries claimed' {
        BeforeEach {
            $prdPath = Join-Path $script:testProject1 'prd.json'
            Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject1 | Out-Null
            Request-RalphQueueEntryClaim -InstanceId 'worker-1' | Out-Null
        }

        It 'Returns null when all entries are claimed' {
            $result = Request-RalphQueueEntryClaim -InstanceId 'worker-2'
            $result | Should -BeNull
        }
    }

    Context 'Multiple workers' {
        BeforeEach {
            $prdPath1 = Join-Path $script:testProject1 'prd.json'
            $prdPath2 = Join-Path $script:testProject2 'prd.json'
            Add-RalphQueueEntry -PrdPath $prdPath1 -ProjectRoot $script:testProject1 | Out-Null
            Add-RalphQueueEntry -PrdPath $prdPath2 -ProjectRoot $script:testProject2 | Out-Null
        }

        It 'Different workers claim different entries' {
            $claim1 = Request-RalphQueueEntryClaim -InstanceId 'worker-1'
            $claim2 = Request-RalphQueueEntryClaim -InstanceId 'worker-2'

            $claim1.id | Should -Not -Be $claim2.id
            $claim1.projectRoot | Should -Not -Be $claim2.projectRoot
        }
    }
}

# =============================================================================
# COMPLETE-RALPHQUEUEENTRY TESTS
# =============================================================================

Describe 'Complete-RalphQueueEntry' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'ralph-queue-complete'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir

        $script:testProject = Join-Path $TestDrive 'project'
        New-Item -Path $script:testProject -ItemType Directory -Force | Out-Null
        $prd = New-TestPrd
        $prd | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testProject 'prd.json')
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    BeforeEach {
        if (Test-Path $script:testGlobalDir) {
            Remove-Item -Path $script:testGlobalDir -Recurse -Force
        }
        Initialize-RalphQueue | Out-Null
    }

    Context 'Marking as completed' {
        BeforeEach {
            $prdPath = Join-Path $script:testProject 'prd.json'
            $script:entryId = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject
        }

        It 'Sets status to completed' {
            Complete-RalphQueueEntry -EntryId $script:entryId -Status 'completed'
            $entry = Get-RalphQueueEntry -EntryId $script:entryId
            $entry.status | Should -Be 'completed'
        }

        It 'Sets completedAt timestamp' {
            Complete-RalphQueueEntry -EntryId $script:entryId -Status 'completed'
            $entry = Get-RalphQueueEntry -EntryId $script:entryId
            $entry.completedAt | Should -Not -BeNullOrEmpty
        }

        It 'Returns true on success' {
            $result = Complete-RalphQueueEntry -EntryId $script:entryId -Status 'completed'
            $result | Should -BeTrue
        }
    }

    Context 'Marking as failed' {
        BeforeEach {
            $prdPath = Join-Path $script:testProject 'prd.json'
            $script:entryId = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject
        }

        It 'Sets status to failed' {
            Complete-RalphQueueEntry -EntryId $script:entryId -Status 'failed'
            $entry = Get-RalphQueueEntry -EntryId $script:entryId
            $entry.status | Should -Be 'failed'
        }
    }

    Context 'Invalid entry' {
        It 'Returns false for non-existent entry' {
            $result = Complete-RalphQueueEntry -EntryId 'nonexistent' -Status 'completed'
            $result | Should -BeFalse
        }
    }
}

# =============================================================================
# REMOVE-RALPHQUEUEENTRY TESTS
# =============================================================================

Describe 'Remove-RalphQueueEntry' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'ralph-queue-remove'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir

        $script:testProject = Join-Path $TestDrive 'project'
        New-Item -Path $script:testProject -ItemType Directory -Force | Out-Null
        $prd = New-TestPrd
        $prd | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testProject 'prd.json')
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    BeforeEach {
        if (Test-Path $script:testGlobalDir) {
            Remove-Item -Path $script:testGlobalDir -Recurse -Force
        }
        Initialize-RalphQueue | Out-Null
    }

    Context 'Removing existing entry' {
        BeforeEach {
            $prdPath = Join-Path $script:testProject 'prd.json'
            $script:entryId = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject
        }

        It 'Returns true on success' {
            $result = Remove-RalphQueueEntry -EntryId $script:entryId
            $result | Should -BeTrue
        }

        It 'Entry no longer exists' {
            Remove-RalphQueueEntry -EntryId $script:entryId | Out-Null
            $entry = Get-RalphQueueEntry -EntryId $script:entryId
            $entry | Should -BeNull
        }

        It 'Decreases entry count' {
            $before = (Get-RalphQueueEntries).Count
            Remove-RalphQueueEntry -EntryId $script:entryId | Out-Null
            $after = (Get-RalphQueueEntries).Count
            $after | Should -Be ($before - 1)
        }
    }

    Context 'Removing non-existent entry' {
        It 'Returns false for non-existent entry' {
            $result = Remove-RalphQueueEntry -EntryId 'nonexistent'
            $result | Should -BeFalse
        }
    }
}

# =============================================================================
# CLEAR-RALPHQUEUECOMPLETED TESTS
# =============================================================================

Describe 'Clear-RalphQueueCompleted' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'ralph-queue-clear'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir

        $script:testProject = Join-Path $TestDrive 'project'
        New-Item -Path $script:testProject -ItemType Directory -Force | Out-Null
        $prd = New-TestPrd
        $prd | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testProject 'prd.json')
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    BeforeEach {
        if (Test-Path $script:testGlobalDir) {
            Remove-Item -Path $script:testGlobalDir -Recurse -Force
        }
        Initialize-RalphQueue | Out-Null
    }

    Context 'Queue with completed entries' {
        BeforeEach {
            $prdPath = Join-Path $script:testProject 'prd.json'
            $id1 = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject
            $id2 = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject
            $id3 = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject

            Complete-RalphQueueEntry -EntryId $id1 -Status 'completed'
            Complete-RalphQueueEntry -EntryId $id2 -Status 'completed'
            # id3 stays pending
        }

        It 'Returns count of cleared entries' {
            $result = Clear-RalphQueueCompleted
            $result | Should -Be 2
        }

        It 'Removes completed entries' {
            Clear-RalphQueueCompleted | Out-Null
            $completed = Get-RalphQueueEntries -Status 'completed'
            $completed.Count | Should -Be 0
        }

        It 'Keeps pending entries' {
            Clear-RalphQueueCompleted | Out-Null
            $pending = Get-RalphQueueEntries -Status 'pending'
            $pending.Count | Should -Be 1
        }
    }

    Context 'Queue with no completed entries' {
        BeforeEach {
            $prdPath = Join-Path $script:testProject 'prd.json'
            Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject | Out-Null
        }

        It 'Returns 0' {
            $result = Clear-RalphQueueCompleted
            $result | Should -Be 0
        }
    }

    Context 'Empty queue' {
        It 'Returns 0 for empty queue' {
            $result = Clear-RalphQueueCompleted
            $result | Should -Be 0
        }
    }
}

# =============================================================================
# GET-RALPHQUEUESUMMARY TESTS
# =============================================================================

Describe 'Get-RalphQueueSummary' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'ralph-queue-summary'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir

        $script:testProject = Join-Path $TestDrive 'project'
        New-Item -Path $script:testProject -ItemType Directory -Force | Out-Null
        $prd = New-TestPrd
        $prd | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testProject 'prd.json')
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    BeforeEach {
        if (Test-Path $script:testGlobalDir) {
            Remove-Item -Path $script:testGlobalDir -Recurse -Force
        }
        Initialize-RalphQueue | Out-Null
    }

    Context 'Empty queue' {
        It 'Returns all zeros' {
            $result = Get-RalphQueueSummary
            $result.total | Should -Be 0
            $result.pending | Should -Be 0
            $result.active | Should -Be 0
            $result.completed | Should -Be 0
            $result.failed | Should -Be 0
        }
    }

    Context 'Queue with mixed statuses' {
        BeforeEach {
            $prdPath = Join-Path $script:testProject 'prd.json'
            $id1 = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject
            $id2 = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject
            $id3 = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject
            $id4 = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject

            Request-RalphQueueEntryClaim -InstanceId 'worker-1' | Out-Null  # Makes id1 active (lowest prio first)
            Complete-RalphQueueEntry -EntryId $id2 -Status 'completed'
            Complete-RalphQueueEntry -EntryId $id3 -Status 'failed'
            # id4 stays pending
        }

        It 'Returns correct total' {
            $result = Get-RalphQueueSummary
            $result.total | Should -Be 4
        }

        It 'Returns correct pending count' {
            $result = Get-RalphQueueSummary
            $result.pending | Should -Be 1
        }

        It 'Returns correct active count' {
            $result = Get-RalphQueueSummary
            $result.active | Should -Be 1
        }

        It 'Returns correct completed count' {
            $result = Get-RalphQueueSummary
            $result.completed | Should -Be 1
        }

        It 'Returns correct failed count' {
            $result = Get-RalphQueueSummary
            $result.failed | Should -Be 1
        }
    }
}

# =============================================================================
# GET-RALPHNEXTQUEUEDPRD TESTS
# =============================================================================

Describe 'Get-RalphNextQueuedPrd' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'ralph-queue-next'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir

        $script:testProject1 = Join-Path $TestDrive 'project1'
        $script:testProject2 = Join-Path $TestDrive 'project2'
        New-Item -Path $script:testProject1 -ItemType Directory -Force | Out-Null
        New-Item -Path $script:testProject2 -ItemType Directory -Force | Out-Null

        $prd = New-TestPrd
        $prd | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testProject1 'prd.json')
        $prd | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testProject2 'prd.json')
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    BeforeEach {
        if (Test-Path $script:testGlobalDir) {
            Remove-Item -Path $script:testGlobalDir -Recurse -Force
        }
        Initialize-RalphQueue | Out-Null
    }

    Context 'Empty queue' {
        It 'Returns null' {
            $result = Get-RalphNextQueuedPrd
            $result | Should -BeNull
        }
    }

    Context 'Queue with pending entries' {
        BeforeEach {
            $prdPath = Join-Path $script:testProject1 'prd.json'
            Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject1 | Out-Null
        }

        It 'Returns pending entry' {
            $result = Get-RalphNextQueuedPrd
            $result | Should -Not -BeNull
            $result.prdPath | Should -Be (Join-Path $script:testProject1 'prd.json')
        }
    }

    Context 'Priority ordering' {
        BeforeEach {
            $prdPath1 = Join-Path $script:testProject1 'prd.json'
            $prdPath2 = Join-Path $script:testProject2 'prd.json'
            Add-RalphQueueEntry -PrdPath $prdPath1 -ProjectRoot $script:testProject1 -Priority 5 | Out-Null
            Add-RalphQueueEntry -PrdPath $prdPath2 -ProjectRoot $script:testProject2 -Priority 1 | Out-Null
        }

        It 'Returns highest priority entry (lowest number)' {
            $result = Get-RalphNextQueuedPrd
            $result.projectRoot | Should -Be $script:testProject2
        }
    }

    Context 'Skips active entries' {
        BeforeEach {
            $prdPath1 = Join-Path $script:testProject1 'prd.json'
            $prdPath2 = Join-Path $script:testProject2 'prd.json'
            Add-RalphQueueEntry -PrdPath $prdPath1 -ProjectRoot $script:testProject1 | Out-Null
            Add-RalphQueueEntry -PrdPath $prdPath2 -ProjectRoot $script:testProject2 | Out-Null

            # Claim first entry
            Request-RalphQueueEntryClaim -InstanceId 'worker-1' | Out-Null
        }

        It 'Returns next pending entry' {
            $result = Get-RalphNextQueuedPrd
            $result.projectRoot | Should -Be $script:testProject2
        }
    }

    Context 'Skips completed entries' {
        BeforeEach {
            $prdPath1 = Join-Path $script:testProject1 'prd.json'
            $prdPath2 = Join-Path $script:testProject2 'prd.json'
            $id1 = Add-RalphQueueEntry -PrdPath $prdPath1 -ProjectRoot $script:testProject1
            Add-RalphQueueEntry -PrdPath $prdPath2 -ProjectRoot $script:testProject2 | Out-Null

            Complete-RalphQueueEntry -EntryId $id1 -Status 'completed'
        }

        It 'Returns pending entry' {
            $result = Get-RalphNextQueuedPrd
            $result.projectRoot | Should -Be $script:testProject2
        }
    }
}

# =============================================================================
# WORKER INTEGRATION TESTS
# =============================================================================

Describe 'Worker Queue Integration' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'ralph-queue-worker'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir

        $script:testProject1 = Join-Path $TestDrive 'project1'
        $script:testProject2 = Join-Path $TestDrive 'project2'
        $script:testProject3 = Join-Path $TestDrive 'project3'

        foreach ($proj in @($script:testProject1, $script:testProject2, $script:testProject3)) {
            New-Item -Path $proj -ItemType Directory -Force | Out-Null
            $prd = New-TestPrd -FeatureName "Feature for $(Split-Path $proj -Leaf)"
            $prd | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $proj 'prd.json')
        }
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    BeforeEach {
        if (Test-Path $script:testGlobalDir) {
            Remove-Item -Path $script:testGlobalDir -Recurse -Force
        }
        Initialize-RalphQueue | Out-Null
    }

    Context 'Worker continues to next PRD' {
        It 'Worker can claim, complete, and get next entry' {
            # Setup: Add two PRDs
            $prd1 = Join-Path $script:testProject1 'prd.json'
            $prd2 = Join-Path $script:testProject2 'prd.json'
            $id1 = Add-RalphQueueEntry -PrdPath $prd1 -ProjectRoot $script:testProject1
            Add-RalphQueueEntry -PrdPath $prd2 -ProjectRoot $script:testProject2 | Out-Null

            # Worker claims first
            $claim1 = Request-RalphQueueEntryClaim -InstanceId 'worker-1'
            $claim1 | Should -Not -BeNull

            # Worker completes first
            Complete-RalphQueueEntry -EntryId $id1 -Status 'completed' | Should -BeTrue

            # Worker claims next
            $claim2 = Request-RalphQueueEntryClaim -InstanceId 'worker-1'
            $claim2 | Should -Not -BeNull
            $claim2.projectRoot | Should -Be $script:testProject2
        }
    }

    Context 'Multiple workers process queue' {
        It 'Three workers claim three different entries' {
            # Setup: Add three PRDs
            foreach ($proj in @($script:testProject1, $script:testProject2, $script:testProject3)) {
                $prd = Join-Path $proj 'prd.json'
                Add-RalphQueueEntry -PrdPath $prd -ProjectRoot $proj | Out-Null
            }

            # Three workers claim
            $claim1 = Request-RalphQueueEntryClaim -InstanceId 'worker-1'
            $claim2 = Request-RalphQueueEntryClaim -InstanceId 'worker-2'
            $claim3 = Request-RalphQueueEntryClaim -InstanceId 'worker-3'

            # All should get different projects
            $projects = @($claim1.projectRoot, $claim2.projectRoot, $claim3.projectRoot) | Sort-Object -Unique
            $projects.Count | Should -Be 3
        }
    }

    Context 'Worker stops when queue empty' {
        It 'Returns null after all entries processed' {
            $prd = Join-Path $script:testProject1 'prd.json'
            $id = Add-RalphQueueEntry -PrdPath $prd -ProjectRoot $script:testProject1

            # Claim and complete
            Request-RalphQueueEntryClaim -InstanceId 'worker-1' | Out-Null
            Complete-RalphQueueEntry -EntryId $id -Status 'completed' | Out-Null

            # Should get nothing now
            $result = Request-RalphQueueEntryClaim -InstanceId 'worker-1'
            $result | Should -BeNull
        }
    }
}

# =============================================================================
# EDGE CASES
# =============================================================================

Describe 'Queue Edge Cases' {
    BeforeAll {
        $script:testGlobalDir = Join-Path $TestDrive 'ralph-queue-edge'
        $script:originalGlobalDir = $env:RALPH_GLOBAL_DIR
        $env:RALPH_GLOBAL_DIR = $script:testGlobalDir

        $script:testProject = Join-Path $TestDrive 'project'
        New-Item -Path $script:testProject -ItemType Directory -Force | Out-Null
        $prd = New-TestPrd
        $prd | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testProject 'prd.json')
    }

    AfterAll {
        $env:RALPH_GLOBAL_DIR = $script:originalGlobalDir
    }

    BeforeEach {
        if (Test-Path $script:testGlobalDir) {
            Remove-Item -Path $script:testGlobalDir -Recurse -Force
        }
        # Ensure project and PRD exist for each test
        if (-not (Test-Path $script:testProject)) {
            New-Item -Path $script:testProject -ItemType Directory -Force | Out-Null
        }
        $prd = New-TestPrd
        $prd | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testProject 'prd.json')
    }

    Context 'Corrupted queue file' {
        It 'Initialize-RalphQueue handles corrupted JSON' {
            New-Item -Path $script:testGlobalDir -ItemType Directory -Force | Out-Null
            'not valid json {{{' | Set-Content (Join-Path $script:testGlobalDir 'queue.json')

            # Should not throw, should reinitialize
            { Initialize-RalphQueue } | Should -Not -Throw
        }
    }

    Context 'Missing PRD file after queue entry' {
        It 'Claim still works even if PRD deleted' {
            Initialize-RalphQueue | Out-Null
            $prdPath = Join-Path $script:testProject 'prd.json'
            Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject | Out-Null

            # Delete PRD
            Remove-Item $prdPath -Force

            # Claim should still work
            $result = Request-RalphQueueEntryClaim -InstanceId 'worker-1'
            $result | Should -Not -BeNull
        }
    }

    Context 'Same PRD added multiple times' {
        It 'Allows duplicate PRD entries' {
            Initialize-RalphQueue | Out-Null
            $prdPath = Join-Path $script:testProject 'prd.json'

            $id1 = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject
            $id2 = Add-RalphQueueEntry -PrdPath $prdPath -ProjectRoot $script:testProject

            $id1 | Should -Not -Be $id2
            (Get-RalphQueueEntries).Count | Should -Be 2
        }
    }
}

AfterAll {
    Remove-Module RalphUtils -ErrorAction SilentlyContinue
}
