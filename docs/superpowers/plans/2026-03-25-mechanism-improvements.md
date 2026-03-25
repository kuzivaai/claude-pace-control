# Mechanism Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Pace Control's mechanism real — measure outcomes, make saves mechanical, add focus mode, track absolute time, distinguish session types, and drop the oversold positioning.

**Architecture:** All changes are in `scripts/pace_control.py` (the single Python module), `README.md`, skill files, and tests. No new dependencies. The module already handles all state, config, and output — we extend it.

**Tech Stack:** Python 3 stdlib, bash, markdown

**Baseline:** 60/60 tests passing. All changes must maintain green tests.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `scripts/pace_control.py` | Modify | All 6 features: outcome tracking, mechanical wrap-up, focus mode, absolute time, session types, config |
| `scripts/test-output.sh` | Modify | New tests for all features |
| `skills/wrap-up/SKILL.md` | Modify | Update to reflect mechanical save |
| `README.md` | Modify | Drop "off-switch" positioning, document new features |

---

### Task 1: Outcome Measurement

Log whether users who see L3+ actually stop within N prompts. Track `/wrap-up` usage. This is the foundation — without data, nothing else can be validated.

**Files:**
- Modify: `scripts/pace_control.py`
- Modify: `scripts/test-output.sh`

- [ ] **Step 1: Add outcome fields to history schema**

In `pace_control.py`, modify `log_completed_session()` to include outcome data. Find the function and add these fields to the session object:

```python
# In log_completed_session(), add to the session dict:
"nudgesShown": state.get("nudgesShown", 0),       # how many L3+ nudges were shown
"promptsAfterL3": state.get("promptsAfterL3", 0), # prompts after first L3 fire
"wrappedUp": state.get("wrappedUp", False),        # did user invoke /wrap-up?
"maxLevel": state.get("windDownLevel", 0),         # highest level reached
```

- [ ] **Step 2: Track nudge count and prompts-after-L3 in state**

Add to `default_state` in `load_state()`:

```python
"nudgesShown": 0,
"promptsAfterL3": 0,
"wrappedUp": False,
```

In `cmd_track()`, after L3+ first-fire or micro-loop nudge is output, increment `state["nudgesShown"]`. After `windDownLevel >= 3`, increment `state["promptsAfterL3"]` on every prompt.

- [ ] **Step 3: Add wrap-up detection**

In `cmd_track()`, add a new command: `python3 pace_control.py wrapped`. When `/wrap-up` skill completes, the skill instructs Claude to run this. It sets `state["wrappedUp"] = True` and logs the session.

Add to `main()`:

```python
elif command == "wrapped":
    cmd_wrapped()
```

```python
def cmd_wrapped(now=None):
    """Mark current session as wrapped up."""
    if now is None:
        now = int(time.time())
    os.makedirs(CLAUDE_DIR, mode=0o700, exist_ok=True)
    state = load_state()
    state["wrappedUp"] = True
    save_state(state)
```

- [ ] **Step 4: Add outcome summary to weekly stats**

In `weekly_stats()`, add:

```python
# Count sessions with outcome data
sessions_with_l3 = [s for s in recent if s.get("maxLevel", 0) >= 3]
wrapped_count = sum(1 for s in sessions_with_l3 if s.get("wrappedUp", False))
if sessions_with_l3:
    wrap_rate = f"{wrapped_count}/{len(sessions_with_l3)} sessions used /wrap-up after L3."
```

Surface this in the weekly context on session start if there are enough data points (5+).

- [ ] **Step 5: Write tests**

Add to `test-output.sh`:

```bash
# --- Outcome: nudgesShown increments after L3 micro-nudge ---
cleanup
setup_day_config
setup_state 200 45 false 0 45 3
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
ACTUAL_STATE=$(find_tracker_state)
NS=$(python3 -c "import json; print(json.load(open('$ACTUAL_STATE')).get('nudgesShown', -1))" 2>/dev/null)
if [ "$NS" -ge 1 ] 2>/dev/null; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\nFAIL: Outcome — nudgesShown not incremented (got: $NS)"
fi
```

- [ ] **Step 6: Run tests, fix, commit**

```bash
bash scripts/test-output.sh
git add scripts/pace_control.py scripts/test-output.sh
git commit -m "feat: outcome measurement — track nudges shown, prompts after L3, wrap-up usage"
```

