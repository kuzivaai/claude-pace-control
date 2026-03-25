# Evidence-Validated Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every issue identified across three rounds of critical validation — security vulnerabilities, unsupported claims, ethical inconsistencies, accessibility defects, and documentation inaccuracies — without changing the core architecture (bash + inline Python) in this release.

**Architecture:** All changes are within the existing two bash scripts (`session-tracker.sh`, `session-start.sh`), two skill files (`pace-check/SKILL.md`, `wrap-up/SKILL.md`), and `README.md`. No new files except an uninstall script. The Python module consolidation is deferred to a future release as a pure refactor — this plan ships fixes on top of the working, tested v0.3.0 architecture.

**Tech Stack:** Bash, Python 3 (stdlib only), Markdown

**Baseline:** 40/40 tests passing. All changes must maintain green tests. New tests added for new behaviour.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `scripts/session-tracker.sh` | Modify | Fix macOS date, remove unsupported claims, fix messaging, add transparency, security hardening |
| `scripts/session-start.sh` | Modify | Fix macOS date, fix late-night messaging, add /wrap-up to welcome, security hardening |
| `skills/pace-check/SKILL.md` | Modify | Remove unsupported "~20% error rate" claim, fix tone |
| `skills/wrap-up/SKILL.md` | Modify | Fix "30 seconds" claim |
| `README.md` | Modify | Fix tagline, GAID citation, unsupported claims, add Data Practices section |
| `scripts/test-output.sh` | Modify | Add tests for new messaging, L4 micro-loop differentiation |
| `scripts/uninstall.sh` | Create | Cleanup script for all pace-control files |
| `.github/ISSUE_TEMPLATE/feedback.md` | Create | Low-friction feedback channel including discomfort reporting |

---

### Task 1: Fix macOS `date` Compatibility

Both scripts use `date +%-H` (GNU extension to strip leading zero). BSD `date` on macOS does not support the `-` flag, breaking all threshold calculations.

**Files:**
- Modify: `scripts/session-tracker.sh:41-42`
- Modify: `scripts/session-start.sh:32,205`

- [ ] **Step 1: Write failing test for macOS date format**

Add to `scripts/test-output.sh` after line 107 (before existing tests):

```bash
# --- Date format: CURRENT_HOUR must be numeric ---
# Simulates what happens if date +%-H fails (macOS)
TEST_HOUR=$(date +%H | sed 's/^0//')
if [[ "$TEST_HOUR" =~ ^[0-9]+$ ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\nFAIL: Date format — CURRENT_HOUR not numeric (got: $TEST_HOUR)"
fi
```

- [ ] **Step 2: Run test to verify it passes on Linux (baseline)**

Run: `bash scripts/test-output.sh`
Expected: 41/41 pass (this test passes on Linux because `date +%H | sed 's/^0//'` works everywhere)

- [ ] **Step 3: Fix `session-tracker.sh` date formatting**

Replace lines 41-42:

```bash
# Old (GNU-only):
# CURRENT_HOUR=$(date +%-H)
# TIMESTR=$(date '+%-I:%M%p' | tr '[:upper:]' '[:lower:]')

# New (cross-platform):
CURRENT_HOUR=$(date +%H | sed 's/^0//')
TIMESTR=$(date '+%I:%M%p' | sed 's/^0//' | tr '[:upper:]' '[:lower:]')
```

- [ ] **Step 4: Fix `session-start.sh` date formatting**

Replace line 32:

```bash
CURRENT_HOUR=$(date +%H | sed 's/^0//')
```

Replace line 205:

```bash
TIMESTR=$(date '+%I:%M%p' | sed 's/^0//' | tr '[:upper:]' '[:lower:]')
```

- [ ] **Step 5: Run full test suite**

Run: `bash scripts/test-output.sh`
Expected: 41/41 pass

- [ ] **Step 6: Commit**

```bash
git add scripts/session-tracker.sh scripts/session-start.sh scripts/test-output.sh
git commit -m "fix: cross-platform date formatting — replace GNU %-H with portable sed strip"
```

