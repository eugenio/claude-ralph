import { z } from 'zod';
export declare const InstanceStateSchema: z.ZodEnum<["starting", "idle", "claiming", "working", "waiting", "merging", "completed", "terminated", "max_iterations", "paused", "rate_limited"]>;
export type InstanceState = z.infer<typeof InstanceStateSchema>;
export declare const InstanceStatusSchema: z.ZodObject<{
    instanceId: z.ZodString;
    shortId: z.ZodString;
    state: z.ZodEnum<["starting", "idle", "claiming", "working", "waiting", "merging", "completed", "terminated", "max_iterations", "paused", "rate_limited"]>;
    currentStory: z.ZodOptional<z.ZodNullable<z.ZodString>>;
    iteration: z.ZodNumber;
    maxIterations: z.ZodNumber;
    startTime: z.ZodString;
    lastHeartbeat: z.ZodString;
    lastHeartbeatEpoch: z.ZodNumber;
    projectRoot: z.ZodString;
    branch: z.ZodOptional<z.ZodString>;
    pid: z.ZodNumber;
}, "strip", z.ZodTypeAny, {
    instanceId: string;
    shortId: string;
    state: "starting" | "idle" | "claiming" | "working" | "waiting" | "merging" | "completed" | "terminated" | "max_iterations" | "paused" | "rate_limited";
    iteration: number;
    maxIterations: number;
    startTime: string;
    lastHeartbeat: string;
    lastHeartbeatEpoch: number;
    projectRoot: string;
    pid: number;
    currentStory?: string | null | undefined;
    branch?: string | undefined;
}, {
    instanceId: string;
    shortId: string;
    state: "starting" | "idle" | "claiming" | "working" | "waiting" | "merging" | "completed" | "terminated" | "max_iterations" | "paused" | "rate_limited";
    iteration: number;
    maxIterations: number;
    startTime: string;
    lastHeartbeat: string;
    lastHeartbeatEpoch: number;
    projectRoot: string;
    pid: number;
    currentStory?: string | null | undefined;
    branch?: string | undefined;
}>;
export type InstanceStatus = z.infer<typeof InstanceStatusSchema>;
export interface InstanceInfo extends InstanceStatus {
    projectName: string;
    heartbeatAge: number;
    isDead: boolean;
    instanceDir: string;
}
export declare const StorySchema: z.ZodObject<{
    id: z.ZodString;
    title: z.ZodString;
    description: z.ZodOptional<z.ZodString>;
    priority: z.ZodDefault<z.ZodNumber>;
    acceptanceCriteria: z.ZodOptional<z.ZodArray<z.ZodString, "many">>;
    passes: z.ZodDefault<z.ZodBoolean>;
    claimedBy: z.ZodOptional<z.ZodNullable<z.ZodString>>;
}, "strip", z.ZodTypeAny, {
    id: string;
    title: string;
    priority: number;
    passes: boolean;
    description?: string | undefined;
    acceptanceCriteria?: string[] | undefined;
    claimedBy?: string | null | undefined;
}, {
    id: string;
    title: string;
    description?: string | undefined;
    priority?: number | undefined;
    acceptanceCriteria?: string[] | undefined;
    passes?: boolean | undefined;
    claimedBy?: string | null | undefined;
}>;
export type Story = z.infer<typeof StorySchema>;
export declare const PrdSchema: z.ZodObject<{
    projectName: z.ZodOptional<z.ZodString>;
    branchName: z.ZodDefault<z.ZodString>;
    userStories: z.ZodArray<z.ZodObject<{
        id: z.ZodString;
        title: z.ZodString;
        description: z.ZodOptional<z.ZodString>;
        priority: z.ZodDefault<z.ZodNumber>;
        acceptanceCriteria: z.ZodOptional<z.ZodArray<z.ZodString, "many">>;
        passes: z.ZodDefault<z.ZodBoolean>;
        claimedBy: z.ZodOptional<z.ZodNullable<z.ZodString>>;
    }, "strip", z.ZodTypeAny, {
        id: string;
        title: string;
        priority: number;
        passes: boolean;
        description?: string | undefined;
        acceptanceCriteria?: string[] | undefined;
        claimedBy?: string | null | undefined;
    }, {
        id: string;
        title: string;
        description?: string | undefined;
        priority?: number | undefined;
        acceptanceCriteria?: string[] | undefined;
        passes?: boolean | undefined;
        claimedBy?: string | null | undefined;
    }>, "many">;
}, "strip", z.ZodTypeAny, {
    branchName: string;
    userStories: {
        id: string;
        title: string;
        priority: number;
        passes: boolean;
        description?: string | undefined;
        acceptanceCriteria?: string[] | undefined;
        claimedBy?: string | null | undefined;
    }[];
    projectName?: string | undefined;
}, {
    userStories: {
        id: string;
        title: string;
        description?: string | undefined;
        priority?: number | undefined;
        acceptanceCriteria?: string[] | undefined;
        passes?: boolean | undefined;
        claimedBy?: string | null | undefined;
    }[];
    projectName?: string | undefined;
    branchName?: string | undefined;
}>;
export type Prd = z.infer<typeof PrdSchema>;
export interface PrdProgress {
    total: number;
    complete: number;
    remaining: number;
    percentage: number;
    stories: Story[];
}
export interface LockInfo {
    storyId: string;
    owner: string;
    timestamp: number;
    pid?: number;
    age: number;
    isStale: boolean;
}
export declare const QueueEntryStatusSchema: z.ZodEnum<["pending", "active", "completed", "failed"]>;
export type QueueEntryStatus = z.infer<typeof QueueEntryStatusSchema>;
export declare const QueueEntrySchema: z.ZodObject<{
    id: z.ZodString;
    prdPath: z.ZodString;
    projectRoot: z.ZodString;
    priority: z.ZodDefault<z.ZodNumber>;
    status: z.ZodEnum<["pending", "active", "completed", "failed"]>;
    addedAt: z.ZodString;
    claimedBy: z.ZodOptional<z.ZodNullable<z.ZodString>>;
    claimedAt: z.ZodOptional<z.ZodNullable<z.ZodString>>;
    completedAt: z.ZodOptional<z.ZodNullable<z.ZodString>>;
}, "strip", z.ZodTypeAny, {
    status: "completed" | "pending" | "active" | "failed";
    projectRoot: string;
    id: string;
    priority: number;
    prdPath: string;
    addedAt: string;
    claimedBy?: string | null | undefined;
    claimedAt?: string | null | undefined;
    completedAt?: string | null | undefined;
}, {
    status: "completed" | "pending" | "active" | "failed";
    projectRoot: string;
    id: string;
    prdPath: string;
    addedAt: string;
    priority?: number | undefined;
    claimedBy?: string | null | undefined;
    claimedAt?: string | null | undefined;
    completedAt?: string | null | undefined;
}>;
export type QueueEntry = z.infer<typeof QueueEntrySchema>;
export declare const QueueSchema: z.ZodObject<{
    entries: z.ZodArray<z.ZodObject<{
        id: z.ZodString;
        prdPath: z.ZodString;
        projectRoot: z.ZodString;
        priority: z.ZodDefault<z.ZodNumber>;
        status: z.ZodEnum<["pending", "active", "completed", "failed"]>;
        addedAt: z.ZodString;
        claimedBy: z.ZodOptional<z.ZodNullable<z.ZodString>>;
        claimedAt: z.ZodOptional<z.ZodNullable<z.ZodString>>;
        completedAt: z.ZodOptional<z.ZodNullable<z.ZodString>>;
    }, "strip", z.ZodTypeAny, {
        status: "completed" | "pending" | "active" | "failed";
        projectRoot: string;
        id: string;
        priority: number;
        prdPath: string;
        addedAt: string;
        claimedBy?: string | null | undefined;
        claimedAt?: string | null | undefined;
        completedAt?: string | null | undefined;
    }, {
        status: "completed" | "pending" | "active" | "failed";
        projectRoot: string;
        id: string;
        prdPath: string;
        addedAt: string;
        priority?: number | undefined;
        claimedBy?: string | null | undefined;
        claimedAt?: string | null | undefined;
        completedAt?: string | null | undefined;
    }>, "many">;
}, "strip", z.ZodTypeAny, {
    entries: {
        status: "completed" | "pending" | "active" | "failed";
        projectRoot: string;
        id: string;
        priority: number;
        prdPath: string;
        addedAt: string;
        claimedBy?: string | null | undefined;
        claimedAt?: string | null | undefined;
        completedAt?: string | null | undefined;
    }[];
}, {
    entries: {
        status: "completed" | "pending" | "active" | "failed";
        projectRoot: string;
        id: string;
        prdPath: string;
        addedAt: string;
        priority?: number | undefined;
        claimedBy?: string | null | undefined;
        claimedAt?: string | null | undefined;
        completedAt?: string | null | undefined;
    }[];
}>;
export type Queue = z.infer<typeof QueueSchema>;
export interface QueueSummary {
    total: number;
    pending: number;
    active: number;
    completed: number;
    failed: number;
}
export declare const RateLimitPauseSchema: z.ZodObject<{
    instanceId: z.ZodString;
    pausedAt: z.ZodString;
    pausedAtEpoch: z.ZodNumber;
    reason: z.ZodString;
    detectionMethod: z.ZodOptional<z.ZodString>;
    patternMatched: z.ZodOptional<z.ZodString>;
    backoffSeconds: z.ZodNumber;
    retryCount: z.ZodDefault<z.ZodNumber>;
    maxRetries: z.ZodDefault<z.ZodNumber>;
    estimatedResumeAt: z.ZodOptional<z.ZodString>;
}, "strip", z.ZodTypeAny, {
    instanceId: string;
    pausedAt: string;
    pausedAtEpoch: number;
    reason: string;
    backoffSeconds: number;
    retryCount: number;
    maxRetries: number;
    detectionMethod?: string | undefined;
    patternMatched?: string | undefined;
    estimatedResumeAt?: string | undefined;
}, {
    instanceId: string;
    pausedAt: string;
    pausedAtEpoch: number;
    reason: string;
    backoffSeconds: number;
    detectionMethod?: string | undefined;
    patternMatched?: string | undefined;
    retryCount?: number | undefined;
    maxRetries?: number | undefined;
    estimatedResumeAt?: string | undefined;
}>;
export type RateLimitPause = z.infer<typeof RateLimitPauseSchema>;
export declare const McpServerConfigSchema: z.ZodObject<{
    enabled: z.ZodDefault<z.ZodBoolean>;
    transport: z.ZodDefault<z.ZodEnum<["streamable-http", "stdio"]>>;
    url: z.ZodOptional<z.ZodString>;
    pollingInterval: z.ZodOptional<z.ZodNumber>;
    timeout: z.ZodOptional<z.ZodNumber>;
    retries: z.ZodOptional<z.ZodNumber>;
    retryDelay: z.ZodOptional<z.ZodNumber>;
}, "strip", z.ZodTypeAny, {
    enabled: boolean;
    transport: "streamable-http" | "stdio";
    url?: string | undefined;
    pollingInterval?: number | undefined;
    timeout?: number | undefined;
    retries?: number | undefined;
    retryDelay?: number | undefined;
}, {
    enabled?: boolean | undefined;
    transport?: "streamable-http" | "stdio" | undefined;
    url?: string | undefined;
    pollingInterval?: number | undefined;
    timeout?: number | undefined;
    retries?: number | undefined;
    retryDelay?: number | undefined;
}>;
export declare const NotificationEventConfigSchema: z.ZodObject<{
    enabled: z.ZodDefault<z.ZodBoolean>;
    channels: z.ZodDefault<z.ZodArray<z.ZodString, "many">>;
    threshold: z.ZodOptional<z.ZodNumber>;
}, "strip", z.ZodTypeAny, {
    channels: string[];
    enabled: boolean;
    threshold?: number | undefined;
}, {
    channels?: string[] | undefined;
    enabled?: boolean | undefined;
    threshold?: number | undefined;
}>;
export declare const McpConfigSchema: z.ZodObject<{
    servers: z.ZodDefault<z.ZodRecord<z.ZodString, z.ZodObject<{
        enabled: z.ZodDefault<z.ZodBoolean>;
        transport: z.ZodDefault<z.ZodEnum<["streamable-http", "stdio"]>>;
        url: z.ZodOptional<z.ZodString>;
        pollingInterval: z.ZodOptional<z.ZodNumber>;
        timeout: z.ZodOptional<z.ZodNumber>;
        retries: z.ZodOptional<z.ZodNumber>;
        retryDelay: z.ZodOptional<z.ZodNumber>;
    }, "strip", z.ZodTypeAny, {
        enabled: boolean;
        transport: "streamable-http" | "stdio";
        url?: string | undefined;
        pollingInterval?: number | undefined;
        timeout?: number | undefined;
        retries?: number | undefined;
        retryDelay?: number | undefined;
    }, {
        enabled?: boolean | undefined;
        transport?: "streamable-http" | "stdio" | undefined;
        url?: string | undefined;
        pollingInterval?: number | undefined;
        timeout?: number | undefined;
        retries?: number | undefined;
        retryDelay?: number | undefined;
    }>>>;
    notifications: z.ZodOptional<z.ZodObject<{
        events: z.ZodDefault<z.ZodRecord<z.ZodString, z.ZodObject<{
            enabled: z.ZodDefault<z.ZodBoolean>;
            channels: z.ZodDefault<z.ZodArray<z.ZodString, "many">>;
            threshold: z.ZodOptional<z.ZodNumber>;
        }, "strip", z.ZodTypeAny, {
            channels: string[];
            enabled: boolean;
            threshold?: number | undefined;
        }, {
            channels?: string[] | undefined;
            enabled?: boolean | undefined;
            threshold?: number | undefined;
        }>>>;
        rateLimit: z.ZodOptional<z.ZodObject<{
            maxPerMinute: z.ZodDefault<z.ZodNumber>;
            burstLimit: z.ZodDefault<z.ZodNumber>;
        }, "strip", z.ZodTypeAny, {
            maxPerMinute: number;
            burstLimit: number;
        }, {
            maxPerMinute?: number | undefined;
            burstLimit?: number | undefined;
        }>>;
    }, "strip", z.ZodTypeAny, {
        events: Record<string, {
            channels: string[];
            enabled: boolean;
            threshold?: number | undefined;
        }>;
        rateLimit?: {
            maxPerMinute: number;
            burstLimit: number;
        } | undefined;
    }, {
        events?: Record<string, {
            channels?: string[] | undefined;
            enabled?: boolean | undefined;
            threshold?: number | undefined;
        }> | undefined;
        rateLimit?: {
            maxPerMinute?: number | undefined;
            burstLimit?: number | undefined;
        } | undefined;
    }>>;
    fallback: z.ZodOptional<z.ZodObject<{
        enabled: z.ZodDefault<z.ZodBoolean>;
        logToFile: z.ZodDefault<z.ZodBoolean>;
        logPath: z.ZodOptional<z.ZodString>;
        retryQueue: z.ZodDefault<z.ZodBoolean>;
        maxRetries: z.ZodDefault<z.ZodNumber>;
        retryBackoff: z.ZodDefault<z.ZodEnum<["linear", "exponential"]>>;
    }, "strip", z.ZodTypeAny, {
        maxRetries: number;
        enabled: boolean;
        logToFile: boolean;
        retryQueue: boolean;
        retryBackoff: "linear" | "exponential";
        logPath?: string | undefined;
    }, {
        maxRetries?: number | undefined;
        enabled?: boolean | undefined;
        logToFile?: boolean | undefined;
        logPath?: string | undefined;
        retryQueue?: boolean | undefined;
        retryBackoff?: "linear" | "exponential" | undefined;
    }>>;
}, "strip", z.ZodTypeAny, {
    servers: Record<string, {
        enabled: boolean;
        transport: "streamable-http" | "stdio";
        url?: string | undefined;
        pollingInterval?: number | undefined;
        timeout?: number | undefined;
        retries?: number | undefined;
        retryDelay?: number | undefined;
    }>;
    notifications?: {
        events: Record<string, {
            channels: string[];
            enabled: boolean;
            threshold?: number | undefined;
        }>;
        rateLimit?: {
            maxPerMinute: number;
            burstLimit: number;
        } | undefined;
    } | undefined;
    fallback?: {
        maxRetries: number;
        enabled: boolean;
        logToFile: boolean;
        retryQueue: boolean;
        retryBackoff: "linear" | "exponential";
        logPath?: string | undefined;
    } | undefined;
}, {
    notifications?: {
        events?: Record<string, {
            channels?: string[] | undefined;
            enabled?: boolean | undefined;
            threshold?: number | undefined;
        }> | undefined;
        rateLimit?: {
            maxPerMinute?: number | undefined;
            burstLimit?: number | undefined;
        } | undefined;
    } | undefined;
    servers?: Record<string, {
        enabled?: boolean | undefined;
        transport?: "streamable-http" | "stdio" | undefined;
        url?: string | undefined;
        pollingInterval?: number | undefined;
        timeout?: number | undefined;
        retries?: number | undefined;
        retryDelay?: number | undefined;
    }> | undefined;
    fallback?: {
        maxRetries?: number | undefined;
        enabled?: boolean | undefined;
        logToFile?: boolean | undefined;
        logPath?: string | undefined;
        retryQueue?: boolean | undefined;
        retryBackoff?: "linear" | "exponential" | undefined;
    } | undefined;
}>;
export type McpConfig = z.infer<typeof McpConfigSchema>;
export declare const DEAD_THRESHOLD_SECONDS = 300;
export declare const STALE_LOCK_THRESHOLD_SECONDS = 7200;
//# sourceMappingURL=types.d.ts.map