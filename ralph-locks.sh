#!/bin/bash
# Wrapper script - delegates to scripts/ralph/ralph-locks.sh
# This file exists for backward compatibility
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/scripts/ralph/ralph-locks.sh" "$@"