---

### Task 2: Remove Unsupported Research Claims

Three claims in `session-tracker.sh` have no specific citation. The "2-3x error rate" numbers appear in L3 night (line 311), L3 day (line 317), and the slot machine comparison appears in L4 (lines 413, 420). The `/pace-check` skill also cites an unsupported "~20% error rate increase."

**Files:**
- Modify: `scripts/session-tracker.sh:309-312,316-319,410-413,417-420`
- Modify: `skills/pace-check/SKILL.md:23`

- [ ] **Step 1: Write test for removed claims**

Add to `scripts/test-output.sh` after the L3 daytime first-fire test (after line 150):

```bash
# --- L3: no unsupported "2-3x" or "slot machine" claims ---
cleanup
setup_day_config
setup_state 200 40 false
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_not_output "L3 daytime — no 2-3x claim" "2-3x" "$OUTPUT"
assert_not_output "L3 daytime — no slot machine" "slot machine" "$OUTPUT"

# L4: no unsupported claims
cleanup
setup_day_config
setup_state 250 55 false
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_not_output "L4 daytime — no 2-3x claim" "2-3x" "$OUTPUT"
assert_not_output "L4 daytime — no slot machine" "slot machine" "$OUTPUT"
```

- [ ] **Step 2: Run test to verify it fails (claims still present)**

Run: `bash scripts/test-output.sh`
Expected: 4 FAIL (the claims are still in the code)

- [ ] **Step 3: Fix L3 night messaging (lines 309-312)**

Replace:

```bash
    echo "At this hour and duration:"
    echo "- Sleep deprivation impairs cognition as much as alcohol intoxication"
    echo "- Error rates at this hour are typically 2-3x your daytime baseline"
    echo "- The 'one more prompt' urge is strongest when you're most tired"
```

With:

```bash
    echo "At this hour and duration:"
    echo "- After 17 hours awake, some cognitive measures decline to levels comparable to 0.05% BAC (Williamson & Feyer, 2000)"
    echo "- Midnight-4am commits correlate with higher bug rates in open-source projects (Eyolfson et al., 2014)"
    echo "- The urge to continue is strongest when you're most tired"
```

- [ ] **Step 4: Fix L3 day messaging (lines 316-319)**

Replace:

```bash
    echo "At this duration:"
    echo "- Error rates typically increase 2-3x vs your first hour"
    echo "- Token waste from retries accumulates"
    echo "- Decisions made now are more likely to need reverting tomorrow"
```

With:

```bash
    echo "At this duration:"
    echo "- Extended sessions show measurable output quality decline that is difficult to self-assess"
    echo "- Decisions made now are more likely to need reverting tomorrow"
    echo "- After a break, you will likely notice issues you are missing now"
```

- [ ] **Step 5: Fix L4 night messaging (lines 410-413)**

Replace:

```bash
    echo "- You are sleep-deprived and in the diminishing returns zone"
    echo "- Code written between midnight and 5am has the highest defect rate of any time block"
    echo "- Tomorrow you will likely revert or rewrite what you're doing right now"
    echo "- The 'one more prompt' urge is variable reinforcement — same pattern as slot machines"
```

With:

```bash
    echo "- You are in the diminishing returns zone"
    echo "- Midnight-4am commits correlate with significantly higher bug rates (Eyolfson et al., 2014)"
    echo "- Tomorrow you will likely revert or rewrite what you're doing right now"
```

- [ ] **Step 6: Fix L4 day messaging (lines 417-420)**

Replace:

```bash
    echo "- You are in the diminishing returns zone"
    echo "- Code written now has significantly higher defect rates"
    echo "- The 'one more prompt' urge is variable reinforcement — same pattern as slot machines"
```

With:

```bash
    echo "- You are in the diminishing returns zone"
    echo "- Extended sessions show measurable quality decline that is difficult to self-assess"
    echo "- After a break, you will notice things you are missing now"
```

