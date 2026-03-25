#!/bin/bash
# Pace Control — Structural Tests
# Tests hook script output at each intervention level.
# Run: bash scripts/test-output.sh
# Exit 0 = all pass, Exit 1 = failures

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRACKER="$SCRIPT_DIR/session-tracker.sh"
STARTER="$SCRIPT_DIR/session-start.sh"

# Use a temp directory for state files to avoid polluting real state
TEMP_HOME=$(mktemp -d)
export HOME="$TEMP_HOME"
trap 'rm -rf "$TEMP_HOME"' EXIT
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

# The tracker uses PPID-stamped state files (pace-control-state.{PPID}.json).
# Tests seed state via the old un-stamped filename so the tracker's migration
# logic picks it up.  After running the tracker, find_tracker_state locates
# the PID-stamped file the tracker actually wrote.
STATE_FILE="$CLAUDE_DIR/pace-control-state.json"
CONFIG_FILE="$CLAUDE_DIR/pace-control-config.json"
HISTORY_FILE="$CLAUDE_DIR/pace-control-history.json"
RESUME_FILE="$CLAUDE_DIR/pace-control-resume.md"
IDEAS_FILE="$CLAUDE_DIR/pace-control-ideas.md"

PASS=0
FAIL=0
ERRORS=""

NOW=$(date +%s)

assert_output() {
  local test_name="$1"
  local pattern="$2"
  local output="$3"
  if echo "$output" | grep -qiE "$pattern"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: ${test_name} — expected pattern '${pattern}' not found"
  fi
}

