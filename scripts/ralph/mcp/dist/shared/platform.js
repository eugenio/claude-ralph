import { spawn } from 'node:child_process';
import { platform } from 'node:os';
import * as path from 'node:path';
/**
 * Detect the current platform
 */
export function detectPlatform() {
    return platform() === 'win32' ? 'windows' : 'unix';
}
/**
 * Check if running on Windows
 */
export function isWindows() {
    return platform() === 'win32';
}
/**
 * Get the appropriate script extension for the current platform
 */
export function getScriptExtension() {
    return isWindows() ? '.ps1' : '.sh';
}
/**
 * Get the shell command for the current platform
 */
export function getShellCommand() {
    if (isWindows()) {
        return { command: 'pwsh', args: ['-File'] };
    }
    return { command: 'bash', args: [] };
}
/**
 * Invoke a ralph script with cross-platform support
 */
export function invokeRalphScript(scriptDir, scriptName, args = [], options = {}) {
    const ext = getScriptExtension();
    const scriptPath = path.join(scriptDir, `${scriptName}${ext}`);
    const shell = getShellCommand();
    const spawnArgs = isWindows()
        ? [...shell.args, scriptPath, ...args]
        : [scriptPath, ...args];
    const spawnOptions = {
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
export function killProcess(pid, signal = 'SIGTERM') {
    try {
        if (isWindows()) {
            const force = signal === 'SIGKILL' ? '/F' : '';
            const child = spawn('taskkill', [force, '/PID', String(pid)].filter(Boolean), { stdio: 'ignore' });
            return child.pid !== undefined;
        }
        else {
            process.kill(pid, signal);
            return true;
        }
    }
    catch {
        return false;
    }
}
/**
 * Check if a process is running by PID
 */
export function isProcessRunning(pid) {
    try {
        process.kill(pid, 0);
        return true;
    }
    catch {
        return false;
    }
}
/**
 * Sleep for a specified number of milliseconds
 */
export function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}
/**
 * Wait for a process to exit with timeout
 */
export async function waitForProcessExit(pid, timeoutMs = 5000) {
    const startTime = Date.now();
    while (Date.now() - startTime < timeoutMs) {
        if (!isProcessRunning(pid)) {
            return true;
        }
        await sleep(100);
    }
    return false;
}
//# sourceMappingURL=platform.js.map