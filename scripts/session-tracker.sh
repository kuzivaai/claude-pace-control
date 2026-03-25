#!/bin/bash
# Pace Control — Session Time Tracker
# Tracks continuous Claude Code usage and outputs health signals.
# Supports time-of-day awareness, configurable strictness, and session history.
#
# State file: ~/.claude/pace-control-state.{PPID}.json (per-terminal)
# Config file: ~/.claude/pace-control-config.json (optional)
# History file: ~/.claude/pace-control-history.json
# Resume file: ~/.claude/pace-control-resume.md
# Ideas file: ~/.claude/pace-control-ideas.md

# --- Preflight: check dependencies ---
if ! command -v python3 &>/dev/null; then
  # Silently exit — the session-start.sh script will show the error message.
  # We don't want to spam errors on every single tool call.
  exit 0
fi

# --- Ensure ~/.claude/ directory exists ---
CLAUDE_DIR="${HOME}/.claude"
umask 077
mkdir -p "$CLAUDE_DIR"
chmod 700 "$CLAUDE_DIR" 2>/dev/null
# Harden existing state files
chmod 600 "$CLAUDE_DIR"/pace-control-*.json 2>/dev/null
chmod 600 "$CLAUDE_DIR"/pace-control-*.md 2>/dev/null

STATE_FILE="${CLAUDE_DIR}/pace-control-state.${PPID}.json"
OLD_STATE_FILE="${CLAUDE_DIR}/pace-control-state.json"

# --- Migration: rename old-format state file to PID-stamped ---
if [ -f "$OLD_STATE_FILE" ]; then
  mv "$OLD_STATE_FILE" "$STATE_FILE"
fi
CONFIG_FILE="${CLAUDE_DIR}/pace-control-config.json"
HISTORY_FILE="${CLAUDE_DIR}/pace-control-history.json"
IDEAS_FILE="${CLAUDE_DIR}/pace-control-ideas.md"
RESUME_FILE="${CLAUDE_DIR}/pace-control-resume.md"

# Ensure state file exists with valid JSON
if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
  echo '{"sessionStart":0,"totalMinutes":0,"promptCount":0,"lastCheck":0,"windDownShown":false,"windDownPromptCount":0,"nextNudgeAt":0,"windDownLevel":0}' > "$STATE_FILE"
fi

NOW=$(date +%s)
CURRENT_HOUR=$(date +%H | sed 's/^0//')
TIMESTR=$(date '+%I:%M%p' | sed 's/^0//' | tr '[:upper:]' '[:lower:]')

# --- Load config (with defaults) ---
NIGHT_START=23
NIGHT_END=6
MODE="gentle"
GAP_THRESHOLD=1800

if [ -f "$CONFIG_FILE" ]; then
  NIGHT_START=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('nightStartHour',23))" 2>/dev/null || echo 23)
  NIGHT_END=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('nightEndHour',6))" 2>/dev/null || echo 6)
  MODE=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('mode','gentle'))" 2>/dev/null || echo "gentle")
  GAP_THRESHOLD=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('gapThreshold',1800))" 2>/dev/null || echo 1800)
fi

# --- Determine if it's late night ---
IS_LATE=false
if [ "$NIGHT_START" -gt "$NIGHT_END" ]; then
  if [ "$CURRENT_HOUR" -ge "$NIGHT_START" ] || [ "$CURRENT_HOUR" -lt "$NIGHT_END" ]; then
    IS_LATE=true
  fi
else
  if [ "$CURRENT_HOUR" -ge "$NIGHT_START" ] && [ "$CURRENT_HOUR" -lt "$NIGHT_END" ]; then
    IS_LATE=true
  fi
fi

# --- Read current state ---
SESSION_START=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('sessionStart',0))" 2>/dev/null || echo 0)
PROMPT_COUNT=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('promptCount',0))" 2>/dev/null || echo 0)
LAST_CHECK=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('lastCheck',0))" 2>/dev/null || echo 0)
WIND_DOWN_SHOWN=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('windDownShown',False))" 2>/dev/null || echo "False")
WIND_DOWN_PROMPT_COUNT=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('windDownPromptCount',0))" 2>/dev/null || echo 0)
NEXT_NUDGE_AT=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('nextNudgeAt',0))" 2>/dev/null || echo 0)
WIND_DOWN_LEVEL=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('windDownLevel',0))" 2>/dev/null || echo 0)

