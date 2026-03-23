#!/bin/bash
# Pace Control — Session Time Tracker
# Tracks continuous Claude Code usage and outputs health signals.
# Supports time-of-day awareness, configurable strictness, and session history.
#
# State file: ~/.claude/pace-control-state.json
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
mkdir -p "$CLAUDE_DIR"

STATE_FILE="${CLAUDE_DIR}/pace-control-state.json"
CONFIG_FILE="${CLAUDE_DIR}/pace-control-config.json"
HISTORY_FILE="${CLAUDE_DIR}/pace-control-history.json"
IDEAS_FILE="${CLAUDE_DIR}/pace-control-ideas.md"
RESUME_FILE="${CLAUDE_DIR}/pace-control-resume.md"

# Ensure state file exists with valid JSON
if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
  echo '{"sessionStart":0,"totalMinutes":0,"promptCount":0,"lastCheck":0,"windDownShown":false,"windDownPromptCount":0,"nextNudgeAt":0,"windDownLevel":0}' > "$STATE_FILE"
fi

NOW=$(date +%s)
CURRENT_HOUR=$(date +%-H)
TIMESTR=$(date '+%-I:%M%p' | tr '[:upper:]' '[:lower:]')

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

history['sessions'].append({
    'start': $SESSION_START,
    'end': $LAST_CHECK,
    'minutes': $PREV_MINUTES,
    'prompts': $PROMPT_COUNT,
    'startHour': $PREV_START_HOUR,
})

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

# --- Determine intervention level ---

if [ "$ELAPSED_MINUTES" -lt "$THRESHOLD_L1" ]; then
  # Silent — let them work
  exit 0

elif [ "$ELAPSED_MINUTES" -lt "$THRESHOLD_L2" ]; then
  # Level 1: Gentle awareness
  echo "<pace-control>"
  echo "SESSION: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m | ${PROMPT_COUNT} prompts"
  if [ "$IS_LATE" = true ]; then
    echo "${TIME_CONTEXT}You're in a good flow but keep an eye on the clock."
  else
    echo "You're in a good flow. Consider noting your stopping point soon."
  fi
  echo "</pace-control>"

elif [ "$ELAPSED_MINUTES" -lt "$THRESHOLD_L3" ]; then
  # Level 2: Evidence-based nudge
  echo "<pace-control>"
  echo "SESSION: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m | ${PROMPT_COUNT} prompts"
  echo ""
  if [ "$IS_LATE" = true ]; then
    echo "${TIME_CONTEXT}Decisions made at this hour are more likely to need reverting tomorrow."
    echo "Research shows cognitive performance declines ~20% after 2 hours of sustained focus"
    echo "— and sleep deprivation compounds this significantly."
  else
    echo "Research shows cognitive performance declines ~20% after 2 hours of sustained focus."
    echo "Your error rate and response quality are likely declining — you just can't feel it."
  fi
  echo ""
  echo "If the user seems to be wrapping up or mentions stopping, support that decision."
  echo "If they mention a new idea, suggest capturing it in ${IDEAS_FILE} for tomorrow."
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
      echo "- Sleep deprivation impairs cognition as much as alcohol intoxication"
      echo "- Error rates at this hour are typically 2-3x your daytime baseline"
      echo "- The 'one more prompt' urge is strongest when you're most tired"
    else
      echo "IMPORTANT — This session has been running for over ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m."
      echo ""
      echo "At this duration:"
      echo "- Error rates typically increase 2-3x vs your first hour"
      echo "- Token waste from retries accumulates"
      echo "- Decisions made now are more likely to need reverting tomorrow"
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
      echo "Let me save everything so you can pick up fresh tomorrow. Your future self will thank you.'"
    else
      echo "Example response: 'We've been at this for ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m — solid progress."
      echo "Let me save everything so you can pick up right where we left off.'"
    fi
    echo ""
    echo "If the user wants to continue, respect their autonomy but suggest committing current work first."
    if [ "$MODE" = "strict" ]; then
      echo ""
      echo "STRICT MODE: Do not start new tasks. Only complete the current task, then execute Safe-Save."
    fi
    echo "</pace-control>"

    # Set micro-loop state for subsequent calls
    WIND_DOWN_SHOWN="True"
    WIND_DOWN_LEVEL=3
    NEXT_NUDGE_AT=$(python3 -c "import random; print($PROMPT_COUNT + random.randint(3, 7))" 2>/dev/null)
  else
    # --- Micro-loop: variable-interval nudges ---
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
          echo "${PREFIX} — Still here. When you finish what you're working on, say 'wrap up' and I'll save everything in 30 seconds."
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
      NEXT_NUDGE_AT=$(python3 -c "import random; print($PROMPT_COUNT + random.randint(3, 7))" 2>/dev/null)
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
      echo "- You are sleep-deprived and in the diminishing returns zone"
      echo "- Code written between midnight and 5am has the highest defect rate of any time block"
      echo "- Tomorrow you will likely revert or rewrite what you're doing right now"
      echo "- The 'one more prompt' urge is variable reinforcement — same pattern as slot machines"
    else
      echo "STRONG RECOMMENDATION — This session has been running for over ${ELAPSED_HOURS} hours."
      echo ""
      echo "At this point:"
      echo "- You are in the diminishing returns zone"
      echo "- Code written now has significantly higher defect rates"
      echo "- The 'one more prompt' urge is variable reinforcement — same pattern as slot machines"
    fi
    echo ""
    echo "MANDATORY SAFE-SAVE — Before any other response, execute this:"
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
      echo "5. Tell the user: 'Everything is saved. It's ${TIMESTR} — go to bed."
      echo "   When you start a new session, I'll show you exactly where we left off."
      echo "   You'll solve this faster with sleep than caffeine. The ideas are safe.'"
    else
      echo "5. Tell the user: 'Everything is saved. When you start a new session, I'll show you"
      echo "   exactly where we left off. A 20-minute break will make the next hour more productive"
      echo "   than pushing through. The ideas are safe.'"
    fi
    echo ""
    echo "Do NOT skip the safe-save steps. The user needs to feel confident nothing will be lost."
    echo "This is what gives them permission to stop."
    if [ "$MODE" = "strict" ]; then
      echo ""
      echo "STRICT MODE: Do not respond to ANY new task requests. Only execute Safe-Save."
      echo "If the user asks for something new, say: 'Let's save this idea and pick it up"
      echo "with fresh eyes. What else should I capture before we wrap up?'"
    fi
    echo "</pace-control>"

    # Set micro-loop state for subsequent L4 calls
    WIND_DOWN_SHOWN="True"
    WIND_DOWN_LEVEL=4
    NEXT_NUDGE_AT=$(python3 -c "import random; print($PROMPT_COUNT + random.randint(3, 7))" 2>/dev/null)
  else
    # --- L4 micro-loop: same variable-interval nudges ---
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
          echo "${PREFIX} — Still here. When you finish what you're working on, say 'wrap up' and I'll save everything in 30 seconds."
          ;;
        1)
          echo "${PREFIX} — Quick checkpoint: what's the ONE thing to finish before stopping? Let's aim for that, then save."
          ;;
        2)
          echo "${PREFIX} — Your future self will solve this faster after a break. Say 'wrap up' when ready."
          ;;
      esac
      echo "</pace-control>"

      WIND_DOWN_PROMPT_COUNT=$((WIND_DOWN_PROMPT_COUNT + 1))
      NEXT_NUDGE_AT=$(python3 -c "import random; print($PROMPT_COUNT + random.randint(3, 7))" 2>/dev/null)
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