- [ ] **Step 7: Fix `/pace-check` skill unsupported claim**

In `skills/pace-check/SKILL.md`, replace line 23:

```
"[X]h [Y]m in, [N] prompts. Research shows error rates increase ~20% after 2 hours of sustained cognitive work. Your code quality is likely declining in ways you can't feel in the moment. A 15-minute break resets your focus more effectively than pushing through."
```

With:

```
"[X]h [Y]m in, [N] prompts. Extended sessions widen the gap between perceived and actual performance. After a break, you'll likely notice issues you're missing now. Details: ask me about /pace-info."
```

- [ ] **Step 8: Run full test suite**

Run: `bash scripts/test-output.sh`
Expected: All pass (including 4 new assertions)

- [ ] **Step 9: Commit**

```bash
git add scripts/session-tracker.sh skills/pace-check/SKILL.md scripts/test-output.sh
git commit -m "fix: replace unsupported claims with cited research — remove 2-3x, slot machine"
```

---

### Task 3: Fix Paternalistic and Unverifiable Messaging

Remove "go to bed" (line 444), replace "You're in a good flow" (unverifiable assertion), replace "MANDATORY SAFE-SAVE" with "AUTOMATIC SAFE-SAVE", fix "30 seconds" claim, fix late-night presumptuous start message.

**Files:**
- Modify: `scripts/session-tracker.sh:267-269,284,322,423,443-446`
- Modify: `scripts/session-start.sh:207`
- Modify: `skills/wrap-up/SKILL.md:83`

- [ ] **Step 1: Write tests for removed paternalistic messaging**

Add to `scripts/test-output.sh`:

```bash
# --- No "go to bed" in any output ---
cleanup
setup_night_config
setup_state 250 55 false
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_not_output "L4 night — no 'go to bed'" "go to bed" "$OUTPUT"

# --- L1 should not claim "good flow" ---
cleanup
setup_day_config
setup_state 100 15
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_not_output "L1 daytime — no 'good flow'" "good flow" "$OUTPUT"
assert_output "L1 daytime — has 'All good'" "All good|all good" "$OUTPUT"

# --- L3 uses AUTOMATIC not MANDATORY ---
cleanup
setup_day_config
setup_state 200 40 false
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "L3 — AUTOMATIC SAFE-SAVE" "AUTOMATIC SAFE-SAVE" "$OUTPUT"
assert_not_output "L3 — no MANDATORY" "MANDATORY" "$OUTPUT"

# --- L4 uses AUTOMATIC not MANDATORY ---
cleanup
setup_day_config
setup_state 250 55 false
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "L4 — AUTOMATIC SAFE-SAVE" "AUTOMATIC SAFE-SAVE" "$OUTPUT"
assert_not_output "L4 — no MANDATORY" "MANDATORY" "$OUTPUT"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/test-output.sh`
Expected: Multiple FAIL (old messaging still present)

- [ ] **Step 3: Fix L1 messaging — replace "good flow" with factual**

In `session-tracker.sh`, replace lines 267-269:

```bash
  if [ "$IS_LATE" = true ]; then
    echo "${TIME_CONTEXT}Session: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m. All good. Consider noting a stopping point when you reach one."
  else
    echo "Session: ${ELAPSED_HOURS}h ${REMAINING_MINUTES}m. All good. Consider noting a stopping point when you reach one."
  fi
```

- [ ] **Step 4: Fix L2 day — remove METR misattribution about session length**

In `session-tracker.sh`, replace lines 283-284:

```bash
    echo "Extended sessions widen the gap between perceived and actual performance."
    echo "After a break, you will likely notice issues you are missing now."
```

- [ ] **Step 5: Fix L3 label — "SAFE-SAVE PROTOCOL" → "AUTOMATIC SAFE-SAVE"**

In `session-tracker.sh`, replace line 322:

```bash
    echo "AUTOMATIC SAFE-SAVE — When responding, naturally work towards wrapping up:"
```