---

### Task 2: Mechanical /wrap-up

Have the Python module handle git commit and resume writing directly. Claude provides semantic context, but the mechanical parts don't depend on Claude's compliance.

**Files:**
- Modify: `scripts/pace_control.py`
- Modify: `skills/wrap-up/SKILL.md`
- Modify: `scripts/test-output.sh`

- [ ] **Step 1: Add `cmd_save` function to pace_control.py**

New command: `python3 pace_control.py save "description of what was being worked on"`

```python
def cmd_save(now=None, description=""):
    """Mechanical save: git commit + resume file + mark wrapped up."""
    if now is None:
        now = int(time.time())
    os.makedirs(CLAUDE_DIR, mode=0o700, exist_ok=True)

    results = []

    # 1. Git commit (if there are changes)
    try:
        status = subprocess.run(["git", "status", "--porcelain"],
                                capture_output=True, text=True, timeout=10)
        if status.stdout.strip():
            # Stage tracked files only (not untracked)
            subprocess.run(["git", "add", "-u"], capture_output=True, timeout=10)
            msg = f"wip: pace-control checkpoint — {description[:100]}" if description else "wip: pace-control checkpoint"
            commit = subprocess.run(["git", "commit", "-m", msg],
                                    capture_output=True, text=True, timeout=10)
            if commit.returncode == 0:
                # Get commit hash
                hash_result = subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                                             capture_output=True, text=True, timeout=5)
                results.append(f"Committed: {hash_result.stdout.strip()}")
            else:
                results.append("Nothing to commit (working tree clean)")
        else:
            results.append("Nothing to commit (working tree clean)")
    except Exception:
        results.append("Git not available or not in a repo")

    # 2. Write resume file
    stub = generate_resume_stub(now)
    if description:
        stub += f"\n### What We Were Working On\n{description}\n"
    fd, tmp = tempfile.mkstemp(dir=CLAUDE_DIR, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(stub)
        os.chmod(tmp, 0o600)
        os.rename(tmp, RESUME_FILE)
        results.append(f"Context saved: {RESUME_FILE}")
    except OSError:
        results.append("Failed to save resume file")

    # 3. Mark session as wrapped up
    state = load_state()
    state["wrappedUp"] = True
    save_state(state)
    results.append("Session marked as wrapped up")

    # Output results for Claude to relay
    print("\n".join(results))
```

- [ ] **Step 2: Add to main()**

```python
elif command == "save":
    desc = " ".join(sys.argv[2:]) if len(sys.argv) > 2 else ""
    cmd_save(description=desc)
```

- [ ] **Step 3: Update /wrap-up skill to use mechanical save**

Rewrite `skills/wrap-up/SKILL.md` to instruct Claude to:
1. Ask the user what they were working on (one sentence)
2. Ask for any ideas to capture
3. Run: `python3 ~/.claude/plugins/pace-control/scripts/pace_control.py save "user's description"`
4. If the user has ideas, append them to `~/.claude/pace-control-ideas.md`
5. Relay the results

The key change: git commit and resume writing are now done by the Python module, not by Claude following instructions.

- [ ] **Step 4: Write test**

```bash
# --- Mechanical save: cmd_save produces output ---
cleanup
setup_day_config
setup_state 200 40 false
SAVE_OUTPUT=$(cd "$TEMP_HOME" && git init -q && git add -A 2>/dev/null; HOME="$TEMP_HOME" python3 "$SCRIPT_DIR/pace_control.py" save "testing save" 2>/dev/null)
assert_output "Mechanical save — produces output" "commit\|Context saved\|working tree" "$SAVE_OUTPUT"
```

- [ ] **Step 5: Run tests, fix, commit**

```bash
bash scripts/test-output.sh
git add scripts/pace_control.py skills/wrap-up/SKILL.md scripts/test-output.sh
git commit -m "feat: mechanical /wrap-up — git commit and resume handled by Python module"
```

---

### Task 3: Focus Mode Override

Let users say "focus 2h" to defer escalation. Addresses the main uninstall reason: being nudged during genuine productive flow.

**Files:**
- Modify: `scripts/pace_control.py`
- Modify: `scripts/test-output.sh`
- Modify: `README.md`

- [ ] **Step 1: Add focus mode to state**

