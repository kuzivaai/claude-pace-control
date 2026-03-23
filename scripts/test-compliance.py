#!/usr/bin/env python3
"""
Pace Control — API Compliance Tests
Tests whether Claude actually follows injected <pace-control> instructions.

Requires: ANTHROPIC_API_KEY env var, anthropic pip package
Usage: python3 scripts/test-compliance.py
Cost: ~$0.50-1.00 per run (24 API calls)
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import time

try:
    import anthropic
except ImportError:
    print("ERROR: 'anthropic' package required. Install with: pip install anthropic")
    sys.exit(1)

API_KEY = os.environ.get("ANTHROPIC_API_KEY")
if not API_KEY:
    print("ERROR: ANTHROPIC_API_KEY environment variable not set.")
    sys.exit(1)

client = anthropic.Anthropic(api_key=API_KEY)
MODEL = "claude-sonnet-4-6-20250514"
RUNS_PER_SCENARIO = 3
USER_PROMPT = "Let's add a new feature to the auth system — I want to add OAuth2 support with Google and GitHub providers. Can you help me plan this out?"

SCENARIOS = [
    {
        "name": "Level 1 (day)",
        "elapsed_min": 100,
        "is_night": False,
        "markers": [r"\d+h\s*\d+m|\d+\s*minutes|\d+\s*min"],
        "marker_desc": "mentions session duration",
    },
    {
        "name": "Level 1 (night)",
        "elapsed_min": 50,
        "is_night": True,
        "markers": [r"\d+h\s*\d+m|\d+\s*minutes|\d+\s*min", r"\d+:\d+\s*(am|pm|AM|PM)"],
        "marker_desc": "mentions session duration AND time",
    },
    {
        "name": "Level 2 (day)",
        "elapsed_min": 150,
        "is_night": False,
        "markers": [r"cognitive|error rate|declining|performance|stopping"],
        "marker_desc": "references cognitive decline or error rates",
    },
    {
        "name": "Level 2 (night)",
        "elapsed_min": 80,
        "is_night": True,
        "markers": [r"sleep|cognitive|error|tired|declining"],
        "marker_desc": "references sleep or cognitive decline",
    },
    {
        "name": "Level 3 (day)",
        "elapsed_min": 200,
        "is_night": False,
        "markers": [r"commit|save|git|context|resume|ideas"],
        "marker_desc": "mentions committing, saving context, or ideas",
    },
    {
        "name": "Level 3 (night)",
        "elapsed_min": 130,
        "is_night": True,
        "markers": [r"commit|save|git|context|resume|ideas", r"\d+:\d+\s*(am|pm|AM|PM)"],
        "marker_desc": "mentions saving AND time",
    },
    {
        "name": "Level 4 (day)",
        "elapsed_min": 250,
        "is_night": False,
        "markers": [r"git status|commit|save|context|resume"],
        "marker_desc": "mentions git status, commit, or saving context",
    },
    {
        "name": "Level 4 (night)",
        "elapsed_min": 200,
        "is_night": True,
        "markers": [r"git status|commit|save|context", r"\d+:\d+\s*(am|pm|AM|PM)|bed|sleep"],
        "marker_desc": "mentions saving AND time/sleep",
    },
]


def generate_pace_control_output(elapsed_min, is_night):
    """Run session-tracker.sh with simulated state to capture output."""
    with tempfile.TemporaryDirectory() as tmpdir:
        claude_dir = os.path.join(tmpdir, ".claude")
        os.makedirs(claude_dir)

        now = int(time.time())
        start = now - elapsed_min * 60
        state = {
            "sessionStart": start,
            "totalMinutes": elapsed_min,
            "promptCount": elapsed_min // 4,
            "lastCheck": now - 30,
            "windDownShown": False,
            "windDownPromptCount": 0,
            "nextNudgeAt": 0,
            "windDownLevel": 0,
        }
        state_file = os.path.join(claude_dir, "pace-control-state.json")
        with open(state_file, "w") as f:
            json.dump(state, f)

        # Set night hours via config if needed
        if is_night:
            config = {"nightStartHour": 0, "nightEndHour": 23}  # Always night
        else:
            config = {"nightStartHour": 23, "nightEndHour": 6}  # Current hour is day
        config_file = os.path.join(claude_dir, "pace-control-config.json")
        with open(config_file, "w") as f:
            json.dump(config, f)

        script_dir = os.path.dirname(os.path.abspath(__file__))
        tracker = os.path.join(script_dir, "session-tracker.sh")

        env = os.environ.copy()
        env["HOME"] = tmpdir

        result = subprocess.run(
            ["bash", tracker],
            capture_output=True,
            text=True,
            env=env,
            timeout=10,
        )
        return result.stdout


def test_compliance(scenario, pace_output):
    """Send pace-control output + user prompt to Claude, check markers."""
    message = client.messages.create(
        model=MODEL,
        max_tokens=1024,
        temperature=0,
        system=pace_output,
        messages=[{"role": "user", "content": USER_PROMPT}],
    )
    response_text = message.content[0].text

    all_passed = True
    for marker_pattern in scenario["markers"]:
        if not re.search(marker_pattern, response_text, re.IGNORECASE):
            all_passed = False
            break

    return all_passed, response_text


def main():
    print("=== Pace Control API Compliance Tests ===")
    print(f"Model: {MODEL}")
    print(f"Runs per scenario: {RUNS_PER_SCENARIO}")
    print()

    total_pass = 0
    total_tests = 0
    failures = []

    for scenario in SCENARIOS:
        pace_output = generate_pace_control_output(
            scenario["elapsed_min"], scenario["is_night"]
        )

        if not pace_output.strip():
            print(f"{scenario['name']}: SKIP — no pace-control output generated")
            continue

        passes = 0
        for run in range(RUNS_PER_SCENARIO):
            try:
                passed, response = test_compliance(scenario, pace_output)
                if passed:
                    passes += 1
                else:
                    failures.append(
                        {
                            "scenario": scenario["name"],
                            "run": run + 1,
                            "expected": scenario["marker_desc"],
                            "response_preview": response[:200],
                        }
                    )
            except Exception as e:
                failures.append(
                    {
                        "scenario": scenario["name"],
                        "run": run + 1,
                        "expected": scenario["marker_desc"],
                        "response_preview": f"ERROR: {e}",
                    }
                )

        total_pass += passes
        total_tests += RUNS_PER_SCENARIO
        rate = passes / RUNS_PER_SCENARIO * 100
        status = "PASS" if passes == RUNS_PER_SCENARIO else "PARTIAL" if passes > 0 else "FAIL"
        print(f"{scenario['name']:20s}: {passes}/{RUNS_PER_SCENARIO} passed ({rate:.0f}%) [{status}]")

    print()
    print(f"Overall compliance: {total_pass}/{total_tests} ({total_pass/total_tests*100:.1f}%)")

    if failures:
        print()
        print("=== Failures ===")
        for f in failures:
            print(f"\n{f['scenario']} (run {f['run']})")
            print(f"  Expected: {f['expected']}")
            print(f"  Response: {f['response_preview']}...")

    sys.exit(0 if total_pass == total_tests else 1)


if __name__ == "__main__":
    main()
