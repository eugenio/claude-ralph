import { z } from 'zod';
import {
  startInstance,
  startParallelInstances,
} from '../services/process-manager.js';
import { jsonResponse, errorResponse, ToolDefinition, ToolHandler } from './index.js';

export const RalphStartInputSchema = z.object({
  prdPath: z.string(),
  projectRoot: z.string(),
  maxIterations: z.number().min(1).max(100).default(10),
  count: z.number().min(1).max(16).default(1),
  queueMode: z.boolean().default(false),
});

export type RalphStartInput = z.infer<typeof RalphStartInputSchema>;

export const ralphStartDefinition: ToolDefinition = {
  name: 'ralph_start',
  description: 'Start new ralph instance(s)',
  inputSchema: {
    type: 'object',
    properties: {
      prdPath: {
        type: 'string',
        description: 'Absolute path to prd.json file',
      },
      projectRoot: {
        type: 'string',
        description: 'Absolute path to project root directory',
      },
      maxIterations: {
        type: 'number',
        description: 'Maximum iterations per instance (default: 10)',
      },
      count: {
        type: 'number',
        description: 'Number of parallel instances to start (default: 1)',
      },
      queueMode: {
        type: 'boolean',
        description: 'Enable queue mode (default: false)',
      },
    },
    required: ['prdPath', 'projectRoot'],
  },
};

export const ralphStartHandler: ToolHandler = async (args) => {
  try {
    const input = RalphStartInputSchema.parse(args);

    if (input.count > 1) {
      // Start parallel instances
      const results = await startParallelInstances({
        prdPath: input.prdPath,
        projectRoot: input.projectRoot,
        maxIterations: input.maxIterations,
        queueMode: input.queueMode,
        count: input.count,
      });

      const successful = results.filter(r => r.success);
      const failed = results.filter(r => !r.success);

      return jsonResponse({
        success: failed.length === 0,
        message: `Started ${successful.length} instance(s)`,
        instances: successful.map(r => ({
          instanceId: r.instanceId,
          shortId: r.shortId,
          pid: r.pid,
          logFile: r.logFile,
        })),
        errors: failed.map(r => r.error),
      });
    } else {
      // Start single instance
      const result = await startInstance({
        prdPath: input.prdPath,
        projectRoot: input.projectRoot,
        maxIterations: input.maxIterations,
        queueMode: input.queueMode,
      });

      if (!result.success) {
        return errorResponse(result.error || 'Failed to start instance');
      }

      return jsonResponse({
        success: true,
        message: 'Instance started',
        instance: {
          instanceId: result.instanceId,
          shortId: result.shortId,
          pid: result.pid,
          logFile: result.logFile,
        },
      });
    }
  } catch (error) {
    if (error instanceof z.ZodError) {
      return errorResponse(`Invalid input: ${error.message}`);
    }
    return errorResponse(
      error instanceof Error ? error.message : String(error)
    );
  }
};