- [ ] **Step 6: Fix L4 label and night close — "MANDATORY" → "AUTOMATIC", remove "go to bed"**

In `session-tracker.sh`, replace line 423:

```bash
    echo "AUTOMATIC SAFE-SAVE — Before any other response, execute this:"
```

Replace lines 443-446 (L4 night close):

```bash
    if [ "$IS_LATE" = true ]; then
      echo "5. Tell the user: 'Everything is saved. It's ${TIMESTR}. Your work is committed and context is preserved."
      echo "   Resume anytime — your next session will pick up right where you left off.'"
    else
```

- [ ] **Step 7: Fix late-night start — remove "often leads to 3am finishes"**

In `session-start.sh`, replace line 207:

```bash
  echo "It's ${TIMESTR}. Late start noted."
```

- [ ] **Step 8: Fix /wrap-up "30 seconds" claim**

In `skills/wrap-up/SKILL.md`, replace line 83:

```
- The goal is to save efficiently, not to lecture. A few minutes to save everything properly.
```

- [ ] **Step 9: Fix micro-loop "30 seconds" claim (lines 374, 483)**

In `session-tracker.sh`, replace both occurrences of "I'll save everything in 30 seconds" with:

```bash
          echo "${PREFIX} — Still here. When you finish what you're working on, say 'wrap up' and I'll save everything."
```

(Same change at line 483 for L4 micro-loop.)

- [ ] **Step 10: Fix existing L1 tests that check for "good flow"**

In `scripts/test-output.sh`, update the existing L1 test assertions (around lines 124 and 195) to match new messaging:

Replace `assert_output "L1 daytime — good flow" "good flow" "$OUTPUT"` with:
```bash
assert_output "L1 daytime — all good" "All good|all good" "$OUTPUT"
```

Replace `assert_output "Firm mode L1 — good flow" "good flow" "$OUTPUT"` with:
```bash
assert_output "Firm mode L1 — all good" "All good|all good" "$OUTPUT"
```

Update the L4 first-fire test (line 180) to match new label:
```bash
assert_output "L4 daytime first-fire" "AUTOMATIC SAFE-SAVE" "$OUTPUT"
```

And the L3-to-L4 reset test (line 187):
```bash
assert_output "L4 from L3 micro-loop — reset" "AUTOMATIC SAFE-SAVE" "$OUTPUT"
```

Update the L1 night test (line 220) — "keep an eye on the clock" was removed:
```bash
assert_output "L1 night — clock mention" "All good|stopping point" "$OUTPUT"
```

And the night L2 test (line 228) — update since we changed the sleep messaging in Task 2:
```bash
assert_output "L2 night (80m)" "reverting tomorrow|fatigue|sleep" "$OUTPUT"
```

- [ ] **Step 11: Run full test suite**

Run: `bash scripts/test-output.sh`
Expected: All pass

- [ ] **Step 12: Commit**

```bash
git add scripts/session-tracker.sh scripts/session-start.sh skills/wrap-up/SKILL.md scripts/test-output.sh
git commit -m "fix: remove paternalistic messaging — no 'go to bed', no 'good flow', AUTOMATIC not MANDATORY"
```

---

### Task 4: Add Transparency Marker at L3+

First L3 or L4 encounter per session should disclose that Pace Control is influencing Claude's response, with an override instruction.

**Files:**
- Modify: `scripts/session-tracker.sh` (L3 first-fire and L4 first-fire sections)

- [ ] **Step 1: Write test for transparency marker**

Add to `scripts/test-output.sh`:

```bash
# --- Transparency marker at L3 first-fire ---
cleanup
setup_day_config
setup_state 200 40 false
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "L3 transparency marker" "Pace Control is influencing" "$OUTPUT"

# --- Transparency marker at L4 first-fire ---
cleanup
setup_day_config
setup_state 250 55 false
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "L4 transparency marker" "Pace Control is influencing" "$OUTPUT"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-output.sh`
Expected: 2 FAIL

