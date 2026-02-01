import { jsonResponse } from './index.js';
import { listQueueEntries, getQueueSummary } from '../services/queue-manager.js';
export const ralphQueueListDefinition = {
    name: 'ralph_queue_list',
    description: 'List queue entries with optional filtering by status',
    inputSchema: {
        type: 'object',
        properties: {
            status: {
                type: 'string',
                enum: ['pending', 'active', 'completed', 'failed', 'all'],
                description: 'Filter by status (default: all)',
            },
        },
    },
};
export const ralphQueueListHandler = async (args) => {
    const statusFilter = args.status || 'all';
    const entries = await listQueueEntries({
        status: statusFilter,
    });
    const summary = await getQueueSummary();
    return jsonResponse({
        entries,
        summary,
        message: `Found ${entries.length} queue entries`,
    });
};
//# sourceMappingURL=ralph-queue-list.js.map