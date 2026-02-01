#!/usr/bin/env bash
# =============================================================================
# ralph-rate-monitor.sh - Rate limit monitoring daemon for claude-ralph
# =============================================================================
#
# DESCRIPTION:
#   Background daemon that monitors for rate limits and automatically
#   pauses/resumes ralph instances based on external API status.
#
# USAGE:
#   ./ralph-rate-monitor.sh start       # Start the daemon
#   ./ralph-rate-monitor.sh stop        # Stop the daemon
#   ./ralph-rate-monitor.sh status      # Check daemon status
#   ./ralph-rate-monitor.sh check       # Single check (no daemon)
#
# ENVIRONMENT:
#   RALPH_RATE_POLL_INTERVAL  - Poll interval in seconds (default: 30)
#   RALPH_RATE_API_URL        - API URL to check (optional)
#   RALPH_RATE_PAUSE_ALL      - Pause all instances on rate limit (default: 0)
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ralph-utils.sh"

# Configuration
POLL_INTERVAL="${RALPH_RATE_POLL_INTERVAL:-30}"
API_URL="${RALPH_RATE_API_URL:-https://status.anthropic.com/api/v2/status.json}"
PAUSE_ALL="${RALPH_RATE_PAUSE_ALL:-0}"

# Daemon files
DAEMON_PID_FILE="$(get_ralph_global_dir)/rate-monitor.pid"
DAEMON_LOG_FILE="$(get_ralph_global_dir)/rate-monitor.log"

# =============================================================================
# DAEMON FUNCTIONS
# =============================================================================

daemon_log() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$DAEMON_LOG_FILE"
}

