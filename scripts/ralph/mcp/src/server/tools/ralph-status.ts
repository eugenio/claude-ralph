import { z } from 'zod';
import {
  getAllInstances,
  getPrdProgress,
  readLocks,
} from '../services/state-reader.js';
import { getProjectPaths } from '../../shared/paths.js';
import { jsonResponse, errorResponse, ToolDefinition, ToolHandler } from './index.js';

// Input schema
export const RalphStatusInputSchema = z.object({
  projectRoot: z.string().optional(),
  includeGlobal: z.boolean().default(true),
  includeDead: z.boolean().default(false),
});

export type RalphStatusInput = z.infer<typeof RalphStatusInputSchema>;

// Tool definition
export const ralphStatusDefinition: ToolDefinition = {
  name: 'ralph_status',
  description: 'Get status of ralph instances, PRD progress, and locks',
  inputSchema: {
    type: 'object',
    properties: {
      projectRoot: {
        type: 'string',
        description: 'Project root directory to scope instance discovery',
      },
      includeGlobal: {
        type: 'boolean',
        description: 'Include instances from global registry (default: true)',
      },
      includeDead: {
        type: 'boolean',
        description: 'Include dead instances with no heartbeat > 5 min (default: false)',
      },
    },
  },
};

// Tool handler
export const ralphStatusHandler: ToolHandler = async (args) => {
  try {
    const input = RalphStatusInputSchema.parse(args);

    // Get all instances
    const instances = await getAllInstances({
      projectRoot: input.projectRoot,
      includeGlobal: input.includeGlobal,
      includeDead: input.includeDead,
    });

    // Format instances for output
    const formattedInstances = instances.map(inst => ({
      instanceId: inst.instanceId,
      shortId: inst.shortId,
      state: inst.state,
      currentStory: inst.currentStory || null,
      iteration: inst.iteration,
      maxIterations: inst.maxIterations,
      projectRoot: inst.projectRoot,
      projectName: inst.projectName,
      branch: inst.branch || null,
      lastHeartbeat: inst.lastHeartbeat,
      heartbeatAge: inst.heartbeatAge,
      isDead: inst.isDead,
      pid: inst.pid,
    }));

    // Get PRD progress if projectRoot specified
    let prd = null;
    let locks: Array<{
      storyId: string;
      owner: string;
      age: number;
      isStale: boolean;
    }> = [];

    if (input.projectRoot) {
      const projectPaths = getProjectPaths(input.projectRoot);

      // Read PRD
      const prdProgress = await getPrdProgress(projectPaths.prdFile);
      if (prdProgress) {
        prd = {
          total: prdProgress.total,
          complete: prdProgress.complete,
          remaining: prdProgress.remaining,
          percentage: prdProgress.percentage,
          stories: prdProgress.stories.map(s => ({
            id: s.id,
            title: s.title,
            priority: s.priority,
            passes: s.passes,
            claimedBy: s.claimedBy || null,
          })),
        };
      }

      // Read locks
      const lockInfos = await readLocks(projectPaths.locksDir);
      locks = lockInfos.map(l => ({
        storyId: l.storyId,
        owner: l.owner,
        age: l.age,
        isStale: l.isStale,
      }));
    }

    return jsonResponse({
      instances: formattedInstances,
      prd,
      locks,
      summary: {
        totalInstances: formattedInstances.length,
        activeInstances: formattedInstances.filter(
          i => !i.isDead && !['completed', 'terminated'].includes(i.state)
        ).length,
        deadInstances: formattedInstances.filter(i => i.isDead).length,
      },
    });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return errorResponse(`Invalid input: ${error.message}`);
    }
    return errorResponse(
      error instanceof Error ? error.message : String(error)
    );
  }
};