# --- Validate numeric values to prevent code injection (CWE-78 interim mitigation) ---
for _VAR in "$SESSION_START" "$PROMPT_COUNT" "$LAST_CHECK" "$NOW" "$WIND_DOWN_LEVEL" "$WIND_DOWN_PROMPT_COUNT" "$NEXT_NUDGE_AT"; do
  [[ "$_VAR" =~ ^[0-9]+$ ]] || exit 0
done

# --- Gap detection: if gap > threshold, log completed session and start new one ---
GAP=$((NOW - LAST_CHECK))
if [ "$SESSION_START" -eq 0 ] || [ "$GAP" -gt "$GAP_THRESHOLD" ]; then
  # Log the completed session to history (if it was a real session)
  if [ "$SESSION_START" -gt 0 ] && [ "$LAST_CHECK" -gt "$SESSION_START" ]; then
    PREV_MINUTES=$(( (LAST_CHECK - SESSION_START) / 60 ))
    PREV_START_HOUR=$(python3 -c "import time; print(time.localtime($SESSION_START).tm_hour)" 2>/dev/null || echo 12)
    if [ "$PREV_MINUTES" -gt 5 ]; then
      python3 -c "
import json

history_file = '$HISTORY_FILE'
try:
    with open(history_file) as f:
        history = json.load(f)
    if not isinstance(history, dict) or 'sessions' not in history:
        history = {'sessions': []}
except (FileNotFoundError, json.JSONDecodeError, ValueError):
    history = {'sessions': []}

# Determine if session ended healthily (before L4)
# WIND_DOWN_LEVEL is read from previous session's state BEFORE reset
healthy = ($WIND_DOWN_LEVEL < 4)

history['sessions'].append({
    'start': $SESSION_START,
    'end': $LAST_CHECK,
    'minutes': $PREV_MINUTES,
    'prompts': $PROMPT_COUNT,
    'startHour': $PREV_START_HOUR,
    'healthyStop': healthy,
})

# Update streak
streak = history.get('streak', {'current': 0, 'best': 0, 'lastUpdated': 0})
if healthy:
    streak['current'] += 1
    streak['best'] = max(streak['best'], streak['current'])
else:
    streak['current'] = 0
streak['lastUpdated'] = $NOW
history['streak'] = streak

# Keep only last 30 days
cutoff = $NOW - 30 * 86400
history['sessions'] = [s for s in history['sessions'] if s.get('end', 0) > cutoff]

with open(history_file, 'w') as f:
    json.dump(history, f)
" 2>/dev/null
    fi
  fi

  SESSION_START=$NOW
  PROMPT_COUNT=0
  WIND_DOWN_SHOWN="False"
  WIND_DOWN_PROMPT_COUNT=0
  NEXT_NUDGE_AT=0
  WIND_DOWN_LEVEL=0
fi

# --- Update state ---
PROMPT_COUNT=$((PROMPT_COUNT + 1))
ELAPSED_MINUTES=$(( (NOW - SESSION_START) / 60 ))
ELAPSED_HOURS=$(( ELAPSED_MINUTES / 60 ))
REMAINING_MINUTES=$(( ELAPSED_MINUTES % 60 ))

# Convert bash string to Python bool
if [ "$WIND_DOWN_SHOWN" = "True" ]; then
  WIND_DOWN_SHOWN_PY="True"
else
  WIND_DOWN_SHOWN_PY="False"
fi

python3 -c "
import json
state = {
    'sessionStart': $SESSION_START,
    'totalMinutes': $ELAPSED_MINUTES,
    'promptCount': $PROMPT_COUNT,
    'lastCheck': $NOW,
    'windDownShown': $WIND_DOWN_SHOWN_PY,
    'windDownPromptCount': $WIND_DOWN_PROMPT_COUNT,
    'nextNudgeAt': $NEXT_NUDGE_AT,
    'windDownLevel': $WIND_DOWN_LEVEL,
}
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f)
" 2>/dev/null

