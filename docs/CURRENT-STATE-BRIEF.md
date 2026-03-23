# Current State Brief — claude-pace-control

**Generated:** 2026-03-23

---

## What This Project Is

- Session health guardrails for Claude Code — two bash hook scripts that progressively intervene as coding sessions get longer.
- **Tech stack:** Bash, inline Python 3 (stdlib only, for JSON parsing and randomisation). No runtime dependencies beyond what the scripts themselves need.
- **Deployment status:** Published to GitHub at `github.com/kuzivaai/claude-pace-control`. Installable as a Claude Code plugin. CI running on GitHub Actions. Version 0.3.0.

## What It Does / Covers

**Core functionality:**
- `session-tracker.sh` (491 lines) — PostToolUse hook. Tracks session duration, outputs progressive interventions at 5 levels (L0 silent → L4 mandatory wind-down).
- `session-start.sh` (257 lines) — SessionStart hook. Shows resume context, weekly stats, streak data, late-night friction prompts, multi-terminal stats.

**Built features (verified in codebase):**
- 5-level progressive intervention with configurable thresholds
- Time-of-day awareness — night thresholds shift down ~40%, sleep-specific messaging
- Weekly pattern detection — surfaces cumulative stats (session count, late-night count, longest session)
- Safe Wind-Down Protocol — git commit, session context save, idea capture, resume on next start
- Micro-loop at Level 3+ — variable-interval one-liner nudges (3-7 prompts, randomised) replace repeated wall of text after first fire
- L4 transition with windDownLevel guard preventing double-fire bug
- Multi-terminal awareness — PID-stamped state files, peer aggregation, stale process detection
- Healthy-stop streak — tracks consecutive sessions ended before L4, surfaces on session start
- Three modes: gentle (default), firm (25% lower thresholds), strict (50% lower, refuses new tasks at L4)
- `/pace-check` skill for manual session health check
- Plugin packaging with `.claude-plugin/plugin.json` manifest

**Test coverage:**
- `test-output.sh` (370 lines) — 38 structural tests covering all levels, modes, micro-loop, night mode, multi-terminal, streak, edge cases. Runs in CI.
- `test-compliance.py` (227 lines) — API compliance tests (manual, costs ~$0.50/run). Sends pace-control output to Claude API, checks response for verifiable markers. Not run in CI.

**State files (all in `~/.claude/`):**
- `pace-control-state.{PPID}.json` — per-terminal session state (8 fields)
- `pace-control-config.json` — user config (optional)
- `pace-control-history.json` — session log (last 30 days) with streak data
- `pace-control-resume.md` — saved context for next session
- `pace-control-ideas.md` — captured ideas

## Current Scale

- **GitHub stars:** 0
- **Forks:** 0
- **Open issues:** 0
- **Subscribers:** 0
- **Known users:** Author only (no public adoption evidence in project files)
- **Revenue:** Zero. MIT-licensed open source.

## Existing Strategic Documents

- `docs/superpowers/specs/2026-03-22-v1.1-improvements-design.md` — v1.1 design spec (micro-loop, compliance tests, plugin packaging). Status: implemented.
- `docs/superpowers/specs/2026-03-23-v1.2-improvements-design.md` — v1.2 design spec (multi-terminal, streak, Show HN). Status: implemented.
- `docs/superpowers/plans/2026-03-22-v1.1-improvements.md` — v1.1 implementation plan. Status: executed.
- `docs/superpowers/plans/2026-03-23-v1.2-improvements.md` — v1.2 implementation plan. Status: executed.
- `docs/show-hn-draft.md` — Hacker News launch post draft. Status: written, not posted.
- Research report at `~/Documents/Pace_Control_Improvement_Research_20260322/` — competitive analysis and improvement recommendations. Scored project 7.5/10 pre-improvements, projected 8.5-8.7/10 post-improvements.

**Key milestones mentioned:**
- v0.1.0 — initial release (5-level intervention, time-of-day, weekly patterns, Safe Wind-Down, session resume)
- v0.2.0 — micro-loop, compliance tests, plugin packaging
- v0.3.0 — multi-terminal awareness, healthy-stop streak, Show HN prep (current)
- Show HN launch — drafted but not submitted. Research recommends Tuesday/Wednesday, 8-10am ET.

## Stated Differentiation

From README and research report:
- "The off-switch for Claude Code that Anthropic won't build"
- Core claim: the barrier to stopping is anxiety about losing progress, not willpower. Safe Wind-Down Protocol addresses this by saving everything.
- Differentiates from break timer apps (Stretchly, DeskBreak, Pomodoro) on: lives inside terminal not external notification, progressive escalation not fixed intervals, saves context on stop not nothing, silent first 90 minutes.
- No direct competitor found in research — no other tool combines progressive intervention + time-of-day awareness + cognitive offloading + session resume inside Claude Code's hook system.

**Constraints / dependencies:**
- Claude Code only — does not work with Cursor, Copilot, Windsurf, or other AI coding tools
- Requires Claude Code v1.0.33+ with hooks support
- Requires Python 3 (for JSON parsing)
- Relies on Claude following injected `<pace-control>` instructions — probabilistic, not deterministic. Compliance rate unmeasured (API compliance tests exist but haven't been run with a real API key per project files)
- State files are local to the machine — no cross-machine sync
- System clock dependent — time zones shift with travel

## Total Codebase

- 23 commits
- 1,419 lines of functional code (scripts)
- 597 lines of test code
- 5 bash scripts, 1 Python script
- 1 CI workflow
- 4 design/plan documents
- 1 launch draft
