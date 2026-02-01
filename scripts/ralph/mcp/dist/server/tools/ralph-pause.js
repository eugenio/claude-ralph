import { jsonResponse, errorResponse } from './index.js';
import { pauseInstance } from '../services/pause-manager.js';
export const ralphPauseDefinition = {
    name: 'ralph_pause',
    description: 'Pause a ralph instance after its current iteration completes. The instance will finish its current work and then enter a paused state.',
    inputSchema: {
        type: 'object',
        properties: {
            instanceId: {
                type: 'string',
                description: 'The instance ID to pause (full ID like "user-host-123-timestamp")',
            },
        },
        required: ['instanceId'],
    },
};
export const ralphPauseHandler = async (args) => {
    const instanceId = args.instanceId;
    if (!instanceId) {
        return errorResponse('instanceId is required');
    }
    const result = await pauseInstance(instanceId);
    if (!result.success) {
        return errorResponse(result.error || 'Failed to pause instance');
    }
    return jsonResponse({
        success: true,
        instanceId: result.instanceId,
        previousState: result.previousState,
        message: `Pause requested for instance ${result.instanceId}. It will pause after the current iteration.`,
    });
};
//# sourceMappingURL=ralph-pause.js.map