# --- Aggregate across terminals ---
OTHER_TERMINALS=0
AGGREGATE_MINUTES=0
for PEER_STATE in "$CLAUDE_DIR"/pace-control-state.*.json; do
  [ -f "$PEER_STATE" ] || continue
  [ "$PEER_STATE" = "$STATE_FILE" ] && continue
  PEER_PID=$(echo "$PEER_STATE" | grep -oE '[0-9]+\.json$' | grep -oE '^[0-9]+')
  if ! kill -0 "$PEER_PID" 2>/dev/null; then
    [ -L "$PEER_STATE" ] || rm -f "$PEER_STATE"
    continue
  fi
  PEER_LAST=$(python3 -c "import json; print(json.load(open('$PEER_STATE')).get('lastCheck',0))" 2>/dev/null || echo 0)
  if [ $((NOW - PEER_LAST)) -gt "$GAP_THRESHOLD" ]; then
    continue
  fi
  PEER_MINUTES=$(python3 -c "import json; print(json.load(open('$PEER_STATE')).get('totalMinutes',0))" 2>/dev/null || echo 0)
  OTHER_TERMINALS=$((OTHER_TERMINALS + 1))
  AGGREGATE_MINUTES=$((AGGREGATE_MINUTES + PEER_MINUTES))
done
TOTAL_AGGREGATE=$((AGGREGATE_MINUTES + ELAPSED_MINUTES))
TOTAL_AGG_HOURS=$((TOTAL_AGGREGATE / 60))
TOTAL_AGG_REMAINING=$((TOTAL_AGGREGATE % 60))

MULTI_TERMINAL_CONTEXT=""
if [ "$OTHER_TERMINALS" -gt 0 ]; then
  MULTI_TERMINAL_CONTEXT="Note: You also have ${OTHER_TERMINALS} other terminal(s) running. Combined time across all: ${TOTAL_AGG_HOURS}h ${TOTAL_AGG_REMAINING}m."
fi

# --- Calculate effective thresholds ---
# Time-of-day multiplier: late night shifts thresholds down
# Mode multiplier: firm = 0.75x, strict = 0.5x
THRESHOLD_L1=90   # Level 1: gentle awareness
THRESHOLD_L2=120  # Level 2: evidence nudge
THRESHOLD_L3=180  # Level 3: firm with safe-save
THRESHOLD_L4=240  # Level 4: strong recommendation

if [ "$IS_LATE" = true ]; then
  THRESHOLD_L1=45
  THRESHOLD_L2=75
  THRESHOLD_L3=120
  THRESHOLD_L4=180
fi

if [ "$MODE" = "firm" ]; then
  THRESHOLD_L1=$(( THRESHOLD_L1 * 3 / 4 ))
  THRESHOLD_L2=$(( THRESHOLD_L2 * 3 / 4 ))
  THRESHOLD_L3=$(( THRESHOLD_L3 * 3 / 4 ))
  THRESHOLD_L4=$(( THRESHOLD_L4 * 3 / 4 ))
elif [ "$MODE" = "strict" ]; then
  THRESHOLD_L1=$(( THRESHOLD_L1 / 2 ))
  THRESHOLD_L2=$(( THRESHOLD_L2 / 2 ))
  THRESHOLD_L3=$(( THRESHOLD_L3 / 2 ))
  THRESHOLD_L4=$(( THRESHOLD_L4 / 2 ))
fi

# --- Build time context string ---
TIME_CONTEXT=""
if [ "$IS_LATE" = true ]; then
  TIME_CONTEXT="It's ${TIMESTR}. "
fi