is_daemon_running() {
    if [[ -f "$DAEMON_PID_FILE" ]]; then
        local pid
        pid=$(cat "$DAEMON_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

start_daemon() {
    if is_daemon_running; then
        echo "Rate monitor daemon is already running (PID: $(cat "$DAEMON_PID_FILE"))"
        return 1
    fi

    # Ensure global directory exists
    mkdir -p "$(get_ralph_global_dir)"

    echo "Starting rate limit monitor daemon..."
    echo "  Poll interval: ${POLL_INTERVAL}s"
    echo "  API URL: $API_URL"
    echo "  Log file: $DAEMON_LOG_FILE"

    # Start daemon in background
    nohup bash "$0" _run_daemon >> "$DAEMON_LOG_FILE" 2>&1 &
    local daemon_pid=$!
    echo "$daemon_pid" > "$DAEMON_PID_FILE"

    echo "Daemon started with PID: $daemon_pid"
}

stop_daemon() {
    if ! is_daemon_running; then
        echo "Rate monitor daemon is not running"
        rm -f "$DAEMON_PID_FILE"
        return 0
    fi

    local pid
    pid=$(cat "$DAEMON_PID_FILE")
    echo "Stopping rate monitor daemon (PID: $pid)..."

    kill "$pid" 2>/dev/null || true
    sleep 2

    if kill -0 "$pid" 2>/dev/null; then
        echo "Force killing daemon..."
        kill -9 "$pid" 2>/dev/null || true
    fi

    rm -f "$DAEMON_PID_FILE"
    echo "Daemon stopped"
}

show_status() {
    if is_daemon_running; then
        local pid
        pid=$(cat "$DAEMON_PID_FILE")
        echo -e "${GREEN}Rate monitor daemon is running (PID: $pid)${NC}"
        echo ""
        echo "Recent log entries:"
        tail -20 "$DAEMON_LOG_FILE" 2>/dev/null || echo "  (no log entries)"
    else
        echo -e "${YELLOW}Rate monitor daemon is not running${NC}"
    fi
}

# =============================================================================
# RATE LIMIT CHECK FUNCTIONS
# =============================================================================

check_api_status() {
    # Check external API for rate limit status
    # Returns: 0 if OK, 1 if rate limited

    if [[ -z "$API_URL" || "$API_URL" == "none" ]]; then
        return 0
    fi

    local response
    if ! response=$(curl -s --max-time 10 "$API_URL" 2>/dev/null); then
        daemon_log "Failed to fetch API status from $API_URL"
        return 0  # Assume OK on fetch failure
    fi

    # Parse Anthropic status page response
    local indicator
    indicator=$(echo "$response" | jq -r '.status.indicator // "none"' 2>/dev/null)

    case "$indicator" in
        "none"|"minor")
            return 0
            ;;
        "major"|"critical")
            daemon_log "API reports degraded status: $indicator"
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

check_instance_rate_limits() {
    # Check each running instance for rate limit markers
    local instances
    instances=$(get_ralph_instances)

    echo "$instances" | jq -c '.[]' 2>/dev/null | while read -r instance; do
        local instance_id state instance_dir
        instance_id=$(echo "$instance" | jq -r '.instanceId')
        state=$(echo "$instance" | jq -r '.state')

        # Skip if already rate limited or paused
        if [[ "$state" == "rate_limited" || "$state" == "paused" ]]; then
            continue
        fi

        # Get instance directory
        eval "$(get_ralph_paths)"
        instance_dir="$INSTANCES_DIR/$instance_id"

        # Check for rate limit marker file
        if [[ -f "$instance_dir/.rate_limited" ]]; then
            daemon_log "Instance $instance_id has rate limit marker"
        fi
    done
}

pause_all_instances() {
    local reason="$1"
    local instances
    instances=$(get_ralph_instances)

    echo "$instances" | jq -c '.[]' 2>/dev/null | while read -r instance; do
        local instance_id state
        instance_id=$(echo "$instance" | jq -r '.instanceId')
        state=$(echo "$instance" | jq -r '.state')

        # Skip if already paused or in terminal state
        if [[ "$state" == "paused" || "$state" == "rate_limited" || "$state" == "completed" || "$state" == "terminated" ]]; then
            continue
        fi

        daemon_log "Pausing instance $instance_id due to: $reason"

        # Create pause request
        eval "$(get_ralph_paths)"
        local instance_dir="$INSTANCES_DIR/$instance_id"
        local pause_file="$instance_dir/.pause_requested"

        if [[ -d "$instance_dir" ]]; then
            cat > "$pause_file" <<EOF
{
    "requestedAt": "$(date -Iseconds)",
    "requestedAtEpoch": $(date +%s),
    "reason": "$reason",
    "source": "rate-monitor"
}
EOF
        fi
    done
}

resume_all_instances() {
    local instances
    instances=$(get_ralph_instances)

    echo "$instances" | jq -c '.[]' 2>/dev/null | while read -r instance; do
        local instance_id state
        instance_id=$(echo "$instance" | jq -r '.instanceId')
        state=$(echo "$instance" | jq -r '.state')

        # Only resume paused instances that were paused by rate monitor
        if [[ "$state" != "paused" && "$state" != "rate_limited" ]]; then
            continue
        fi

        daemon_log "Resuming instance $instance_id"

        # Create resume request
        eval "$(get_ralph_paths)"
        local instance_dir="$INSTANCES_DIR/$instance_id"
        local resume_file="$instance_dir/.resume_requested"

        if [[ -d "$instance_dir" ]]; then
            cat > "$resume_file" <<EOF
{
    "requestedAt": "$(date -Iseconds)",
    "requestedAtEpoch": $(date +%s),
    "source": "rate-monitor"
}
EOF
        fi
    done
}

single_check() {
    echo "Checking rate limit status..."

    local api_ok=0
    if check_api_status; then
        echo -e "${GREEN}✓ API status: OK${NC}"
    else
        echo -e "${RED}✗ API status: DEGRADED${NC}"
        api_ok=1
    fi

    echo ""
    echo "Instance status:"
    local instances
    instances=$(get_ralph_instances)
    echo "$instances" | jq -r '.[] | "  \(.shortId): \(.state)"' 2>/dev/null || echo "  (no instances)"

    return $api_ok
}

# =============================================================================
# DAEMON MAIN LOOP
# =============================================================================

run_daemon() {
    daemon_log "Rate monitor daemon started (PID: $$)"
    daemon_log "Poll interval: ${POLL_INTERVAL}s, API URL: $API_URL"

    local was_rate_limited=0

    while true; do
        if check_api_status; then
            if [[ $was_rate_limited -eq 1 ]]; then
                daemon_log "Rate limit cleared, resuming instances"
                if [[ "$PAUSE_ALL" == "1" ]]; then
                    resume_all_instances
                fi
                was_rate_limited=0
            fi
        else
            if [[ $was_rate_limited -eq 0 ]]; then
                daemon_log "Rate limit detected via API"
                if [[ "$PAUSE_ALL" == "1" ]]; then
                    pause_all_instances "api_rate_limit"
                fi
                was_rate_limited=1
            fi
        fi

        # Also check individual instances
        check_instance_rate_limits

        sleep "$POLL_INTERVAL"
    done
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local command="${1:-status}"

    case "$command" in
        start)
            start_daemon
            ;;
        stop)
            stop_daemon
            ;;
        status)
            show_status
            ;;
        check)
            single_check
            ;;
        _run_daemon)
            run_daemon
            ;;
        *)
            echo "Usage: $0 {start|stop|status|check}"
            echo ""
            echo "Commands:"
            echo "  start   - Start the rate monitor daemon"
            echo "  stop    - Stop the rate monitor daemon"
            echo "  status  - Show daemon status and recent logs"
            echo "  check   - Perform a single rate limit check"
            exit 1
            ;;
    esac
}

main "$@"