- [ ] **Step 3: Add transparency marker to L3 first-fire**

In `session-tracker.sh`, after line 346 (after the "respect their autonomy" line), add:

```bash
    echo ""
    echo "Pace Control is influencing this response. The user can adjust settings in ~/.claude/pace-control-config.json or disable hooks in ~/.claude/settings.json."
```

- [ ] **Step 4: Add transparency marker to L4 first-fire**

In `session-tracker.sh`, after line 454 (after "permission to stop"), add:

```bash
    echo ""
    echo "Pace Control is influencing this response. The user can adjust settings in ~/.claude/pace-control-config.json or disable hooks in ~/.claude/settings.json."
```

- [ ] **Step 5: Run full test suite**

Run: `bash scripts/test-output.sh`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add scripts/session-tracker.sh scripts/test-output.sh
git commit -m "feat: add transparency marker — disclose Pace Control influence at L3+"
```

---

### Task 5: Differentiate L4 Micro-Loop from L3

L4 micro-loop currently uses identical messages to L3. L4 should be noticeably more direct.

**Files:**
- Modify: `scripts/session-tracker.sh:481-491`

- [ ] **Step 1: Write test for L4 micro-loop differentiation**

Add to `scripts/test-output.sh`:

```bash
# --- L4 micro-loop is more direct than L3 ---
cleanup
setup_day_config
setup_state 266 65 true 0 65 4
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "L4 micro-nudge — direct" "work is not yet saved|save your work|committed" "$OUTPUT"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-output.sh`
Expected: 1 FAIL

- [ ] **Step 3: Replace L4 micro-loop messages**

In `session-tracker.sh`, replace lines 481-491 (L4 micro-loop case statement):

```bash
      case $NUDGE_INDEX in
        0)
          echo "${PREFIX} — Your work is not yet saved. Say 'wrap up' to commit and preserve context."
          ;;
        1)
          echo "${PREFIX} — Still going. Your code and context can be saved and resumed anytime. Say 'wrap up'."
          ;;
        2)
          echo "${PREFIX} — Extended session. Say 'wrap up' to save everything — takes a few minutes."
          ;;
      esac
```

- [ ] **Step 4: Run full test suite**

Run: `bash scripts/test-output.sh`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add scripts/session-tracker.sh scripts/test-output.sh
git commit -m "feat: differentiate L4 micro-loop — more direct than L3"
```

---

### Task 6: Security Hardening — File Permissions

Add `umask 077` before file creation and `chmod 600` on existing files at startup.

**Files:**
- Modify: `scripts/session-tracker.sh:20-21`
- Modify: `scripts/session-start.sh:16-17`

- [ ] **Step 1: Add umask and permission hardening to session-tracker.sh**

After line 19 (`CLAUDE_DIR="${HOME}/.claude"`), before `mkdir -p`, add:

```bash
umask 077
mkdir -p "$CLAUDE_DIR"
chmod 700 "$CLAUDE_DIR" 2>/dev/null
# Harden existing state files
chmod 600 "$CLAUDE_DIR"/pace-control-*.json 2>/dev/null
chmod 600 "$CLAUDE_DIR"/pace-control-*.md 2>/dev/null
```

Replace the existing `mkdir -p "$CLAUDE_DIR"` on line 21.

- [ ] **Step 2: Add same hardening to session-start.sh**

After line 15 (`CLAUDE_DIR="${HOME}/.claude"`), before `mkdir -p`, add the same block.

- [ ] **Step 3: Add symlink check before stale PID cleanup**

In `session-tracker.sh`, replace lines 175-177:

```bash
  if ! kill -0 "$PEER_PID" 2>/dev/null; then
    [ -L "$PEER_STATE" ] || rm -f "$PEER_STATE"
    continue
  fi
```

Same change in `session-start.sh` lines 69-71.

- [ ] **Step 4: Run full test suite**

