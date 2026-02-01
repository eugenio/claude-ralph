export interface ToolDefinition {
    name: string;
    description: string;
    inputSchema: {
        type: 'object';
        properties: Record<string, unknown>;
        required?: string[];
    };
}
export type ToolHandler = (args: Record<string, unknown>) => Promise<{
    content: Array<{
        type: 'text';
        text: string;
    }>;
}>;
/**
 * Register a tool with the MCP server
 */
export declare function registerTool(definition: ToolDefinition, handler: ToolHandler): void;
/**
 * Get all tool definitions
 */
export declare function getToolDefinitions(): ToolDefinition[];
/**
 * Handle a tool call
 */
export declare function handleToolCall(name: string, args: Record<string, unknown>): Promise<{
    content: Array<{
        type: 'text';
        text: string;
    }>;
}>;
/**
 * Helper to create successful JSON response
 */
export declare function jsonResponse(data: unknown): {
    content: Array<{
        type: 'text';
        text: string;
    }>;
};
/**
 * Helper to create error response
 */
export declare function errorResponse(message: string): {
    content: Array<{
        type: 'text';
        text: string;
    }>;
};
export declare function registerTools(): void;
//# sourceMappingURL=index.d.ts.map