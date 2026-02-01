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
 * Start a single ralph instance
 */
export declare function startInstance(options: StartInstanceOptions): Promise<StartInstanceResult>;
/**
 * Start multiple ralph instances in parallel
 */
export declare function startParallelInstances(options: StartParallelOptions): Promise<StartInstanceResult[]>;
/**
 * Stop a specific instance
 */
export declare function stopInstance(instanceId: string, force?: boolean): Promise<StopInstanceResult>;
/**
 * Stop all instances, optionally filtered by project
 */
export declare function stopAllInstances(projectRoot?: string, force?: boolean): Promise<StopInstanceResult[]>;
//# sourceMappingURL=process-manager.d.ts.map