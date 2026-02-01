import { spawn, ChildProcess, SpawnOptions } from 'node:child_process';
import { platform } from 'node:os';
import * as path from 'node:path';

export type Platform = 'windows' | 'unix';

/**
 * Detect the current platform
 */
export function detectPlatform(): Platform {
  return platform() === 'win32' ? 'windows' : 'unix';
}

/**
 * Check if running on Windows
 */
export function isWindows(): boolean {
  return platform() === 'win32';
}

/**
 * Get the appropriate script extension for the current platform
 */
export function getScriptExtension(): string {
  return isWindows() ? '.ps1' : '.sh';
}

/**
 * Get the shell command for the current platform
 */
export function getShellCommand(): { command: string; args: string[] } {
  if (isWindows()) {
    return { command: 'pwsh', args: ['-File'] };
  }
  return { command: 'bash', args: [] };
}

export interface InvokeScriptOptions extends SpawnOptions {
  /** Working directory */
  cwd?: string;
  /** Environment variables */
  env?: NodeJS.ProcessEnv;
  /** Run detached from parent */
  detached?: boolean;
}

/**
 * Invoke a ralph script with cross-platform support
 */
export function invokeRalphScript(
  scriptDir: string,
  scriptName: string,
  args: string[] = [],
  options: InvokeScriptOptions = {}
): ChildProcess {
  const ext = getScriptExtension();
  const scriptPath = path.join(scriptDir, `${scriptName}${ext}`);
  const shell = getShellCommand();

  const spawnArgs = isWindows()
    ? [...shell.args, scriptPath, ...args]
    : [scriptPath, ...args];

  const spawnOptions: SpawnOptions = {
    cwd: options.cwd,
    env: { ...process.env, ...options.env },
    detached: options.detached ?? false,
    stdio: options.stdio ?? 'pipe',
  };

  return spawn(shell.command, spawnArgs, spawnOptions);
}

/**
 * Kill a process by PID with cross-platform support
 */
export function killProcess(
  pid: number,
  signal: 'SIGTERM' | 'SIGKILL' = 'SIGTERM'
): boolean {
  try {
    if (isWindows()) {
      const force = signal === 'SIGKILL' ? '/F' : '';
      const child = spawn(
        'taskkill',
        [force, '/PID', String(pid)].filter(Boolean),
        { stdio: 'ignore' }
      );
      return child.pid !== undefined;
    } else {
      process.kill(pid, signal);
      return true;
    }
  } catch {
    return false;
  }
}

/**
 * Check if a process is running by PID
 */
export function isProcessRunning(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

/**
 * Sleep for a specified number of milliseconds
 */
export function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Wait for a process to exit with timeout
 */
export async function waitForProcessExit(
  pid: number,
  timeoutMs: number = 5000
): Promise<boolean> {
  const startTime = Date.now();

  while (Date.now() - startTime < timeoutMs) {
    if (!isProcessRunning(pid)) {
      return true;
    }
    await sleep(100);
  }

  return false;
}
