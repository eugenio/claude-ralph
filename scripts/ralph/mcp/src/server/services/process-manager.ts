import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import {
  invokeRalphScript,
  killProcess,
  isProcessRunning,
  waitForProcessExit,
  sleep,
} from '../../shared/platform.js';
import { getAllInstances } from './state-reader.js';
import { InstanceInfo, recordActiveInstances } from '../../shared/index.js';
import { getGlobalPaths, getProjectName } from '../../shared/paths.js';

export interface StartInstanceOptions {
  prdPath: string;
  projectRoot: string;
  maxIterations?: number;
  queueMode?: boolean;
}

export interface StartInstanceResult {
  success: boolean;
  instanceId?: string;
  shortId?: string;
  pid?: number;
  logFile?: string;
  error?: string;
}

export interface StartParallelOptions extends StartInstanceOptions {
  count: number;
}

export interface StopInstanceResult {
  instanceId: string;
  success: boolean;
  error?: string;
}

/**
 * Get the ralph scripts directory
 */
function getRalphScriptDir(projectRoot: string): string {
  return path.join(projectRoot, 'scripts', 'ralph');
}

/**
 * Start a single ralph instance
 */
export async function startInstance(
  options: StartInstanceOptions
): Promise<StartInstanceResult> {
  const { prdPath, projectRoot, maxIterations = 10, queueMode = false } = options;

  const scriptDir = getRalphScriptDir(projectRoot);
  const args: string[] = [
    '--prd', prdPath,
    '--project', projectRoot,
    String(maxIterations),
  ];

  if (queueMode) {
    args.push('--queue-mode');
  }

  try {
    const child = invokeRalphScript(scriptDir, 'ralph', args, {
      cwd: projectRoot,
      detached: true,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    // Detach so parent can exit
    child.unref();

    if (!child.pid) {
      return {
        success: false,
        error: 'Failed to start process - no PID',
      };
    }

    // Wait for status.json to appear (up to 10 seconds)
    const instanceInfo = await waitForInstanceStart(projectRoot, child.pid, 10000);

    if (instanceInfo) {
      // Record active instances metric
      const allInstances = await getAllInstances({ includeGlobal: true, includeDead: false });
      recordActiveInstances(allInstances.length);

      return {
        success: true,
        instanceId: instanceInfo.instanceId,
        shortId: instanceInfo.shortId,
        pid: child.pid,
        logFile: path.join(instanceInfo.instanceDir, 'ralph.log'),
      };
    }

    return {
      success: true,
      pid: child.pid,
      logFile: path.join(scriptDir, 'ralph.log'),
    };
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

/**
 * Start multiple ralph instances in parallel
 */
export async function startParallelInstances(
  options: StartParallelOptions
): Promise<StartInstanceResult[]> {
  const { prdPath, projectRoot, maxIterations = 10, queueMode = false, count } = options;

  const scriptDir = getRalphScriptDir(projectRoot);
  const args: string[] = [
    'start',
    '-c', String(count),
    '-m', String(maxIterations),
    '-p', prdPath,
    '-r', projectRoot,
  ];

  if (queueMode) {
    args.push('--queue-mode');
  }

  try {
    const child = invokeRalphScript(scriptDir, 'ralph-parallel', args, {
      cwd: projectRoot,
      detached: true,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    child.unref();

    if (!child.pid) {
      return [{
        success: false,
        error: 'Failed to start parallel instances - no PID',
      }];
    }

    // Wait a bit for instances to start
    await sleep(2000);

    // Get all instances that were just started
    const instances = await getAllInstances({
      projectRoot,
      includeGlobal: false,
      includeDead: false,
    });

    // Return info about recently started instances
    const results: StartInstanceResult[] = instances
      .filter(i => {
        const startTime = new Date(i.startTime).getTime();
        const now = Date.now();
        return now - startTime < 30000; // Started in last 30 seconds
      })
      .map(i => ({
        success: true,
        instanceId: i.instanceId,
        shortId: i.shortId,
        pid: i.pid,
        logFile: path.join(i.instanceDir, 'ralph.log'),
      }));

    if (results.length === 0) {
      return [{
        success: true,
        pid: child.pid,
      }];
    }

    return results;
  } catch (error) {
    return [{
      success: false,
      error: error instanceof Error ? error.message : String(error),
    }];
  }
}

/**
 * Wait for an instance to start and return its info
 */
async function waitForInstanceStart(
  projectRoot: string,
  pid: number,
  timeoutMs: number
): Promise<InstanceInfo | null> {
  const startTime = Date.now();

  while (Date.now() - startTime < timeoutMs) {
    const instances = await getAllInstances({
      projectRoot,
      includeGlobal: false,
      includeDead: false,
    });

    const instance = instances.find(i => i.pid === pid);
    if (instance) {
      return instance;
    }

    await sleep(500);
  }

  return null;
}

/**
 * Stop a specific instance
 */
export async function stopInstance(
  instanceId: string,
  force: boolean = false
): Promise<StopInstanceResult> {
  const instances = await getAllInstances({
    includeGlobal: true,
    includeDead: true,
  });

  const instance = instances.find(i => i.instanceId === instanceId);

  if (!instance) {
    return {
      instanceId,
      success: false,
      error: `Instance not found: ${instanceId}`,
    };
  }

  return stopInstanceByInfo(instance, force);
}

/**
 * Remove the global registry symlink for a stopped instance
 */
async function removeGlobalSymlink(instance: InstanceInfo): Promise<void> {
  try {
    const globalPaths = getGlobalPaths();
    const projectName = getProjectName(instance.projectRoot);
    const symlinkPath = path.join(
      globalPaths.globalInstancesDir,
      `${projectName}-${instance.instanceId}`
    );
    await fs.unlink(symlinkPath);
  } catch {
    // Symlink might not exist — ignore
  }
}

/**
 * Stop an instance by its info
 */
async function stopInstanceByInfo(
  instance: InstanceInfo,
  force: boolean
): Promise<StopInstanceResult> {
  const signal = force ? 'SIGKILL' : 'SIGTERM';

  if (!isProcessRunning(instance.pid)) {
    // Process already gone — still clean up the registry entry
    await removeGlobalSymlink(instance);
    return {
      instanceId: instance.instanceId,
      success: true, // Already stopped
    };
  }

  const killed = killProcess(instance.pid, signal);

  if (!killed) {
    return {
      instanceId: instance.instanceId,
      success: false,
      error: `Failed to send ${signal} to process ${instance.pid}`,
    };
  }

  // Wait for process to exit
  const exited = await waitForProcessExit(instance.pid, force ? 2000 : 10000);

  if (!exited && !force) {
    // Try force kill
    killProcess(instance.pid, 'SIGKILL');
    await waitForProcessExit(instance.pid, 2000);
  }

  await removeGlobalSymlink(instance);

  return {
    instanceId: instance.instanceId,
    success: true,
  };
}

/**
 * Stop all instances, optionally filtered by project
 */
export async function stopAllInstances(
  projectRoot?: string,
  force: boolean = false
): Promise<StopInstanceResult[]> {
  const instances = await getAllInstances({
    projectRoot,
    includeGlobal: true,
    includeDead: false,
  });

  const results: StopInstanceResult[] = [];

  for (const instance of instances) {
    const result = await stopInstanceByInfo(instance, force);
    results.push(result);
  }

  return results;
}
