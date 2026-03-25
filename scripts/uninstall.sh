#!/bin/bash
# Pace Control — Uninstall
# Removes all pace-control state files from ~/.claude/

CLAUDE_DIR="${HOME}/.claude"

echo "Removing Pace Control state files..."
rm -f "$CLAUDE_DIR"/pace-control-state.*.json
rm -f "$CLAUDE_DIR"/pace-control-state.json
rm -f "$CLAUDE_DIR"/pace-control-config.json
rm -f "$CLAUDE_DIR"/pace-control-history.json
rm -f "$CLAUDE_DIR"/pace-control-resume.md
rm -f "$CLAUDE_DIR"/pace-control-ideas.md
echo "Done. State files removed."
echo ""
echo "To complete uninstall:"
echo "1. Remove SessionStart and PostToolUse hooks from ~/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "2. Optionally remove the repo: rm -rf $SCRIPT_DIR"