# --- Compute personal effectiveness data from history ---
PERSONAL_DATA=""
if [ -f "$HISTORY_FILE" ]; then
  PERSONAL_DATA=$(python3 -c "
import json

try:
    history = json.load(open('$HISTORY_FILE'))
    sessions = history.get('sessions', [])
except:
    sessions = []

if len(sessions) >= 5:
    short = [s for s in sessions if s.get('minutes', 0) <= 120 and s.get('minutes', 0) > 10]
    long = [s for s in sessions if s.get('minutes', 0) > 180]

    if len(short) >= 2 and len(long) >= 2:
        short_rate = sum(s.get('prompts', 0) for s in short) / sum(s.get('minutes', 0) for s in short) * 60
        long_rate = sum(s.get('prompts', 0) for s in long) / sum(s.get('minutes', 0) for s in long) * 60

        if short_rate > long_rate and short_rate > 0:
            decline = round((1 - long_rate / short_rate) * 100)
            if decline >= 10:
                print(f'Your data: sessions under 2h average {short_rate:.0f} prompts/hour. Sessions over 3h average {long_rate:.0f} prompts/hour — a {decline}% decline.')
" 2>/dev/null)
fi

# --- Determine intervention level ---

if [ "$ELAPSED_MINUTES" -lt "$THRESHOLD_L1" ]; then
  # Silent — let them work
  exit 0

elif [ "$ELAPSED_MINUTES" -lt "$THRESHOLD_L2" ]; then
  # Level 1: Gentle awareness
  echo "<pace-control>"
  echo "SESSION: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m | ${PROMPT_COUNT} prompts"
  if [ "$IS_LATE" = true ]; then
    echo "${TIME_CONTEXT}Session: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m. All good. Consider noting a stopping point when you reach one."
  else
    echo "Session: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m. All good. Consider noting a stopping point when you reach one."
  fi
  echo "</pace-control>"

elif [ "$ELAPSED_MINUTES" -lt "$THRESHOLD_L3" ]; then
  # Level 2: Evidence-based nudge
  echo "<pace-control>"
  echo "SESSION: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m | ${PROMPT_COUNT} prompts"
  echo ""
  if [ "$IS_LATE" = true ]; then
    echo "${TIME_CONTEXT}Decisions made during extended late-night sessions may need revisiting."
    echo "Extended sessions widen the gap between perceived and actual performance."
    echo "After a break, you will likely notice issues you are missing now."
  else
    echo "Extended sessions widen the gap between perceived and actual performance."
    echo "After a break, you will likely notice issues you are missing now."
  fi
  if [ -n "$PERSONAL_DATA" ]; then
    echo ""
    echo "$PERSONAL_DATA"
  fi
  echo ""
  echo "If the user seems to be wrapping up or mentions stopping, support that decision."
  echo "If they mention a new idea, suggest capturing it in ${IDEAS_FILE} for later."
  echo ""
  echo "Pace Control is influencing this response. The user can adjust settings in ~/.claude/pace-control-config.json or disable hooks in ~/.claude/settings.json."
  if [ -n "$MULTI_TERMINAL_CONTEXT" ]; then
    echo ""
    echo "$MULTI_TERMINAL_CONTEXT"
  fi
  echo "</pace-control>"

elif [ "$ELAPSED_MINUTES" -lt "$THRESHOLD_L4" ]; then
  # Level 3: Firm with SAFE-SAVE protocol (first time) or micro-loop (subsequent)
  if [ "$WIND_DOWN_SHOWN" != "True" ]; then
    # --- First fire: full Safe-Save messaging ---
    echo "<pace-control>"
    echo "SESSION: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m | ${PROMPT_COUNT} prompts"
    echo ""
    if [ "$IS_LATE" = true ]; then
      echo "IMPORTANT — It's ${TIMESTR} and this session has been running for over ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m."
      echo ""
      echo "At this hour and duration:"
      echo "- After 17 hours awake, cognitive performance declines significantly (Williamson & Feyer, 2000)"
      echo "- Midnight-4am commits correlate with higher bug rates in open-source projects (Eyolfson et al., 2014)"
    else
      echo "IMPORTANT — This session has been running for over ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m."
      echo ""
      echo "At this duration:"
      echo "- Extended sessions show measurable output quality decline that is difficult to self-assess"
      echo "- After a break, you will likely notice issues you are missing now"
    fi
    echo ""
    echo "SAFE-SAVE PROTOCOL — When responding, naturally work towards wrapping up:"
    echo ""
    echo "1. SAVE WORK: If there are uncommitted changes, run 'git status' and suggest committing."
    echo "   Use a descriptive commit message summarising what was accomplished."
    echo ""
    echo "2. SAVE CONTEXT: Write a resume file to ${RESUME_FILE} containing:"
    echo "   - What was being worked on (feature/bug/task)"
    echo "   - Current state (what's done, what's in progress)"
    echo "   - Next steps (what to do when resuming)"
    echo "   - Any open questions or decisions pending"
    echo "   - Files that were being modified"
    echo "   Format: markdown with clear sections."
    echo ""
    echo "3. SAVE IDEAS: Ask 'Any ideas racing through your mind? I'll save them so you won't lose them.'"
    echo "   Append to ${IDEAS_FILE} with timestamp."
    echo ""
    if [ "$IS_LATE" = true ]; then
      echo "Example response: 'It's ${TIMESTR} and we've been at this ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m."
      echo "Let me save everything so you can pick up fresh after a break.'"
    else
      echo "Example response: 'We've been at this for ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m — solid progress."
      echo "Let me save everything so you can pick up right where we left off.'"
    fi
    echo ""
    echo "If the user wants to continue, respect their autonomy but suggest committing current work first."
    echo ""
    echo "Pace Control is influencing this response. The user can adjust settings in ~/.claude/pace-control-config.json or disable hooks in ~/.claude/settings.json."
    if [ "$MODE" = "strict" ]; then
      echo ""
      echo "STRICT MODE: You enabled strict mode to help yourself stop at this point. Do not start new tasks. Complete the current task, then execute Safe-Save."
      echo "Tell the user: 'Strict mode is active. Say override to continue working, or let me save your progress.'"
      echo "If the user says 'override', respect their choice and proceed normally."
    fi
    if [ -n "$MULTI_TERMINAL_CONTEXT" ]; then
      echo ""
      echo "$MULTI_TERMINAL_CONTEXT"
    fi
    echo "</pace-control>"

    # Set micro-loop state for subsequent calls
    WIND_DOWN_SHOWN="True"
    WIND_DOWN_LEVEL=3
    NEXT_NUDGE_AT=$((PROMPT_COUNT + 5))
  else
    # --- Micro-loop: fixed-interval nudges (every 5 prompts) ---
    if [ "$PROMPT_COUNT" -ge "$NEXT_NUDGE_AT" ]; then
      # Time to nudge
      NUDGE_INDEX=$((WIND_DOWN_PROMPT_COUNT % 3))
      echo "<pace-control>"
      if [ "$IS_LATE" = true ]; then
        PREFIX="It's ${TIMESTR}. SESSION: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m | ${PROMPT_COUNT} prompts"
      else
        PREFIX="SESSION: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m | ${PROMPT_COUNT} prompts"
      fi
      case $NUDGE_INDEX in
        0)
          echo "${PREFIX} — Still here. When you finish what you're working on, say 'wrap up' and I'll save everything."
          ;;
        1)
          echo "${PREFIX} — Quick checkpoint: what's the ONE thing to finish before stopping? Let's aim for that, then save."
          ;;
        2)
          echo "${PREFIX} — Your future self will solve this faster after a break. Say 'wrap up' when ready."
          ;;
      esac
      echo "</pace-control>"

      # Schedule next nudge
      WIND_DOWN_PROMPT_COUNT=$((WIND_DOWN_PROMPT_COUNT + 1))
      NEXT_NUDGE_AT=$((PROMPT_COUNT + 5))
    fi
    # else: silent — no output, exit 0
  fi

