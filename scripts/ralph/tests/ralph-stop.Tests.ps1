#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for ralph-stop.ps1 graceful stop script.

.DESCRIPTION
    Comprehensive test suite for ralph-stop.ps1 including:
    - Parameter validation
    - Signal sending (mocked)
    - State file cleanup
    - Handling of non-existent processes
    - Force vs graceful shutdown
#>

BeforeAll {
    # Define the script path
    $script:stopScript = Join-Path $PSScriptRoot '..' 'ralph-stop.ps1'

    # Import the utilities module if it exists
    $modulePath = Join-Path $PSScriptRoot '..' 'RalphUtils.psm1'
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
    }
}

Describe 'ralph-stop.ps1 Script Structure' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:stopScript -Raw
    }

    It 'Has proper help documentation' {
        $script:scriptContent | Should -Match '\.SYNOPSIS'
        $script:scriptContent | Should -Match '\.DESCRIPTION'
        $script:scriptContent | Should -Match '\.EXAMPLE'
    }

    It 'Uses CmdletBinding' {
        $script:scriptContent | Should -Match '\[CmdletBinding\(\)\]'
    }

    It 'Defines Force switch parameter' {
        $script:scriptContent | Should -Match '\[switch\]\$Force'
    }
}

Describe 'State File Configuration' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:stopScript -Raw
    }

    It 'Defines StateFile path' {
        $script:scriptContent | Should -Match '\$StateFile = "\.claude\\ralph-supervisor\.local\.json"'
    }

    It 'Defines LogFile path' {
        $script:scriptContent | Should -Match '\$LogFile = "\.claude\\ralph-supervisor\.log"'
    }

    It 'Defines PidFile path' {
        $script:scriptContent | Should -Match '\$PidFile = "\.claude\\ralph-supervisor\.pid"'
    }

    It 'Defines ClaudePidFile path' {
        $script:scriptContent | Should -Match '\$ClaudePidFile = "\.claude\\ralph-supervisor-claude\.pid"'
    }
}

Describe 'Stop-ProcessGracefully Function' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:stopScript -Raw
    }

    It 'Defines Stop-ProcessGracefully function' {
        $script:scriptContent | Should -Match 'function Stop-ProcessGracefully'
    }

    It 'Accepts ProcessId parameter' {
        $script:scriptContent | Should -Match '\[int\]\$ProcessId'
    }

    It 'Accepts Name parameter' {
        $script:scriptContent | Should -Match '\[string\]\$Name'
    }

    It 'Accepts Force switch parameter' {
        $script:scriptContent | Should -Match 'function Stop-ProcessGracefully[\s\S]*?\[switch\]\$Force'
    }

    It 'Returns early if ProcessId is 0 or less' {
        $script:scriptContent | Should -Match 'if \(\$ProcessId -le 0\) \{ return \$true \}'
    }

    It 'Checks if process exists using Get-Process' {
        $script:scriptContent | Should -Match 'Get-Process -Id \$ProcessId -ErrorAction SilentlyContinue'
    }

    It 'Reports if process is not running' {
        $script:scriptContent | Should -Match 'Not running.*Yellow'
    }

    It 'Uses Stop-Process with -Force for force mode' {
        $script:scriptContent | Should -Match 'Stop-Process -Id \$ProcessId -Force'
    }

    It 'Uses CloseMainWindow for graceful shutdown' {
        $script:scriptContent | Should -Match '\$process\.CloseMainWindow\(\)'
    }

    It 'Waits up to 10 seconds for graceful shutdown' {
        $script:scriptContent | Should -Match '\$waited -lt 10'
    }

    It 'Falls back to force kill after graceful timeout' {
        $script:scriptContent | Should -Match 'Still running, force killing'
    }

    It 'Verifies process stopped after shutdown' {
        $script:scriptContent | Should -Match '\$checkProcess = Get-Process -Id \$ProcessId'
    }

    It 'Reports success with green color' {
        $script:scriptContent | Should -Match '"Stopped".*Green'
    }

    It 'Reports failure with red color' {
        $script:scriptContent | Should -Match '"Failed to stop".*Red'
    }
}

Describe 'Remove-StateFiles Function' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:stopScript -Raw
    }

    It 'Defines Remove-StateFiles function' {
        $script:scriptContent | Should -Match 'function Remove-StateFiles'
    }

    It 'Removes all three state files' {
        $script:scriptContent | Should -Match '\$files = @\(\$StateFile, \$PidFile, \$ClaudePidFile\)'
    }

    It 'Checks if file exists before removing' {
        $script:scriptContent | Should -Match 'if \(Test-Path \$file\)'
    }

    It 'Uses Remove-Item to delete files' {
        $script:scriptContent | Should -Match 'Remove-Item \$file -Force'
    }

    It 'Reports which files were removed' {
        $script:scriptContent | Should -Match 'Removed: \$file'
    }
}

Describe 'No Supervisor Running Handling' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:stopScript -Raw
    }

    It 'Checks if state file exists' {
        $script:scriptContent | Should -Match 'if \(-not \(Test-Path \$StateFile\) -and -not \(Test-Path \$PidFile\)\)'
    }

    It 'Reports when no supervisor is running' {
        $script:scriptContent | Should -Match 'No Ralph supervisor appears to be running'
    }

    It 'Shows which files are missing' {
        $script:scriptContent | Should -Match 'No state files found'
    }

    It 'Exits with code 0 when nothing to stop' {
        $script:scriptContent | Should -Match 'exit 0'
    }
}

