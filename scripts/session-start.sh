#!/bin/bash
# Pace Control — Session Start Handler
# Shows resume context from previous session, saved ideas,
# weekly patterns, and late-night friction prompts.

# --- Preflight: check dependencies ---
if ! command -v python3 &>/dev/null; then
  echo "<pace-control-error>"
  echo "Pace Control requires Python 3 for JSON parsing but python3 was not found."
  echo "Install Python 3 or add it to your PATH to enable session tracking."
  echo "</pace-control-error>"
  exit 0
fi

# --- Ensure ~/.claude/ directory exists ---
CLAUDE_DIR="${HOME}/.claude"
mkdir -p "$CLAUDE_DIR"

STATE_FILE="${CLAUDE_DIR}/pace-control-state.${PPID}.json"
OLD_STATE_FILE="${CLAUDE_DIR}/pace-control-state.json"

# --- Migration: rename old-format state file to PID-stamped ---
if [ -f "$OLD_STATE_FILE" ]; then
  mv "$OLD_STATE_FILE" "$STATE_FILE"
fi
CONFIG_FILE="${CLAUDE_DIR}/pace-control-config.json"
IDEAS_FILE="${CLAUDE_DIR}/pace-control-ideas.md"
RESUME_FILE="${CLAUDE_DIR}/pace-control-resume.md"
HISTORY_FILE="${CLAUDE_DIR}/pace-control-history.json"

NOW=$(date +%s)
CURRENT_HOUR=$(date +%-H)
HAS_RESUME=false
HAS_IDEAS=false

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
  # Wraps midnight (e.g., 23-6)
  if [ "$CURRENT_HOUR" -ge "$NIGHT_START" ] || [ "$CURRENT_HOUR" -lt "$NIGHT_END" ]; then
    IS_LATE=true
  fi
else
  if [ "$CURRENT_HOUR" -ge "$NIGHT_START" ] && [ "$CURRENT_HOUR" -lt "$NIGHT_END" ]; then
    IS_LATE=true
  fi
fi

# --- Aggregate across terminals ---
OTHER_TERMINALS=0
AGGREGATE_MINUTES=0
for PEER_STATE in "$CLAUDE_DIR"/pace-control-state.*.json; do
  [ -f "$PEER_STATE" ] || continue
  [ "$PEER_STATE" = "$STATE_FILE" ] && continue
  PEER_PID=$(echo "$PEER_STATE" | grep -oE '[0-9]+\.json$' | grep -oE '^[0-9]+')
  if ! kill -0 "$PEER_PID" 2>/dev/null; then
    rm -f "$PEER_STATE"
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

MULTI_TERMINAL_LINE=""
if [ "$OTHER_TERMINALS" -gt 0 ]; then
  OWN_MINUTES=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('totalMinutes',0))" 2>/dev/null || echo 0)
  TOTAL_AGGREGATE=$((AGGREGATE_MINUTES + OWN_MINUTES))
  TOTAL_AGG_HOURS=$((TOTAL_AGGREGATE / 60))
  TOTAL_AGG_REMAINING=$((TOTAL_AGGREGATE % 60))
  MULTI_TERMINAL_LINE="You have ${OTHER_TERMINALS} other Claude Code session(s) running (combined total: ${TOTAL_AGG_HOURS}h ${TOTAL_AGG_REMAINING}m across all terminals)."
fi

# --- Check for resume context from previous session ---
if [ -f "$RESUME_FILE" ] && [ -s "$RESUME_FILE" ]; then
  HAS_RESUME=true
fi

# Check for saved ideas
if [ -f "$IDEAS_FILE" ] && [ -s "$IDEAS_FILE" ]; then
  IDEA_COUNT=$(grep -c "^-" "$IDEAS_FILE" 2>/dev/null || echo 0)
  if [ "$IDEA_COUNT" -gt 0 ]; then
    HAS_IDEAS=true
  fi