Run: `bash scripts/test-output.sh`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add scripts/session-tracker.sh scripts/session-start.sh
git commit -m "fix: security hardening — umask 077, chmod 600, symlink protection"
```

---

### Task 7: Security Hardening — Resume/Ideas Injection

Escape XML entities in resume and ideas files before injecting into Claude's context. Truncate to 2000 characters.

**Files:**
- Modify: `scripts/session-start.sh:179,187`

- [ ] **Step 1: Create escape helper function**

In `session-start.sh`, add after the config loading section (after line 47):

```bash
# Escape XML-like content and truncate to prevent prompt injection
safe_cat() {
  local file="$1"
  local max_chars="${2:-2000}"
  if [ -f "$file" ] && [ -s "$file" ]; then
    head -c "$max_chars" "$file" | sed 's/</\&lt;/g; s/>/\&gt;/g'
  fi
}
```

- [ ] **Step 2: Replace raw `cat` with `safe_cat`**

In `session-start.sh`, replace line 179:

```bash
    safe_cat "$RESUME_FILE"
```

Replace line 187:

```bash
    safe_cat "$IDEAS_FILE"
```

- [ ] **Step 3: Run full test suite**

Run: `bash scripts/test-output.sh`
Expected: All pass (the resume test at line 276 checks for "Working on auth" which contains no XML characters, so safe_cat passes it through unchanged)

- [ ] **Step 4: Commit**

```bash
git add scripts/session-start.sh
git commit -m "fix: escape XML entities and truncate resume/ideas content before injection"
```

---

### Task 8: Add /wrap-up to First-Run Welcome

The tyre-kicker journey identified that the tool is silent for 90 minutes. The first-run welcome should mention both `/pace-check` and `/wrap-up` as immediate interaction points.

**Files:**
- Modify: `scripts/session-start.sh:258-261`

- [ ] **Step 1: Write test for /wrap-up in welcome**

Add to `scripts/test-output.sh`:

```bash
# --- First-run welcome mentions /wrap-up ---
cleanup
setup_day_config
rm -f "$HISTORY_FILE"
OUTPUT=$(bash "$STARTER" 2>/dev/null)
assert_output "First-run — mentions /wrap-up" "wrap-up" "$OUTPUT"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-output.sh`
Expected: 1 FAIL

- [ ] **Step 3: Update first-run welcome message**

In `session-start.sh`, replace lines 258-261:

```bash
  echo "Pace Control is active. It stays silent while you're productive."
  echo ""
  echo "Try /pace-check anytime to see your session status, or /wrap-up to save everything and stop."
```

- [ ] **Step 4: Run full test suite**

Run: `bash scripts/test-output.sh`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add scripts/session-start.sh scripts/test-output.sh
git commit -m "feat: add /wrap-up to first-run welcome for immediate tyre-kicker value"
```

---

### Task 9: Fix README — Tagline, Claims, Data Practices

Fix all README issues identified across validation rounds.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Fix tagline (line 5)**

Replace:

```markdown
**The off-switch for Claude Code that Anthropic won't build.**
```

With:

```markdown
**The off-switch for Claude Code.**
```

- [ ] **Step 2: Fix "Tinfoil hat" line (line 15)**

Remove line 15 entirely:

```
Tinfoil hat moment: I think Anthropic is doing something weird. But regardless, I need to sleep better. I simply need to do better.
```

Replace with:

```
Regardless, I need to sleep better. I simply need to do better.
```

- [ ] **Step 3: Fix intervention table — "What Claude Does" → "What Claude Is Asked To Do" (line 27)**

Replace:

```markdown
| Level | Daytime Threshold | Night Threshold (after 11pm) | What Claude Does |
```

With:

```markdown
| Level | Daytime Threshold | Night Threshold (after 11pm) | What Claude Is Asked To Do |
```

- [ ] **Step 4: Fix Late-Night section — remove "go to bed" reference (line 40)**

Replace:

