#!/bin/bash

# Ralph Loop Process Supervisor
# Monitors Claude Code process and restarts on crash
# Provides true process supervision with crash recovery

set -euo pipefail

# ============================================================================
# Configuration Defaults
# ============================================================================
MAX_ITERATIONS=0       # 0 = unlimited
MAX_RESTARTS=10        # Max crash restarts before giving up
RESTART_DELAY=5        # Seconds between restarts
COMPLETION_PROMISE=""  # Optional completion promise text
VERBOSE=false          # Verbose logging
BACKGROUND=false       # Run as daemon
PROMPT=""              # The prompt to run

# Internal state
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE=".claude/ralph-supervisor.local.json"
LOG_FILE=".claude/ralph-supervisor.log"
PID_FILE=".claude/ralph-supervisor.pid"
CLAUDE_PID_FILE=".claude/ralph-supervisor-claude.pid"

# Runtime tracking
iteration=1
restart_count=0
started_at=""
foreground_internal=false

# ============================================================================
# Usage
# ============================================================================
usage() {
    cat <<EOF
Ralph Loop Process Supervisor

USAGE:
    ralph-supervisor.sh [OPTIONS] "PROMPT"

OPTIONS:
    --max-iterations N      Max iterations (0 = unlimited, default: 0)
    --max-restarts N        Max crash restarts before giving up (default: 10)
    --restart-delay N       Seconds between restarts (default: 5)
    --completion-promise T  Promise text to detect completion
    --background            Run as detached daemon
    --verbose               Enable verbose logging
    --help                  Show this help message

EXAMPLES:
    # Run interactively with max 10 iterations
    ralph-supervisor.sh --max-iterations 10 "Build a REST API"

    # Run in background as daemon
    ralph-supervisor.sh --background --max-restarts 5 "Long running task"

    # With completion promise
    ralph-supervisor.sh --completion-promise "DONE" "Complete when ready"

EOF
    exit 0
}

# ============================================================================
# Logging
# ============================================================================
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$level] $msg"

    # Always write to log file
    echo "$log_entry" >> "$LOG_FILE"

    # Print to stdout if verbose or if it's an error/important message
    if [[ "$VERBOSE" == "true" ]] || [[ "$level" == "ERROR" ]] || [[ "$level" == "WARN" ]]; then
        echo "$log_entry" >&2
    fi
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { [[ "$VERBOSE" == "true" ]] && log "DEBUG" "$@" || true; }

# ============================================================================
# State Management
# ============================================================================
ensure_claude_dir() {
    mkdir -p .claude
}

write_state() {
    local status="${1:-running}"
    local claude_pid="${2:-}"

    cat > "$STATE_FILE" <<EOF
{
  "pid": $$,
  "claude_pid": ${claude_pid:-null},
  "started_at": "$started_at",
  "iteration": $iteration,
  "restart_count": $restart_count,
  "max_iterations": $MAX_ITERATIONS,
  "max_restarts": $MAX_RESTARTS,
  "completion_promise": $(echo "$COMPLETION_PROMISE" | jq -R .),
  "prompt": $(echo "$PROMPT" | jq -R .),
  "status": "$status",
  "log_file": "$LOG_FILE",
  "last_update": "$(date -Iseconds)"
}
EOF
}

update_state() {
    local status="${1:-running}"
    local claude_pid="${2:-}"
    write_state "$status" "$claude_pid"
}

cleanup() {
    log_info "Cleaning up supervisor state files"
    rm -f "$STATE_FILE" "$PID_FILE" "$CLAUDE_PID_FILE" 2>/dev/null || true
}

