#!/bin/bash
# Pace Control — Demo Simulation
# Rapidly simulates the full L0->L1->L2->L3->micro-nudge->L4 progression.
# Record with: asciinema rec demo.cast
# Convert to GIF with: agg demo.cast demo.gif

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRACKER="$SCRIPT_DIR/session-tracker.sh"
STARTER="$SCRIPT_DIR/session-start.sh"

DEMO_HOME=$(mktemp -d)
export HOME="$DEMO_HOME"
trap "rm -rf '$DEMO_HOME'" EXIT
mkdir -p "$HOME/.claude"

# Force daytime mode so demo looks correct regardless of actual time
echo '{"nightStartHour":0,"nightEndHour":0}' > "$HOME/.claude/pace-control-config.json"

NOW=$(date +%s)

header() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

simulate() {
  local label="$1"
  local elapsed="$2"
  local prompts="$3"
  local wds="${4:-false}"
  local wdpc="${5:-0}"
  local nna="${6:-0}"
  local wdl="${7:-0}"

  header "$label"
  local start=$((NOW - elapsed * 60))
  # Write state to the OLD un-stamped filename so the tracker's migration
  # logic picks it up (tracker will rename to pace-control-state.{PPID}.json)
  echo "{\"sessionStart\":${start},\"totalMinutes\":${elapsed},\"promptCount\":${prompts},\"lastCheck\":$((NOW - 30)),\"windDownShown\":${wds},\"windDownPromptCount\":${wdpc},\"nextNudgeAt\":${nna},\"windDownLevel\":${wdl}}" > "$HOME/.claude/pace-control-state.json"
  OUTPUT=$(bash "$TRACKER" 2>/dev/null)
  # Clean up PID-stamped files so next simulate() can use migration again
  rm -f "$HOME/.claude"/pace-control-state.*.json
  if [ -n "$OUTPUT" ]; then
    echo "$OUTPUT"
  else
    echo "  (silent — no output)"
  fi
  sleep 2
}

echo ""
echo "  PACE CONTROL — Demo"
echo "  Progressive session health intervention for Claude Code"
echo ""
sleep 2

header "Session Start"
bash "$STARTER" 2>/dev/null || echo "  (clean start — no previous session)"
sleep 2

simulate "Level 0: Silent (30 min)" 30 5
simulate "Level 1: Gentle Awareness (100 min)" 100 15
simulate "Level 2: Evidence Nudge (150 min)" 150 25
simulate "Level 3: Safe Wind-Down Protocol (200 min)" 200 40 false 0 0 0
simulate "Level 3: Micro-Nudge (still going...)" 210 46 true 0 46 3
simulate "Level 3: Silent Between Nudges" 212 47 true 1 52 3
simulate "Level 4: Mandatory Wind-Down (250 min)" 250 60 true 3 65 3

header "Done"
echo "  That's Pace Control."
echo "  Silent when you're productive. Evidence-based when you're not."
echo "  Everything saved. Nothing lost."
echo ""
echo "  Install: claude /plugin install --url https://github.com/kuzivaai/claude-pace-control"
echo ""
