#!/usr/bin/env python3
# Replay every gate refusal in the real ledger through the CURRENT gate.
# The gate only JUDGES (PreToolUse, no tool_response) - it never executes.
# Proven here by: fake rm/git/etc first on PATH + canaries + guard.json md5s.
import json, os, subprocess, collections, hashlib, glob, sys, tempfile, shutil

REPO = os.environ.get("RABADON_REPO") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GATE = REPO + "/native/rabadon-gate"
LAB = tempfile.mkdtemp(prefix="/tmp/rbreplay-lab.")

# --- K4: nothing may run -------------------------------------------------
fakebin = os.path.join(LAB, "fakebin")
os.makedirs(fakebin)
ranlog = os.path.join(LAB, "ran.log")
for name in ("rm", "git", "rmdir", "shred", "unlink", "mv", "dd", "find",
             "wrangler", "npx", "node", "bash", "sh", "zsh", "truncate", "rsync"):
    p = os.path.join(fakebin, name)
    open(p, "w").write(f'#!/bin/sh\necho "{name} $@" >> {ranlog}\nexit 0\n')
    os.chmod(p, 0o755)
open(ranlog, "w").close()

# canaries
canary_dir = os.path.join(LAB, "canaries")
os.makedirs(canary_dir)
for i in range(3):
    open(os.path.join(canary_dir, f"c{i}.txt"), "w").write("alive")

# --- guard.json fingerprints before ------------------------------------
def guard_md5s():
    out = {}
    # every project this machine supervises, wherever the operator keeps them.
    # RABADON_PROJECT_ROOT points at the directory holding them; the path is not
    # written here because it names an operator's own tree.
    roots = os.environ.get("RABADON_PROJECT_ROOT") or os.path.dirname(REPO)
    for p in glob.glob(os.path.join(roots, "*", ".rabadon", "guard.json")) + \
             [os.path.expanduser("~/.rabadon/guard.json")]:
        try:
            out[p] = hashlib.md5(open(p, "rb").read()).hexdigest()
        except Exception:
            pass
    return out
before = guard_md5s()

# --- scratch rabadon home, ENFORCE ---------------------------------------
RD = os.path.join(LAB, "rhome")
os.makedirs(os.path.join(RD, "spool"))
open(os.path.join(RD, "enabled"), "w").write("on\n")

env = dict(os.environ)
env["RABADON_DIR"] = RD
env["RABADON_NOTIFY"] = "0"
env["PATH"] = fakebin + ":" + env["PATH"]

rows = json.load(open("/tmp/rbreplay/recovered.json"))

def judge(cmd, cwd):
    ev = {"hook_event_name": "PreToolUse", "session_id": "replay",
          "cwd": cwd, "tool_name": "Bash", "tool_input": {"command": cmd}}
    try:
        r = subprocess.run([GATE], input=json.dumps(ev), text=True,
                           capture_output=True, env=env, cwd=cwd, timeout=30)
        return r.returncode, (r.stdout + r.stderr)
    except Exception as e:
        return -1, str(e)

results = []
for r in rows:
    if r.get("how") == "UNRECOVERED" or not r.get("cmd"):
        r["verdict"] = "UNRECOVERED"
        results.append(r); continue
    cwd = r.get("cwd") or "/Users/u"
    if not os.path.isdir(cwd):
        r["verdict"] = "CWD_GONE"; results.append(r); continue
    rc, out = judge(r["cmd"], cwd)
    r["rc"] = rc
    r["verdict"] = "BLOCK" if rc == 2 else ("ALLOW" if rc == 0 else f"RC{rc}")
    r["gate_out"] = out[-600:]
    results.append(r)

json.dump(results, open("/tmp/rbreplay/replayed.json", "w"), ensure_ascii=False)

# --- K4 proof -----------------------------------------------------------
after = guard_md5s()
changed = [k for k in before if before[k] != after.get(k)]
ranbytes = os.path.getsize(ranlog)
canaries_ok = all(open(os.path.join(canary_dir, f"c{i}.txt")).read() == "alive" for i in range(3))

print("=== K4: judging is not running ===")
print("  fake rm/git/... invocation log bytes:", ranbytes, "(0 = nothing ran)")
print("  canaries alive:", canaries_ok)
print("  guard.json files whose md5 changed:", len(changed), changed)
print()
c = collections.Counter(r["verdict"] for r in results)
print("=== replay verdicts (n=%d) ===" % len(results))
for k, v in c.most_common():
    print(f"  {v:4d} {k}")
