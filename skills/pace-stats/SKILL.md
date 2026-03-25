---
name: pace-stats
description: View your session history, outcome data, and whether Pace Control's nudges are actually working.
---

# Pace Stats

Read the session history and present a useful summary.

## What to Do

1. Read `~/.claude/pace-control-history.json`
2. Present the data in a clear format:

### Summary (last 30 days)
- Total sessions: [count]
- Total time: [hours]
- Average session: [minutes]
- Late-night sessions (after 11pm): [count]

### Nudge Effectiveness
- Sessions that reached L3+: [count]
- Of those, sessions that ended with /wrap-up: [count] ([percentage])
- Average prompts after first L3 nudge: [number]
- Average session length when /wrap-up was used: [minutes] vs not used: [minutes]

### Patterns
- Most common session start hour: [hour]
- Longest session: [duration]
- Current streak: [X] of last [Y] sessions ended before Level 4

### Interpretation
Be honest about what the data shows:
- If wrap-up rate is high (>50%), say "The nudges appear to be working — you're wrapping up most sessions."
- If wrap-up rate is low (<20%), say "Most sessions end without /wrap-up. The nudges may not be changing your behaviour. Consider adjusting mode or messaging settings."
- If there's not enough data (fewer than 5 sessions with L3+), say "Not enough data yet to assess nudge effectiveness."

## Tone
- Factual, not judgmental
- Present the data, let the user draw conclusions
- If the data suggests the tool isn't working, say so honestly
