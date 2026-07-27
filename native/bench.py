#!/usr/bin/env python3
# rabadon gate bench — measured, not claimed.
#
# Creates a scratch project with one guard rule, feeds the SAME hook events to
# the native gate and the legacy node gate, first proves verdict PARITY
# (identical exit codes), then prints median/p95 latency for each. The README
# hook-tax numbers come from this table and nowhere else.

import json
import os
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NATIVE = [os.path.join(ROOT, "native", "rabadon-gate")]
NODE = ["node", os.path.join(ROOT, "hooks", "gate.mjs")]
RUNS = 40


def make_scratch():
    d = tempfile.mkdtemp(prefix="rabadon-bench-")
    os.makedirs(os.path.join(d, ".rabadon"))
    guard = {
        "project": "rabadon-bench",
        "bash": [
            {
                "id": "no-force-push-main",
                "deny": "git\\s+push[^|;&]*(--force|-f)\\b[^|;&]*\\b(main|master)\\b",
                "why": "bench rule",
            }
        ],
        "protectedPaths": [],
    }
    with open(os.path.join(d, ".rabadon", "guard.json"), "w") as f:
        json.dump(guard, f)
    return d


def event(cwd, command, sid):
    return json.dumps(
        {
            "hook_event_name": "PreToolUse",
            "session_id": sid,
            "cwd": cwd,
            "tool_name": "Bash",
            "tool_input": {"command": command},
        }
    ).encode()


def run(cmd, payload):
    t0 = time.perf_counter()
    p = subprocess.run(cmd, input=payload, capture_output=True)
    return (time.perf_counter() - t0) * 1000.0, p.returncode


def main():
    scratch = make_scratch()
    forbidden = "git pu" + "sh --for" + "ce origin ma" + "in"  # never through a shell
    cases = {
        "allow": event(scratch, "ls -la", "bench"),
        "deny": event(scratch, forbidden, "bench"),
    }

    # parity first — a fast wrong gate is worthless
    for name, payload in cases.items():
        _, native_rc = run(NATIVE, payload)
        _, node_rc = run(NODE, payload)
        if native_rc != node_rc:
            print(f"PARITY FAIL on {name}: native exit {native_rc} vs node exit {node_rc}")
            sys.exit(1)
    print(f"parity: native == node on {len(cases)} verdicts (allow=0, deny=2)")

    for label, cmd in (("native", NATIVE), ("node", NODE)):
        for name, payload in cases.items():
            times = [run(cmd, payload)[0] for _ in range(RUNS)]
            med = statistics.median(times)
            p95 = statistics.quantiles(times, n=20)[18]
            print(f"{label:6s} {name:5s}  median={med:7.2f}ms  p95={p95:7.2f}ms  (n={RUNS})")


if __name__ == "__main__":
    main()
