# claude-pace-control

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**The off-switch for Claude Code that Anthropic won't build.**

---

## Why I built this

Since I started using Claude Code, I've struggled to sleep. I'm either coding or thinking about coding. I know this isn't the first time you're reading something like this, because you're probably going through the exact same thing.

I started seeing it everywhere. The [Reddit threads](https://www.reddit.com/r/ClaudeAI/comments/1kwrmfn/claude_code_is_like_going_from_weed_to_crack/). The Instagram posts. People describing the same loop: "just one more prompt," then it's 3am and you're refactoring code that was fine to begin with. I thought I had a problem. I do. But it's validating that it's not just me.

Tinfoil hat moment: I think Anthropic is doing something weird. But regardless, I need to sleep better. I simply need to do better.

I have a [command centre](https://github.com/kuzivaai/hangar) I built for myself called Hangar that tracks my (embarrassingly) five projects, including Hangar itself. And I thought, okay, let me see if I can help myself by locking myself out of Claude. That's why I built this.

## How It Works

Pace Control uses Claude Code's [hook system](https://docs.anthropic.com/en/docs/claude-code/hooks) to inject context into Claude's responses. No daemon, no background process, no server. Just two bash scripts and Claude's own helpfulness.

### Progressive Intervention

Silent when you're productive. Escalates only when the evidence says you're declining.

| Level | Daytime Threshold | Night Threshold (after 11pm) | What Claude Does |
|-------|-------------------|------------------------------|-----------------|
| 0 | 0–90 min | 0–45 min | Nothing. You're in the zone. |
| 1 | 90–120 min | 45–75 min | Mentions session length. No pressure. |
| 2 | 2–3 hours | 75 min–2 hours | Surfaces error rate evidence. Supports stopping. |
| 3 | 3–4 hours | 2–3 hours | Initiates Safe-Save Protocol. Suggests committing. |
| 4 | 4+ hours | 3+ hours | Mandatory wind-down. Commits, saves context, captures ideas. |

### Late-Night Awareness

A 2-hour session at 2pm is productive. A 2-hour session at 2am is pathological. Pace Control knows the difference.

- **Pre-session friction:** Start Claude Code after 11pm and it gently surfaces the time before responding. *"It's 11:47pm. Quick fix or exploration?"* One mention, not a lecture.
- **Faster escalation:** All thresholds shift down ~40% at night. Level 4 messaging is blunt. *"It's 2:17am. Go to bed."*
- **Sleep-specific framing:** Night-time nudges reference sleep deprivation research instead of generic productivity stats.

### Weekly Pattern Detection

Surfaces cumulative stats on session start:

> *"Last 7 days: 12 sessions, 18.5h total. 4 late-night sessions (after 23:00). Longest session: 5h 12m."*

If you've had 3+ late-night sessions in a week, you'll see this even during daytime starts. Not a guilt trip. Just a pattern you might not have noticed.

### The Safe Wind-Down Protocol

The reason people don't stop isn't willpower. It's anxiety about losing progress. The Wind-Down Protocol eliminates that anxiety:

1. **Commits your work.** `git status`, stage, commit with a descriptive message.
2. **Saves session context.** What you were working on, current state, next steps, modified files, open questions.
3. **Captures ideas.** *"Any thoughts racing? I'll save them so you won't lose them."*
4. **Resumes next time.** Your next Claude Code session opens with full context: *"Welcome back. Last time you were working on X, you finished Y, and the next step is Z."*

### Micro-Loop at Level 3+

After the first Safe-Save message, Pace Control doesn't keep repeating the same wall of text. It switches to short, variable-interval check-ins every 3-7 prompts:

> *"SESSION: 3h 25m | 52 prompts — Still here. When you finish what you're working on, say 'wrap up' and I'll save everything in 30 seconds."*

Silent between check-ins. If you cross into Level 4, you get one full mandatory wind-down message, then the micro-loop resumes.

### Multi-Terminal Awareness

If you have multiple Claude Code terminals open, Pace Control aggregates time across all of them:

> *"Note: You also have 2 other terminal(s) running. Combined time across all: 5h 12m."*

Each terminal has its own state file. Dead terminals are cleaned up automatically.

### Healthy-Stop Streak

Tracks consecutive sessions where you stopped before Level 4:

> *"Healthy stop streak: 5 sessions in a row."*

Surfaced on session start only — never during work. If the streak breaks: *"Last session ran long. Previous best: 8 sessions. Fresh start now."* Data, not guilt.

### What Makes This Different

| Property | Break Reminder Apps | Pace Control |
|----------|-------------------|--------------|
| **Location** | External notification | Inside your terminal |
| **Dismissal** | One click to ignore | Part of Claude's response |
| **Evidence** | "Time's up" | "Your error rate is increasing" |
| **On stop** | Nothing happens | Commits code, saves context, captures ideas |
| **Resume** | None | Full context injection next session |
| **Autonomy** | Nags or blocks | Shows evidence, respects choice |
| **First 90 min** | May interrupt flow | Completely silent |
| **Escalation** | Same intensity always | 5 levels, progressive |

**Key insight:** The barrier to stopping isn't willpower. It's anxiety about losing progress. Remove the anxiety, and people stop naturally.

## Install

**Prerequisites:** Claude Code v1.0.33+ with hooks support, Python 3, bash.

### Quick Install (Plugin)

The easiest way. One command, no manual configuration:

```bash
claude /plugin install --url https://github.com/kuzivaai/claude-pace-control
```

That's it. Hooks and skills are registered automatically.

### Manual Install

If you prefer to manage things yourself, or if your Claude Code version doesn't support plugins:

#### Step 1: Clone the repo

```bash
git clone https://github.com/kuzivaai/claude-pace-control.git ~/.claude/plugins/pace-control
chmod +x ~/.claude/plugins/pace-control/scripts/*.sh
```

#### Step 2: Add hooks to your settings

Add these hooks to `~/.claude/settings.json` (create the file if it doesn't exist, or merge with existing hooks):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/plugins/pace-control/scripts/session-start.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/plugins/pace-control/scripts/session-tracker.sh",
            "async": true,
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

#### Step 3: Verify

Start a Claude Code session. You should see **no output**. Level 0 is silent for the first 90 minutes (45 at night). That means it's working.

### Alternative: Just grab the scripts

The whole thing is two bash scripts. Copy `scripts/session-start.sh` and `scripts/session-tracker.sh` anywhere, make them executable, and point your hooks at them.

## Configuration

Create `~/.claude/pace-control-config.json` to customise. Optional, the defaults are sensible:

```json
{
  "mode": "gentle",
  "nightStartHour": 23,
  "nightEndHour": 6,
  "gapThreshold": 1800
}
```

| Option | Values | Default | What it does |
|--------|--------|---------|-------------|
| `mode` | `gentle` / `firm` / `strict` | `gentle` | How aggressively thresholds are applied |
| `nightStartHour` | 0–23 | 23 | When late-night mode activates |
| `nightEndHour` | 0–23 | 6 | When late-night mode deactivates |
| `gapThreshold` | seconds | 1800 | Inactivity gap that starts a new session |

### Modes

- **Gentle** is the default. Evidence and suggestions, full autonomy. For most people.
- **Firm** reduces thresholds by 25% with stronger language. Still respects your choice.
- **Strict** halves all thresholds. At Level 4, Claude refuses new tasks and only completes current work + Safe-Save. For people who've asked to be held accountable.

## Files

All state lives in `~/.claude/`. Plain text. Deletable. Yours.

| File | Created | Purpose |
|------|---------|---------|
| `pace-control-state.{PID}.json` | Automatically | Current session state (per-terminal) |
| `pace-control-config.json` | By you (optional) | Mode, night hours, gap threshold |
| `pace-control-history.json` | Automatically | Session log (last 30 days) for weekly patterns |
| `pace-control-resume.md` | By wind-down | Saved context for next session |
| `pace-control-ideas.md` | By wind-down | Captured ideas |

## Manual Check

Check your session health anytime with the `/pace-check` skill. Copy `skills/pace-check/SKILL.md` to your Claude Code skills directory.

```
/pace-check
```

## Known Limitations

- **Multi-terminal:** Sessions are tracked per-terminal with aggregate stats surfaced when multiple terminals are active. Stale terminals are detected and cleaned up automatically.
- **Claude Code only:** This uses Claude Code's hook system. It won't work with Cursor, Copilot, or other AI coding tools.
- **System clock:** Thresholds use your local system time. If you travel across time zones, night mode shifts with you.
- **Python 3 required:** Used for JSON parsing. The scripts will show a clear error message if Python 3 isn't found.
- **No cross-machine sync:** State files are local to your machine.

## Uninstalling

1. Remove the `SessionStart` and `PostToolUse` entries from `~/.claude/settings.json`
2. Optionally delete the state files: `rm ~/.claude/pace-control-*`
3. Optionally remove the repo: `rm -rf ~/.claude/plugins/pace-control`

## Research Backing

The intervention model is grounded in real research, not vibes:

- **Gloria Mark (UC Irvine)** researched attention span and cognitive degradation curves over sustained work. Recovery from interruption takes ~25 minutes.
- **Anders Ericsson** found that peak performers sustain focused work in 90-minute blocks. That's the basis for Level 0's silent period.
- **B.F. Skinner** showed that variable ratio reinforcement schedules produce the highest, most persistent response rates. The "one more prompt" loop follows this pattern exactly.
- **Zeigarnik Effect.** Incomplete tasks occupy working memory disproportionately. Writing down an idea (cognitive offloading) releases the hold, making it safe to stop.
- **Thaler & Sunstein (Nudge theory).** Modifying the choice environment is more effective than relying on willpower. Pace Control modifies Claude's responses rather than asking you to self-regulate.

## Contributing

Issues and PRs welcome. If this helped you sleep, consider starring the repo.

## Licence

[MIT](LICENSE). Do whatever you want with it. If it helps you sleep, that's enough.
