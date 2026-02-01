import * as path from 'node:path';
import * as fs from 'node:fs';
import * as os from 'node:os';
/**
 * Get global ralph paths
 */
export function getGlobalPaths() {
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
export function getProjectPaths(projectRoot) {
    const root = projectRoot
        || process.env.RALPH_PROJECT_ROOT
        || process.cwd();
    const ralphDir = path.join(root, 'scripts', 'ralph');
    const prdFile = process.env.RALPH_PRD_FILE
        || path.join(ralphDir, 'prd.json');
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
export function ensureDir(dirPath) {
    if (!fs.existsSync(dirPath)) {
        fs.mkdirSync(dirPath, { recursive: true });
    }
}
/**
 * Check if a path exists and is a file
 */
export function fileExists(filePath) {
    try {
        return fs.statSync(filePath).isFile();
    }
    catch {
        return false;
    }
}
/**
 * Check if a path exists and is a directory
 */
export function dirExists(dirPath) {
    try {
        return fs.statSync(dirPath).isDirectory();
    }
    catch {
        return false;
    }
}
/**
 * Get project name from project root path
 */
export function getProjectName(projectRoot) {
    return path.basename(projectRoot);
}
/**
 * Resolve environment variables in a string (e.g., "${HOME}/path")
 */
export function resolveEnvVars(str) {
    return str.replace(/\$\{(\w+)\}/g, (_, name) => process.env[name] || '');
}
/**
 * Expand ~ to home directory
 */
export function expandHome(filePath) {
    if (filePath.startsWith('~')) {
        return path.join(os.homedir(), filePath.slice(1));
    }
    return filePath;
}
//# sourceMappingURL=paths.js.map