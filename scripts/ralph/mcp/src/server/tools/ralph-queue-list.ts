import { ToolDefinition, ToolHandler, jsonResponse } from './index.js';
import { listQueueEntries, getQueueSummary } from '../services/queue-manager.js';
import { QueueEntryStatus } from '../../shared/index.js';

export const ralphQueueListDefinition: ToolDefinition = {
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

export const ralphQueueListHandler: ToolHandler = async (args) => {
  const statusFilter = (args.status as string | undefined) || 'all';

  const entries = await listQueueEntries({
    status: statusFilter as QueueEntryStatus | 'all',
  });

  const summary = await getQueueSummary();

  return jsonResponse({
    entries,
    summary,
    message: `Found ${entries.length} queue entries`,
  });
};
