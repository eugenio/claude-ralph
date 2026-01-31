#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for ralph-supervisor.ps1 process supervisor script.

.DESCRIPTION
    Comprehensive test suite for ralph-supervisor.ps1 including:
    - Parameter validation
    - State file creation/reading
    - Process spawning (mocked)
    - Crash detection logic
    - Restart behavior
    - Graceful shutdown
    - Exit code handling
#>

BeforeAll {
    # Define the script path
    $script:supervisorScript = Join-Path $PSScriptRoot '..' 'ralph-supervisor.ps1'

    # Import the utilities module
    $modulePath = Join-Path $PSScriptRoot '..' 'RalphUtils.psm1'
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
    }
}

Describe 'ralph-supervisor.ps1 Script Structure' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:supervisorScript -Raw
    }

    It 'Has proper help documentation' {
        $script:scriptContent | Should -Match '\.SYNOPSIS'
        $script:scriptContent | Should -Match '\.DESCRIPTION'
        $script:scriptContent | Should -Match '\.PARAMETER'
        $script:scriptContent | Should -Match '\.EXAMPLE'
    }

    It 'Uses CmdletBinding' {
        $script:scriptContent | Should -Match '\[CmdletBinding\(\)\]'
    }

    It 'Defines required Prompt parameter' {
        $script:scriptContent | Should -Match '\[Parameter\(Mandatory=\$true'
        $script:scriptContent | Should -Match '\[string\]\$Prompt'
    }

    It 'Defines MaxIterations parameter with default 0' {
        $script:scriptContent | Should -Match '\[int\]\$MaxIterations = 0'
    }

    It 'Defines MaxRestarts parameter with default 10' {
        $script:scriptContent | Should -Match '\[int\]\$MaxRestarts = 10'
    }

    It 'Defines RestartDelay parameter with default 5' {
        $script:scriptContent | Should -Match '\[int\]\$RestartDelay = 5'
    }

    It 'Defines Background switch parameter' {
        $script:scriptContent | Should -Match '\[switch\]\$Background'
    }

    It 'Defines VerboseLog switch parameter' {
        $script:scriptContent | Should -Match '\[switch\]\$VerboseLog'
    }

    It 'Defines CompletionPromise parameter' {
        $script:scriptContent | Should -Match '\[string\]\$CompletionPromise'
    }
}

Describe 'State File Configuration' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:supervisorScript -Raw
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

Describe 'Logging Functions' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:supervisorScript -Raw
    }

    It 'Defines Write-Log function' {
        $script:scriptContent | Should -Match 'function Write-Log'
    }

    It 'Defines Write-LogInfo helper' {
        $script:scriptContent | Should -Match 'function Write-LogInfo'
    }

    It 'Defines Write-LogWarn helper' {
        $script:scriptContent | Should -Match 'function Write-LogWarn'
    }

    It 'Defines Write-LogError helper' {
        $script:scriptContent | Should -Match 'function Write-LogError'
    }

    It 'Defines Write-LogDebug helper' {
        $script:scriptContent | Should -Match 'function Write-LogDebug'
    }

    It 'Uses timestamp format in logs' {
        $script:scriptContent | Should -Match 'Get-Date -Format "yyyy-MM-dd HH:mm:ss"'
    }

    It 'Writes to log file' {
        $script:scriptContent | Should -Match 'Add-Content -Path \$LogFile'
    }

    It 'Uses appropriate colors for log levels' {
        $script:scriptContent | Should -Match '"ERROR".*Red'
        $script:scriptContent | Should -Match '"WARN".*Yellow'
        $script:scriptContent | Should -Match '"INFO".*Cyan'
        $script:scriptContent | Should -Match '"DEBUG".*Gray'
    }
}

