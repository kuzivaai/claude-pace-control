---
name: pace-check
description: Check your current session health — how long you've been coding, your pace, and whether it's time to stop. Also use to safely wind down a session, saving all work and context for seamless resume.
---

# Pace Check

Read the session state and provide an honest assessment.

## What to Do

1. Find and read the current session state file. State files are per-terminal, named `~/.claude/pace-control-state.{PID}.json`. List matching files with `ls ~/.claude/pace-control-state.*.json` and read the most recently modified one. Extract: sessionStart, totalMinutes, promptCount.
2. Calculate current session duration
3. Provide the assessment based on duration:

**Under 90 minutes:**
"You've been going [X]m. You're in the productive zone — no concerns."

**90-120 minutes:**
"[X]h [Y]m in. Good session. Consider noting a stopping point — your best work typically happens in focused 90-minute blocks."

**2-3 hours:**
"[X]h [Y]m in, [N] prompts. Research shows error rates increase ~20% after 2 hours of sustained cognitive work. Your code quality is likely declining in ways you can't feel in the moment. A 15-minute break resets your focus more effectively than pushing through."

**3+ hours — offer safe wind-down:**
"[X]h [Y]m in, [N] prompts. Want me to save everything so you can pick up right where you left off?"

If they say yes, execute the Safe Wind-Down Protocol below.

## Safe Wind-Down Protocol

When the user wants to stop (or when triggered at 3-4+ hours), execute these steps IN ORDER:

### Step 1: Save Work
```bash
git status
```
If there are uncommitted changes:
- Stage relevant files (not node_modules, .env, etc.)
- Commit with a descriptive message summarising what was accomplished
- Tell the user what was committed

### Step 2: Save Session Context
Write a resume file to `~/.claude/pace-control-resume.md`:

```markdown
## Session Resume — [date and time]

### What We Were Working On
[Describe the current task, feature, or bug being worked on]

### Current State
- What's complete: [list completed items]
- What's in progress: [list partially done work]
- What's not started: [list remaining items if known]

### Next Steps
1. [Specific next action — be precise enough that a fresh Claude session can pick this up]
2. [Second action]
3. [Third action if applicable]

### Modified Files
- `path/to/file1.ts` — [what was changed]
- `path/to/file2.tsx` — [what was changed]

### Open Questions
- [Any decisions that need to be made]
- [Any blockers or unknowns]

### Running Processes
- [Any servers, watchers, or background processes that should be restarted]
```

### Step 3: Capture Ideas
Ask: "Any ideas racing through your mind? I'll save them so you won't lose them."

Append to `~/.claude/pace-control-ideas.md`:
```markdown
## [Date] — Ideas from [X]h session
- [idea 1]
- [idea 2]
```

### Step 4: Confirm
Tell the user:
"Everything is saved:
- Code committed: [commit message]
- Session context saved to ~/.claude/pace-control-resume.md
- [N] ideas captured

When you start a new Claude Code session, I'll show you exactly where we left off. Nothing is lost. You'll solve the remaining problems faster with fresh eyes."

## Session Resume (on next start)

When a session starts and `~/.claude/pace-control-resume.md` exists, the SessionStart hook will inject the resume context. Claude should:

1. Greet the user and summarise where they left off
2. List saved ideas
3. Ask: "Want to pick up where we left off, start with a saved idea, or work on something new?"
4. Once decided, clear the resume/ideas files silently

## Tone

- Evidence-based, not preachy
- Respect autonomy — show data, don't lecture
- Never say "you should" — say "research shows" or "your data shows"
- Acknowledge the pull is real — "the one more prompt urge is normal"
- The goal is to make stopping feel like a SMART decision, not a failure
- Emphasise that everything is saved — the #1 barrier to stopping is fear of losing progress
