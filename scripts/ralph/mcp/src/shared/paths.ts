import * as path from 'node:path';
import * as fs from 'node:fs';
import * as os from 'node:os';

/**
 * Resolves ralph paths based on environment and defaults
 */
export interface RalphPaths {
  globalDir: string;
  globalInstancesDir: string;
  globalQueueFile: string;
  globalRateLimitsDir: string;
  globalMcpDir: string;
  globalMcpConfigFile: string;
  globalNotificationsDir: string;
}

export interface ProjectPaths {
  projectRoot: string;
  ralphDir: string;
  prdFile: string;
  progressFile: string;
  logFile: string;
  instancesDir: string;
  locksDir: string;
}

/**
 * Get global ralph paths
 */
export function getGlobalPaths(): RalphPaths {
  const globalDir = process.env.RALPH_GLOBAL_DIR
    || path.join(os.homedir(), '.ralph', 'global');

  return {
    globalDir,
    globalInstancesDir: path.join(globalDir, 'instances'),
    globalQueueFile: path.join(globalDir, 'queue.json'),
    globalRateLimitsDir: path.join(globalDir, 'rate_limits'),
    globalMcpDir: path.join(globalDir, 'mcp'),
    globalMcpConfigFile: path.join(globalDir, 'mcp', 'config.json'),
    globalNotificationsDir: path.join(globalDir, 'notifications'),
  };
}

/**
 * Get project-specific ralph paths
 */
export function getProjectPaths(projectRoot?: string, prdPath?: string): ProjectPaths {
  const root = projectRoot
    || process.env.RALPH_PROJECT_ROOT
    || process.cwd();

  const ralphDir = path.join(root, 'scripts', 'ralph');

  // Resolve PRD file: explicit arg > env var > .ralph/*.json scan > fallback template
  let prdFile: string;
  if (prdPath) {
    prdFile = prdPath;
  } else if (process.env.RALPH_PRD_FILE) {
    prdFile = process.env.RALPH_PRD_FILE;
  } else {
    // Check <projectRoot>/.ralph/ for user PRD files (preferred location)
    const dotRalphDir = path.join(root, '.ralph');
    prdFile = path.join(ralphDir, 'prd.json'); // fallback to bundled template
    try {
      const entries = fs.readdirSync(dotRalphDir);
      const jsonFiles = entries
        .filter(e => e.endsWith('.json') && !e.startsWith('_'))
        .sort();
      if (jsonFiles.length > 0) {
        prdFile = path.join(dotRalphDir, jsonFiles[0]);
      }
    } catch {
      // .ralph/ doesn't exist — use template fallback
    }
  }

  return {
    projectRoot: root,
    ralphDir,
    prdFile,
    progressFile: path.join(ralphDir, 'progress.txt'),
    logFile: path.join(ralphDir, 'ralph.log'),
    instancesDir: path.join(ralphDir, 'instances'),
    locksDir: path.join(ralphDir, 'locks'),
  };
}

/**
 * Ensure a directory exists, creating it if necessary
 */
export function ensureDir(dirPath: string): void {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

/**
 * Check if a path exists and is a file
 */
export function fileExists(filePath: string): boolean {
  try {
    return fs.statSync(filePath).isFile();
  } catch {
    return false;
  }
}

/**
 * Check if a path exists and is a directory
 */
export function dirExists(dirPath: string): boolean {
  try {
    return fs.statSync(dirPath).isDirectory();
  } catch {
    return false;
  }
}

/**
 * Get project name from project root path
 */
export function getProjectName(projectRoot: string): string {
  return path.basename(projectRoot);
}

/**
 * Resolve environment variables in a string (e.g., "${HOME}/path")
 */
export function resolveEnvVars(str: string): string {
  return str.replace(/\$\{(\w+)\}/g, (_, name) => process.env[name] || '');
}

/**
 * Expand ~ to home directory
 */
export function expandHome(filePath: string): string {
  if (filePath.startsWith('~')) {
    return path.join(os.homedir(), filePath.slice(1));
  }
  return filePath;
}