assert_empty() {
  local test_name="$1"
  local output="$2"
  if [ -z "$output" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: ${test_name} — expected empty output, got: $(echo "$output" | head -1)"
  fi
}

assert_not_output() {
  local test_name="$1"
  local pattern="$2"
  local output="$3"
  if echo "$output" | grep -qiE "$pattern"; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: ${test_name} — pattern '${pattern}' should NOT appear"
  else
    PASS=$((PASS + 1))
  fi
}

cleanup() {
  rm -f "$STATE_FILE" "$CONFIG_FILE" "$HISTORY_FILE" "$RESUME_FILE" "$IDEAS_FILE"
  rm -f "$CLAUDE_DIR"/pace-control-state.*.json
}

setup_state() {
  local elapsed_min="$1"
  local prompt_count="${2:-10}"
  # Parameter 3 was windDownShown (removed — derived from windDownLevel > 0)
  local _unused="${3:-}"
  local wind_down_prompt_count="${4:-0}"
  local next_nudge_at="${5:-0}"
  local wind_down_level="${6:-0}"
  local start=$((NOW - elapsed_min * 60))
  local last=$((NOW - 30))
  echo "{\"sessionStart\":${start},\"totalMinutes\":${elapsed_min},\"promptCount\":${prompt_count},\"lastCheck\":${last},\"windDownPromptCount\":${wind_down_prompt_count},\"nextNudgeAt\":${next_nudge_at},\"windDownLevel\":${wind_down_level}}" > "$STATE_FILE"
}

setup_night_config() {
  # Force night mode by setting nightStartHour=0, nightEndHour=23 (always night)
  echo '{"nightStartHour":0,"nightEndHour":23}' > "$CONFIG_FILE"
}

setup_day_config() {
  # Force daytime: nightStartHour == nightEndHour means night window is zero-length
  echo '{"nightStartHour":0,"nightEndHour":0}' > "$CONFIG_FILE"
}

# After running the tracker, find the PID-stamped state file it created
find_tracker_state() {
  local f
  for f in "$CLAUDE_DIR"/pace-control-state.*.json; do
    [ -f "$f" ] && echo "$f" && return
  done
  echo "$STATE_FILE"  # fallback
}

echo "=== Pace Control Structural Tests ==="
echo ""

# --- L0: Silent ---
cleanup
setup_day_config
setup_state 30 5
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_empty "L0 daytime (30m)" "$OUTPUT"

# --- L1: Gentle awareness ---
cleanup
setup_day_config
setup_state 100 15
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "L1 daytime (100m)" "pace-control" "$OUTPUT"
assert_output "L1 daytime — session duration" "[0-9]+h [0-9]+m" "$OUTPUT"
assert_output "L1 daytime — all good" "all good" "$OUTPUT"

# --- L2: Evidence nudge ---
cleanup
setup_day_config
setup_state 150 25
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "L2 daytime (150m)" "pace-control" "$OUTPUT"
assert_output "L2 daytime — evidence" "METR|slower|performance|declining" "$OUTPUT"

# --- L3: First fire — suggests /wrap-up ---
cleanup
setup_day_config
setup_state 200 40 false
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "L3 daytime first-fire" "wrap-up" "$OUTPUT"
assert_not_output "L3 daytime — not L4" "MANDATORY" "$OUTPUT"

# Verify state was updated with windDownLevel >= 3 (windDownShown removed; derivable from windDownLevel > 0)
ACTUAL_STATE=$(find_tracker_state)
WDL=$(python3 -c "import json; print(json.load(open('$ACTUAL_STATE')).get('windDownLevel', 0))" 2>/dev/null)
if [ "$WDL" -ge 3 ] 2>/dev/null; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\nFAIL: L3 first-fire — windDownLevel not set to >= 3 (got: $WDL)"
fi

# --- L3: Micro-loop nudge (promptCount == nextNudgeAt) ---
cleanup
setup_day_config
setup_state 200 45 true 0 45 3
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "L3 micro-nudge fires" "wrap up|checkpoint|future self" "$OUTPUT"
assert_not_output "L3 micro-nudge — not full Safe-Save" "SAFE-SAVE PROTOCOL" "$OUTPUT"

# --- L3: Micro-loop silent (promptCount < nextNudgeAt) ---
cleanup
setup_day_config
setup_state 200 43 true 0 50 3
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_empty "L3 micro-loop silent (43 < 50)" "$OUTPUT"

# --- L3: Micro-loop boundary (promptCount + 1 == nextNudgeAt - 1) ---
# Note: script increments promptCount by 1 before comparing, so 43 becomes 44 < 45
cleanup
setup_day_config
setup_state 200 43 true 0 45 3
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_empty "L3 boundary silent (43+1=44 < 45)" "$OUTPUT"

# --- L4: First fire (auto-save) ---
cleanup
setup_day_config
setup_state 250 55 false
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "L4 daytime first-fire" "auto-saved" "$OUTPUT"

# --- L4: First fire after L3 micro-loop (reset — windDownLevel=3 triggers reset) ---
cleanup
setup_day_config
setup_state 250 60 true 3 65 3
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "L4 from L3 micro-loop — reset" "auto-saved" "$OUTPUT"

# --- Firm mode: lower thresholds ---
cleanup
echo '{"mode":"firm","nightStartHour":0,"nightEndHour":0}' > "$CONFIG_FILE"
setup_state 70 12
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "Firm mode L1 at 70m" "pace-control" "$OUTPUT"
assert_output "Firm mode L1 — all good" "all good" "$OUTPUT"
rm -f "$CONFIG_FILE"

# --- Strict mode L4 ---
cleanup
echo '{"mode":"strict","nightStartHour":0,"nightEndHour":0}' > "$CONFIG_FILE"
setup_state 130 30 false
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "Strict mode L4 at 130m" "Strict mode is active|Do not start new tasks" "$OUTPUT"
rm -f "$CONFIG_FILE"

# --- Night mode: L0 silent ---
cleanup
setup_night_config
setup_state 20 3
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_empty "L0 night (20m)" "$OUTPUT"
setup_day_config

# --- Night mode: L1 with time ---
cleanup
setup_night_config
setup_state 50 8
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "L1 night (50m)" "pace-control" "$OUTPUT"
assert_output "L1 night — all good" "all good|stopping point" "$OUTPUT"
setup_day_config

# --- Night mode: L2 with sleep reference ---
cleanup
setup_night_config
setup_state 80 15
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "L2 night (80m)" "late-night sessions|perceived and actual" "$OUTPUT"
setup_day_config

# --- L4 persistence: micro-loop continues after L4 first-fire (catches double-fire bug) ---
cleanup
setup_day_config
setup_state 266 65 true 0 65 4
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "L4 micro-nudge after first-fire" "wrap up|checkpoint|future self" "$OUTPUT"
assert_not_output "L4 micro-nudge — not full L4" "MANDATORY SAFE-SAVE" "$OUTPUT"

# --- L4 persistence: silent between nudges ---
cleanup
setup_day_config
setup_state 266 66 true 1 72 4
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_empty "L4 micro-loop silent (66 < 72)" "$OUTPUT"

# --- Missing config file: still produces output at 90m ---
# Without config, night mode depends on system clock, so we only assert
# that *some* pace-control output appears (L1 daytime or L2+ at night)
cleanup
rm -f "$CONFIG_FILE"
setup_state 90 14
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "No config — output at 90m" "pace-control" "$OUTPUT"

# --- Corrupt state file ---
cleanup
setup_day_config
echo "not json" > "$STATE_FILE"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
# Should not crash — script handles gracefully
assert_empty "Corrupt state — no crash (L0)" "$OUTPUT"

# --- First prompt (promptCount=0) ---
cleanup
setup_day_config
echo "{\"sessionStart\":${NOW},\"totalMinutes\":0,\"promptCount\":0,\"lastCheck\":${NOW}}" > "$STATE_FILE"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_empty "First prompt (L0)" "$OUTPUT"

# --- Session start with resume ---
cleanup
echo "## Resume" > "$RESUME_FILE"
echo "Working on auth" >> "$RESUME_FILE"
OUTPUT=$(bash "$STARTER" 2>/dev/null)
assert_output "Session start with resume" "pace-control-resume" "$OUTPUT"
assert_output "Session start — resume content" "Working on auth" "$OUTPUT"

# --- Session start with weekly (3+ late sessions) ---
cleanup
rm -f "$RESUME_FILE"
python3 -c "
import json, time
now = int(time.time())
sessions = []
for i in range(4):
    s = now - (i+1) * 86400
    sessions.append({'start': s, 'end': s + 7200, 'minutes': 120, 'prompts': 30, 'startHour': 23})
json.dump({'sessions': sessions}, open('$HISTORY_FILE', 'w'))
"
OUTPUT=$(bash "$STARTER" 2>/dev/null)
assert_output "Session start with weekly stats" "pace-control-weekly|late-night" "$OUTPUT"

# --- First-run welcome (no history file) ---
cleanup
setup_day_config
rm -f "$HISTORY_FILE"
OUTPUT=$(bash "$STARTER" 2>/dev/null)
assert_output "First-run welcome" "pace-control-welcome" "$OUTPUT"
assert_output "First-run — mentions /pace-check" "pace-check" "$OUTPUT"

# --- Second session: no welcome (history exists) ---
cleanup
setup_day_config
echo '{"sessions":[{"start":1,"end":2,"minutes":60,"prompts":10,"startHour":14}]}' > "$HISTORY_FILE"
OUTPUT=$(bash "$STARTER" 2>/dev/null)
assert_not_output "Second session — no welcome" "pace-control-welcome" "$OUTPUT"

# --- Gap detection ---
cleanup
LAST=$((NOW - 2700))  # 45 minutes ago (> 1800 threshold)
START=$((LAST - 3600))  # Session started 1h before last check
echo "{\"sessionStart\":${START},\"totalMinutes\":60,\"promptCount\":20,\"lastCheck\":${LAST},\"windDownPromptCount\":5,\"nextNudgeAt\":25,\"windDownLevel\":3}" > "$STATE_FILE"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
# After gap, windDownLevel should be reset to 0 (windDownShown removed; derivable from windDownLevel > 0)
ACTUAL_STATE=$(find_tracker_state)
WDL=$(python3 -c "import json; print(json.load(open('$ACTUAL_STATE')).get('windDownLevel', -1))" 2>/dev/null)
if [ "$WDL" = "0" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\nFAIL: Gap detection — windDownLevel not reset (got: $WDL)"
fi

# --- Multi-terminal: aggregation shows combined time ---
cleanup
setup_day_config
setup_state 150 25  # Own terminal at 150m (L2)
# Create a peer state file with a live PID (use test script's own PID, guaranteed alive)
echo "{\"sessionStart\":$((NOW - 7200)),\"totalMinutes\":120,\"promptCount\":20,\"lastCheck\":$((NOW - 60))}" > "$CLAUDE_DIR/pace-control-state.$$.json"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "Multi-terminal aggregation" "other terminal" "$OUTPUT"
rm -f "$CLAUDE_DIR/pace-control-state.$$.json"

# --- Stale detection: dead PID file is removed ---
cleanup
setup_day_config
setup_state 150 25
echo "{\"sessionStart\":$((NOW - 3600)),\"totalMinutes\":60,\"promptCount\":10,\"lastCheck\":$((NOW - 60))}" > "$CLAUDE_DIR/pace-control-state.99999999.json"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
if [ ! -f "$CLAUDE_DIR/pace-control-state.99999999.json" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\nFAIL: Stale detection — dead PID file not removed"
fi

# --- Migration: old state file renamed ---
cleanup
echo "{\"sessionStart\":$((NOW - 600)),\"totalMinutes\":10,\"promptCount\":5,\"lastCheck\":$((NOW - 30))}" > "$CLAUDE_DIR/pace-control-state.json"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
if [ ! -f "$CLAUDE_DIR/pace-control-state.json" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\nFAIL: Migration — old state file not removed"
fi

# --- Streak: healthy stop increments streak ---
cleanup
echo '{"sessions":[],"streak":{"current":3,"best":5,"lastUpdated":0}}' > "$HISTORY_FILE"
LAST=$((NOW - 2100))
GSTART=$((LAST - 3600))
echo "{\"sessionStart\":${GSTART},\"totalMinutes\":60,\"promptCount\":20,\"lastCheck\":${LAST},\"windDownPromptCount\":0,\"nextNudgeAt\":0,\"windDownLevel\":0}" > "$STATE_FILE"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
STREAK_CURRENT=$(python3 -c "import json; print(json.load(open('$HISTORY_FILE')).get('streak',{}).get('current',0))" 2>/dev/null)
if [ "$STREAK_CURRENT" = "4" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\nFAIL: Streak — healthy stop should increment to 4 (got: $STREAK_CURRENT)"
fi

# --- Streak: unhealthy stop resets streak ---
cleanup
echo '{"sessions":[],"streak":{"current":3,"best":5,"lastUpdated":0}}' > "$HISTORY_FILE"
LAST=$((NOW - 2100))
GSTART=$((LAST - 14400))
echo "{\"sessionStart\":${GSTART},\"totalMinutes\":240,\"promptCount\":60,\"lastCheck\":${LAST},\"windDownPromptCount\":5,\"nextNudgeAt\":65,\"windDownLevel\":4}" > "$STATE_FILE"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
STREAK_CURRENT=$(python3 -c "import json; print(json.load(open('$HISTORY_FILE')).get('streak',{}).get('current',0))" 2>/dev/null)
STREAK_BEST=$(python3 -c "import json; print(json.load(open('$HISTORY_FILE')).get('streak',{}).get('best',0))" 2>/dev/null)
if [ "$STREAK_CURRENT" = "0" ] && [ "$STREAK_BEST" = "5" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\nFAIL: Streak — unhealthy stop should reset to 0, best at 5 (got: current=$STREAK_CURRENT, best=$STREAK_BEST)"
fi

# --- New assertions: evidence-validated improvements ---

# No unsupported claims in L3
cleanup
setup_day_config
setup_state 200 40 false
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_not_output "L3 daytime — no 2-3x claim" "2-3x" "$OUTPUT"
assert_not_output "L3 daytime — no slot machine" "slot machine" "$OUTPUT"
assert_output "L3 — transparency marker" "Pace Control is influencing" "$OUTPUT"

# No unsupported claims in L4
cleanup
setup_day_config
setup_state 250 55 false
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_not_output "L4 daytime — no 2-3x claim" "2-3x" "$OUTPUT"
assert_not_output "L4 daytime — no slot machine" "slot machine" "$OUTPUT"
assert_not_output "L4 daytime — no go to bed" "go to bed" "$OUTPUT"
assert_not_output "L4 daytime — no MANDATORY" "MANDATORY" "$OUTPUT"
assert_output "L4 — transparency marker" "Pace Control is influencing" "$OUTPUT"

# L4 micro-loop is different from L3 micro-loop
cleanup
setup_day_config
setup_state 266 65 true 0 65 4
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "L4 micro-nudge — distinct from L3" "Ready to save|save your work|Extended session" "$OUTPUT"

# Strict mode has override path
cleanup
echo '{"mode":"strict","nightStartHour":0,"nightEndHour":0}' > "$CONFIG_FILE"
setup_state 130 30 false
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "Strict mode — has override" "override" "$OUTPUT"
rm -f "$CONFIG_FILE"

# First-run welcome mentions /wrap-up
cleanup
setup_day_config
rm -f "$HISTORY_FILE"
OUTPUT=$(bash "$STARTER" 2>/dev/null)
assert_output "First-run — mentions /wrap-up" "wrap-up" "$OUTPUT"

# Late-night start — no presumptuous messaging
cleanup
setup_night_config
rm -f "$RESUME_FILE" "$IDEAS_FILE" "$HISTORY_FILE"
# Create minimal history so it doesn't trigger first-run welcome
echo '{"sessions":[{"start":1,"end":2,"minutes":60,"prompts":10,"startHour":23}]}' > "$HISTORY_FILE"
OUTPUT=$(bash "$STARTER" 2>/dev/null)
assert_not_output "Late-night start — no 3am claim" "3am finishes" "$OUTPUT"

# --- Messaging modes: awareness ---
cleanup
echo '{"messaging":"awareness","nightStartHour":0,"nightEndHour":0}' > "$CONFIG_FILE"
setup_state 150 25
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "Awareness mode L2 — has wrap-up" "wrap-up" "$OUTPUT"
assert_not_output "Awareness mode L2 — no full evidence" "perceived and actual" "$OUTPUT"
rm -f "$CONFIG_FILE"

# --- Messaging modes: tracking ---
cleanup
echo '{"messaging":"tracking","nightStartHour":0,"nightEndHour":0}' > "$CONFIG_FILE"
setup_state 150 25
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "Tracking mode L2 — has session time" "[0-9]+h [0-9]+m" "$OUTPUT"
assert_output "Tracking mode L2 — has wrap-up" "wrap-up" "$OUTPUT"
assert_not_output "Tracking mode L2 — no evidence" "perceived|performance|decline" "$OUTPUT"
rm -f "$CONFIG_FILE"

# --- Messaging modes: tracking at L3 ---
cleanup
echo '{"messaging":"tracking","nightStartHour":0,"nightEndHour":0}' > "$CONFIG_FILE"
setup_state 200 40 false 0 0 0
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "Tracking mode L3 — has wrap-up" "wrap-up" "$OUTPUT"
assert_not_output "Tracking mode L3 — no safe-save protocol" "SAFE-SAVE PROTOCOL" "$OUTPUT"
rm -f "$CONFIG_FILE"

# --- gapThreshold floor (minimum 60s) ---
cleanup
echo '{"gapThreshold":0,"nightStartHour":0,"nightEndHour":0}' > "$CONFIG_FILE"
setup_state 100 15
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
# With gapThreshold=0 (floored to 60), a 30-second-old lastCheck should NOT trigger gap
assert_output "gapThreshold floor — still outputs at L1" "pace-control" "$OUTPUT"
rm -f "$CONFIG_FILE"

# --- Feature: Focus mode suppresses output ---
cleanup
setup_day_config
FOCUS_UNTIL=$((NOW + 3600))
echo "{\"sessionStart\":$((NOW - 6000)),\"totalMinutes\":100,\"promptCount\":15,\"lastCheck\":$((NOW - 30)),\"windDownPromptCount\":0,\"nextNudgeAt\":0,\"windDownLevel\":0,\"nudgesShown\":0,\"promptsAfterL3\":0,\"wrappedUp\":0,\"focusUntil\":${FOCUS_UNTIL},\"sessionType\":\"\"}" > "$STATE_FILE"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_empty "Focus mode — suppresses L1 output" "$OUTPUT"

# --- Feature: Focus mode expired resumes normally ---
cleanup
setup_day_config
FOCUS_EXPIRED=$((NOW - 60))
echo "{\"sessionStart\":$((NOW - 6000)),\"totalMinutes\":100,\"promptCount\":15,\"lastCheck\":$((NOW - 30)),\"windDownPromptCount\":0,\"nextNudgeAt\":0,\"windDownLevel\":0,\"nudgesShown\":0,\"promptsAfterL3\":0,\"wrappedUp\":0,\"focusUntil\":${FOCUS_EXPIRED},\"sessionType\":\"\"}" > "$STATE_FILE"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "Focus expired — L1 resumes" "pace-control" "$OUTPUT"

# --- Feature: Session type incident extends thresholds ---
cleanup
setup_day_config
# Normal L1 at 90m. Incident (1.5x) = L1 at 135m. So 100m should be L0 (silent).
echo "{\"sessionStart\":$((NOW - 6000)),\"totalMinutes\":100,\"promptCount\":15,\"lastCheck\":$((NOW - 30)),\"windDownPromptCount\":0,\"nextNudgeAt\":0,\"windDownLevel\":0,\"nudgesShown\":0,\"promptsAfterL3\":0,\"wrappedUp\":0,\"focusUntil\":0,\"sessionType\":\"incident\"}" > "$STATE_FILE"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_empty "Session type incident — L0 at 100m" "$OUTPUT"

# --- Feature: Session type exploring shortens thresholds ---
cleanup
setup_day_config
# Normal L1 at 90m. Exploring (0.85x) = L1 at ~76m. So 80m should be L1.
echo "{\"sessionStart\":$((NOW - 4800)),\"totalMinutes\":80,\"promptCount\":12,\"lastCheck\":$((NOW - 30)),\"windDownPromptCount\":0,\"nextNudgeAt\":0,\"windDownLevel\":0,\"nudgesShown\":0,\"promptsAfterL3\":0,\"wrappedUp\":0,\"focusUntil\":0,\"sessionType\":\"exploring\"}" > "$STATE_FILE"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "Session type exploring — L1 at 80m" "pace-control" "$OUTPUT"

# --- Feature: Outcome — nudgesShown increments after L3 nudge ---
cleanup
setup_day_config
echo "{\"sessionStart\":$((NOW - 12000)),\"totalMinutes\":200,\"promptCount\":44,\"lastCheck\":$((NOW - 30)),\"windDownPromptCount\":0,\"nextNudgeAt\":45,\"windDownLevel\":3,\"nudgesShown\":0,\"promptsAfterL3\":0,\"wrappedUp\":0,\"focusUntil\":0,\"sessionType\":\"\"}" > "$STATE_FILE"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
ACTUAL_STATE=$(find_tracker_state)
NS=$(python3 -c "import json; print(json.load(open('$ACTUAL_STATE')).get('nudgesShown', -1))" 2>/dev/null)
if [ "$NS" -ge 1 ] 2>/dev/null; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\nFAIL: Outcome — nudgesShown not incremented (got: $NS)"
fi

# --- Feature: Outcome — promptsAfterL3 increments ---
cleanup
setup_day_config
echo "{\"sessionStart\":$((NOW - 12000)),\"totalMinutes\":200,\"promptCount\":50,\"lastCheck\":$((NOW - 30)),\"windDownPromptCount\":2,\"nextNudgeAt\":60,\"windDownLevel\":3,\"nudgesShown\":2,\"promptsAfterL3\":5,\"wrappedUp\":0,\"focusUntil\":0,\"sessionType\":\"\"}" > "$STATE_FILE"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
ACTUAL_STATE=$(find_tracker_state)
PA=$(python3 -c "import json; print(json.load(open('$ACTUAL_STATE')).get('promptsAfterL3', -1))" 2>/dev/null)
if [ "$PA" -ge 6 ] 2>/dev/null; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\nFAIL: Outcome — promptsAfterL3 not incremented (got: $PA)"
fi

# --- Feature: Mechanical save produces output ---
cleanup
setup_day_config
setup_state 200 40 false
SAVE_OUTPUT=$(HOME="$TEMP_HOME" python3 "$SCRIPT_DIR/pace_control.py" save "testing save" 2>/dev/null)
if echo "$SAVE_OUTPUT" | grep -qiE "commit|Context saved|working tree"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\nFAIL: Mechanical save — no output (got: $SAVE_OUTPUT)"
fi

# --- CLI: set command ---
cleanup
setup_day_config
HOME="$TEMP_HOME" python3 "$SCRIPT_DIR/pace_control.py" set mode firm 2>/dev/null
SET_MODE=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('mode', 'MISSING'))" 2>/dev/null)
if [ "$SET_MODE" = "firm" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\nFAIL: CLI set command — mode not set to firm (got: $SET_MODE)"
fi

# --- Fatigue carry-forward: recent long session shifts threshold ---
cleanup
setup_day_config
# Create history with a long session that ended 20 min ago
RECENT_END=$((NOW - 1200))
RECENT_START=$((RECENT_END - 7200))
python3 -c "
import json
history = {'sessions': [{'start': $RECENT_START, 'end': $RECENT_END, 'minutes': 120, 'prompts': 30, 'startHour': 14, 'healthyStop': True, 'maxLevel': 2}], 'streak': {'current': 1, 'best': 1, 'lastUpdated': $NOW}}
json.dump(history, open('$HISTORY_FILE', 'w'))
"
# New session just started — with fatigue carry-forward from a recent 2h session,
# the session should skip L0 and show L1 output almost immediately
echo "{\"sessionStart\":$NOW,\"totalMinutes\":0,\"promptCount\":0,\"lastCheck\":0,\"windDownPromptCount\":0,\"nextNudgeAt\":0,\"windDownLevel\":0,\"nudgesShown\":0,\"promptsAfterL3\":0,\"wrappedUp\":0,\"focusUntil\":0,\"sessionType\":\"\"}" > "$STATE_FILE"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
# Fatigue carry-forward requires session > 90min AND gap < 30min (1800s).
# Our gap is 20min (1200s) and session was 120min (>90). So carry-forward should fire.
# L1 threshold is 90min. Carry-forward backdates by 90*60=5400s, so elapsed = 5400/60 = 90min.
# 90min >= L1 threshold of 90 → should produce output
assert_output "Fatigue carry-forward — L1 fires on fresh session" "pace-control" "$OUTPUT"

# --- Results ---
echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [ $FAIL -gt 0 ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
  exit 1
fi

echo "All tests passed."
exit 0