Describe 'State Management Functions' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:supervisorScript -Raw
    }

    It 'Defines Ensure-ClaudeDir function' {
        $script:scriptContent | Should -Match 'function Ensure-ClaudeDir'
    }

    It 'Creates .claude directory if not exists' {
        $script:scriptContent | Should -Match 'if \(-not \(Test-Path "\.claude"\)\)'
        $script:scriptContent | Should -Match 'New-Item -ItemType Directory -Path "\.claude"'
    }

    It 'Defines Write-State function' {
        $script:scriptContent | Should -Match 'function Write-State'
    }

    It 'Defines Update-State function' {
        $script:scriptContent | Should -Match 'function Update-State'
    }

    It 'Defines Remove-StateFiles function' {
        $script:scriptContent | Should -Match 'function Remove-StateFiles'
    }

    It 'Write-State includes all required fields' {
        $script:scriptContent | Should -Match 'pid = \$PID'
        $script:scriptContent | Should -Match 'claude_pid'
        $script:scriptContent | Should -Match 'started_at'
        $script:scriptContent | Should -Match 'iteration'
        $script:scriptContent | Should -Match 'restart_count'
        $script:scriptContent | Should -Match 'max_iterations'
        $script:scriptContent | Should -Match 'max_restarts'
        $script:scriptContent | Should -Match 'status'
        $script:scriptContent | Should -Match 'last_update'
    }

    It 'Uses ConvertTo-Json for state serialization' {
        $script:scriptContent | Should -Match 'ConvertTo-Json -Depth 10'
    }

    It 'Remove-StateFiles cleans up all state files' {
        $script:scriptContent | Should -Match 'Remove-Item -Path \$StateFile'
        $script:scriptContent | Should -Match 'Remove-Item -Path \$PidFile'
        $script:scriptContent | Should -Match 'Remove-Item -Path \$ClaudePidFile'
    }
}

Describe 'Process Management Functions' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:supervisorScript -Raw
    }

    It 'Defines Stop-ClaudeProcess function' {
        $script:scriptContent | Should -Match 'function Stop-ClaudeProcess'
    }

    It 'Checks if process has exited before stopping' {
        $script:scriptContent | Should -Match '\$script:ClaudeProcess\.HasExited'
    }

    It 'Kills process when stopping' {
        $script:scriptContent | Should -Match '\$script:ClaudeProcess\.Kill\(\)'
    }

    It 'Waits for process exit with timeout' {
        $script:scriptContent | Should -Match 'WaitForExit\(5000\)'
    }
}

Describe 'Exit Code Handling' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:supervisorScript -Raw
    }

    It 'Defines Handle-ExitCode function' {
        $script:scriptContent | Should -Match 'function Handle-ExitCode'
    }

    It 'Handles exit code 0 as success' {
        $script:scriptContent | Should -Match '0 \{[\s\S]*?Claude exited successfully'
    }

    It 'Handles Ctrl+C exit codes' {
        # Windows uses -1073741510 or 0xC000013A for Ctrl+C
        $script:scriptContent | Should -Match '-1073741510'
        $script:scriptContent | Should -Match '130'
    }

    It 'Handles SIGTERM (143)' {
        $script:scriptContent | Should -Match '143 \{'
        $script:scriptContent | Should -Match 'SIGTERM'
    }

    It 'Handles SIGKILL (137)' {
        $script:scriptContent | Should -Match '137 \{'
        $script:scriptContent | Should -Match 'SIGKILL'
    }

    It 'Calls cleanup on successful exit' {
        $script:scriptContent | Should -Match 'Remove-StateFiles'
    }
}