Add to `default_state`:

```python
"focusUntil": 0,  # Unix timestamp — suppress nudges until this time
```

- [ ] **Step 2: Add `cmd_focus` function**

New command: `python3 pace_control.py focus 120` (minutes)

```python
def cmd_focus(now=None, minutes=120):
    """Defer escalation for N minutes."""
    if now is None:
        now = int(time.time())
    os.makedirs(CLAUDE_DIR, mode=0o700, exist_ok=True)
    minutes = max(min(safe_int(minutes, 120), 480), 15)  # 15 min to 8 hours
    state = load_state()
    state["focusUntil"] = now + (minutes * 60)
    save_state(state)
    h, m = format_duration(minutes)
    print(f"Focus mode: nudges suppressed for {h}h {m}m. Session timer still runs.")
```

- [ ] **Step 3: Check focus mode in cmd_track**

In `cmd_track()`, after calculating elapsed_minutes and before the level checks, add:

```python
# Focus mode: suppress all nudges until focusUntil
if state.get("focusUntil", 0) > now:
    save_state(state)
    return  # exit silently — timer runs but no output
```

When focus expires, normal escalation resumes based on actual elapsed time.

- [ ] **Step 4: Add to main()**

```python
elif command == "focus":
    mins = safe_int(sys.argv[2] if len(sys.argv) > 2 else "120", 120)
    cmd_focus(minutes=mins)
```

- [ ] **Step 5: Write tests**

```bash
# --- Focus mode: suppresses output ---
cleanup
setup_day_config
# Set focus mode 60 min into the future
FOCUS_UNTIL=$((NOW + 3600))
echo "{\"sessionStart\":$((NOW - 6000)),\"totalMinutes\":100,\"promptCount\":15,\"lastCheck\":$((NOW - 30)),\"windDownPromptCount\":0,\"nextNudgeAt\":0,\"windDownLevel\":0,\"focusUntil\":${FOCUS_UNTIL}}" > "$STATE_FILE"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_empty "Focus mode — suppresses L1 output" "$OUTPUT"

# --- Focus mode expired: resumes normally ---
cleanup
setup_day_config
FOCUS_EXPIRED=$((NOW - 60))
echo "{\"sessionStart\":$((NOW - 6000)),\"totalMinutes\":100,\"promptCount\":15,\"lastCheck\":$((NOW - 30)),\"windDownPromptCount\":0,\"nextNudgeAt\":0,\"windDownLevel\":0,\"focusUntil\":${FOCUS_EXPIRED}}" > "$STATE_FILE"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_output "Focus mode expired — L1 resumes" "pace-control" "$OUTPUT"
```

- [ ] **Step 6: Run tests, fix, commit**

```bash
bash scripts/test-output.sh
git add scripts/pace_control.py scripts/test-output.sh
git commit -m "feat: focus mode — defer nudges with 'focus 2h', timer still runs"
```

---

### Task 4: Absolute Clock Time Tracking

2am matters independently of session duration. A session that starts at 1am should escalate faster than one that starts at 2pm, even if both are 30 minutes in.

**Files:**
- Modify: `scripts/pace_control.py`
- Modify: `scripts/test-output.sh`

- [ ] **Step 1: Add absolute-time escalation**

In `cmd_track()`, after computing the normal level from elapsed time, add an absolute-time modifier:

```python
# Absolute clock time escalation
# Between midnight and 5am, enforce minimum L1 regardless of session duration
if current_hour >= 0 and current_hour < 5 and level == 0 and elapsed_minutes >= 15:
    level = 1  # Surface at least L1 after 15 min between midnight-5am
```

This is conservative: it only boosts L0 to L1 after 15 minutes, only between midnight and 5am. It doesn't override focus mode (that check happens first).

- [ ] **Step 2: Add time-of-night urgency to L3/L4 messaging**

In the L3/L4 night messaging, if the current hour is between 1am and 5am, add the actual time prominently:

```python
if is_late and current_hour >= 1 and current_hour < 5:
    lines.append(f"It is {timestr}.")
```

This is not a nudge — it's just surfacing a fact the user may have lost track of.

- [ ] **Step 3: Write tests**

