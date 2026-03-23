# Show HN: Pace Control — Session health guardrails for Claude Code

**Title:** Show HN: Pace Control — Session health guardrails for Claude Code

**URL:** https://github.com/kuzivaai/claude-pace-control

---

I built this because I couldn't sleep.

Since I started using Claude Code, I've been staying up until 3am most nights. Not because the work is urgent — because the loop is addictive. "One more prompt" is the developer equivalent of "one more episode." Y Combinator's CEO Garry Tan posted that he stayed up 19 hours. Steve Yegge called himself addicted. There's a Hacker News thread literally titled "Addicted to Claude Code — Help."

I'm not the only one. But nobody was building the off-switch.

## What it does

Pace Control is a Claude Code hook system (two bash scripts, no daemon) that progressively intervenes as your session gets longer:

- **0-90 min:** Silent. You're productive.
- **90-120 min:** Mentions session length. No pressure.
- **2-3 hours:** Surfaces error-rate evidence. "Your code quality is declining — you just can't feel it."
- **3-4 hours:** Safe Wind-Down Protocol — commits your code, saves session context, captures ideas. Then switches to variable-interval one-liner nudges instead of repeating the same wall of text.
- **4+ hours:** Mandatory wind-down. Everything saved. "Go to bed."

At night, thresholds shift down 40%. The messaging references sleep deprivation research instead of generic productivity stats.

## The key insight

The reason people don't stop isn't willpower. It's anxiety about losing progress. The Wind-Down Protocol eliminates that anxiety — it commits your code, writes a resume file with exactly where you left off, and captures your ideas. Your next Claude Code session opens with full context.

## What makes it different from a break timer

It lives inside Claude's responses, not as an external notification you dismiss. The first 90 minutes are completely silent. It escalates based on evidence, not arbitrary intervals. And when you stop, nothing is lost.

It also tracks healthy-stop streaks and aggregates time across multiple terminals.

## Install

    claude /plugin install --url https://github.com/kuzivaai/claude-pace-control

GitHub: https://github.com/kuzivaai/claude-pace-control

---

**Posting notes:**
- Launch on Tuesday or Wednesday (research shows higher engagement)
- Post between 8-10am ET (US morning, EU afternoon)
- First comment: briefly explain the research backing (Ericsson's 90-min blocks, Skinner's variable reinforcement, Zeigarnik effect)
