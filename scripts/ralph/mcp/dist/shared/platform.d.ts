import { ChildProcess, SpawnOptions } from 'node:child_process';
export type Platform = 'windows' | 'unix';
/**
 * Detect the current platform
 */
export declare function detectPlatform(): Platform;
/**
 * Check if running on Windows
 */
export declare function isWindows(): boolean;
/**
 * Get the appropriate script extension for the current platform
 */
export declare function getScriptExtension(): string;
/**
 * Get the shell command for the current platform
 */
export declare function getShellCommand(): {
    command: string;
    args: string[];
};
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
export declare function invokeRalphScript(scriptDir: string, scriptName: string, args?: string[], options?: InvokeScriptOptions): ChildProcess;
/**
 * Kill a process by PID with cross-platform support
 */
export declare function killProcess(pid: number, signal?: 'SIGTERM' | 'SIGKILL'): boolean;
/**
 * Check if a process is running by PID
 */
export declare function isProcessRunning(pid: number): boolean;
/**
 * Sleep for a specified number of milliseconds
 */
export declare function sleep(ms: number): Promise<void>;
/**
 * Wait for a process to exit with timeout
 */
export declare function waitForProcessExit(pid: number, timeoutMs?: number): Promise<boolean>;
//# sourceMappingURL=platform.d.ts.map