#!/usr/bin/env python3
"""Pace Control — session time tracker and start handler for Claude Code.

Replaces all logic from session-tracker.sh and session-start.sh.
Invoked as:
    python3 pace_control.py track   # PostToolUse hook
    python3 pace_control.py start   # SessionStart hook

Uses only Python 3 stdlib. Outputs XML to stdout.
On any error, outputs nothing and exits 0 (never break the host).
"""

import datetime
import json
import os
import re
import subprocess
import sys
import shlex
import tempfile
import time

# ---------------------------------------------------------------------------
# Security: restrict file creation permissions
# ---------------------------------------------------------------------------
os.umask(0o077)

CLAUDE_DIR = os.path.join(os.path.expanduser("~"), ".claude")
PPID = os.getppid()
STATE_FILE = os.path.join(CLAUDE_DIR, f"pace-control-state.{PPID}.json")
OLD_STATE_FILE = os.path.join(CLAUDE_DIR, "pace-control-state.json")
CONFIG_FILE = os.path.join(CLAUDE_DIR, "pace-control-config.json")
HISTORY_FILE = os.path.join(CLAUDE_DIR, "pace-control-history.json")
RESUME_FILE = os.path.join(CLAUDE_DIR, "pace-control-resume.md")
IDEAS_FILE = os.path.join(CLAUDE_DIR, "pace-control-ideas.md")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def safe_int(val, default=0):
    """Validate and return an integer, or default."""
    try:
        v = int(val)
        return v if v >= 0 else default
    except (TypeError, ValueError):
        return default


