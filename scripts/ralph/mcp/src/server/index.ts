#!/usr/bin/env node
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';

import {
  initTelemetry,
  shutdownTelemetry,
  DEFAULT_IDLE_TIMEOUT_MS,
} from '../shared/index.js';
import { handleToolCall, getToolDefinitions } from './tools/index.js';

const SERVER_NAME = 'ralph-mcp';
const SERVER_VERSION = '1.0.0';

// Idle timeout management
let idleTimer: NodeJS.Timeout | null = null;
const IDLE_TIMEOUT_MS = parseInt(
  process.env.RALPH_MCP_IDLE_TIMEOUT || String(DEFAULT_IDLE_TIMEOUT_MS),
  10
);

function resetIdleTimer(): void {
  if (idleTimer) {
    clearTimeout(idleTimer);
  }
  idleTimer = setTimeout(() => {
    console.error(`[${SERVER_NAME}] Idle timeout reached, shutting down`);
    shutdown();
  }, IDLE_TIMEOUT_MS);
}

async function shutdown(): Promise<void> {
  if (idleTimer) {
    clearTimeout(idleTimer);
  }
  await shutdownTelemetry();
  process.exit(0);
}

async function main(): Promise<void> {
  // Initialize OpenTelemetry if enabled
  await initTelemetry();

  // Create MCP server
  const server = new Server(
    {
      name: SERVER_NAME,
      version: SERVER_VERSION,
    },
    {
      capabilities: {
        tools: {},
      },
    }
  );

  // Register tool list handler
  server.setRequestHandler(ListToolsRequestSchema, async () => {
    resetIdleTimer();
    return {
      tools: getToolDefinitions(),
    };
  });

  // Register tool call handler
  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    resetIdleTimer();
    const { name, arguments: args } = request.params;
    return handleToolCall(name, args || {});
  });

  // Handle shutdown signals
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);

  // Connect via stdio transport
  const transport = new StdioServerTransport();
  await server.connect(transport);

  // Start idle timer
  resetIdleTimer();

  console.error(`[${SERVER_NAME}] Server started (v${SERVER_VERSION})`);
  console.error(`[${SERVER_NAME}] Idle timeout: ${IDLE_TIMEOUT_MS / 1000}s`);
}

main().catch((error) => {
  console.error(`[${SERVER_NAME}] Fatal error:`, error);
  process.exit(1);
});
