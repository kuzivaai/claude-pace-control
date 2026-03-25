---
name: pace-check
description: Check your current session health — how long you've been coding, your pace, and whether it might be time to take a break. Use /wrap-up to save and stop.
---

# Pace Check

Read the session state and provide an honest assessment.

## What to Do

1. Read the session state file for the current terminal. The file is named `~/.claude/pace-control-state.{PID}.json` where PID is the parent process ID. You can find it by checking which PID-stamped file was most recently modified, but ideally match the current session's PID. List matching files with `ls -lt ~/.claude/pace-control-state.*.json` and read the most recently modified one. Extract: sessionStart, totalMinutes, promptCount.
2. Calculate current session duration
3. Provide the assessment based on duration:

**Under 90 minutes:**
"You've been going [X]m. You're in the productive zone — no concerns."

**90-120 minutes:**
"[X]h [Y]m in. Good session. Consider noting a stopping point — your best work typically happens in focused 90-minute blocks."

**2-3 hours:**
"[X]h [Y]m in, [N] prompts. Extended sessions widen the gap between perceived and actual performance. After a break, you'll likely notice issues you're missing now."

**3+ hours — suggest /wrap-up:**
"[X]h [Y]m in, [N] prompts. Want me to save everything? Just say /wrap-up — it commits your code, saves context, and captures ideas."

If they say yes, tell them to run `/wrap-up`. Do not attempt to do the git operations yourself.

## Saving Work

If the user wants to save, direct them to `/wrap-up`. That command handles everything mechanically — git commit, resume file, ideas capture.

Do not attempt to run git commands or write resume files yourself. The `/wrap-up` skill handles this.

## Tone

- Evidence-based, not preachy
- Respect autonomy — show data, don't lecture
- Never say "you should" — say "research shows" or "your data shows"
- Acknowledge the pull is real — extended sessions create momentum that can make stopping feel harder
- The goal is to make stopping feel like a SMART decision, not a failure
- Emphasise that everything is saved — the #1 barrier to stopping is fear of losing progress
