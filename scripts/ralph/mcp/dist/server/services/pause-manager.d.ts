export interface PauseInstanceResult {
    instanceId: string;
    success: boolean;
    previousState?: string;
    error?: string;
}
export interface ResumeInstanceResult {
    instanceId: string;
    success: boolean;
    error?: string;
}
/**
 * Request an instance to pause after current iteration
 */
export declare function pauseInstance(instanceId: string): Promise<PauseInstanceResult>;
/**
 * Resume a paused instance
 */
export declare function resumeInstance(instanceId: string): Promise<ResumeInstanceResult>;
/**
 * Check if an instance has a pending pause request
 */
export declare function hasPauseRequest(instanceDir: string): Promise<boolean>;
/**
 * Check if an instance has a pending resume request
 */
export declare function hasResumeRequest(instanceDir: string): Promise<boolean>;
/**
 * Get pause request details
 */
export declare function getPauseRequest(instanceDir: string): Promise<{
    requestedAt: string;
    previousState?: string;
} | null>;
//# sourceMappingURL=pause-manager.d.ts.map