# ============================================================================
# Signal Handlers
# ============================================================================
cleanup_and_exit() {
    local signal="$1"
    log_info "Received $signal signal, shutting down..."

    # Kill Claude if running
    if [[ -f "$CLAUDE_PID_FILE" ]]; then
        local claude_pid
        claude_pid=$(cat "$CLAUDE_PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$claude_pid" ]] && kill -0 "$claude_pid" 2>/dev/null; then
            log_info "Stopping Claude process (PID: $claude_pid)"
            kill -TERM "$claude_pid" 2>/dev/null || true
            # Wait a moment for graceful shutdown
            sleep 2
            # Force kill if still running
            if kill -0 "$claude_pid" 2>/dev/null; then
                kill -KILL "$claude_pid" 2>/dev/null || true
            fi
        fi
    fi

    cleanup
    exit 0
}

setup_signal_handlers() {
    trap 'cleanup_and_exit SIGINT' SIGINT
    trap 'cleanup_and_exit SIGTERM' SIGTERM
    trap 'cleanup_and_exit SIGHUP' SIGHUP
}

# ============================================================================
# Argument Parsing
# ============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --max-iterations)
                MAX_ITERATIONS="$2"
                shift 2
                ;;
            --max-restarts)
                MAX_RESTARTS="$2"
                shift 2
                ;;
            --restart-delay)
                RESTART_DELAY="$2"
                shift 2
                ;;
            --completion-promise)
                COMPLETION_PROMISE="$2"
                shift 2
                ;;
            --background)
                BACKGROUND=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --foreground-internal)
                foreground_internal=true
                shift
                ;;
            --help|-h)
                usage
                ;;
            -*)
                echo "Unknown option: $1" >&2
                usage
                ;;
            *)
                if [[ -z "$PROMPT" ]]; then
                    PROMPT="$1"
                else
                    echo "Error: Multiple prompts provided" >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$PROMPT" ]]; then
        echo "Error: PROMPT is required" >&2
        cat <<EOF
Ralph Loop Process Supervisor

USAGE:
    ralph-supervisor.sh [OPTIONS] "PROMPT"

Run 'ralph-supervisor.sh --help' for more information.
EOF
        exit 1
    fi
}

# ============================================================================
# Exit Code Handling
# ============================================================================
handle_exit_code() {
    local exit_code=$1

    case $exit_code in
        0)
            log_info "Claude exited successfully (code 0)"
            echo ""
            echo "Ralph supervisor: Claude completed successfully"
            cleanup
            exit 0
            ;;
        130)
            # SIGINT (Ctrl+C)
            log_info "Claude interrupted by user (SIGINT)"
            echo ""
            echo "Ralph supervisor: Stopped by user (Ctrl+C)"
            cleanup
            exit 0
            ;;
        143)
            # SIGTERM
            log_info "Claude terminated (SIGTERM)"
            echo ""
            echo "Ralph supervisor: Stopped by SIGTERM"
            cleanup
            exit 0
            ;;
        137)
            # SIGKILL - could be intentional or OOM
            log_warn "Claude was killed (SIGKILL, exit 137)"
            # Check if we should restart
            should_restart "SIGKILL"
            ;;
        *)
            log_warn "Claude crashed with exit code $exit_code"
            should_restart "exit code $exit_code"
            ;;
    esac
}

should_restart() {
    local reason="$1"

    ((restart_count++))

    if [[ $restart_count -ge $MAX_RESTARTS ]]; then
        log_error "Max restarts ($MAX_RESTARTS) reached after $reason"
        echo ""
        echo "Ralph supervisor: Max restarts ($MAX_RESTARTS) reached"
        echo "Check log for details: $LOG_FILE"
        cleanup
        exit 1
    fi

    log_info "Crash detected ($reason), restart $restart_count/$MAX_RESTARTS in ${RESTART_DELAY}s"
    echo ""
    echo "Ralph supervisor: Crash detected ($reason)"
    echo "Restarting in ${RESTART_DELAY}s (attempt $restart_count/$MAX_RESTARTS)..."

    sleep "$RESTART_DELAY"

    # Increment iteration and update state
    ((iteration++))
    update_state "restarting"
}

