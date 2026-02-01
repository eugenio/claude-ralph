import { InstanceStatus, InstanceInfo, Prd, PrdProgress, LockInfo } from '../../shared/index.js';
/**
 * Read instance status from a status.json file
 */
export declare function readInstanceStatus(instanceDir: string): Promise<InstanceStatus | null>;
/**
 * Get instance info with computed fields
 */
export declare function getInstanceInfo(status: InstanceStatus, instanceDir: string): InstanceInfo;
/**
 * Read all instances from a local instances directory
 */
export declare function readLocalInstances(instancesDir: string): Promise<InstanceInfo[]>;
/**
 * Read all instances from the global registry
 */
export declare function readGlobalInstances(): Promise<InstanceInfo[]>;
/**
 * Get all instances, optionally filtered
 */
export declare function getAllInstances(options: {
    projectRoot?: string;
    includeGlobal?: boolean;
    includeDead?: boolean;
}): Promise<InstanceInfo[]>;
/**
 * Read PRD file
 */
export declare function readPrd(prdPath: string): Promise<Prd | null>;
/**
 * Get PRD progress summary
 */
export declare function getPrdProgress(prdPath: string): Promise<PrdProgress | null>;
/**
 * Read story locks from locks directory
 */
export declare function readLocks(locksDir: string): Promise<LockInfo[]>;
//# sourceMappingURL=state-reader.d.ts.map