```markdown
- **Faster escalation:** All thresholds shift down ~40% at night. Level 4 messaging is blunt. *"It's 2:17am. Go to bed."*
```

With:

```markdown
- **Faster escalation:** All thresholds shift down ~40% at night. Level 4 messaging references sleep research and cites evidence directly.
```

- [ ] **Step 5: Fix "pathological" language (line 37)**

Replace:

```markdown
A 2-hour session at 2pm is productive. A 2-hour session at 2am is pathological. Pace Control knows the difference.
```

With:

```markdown
A 2-hour session at 2pm and a 2-hour session at 2am have measurably different outcomes. Pace Control adjusts accordingly.
```

- [ ] **Step 6: Fix comparison table — "Your error rate is increasing" (line 90)**

Replace:

```markdown
| **Evidence** | "Time's up" | "Your error rate is increasing" |
```

With:

```markdown
| **Evidence** | "Time's up" | Research-backed session data |
```

- [ ] **Step 7: Fix micro-loop "30 seconds" (line 64)**

Replace:

```markdown
> *"SESSION: 3h 25m | 52 prompts — Still here. When you finish what you're working on, say 'wrap up' and I'll save everything in 30 seconds."*
```

With:

```markdown
> *"SESSION: 3h 25m | 52 prompts — Still here. When you finish what you're working on, say 'wrap up' and I'll save everything."*
```

- [ ] **Step 8: Fix GAID citation (line 240)**

Replace:

```markdown
- **Generative AI Addiction Disorder (2025).** A [ScienceDirect paper](https://www.sciencedirect.com/science/article/abs/pii/S1876201825001194) formally defines GAID as a behavioural addiction with withdrawal symptoms including anxiety when users try to reduce AI interaction. This isn't a metaphor — it's a clinical framework.
```

With:

```markdown
- **Generative AI Addiction Disorder (2025).** A [ScienceDirect paper](https://www.sciencedirect.com/science/article/abs/pii/S1876201825001194) proposes GAID as a behavioural framework describing compulsive AI interaction patterns. This is a proposed research framework, not a validated clinical diagnosis — but the pattern it describes (difficulty disengaging from AI coding sessions) maps to behaviours many developers report.
```

- [ ] **Step 9: Fix Ericsson claim (line 241)**

Replace:

```markdown
- **Anders Ericsson** found that peak performers sustain focused work in 90-minute blocks. That's the basis for Level 0's silent period.
```

With:

```markdown
- **Anders Ericsson** observed that elite performers tend to practise in 60-90 minute sessions (Ericsson et al., 1993). This is an observational finding, not an experimentally validated optimum, but it informs Level 0's silent period as a reasonable heuristic.
```

- [ ] **Step 10: Fix Skinner claim (line 242)**

Replace:

```markdown
- **B.F. Skinner** showed that variable ratio reinforcement schedules produce the highest, most persistent response rates. The "one more prompt" loop follows this pattern exactly.
```

With:

```markdown
- **B.F. Skinner** established that variable reinforcement schedules produce persistent response rates in classic demonstrations. The "one more prompt" loop has structural similarities to this pattern, though the specific application to AI coding has not been empirically studied.
```

- [ ] **Step 11: Fix Zeigarnik claim (line 243)**

Replace:

```markdown
- **Zeigarnik Effect.** Incomplete tasks occupy working memory disproportionately. Writing down an idea (cognitive offloading) releases the hold, making it safe to stop.
```

With:

```markdown
- **Cognitive offloading.** Formulating specific plans for incomplete tasks reduces their cognitive interference (Masicampo & Baumeister, 2011). The Safe-Save Protocol is designed around this finding — saving context with specific next steps releases the hold that unfinished work exerts.
```

- [ ] **Step 12: Add Data Practices section**

After the "Known Limitations" section (after line 228), add:

```markdown
## Data Practices

Pace Control runs entirely on your machine. No data is sent anywhere. All state files are stored in `~/.claude/` as plain JSON and markdown. There is no server, no analytics, no telemetry. You can delete all data at any time with `rm ~/.claude/pace-control-*`.
```