```bash
# --- Absolute time: midnight-5am forces minimum L1 after 15 min ---
cleanup
# Force night mode AND set hour to 2am
echo '{"nightStartHour":0,"nightEndHour":23}' > "$CONFIG_FILE"
# Session only 20 min old (normally L0 at night = silent until 45m)
setup_state 20 5
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
# At 2am with nightStartHour=0,nightEndHour=23, the 20-min session would be L0
# But absolute time check should force L1 if hour is 0-4
# Note: this test depends on system clock hour. Add a comment about this.
# For reliable testing, we'd need to inject the hour. Skip if system hour is not 0-4.
SYSTEM_HOUR=$(date +%H | sed 's/^0//')
if [ "$SYSTEM_HOUR" -ge 0 ] && [ "$SYSTEM_HOUR" -lt 5 ]; then
  assert_output "Absolute time — L1 forced at 2am" "pace-control" "$OUTPUT"
else
  PASS=$((PASS + 1))  # Skip — can only test during midnight-5am
fi
```

To make this testable, add an optional `_hour_override` parameter to `cmd_track()`. When set, it replaces `current_hour`. Use it in the test to force hour=2. Two-line change in the function signature + one conditional.

- [ ] **Step 4: Run tests, fix, commit**

```bash
bash scripts/test-output.sh
git add scripts/pace_control.py scripts/test-output.sh
git commit -m "feat: absolute clock time — midnight-5am forces minimum L1 after 15 min"
```

---

### Task 5: Session Type Awareness

Let users (or Claude) tag what kind of work is happening. Different work types get different thresholds.

**Files:**
- Modify: `scripts/pace_control.py`
- Modify: `scripts/test-output.sh`

- [ ] **Step 1: Add session type to state and config**

Add to `default_state`:

```python
"sessionType": "",  # "incident", "shipping", "exploring", or "" (default)
```

Add to config defaults:

```python
"incidentMultiplier": 1.5,  # during incidents, thresholds are 1.5x
```

- [ ] **Step 2: Add `cmd_mode` function for setting session type**

New command: `python3 pace_control.py type incident`

```python
VALID_SESSION_TYPES = {"incident": 1.5, "shipping": 1.25, "exploring": 0.85, "": 1.0}

def cmd_type(session_type=""):
    """Set the session type for threshold adjustment."""
    os.makedirs(CLAUDE_DIR, mode=0o700, exist_ok=True)
    session_type = session_type.lower().strip()
    if session_type not in VALID_SESSION_TYPES:
        session_type = ""
    state = load_state()
    state["sessionType"] = session_type
    save_state(state)
    if session_type:
        mult = VALID_SESSION_TYPES[session_type]
        direction = "extended" if mult > 1 else "shortened"
        print(f"Session type: {session_type}. Thresholds {direction} by {int((mult - 1) * 100)}%.")
    else:
        print("Session type cleared. Default thresholds restored.")
```

- [ ] **Step 3: Apply session type multiplier to thresholds**

In `cmd_track()`, after `compute_thresholds()`, apply the multiplier:

```python
session_type = state.get("sessionType", "")
type_mult = VALID_SESSION_TYPES.get(session_type, 1.0)
if type_mult != 1.0:
    tl1 = int(tl1 * type_mult)
    tl2 = int(tl2 * type_mult)
    tl3 = int(tl3 * type_mult)
    tl4 = int(tl4 * type_mult)
```

- [ ] **Step 4: Add to main()**

```python
elif command == "type":
    stype = sys.argv[2] if len(sys.argv) > 2 else ""
    cmd_type(stype)
```

- [ ] **Step 5: Write test**

```bash
# --- Session type: incident extends thresholds ---
cleanup
setup_day_config
# Normal L1 at 90m. With incident (1.5x), L1 at 135m. So 100m should be L0.
echo "{\"sessionStart\":$((NOW - 6000)),\"totalMinutes\":100,\"promptCount\":15,\"lastCheck\":$((NOW - 30)),\"windDownPromptCount\":0,\"nextNudgeAt\":0,\"windDownLevel\":0,\"sessionType\":\"incident\"}" > "$STATE_FILE"
OUTPUT=$(bash "$TRACKER" 2>/dev/null)
assert_empty "Session type incident — L0 at 100m (threshold 135m)" "$OUTPUT"
```

- [ ] **Step 6: Run tests, fix, commit**