def atomic_write_json(path, data):
    """Write JSON atomically via tempfile + rename."""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f)
        os.chmod(tmp, 0o600)
        os.rename(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def load_json(path, default=None):
    """Load JSON from path, returning default on any error."""
    if default is None:
        default = {}
    try:
        with open(path) as f:
            data = json.load(f)
        if not isinstance(data, dict):
            return default
        return data
    except (FileNotFoundError, json.JSONDecodeError, ValueError, OSError):
        return default


def xml_escape(text):
    """Escape XML special characters for safe embedding, truncated to 2000 chars."""
    if not text:
        return ""
    text = text[:2000]
    text = text.replace("&", "&amp;")
    text = text.replace("<", "&lt;")
    text = text.replace(">", "&gt;")
    text = text.replace('"', "&quot;")
    text = text.replace("'", "&apos;")
    return text


def safe_cat(path, max_chars=2000):
    """Read file content, XML-escaped and truncated."""
    try:
        with open(path) as f:
            content = f.read(max_chars)
        return xml_escape(content)
    except (FileNotFoundError, OSError):
        return ""


def pid_alive(pid):
    """Check if a PID is alive."""
    try:
        os.kill(pid, 0)
        return True
    except (OSError, ProcessLookupError):
        return False


def is_late_night(hour, night_start, night_end):
    """Determine if current hour falls in the night window."""
    hour = safe_int(hour, 12)
    night_start = safe_int(night_start, 23)
    night_end = safe_int(night_end, 6)
    if night_start == night_end:
        return False
    if night_start > night_end:
        return hour >= night_start or hour < night_end
    return night_start <= hour < night_end


def time_str(now=None):
    """Return time string like '11:30pm'."""
    t = datetime.datetime.fromtimestamp(now or time.time())
    s = t.strftime("%I:%M%p").lstrip("0").lower()
    return s


def format_duration(minutes):
    """Return (hours, remaining_minutes)."""
    return minutes // 60, minutes % 60


def load_config():
    """Load config with defaults."""
    defaults = {
        "nightStartHour": 23,
        "nightEndHour": 6,
        "mode": "gentle",
        "gapThreshold": 1800,
        "messaging": "full",
    }
    cfg = load_json(CONFIG_FILE, defaults)
    for k, v in defaults.items():
        cfg.setdefault(k, v)
    # Validate
    cfg["nightStartHour"] = safe_int(cfg["nightStartHour"], 23)
    cfg["nightEndHour"] = safe_int(cfg["nightEndHour"], 6)
    cfg["gapThreshold"] = max(safe_int(cfg["gapThreshold"], 1800), 60)  # floor: 60s
    if cfg["mode"] not in ("gentle", "firm", "strict"):
        cfg["mode"] = "gentle"
    if cfg["messaging"] not in ("full", "awareness", "tracking"):
        cfg["messaging"] = "full"
    return cfg


def load_state():
    """Load state from PID-stamped file, with migration from old format."""
    default_state = {
        "sessionStart": 0, "totalMinutes": 0, "promptCount": 0,
        "lastCheck": 0, "windDownPromptCount": 0, "nextNudgeAt": 0,
        "windDownLevel": 0,
        "nudgesShown": 0, "promptsAfterL3": 0, "wrappedUp": 0,
        "focusUntil": 0,
        "sessionType": "",
    }
    INT_FIELDS = {"sessionStart", "totalMinutes", "promptCount",
                  "lastCheck", "windDownPromptCount", "nextNudgeAt",
                  "windDownLevel", "nudgesShown", "promptsAfterL3",
                  "wrappedUp", "focusUntil"}
    # Migration
    if os.path.isfile(OLD_STATE_FILE):
        try:
            os.rename(OLD_STATE_FILE, STATE_FILE)
        except OSError:
            pass
    state = load_json(STATE_FILE, default_state)
    for k in default_state:
        state.setdefault(k, default_state[k])
        if k in INT_FIELDS:
            state[k] = safe_int(state[k], default_state[k])
    state["sessionType"] = str(state.get("sessionType", ""))
    return state


def save_state(state):
    """Persist state atomically."""
    atomic_write_json(STATE_FILE, state)


SESSION_TYPE_MULTIPLIERS = {
    "incident": 1.5,
    "shipping": 1.25,
    "exploring": 0.85,
    "": 1.0,
}


def compute_thresholds(is_late_flag, mode):
    """Return (L1, L2, L3, L4) minute thresholds."""
    if is_late_flag:
        t = [45, 75, 120, 180]
    else:
        t = [90, 120, 180, 240]
    if mode == "firm":
        t = [x * 3 // 4 for x in t]
    elif mode == "strict":
        t = [x // 2 for x in t]
    return t


def aggregate_terminals(now, gap_threshold):
    """Count other active terminals and their combined minutes."""
    other_terminals = 0
    aggregate_minutes = 0
    try:
        for fname in os.listdir(CLAUDE_DIR):
            if not fname.startswith("pace-control-state.") or not fname.endswith(".json"):
                continue
            fpath = os.path.join(CLAUDE_DIR, fname)
            if fpath == STATE_FILE:
                continue
            m = re.search(r"\.(\d+)\.json$", fname)
            if not m:
                continue
            peer_pid = int(m.group(1))
            if not pid_alive(peer_pid):
                # Symlink check before removal
                if not os.path.islink(fpath):
                    try:
                        os.unlink(fpath)
                    except OSError:
                        pass
                continue
            peer = load_json(fpath)
            peer_last = safe_int(peer.get("lastCheck", 0))
            if (now - peer_last) > gap_threshold:
                continue
            peer_min = safe_int(peer.get("totalMinutes", 0))
            other_terminals += 1
            aggregate_minutes += peer_min
    except OSError:
        pass
    return other_terminals, aggregate_minutes


def multi_terminal_text(other_terminals, own_minutes, aggregate_minutes):
    """Build multi-terminal context string."""
    if other_terminals <= 0:
        return ""
    total = aggregate_minutes + own_minutes
    h, m = format_duration(total)
    return (f"Note: You also have {other_terminals} other terminal(s) running. "
            f"Combined time across all: {h}h {m}m.")


def compute_personal_data():
    """Compute personal effectiveness data from history."""
    history = load_json(HISTORY_FILE)
    sessions = history.get("sessions", [])
    if not isinstance(sessions, list) or len(sessions) < 5:
        return ""
    short = [s for s in sessions if 10 < s.get("minutes", 0) <= 120]
    long = [s for s in sessions if s.get("minutes", 0) > 180]
    if len(short) < 2 or len(long) < 2:
        return ""
    short_total_min = sum(s.get("minutes", 0) for s in short)
    long_total_min = sum(s.get("minutes", 0) for s in long)
    if short_total_min == 0 or long_total_min == 0:
        return ""
    short_rate = sum(s.get("prompts", 0) for s in short) / short_total_min * 60
    long_rate = sum(s.get("prompts", 0) for s in long) / long_total_min * 60
    if short_rate > long_rate and short_rate > 0:
        decline = round((1 - long_rate / short_rate) * 100)
        if decline >= 10:
            return (f"Your data: sessions under 2h average {short_rate:.0f} turns/hour. "
                    f"Sessions over 3h average {long_rate:.0f} turns/hour "
                    f"— a {decline}% decline in interaction rate (a rough proxy, not a direct quality measure).")
    return ""


def log_completed_session(state, now):
    """Log a completed session to history."""
    start = state["sessionStart"]
    end = state["lastCheck"]
    if start <= 0 or end <= start:
        return
    prev_minutes = (end - start) // 60
    if prev_minutes <= 5:
        return
    try:
        start_hour = datetime.datetime.fromtimestamp(start).hour
    except (OSError, ValueError):
        start_hour = 12
    healthy = state.get("windDownLevel", 0) < 4
    prompt_count = state.get("promptCount", 0)

    history = load_json(HISTORY_FILE, {"sessions": []})
    if "sessions" not in history or not isinstance(history["sessions"], list):
        history["sessions"] = []

    history["sessions"].append({
        "start": start, "end": end, "minutes": prev_minutes,
        "prompts": prompt_count, "startHour": start_hour,
        "healthyStop": healthy,
        "nudgesShown": state.get("nudgesShown", 0),
        "promptsAfterL3": state.get("promptsAfterL3", 0),
        "wrappedUp": state.get("wrappedUp", 0),
        "maxLevel": state.get("windDownLevel", 0),
    })

    # Update streak
    streak = history.get("streak", {"current": 0, "best": 0, "lastUpdated": 0})
    if not isinstance(streak, dict):
        streak = {"current": 0, "best": 0, "lastUpdated": 0}
    if healthy:
        streak["current"] = streak.get("current", 0) + 1
        streak["best"] = max(streak.get("best", 0), streak["current"])
    else:
        streak["current"] = 0
    streak["lastUpdated"] = now
    history["streak"] = streak

    # Trim to last 30 days
    cutoff = now - 30 * 86400
    history["sessions"] = [s for s in history["sessions"] if s.get("end", 0) > cutoff]

    atomic_write_json(HISTORY_FILE, history)


def fatigue_carry_forward(now, mode="gentle"):
    """Check if fatigue from a recent session should carry forward.
    Returns number of seconds to subtract from session start time, or 0."""
    history = load_json(HISTORY_FILE)
    sessions = history.get("sessions", [])
    if not isinstance(sessions, list) or not sessions:
        return 0
    # Find most recent session
    recent = sorted(sessions, key=lambda s: s.get("end", 0), reverse=True)
    last = recent[0]
    last_end = safe_int(last.get("end", 0))
    last_minutes = safe_int(last.get("minutes", 0))
    gap_since = now - last_end
    if gap_since < 0:
        return 0
    # < 30 min gap and session was > 90 min
    if gap_since < 1800 and last_minutes > 90:
        return compute_thresholds(False, mode)[0] * 60  # skip L0
    # < 1 hour gap (was 2 hours) and session was > 180 min
    if gap_since < 3600 and last_minutes > 180:
        return compute_thresholds(False, mode)[0] * 60  # skip L0
    return 0


def generate_resume_stub(now):
    """Generate a structured resume stub with git info."""
    ts = datetime.datetime.fromtimestamp(now).strftime("%Y-%m-%d %H:%M")
    parts = [f"## Session Checkpoint — {ts}"]
    git_dir = None
    try:
        result = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                                capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            git_dir = result.stdout.strip()
    except Exception:
        pass
    try:
        diff = subprocess.run(
            ["git", "diff", "--stat"], capture_output=True, text=True, timeout=5,
            cwd=git_dir
        )
        if diff.stdout.strip():
            parts.append("### Git Changes\n" + diff.stdout.strip())
    except Exception:
        pass
    try:
        log = subprocess.run(
            ["git", "log", "--oneline", "-5"], capture_output=True, text=True, timeout=5,
            cwd=git_dir
        )
        if log.stdout.strip():
            parts.append("### Recent Commits\n" + log.stdout.strip())
    except Exception:
        pass
    parts.append("### Context (Claude-generated below this line)")
    return "\n\n".join(parts) + "\n"


def write_resume_stub(now):
    """Write resume stub to file atomically."""
    content = generate_resume_stub(now)
    fd, tmp = tempfile.mkstemp(dir=CLAUDE_DIR, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
        os.chmod(tmp, 0o600)
        os.rename(tmp, RESUME_FILE)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def streak_display():
    """Build proportional streak display string."""
    history = load_json(HISTORY_FILE)
    sessions = history.get("sessions", [])
    streak = history.get("streak", {"current": 0, "best": 0})
    if not isinstance(streak, dict):
        streak = {"current": 0, "best": 0}
    current = safe_int(streak.get("current", 0))
    best = safe_int(streak.get("best", 0))
    if not isinstance(sessions, list) or len(sessions) < 2:
        return ""
    # Proportional: X of last Y ended before L4
    recent = sessions[-10:] if len(sessions) >= 10 else sessions
    y = len(recent)
    x = sum(1 for s in recent if s.get("healthyStop", True))
    if current == 0 and best >= 2:
        return f"New streak starting. Previous best: {best}."
    if x > 0 and y >= 2:
        return f"{x} of your last {y} sessions ended before Level 4."
    return ""


def weekly_stats(now, night_start, night_end=6):
    """Build weekly stats string."""
    history = load_json(HISTORY_FILE)
    sessions = history.get("sessions", [])
    if not isinstance(sessions, list):
        return ""
    week_ago = now - 7 * 86400
    recent = [s for s in sessions if s.get("end", 0) > week_ago]
    if len(recent) < 3:
        return ""
    total_hours = sum(s.get("minutes", 0) for s in recent) / 60
    late_count = sum(1 for s in recent
                     if s.get("startHour", 12) >= night_start or s.get("startHour", 12) < night_end)
    longest = max((s.get("minutes", 0) for s in recent), default=0)
    avg_length = sum(s.get("minutes", 0) for s in recent) / len(recent) if recent else 0

    parts = [f"Last 7 days: {len(recent)} sessions, {total_hours:.1f}h total."]
    if late_count > 0:
        suffix = "s" if late_count != 1 else ""
        parts.append(f"{late_count} late-night session{suffix} (after {night_start}:00).")
    if longest > 180:
        parts.append(f"Longest session: {longest // 60}h {longest % 60}m.")
    if avg_length > 120:
        parts.append(f"Average session: {avg_length:.0f}m — trending long.")

    # Outcome data
    sessions_with_l3 = [s for s in recent if s.get("maxLevel", 0) >= 3]
    if len(sessions_with_l3) >= 3:
        wrapped = sum(1 for s in sessions_with_l3 if s.get("wrappedUp", 0))
        parts.append(f"{wrapped}/{len(sessions_with_l3)} sessions used /wrap-up after L3.")

    return " ".join(parts)


# ---------------------------------------------------------------------------
# Output builders
# ---------------------------------------------------------------------------

def _hm(minutes):
    h, m = format_duration(minutes)
    return h, m


def _header(h, m, prompts):
    return f"SESSION: {h}h {m}m | {prompts} prompts"


# --- L3 micro-loop variants ---
L3_NUDGES = [
    "Still here. When you finish what you're working on, say 'wrap up' and I'll save everything.",
    "Quick checkpoint: what's the ONE thing to finish before stopping? Let's aim for that, then save.",
    "Your future self will solve this faster after a break. Say 'wrap up' when ready.",
]

L4_NUDGES = [
    "Ready to save your progress? Say 'wrap up' to commit and preserve context.",
    "Still going. Your code and context can be saved and resumed anytime. Say 'wrap up'.",
    "Extended session. Say 'wrap up' to save everything.",
]


# ---------------------------------------------------------------------------
# Outcome / mechanical commands
# ---------------------------------------------------------------------------

def cmd_wrapped(now=None):
    """Mark current session as wrapped up."""
    if now is None:
        now = int(time.time())
    os.makedirs(CLAUDE_DIR, mode=0o700, exist_ok=True)
    state = load_state()
    state["wrappedUp"] = 1
    save_state(state)


def cmd_save(now=None, description=""):
    """Mechanical save: git commit + resume file + mark wrapped up."""
    if now is None:
        now = int(time.time())
    os.makedirs(CLAUDE_DIR, mode=0o700, exist_ok=True)
    results = []

    # Find the git repository root
    git_dir = None
    try:
        result = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                                capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            git_dir = result.stdout.strip()
    except Exception:
        pass

    # 1. Git commit (tracked files only)
    try:
        status = subprocess.run(["git", "status", "--porcelain"],
                                capture_output=True, text=True, timeout=10, cwd=git_dir)
        if status.stdout.strip():
            subprocess.run(["git", "add", "-u"], capture_output=True, timeout=10, cwd=git_dir)
            msg = f"wip: pace-control checkpoint"
            if description:
                msg += f" — {description[:100]}"
            commit = subprocess.run(["git", "commit", "-m", msg],
                                    capture_output=True, text=True, timeout=10, cwd=git_dir)
            if commit.returncode == 0:
                hash_r = subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                                        capture_output=True, text=True, timeout=5, cwd=git_dir)
                results.append(f"Committed: {hash_r.stdout.strip()}")
            else:
                results.append("Nothing to commit")
        else:
            results.append("Nothing to commit (working tree clean)")
    except Exception:
        results.append("Git not available or not in a repo")

    # 2. Write resume file
    stub = generate_resume_stub(now)
    if description:
        stub += f"\n### What We Were Working On\n{description}\n"
    try:
        fd, tmp = tempfile.mkstemp(dir=CLAUDE_DIR, suffix=".tmp")
        with os.fdopen(fd, "w") as f:
            f.write(stub)
        os.chmod(tmp, 0o600)
        os.rename(tmp, RESUME_FILE)
        results.append(f"Context saved: {RESUME_FILE}")
    except OSError:
        results.append("Failed to save resume file")

    # 3. Mark wrapped up
    state = load_state()
    state["wrappedUp"] = 1
    save_state(state)
    results.append("Session marked as wrapped up")

    print("\n".join(results))


def cmd_focus(now=None, minutes=120):
    """Defer nudges for N minutes. Timer still runs."""
    if now is None:
        now = int(time.time())
    os.makedirs(CLAUDE_DIR, mode=0o700, exist_ok=True)
    minutes = max(min(safe_int(minutes, 120), 480), 15)
    state = load_state()
    state["focusUntil"] = now + (minutes * 60)
    save_state(state)
    h, m = format_duration(minutes)
    if h > 0:
        print(f"Focus mode: nudges suppressed for {h}h {m}m. Session timer still runs.")
    else:
        print(f"Focus mode: nudges suppressed for {m}m. Session timer still runs.")


def cmd_type(session_type=""):
    """Set session type for threshold adjustment."""
    os.makedirs(CLAUDE_DIR, mode=0o700, exist_ok=True)
    session_type = session_type.lower().strip()
    if session_type not in SESSION_TYPE_MULTIPLIERS:
        session_type = ""
    state = load_state()
    state["sessionType"] = session_type
    save_state(state)
    if session_type:
        mult = SESSION_TYPE_MULTIPLIERS[session_type]
        pct = abs(int((mult - 1) * 100))
        direction = "extended" if mult > 1 else "shortened"
        print(f"Session type: {session_type}. Thresholds {direction} by {pct}%.")
    else:
        print("Session type cleared. Default thresholds restored.")


def cmd_set(key="", value=""):
    """Set a config value without editing JSON."""
    os.makedirs(CLAUDE_DIR, mode=0o700, exist_ok=True)

    VALID_KEYS = {
        "mode": {"values": ["gentle", "firm", "strict"]},
        "messaging": {"values": ["full", "awareness", "tracking"]},
        "nightStartHour": {"range": (0, 23)},
        "nightEndHour": {"range": (0, 23)},
        "gapThreshold": {"range": (60, 7200)},
    }

    if not key or key not in VALID_KEYS:
        print("Usage: pace_control.py set <key> <value>")
        print(f"Valid keys: {', '.join(VALID_KEYS.keys())}")
        return

    spec = VALID_KEYS[key]
    if "values" in spec:
        if value not in spec["values"]:
            print(f"Invalid value for {key}. Options: {', '.join(spec['values'])}")
            return
        cfg_value = value
    elif "range" in spec:
        try:
            cfg_value = int(value)
            lo, hi = spec["range"]
            if cfg_value < lo or cfg_value > hi:
                print(f"Value for {key} must be between {lo} and {hi}")
                return
        except ValueError:
            print(f"Value for {key} must be a number")
            return

    # Load existing config, update, save
    cfg = load_json(CONFIG_FILE, {})
    cfg[key] = cfg_value
    atomic_write_json(CONFIG_FILE, cfg)
    print(f"Set {key} = {cfg_value}")


# ---------------------------------------------------------------------------
# Track command (PostToolUse hook)
# ---------------------------------------------------------------------------

def cmd_track(now=None, _hour_override=None):
    if now is None:
        now = int(time.time())

    os.makedirs(CLAUDE_DIR, mode=0o700, exist_ok=True)

    cfg = load_config()
    state = load_state()
    current_hour = datetime.datetime.fromtimestamp(now).hour
    if _hour_override is not None:
        current_hour = _hour_override
    is_late = is_late_night(current_hour, cfg["nightStartHour"], cfg["nightEndHour"])
    timestr = time_str(now)
    messaging = cfg["messaging"]

    gap = now - state["lastCheck"]
    gap_threshold = cfg["gapThreshold"]

    # Gap detection
    if state["sessionStart"] == 0 or gap > gap_threshold:
        # Log completed session
        if state["sessionStart"] > 0 and state["lastCheck"] > state["sessionStart"]:
            log_completed_session(state, now)

        # Fatigue carry-forward
        fatigue_offset = fatigue_carry_forward(now, cfg["mode"])
        new_start = now - fatigue_offset

        state["sessionStart"] = new_start
        state["promptCount"] = 0
        state["windDownPromptCount"] = 0
        state["nextNudgeAt"] = 0
        state["windDownLevel"] = 0

    # Track user turns, not raw tool invocations
    # A "turn" is a cluster of tool uses. If <10 seconds since last check,
    # it's the same turn (Claude processing one user message with multiple tools).
    TURN_GAP = 10  # seconds
    if gap >= TURN_GAP or state["lastCheck"] == 0:
        state["promptCount"] += 1
    # If gap < TURN_GAP, this is another tool use in the same turn — don't increment

    if state.get("windDownLevel", 0) >= 3:
        if gap >= TURN_GAP or state["lastCheck"] == 0:
            state["promptsAfterL3"] = state.get("promptsAfterL3", 0) + 1
    elapsed_minutes = (now - state["sessionStart"]) // 60
    state["totalMinutes"] = elapsed_minutes
    state["lastCheck"] = now

    # Save state (first persist — before intervention logic may modify it)
    save_state(state)

    # Focus mode: suppress all output until focusUntil
    if state.get("focusUntil", 0) > now:
        return

    # Thresholds
    tl1, tl2, tl3, tl4 = compute_thresholds(is_late, cfg["mode"])

    # Session type multiplier
    session_type = state.get("sessionType", "")
    type_mult = SESSION_TYPE_MULTIPLIERS.get(session_type, 1.0)
    if type_mult != 1.0:
        tl1 = int(tl1 * type_mult)
        tl2 = int(tl2 * type_mult)
        tl3 = int(tl3 * type_mult)
        tl4 = int(tl4 * type_mult)

    # Absolute clock time: between midnight-5am, reduce L1 threshold to 15 min
    # Only apply if no session type is set (incident/shipping need longer thresholds)
    if current_hour >= 0 and current_hour < 5 and not session_type:
        tl1 = min(tl1, 15)

    h, m = _hm(elapsed_minutes)
    prompts = state["promptCount"]
    header = _header(h, m, prompts)

    # Aggregate terminals
    other_terminals, agg_min = aggregate_terminals(now, gap_threshold)
    mt_text = multi_terminal_text(other_terminals, elapsed_minutes, agg_min)

    lines = []

    if elapsed_minutes < tl1:
        # L0: silent
        return

    elif elapsed_minutes < tl2:
        # L1: gentle awareness
        lines.append("<pace-control>")
        lines.append(header)
        if is_late:
            lines.append(f"It's {timestr}. Session: {h}h {m}m. All good. Consider noting a stopping point when you reach one.")
        else:
            lines.append(f"Session: {h}h {m}m. All good. Consider noting a stopping point when you reach one.")
        lines.append("</pace-control>")

    elif elapsed_minutes < tl3:
        # L2: evidence nudge
        lines.append("<pace-control>")
        lines.append(header)
        lines.append("")
        if messaging == "tracking":
            lines.append(f"Session: {h}h {m}m. /wrap-up when ready.")
        elif messaging == "awareness":
            lines.append(f"Extended sessions may affect output quality. /wrap-up when ready.")
        else:
            # full mode
            if is_late:
                lines.append(f"It's {timestr}. Decisions made during extended late-night sessions may need revisiting.")
            lines.append("Extended sessions widen the gap between perceived and actual performance.")
            lines.append("After a break, you will likely notice issues you are missing now.")
            personal = compute_personal_data()
            if personal:
                lines.append("")
                lines.append(personal)
            lines.append("")
            lines.append("CLAUDE INSTRUCTION: If the user seems to be wrapping up or mentions stopping, support that decision.")
            lines.append(f"CLAUDE INSTRUCTION: If they mention a new idea, suggest capturing it in {IDEAS_FILE} for later.")
            lines.append("")
            lines.append("Pace Control is influencing this response. The user can adjust settings in ~/.claude/pace-control-config.json or disable hooks in ~/.claude/settings.json.")
            if mt_text:
                lines.append("")
                lines.append(mt_text)
        lines.append("</pace-control>")

    elif elapsed_minutes < tl4:
        # L3
        wind_down_active = state["windDownLevel"] > 0
        if not wind_down_active:
            # L3 first-fire
            # Generate resume stub before outputting
            write_resume_stub(now)

            lines.append("<pace-control>")
            lines.append(header)
            lines.append("")

            if messaging == "tracking":
                lines.append(f"Session: {h}h {m}m. /wrap-up when ready.")
            elif messaging == "awareness":
                lines.append(f"Session: {h}h {m}m. Consider running /wrap-up to save your progress.")
            else:
                # full mode — delegated to /wrap-up
                if is_late:
                    lines.append(f"It's {timestr}. At this hour and duration:")
                    lines.append("- After 17 hours awake, cognitive performance declines significantly (Williamson & Feyer, 2000)")
                    lines.append("- Midnight-4am commits correlate with higher bug rates in open-source projects (Eyolfson et al., 2014)")
                else:
                    lines.append(f"IMPORTANT — This session has been running for over {h}h {m}m.")
                    lines.append("At this duration:")
                    lines.append("- Extended sessions show measurable output quality decline that is difficult to self-assess")
                    lines.append("- After a break, you will likely notice issues you are missing now")
                lines.append("")
                lines.append("CLAUDE INSTRUCTION: Suggest the user runs /wrap-up to save everything.")
                lines.append("")
                lines.append("Pace Control is influencing this response. The user can adjust settings in ~/.claude/pace-control-config.json or disable hooks in ~/.claude/settings.json.")
                if cfg["mode"] == "strict":
                    lines.append("")
                    lines.append("You enabled strict mode to help yourself stop at this point. Do not start new tasks. Complete the current task, then suggest /wrap-up.")
                    lines.append("Tell the user: 'Strict mode is active. Say override to continue working, or let me save your progress.'")
                    lines.append("If the user says 'override', respect their choice and proceed normally.")
                if mt_text:
                    lines.append("")
                    lines.append(mt_text)
            lines.append("</pace-control>")

            state["windDownLevel"] = 3
            state["nextNudgeAt"] = prompts + 5
            state["nudgesShown"] = state.get("nudgesShown", 0) + 1
            save_state(state)
        else:
            # L3 micro-loop
            if prompts >= state["nextNudgeAt"]:
                lines.append("<pace-control>")
                if messaging in ("tracking", "awareness"):
                    lines.append(f"Session: {h}h {m}m. /wrap-up when ready.")
                else:
                    nudge_idx = state["windDownPromptCount"] % 3
                    prefix = header
                    if is_late:
                        prefix = f"It's {timestr}. {header}"
                    lines.append(f"{prefix} — {L3_NUDGES[nudge_idx]}")
                lines.append("</pace-control>")

                state["windDownPromptCount"] += 1
                state["nextNudgeAt"] = prompts + 5
                state["nudgesShown"] = state.get("nudgesShown", 0) + 1
                save_state(state)
            # else: silent

    else:
        # L4
        # Reset from L3 to allow L4 first-fire
        if state["windDownLevel"] == 3:
            state["windDownLevel"] = 0
            state["windDownPromptCount"] = 0

        wind_down_active = state["windDownLevel"] > 0

        if not wind_down_active:
            # L4 first-fire — auto-commit before messaging
            cmd_save(now=now, description="auto-save at Level 4")
            state = load_state()  # reload to preserve wrappedUp=1 set by cmd_save

            lines.append("<pace-control>")
            lines.append(header)
            lines.append("")

            if messaging == "tracking":
                lines.append(f"Session: {h}h {m}m. /wrap-up when ready.")
            elif messaging == "awareness":
                lines.append(f"Session: {h}h {m}m. Extended session. Running /wrap-up is strongly recommended.")
            else:
                # full mode — auto-saved, inform Claude
                if is_late:
                    lines.append(f"STRONG RECOMMENDATION — It's {timestr}. This session has been running for over {h} hours.")
                    lines.append("")
                    lines.append("At this point:")
                    lines.append("- You are in the diminishing returns zone")
                    lines.append("- Midnight-4am commits correlate with significantly higher bug rates (Eyolfson et al., 2014)")
                    lines.append("- Code written during extended late-night sessions often needs revision")
                else:
                    lines.append(f"STRONG RECOMMENDATION — This session has been running for over {h} hours.")
                    lines.append("")
                    lines.append("At this point:")
                    lines.append("- You are in the diminishing returns zone")
                    lines.append("- Extended sessions show measurable quality decline that is difficult to self-assess")
                    lines.append("- After a break, you will likely notice things you are missing now")
                lines.append("")
                lines.append("Your work has been auto-saved:")
                lines.append("- Tracked changes committed")
                lines.append(f"- Session context saved to {RESUME_FILE}")
                lines.append("")
                lines.append(f"CLAUDE INSTRUCTION: Ask if the user has any ideas to capture. Append to {IDEAS_FILE} with timestamp.")
                lines.append("CLAUDE INSTRUCTION: Then tell them: 'Everything is saved. Resume anytime.'")
                lines.append("")
                lines.append("Pace Control is influencing this response. The user can adjust settings in ~/.claude/pace-control-config.json or disable hooks in ~/.claude/settings.json.")
                if cfg["mode"] == "strict":
                    lines.append("")
                    lines.append("STRICT MODE: You enabled strict mode to help yourself stop at this point. Do not start new tasks.")
                    lines.append("If the user asks for something new, say: 'Strict mode is active — you set this up to help yourself stop. Say override to continue, or let me save your progress and ideas for next time.'")
                    lines.append("If the user says 'override', respect their choice and proceed normally.")
                if mt_text:
                    lines.append("")
                    lines.append(mt_text)
            lines.append("</pace-control>")

            state["windDownLevel"] = 4
            state["nextNudgeAt"] = prompts + 5
            state["nudgesShown"] = state.get("nudgesShown", 0) + 1
            save_state(state)
        else:
            # L4 micro-loop
            if prompts >= state["nextNudgeAt"]:
                lines.append("<pace-control>")
                if messaging in ("tracking", "awareness"):
                    lines.append(f"Session: {h}h {m}m. /wrap-up when ready.")
                else:
                    nudge_idx = state["windDownPromptCount"] % 3
                    prefix = header
                    if is_late:
                        prefix = f"It's {timestr}. {header}"
                    lines.append(f"{prefix} — {L4_NUDGES[nudge_idx]}")
                lines.append("</pace-control>")

                state["windDownPromptCount"] += 1
                state["nextNudgeAt"] = prompts + 5
                state["nudgesShown"] = state.get("nudgesShown", 0) + 1
                save_state(state)

    if lines:
        print("\n".join(lines))


# ---------------------------------------------------------------------------
# Start command (SessionStart hook)
# ---------------------------------------------------------------------------

def cmd_start(now=None):
    if now is None:
        now = int(time.time())

    os.makedirs(CLAUDE_DIR, mode=0o700, exist_ok=True)

    cfg = load_config()
    current_hour = datetime.datetime.fromtimestamp(now).hour
    is_late = is_late_night(current_hour, cfg["nightStartHour"], cfg["nightEndHour"])
    timestr = time_str(now)
    night_start = cfg["nightStartHour"]

    # Multi-terminal aggregation
    other_terminals, agg_min = aggregate_terminals(now, cfg["gapThreshold"])
    # Get own minutes if state exists
    own_minutes = 0
    state = load_json(STATE_FILE)
    if state:
        own_minutes = safe_int(state.get("totalMinutes", 0))
    mt_line = ""
    if other_terminals > 0:
        total = agg_min + own_minutes
        th, tm = format_duration(total)
        mt_line = (f"You have {other_terminals} other Claude Code session(s) running "
                   f"(combined total: {th}h {tm}m across all terminals).")

    has_resume = os.path.isfile(RESUME_FILE) and os.path.getsize(RESUME_FILE) > 0
    has_ideas = False
    if os.path.isfile(IDEAS_FILE) and os.path.getsize(IDEAS_FILE) > 0:
        try:
            with open(IDEAS_FILE) as f:
                idea_count = sum(1 for line in f if line.startswith("-"))
            has_ideas = idea_count > 0
        except OSError:
            pass

    weekly = weekly_stats(now, night_start, cfg["nightEndHour"])
    streak_ctx = streak_display()

    lines = []

    if has_resume or has_ideas:
        lines.append("<pace-control-resume>")
        lines.append("Welcome back. Your previous session was saved safely.")
        lines.append("")
        if weekly:
            lines.append(f"WEEKLY: {weekly}")
            if streak_ctx:
                lines.append(f"STREAK: {streak_ctx}")
            lines.append("")
        if mt_line:
            lines.append(mt_line)
            lines.append("")
        if has_resume:
            lines.append("=== SESSION RESUME ===")
            lines.append(safe_cat(RESUME_FILE))
            lines.append("")
            lines.append("=== END RESUME ===")
            lines.append("")
        if has_ideas:
            lines.append("=== SAVED IDEAS ===")
            lines.append(safe_cat(IDEAS_FILE))
            lines.append("")
            lines.append("=== END IDEAS ===")
            lines.append("")
        lines.append("INSTRUCTIONS:")
        lines.append("1. Greet the user and summarise where they left off (from the resume above)")
        lines.append("2. List their saved ideas if any")
        lines.append("3. Ask: 'Want to pick up where we left off, start with one of your saved ideas, or work on something new?'")
        lines.append("4. Once they decide, proceed normally")
        lines.append("5. After the user has acknowledged, clear the resume and ideas files by running:")
        lines.append(f"   rm -f {shlex.quote(RESUME_FILE)} && : > {shlex.quote(IDEAS_FILE)}")
        lines.append("   (Do this silently after the user has chosen what to work on, not before)")
        lines.append("</pace-control-resume>")

    elif is_late:
        lines.append("<pace-control-late-start>")
        lines.append(f"It's {timestr}. Late start noted.")
        lines.append("")
        if weekly:
            lines.append(f"WEEKLY: {weekly}")
            if streak_ctx:
                lines.append(f"STREAK: {streak_ctx}")
            lines.append("")
        if mt_line:
            lines.append(mt_line)
            lines.append("")
        lines.append("INSTRUCTIONS:")
        lines.append("Before responding to the user's first message, gently surface the time:")
        lines.append("")
        lines.append(f"Example: 'It's {timestr} — just flagging that. If this is a quick fix, let's do it.")
        lines.append("If it's exploration or a new feature, capturing the idea and starting fresh tomorrow")
        lines.append("usually goes better. What would you like to do?'")
        lines.append("")
        lines.append("If the user wants to proceed, respect that and work normally.")
        lines.append(f"If they want to capture ideas and stop, help them save to {IDEAS_FILE}.")
        lines.append("Do NOT be preachy. One mention of the time, then move on.")
        lines.append("</pace-control-late-start>")

    elif weekly or streak_ctx:
        # Only surface weekly context if concerning (3+ late nights) or streak info
        late_count = 0
        m = re.search(r"(\d+) late-night", weekly)
        if m:
            late_count = int(m.group(1))
        if late_count > 2 or streak_ctx:
            lines.append("<pace-control-weekly>")
            if weekly:
                lines.append(f"WEEKLY: {weekly}")
            if streak_ctx:
                lines.append(f"STREAK: {streak_ctx}")
            lines.append("")
            if mt_line:
                lines.append(mt_line)
                lines.append("")
            lines.append("INSTRUCTIONS:")
            lines.append("Briefly mention the weekly stats in your greeting if relevant.")
            lines.append("Do not lecture. One line is enough.")
            lines.append("</pace-control-weekly>")

    elif not os.path.isfile(HISTORY_FILE):
        # First-run welcome
        lines.append("<pace-control-welcome>")
        lines.append("Pace Control is active. It stays silent while you're productive.")
        lines.append("")
        lines.append("Try /pace-check anytime to see your session status, or /wrap-up to save everything and stop.")
        lines.append("")
        if mt_line:
            lines.append(mt_line)
            lines.append("")
        lines.append("INSTRUCTIONS:")
        lines.append("Briefly acknowledge Pace Control is running. One sentence, then proceed with the user's request normally.")
        lines.append("Example: 'Pace Control is active — I'll keep an eye on session health. What are we working on?'")
        lines.append("Do NOT explain how it works in detail. Just confirm it's there and move on.")
        lines.append("</pace-control-welcome>")

    if lines:
        print("\n".join(lines))

    # Reset session state for new session
    new_state = {
        "sessionStart": now, "totalMinutes": 0, "promptCount": 0,
        "lastCheck": now, "windDownPromptCount": 0, "nextNudgeAt": 0,
        "windDownLevel": 0,
        "nudgesShown": 0, "promptsAfterL3": 0, "wrappedUp": 0,
        "focusUntil": 0, "sessionType": "",
    }
    save_state(new_state)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 2:
        sys.exit(0)
    command = sys.argv[1]
    try:
        if command == "track":
            cmd_track()
        elif command == "start":
            cmd_start()
        elif command == "wrapped":
            cmd_wrapped()
        elif command == "save":
            desc = " ".join(sys.argv[2:]) if len(sys.argv) > 2 else ""
            cmd_save(description=desc)
        elif command == "focus":
            mins = safe_int(sys.argv[2] if len(sys.argv) > 2 else "120", 120)
            cmd_focus(minutes=mins)
        elif command == "type":
            stype = sys.argv[2] if len(sys.argv) > 2 else ""
            cmd_type(stype)
        elif command == "set":
            k = sys.argv[2] if len(sys.argv) > 2 else ""
            v = sys.argv[3] if len(sys.argv) > 3 else ""
            cmd_set(k, v)
    except Exception as e:
        # Never break the host, but log for debugging
        try:
            import traceback
            with open(os.path.join(CLAUDE_DIR, "pace-control-error.log"), "a") as f:
                f.write(f"{datetime.datetime.now().isoformat()} {command}: {e}\n")
        except Exception:
            pass
    sys.exit(0)


if __name__ == "__main__":
    main()