# ============================================================================
# Main Loop (Foreground)
# ============================================================================
run_foreground() {
    ensure_claude_dir
    setup_signal_handlers

    started_at=$(date -Iseconds)
    echo $$ > "$PID_FILE"
    write_state "running"

    log_info "Starting Ralph supervisor"
    log_info "Prompt: $PROMPT"
    log_info "Max iterations: $MAX_ITERATIONS (0=unlimited)"
    log_info "Max restarts: $MAX_RESTARTS"
    log_info "Completion promise: ${COMPLETION_PROMISE:-<none>}"

    echo ""
    echo "Ralph supervisor started (PID: $$)"
    echo "Log file: $LOG_FILE"
    echo "State file: $STATE_FILE"
    echo "Stop with: Ctrl+C or ralph-stop.sh"
    echo ""

    while true; do
        # Check max iterations
        if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $iteration -gt $MAX_ITERATIONS ]]; then
            log_info "Max iterations ($MAX_ITERATIONS) reached"
            echo ""
            echo "Ralph supervisor: Max iterations ($MAX_ITERATIONS) reached"
            cleanup
            exit 0
        fi

        log_info "Starting iteration $iteration"

        local claude_args
        if [[ $iteration -eq 1 ]]; then
            # First iteration: start with prompt
            log_debug "Running: claude -p \"$PROMPT\""
            claude_args=(-p "$PROMPT")
        else
            # Subsequent iterations: continue previous session
            log_debug "Running: claude --continue"
            claude_args=(--continue)
        fi

        # Start Claude and capture its PID
        update_state "running"

        # Run Claude in foreground, capturing exit code
        set +e
        claude "${claude_args[@]}" 2>&1 | tee -a "$LOG_FILE"
        local exit_code=${PIPESTATUS[0]}
        set -e

        log_debug "Claude exited with code: $exit_code"

        # Handle the exit code
        handle_exit_code $exit_code
    done
}

# ============================================================================
# Background Mode
# ============================================================================
run_background() {
    ensure_claude_dir

    # Check if already running
    if [[ -f "$PID_FILE" ]]; then
        local existing_pid
        existing_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            echo "Error: Ralph supervisor already running (PID: $existing_pid)"
            echo "Use ralph-stop.sh to stop it first"
            exit 1
        else
            # Stale PID file
            rm -f "$PID_FILE"
        fi
    fi

    echo "Starting Ralph supervisor in background..."

    # Build argument list for subprocess
    local args=()
    args+=(--foreground-internal)
    [[ $MAX_ITERATIONS -gt 0 ]] && args+=(--max-iterations "$MAX_ITERATIONS")
    [[ $MAX_RESTARTS -ne 10 ]] && args+=(--max-restarts "$MAX_RESTARTS")
    [[ $RESTART_DELAY -ne 5 ]] && args+=(--restart-delay "$RESTART_DELAY")
    [[ -n "$COMPLETION_PROMISE" ]] && args+=(--completion-promise "$COMPLETION_PROMISE")
    [[ "$VERBOSE" == "true" ]] && args+=(--verbose)
    args+=("$PROMPT")

    # Start in background with nohup
    nohup "$0" "${args[@]}" > "$LOG_FILE" 2>&1 &
    local bg_pid=$!

    echo $bg_pid > "$PID_FILE"

    echo ""
    echo "Ralph supervisor started in background"
    echo "  PID: $bg_pid"
    echo "  Log: $LOG_FILE"
    echo "  State: $STATE_FILE"
    echo ""
    echo "Commands:"
    echo "  Check status: ralph-status.sh"
    echo "  Stop: ralph-stop.sh"
    echo "  View logs: tail -f $LOG_FILE"
}

# ============================================================================
# Main Entry Point
# ============================================================================
main() {
    parse_args "$@"

    if [[ "$BACKGROUND" == "true" ]]; then
        run_background
    else
        run_foreground
    fi
}

main "$@"