fi

# --- Build weekly stats ---
WEEKLY_CONTEXT=""
STREAK_CONTEXT=""
if [ -f "$HISTORY_FILE" ]; then
  IFS=$'\t' read -r WEEKLY_CONTEXT STREAK_CONTEXT < <(python3 -c "
import json

now = $NOW
week_ago = now - 7 * 86400
night_start = $NIGHT_START

try:
    history = json.load(open('$HISTORY_FILE'))
    sessions = history.get('sessions', [])
except:
    history = {}
    sessions = []

# Weekly stats
weekly = ''
recent = [s for s in sessions if s.get('end', 0) > week_ago]
if len(recent) >= 3:
    total_hours = sum(s.get('minutes', 0) for s in recent) / 60
    late_count = sum(1 for s in recent if s.get('startHour', 12) >= night_start or s.get('startHour', 12) < 6)
    longest = max((s.get('minutes', 0) for s in recent), default=0)
    avg_length = sum(s.get('minutes', 0) for s in recent) / len(recent) if recent else 0

    parts = []
    parts.append(f'Last 7 days: {len(recent)} sessions, {total_hours:.1f}h total.')
    if late_count > 0:
        suffix = 's' if late_count != 1 else ''
        parts.append(f'{late_count} late-night session{suffix} (after {night_start}:00).')
    if longest > 180:
        parts.append(f'Longest session: {longest // 60}h {longest % 60}m.')
    if avg_length > 120:
        parts.append(f'Average session: {avg_length:.0f}m — trending long.')
    weekly = ' '.join(parts)

# Streak
streak_line = ''
streak = history.get('streak', {'current': 0, 'best': 0})
current = streak.get('current', 0)
best = streak.get('best', 0)
if current >= 2:
    streak_line = f'Healthy stop streak: {current} sessions in a row.'
elif current == 0 and best >= 2:
    streak_line = f'Last session ran long. Previous best: {best} sessions. Fresh start now.'

# Print tab-separated
print(weekly, end='\t')
print(streak_line)
" 2>/dev/null)
fi

# --- Output resume context if available ---
if [ "$HAS_RESUME" = true ] || [ "$HAS_IDEAS" = true ]; then
  echo "<pace-control-resume>"
  echo "Welcome back. Your previous session was saved safely."
  echo ""

  if [ -n "$WEEKLY_CONTEXT" ]; then
    echo "WEEKLY: ${WEEKLY_CONTEXT}"
    if [ -n "$STREAK_CONTEXT" ]; then
      echo "STREAK: ${STREAK_CONTEXT}"
    fi
    echo ""
  fi

  if [ -n "$MULTI_TERMINAL_LINE" ]; then
    echo "$MULTI_TERMINAL_LINE"
    echo ""
  fi

  if [ "$HAS_RESUME" = true ]; then
    echo "=== SESSION RESUME ==="
    cat "$RESUME_FILE"
    echo ""
    echo "=== END RESUME ==="
    echo ""
  fi

  if [ "$HAS_IDEAS" = true ]; then
    echo "=== SAVED IDEAS ==="
    cat "$IDEAS_FILE"
    echo ""
    echo "=== END IDEAS ==="
    echo ""
  fi

  echo "INSTRUCTIONS:"
  echo "1. Greet the user and summarise where they left off (from the resume above)"
  echo "2. List their saved ideas if any"
  echo "3. Ask: 'Want to pick up where we left off, start with one of your saved ideas, or work on something new?'"
  echo "4. Once they decide, proceed normally"
  echo "5. After the user has acknowledged, clear the resume and ideas files by running:"
  echo "   rm -f '${RESUME_FILE}' && : > '${IDEAS_FILE}'"
  echo "   (Do this silently after the user has chosen what to work on, not before)"
  echo "</pace-control-resume>"

# --- Late-night pre-session friction (only when no resume) ---
elif [ "$IS_LATE" = true ]; then
  TIMESTR=$(date '+%-I:%M%p' | tr '[:upper:]' '[:lower:]')
  echo "<pace-control-late-start>"
  echo "It's ${TIMESTR}. Starting a new session now often leads to 3am finishes."
  echo ""
  if [ -n "$WEEKLY_CONTEXT" ]; then
    echo "WEEKLY: ${WEEKLY_CONTEXT}"
    if [ -n "$STREAK_CONTEXT" ]; then
      echo "STREAK: ${STREAK_CONTEXT}"
    fi
    echo ""
  fi
  if [ -n "$MULTI_TERMINAL_LINE" ]; then
    echo "$MULTI_TERMINAL_LINE"
    echo ""
  fi
  echo "INSTRUCTIONS:"
  echo "Before responding to the user's first message, gently surface the time:"
  echo ""
  echo "Example: 'It's ${TIMESTR} — just flagging that. If this is a quick fix, let's do it."
  echo "If it's exploration or a new feature, capturing the idea and starting fresh tomorrow"
  echo "usually goes better. What would you like to do?'"
  echo ""
  echo "If the user wants to proceed, respect that and work normally."
  echo "If they want to capture ideas and stop, help them save to ${IDEAS_FILE}."
  echo "Do NOT be preachy. One mention of the time, then move on."
  echo "</pace-control-late-start>"

# --- Daytime, no resume, but weekly context or streak worth surfacing ---
elif [ -n "$WEEKLY_CONTEXT" ] || [ -n "$STREAK_CONTEXT" ]; then
  # Only surface weekly context if there's something concerning (3+ late nights) or streak info
  LATE_COUNT=$(echo "$WEEKLY_CONTEXT" | grep -oE '[0-9]+ late-night' | grep -oE '^[0-9]+' || echo "0")
  if [ "$LATE_COUNT" -gt 2 ] || [ -n "$STREAK_CONTEXT" ]; then
    echo "<pace-control-weekly>"
    if [ -n "$WEEKLY_CONTEXT" ]; then
      echo "WEEKLY: ${WEEKLY_CONTEXT}"
    fi
    if [ -n "$STREAK_CONTEXT" ]; then
      echo "STREAK: ${STREAK_CONTEXT}"
    fi
    echo ""
    if [ -n "$MULTI_TERMINAL_LINE" ]; then
      echo "$MULTI_TERMINAL_LINE"
      echo ""
    fi
    echo "INSTRUCTIONS:"
    echo "Briefly mention the weekly stats in your greeting if relevant."
    echo "Do not lecture. One line is enough."
    echo "</pace-control-weekly>"
  fi

# --- First-run welcome (no history = brand new install) ---
elif [ ! -f "$HISTORY_FILE" ]; then
  echo "<pace-control-welcome>"
  echo "Pace Control is active. It will stay silent for the first 90 minutes — that's when you're productive."
  echo ""
  echo "After that, it progressively surfaces session health data inside Claude's responses."
  echo "You can check your session status anytime with /pace-check."
  echo ""
  if [ -n "$MULTI_TERMINAL_LINE" ]; then
    echo "$MULTI_TERMINAL_LINE"
    echo ""
  fi
  echo "INSTRUCTIONS:"
  echo "Briefly acknowledge Pace Control is running. One sentence, then proceed with the user's request normally."
  echo "Example: 'Pace Control is active — I'll keep an eye on session health. What are we working on?'"
  echo "Do NOT explain how it works in detail. Just confirm it's there and move on."
  echo "</pace-control-welcome>"
fi

# --- Reset session state for new session ---
echo "{\"sessionStart\":${NOW},\"totalMinutes\":0,\"promptCount\":0,\"lastCheck\":${NOW},\"windDownShown\":false,\"windDownPromptCount\":0,\"nextNudgeAt\":0,\"windDownLevel\":0}" > "$STATE_FILE"
