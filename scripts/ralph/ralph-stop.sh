#!/bin/bash

# Ralph Loop Process Supervisor - Graceful Stop
# Stops the supervisor and Claude processes cleanly

set -euo pipefail

STATE_FILE=".claude/ralph-supervisor.local.json"
LOG_FILE=".claude/ralph-supervisor.log"
PID_FILE=".claude/ralph-supervisor.pid"
CLAUDE_PID_FILE=".claude/ralph-supervisor-claude.pid"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Options
FORCE=false

# ============================================================================
# Usage
# ============================================================================
usage() {
    cat <<EOF
Ralph Loop Process Supervisor - Stop

USAGE:
    ralph-stop.sh [OPTIONS]

OPTIONS:
    --force, -f   Force kill (SIGKILL) instead of graceful shutdown
    --help, -h    Show this help

DESCRIPTION:
    Gracefully stops the Ralph supervisor and any running Claude process.
    By default, sends SIGTERM and waits for clean shutdown.
    Use --force for immediate termination (SIGKILL).

EOF
    exit 0
}

# ============================================================================
# Argument Parsing
# ============================================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

# ============================================================================
# Stop Functions
# ============================================================================
stop_process() {
    local pid=$1
    local name=$2
    local force=$3

    if [[ -z "$pid" ]] || [[ "$pid" == "null" ]]; then
        return 0
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        echo -e "  $name (PID $pid): ${YELLOW}Not running${NC}"
        return 0
    fi

    if [[ "$force" == "true" ]]; then
        echo -e "  $name (PID $pid): Force killing..."
        kill -KILL "$pid" 2>/dev/null || true
    else
        echo -e "  $name (PID $pid): Sending SIGTERM..."
        kill -TERM "$pid" 2>/dev/null || true

        # Wait for graceful shutdown (up to 10 seconds)
        local waited=0
        while kill -0 "$pid" 2>/dev/null && [[ $waited -lt 10 ]]; do
            sleep 1
            ((waited++))
        done

        if kill -0 "$pid" 2>/dev/null; then
            echo -e "  $name (PID $pid): ${YELLOW}Still running, force killing...${NC}"
            kill -KILL "$pid" 2>/dev/null || true
        fi
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        echo -e "  $name (PID $pid): ${GREEN}Stopped${NC}"
    else
        echo -e "  $name (PID $pid): ${RED}Failed to stop${NC}"
        return 1
    fi

    return 0
}

cleanup_files() {
    echo ""
    echo "Cleaning up state files..."

    for file in "$STATE_FILE" "$PID_FILE" "$CLAUDE_PID_FILE"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            echo -e "  Removed: $file"
        fi
    done
}

# ============================================================================
# Main
# ============================================================================
echo ""
echo "Ralph Loop Supervisor - Stop"
echo "=============================="
echo ""

# Check if state file exists
if [[ ! -f "$STATE_FILE" ]] && [[ ! -f "$PID_FILE" ]]; then
    echo -e "${YELLOW}No Ralph supervisor appears to be running.${NC}"
    echo ""
    echo "No state files found:"
    echo "  - $STATE_FILE"
    echo "  - $PID_FILE"
    echo ""
    exit 0
fi

# Get PIDs
supervisor_pid=""
claude_pid=""

if [[ -f "$STATE_FILE" ]]; then
    supervisor_pid=$(jq -r '.pid // empty' "$STATE_FILE" 2>/dev/null || echo "")
    claude_pid=$(jq -r '.claude_pid // empty' "$STATE_FILE" 2>/dev/null || echo "")
fi

# Fallback to PID file
if [[ -z "$supervisor_pid" ]] && [[ -f "$PID_FILE" ]]; then
    supervisor_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
fi

if [[ -z "$claude_pid" ]] && [[ -f "$CLAUDE_PID_FILE" ]]; then
    claude_pid=$(cat "$CLAUDE_PID_FILE" 2>/dev/null || echo "")
fi

echo "Stopping processes..."

# Stop Claude first (if running)
if [[ -n "$claude_pid" ]] && [[ "$claude_pid" != "null" ]]; then
    stop_process "$claude_pid" "Claude" "$FORCE" || true
fi

# Stop supervisor
if [[ -n "$supervisor_pid" ]]; then
    stop_process "$supervisor_pid" "Supervisor" "$FORCE" || true
fi

# Clean up files
cleanup_files

echo ""
echo -e "${GREEN}Ralph supervisor stopped.${NC}"
echo ""

# Log the stop
if [[ -f "$LOG_FILE" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Supervisor stopped by ralph-stop.sh" >> "$LOG_FILE"
fi
