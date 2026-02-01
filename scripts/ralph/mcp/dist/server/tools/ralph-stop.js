import { z } from 'zod';
import { stopInstance, stopAllInstances, } from '../services/process-manager.js';
import { jsonResponse, errorResponse } from './index.js';
export const RalphStopInputSchema = z.object({
    instanceId: z.string().optional(),
    force: z.boolean().default(false),
    projectRoot: z.string().optional(),
});
export const ralphStopDefinition = {
    name: 'ralph_stop',
    description: 'Stop running ralph instances',
    inputSchema: {
        type: 'object',
        properties: {
            instanceId: {
                type: 'string',
                description: 'Specific instance ID to stop (stops all if omitted)',
            },
            force: {
                type: 'boolean',
                description: 'Force kill with SIGKILL (default: false)',
            },
            projectRoot: {
                type: 'string',
                description: 'Project root to scope instance discovery',
            },
        },
    },
};
export const ralphStopHandler = async (args) => {
    try {
        const input = RalphStopInputSchema.parse(args);
        if (input.instanceId) {
            // Stop specific instance
            const result = await stopInstance(input.instanceId, input.force);
            if (!result.success) {
                return errorResponse(result.error || 'Failed to stop instance');
            }
            return jsonResponse({
                success: true,
                message: `Stopped instance ${input.instanceId}`,
                stoppedInstances: [result.instanceId],
            });
        }
        else {
            // Stop all instances
            const results = await stopAllInstances(input.projectRoot, input.force);
            const successful = results.filter(r => r.success);
            const failed = results.filter(r => !r.success);
            if (results.length === 0) {
                return jsonResponse({
                    success: true,
                    message: 'No running instances found',
                    stoppedInstances: [],
                });
            }
            return jsonResponse({
                success: failed.length === 0,
                message: `Stopped ${successful.length} instance(s)`,
                stoppedInstances: successful.map(r => r.instanceId),
                errors: failed.map(r => ({
                    instanceId: r.instanceId,
                    error: r.error,
                })),
            });
        }
    }
    catch (error) {
        if (error instanceof z.ZodError) {
            return errorResponse(`Invalid input: ${error.message}`);
        }
        return errorResponse(error instanceof Error ? error.message : String(error));
    }
};
//# sourceMappingURL=ralph-stop.js.map