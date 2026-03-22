# claude-pace-control

Look, we need to talk about this.

I've been using Claude Code since launch and somewhere around week three I realised I hadn't gone to bed before 2am in five consecutive days. I'd finish a feature, feel the rush, and think "just one more prompt." Three hours later I'm refactoring code that was fine to begin with and my commit messages are getting progressively unhinged.

I know I'm not alone. Every Claude Code thread has the same energy — "this thing is crack," "I can't stop," "my girlfriend thinks I'm having an affair with my terminal." We're all half-joking. Half.

So I built this. It's a Claude Code hook that tracks how long you've been going and progressively nudges you to stop. Not by nagging. Not by locking you out. It just starts showing you evidence that you're getting worse — because you are, you just can't feel it at 1am.

The key trick: it captures your racing ideas before you stop, so the "but I'll forget this brilliant thing" excuse doesn't work anymore. Everything gets saved. Next session, Claude shows you exactly where you left off. Nothing lost.

**Use it or don't. But if you've ever looked up from your terminal and realised the sun came up, maybe give it a go.**

## How It Works

Pace Control runs as a hook inside Claude Code. It's silent for the first 90 minutes — that's your productive zone, no interruptions. After that, it escalates gradually:

| Duration | What Happens |
|----------|-------------|
| 0–90 min | **Nothing.** You're in the zone. |
| 90–120 min | **Gentle note.** Session length mentioned, no pressure. |
| 2–3 hours | **Evidence nudge.** "Error rates increase ~20% after 2 hours of sustained focus." |
| 3–4 hours | **Safe-save prompt.** Suggests committing work and saving context. |
| 4+ hours | **Full wind-down.** Commits code, saves session context, captures ideas. |

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

## Requirements

- Bash
- Python 3 (used for JSON parsing in the tracker — literally 3 lines)
- Claude Code with hooks support

## Configuration

The only real config is the session gap threshold — if you stop prompting for more than 30 minutes, it starts a new session. Change the `1800` value on line 27 of `scripts/session-tracker.sh` if you want different timing.

State lives in `~/.claude/pace-control-state.json`. Ideas go to `~/.claude/pace-control-ideas.md`. Resume context goes to `~/.claude/pace-control-resume.md`. All plain text, all deletable, all yours.

## How it actually works (for the curious)

There's no daemon, no background process, no server. The `PostToolUse` hook fires after every tool call Claude makes. The script checks how long you've been going, and if you're past a threshold, it injects a `<pace-control>` message into Claude's context. Claude reads it and adjusts its behaviour — mentioning session length, suggesting commits, offering to capture ideas.

The `SessionStart` hook checks if you left a resume file last time. If you did, it injects it so Claude can greet you with "here's where you left off."

That's literally it. Two scripts, some JSON state, and Claude's own helpfulness doing the rest.

## Why not just set a timer?

Because timers don't know what you're working on. They can't commit your code. They can't save your context. They can't capture the idea that's keeping you awake. And you'll dismiss a timer. You won't dismiss Claude saying "we've been at this for 4 hours, let me save everything so you can pick up tomorrow."

The intervention is *inside* the thing you're addicted to. That's the whole point.

## Licence

MIT — do whatever you want with it. If it helps you sleep, that's enough.
