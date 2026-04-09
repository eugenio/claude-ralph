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
export declare function getGlobalPaths(): RalphPaths;
/**
 * Get project-specific ralph paths
 */
export declare function getProjectPaths(projectRoot?: string, prdPath?: string): ProjectPaths;
/**
 * Ensure a directory exists, creating it if necessary
 */
export declare function ensureDir(dirPath: string): void;
/**
 * Check if a path exists and is a file
 */
export declare function fileExists(filePath: string): boolean;
/**
 * Check if a path exists and is a directory
 */
export declare function dirExists(dirPath: string): boolean;
/**
 * Get project name from project root path
 */
export declare function getProjectName(projectRoot: string): string;
/**
 * Resolve environment variables in a string (e.g., "${HOME}/path")
 */
export declare function resolveEnvVars(str: string): string;
/**
 * Expand ~ to home directory
 */
export declare function expandHome(filePath: string): string;
//# sourceMappingURL=paths.d.ts.map