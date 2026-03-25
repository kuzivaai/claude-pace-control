# claude-pace-control

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**The off-switch for Claude Code.**

---

## Why I built this

Since I started using Claude Code, I've struggled to sleep. I'm either coding or thinking about coding. I know this isn't the first time you're reading something like this, because you're probably going through the exact same thing.

I started seeing it everywhere. The [Reddit threads](https://www.reddit.com/r/ClaudeAI/comments/1kwrmfn/claude_code_is_like_going_from_weed_to_crack/). The Instagram posts. People describing the same loop: "just one more prompt," then it's 3am and you're refactoring code that was fine to begin with. I thought I had a problem. I do. But it's validating that it's not just me.

Regardless, I need to sleep better. I simply need to do better.

I have a [command centre](https://github.com/kuzivaai/hangar) I built for myself called Hangar that tracks my (embarrassingly) five projects, including Hangar itself. And I thought, okay, let me see if I can help myself by locking myself out of Claude. That's why I built this.

## How It Works

Pace Control uses Claude Code's [hook system](https://docs.anthropic.com/en/docs/claude-code/hooks) to inject context into Claude's responses. No daemon, no background process, no server. Just a Python module, two bash wrappers, and Claude's own helpfulness.

### Progressive Intervention

Silent when you're productive. Escalates only when the evidence says you're declining.

| Level | Daytime Threshold | Night Threshold (after 11pm) | What Claude Is Asked To Do |
|-------|-------------------|------------------------------|-----------------|
| 0 | 0–90 min | 0–45 min | Nothing. You're in the zone. |
| 1 | 90–120 min | 45–75 min | Mentions session length. No pressure. |
| 2 | 2–3 hours | 75 min–2 hours | Surfaces error rate evidence. Supports stopping. |
| 3 | 3–4 hours | 2–3 hours | Initiates Safe-Save Protocol. Suggests committing. |
| 4 | 4+ hours | 3+ hours | Automatic wind-down. Commits, saves context, captures ideas. |

### Late-Night Awareness

A 2-hour session at 2pm and a 2-hour session at 2am have measurably different outcomes. Pace Control adjusts accordingly.

- **Pre-session friction:** Start Claude Code after 11pm and it gently surfaces the time before responding. *"It's 11:47pm. Quick fix or exploration?"* One mention, not a lecture.
- **Faster escalation:** All thresholds shift down 25-50% at night. Level 4 messaging references sleep research and cites evidence directly.
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

After the first Safe-Save message, Pace Control doesn't keep repeating the same wall of text. It switches to short check-ins every 5 prompts:

> *"SESSION: 3h 25m | 52 prompts — Still here. When you finish what you're working on, say 'wrap up' and I'll save everything."*

Silent between check-ins. If you cross into Level 4, you get one full automatic wind-down message, then the micro-loop resumes with more direct messaging.

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
| **Dismissal** | One click to ignore | Woven into Claude's response |
| **Evidence** | "Time's up" | Research-backed session data |
| **On stop** | Nothing happens | Commits code, saves context, captures ideas |
| **Resume** | None | Full context injection next session |
| **Autonomy** | Timer-based alerts | Shows evidence, respects choice |
| **First 90 min** | May interrupt flow | Completely silent |
| **Escalation** | Typically same intensity | 5 levels, progressive |

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

The whole thing is a Python module with two bash wrappers. Copy the `scripts/` directory anywhere, make the `.sh` files executable, and point your hooks at them. Requires Python 3.

## Configuration

Create `~/.claude/pace-control-config.json` to customise. Optional, the defaults are sensible:

```json
{
  "mode": "gentle",
  "messaging": "full",
  "nightStartHour": 23,
  "nightEndHour": 6,
  "gapThreshold": 1800
}
```

| Option | Values | Default | What it does |
|--------|--------|---------|-------------|
| `mode` | `gentle` / `firm` / `strict` | `gentle` | How aggressively thresholds are applied |
| `messaging` | `full` / `awareness` / `tracking` | `full` | How verbose the interventions are |
| `nightStartHour` | 0–23 | 23 | When late-night mode activates |
| `nightEndHour` | 0–23 | 6 | When late-night mode deactivates |
| `gapThreshold` | seconds | 1800 | Inactivity gap that starts a new session |

### Modes

- **Gentle** is the default. Evidence and suggestions, full autonomy. For most people.
- **Firm** reduces thresholds by 25% with stronger language. Still respects your choice.
- **Strict** halves all thresholds. At Level 4, Claude suggests saving instead of starting new tasks (say "override" to continue). For people who've asked to be held accountable.

### Messaging Verbosity

- **Full** is the default. Evidence-based nudges, session data, and the Safe-Save protocol at L3+.
- **Awareness** shows session duration and brief evidence. No inline safe-save protocol — just suggests `/wrap-up`.
- **Tracking** shows only a timer line. No evidence, no protocol. For users who want the data without any nudging.

## Files

All state lives in `~/.claude/`. Plain text. Deletable. Yours.

| File | Created | Purpose |
|------|---------|---------|
| `pace-control-state.{PID}.json` | Automatically | Current session state (per-terminal) |
| `pace-control-config.json` | By you (optional) | Mode, night hours, gap threshold |
| `pace-control-history.json` | Automatically | Session log (last 30 days) for weekly patterns |
| `pace-control-resume.md` | By wind-down | Saved context for next session |
| `pace-control-ideas.md` | By wind-down | Captured ideas |

## Skills

**Check session health:** `/pace-check` — see your current session duration, prompt count, and an evidence-based assessment.

**Save and stop:** `/wrap-up` — commits code, saves session context, captures ideas. Your next session picks up exactly where you left off.

**Research details:** `/pace-info` — see the evidence behind Pace Control's interventions, with citations, sample sizes, and honest quality ratings.

Copy the skill files from `skills/` to your Claude Code skills directory, or install via the plugin system.

## Why not just use a break timer?

Tools like Stretchly, DeskBreak, and Pomodoro apps remind you to take breaks. They work for general computer use. They don't work for AI-assisted coding because:

- **They're external.** A notification you dismiss in one click. Pace Control lives inside Claude's response — you can't ignore it without reading it.
- **They're context-unaware.** Fixed intervals regardless of what you're doing. Pace Control is silent for the first 90 minutes because that's when you're productive.
- **They don't save anything.** When a break timer goes off, you still have to manually save your work, remember where you were, and capture your ideas. Pace Control does all of that.
- **They don't know it's 3am.** Pace Control shifts all thresholds down 25-50% at night and references sleep research instead of generic productivity stats.

Other Claude Code tools like [claude-pulse](https://github.com/NoobyGains/claude-pulse) and [claude_timings_wrapper](https://github.com/martinambrus/claude_timings_wrapper) track time and usage limits — but they never act on it. They show you data. Pace Control intervenes.

## Known Limitations

- **Claude Code only:** This uses Claude Code's hook system. It won't work with Cursor, Copilot, or other AI coding tools.
- **System clock:** Thresholds use your local system time. If you travel across time zones, night mode shifts with you.
- **Python 3 required:** Used for JSON parsing. The scripts will show a clear error message if Python 3 isn't found.
- **No cross-machine sync:** State files are local to your machine.

## Data Practices

Pace Control runs entirely on your machine. No data is sent anywhere. All state files are stored in `~/.claude/` as plain JSON and markdown. There is no server, no analytics, no telemetry. You can delete all data at any time with `rm ~/.claude/pace-control-*`.

## Uninstalling

1. Remove the `SessionStart` and `PostToolUse` entries from `~/.claude/settings.json`
2. Optionally delete the state files: `rm ~/.claude/pace-control-*`
3. Optionally remove the repo: `rm -rf ~/.claude/plugins/pace-control`

## Research Backing

The intervention model is grounded in real research, not vibes:

- **METR (2025).** A controlled study found experienced developers were [19% slower with AI tools but believed they were 20% faster](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/). That perception gap is what Level 2's messaging addresses — the decline is difficult to self-assess.
- **Generative AI Addiction Disorder (2025).** A [ScienceDirect paper](https://www.sciencedirect.com/science/article/abs/pii/S1876201825001194) proposes GAID as a behavioural framework describing compulsive AI interaction patterns. This is a proposed research framework, not a validated clinical diagnosis — but the pattern it describes (difficulty disengaging from AI coding sessions) maps to behaviours many developers report.
- **Anders Ericsson** observed that elite performers tend to practise in 60-90 minute sessions (Ericsson et al., 1993). This is an observational finding, not an experimentally validated optimum, but it informs Level 0's silent period as a reasonable heuristic.
- **B.F. Skinner** established that variable reinforcement schedules produce persistent response rates in classic demonstrations. The "one more prompt" loop has structural similarities to this pattern, though the specific application to AI coding has not been empirically studied.
- **Cognitive offloading.** Formulating specific plans for incomplete tasks reduces their cognitive interference (Masicampo & Baumeister, 2011). The Safe-Save Protocol is designed around this finding — saving context with specific next steps releases the hold that unfinished work exerts.
- **Thaler & Sunstein (Nudge theory).** Modifying the choice environment is more effective than relying on willpower. Pace Control modifies Claude's responses rather than asking you to self-regulate.

## Contributing

Issues and PRs welcome. If this helped you sleep, consider starring the repo.

## Licence

[MIT](LICENSE). Do whatever you want with it. If it helps you sleep, that's enough.
