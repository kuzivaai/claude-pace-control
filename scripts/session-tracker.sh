#!/bin/bash
# Pace Control — Session Time Tracker
# Tracks continuous Claude Code usage and outputs health signals.
#
# State file: ~/.claude/pace-control-state.json
# Resume file: ~/.claude/pace-control-resume.md (saved context for next session)
# Ideas file: ~/.claude/pace-control-ideas.md (captured thoughts)

STATE_FILE="${HOME}/.claude/pace-control-state.json"
IDEAS_FILE="${HOME}/.claude/pace-control-ideas.md"
RESUME_FILE="${HOME}/.claude/pace-control-resume.md"

# Ensure state file exists
if [ ! -f "$STATE_FILE" ]; then
  echo '{"sessionStart":0,"totalMinutes":0,"promptCount":0,"lastCheck":0}' > "$STATE_FILE"
fi

NOW=$(date +%s)

# Read current state
SESSION_START=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('sessionStart',0))" 2>/dev/null || echo 0)
PROMPT_COUNT=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('promptCount',0))" 2>/dev/null || echo 0)
LAST_CHECK=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('lastCheck',0))" 2>/dev/null || echo 0)

# If session start is 0 or gap > 30 minutes, start new session
GAP=$((NOW - LAST_CHECK))
if [ "$SESSION_START" -eq 0 ] || [ "$GAP" -gt 1800 ]; then
  SESSION_START=$NOW
  PROMPT_COUNT=0
fi

# Update state
PROMPT_COUNT=$((PROMPT_COUNT + 1))
ELAPSED_MINUTES=$(( (NOW - SESSION_START) / 60 ))
ELAPSED_HOURS=$(( ELAPSED_MINUTES / 60 ))
REMAINING_MINUTES=$(( ELAPSED_MINUTES % 60 ))

# Write updated state
python3 -c "
import json
state = {
    'sessionStart': $SESSION_START,
    'totalMinutes': $ELAPSED_MINUTES,
    'promptCount': $PROMPT_COUNT,
    'lastCheck': $NOW,
}
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f)
" 2>/dev/null

# Determine intervention level based on elapsed time
# Level 0: < 90 min  — silent (productive zone)
# Level 1: 90-120 min — gentle awareness
# Level 2: 120-180 min — evidence-based nudge
# Level 3: 180-240 min — firm with safe-save protocol
# Level 4: 240+ min — strong recommendation with full wind-down

if [ "$ELAPSED_MINUTES" -lt 90 ]; then
  # Silent — let them work
  exit 0

elif [ "$ELAPSED_MINUTES" -lt 120 ]; then
  # Level 1: Gentle awareness
  echo "<pace-control>"
  echo "SESSION: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m | ${PROMPT_COUNT} prompts"
  echo "You're in a good flow. Consider noting your stopping point soon."
  echo "</pace-control>"

elif [ "$ELAPSED_MINUTES" -lt 180 ]; then
  # Level 2: Evidence-based nudge
  echo "<pace-control>"
  echo "SESSION: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m | ${PROMPT_COUNT} prompts"
  echo ""
  echo "Research shows cognitive performance declines ~20% after 2 hours of sustained focus."
  echo "Your error rate and response quality are likely declining — you just can't feel it."
  echo ""
  echo "If the user seems to be wrapping up or mentions stopping, support that decision."
  echo "If they mention a new idea, suggest capturing it in ${IDEAS_FILE} for tomorrow."
  echo "</pace-control>"

elif [ "$ELAPSED_MINUTES" -lt 240 ]; then
  # Level 3: Firm with SAFE-SAVE protocol
  echo "<pace-control>"
  echo "SESSION: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m | ${PROMPT_COUNT} prompts"
  echo ""
  echo "IMPORTANT — This session has been running for over 3 hours."
  echo ""
  echo "At this duration:"
  echo "- Error rates typically increase 2-3x vs your first hour"
  echo "- Token waste from retries accumulates"
  echo "- Decisions made now are more likely to need reverting tomorrow"
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
  echo "Example response: 'We've been at this for ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m — solid progress."
  echo "Let me save everything so you can pick up right where we left off. I'll commit the current work,"
  echo "write up where we are, and capture any ideas. Nothing will be lost.'"
  echo ""
  echo "If the user wants to continue, respect their autonomy but suggest committing current work first."
  echo "</pace-control>"

else
  # Level 4: Strong recommendation with full wind-down
  echo "<pace-control>"
  echo "SESSION: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m | ${PROMPT_COUNT} prompts"
  echo ""
  echo "STRONG RECOMMENDATION — This session has been running for over 4 hours."
  echo ""
  echo "At this point:"
  echo "- You are in the diminishing returns zone"
  echo "- Code written now has significantly higher defect rates"
  echo "- The 'one more prompt' urge is variable reinforcement — same pattern as slot machines"
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
  echo "5. Tell the user: 'Everything is saved. When you start a new session, I'll show you"
  echo "   exactly where we left off. A 20-minute break will make the next hour more productive"
  echo "   than pushing through. The ideas are safe.'"
  echo ""
  echo "Do NOT skip the safe-save steps. The user needs to feel confident nothing will be lost."
  echo "This is what gives them permission to stop."
  echo "</pace-control>"
fi
