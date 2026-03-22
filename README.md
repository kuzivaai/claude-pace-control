# claude-pace-control

Look, we need to talk about this.

I've been using Claude Code since launch and somewhere around week three I realised I hadn't gone to bed before 2am in five consecutive days. I'd finish a feature, feel the rush, and think "just one more prompt." Three hours later I'm refactoring code that was fine to begin with and my commit messages are getting progressively unhinged.

I know I'm not alone. Every Claude Code thread has the same energy — "this thing is crack," "I can't stop," "my girlfriend thinks I'm having an affair with my terminal." We're all half-joking. Half.

So I built this. It's a Claude Code hook that tracks how long you've been going and progressively nudges you to stop. Not by nagging. Not by locking you out. It just starts showing you evidence that you're getting worse — because you are, you just can't feel it at 1am.

The key trick: it captures your racing ideas before you stop, so the "but I'll forget this brilliant thing" excuse doesn't work anymore. Everything gets saved. Next session, Claude shows you exactly where you left off. Nothing lost.

**Use it or don't. But if you've ever looked up from your terminal and realised the sun came up, maybe give it a go.**

## How It Works

Pace Control runs as a hook inside Claude Code. It's silent for the first 90 minutes — that's your productive zone, no interruptions. After that, it escalates gradually:

| Duration (daytime) | Duration (after 11pm) | What Happens |
|--------------------|----------------------|-------------|
| 0–90 min | 0–45 min | **Nothing.** You're in the zone. |
| 90–120 min | 45–75 min | **Gentle note.** Session length mentioned, no pressure. |
| 2–3 hours | 75 min–2 hours | **Evidence nudge.** Error rate data + sleep deprivation framing at night. |
| 3–4 hours | 2–3 hours | **Safe-save prompt.** Suggests committing work and saving context. |
| 4+ hours | 3+ hours | **Full wind-down.** Commits code, saves session context, captures ideas. |

### Late-Night Awareness

The problem isn't 2-hour sessions at 2pm. It's 2-hour sessions at 2am.

If you start a session after 11pm, Pace Control does two things:
1. **Pre-session friction** — before Claude responds, it gently surfaces the time and asks whether this is a quick fix or exploration. One mention, not a lecture.
2. **Faster escalation** — all thresholds shift down. Level 2 kicks in at 75 minutes instead of 120. At level 4, the messaging is blunt: *"It's 2:17am — go to bed."*

### Weekly Patterns

Pace Control tracks your session history and surfaces weekly stats on session start:

> *"Last 7 days: 12 sessions, 18.5h total. 4 late-night sessions (after 23:00). Longest session: 5h 12m."*

If you've had 3+ late-night sessions in a week, you'll see this context even during daytime starts. It's not a guilt trip — it's a pattern you might not have noticed.

### The Wind-Down Protocol

When you do stop (or when Claude starts firmly suggesting it), here's what happens:

1. **Commits your work** — staged, messaged, pushed if you want
2. **Saves session context** — what you were working on, current state, next steps, modified files
3. **Captures your ideas** — "any thoughts racing? I'll save them for tomorrow"
4. **Resumes next time** — your next Claude Code session opens with everything you saved

The resume is the bit that actually matters. The reason people don't stop is fear of losing momentum. This removes that fear.

### Manual Check

You can also check your session health anytime:

```
/pace-check
```

## Install

### Option 1: Clone and hook up

```bash
git clone https://github.com/kuzivaai/claude-pace-control.git ~/.claude/plugins/pace-control
chmod +x ~/.claude/plugins/pace-control/scripts/*.sh
```

Then add these hooks to your `~/.claude/settings.json` (create the file if it doesn't exist, or merge with your existing hooks):

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

### Option 2: Just grab the scripts

Honestly, the whole thing is two bash scripts. Copy `scripts/session-start.sh` and `scripts/session-tracker.sh` somewhere, make them executable, and point your hooks at them. That's it.

## Configuration

Create `~/.claude/pace-control-config.json` to customise behaviour:

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

- **Gentle** — current default. Evidence and suggestions. Full autonomy.
- **Firm** — thresholds reduced by 25%. Stronger language. Still respects choice.
- **Strict** — thresholds halved. At Level 4, Claude refuses new tasks and only completes current work + Safe-Save. For people who've asked to be held accountable.

The config file is optional. Without it, everything runs on gentle mode with default timings.

## Requirements

- Bash
- Python 3 (used for JSON parsing — a few lines per script)
- Claude Code with hooks support

## Files

All state lives in `~/.claude/`. All plain text. All deletable. All yours.

| File | Purpose |
|------|---------|
| `pace-control-state.json` | Current session: start time, prompt count, last check |
| `pace-control-config.json` | Optional config: mode, night hours, gap threshold |
| `pace-control-history.json` | Session log (last 30 days) for weekly pattern detection |
| `pace-control-resume.md` | Saved context from last wind-down |
| `pace-control-ideas.md` | Captured ideas from wind-down sessions |

## How it actually works (for the curious)

There's no daemon, no background process, no server. The `PostToolUse` hook fires after every tool call Claude makes. The script checks how long you've been going, what time it is, and what mode you're in. If you're past a threshold, it injects a `<pace-control>` message into Claude's context. Claude reads it and adjusts its behaviour — mentioning session length, suggesting commits, offering to capture ideas.

The `SessionStart` hook checks three things: (1) do you have a resume file from last time? (2) is it late at night? (3) what do your weekly patterns look like? It injects the relevant context before Claude responds.

When a session ends (gap > 30 minutes), the tracker logs it to a history file. This builds the weekly pattern data that surfaces on your next session start.

That's literally it. Two scripts, some JSON state, and Claude's own helpfulness doing the rest.

## Why not just set a timer?

Because timers don't know what you're working on. They can't commit your code. They can't save your context. They can't capture the idea that's keeping you awake. And you'll dismiss a timer. You won't dismiss Claude saying "it's 2am and we've been at this for 3 hours, let me save everything so you can pick up tomorrow."

The intervention is *inside* the thing you're addicted to. That's the whole point.

## Known Limitations

- **Multi-terminal:** If you have 3 Claude Code terminals open, each is tracked independently. Power users will understand this. A shared state file is possible but adds complexity — maybe v2.
- **Time zones:** Uses your system clock. If you travel, thresholds shift with you.
- **Not a replacement for discipline:** This is a nudge, not a lock. If you're determined to code at 4am, nothing will stop you. But it'll make sure your work is saved when you inevitably crash.

## Licence

MIT — do whatever you want with it. If it helps you sleep, that's enough.