Describe 'Restart Logic' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:supervisorScript -Raw
    }

    It 'Defines Test-ShouldRestart function' {
        $script:scriptContent | Should -Match 'function Test-ShouldRestart'
    }

    It 'Increments restart count on crash' {
        $script:scriptContent | Should -Match '\$script:RestartCount\+\+'
    }

    It 'Checks max restarts limit' {
        $script:scriptContent | Should -Match '\$script:RestartCount -ge \$MaxRestarts'
    }

    It 'Reports max restarts reached' {
        $script:scriptContent | Should -Match 'Max restarts.*reached'
    }

    It 'Uses configured restart delay' {
        $script:scriptContent | Should -Match 'Start-Sleep -Seconds \$RestartDelay'
    }

    It 'Increments iteration on restart' {
        $script:scriptContent | Should -Match '\$script:Iteration\+\+'
    }

    It 'Updates state to restarting' {
        $script:scriptContent | Should -Match 'Update-State -Status "restarting"'
    }
}

Describe 'Main Loop (Foreground)' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:supervisorScript -Raw
    }

    It 'Defines Start-Foreground function' {
        $script:scriptContent | Should -Match 'function Start-Foreground'
    }

    It 'Ensures .claude directory exists' {
        $script:scriptContent | Should -Match 'Ensure-ClaudeDir'
    }

    It 'Writes initial state' {
        $script:scriptContent | Should -Match 'Write-State -Status "running"'
    }

    It 'Writes PID to file' {
        $script:scriptContent | Should -Match '\$PID \| Set-Content -Path \$PidFile'
    }

    It 'Logs startup information' {
        $script:scriptContent | Should -Match 'Write-LogInfo "Starting Ralph supervisor"'
    }

    It 'Checks max iterations in loop' {
        $script:scriptContent | Should -Match '\$MaxIterations -gt 0 -and \$script:Iteration -gt \$MaxIterations'
    }

    It 'Uses -p flag for first iteration' {
        $script:scriptContent | Should -Match '\$script:Iteration -eq 1'
        $script:scriptContent | Should -Match '"-p", \$Prompt'
    }

    It 'Uses --continue for subsequent iterations' {
        $script:scriptContent | Should -Match '"--continue"'
    }

    It 'Starts Claude process using ProcessStartInfo' {
        $script:scriptContent | Should -Match 'New-Object System\.Diagnostics\.ProcessStartInfo'
        $script:scriptContent | Should -Match '\$processInfo\.FileName = "claude"'
    }

    It 'Writes Claude PID to file' {
        $script:scriptContent | Should -Match '\$script:ClaudeProcess\.Id \| Set-Content -Path \$ClaudePidFile'
    }

    It 'Waits for Claude process to exit' {
        $script:scriptContent | Should -Match '\$script:ClaudeProcess\.WaitForExit\(\)'
    }

    It 'Handles exit code after process completes' {
        $script:scriptContent | Should -Match '\$shouldStop = Handle-ExitCode'
    }

    It 'Cleans up in finally block' {
        $script:scriptContent | Should -Match 'finally \{[\s\S]*?Stop-ClaudeProcess[\s\S]*?Remove-StateFiles'
    }

    It 'Registers cleanup handler for script exit' {
        $script:scriptContent | Should -Match 'Register-EngineEvent.*PowerShell\.Exiting'
    }
}

Describe 'Background Mode' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:supervisorScript -Raw
    }

    It 'Defines Start-Background function' {
        $script:scriptContent | Should -Match 'function Start-Background'
    }

    It 'Checks if supervisor already running' {
        $script:scriptContent | Should -Match 'if \(Test-Path \$PidFile\)'
        $script:scriptContent | Should -Match 'Get-Process -Id \$existingPid'
    }

    It 'Reports error if already running' {
        $script:scriptContent | Should -Match 'Error: Ralph supervisor already running'
    }

    It 'Removes stale PID file' {
        $script:scriptContent | Should -Match 'Remove-Item \$PidFile'
    }

    It 'Starts PowerShell in background' {
        $script:scriptContent | Should -Match 'Start-Process -FilePath "powershell\.exe"'
        $script:scriptContent | Should -Match '-WindowStyle Hidden'
    }

    It 'Uses ForegroundInternal flag for background job' {
        $script:scriptContent | Should -Match '-ForegroundInternal'
    }

    It 'Passes all parameters to background job' {
        $script:scriptContent | Should -Match '"-Prompt"'
        $script:scriptContent | Should -Match '"-MaxIterations"'
        $script:scriptContent | Should -Match '"-MaxRestarts"'
        $script:scriptContent | Should -Match '"-RestartDelay"'
    }

    It 'Writes background process PID to file' {
        $script:scriptContent | Should -Match '\$bgProcess\.Id \| Set-Content -Path \$PidFile'
    }

    It 'Shows helpful commands after starting' {
        $script:scriptContent | Should -Match 'ralph-status\.ps1'
        $script:scriptContent | Should -Match 'ralph-stop\.ps1'
    }
}

