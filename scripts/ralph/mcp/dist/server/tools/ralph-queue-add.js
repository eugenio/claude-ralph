import { jsonResponse, errorResponse } from './index.js';
import { addQueueEntry } from '../services/queue-manager.js';
export const ralphQueueAddDefinition = {
    name: 'ralph_queue_add',
    description: 'Add a PRD to the global queue for processing by ralph workers',
    inputSchema: {
        type: 'object',
        properties: {
            prdPath: {
                type: 'string',
                description: 'Absolute path to prd.json file',
            },
            projectRoot: {
                type: 'string',
                description: 'Absolute path to project root',
            },
            priority: {
                type: 'number',
                description: 'Priority (1-99, lower = higher priority, default: 10)',
            },
        },
        required: ['prdPath', 'projectRoot'],
    },
};
export const ralphQueueAddHandler = async (args) => {
    const prdPath = args.prdPath;
    const projectRoot = args.projectRoot;
    const priority = args.priority;
    if (!prdPath) {
        return errorResponse('prdPath is required');
    }
    if (!projectRoot) {
        return errorResponse('projectRoot is required');
    }
    const result = await addQueueEntry({
        prdPath,
        projectRoot,
        priority: priority ?? 10,
    });
    if (!result.success) {
        return errorResponse(result.error || 'Failed to add queue entry');
    }
    return jsonResponse({
        success: true,
        entryId: result.entryId,
        message: `Added PRD to queue with ID: ${result.entryId}`,
    });
};
//# sourceMappingURL=ralph-queue-add.js.map