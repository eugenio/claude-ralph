import { z } from 'zod';

// Instance status as stored in status.json
export const InstanceStateSchema = z.enum([
  'starting',
  'idle',
  'claiming',
  'working',
  'waiting',
  'merging',
  'completed',
  'terminated',
  'max_iterations',
  'paused',
  'rate_limited',
]);

export type InstanceState = z.infer<typeof InstanceStateSchema>;

export const InstanceStatusSchema = z.object({
  instanceId: z.string(),
  shortId: z.string(),
  state: InstanceStateSchema,
  currentStory: z.string().nullable().optional(),
  iteration: z.number(),
  maxIterations: z.number(),
  startTime: z.string(),
  lastHeartbeat: z.string(),
  lastHeartbeatEpoch: z.number(),
  projectRoot: z.string(),
  branch: z.string().optional(),
  pid: z.number(),
});

export type InstanceStatus = z.infer<typeof InstanceStatusSchema>;

// Extended instance info with computed fields
export interface InstanceInfo extends InstanceStatus {
  projectName: string;
  heartbeatAge: number;
  isDead: boolean;
  instanceDir: string;
}

// PRD story structure
export const StorySchema = z.object({
  id: z.string(),
  title: z.string(),
  description: z.string().optional(),
  priority: z.number().default(10),
  acceptanceCriteria: z.array(z.string()).optional(),
  passes: z.boolean().default(false),
  claimedBy: z.string().nullable().optional(),
});

export type Story = z.infer<typeof StorySchema>;

// PRD structure
export const PrdSchema = z.object({
  projectName: z.string().optional(),
  branchName: z.string().default('main'),
  userStories: z.array(StorySchema),
});

export type Prd = z.infer<typeof PrdSchema>;

// PRD progress summary
export interface PrdProgress {
  total: number;
  complete: number;
  remaining: number;
  percentage: number;
  stories: Story[];
}

// Story lock info
export interface LockInfo {
  storyId: string;
  owner: string;
  timestamp: number;
  pid?: number;
  age: number;
  isStale: boolean;
}

// Queue entry structure
export const QueueEntryStatusSchema = z.enum([
  'pending',
  'active',
  'completed',
  'failed',
]);

export type QueueEntryStatus = z.infer<typeof QueueEntryStatusSchema>;

export const QueueEntrySchema = z.object({
  id: z.string(),
  prdPath: z.string(),
  projectRoot: z.string(),
  priority: z.number().default(10),
  status: QueueEntryStatusSchema,
  addedAt: z.string(),
  claimedBy: z.string().nullable().optional(),
  claimedAt: z.string().nullable().optional(),
  completedAt: z.string().nullable().optional(),
});

export type QueueEntry = z.infer<typeof QueueEntrySchema>;

export const QueueSchema = z.object({
  entries: z.array(QueueEntrySchema),
});

export type Queue = z.infer<typeof QueueSchema>;

// Queue summary
export interface QueueSummary {
  total: number;
  pending: number;
  active: number;
  completed: number;
  failed: number;
}

// Rate limit pause file format
export const RateLimitPauseSchema = z.object({
  instanceId: z.string(),
  pausedAt: z.string(),
  pausedAtEpoch: z.number(),
  reason: z.string(),
  detectionMethod: z.string().optional(),
  patternMatched: z.string().optional(),
  backoffSeconds: z.number(),
  retryCount: z.number().default(0),
  maxRetries: z.number().default(5),
  estimatedResumeAt: z.string().optional(),
});

export type RateLimitPause = z.infer<typeof RateLimitPauseSchema>;

// MCP config structure
export const McpServerConfigSchema = z.object({
  enabled: z.boolean().default(false),
  transport: z.enum(['streamable-http', 'stdio']).default('stdio'),
  url: z.string().optional(),
  pollingInterval: z.number().optional(),
  timeout: z.number().optional(),
  retries: z.number().optional(),
  retryDelay: z.number().optional(),
});

export const NotificationEventConfigSchema = z.object({
  enabled: z.boolean().default(false),
  channels: z.array(z.string()).default([]),
  threshold: z.number().optional(),
});

export const McpConfigSchema = z.object({
  servers: z.record(z.string(), McpServerConfigSchema).default({}),
  notifications: z.object({
    events: z.record(z.string(), NotificationEventConfigSchema).default({}),
    rateLimit: z.object({
      maxPerMinute: z.number().default(10),
      burstLimit: z.number().default(3),
    }).optional(),
  }).optional(),
  fallback: z.object({
    enabled: z.boolean().default(true),
    logToFile: z.boolean().default(true),
    logPath: z.string().optional(),
    retryQueue: z.boolean().default(true),
    maxRetries: z.number().default(5),
    retryBackoff: z.enum(['linear', 'exponential']).default('exponential'),
  }).optional(),
});

export type McpConfig = z.infer<typeof McpConfigSchema>;

// Constants
export const DEAD_THRESHOLD_SECONDS = 300; // 5 minutes
export const STALE_LOCK_THRESHOLD_SECONDS = 7200; // 2 hours