```bash
bash scripts/test-output.sh
git add scripts/pace_control.py scripts/test-output.sh
git commit -m "feat: session types — incident/shipping/exploring adjust thresholds"
```

---

### Task 6: Drop "Off-Switch" Positioning + Document New Features

Update README to be honest about what the tool is, and document all new capabilities.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Fix tagline**

Replace: `**The off-switch for Claude Code.**`
With: `**Session awareness for Claude Code.**`

- [ ] **Step 2: Fix "How It Works" opening**

Replace: `Pace Control uses Claude Code's hook system to inject context into Claude's responses. No daemon, no background process, no server. Just a Python module, two bash wrappers, and Claude's own helpfulness.`

With: `Pace Control tracks your Claude Code session and surfaces time-awareness inside Claude's responses. When you stop, it saves your work mechanically — git commit, context file, ideas — so the next session picks up where you left off. A Python module with two bash wrappers, no server, no telemetry.`

- [ ] **Step 3: Add new features to README**

After the Messaging Verbosity section, add:

```markdown
### Focus Mode

If you're in genuine flow and don't want nudges:

```bash
python3 ~/.claude/plugins/pace-control/scripts/pace_control.py focus 120
```

Suppresses all nudges for 2 hours. Session timer still runs. When focus expires, normal escalation resumes based on actual elapsed time. Range: 15 minutes to 8 hours.

### Session Types

Different work gets different thresholds:

```bash
python3 ~/.claude/plugins/pace-control/scripts/pace_control.py type incident
```

| Type | Threshold Adjustment | Use When |
|------|---------------------|----------|
| `incident` | +50% (longer before nudges) | Production outage, urgent fix |
| `shipping` | +25% | Deadline crunch, final push |
| `exploring` | -15% (earlier nudges) | Learning, side project, exploration |
| (blank) | Default | Normal work |

### Outcome Tracking

Pace Control logs whether its nudges actually work:
- How many L3+ nudges were shown per session
- How many prompts happened after the first L3 nudge
- Whether the session ended with `/wrap-up`

Surface with `/pace-check` or in the weekly stats on session start. This data helps you (and us) understand whether the tool is actually useful.
```

- [ ] **Step 4: Fix the comparison table**

The "Dismissal" row currently implies you can't ignore Pace Control. Add honesty:

Replace: `| **Dismissal** | One click to ignore | Woven into Claude's response |`
With: `| **Dismissal** | One click to ignore | In Claude's response (still ignorable — you say "keep going") |`

- [ ] **Step 5: Fix "Key insight"**

Replace: `**Key insight:** The barrier to stopping isn't willpower. It's anxiety about losing progress. Remove the anxiety, and people stop naturally.`

With: `**Key insight:** The barrier to stopping is often anxiety about losing progress. The mechanical save — git commit, context file, ideas — removes that barrier. Whether that actually changes behaviour is something we're measuring.`

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: honest positioning — session awareness tool, not an off-switch"
```

---

### Task 7: Integration Test + Final Verification

- [ ] **Step 1: Run full test suite**

```bash
bash scripts/test-output.sh
```

Expected: All pass (60+ original + ~8 new)

- [ ] **Step 2: Verify no regressions**

```bash
python3 -c "import py_compile; py_compile.compile('scripts/pace_control.py', doraise=True)"
bash -n scripts/session-tracker.sh
bash -n scripts/session-start.sh
```

- [ ] **Step 3: Smoke test new features**

```bash
TEMP_HOME=$(mktemp -d)
mkdir -p "$TEMP_HOME/.claude"
echo '{"nightStartHour":0,"nightEndHour":0}' > "$TEMP_HOME/.claude/pace-control-config.json"

# Test focus mode
HOME="$TEMP_HOME" python3 scripts/pace_control.py focus 60

# Test session type
HOME="$TEMP_HOME" python3 scripts/pace_control.py type incident

# Test mechanical save (needs git repo)
cd "$TEMP_HOME" && git init -q && echo "test" > test.txt && git add .
HOME="$TEMP_HOME" python3 /home/mkuziva/pace-control/scripts/pace_control.py save "testing mechanical save"

rm -rf "$TEMP_HOME"
```

- [ ] **Step 4: Final commit and tag**

```bash
git tag -a v0.5.0 -m "v0.5.0: outcome tracking, mechanical save, focus mode, session types, absolute time, honest positioning"
```