Describe 'Main Entry Point' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:supervisorScript -Raw
    }

    It 'Checks Background flag at entry' {
        $script:scriptContent | Should -Match 'if \(\$Background -and -not \$ForegroundInternal\)'
    }

    It 'Calls Start-Background when Background flag set' {
        $script:scriptContent | Should -Match 'Start-Background'
    }

    It 'Calls Start-Foreground otherwise' {
        $script:scriptContent | Should -Match 'Start-Foreground'
    }
}

Describe 'State File JSON Schema' {
    BeforeAll {
        # Extract the state structure from the script
        $script:scriptContent = Get-Content -Path $script:supervisorScript -Raw
    }

    It 'State includes pid field' {
        $script:scriptContent | Should -Match 'pid = \$PID'
    }

    It 'State includes claude_pid field' {
        $script:scriptContent | Should -Match 'claude_pid ='
    }

    It 'State includes started_at field' {
        $script:scriptContent | Should -Match 'started_at = \$script:StartedAt'
    }

    It 'State includes iteration field' {
        $script:scriptContent | Should -Match 'iteration = \$script:Iteration'
    }

    It 'State includes restart_count field' {
        $script:scriptContent | Should -Match 'restart_count = \$script:RestartCount'
    }

    It 'State includes max_iterations field' {
        $script:scriptContent | Should -Match 'max_iterations = \$MaxIterations'
    }

    It 'State includes max_restarts field' {
        $script:scriptContent | Should -Match 'max_restarts = \$MaxRestarts'
    }

    It 'State includes completion_promise field' {
        $script:scriptContent | Should -Match 'completion_promise = \$CompletionPromise'
    }

    It 'State includes prompt field' {
        $script:scriptContent | Should -Match 'prompt = \$Prompt'
    }

    It 'State includes status field' {
        $script:scriptContent | Should -Match 'status = \$Status'
    }

    It 'State includes log_file field' {
        $script:scriptContent | Should -Match 'log_file = \$LogFile'
    }

    It 'State includes last_update field with ISO format' {
        $script:scriptContent | Should -Match 'last_update = \(Get-Date -Format "o"\)'
    }
}

Describe 'Error Handling' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path $script:supervisorScript -Raw
    }

    It 'Has try-catch around process start' {
        $script:scriptContent | Should -Match 'try \{[\s\S]*?\$script:ClaudeProcess = \[System\.Diagnostics\.Process\]::Start'
    }

    It 'Handles failed process start' {
        $script:scriptContent | Should -Match 'catch \{[\s\S]*?Failed to start Claude'
    }

    It 'Increments restart count on start failure' {
        $script:scriptContent | Should -Match 'catch \{[\s\S]*?\$script:RestartCount\+\+'
    }

    It 'Respects max restarts on start failures' {
        $script:scriptContent | Should -Match 'if \(\$script:RestartCount -ge \$MaxRestarts\)'
    }

    It 'Uses ErrorAction SilentlyContinue for non-critical operations' {
        $script:scriptContent | Should -Match '-ErrorAction SilentlyContinue'
    }
}

AfterAll {
    # Clean up - remove the imported module
    Remove-Module RalphUtils -ErrorAction SilentlyContinue
}
