# Ralph MCP Server

MCP (Model Context Protocol) server for claude-ralph that enables Claude Code to control ralph instances.

## Features

- **ralph_status** - Get status of all ralph instances, PRD progress, and story locks
- **ralph_start** - Start new ralph instances (single or parallel)
- **ralph_stop** - Stop running instances (graceful or force)
- **ralph_pause** - Pause an instance after current iteration
- **ralph_resume** - Resume a paused or rate-limited instance
- **ralph_queue_add** - Add a PRD to the global queue
- **ralph_queue_list** - List queue entries with filtering

## Installation

```bash
cd scripts/ralph/mcp
npm install
npm run build
```

## Configuration for Claude Code

Add to your Claude Code MCP configuration (`~/.claude/settings.json` or project `.claude/settings.json`):

```json
{
  "mcpServers": {
    "ralph": {
      "command": "node",
      "args": ["/path/to/scripts/ralph/mcp/dist/server/index.js"]
    }
  }
}
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `RALPH_MCP_IDLE_TIMEOUT` | Server idle timeout in ms | `300000` (5 min) |
| `RALPH_OTEL_ENABLED` | Enable OpenTelemetry | `false` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP collector endpoint | `http://localhost:4318` |
| `OTEL_SERVICE_NAME` | Service name in traces | `ralph-mcp` |

## Tool Reference

### ralph_status

Get comprehensive status of ralph instances and PRD progress.

**Input:**
- `projectRoot` (optional): Filter to specific project
- `includeGlobal` (optional): Include global registry instances (default: true)
- `includeDead` (optional): Include dead instances (default: false)

**Output:**
- `instances`: Array of instance info
- `prd`: PRD progress (if projectRoot specified)
- `locks`: Active story locks
- `summary`: Instance counts by state

### ralph_start

Start one or more ralph instances.

**Input:**
- `prdPath` (required): Absolute path to prd.json
- `projectRoot` (required): Absolute path to project
- `maxIterations` (optional): Max iterations per instance (default: 10)
- `count` (optional): Number of parallel instances (default: 1)
- `queueMode` (optional): Enable queue mode (default: false)

**Output:**
- `instances`: Array of started instance info
- `message`: Status message

### ralph_stop

Stop ralph instances.

**Input:**
- `instanceId` (optional): Specific instance to stop
- `projectRoot` (optional): Stop all in project
- `all` (optional): Stop all instances
- `force` (optional): Use SIGKILL instead of SIGTERM

**Output:**
- `results`: Array of stop results
- `message`: Status message

### ralph_pause

Pause an instance after its current iteration completes.

**Input:**
- `instanceId` (required): Instance ID to pause

**Output:**
- `success`: Boolean
- `previousState`: State before pause request
- `message`: Status message

### ralph_resume

Resume a paused or rate-limited instance.

**Input:**
- `instanceId` (required): Instance ID to resume

**Output:**
- `success`: Boolean
- `message`: Status message

### ralph_queue_add

Add a PRD to the global processing queue.

**Input:**
- `prdPath` (required): Absolute path to prd.json
- `projectRoot` (required): Absolute path to project
- `priority` (optional): Priority 1-99, lower = higher (default: 10)

**Output:**
- `success`: Boolean
- `entryId`: Created queue entry ID
- `message`: Status message

### ralph_queue_list

List queue entries with optional filtering.

**Input:**
- `status` (optional): Filter by status: pending, active, completed, failed, all

**Output:**
- `entries`: Array of queue entries
- `summary`: Queue status counts
- `message`: Status message

## Rate Limit Handling

The MCP server integrates with ralph's rate limit detection:

1. **Output Pattern Detection**: Scans claude-output.log for rate limit patterns
2. **Exit Code Detection**: Exit code 2 indicates rate limiting
3. **Automatic Pause**: Instances enter `rate_limited` state with exponential backoff
4. **Manual Resume**: Use `ralph_resume` to resume before backoff completes

### Rate Monitor Daemon

Start the rate limit monitor daemon:

```bash
./scripts/ralph/ralph-rate-monitor.sh start
./scripts/ralph/ralph-rate-monitor.sh status
./scripts/ralph/ralph-rate-monitor.sh stop
```

Environment variables:
- `RALPH_RATE_POLL_INTERVAL`: Poll interval in seconds (default: 30)
- `RALPH_RATE_API_URL`: Status API to poll (default: status.anthropic.com)
- `RALPH_RATE_PAUSE_ALL`: Pause all instances on API degradation (default: 0)

## OpenTelemetry

Enable observability by setting `RALPH_OTEL_ENABLED=true`:

**Traces:**
- `ralph.tool.{toolName}`: Each MCP tool invocation

**Metrics:**
- `ralph_instances_active`: Gauge of active instances
- `ralph_iterations_total`: Counter of iterations by outcome
- `ralph_rate_limits_total`: Counter of rate limit events
- `ralph_iteration_duration_seconds`: Histogram of iteration durations
- `ralph_backoff_duration_seconds`: Histogram of backoff durations
- `ralph_queue_depth`: Gauge of queue entries by status

## Development

```bash
# Build
npm run build

# Watch mode
npm run dev

# Type check
npm run typecheck
```

## Architecture

```
src/
├── server/
│   ├── index.ts              # MCP server entry point
│   ├── tools/
│   │   ├── index.ts          # Tool registry
│   │   ├── ralph-status.ts   # Status tool
│   │   ├── ralph-start.ts    # Start tool
│   │   ├── ralph-stop.ts     # Stop tool
│   │   ├── ralph-pause.ts    # Pause tool
│   │   ├── ralph-resume.ts   # Resume tool
│   │   ├── ralph-queue-add.ts
│   │   └── ralph-queue-list.ts
│   └── services/
│       ├── state-reader.ts   # Read instance/PRD state
│       ├── process-manager.ts # Start/stop processes
│       ├── pause-manager.ts  # Pause/resume logic
│       └── queue-manager.ts  # Queue operations
├── client/                   # MCP client (future)
└── shared/
    ├── index.ts              # Shared exports
    ├── types.ts              # Zod schemas
    ├── paths.ts              # Path utilities
    ├── platform.ts           # Cross-platform script invocation
    └── telemetry.ts          # OpenTelemetry setup
```
