#Requires -Version 7.0
<#
.SYNOPSIS
    Queue management functions for Ralph multi-project support.
.DESCRIPTION
    Provides functions for managing a global PRD queue that enables
    cross-project automation. Workers can pick up queued PRDs when their
    current work completes.
#>

function Get-RalphQueueFile {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $globalDir = Get-RalphGlobalDir
    return Join-Path $globalDir 'queue.json'
}

function Get-RalphQueueLock {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $globalDir = Get-RalphGlobalDir
    return Join-Path $globalDir 'queue.lock'
}

function Initialize-RalphQueue {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $globalDir = Get-RalphGlobalDir
    $queueFile = Get-RalphQueueFile

    if (-not (Test-Path $globalDir)) {
        New-Item -Path $globalDir -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path $queueFile)) {
        $queue = @{ entries = @() }
        $queue | ConvertTo-Json -Depth 10 | Set-Content -Path $queueFile -Force
        return $true
    }

    try {
        $content = Get-Content $queueFile -Raw | ConvertFrom-Json
        if (-not $content.entries) { throw "Invalid" }
        return $true
    }
    catch {
        $queue = @{ entries = @() }
        $queue | ConvertTo-Json -Depth 10 | Set-Content -Path $queueFile -Force
        return $true
    }
}

function New-RalphQueueEntryId {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $random = -join ((48..57) + (97..102) | Get-Random -Count 8 | ForEach-Object { [char]$_ })
    return "q-$timestamp-$random"
}

function Add-RalphQueueEntry {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$PrdPath,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter()][int]$Priority = 10
    )

    if (-not (Test-Path $PrdPath)) { throw "PRD file not found: $PrdPath" }
    if (-not (Test-Path $ProjectRoot)) { throw "Project root not found: $ProjectRoot" }

    Initialize-RalphQueue | Out-Null
    $queueFile = Get-RalphQueueFile
    $entryId = New-RalphQueueEntryId
    $entry = @{
        id = $entryId
        prdPath = $PrdPath
        projectRoot = $ProjectRoot
        priority = $Priority
        status = 'pending'
        addedAt = (Get-Date).ToString('o')
        claimedBy = $null
        claimedAt = $null
        completedAt = $null
    }

    $queue = Get-Content $queueFile -Raw | ConvertFrom-Json
    $entries = [System.Collections.ArrayList]@($queue.entries)
    $entries.Add($entry) | Out-Null
    $queue.entries = $entries.ToArray()
    $queue | ConvertTo-Json -Depth 10 | Set-Content -Path $queueFile -Force
    return $entryId
}

function Get-RalphQueueEntries {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [ValidateSet('pending','active','completed','failed','all')]
        [string]$Status = 'all'
    )

    $queueFile = Get-RalphQueueFile
    if (-not (Test-Path $queueFile)) { return @() }
    try {
        $queue = Get-Content $queueFile -Raw | ConvertFrom-Json
        $entries = @($queue.entries)
        if ($Status -ne 'all') {
            $entries = @($entries | Where-Object { $_.status -eq $Status })
        }
        return $entries
    } catch { return @() }
}

function Get-RalphQueueEntry {
    [CmdletBinding()]
    [OutputType([PSObject])]
    param([Parameter(Mandatory)][string]$EntryId)
    $entries = Get-RalphQueueEntries -Status 'all'
    return $entries | Where-Object { $_.id -eq $EntryId } | Select-Object -First 1
}

