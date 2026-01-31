#!/usr/bin/env bash
# =============================================================================
# ralph-queue-workers.sh - Start/stop queue workers
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ralph-utils.sh"

DEFAULT_ITERATIONS="${RALPH_ITERATIONS:-10}"
QUEUE_WORKERS_FILE="${RALPH_GLOBAL_DIR:-$HOME/.ralph/global}/queue-workers.json"

show_help() {
    cat <<'EOF'
Usage: ralph-queue-workers.sh <command> [options]

Commands:
  start    Start queue workers
  stop     Stop all queue workers
  kill     Force kill all workers
  status   Show worker status

Options:
  -c, --count N            Number of queue processors (default: CPU/2)
  -m, --max-iterations N   Max iterations per worker (default: 10)
  -w, --workers-per-prd N  Parallel workers per PRD (default: 1)
  --parallel               Use ralph-parallel for each PRD (shorthand for -w with CPU/2)

Examples:
  # Start 3 queue processors (one per PRD)
  ralph-queue-workers.sh start -c 3 -m 10

  # Start with 6 parallel workers per PRD
  ralph-queue-workers.sh start -c 2 -w 6 -m 10

  # Quick parallel mode (uses CPU/2 workers per PRD)
  ralph-queue-workers.sh start --parallel -m 10

  ralph-queue-workers.sh stop
EOF
}

get_default_worker_count() {
    local cpu_count
    cpu_count=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
    local default=$((cpu_count / 2))
    [[ "$default" -lt 1 ]] && default=1
    echo "$default"
}

is_worker_running() {
    kill -0 "$1" 2>/dev/null
}

save_queue_workers() {
    mkdir -p "$(dirname "$QUEUE_WORKERS_FILE")"
    echo "$1" > "$QUEUE_WORKERS_FILE"
}

get_queue_workers() {
    [[ ! -f "$QUEUE_WORKERS_FILE" ]] && echo "[]" && return 0
    local content
    content=$(cat "$QUEUE_WORKERS_FILE" 2>/dev/null)
    [[ -z "$content" ]] && echo "[]" && return 0
    echo "$content" | jq '.' &>/dev/null && echo "$content" || echo "[]"
}

cmd_start() {
    local count=""
    local max_iterations=""
    local workers_per_prd=""
    local use_parallel=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--count)
                count="$2"
                shift 2
                ;;
            -m|--max-iterations)
                max_iterations="$2"
                shift 2
                ;;
            -w|--workers-per-prd)
                workers_per_prd="$2"
                use_parallel=1
                shift 2
                ;;
            --parallel)
                use_parallel=1
                shift
                ;;
            *)
                if [[ "$1" =~ ^[0-9]+$ && -z "$count" ]]; then
                    count="$1"
                else
                    echo "Error: Unknown option: $1" >&2
                    return 1
                fi
                shift
                ;;
        esac
    done

    [[ -z "$max_iterations" || "$max_iterations" -le 0 ]] && max_iterations="$DEFAULT_ITERATIONS"

    # If parallel mode but no workers specified, use default
    if [[ "$use_parallel" -eq 1 && -z "$workers_per_prd" ]]; then
        workers_per_prd=$(get_default_worker_count)
    fi

    # Default count: if parallel mode and -c not specified, default to 1 queue processor
    # (since you're running multiple workers per PRD, you usually want 1 processor per PRD)
    if [[ -z "$count" || "$count" -le 0 ]]; then
        if [[ "$use_parallel" -eq 1 ]]; then
            count=1  # Default to 1 when using parallel mode
        else
            count=$(get_default_worker_count)
        fi
    fi

    local pending_count
    pending_count=$(get_ralph_queue_entries "pending" | jq 'length')

    if [[ "$pending_count" -eq 0 ]]; then
        echo ""
        write_colored yellow "No pending entries in queue."
        echo "Add PRDs first: ralph-queue add -p /path/prd.json -r /path/project"
        echo ""
        return 1
    fi

    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║ STARTING QUEUE WORKERS                                                     ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Queue processors: $count"
    echo "  Max iterations: $max_iterations per worker"
    echo "  Pending PRDs: $pending_count"
    if [[ "$use_parallel" -eq 1 ]]; then
        echo "  Parallel mode: ${workers_per_prd} workers per PRD"
    fi
    echo ""

    local ralph_script="$SCRIPT_DIR/ralph.sh"
    local parallel_script="$SCRIPT_DIR/ralph-parallel.sh"
    if [[ ! -f "$ralph_script" ]]; then
        write_colored red "Error: ralph.sh not found"
        return 1
    fi
    if [[ "$use_parallel" -eq 1 && ! -f "$parallel_script" ]]; then
        write_colored red "Error: ralph-parallel.sh not found"
        return 1
    fi

    local workers_json="[]"
    local started=0
    local workers_dir="${RALPH_GLOBAL_DIR:-$HOME/.ralph/global}"
    mkdir -p "$workers_dir/logs"

    for ((i = 1; i <= count; i++)); do
        local instance_id="queue-worker-$$-$i"
        local entry

        entry=$(claim_ralph_queue_entry "$instance_id" 2>/dev/null) || {
            write_colored yellow "  Worker $i: No more pending entries"
            break
        }

        local entry_id prd_path project_root
        entry_id=$(echo "$entry" | jq -r '.id')
        prd_path=$(echo "$entry" | jq -r '.prdPath')
        project_root=$(echo "$entry" | jq -r '.projectRoot')

        if [[ -z "$prd_path" || "$prd_path" == "null" ]]; then
            write_colored yellow "  Worker $i: Invalid queue entry"
            continue
        fi

        write_colored cyan "  Starting worker $i..."
        echo "    PRD: $prd_path"
        echo "    Project: $project_root"
        if [[ "$use_parallel" -eq 1 ]]; then
            echo "    Parallel workers: $workers_per_prd"
        fi

        [[ "$started" -gt 0 ]] && sleep 1

        local log_file="$workers_dir/logs/queue-worker-$i-$$.log"

        if [[ "$use_parallel" -eq 1 ]]; then
            # Use ralph-parallel for multiple workers per PRD
            "$parallel_script" start \
                -c "$workers_per_prd" \
                -m "$max_iterations" \
                -p "$prd_path" \
                -r "$project_root" \
                > "$log_file" 2>&1 &
        else
            # Single worker per PRD
            "$ralph_script" "$max_iterations" \
                --queue-mode \
                --queue-entry "$entry_id" \
                -p "$prd_path" \
                -r "$project_root" \
                > "$log_file" 2>&1 &
        fi
        local pid=$!

        workers_json=$(echo "$workers_json" | jq \
            --argjson pid "$pid" \
            --arg log "$log_file" \
            --argjson idx "$i" \
            --arg eid "$entry_id" \
            '. += [{pid:$pid,index:$idx,logFile:$log,entryId:$eid}]')

        write_colored green "    PID: $pid"
        ((started++))
    done

    save_queue_workers "$workers_json"

    echo ""
    if [[ "$started" -gt 0 ]]; then
        write_colored green "Started $started queue workers"
        echo ""
        echo "Monitor: ralph-queue-workers status"
        echo "Stop: ralph-queue-workers stop"
    else
        write_colored yellow "No workers started"
    fi
    echo ""
}

