---
name: wrap-up
description: Save everything and stop — commits code, saves session context, captures ideas. Use when you're done coding or when Pace Control suggests wrapping up.
---

# Wrap Up

Execute the Safe Wind-Down Protocol. Save everything so the next session picks up exactly where you left off.

## What to Do

Execute these steps IN ORDER. Do not skip any.

### Step 1: Save Work

```bash
git status
```

If there are uncommitted changes:
- Stage relevant files (not node_modules, .env, etc.)
- Commit with a descriptive message summarising what was accomplished
- Tell the user what was committed

If no changes, say "Working tree clean — nothing to commit."

### Step 2: Save Session Context

Write a resume file to `~/.claude/pace-control-resume.md`:

```markdown
## Session Resume — [date and time]

### What We Were Working On
[Describe the current task, feature, or bug]

### Current State
- What's complete: [list completed items]
- What's in progress: [list partially done work]
- What's not started: [list remaining items if known]

### Next Steps
1. [Specific next action — be precise enough that a fresh session can pick this up]
2. [Second action]
3. [Third action if applicable]

### Modified Files
- `path/to/file1` — [what was changed]
- `path/to/file2` — [what was changed]

### Open Questions
- [Any decisions that need to be made]
- [Any blockers or unknowns]
```

### Step 3: Capture Ideas

Ask: "Any ideas racing through your mind? I'll save them so you won't lose them."

Wait for the user's response. Append to `~/.claude/pace-control-ideas.md`:

```markdown
## [Date] — Ideas from session
- [idea 1]
- [idea 2]
```

### Step 4: Confirm

Tell the user:

"Everything is saved:
- Code committed: [commit message or 'nothing to commit']
- Session context saved to ~/.claude/pace-control-resume.md
- [N] ideas captured

When you start a new Claude Code session, I'll show you exactly where we left off. Nothing is lost."

## Tone

- Fast and matter-of-fact. The user decided to stop — respect that by saving quickly, not by lecturing.
- Do NOT mention session duration, research, or why stopping is good. They already decided.
- The goal is to save efficiently, not to lecture. A few minutes to save everything properly.