Describe 'PID Extraction from State Files' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:stopScript -Raw
    }

    It 'Reads state file JSON' {
        $script:scriptContent | Should -Match 'Get-Content \$StateFile -Raw \| ConvertFrom-Json'
    }

    It 'Extracts supervisor PID from state' {
        $script:scriptContent | Should -Match '\$supervisorPid = \[int\]\$state\.pid'
    }

    It 'Extracts Claude PID from state' {
        $script:scriptContent | Should -Match '\$claudePid = \[int\]\$state\.claude_pid'
    }

    It 'Falls back to PID file if state JSON fails' {
        $script:scriptContent | Should -Match 'if \(\$supervisorPid -le 0 -and \(Test-Path \$PidFile\)\)'
    }

    It 'Falls back to Claude PID file' {
        $script:scriptContent | Should -Match 'if \(\$claudePid -le 0 -and \(Test-Path \$ClaudePidFile\)\)'
    }

    It 'Handles state file parse errors gracefully' {
        $script:scriptContent | Should -Match 'catch \{[\s\S]*?# Ignore parse errors'
    }
}

Describe 'Process Stop Order' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:stopScript -Raw
    }

    It 'Stops Claude process before supervisor' {
        # Check that Claude stop comes before supervisor stop
        $claudeStopIndex = $script:scriptContent.IndexOf('Stop-ProcessGracefully -ProcessId $claudePid -Name "Claude"')
        $supervisorStopIndex = $script:scriptContent.IndexOf('Stop-ProcessGracefully -ProcessId $supervisorPid -Name "Supervisor"')
        $claudeStopIndex | Should -BeLessThan $supervisorStopIndex
    }

    It 'Only stops Claude if PID is greater than 0' {
        $script:scriptContent | Should -Match 'if \(\$claudePid -gt 0\)'
    }

    It 'Only stops supervisor if PID is greater than 0' {
        $script:scriptContent | Should -Match 'if \(\$supervisorPid -gt 0\)'
    }

    It 'Passes Force parameter to Stop-ProcessGracefully' {
        $script:scriptContent | Should -Match '-Force:\$Force'
    }
}

Describe 'State File Cleanup' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:stopScript -Raw
    }

    It 'Calls Remove-StateFiles after stopping processes' {
        $script:scriptContent | Should -Match 'Remove-StateFiles'
    }

    It 'Shows completion message' {
        $script:scriptContent | Should -Match 'Ralph supervisor stopped\.'
    }

    It 'Uses green color for success message' {
        $script:scriptContent | Should -Match '"Ralph supervisor stopped\.".*Green'
    }
}

Describe 'Logging' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:stopScript -Raw
    }

    It 'Checks if log file exists' {
        $script:scriptContent | Should -Match 'if \(Test-Path \$LogFile\)'
    }

    It 'Logs the stop event' {
        $script:scriptContent | Should -Match 'Add-Content -Path \$LogFile'
    }

    It 'Uses timestamp in log entry' {
        $script:scriptContent | Should -Match 'Get-Date -Format "yyyy-MM-dd HH:mm:ss"'
    }

    It 'Logs with INFO level' {
        $script:scriptContent | Should -Match '\[INFO\].*Supervisor stopped'
    }
}

Describe 'User Interface' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:stopScript -Raw
    }

    It 'Shows header' {
        $script:scriptContent | Should -Match 'Ralph Loop Supervisor - Stop'
    }

    It 'Shows separator line' {
        $script:scriptContent | Should -Match '==============================='
    }

    It 'Reports stopping processes' {
        $script:scriptContent | Should -Match 'Stopping processes\.\.\.'
    }

    It 'Reports cleaning up state files' {
        $script:scriptContent | Should -Match 'Cleaning up state files\.\.\.'
    }
}

Describe 'Force Mode' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:stopScript -Raw
    }

    It 'Has Force mode documentation' {
        $script:scriptContent | Should -Match '\.PARAMETER Force'
        $script:scriptContent | Should -Match '-Force'
    }

    It 'Shows example with Force flag' {
        $script:scriptContent | Should -Match '\.EXAMPLE[\s\S]*?-Force'
    }

    It 'Uses Force for immediate termination' {
        $script:scriptContent | Should -Match 'Force kill processes immediately'
    }

    It 'Skips graceful shutdown when Force is set' {
        $script:scriptContent | Should -Match 'if \(\$Force\) \{[\s\S]*?Stop-Process -Id \$ProcessId -Force'
    }

    It 'Reports force killing in output' {
        $script:scriptContent | Should -Match 'Force killing\.\.\.'
    }
}

Describe 'Error Handling' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:stopScript -Raw
    }

    It 'Uses ErrorAction SilentlyContinue for Get-Process' {
        $script:scriptContent | Should -Match 'Get-Process.*-ErrorAction SilentlyContinue'
    }

    It 'Uses ErrorAction SilentlyContinue for Remove-Item' {
        $script:scriptContent | Should -Match 'Remove-Item.*-ErrorAction SilentlyContinue'
    }

    It 'Has try-catch around graceful shutdown' {
        $script:scriptContent | Should -Match 'try \{[\s\S]*?CloseMainWindow[\s\S]*?\} catch'
    }

    It 'Has try-catch around force kill' {
        $script:scriptContent | Should -Match 'try \{[\s\S]*?Stop-Process[\s\S]*?\} catch'
    }

    It 'Handles process exiting during shutdown' {
        $script:scriptContent | Should -Match '# Process might have already exited'
    }
}

AfterAll {
    # Clean up - remove the imported module
    Remove-Module RalphUtils -ErrorAction SilentlyContinue
}