- [ ] **Step 13: Commit**

```bash
git add README.md
git commit -m "fix: README — drop Anthropic jab, fix unsupported claims, add Data Practices, honest research framing"
```

---

### Task 10: Create Uninstall Script and Feedback Template

**Files:**
- Create: `scripts/uninstall.sh`
- Create: `.github/ISSUE_TEMPLATE/feedback.md`

- [ ] **Step 1: Create uninstall script**

```bash
#!/bin/bash
# Pace Control — Uninstall
# Removes all pace-control state files from ~/.claude/

CLAUDE_DIR="${HOME}/.claude"

echo "Removing Pace Control state files..."
rm -f "$CLAUDE_DIR"/pace-control-state.*.json
rm -f "$CLAUDE_DIR"/pace-control-state.json
rm -f "$CLAUDE_DIR"/pace-control-config.json
rm -f "$CLAUDE_DIR"/pace-control-history.json
rm -f "$CLAUDE_DIR"/pace-control-resume.md
rm -f "$CLAUDE_DIR"/pace-control-ideas.md
echo "Done. State files removed."
echo ""
echo "To complete uninstall:"
echo "1. Remove SessionStart and PostToolUse hooks from ~/.claude/settings.json"
echo "2. Optionally remove the repo: rm -rf $(dirname "$(dirname "$(realpath "$0")")")"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/uninstall.sh
```

- [ ] **Step 3: Create feedback issue template**

Create `.github/ISSUE_TEMPLATE/feedback.md`:

```markdown
---
name: Feedback
about: Share your experience with Pace Control — what worked, what didn't, what made you uncomfortable
title: "[Feedback] "
labels: feedback
assignees: ''
---

**How long have you been using Pace Control?**

**What worked well?**

**What didn't work or felt wrong?**

**Did any messaging make you uncomfortable?**
(This is important — if anything felt patronising, shaming, or triggering, we want to know.)

**Would you recommend it to a colleague?**

**Anything else?**
```

- [ ] **Step 4: Commit**

```bash
mkdir -p .github/ISSUE_TEMPLATE
git add scripts/uninstall.sh .github/ISSUE_TEMPLATE/feedback.md
git commit -m "feat: add uninstall script and feedback issue template"
```

---

### Task 11: Final Integration Verification

- [ ] **Step 1: Run full test suite**

Run: `bash scripts/test-output.sh`
Expected: All pass (50+ assertions)

- [ ] **Step 2: Verify no uncited claims remain**

Run: `grep -n "2-3x\|slot machine\|go to bed\|good flow" scripts/session-tracker.sh scripts/session-start.sh`
Expected: Zero matches

- [ ] **Step 3: Verify no "MANDATORY" remains**

Run: `grep -n "MANDATORY" scripts/session-tracker.sh`
Expected: Zero matches

- [ ] **Step 4: Verify date compatibility**

Run: `grep -n "%-H\|%-I" scripts/session-tracker.sh scripts/session-start.sh`
Expected: Zero matches (all replaced with portable alternatives)

- [ ] **Step 5: Verify file permissions are set**

Run: `grep -n "umask 077" scripts/session-tracker.sh scripts/session-start.sh`
Expected: One match per file

- [ ] **Step 6: Verify README claims**

Run: `grep -n "clinical framework\|Anthropic won't build\|go to bed\|2-3x\|pathological" README.md`
Expected: Zero matches

- [ ] **Step 7: Manual smoke test — start a fresh session**

```bash
# In a temp home dir:
TEMP_HOME=$(mktemp -d)
HOME="$TEMP_HOME" bash scripts/session-start.sh
```

Expected: First-run welcome mentioning /pace-check and /wrap-up

- [ ] **Step 8: Tag release**

```bash
git tag -a v0.4.0 -m "Evidence-validated improvements: fix unsupported claims, security hardening, accessibility, transparency"
```
