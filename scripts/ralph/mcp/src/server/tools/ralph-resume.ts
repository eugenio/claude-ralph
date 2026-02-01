import { ToolDefinition, ToolHandler, jsonResponse, errorResponse } from './index.js';
import { resumeInstance } from '../services/pause-manager.js';

export const ralphResumeDefinition: ToolDefinition = {
  name: 'ralph_resume',
  description: 'Resume a paused or rate-limited ralph instance. The instance will continue from where it left off.',
  inputSchema: {
    type: 'object',
    properties: {
      instanceId: {
        type: 'string',
        description: 'The instance ID to resume (full ID like "user-host-123-timestamp")',
      },
    },
    required: ['instanceId'],
  },
};

export const ralphResumeHandler: ToolHandler = async (args) => {
  const instanceId = args.instanceId as string | undefined;

  if (!instanceId) {
    return errorResponse('instanceId is required');
  }

  const result = await resumeInstance(instanceId);

  if (!result.success) {
    return errorResponse(result.error || 'Failed to resume instance');
  }

  return jsonResponse({
    success: true,
    instanceId: result.instanceId,
    message: `Resume requested for instance ${result.instanceId}. It will continue processing.`,
  });
};
