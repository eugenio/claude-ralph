import { trace, metrics, SpanStatusCode, } from '@opentelemetry/api';
let isInitialized = false;
const SERVICE_NAME = process.env.OTEL_SERVICE_NAME || 'ralph-mcp';
const SERVICE_VERSION = '1.0.0';
/**
 * Check if OpenTelemetry is enabled
 */
export function isOtelEnabled() {
    return process.env.RALPH_OTEL_ENABLED === 'true'
        || process.env.RALPH_OTEL_ENABLED === '1';
}
/**
 * Initialize OpenTelemetry SDK
 * Uses dynamic import to avoid version conflicts
 */
export async function initTelemetry() {
    if (isInitialized || !isOtelEnabled()) {
        return;
    }
    try {
        const { NodeSDK } = await import('@opentelemetry/sdk-node');
        const { OTLPTraceExporter } = await import('@opentelemetry/exporter-trace-otlp-http');
        const { Resource } = await import('@opentelemetry/resources');
        const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT
            || 'http://localhost:4318';
        const resource = new Resource({
            'service.name': SERVICE_NAME,
            'service.version': SERVICE_VERSION,
        });
        const traceExporter = new OTLPTraceExporter({
            url: `${endpoint}/v1/traces`,
        });
        const sdk = new NodeSDK({
            resource,
            traceExporter,
        });
        sdk.start();
        isInitialized = true;
        console.error(`[ralph-mcp] OpenTelemetry initialized (${endpoint})`);
        // Handle shutdown
        process.on('beforeExit', async () => {
            await sdk.shutdown();
        });
    }
    catch (error) {
        console.error('[ralph-mcp] Failed to initialize OpenTelemetry:', error);
    }
}
/**
 * Shutdown OpenTelemetry SDK gracefully
 */
export async function shutdownTelemetry() {
    // SDK shutdown is handled via beforeExit event
    isInitialized = false;
}
/**
 * Get a tracer for creating spans
 */
export function getTracer(name) {
    return trace.getTracer(name || SERVICE_NAME, SERVICE_VERSION);
}
/**
 * Get a meter for creating metrics
 */
export function getMeter(name) {
    return metrics.getMeter(name || SERVICE_NAME, SERVICE_VERSION);
}
// Pre-configured metrics (lazy initialized)
let metricsInitialized = false;
let instancesActiveGauge;
let iterationsCounter;
let rateLimitsCounter;
let iterationDurationHistogram;
let backoffDurationHistogram;
let queueDepthGauge;
/**
 * Initialize metrics instruments
 */
function initMetrics() {
    if (metricsInitialized || !isOtelEnabled()) {
        return;
    }
    const meter = getMeter();
    instancesActiveGauge = meter.createGauge('ralph_instances_active', {
        description: 'Number of active ralph instances',
    });
    iterationsCounter = meter.createCounter('ralph_iterations_total', {
        description: 'Total number of ralph iterations',
    });
    rateLimitsCounter = meter.createCounter('ralph_rate_limits_total', {
        description: 'Total number of rate limit events',
    });
    iterationDurationHistogram = meter.createHistogram('ralph_iteration_duration_seconds', {
        description: 'Duration of ralph iterations in seconds',
        unit: 's',
    });
    backoffDurationHistogram = meter.createHistogram('ralph_backoff_duration_seconds', {
        description: 'Duration of rate limit backoff in seconds',
        unit: 's',
    });
    queueDepthGauge = meter.createGauge('ralph_queue_depth', {
        description: 'Number of entries in the queue',
    });
    metricsInitialized = true;
}
/**
 * Record the number of active instances
 */
export function recordActiveInstances(count, attributes) {
    if (!isOtelEnabled())
        return;
    initMetrics();
    instancesActiveGauge?.record(count, attributes);
}
/**
 * Record an iteration completion
 */
export function recordIteration(outcome, attributes) {
    if (!isOtelEnabled())
        return;
    initMetrics();
    iterationsCounter?.add(1, { outcome, ...attributes });
}
/**
 * Record a rate limit event
 */
export function recordRateLimit(detectionMethod, attributes) {
    if (!isOtelEnabled())
        return;
    initMetrics();
    rateLimitsCounter?.add(1, { detection_method: detectionMethod, ...attributes });
}
/**
 * Record iteration duration
 */
export function recordIterationDuration(durationSeconds, attributes) {
    if (!isOtelEnabled())
        return;
    initMetrics();
    iterationDurationHistogram?.record(durationSeconds, attributes);
}
/**
 * Record backoff duration
 */
export function recordBackoffDuration(durationSeconds, retryCount) {
    if (!isOtelEnabled())
        return;
    initMetrics();
    backoffDurationHistogram?.record(durationSeconds, { retry_count: String(retryCount) });
}
/**
 * Record queue depth
 */
export function recordQueueDepth(depth, status) {
    if (!isOtelEnabled())
        return;
    initMetrics();
    queueDepthGauge?.record(depth, status ? { status } : undefined);
}
/**
 * Create a span for tracing a tool invocation
 */
export async function traceToolInvocation(toolName, fn) {
    if (!isOtelEnabled()) {
        return fn();
    }
    const tracer = getTracer();
    return tracer.startActiveSpan(`ralph.tool.${toolName}`, async (span) => {
        try {
            const result = await fn();
            span.setStatus({ code: SpanStatusCode.OK });
            return result;
        }
        catch (error) {
            span.setStatus({
                code: SpanStatusCode.ERROR,
                message: error instanceof Error ? error.message : String(error),
            });
            throw error;
        }
        finally {
            span.end();
        }
    });
}
export { SpanStatusCode };
export const DEFAULT_IDLE_TIMEOUT_MS = 5 * 60 * 1000; // 5 minutes
//# sourceMappingURL=telemetry.js.map