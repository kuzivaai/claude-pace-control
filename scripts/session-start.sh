#!/bin/bash
# Pace Control — Session Start Handler
# Shows resume context from previous session and saved ideas.

STATE_FILE="${HOME}/.claude/pace-control-state.json"
IDEAS_FILE="${HOME}/.claude/pace-control-ideas.md"
RESUME_FILE="${HOME}/.claude/pace-control-resume.md"

NOW=$(date +%s)
HAS_RESUME=false
HAS_IDEAS=false

# Check for resume context from previous session
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

# Output resume context if available
if [ "$HAS_RESUME" = true ] || [ "$HAS_IDEAS" = true ]; then
  echo "<pace-control-resume>"
  echo "Welcome back. Your previous session was saved safely."
  echo ""

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
fi

# Reset session state for new session
echo "{\"sessionStart\":${NOW},\"totalMinutes\":0,\"promptCount\":0,\"lastCheck\":${NOW}}" > "$STATE_FILE"
