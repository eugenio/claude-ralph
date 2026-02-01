import { traceToolInvocation } from '../../shared/index.js';
import { ralphStatusDefinition, ralphStatusHandler } from './ralph-status.js';
import { ralphStartDefinition, ralphStartHandler } from './ralph-start.js';
import { ralphStopDefinition, ralphStopHandler } from './ralph-stop.js';
import { ralphPauseDefinition, ralphPauseHandler } from './ralph-pause.js';
import { ralphResumeDefinition, ralphResumeHandler } from './ralph-resume.js';
import { ralphQueueAddDefinition, ralphQueueAddHandler } from './ralph-queue-add.js';
import { ralphQueueListDefinition, ralphQueueListHandler } from './ralph-queue-list.js';
import {
  ralphNotifyDefinition,
  ralphNotifyHandler,
  ralphNotifyConfigDefinition,
  ralphNotifyConfigHandler,
  ralphNotifyHistoryDefinition,
  ralphNotifyHistoryHandler,
} from './ralph-notify.js';

// Tool definition type matching MCP SDK
export interface ToolDefinition {
  name: string;
  description: string;
  inputSchema: {
    type: 'object';
    properties: Record<string, unknown>;
    required?: string[];
  };
}

// Tool handler type
export type ToolHandler = (
  args: Record<string, unknown>
) => Promise<{ content: Array<{ type: 'text'; text: string }> }>;

// Registry of tools
const toolRegistry: Map<string, {
  definition: ToolDefinition;
  handler: ToolHandler;
}> = new Map();

/**
 * Register a tool with the MCP server
 */
export function registerTool(
  definition: ToolDefinition,
  handler: ToolHandler
): void {
  toolRegistry.set(definition.name, { definition, handler });
}

/**
 * Get all tool definitions
 */
export function getToolDefinitions(): ToolDefinition[] {
  return Array.from(toolRegistry.values()).map(t => t.definition);
}

/**
 * Handle a tool call
 */
export async function handleToolCall(
  name: string,
  args: Record<string, unknown>
): Promise<{ content: Array<{ type: 'text'; text: string }> }> {
  const tool = toolRegistry.get(name);

  if (!tool) {
    return {
      content: [{
        type: 'text',
        text: JSON.stringify({ error: `Unknown tool: ${name}` }),
      }],
    };
  }

  try {
    return await traceToolInvocation(name, () => tool.handler(args));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      content: [{
        type: 'text',
        text: JSON.stringify({ error: message }),
      }],
    };
  }
}

/**
 * Helper to create successful JSON response
 */
export function jsonResponse(
  data: unknown
): { content: Array<{ type: 'text'; text: string }> } {
  return {
    content: [{
      type: 'text',
      text: JSON.stringify(data, null, 2),
    }],
  };
}

/**
 * Helper to create error response
 */
export function errorResponse(
  message: string
): { content: Array<{ type: 'text'; text: string }> } {
  return {
    content: [{
      type: 'text',
      text: JSON.stringify({ error: message }),
    }],
  };
}

// Register all tools
export function registerTools(): void {
  // Implemented tools
  registerTool(ralphStatusDefinition, ralphStatusHandler);
  registerTool(ralphStartDefinition, ralphStartHandler);
  registerTool(ralphStopDefinition, ralphStopHandler);
  registerTool(ralphPauseDefinition, ralphPauseHandler);
  registerTool(ralphResumeDefinition, ralphResumeHandler);
  registerTool(ralphQueueAddDefinition, ralphQueueAddHandler);
  registerTool(ralphQueueListDefinition, ralphQueueListHandler);
  registerTool(ralphNotifyDefinition, ralphNotifyHandler);
  registerTool(ralphNotifyConfigDefinition, ralphNotifyConfigHandler);
  registerTool(ralphNotifyHistoryDefinition, ralphNotifyHistoryHandler);
}

// Auto-register tools on module load
registerTools();