cmd_stop() {
    write_colored yellow "Stopping all queue workers..."

    local workers pids stopped=0
    workers=$(get_queue_workers)
    pids=$(echo "$workers" | jq -r '.[].pid')

    for pid in $pids; do
        if is_worker_running "$pid"; then
            write_colored gray "  Stopping PID $pid..."
            kill -TERM "$pid" 2>/dev/null || true
            ((stopped++)) || true
        fi
    done

    if [[ "$stopped" -eq 0 ]]; then
        write_colored green "No running workers found"
    else
        write_colored green "Stopped $stopped workers"
    fi

    save_queue_workers "[]"
}

cmd_kill() {
    write_colored red "Force killing all queue workers..."

    local workers pids killed=0
    workers=$(get_queue_workers)
    pids=$(echo "$workers" | jq -r '.[].pid')

    for pid in $pids; do
        if is_worker_running "$pid"; then
            write_colored gray "  Killing PID $pid..."
            kill -KILL "$pid" 2>/dev/null || true
            ((killed++)) || true
        fi
    done

    write_colored red "Killed $killed workers"
    save_queue_workers "[]"
}

cmd_status() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║ QUEUE WORKERS STATUS                                                       ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    local workers running=0
    workers=$(get_queue_workers)
    local worker_count
    worker_count=$(echo "$workers" | jq 'length')

    if [[ "$worker_count" -eq 0 ]]; then
        echo "  No workers registered."
        echo ""
        return 0
    fi

    printf "  %-6s %-10s %-40s\n" "PID" "STATUS" "LOG FILE"
    printf "  %-6s %-10s %-40s\n" "------" "----------" "----------------------------------------"

    echo "$workers" | jq -c '.[]' | while read -r worker; do
        local pid log status
        pid=$(echo "$worker" | jq -r '.pid')
        log=$(echo "$worker" | jq -r '.logFile')

        if is_worker_running "$pid"; then
            status="running"
            ((running++)) || true
        else
            status="stopped"
        fi

        printf "  %-6s %-10s %-40s\n" "$pid" "$status" "$(basename "$log")"
    done

    echo ""
    echo "  Total: $worker_count workers"
    echo ""
}

main() {
    local command="${1:-status}"
    shift || true

    case "$command" in
        start)
            cmd_start "$@"
            ;;
        stop)
            cmd_stop "$@"
            ;;
        kill)
            cmd_kill "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Error: Unknown command: $command" >&2
            show_help
            exit 1
            ;;
    esac
}

main "$@"