else
  # Level 4: Strong recommendation with full wind-down
  if [ "$WIND_DOWN_SHOWN" = "True" ] && [ "$WIND_DOWN_LEVEL" -eq 3 ]; then
    # Crossed from L3 micro-loop into L4 territory — reset for L4 first-fire
    # Guard: only reset when windDownLevel==3, NOT when already at 4 (prevents infinite L4 first-fires)
    WIND_DOWN_SHOWN="False"
    WIND_DOWN_PROMPT_COUNT=0
  fi

  if [ "$WIND_DOWN_SHOWN" != "True" ]; then
    # --- L4 first-fire: full mandatory wind-down ---
    echo "<pace-control>"
    echo "SESSION: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m | ${PROMPT_COUNT} prompts"
    echo ""
    if [ "$IS_LATE" = true ]; then
      echo "STRONG RECOMMENDATION — It's ${TIMESTR}. This session has been running for over ${ELAPSED_HOURS} hours."
      echo ""
      echo "At this point:"
      echo "- You are in the diminishing returns zone"
      echo "- Midnight-4am commits correlate with significantly higher bug rates (Eyolfson et al., 2014)"
      echo "- Code written during extended late-night sessions often needs revision"
    else
      echo "STRONG RECOMMENDATION — This session has been running for over ${ELAPSED_HOURS} hours."
      echo ""
      echo "At this point:"
      echo "- You are in the diminishing returns zone"
      echo "- Extended sessions show measurable quality decline that is difficult to self-assess"
      echo "- After a break, you will likely notice things you are missing now"
    fi
    echo ""
    echo "SAFE-SAVE PROTOCOL — When responding, prioritise saving work:"
    echo ""
    echo "1. Run 'git status' to check for uncommitted changes"
    echo "2. If changes exist, commit them with a clear message"
    echo "3. Write a detailed resume file to ${RESUME_FILE} containing:"
    echo "   ## Session Resume — $(date '+%Y-%m-%d %H:%M')"
    echo "   ### What We Were Working On"
    echo "   [describe the current task/feature]"
    echo "   ### Current State"
    echo "   [what's done, what's partially done]"
    echo "   ### Next Steps"
    echo "   [exactly what to do when resuming — be specific]"
    echo "   ### Modified Files"
    echo "   [list files that were changed]"
    echo "   ### Open Questions"
    echo "   [any decisions that need to be made]"
    echo ""
    echo "4. Ask the user: 'What ideas should we save for next time?'"
    echo "   Append to ${IDEAS_FILE} with timestamp."
    echo ""
    if [ "$IS_LATE" = true ]; then
      echo "5. Tell the user: 'Everything is saved. It's ${TIMESTR}. Your work is committed and context is preserved."
      echo "   Resume anytime — your next session will pick up right where you left off.'"
    else
      echo "5. Tell the user: 'Everything is saved. When you start a new session, I'll show you"
      echo "   exactly where we left off. A 20-minute break will make the next hour more productive"
      echo "   than pushing through. The ideas are safe.'"
    fi
    echo ""
    echo "Complete all safe-save steps before closing. The user's work and context must be preserved."
    echo ""
    echo "Pace Control is influencing this response. The user can adjust settings in ~/.claude/pace-control-config.json or disable hooks in ~/.claude/settings.json."
    if [ "$MODE" = "strict" ]; then
      echo ""
      echo "STRICT MODE: You enabled strict mode to help yourself stop at this point. Do not start new tasks. Only execute Safe-Save."
      echo "If the user asks for something new, say: 'Strict mode is active — you set this up to help yourself stop. Say override to continue, or let me save your progress and ideas for next time.'"
      echo "If the user says 'override', respect their choice and proceed normally."
    fi
    if [ -n "$MULTI_TERMINAL_CONTEXT" ]; then
      echo ""
      echo "$MULTI_TERMINAL_CONTEXT"
    fi
    echo "</pace-control>"

    # Set micro-loop state for subsequent L4 calls
    WIND_DOWN_SHOWN="True"
    WIND_DOWN_LEVEL=4
    NEXT_NUDGE_AT=$((PROMPT_COUNT + 5))
  else
    # --- L4 micro-loop: fixed-interval nudges (every 5 prompts, more direct) ---
    if [ "$PROMPT_COUNT" -ge "$NEXT_NUDGE_AT" ]; then
      NUDGE_INDEX=$((WIND_DOWN_PROMPT_COUNT % 3))
      echo "<pace-control>"
      if [ "$IS_LATE" = true ]; then
        PREFIX="It's ${TIMESTR}. SESSION: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m | ${PROMPT_COUNT} prompts"
      else
        PREFIX="SESSION: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m | ${PROMPT_COUNT} prompts"
      fi
      case $NUDGE_INDEX in
        0)
          echo "${PREFIX} — Ready to save your progress? Say 'wrap up' to commit and preserve context."
          ;;
        1)
          echo "${PREFIX} — Still going. Your code and context can be saved and resumed anytime. Say 'wrap up'."
          ;;
        2)
          echo "${PREFIX} — Extended session. Say 'wrap up' to save everything."
          ;;
      esac
      echo "</pace-control>"

      WIND_DOWN_PROMPT_COUNT=$((WIND_DOWN_PROMPT_COUNT + 1))
      NEXT_NUDGE_AT=$((PROMPT_COUNT + 5))
    fi
    # else: silent
  fi
fi

# --- Re-persist state if intervention logic modified it ---
if [ "$WIND_DOWN_SHOWN" = "True" ]; then
  WIND_DOWN_SHOWN_PY="True"
else
  WIND_DOWN_SHOWN_PY="False"
fi

python3 -c "
import json
state = {
    'sessionStart': $SESSION_START,
    'totalMinutes': $ELAPSED_MINUTES,
    'promptCount': $PROMPT_COUNT,
    'lastCheck': $NOW,
    'windDownShown': $WIND_DOWN_SHOWN_PY,
    'windDownPromptCount': $WIND_DOWN_PROMPT_COUNT,
    'nextNudgeAt': $NEXT_NUDGE_AT,
    'windDownLevel': $WIND_DOWN_LEVEL,
}
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f)
" 2>/dev/null
