---
name: wrap-up
description: Save everything and stop — commits code, saves session context, captures ideas. Use when you're done coding or when Pace Control suggests wrapping up.
---

# Wrap Up

Save everything so the next session picks up exactly where you left off.

## What to Do

### Step 1: Ask what they were working on

Ask the user: "What were you working on? One sentence is fine."

Wait for their response.

### Step 2: Ask for ideas

Ask: "Any ideas to capture before you stop?"

Wait for their response. If they have ideas, append them to `~/.claude/pace-control-ideas.md` with a timestamp:

```markdown
## [Date] — Ideas from session
- [idea 1]
- [idea 2]
```

### Step 3: Run the mechanical save

Run this command with the user's description of what they were working on:

```bash
python3 <pace-control-scripts-dir>/pace_control.py save "user's description here"
```

(The script is in the pace-control plugin's scripts/ directory. If installed via plugin, Claude Code resolves the path automatically.)

This command:
- Commits tracked changes with a descriptive message
- Writes a resume file with git state and the user's description
- Marks the session as wrapped up for outcome tracking

### Step 4: Relay the results

Tell the user what was saved. Example:

"Everything saved:
- Committed: abc1234
- Context saved to ~/.claude/pace-control-resume.md
- 2 ideas captured

Your next session will pick up right where you left off."

## Tone

- Fast and matter-of-fact. The user decided to stop — save quickly, don't lecture.
- Do NOT mention session duration, research, or why stopping is good. They already decided.
