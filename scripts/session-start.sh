#!/bin/bash
# Pace Control — Session Start Handler (SessionStart hook)
# Delegates all logic to pace_control.py
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
output=$(python3 "$SCRIPT_DIR/pace_control.py" start 2>/dev/null) || exit 0
[ -n "$output" ] && echo "$output"
exit 0
