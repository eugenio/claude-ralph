import { Tracer, Meter, SpanStatusCode } from '@opentelemetry/api';
/**
 * Check if OpenTelemetry is enabled
 */
export declare function isOtelEnabled(): boolean;
/**
 * Initialize OpenTelemetry SDK
 * Uses dynamic import to avoid version conflicts
 */
export declare function initTelemetry(): Promise<void>;
/**
 * Shutdown OpenTelemetry SDK gracefully
 */
export declare function shutdownTelemetry(): Promise<void>;
/**
 * Get a tracer for creating spans
 */
export declare function getTracer(name?: string): Tracer;
/**
 * Get a meter for creating metrics
 */
export declare function getMeter(name?: string): Meter;
/**
 * Record the number of active instances
 */
export declare function recordActiveInstances(count: number, attributes?: Record<string, string>): void;
/**
 * Record an iteration completion
 */
export declare function recordIteration(outcome: 'success' | 'failure' | 'rate_limited', attributes?: Record<string, string>): void;
/**
 * Record a rate limit event
 */
export declare function recordRateLimit(detectionMethod: string, attributes?: Record<string, string>): void;
/**
 * Record iteration duration
 */
export declare function recordIterationDuration(durationSeconds: number, attributes?: Record<string, string>): void;
/**
 * Record backoff duration
 */
export declare function recordBackoffDuration(durationSeconds: number, retryCount: number): void;
/**
 * Record queue depth
 */
export declare function recordQueueDepth(depth: number, status?: string): void;
/**
 * Create a span for tracing a tool invocation
 */
export declare function traceToolInvocation<T>(toolName: string, fn: () => Promise<T>): Promise<T>;
export { SpanStatusCode };
export declare const DEFAULT_IDLE_TIMEOUT_MS: number;
//# sourceMappingURL=telemetry.d.ts.map