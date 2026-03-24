# Launch Readiness — Inspection Spec

**Date:** 2026-03-24
**Scope:** Fix what's broken, update what's stale, ship what exists.

---

## Inspection Findings

### 1. Tests are broken — 8 of 38 failing

**Severity: Blocking**

`scripts/test-output.sh` has 8 failures. Root cause: tests labelled "daytime" don't force daytime via config. They rely on the system clock. When run at night (currently 4:32am SAST), the night thresholds activate, so:
- 100m hits L2 instead of L1 (night L1 threshold is 45m)
- 200m hits L4 instead of L3 (night L3 threshold is 120m)
- Micro-loop tests at 200m enter L4 instead of L3

**Failing tests:**
- `L1 daytime — good flow` (line 121) — at night, 100m is L2
- `L3 daytime first-fire` (line 134) — at night, 200m is L4
- `L3 daytime — not L4` (line 135) — at night, 200m IS L4
- `L3 micro-nudge fires` (line 151) — at night, 200m is L4 range
- `L3 micro-loop silent` (line 158) — at night, 200m is L4 range
- `L3 boundary silent` (line 165) — same
- `Firm mode L1 — good flow` (line 185) — firm mode at night, 70m is past L1
- `No config — good flow` (line 210) — no config at night, 90m is past L1

**Fix:** Add `setup_day_config` calls (force `nightStartHour=23, nightEndHour=6`) before every "daytime" test. The existing `setup_day_config` removes the config file — it needs to instead write a daytime config.

**CI passed previously** because the GitHub Actions runner (ubuntu-latest) runs in UTC where the tests were executed during daytime hours. This is a timezone-dependent flake.

### 2. README is stale — 3 sections don't match v0.3.0

**Severity: High-value fix**

- **Line 173:** Files table says `pace-control-state.json` — should be `pace-control-state.{PPID}.json` (per-terminal)
- **Line 189:** Known Limitations says "Multi-terminal: Each Claude Code terminal is tracked independently... Maybe v2" — multi-terminal is implemented in v0.3.0
- **Missing from README:** healthy-stop streak feature, micro-loop behaviour at L3+
- **Missing from README:** multi-terminal aggregation feature

These are what a first-time user reads. Stale info means the first impression is wrong.

### 3. Compliance rate is unsubstantiated

**Severity: Not blocking, but honest**

`test-compliance.py` exists and is well-structured. It has never been run with a real API key (no compliance results in the repo). The research report claims compliance testing "validates the foundation" but the foundation has not actually been validated.

Additionally, `test-compliance.py:113` writes state to `pace-control-state.json` (old format, not PID-stamped). When the tracker migrates this file, the state file path inside the script's temp directory will differ from what `generate_pace_control_output()` expects. This is a bug — the compliance tests will silently produce unexpected output.

**Not blocking for launch.** The tool works regardless of whether we've measured compliance rate. But the research report's score assumed compliance testing would validate the system — it hasn't.

### 4. Plugin manifest is minimal but functional

**Severity: No action needed**

`.claude-plugin/plugin.json` has name, description, version, author, homepage, repository, license. This matches what the plugin spec requires. No blocking fields missing.

### 5. State file integrity is sound

**Severity: No action needed**

- Each terminal writes only its own PID-stamped file
- Stale detection via `kill -0` works correctly
- Gap threshold check prevents counting idle peers
- The theoretical race condition (cleanup deleting a peer's file mid-write) is acknowledged in the spec and is inconsequential in practice

---

## Blocking Issues

| # | Issue | Fix | Effort |
|---|-------|-----|--------|
| 1 | 8/38 tests failing (timezone-dependent) | Force daytime config in all "daytime" tests | 30 min |

## High-Value Fixes

| # | Issue | Fix | Effort |
|---|-------|-----|--------|
| 2 | README stale on multi-terminal, streak, state file, micro-loop | Update 4 sections to match v0.3.0 | 45 min |
| 3 | test-compliance.py uses old state file format | Change line 113 to PID-stamped path | 5 min |

## Out of Scope

- Running compliance tests with a real API key (costs money, not blocking)
- Adding more test cases beyond the timezone fix
- Changing any intervention logic
- Show HN post timing/strategy (that's a marketing decision, not a code decision)
- Any new features