function Request-RalphQueueEntryClaim {
    [CmdletBinding()]
    [OutputType([PSObject])]
    param([Parameter(Mandatory)][string]$InstanceId)

    $queueFile = Get-RalphQueueFile
    if (-not (Test-Path $queueFile)) { return $null }
    $queue = Get-Content $queueFile -Raw | ConvertFrom-Json
    $entries = [System.Collections.ArrayList]@($queue.entries)
    $pending = $entries | Where-Object { $_.status -eq 'pending' } | Sort-Object priority
    $toClaim = $pending | Select-Object -First 1
    if (-not $toClaim) { return $null }

    $index = 0
    foreach ($e in $entries) {
        if ($e.id -eq $toClaim.id) {
            $entries[$index].status = 'active'
            $entries[$index].claimedBy = $InstanceId
            $entries[$index].claimedAt = (Get-Date).ToString('o')
            break
        }
        $index++
    }
    $queue.entries = $entries.ToArray()
    $queue | ConvertTo-Json -Depth 10 | Set-Content -Path $queueFile -Force
    return Get-RalphQueueEntry -EntryId $toClaim.id
}

function Complete-RalphQueueEntry {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$EntryId,
        [Parameter(Mandatory)][ValidateSet('completed','failed')][string]$Status
    )
    $queueFile = Get-RalphQueueFile
    if (-not (Test-Path $queueFile)) { return $false }
    $queue = Get-Content $queueFile -Raw | ConvertFrom-Json
    $entries = [System.Collections.ArrayList]@($queue.entries)
    $found = $false
    $index = 0
    foreach ($e in $entries) {
        if ($e.id -eq $EntryId) {
            $entries[$index].status = $Status
            $entries[$index].completedAt = (Get-Date).ToString('o')
            $found = $true
            break
        }
        $index++
    }
    if (-not $found) { return $false }
    $queue.entries = $entries.ToArray()
    $queue | ConvertTo-Json -Depth 10 | Set-Content -Path $queueFile -Force
    return $true
}

function Remove-RalphQueueEntry {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$EntryId)
    $queueFile = Get-RalphQueueFile
    if (-not (Test-Path $queueFile)) { return $false }
    $queue = Get-Content $queueFile -Raw | ConvertFrom-Json
    $originalCount = @($queue.entries).Count
    $queue.entries = @($queue.entries | Where-Object { $_.id -ne $EntryId })
    if (@($queue.entries).Count -eq $originalCount) { return $false }
    $queue | ConvertTo-Json -Depth 10 | Set-Content -Path $queueFile -Force
    return $true
}

function Clear-RalphQueueCompleted {
    [CmdletBinding()]
    [OutputType([int])]
    param()
    $queueFile = Get-RalphQueueFile
    if (-not (Test-Path $queueFile)) { return 0 }
    $queue = Get-Content $queueFile -Raw | ConvertFrom-Json
    $originalCount = @($queue.entries).Count
    $queue.entries = @($queue.entries | Where-Object { $_.status -ne 'completed' })
    $cleared = $originalCount - @($queue.entries).Count
    $queue | ConvertTo-Json -Depth 10 | Set-Content -Path $queueFile -Force
    return $cleared
}

function Get-RalphQueueSummary {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $entries = Get-RalphQueueEntries -Status 'all'
    return @{
        total = @($entries).Count
        pending = @($entries | Where-Object { $_.status -eq 'pending' }).Count
        active = @($entries | Where-Object { $_.status -eq 'active' }).Count
        completed = @($entries | Where-Object { $_.status -eq 'completed' }).Count
        failed = @($entries | Where-Object { $_.status -eq 'failed' }).Count
    }
}

function Get-RalphNextQueuedPrd {
    [CmdletBinding()]
    [OutputType([PSObject])]
    param()
    $pending = Get-RalphQueueEntries -Status 'pending' | Sort-Object priority
    return $pending | Select-Object -First 1
}

Export-ModuleMember -Function @(
    'Get-RalphQueueFile'
    'Get-RalphQueueLock'
    'Initialize-RalphQueue'
    'Add-RalphQueueEntry'
    'Get-RalphQueueEntries'
    'Get-RalphQueueEntry'
    'Request-RalphQueueEntryClaim'
    'Complete-RalphQueueEntry'
    'Remove-RalphQueueEntry'
    'Clear-RalphQueueCompleted'
    'Get-RalphQueueSummary'
    'Get-RalphNextQueuedPrd'
)
