import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import {
  InstanceStatus,
  InstanceStatusSchema,
  InstanceInfo,
  Prd,
  PrdSchema,
  PrdProgress,
  LockInfo,
  DEAD_THRESHOLD_SECONDS,
  STALE_LOCK_THRESHOLD_SECONDS,
} from '../../shared/index.js';
import {
  getGlobalPaths,
  getProjectPaths,
  dirExists,
  getProjectName,
} from '../../shared/paths.js';

/**
 * Read instance status from a status.json file
 */
export async function readInstanceStatus(
  instanceDir: string
): Promise<InstanceStatus | null> {
  const statusFile = path.join(instanceDir, 'status.json');

  try {
    const content = await fs.readFile(statusFile, 'utf-8');
    const parsed = JSON.parse(content);
    return InstanceStatusSchema.parse(parsed);
  } catch {
    return null;
  }
}

/**
 * Get instance info with computed fields
 */
export function getInstanceInfo(
  status: InstanceStatus,
  instanceDir: string
): InstanceInfo {
  const now = Math.floor(Date.now() / 1000);
  const heartbeatAge = now - status.lastHeartbeatEpoch;
  const isDead = heartbeatAge > DEAD_THRESHOLD_SECONDS;

  return {
    ...status,
    projectName: getProjectName(status.projectRoot),
    heartbeatAge,
    isDead,
    instanceDir,
  };
}

/**
 * Read all instances from a local instances directory
 */
export async function readLocalInstances(
  instancesDir: string
): Promise<InstanceInfo[]> {
  const instances: InstanceInfo[] = [];

  if (!dirExists(instancesDir)) {
    return instances;
  }

  try {
    const entries = await fs.readdir(instancesDir, { withFileTypes: true });

    for (const entry of entries) {
      if (!entry.isDirectory()) continue;

      const instanceDir = path.join(instancesDir, entry.name);
      const status = await readInstanceStatus(instanceDir);

      if (status) {
        instances.push(getInstanceInfo(status, instanceDir));
      }
    }
  } catch {
    // Directory doesn't exist or can't be read
  }

  return instances;
}

/**
 * Read all instances from the global registry
 */
export async function readGlobalInstances(): Promise<InstanceInfo[]> {
  const instances: InstanceInfo[] = [];
  const globalPaths = getGlobalPaths();

  if (!dirExists(globalPaths.globalInstancesDir)) {
    return instances;
  }

  try {
    const entries = await fs.readdir(
      globalPaths.globalInstancesDir,
      { withFileTypes: true }
    );

    for (const entry of entries) {
      // Global registry uses symlinks
      const linkPath = path.join(globalPaths.globalInstancesDir, entry.name);

      try {
        const realPath = await fs.realpath(linkPath);
        const status = await readInstanceStatus(realPath);

        if (status) {
          instances.push(getInstanceInfo(status, realPath));
        }
      } catch {
        // Broken symlink — remove it to prevent registry accumulation
        try { await fs.unlink(linkPath); } catch { /* ignore */ }
      }
    }
  } catch {
    // Directory doesn't exist or can't be read
  }

  return instances;
}

/**
 * Get all instances, optionally filtered
 */
export async function getAllInstances(options: {
  projectRoot?: string;
  includeGlobal?: boolean;
  includeDead?: boolean;
}): Promise<InstanceInfo[]> {
  const {
    projectRoot,
    includeGlobal = true,
    includeDead = false,
  } = options;

  let instances: InstanceInfo[] = [];

  // Read from local instances directory if projectRoot specified
  if (projectRoot) {
    const projectPaths = getProjectPaths(projectRoot);
    const localInstances = await readLocalInstances(projectPaths.instancesDir);
    instances.push(...localInstances);
  }

  // Read from global registry
  if (includeGlobal) {
    const globalInstances = await readGlobalInstances();

    // Deduplicate by instanceId
    const existingIds = new Set(instances.map(i => i.instanceId));
    for (const inst of globalInstances) {
      if (!existingIds.has(inst.instanceId)) {
        // Filter by projectRoot if specified; use startsWith so worktree instances
        // (whose projectRoot is a subdirectory of the project) are included
        const normalizedFilter = projectRoot ? path.resolve(projectRoot) : null;
        const normalizedInst = path.resolve(inst.projectRoot);
        if (!normalizedFilter || normalizedInst.startsWith(normalizedFilter)) {
          instances.push(inst);
          existingIds.add(inst.instanceId);
        }
      }
    }
  }

  // Filter dead instances
  if (!includeDead) {
    instances = instances.filter(i => !i.isDead);
  }

  // Sort by start time (newest first)
  instances.sort((a, b) => {
    return new Date(b.startTime).getTime() - new Date(a.startTime).getTime();
  });

  return instances;
}

/**
 * Read PRD file
 */
export async function readPrd(prdPath: string): Promise<Prd | null> {
  try {
    const content = await fs.readFile(prdPath, 'utf-8');
    const parsed = JSON.parse(content);
    return PrdSchema.parse(parsed);
  } catch {
    return null;
  }
}

/**
 * Get PRD progress summary
 */
export async function getPrdProgress(
  prdPath: string
): Promise<PrdProgress | null> {
  const prd = await readPrd(prdPath);

  if (!prd) {
    return null;
  }

  const stories = prd.userStories;
  const total = stories.length;
  const complete = stories.filter(s => s.passes).length;
  const remaining = total - complete;
  const percentage = total > 0 ? Math.round((complete / total) * 100) : 0;

  return {
    total,
    complete,
    remaining,
    percentage,
    stories,
  };
}

/**
 * Read story locks from locks directory
 */
export async function readLocks(locksDir: string): Promise<LockInfo[]> {
  const locks: LockInfo[] = [];
  const now = Math.floor(Date.now() / 1000);

  if (!dirExists(locksDir)) {
    return locks;
  }

  try {
    const entries = await fs.readdir(locksDir, { withFileTypes: true });

    for (const entry of entries) {
      if (!entry.isDirectory() || !entry.name.endsWith('.lock')) {
        continue;
      }

      const lockDir = path.join(locksDir, entry.name);
      const storyId = entry.name.replace('.lock', '');

      try {
        const ownerFile = path.join(lockDir, 'owner');
        const timestampFile = path.join(lockDir, 'timestamp');
        const pidFile = path.join(lockDir, 'pid');

        const owner = (await fs.readFile(ownerFile, 'utf-8')).trim();
        const timestampStr = (await fs.readFile(timestampFile, 'utf-8')).trim();
        const timestamp = parseInt(timestampStr, 10);

        let pid: number | undefined;
        try {
          const pidStr = (await fs.readFile(pidFile, 'utf-8')).trim();
          pid = parseInt(pidStr, 10);
        } catch {
          // pid file might not exist
        }

        const age = now - timestamp;
        const isStale = age > STALE_LOCK_THRESHOLD_SECONDS;

        locks.push({
          storyId,
          owner,
          timestamp,
          pid,
          age,
          isStale,
        });
      } catch {
        // Can't read lock info - skip
      }
    }
  } catch {
    // Directory doesn't exist or can't be read
  }

  return locks;
}
