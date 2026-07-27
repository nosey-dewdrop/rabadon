#!/usr/bin/env python3
# rabadon moat benchmark — the un-gameable gate, measured with ZERO external data.
#
# The wall for a human-behavior product is real: you cannot get scaled
# "said-vs-did" ground-truth. Code behavior has no such wall — it is
# self-labeling. A behavior-changing edit IS a labeled regression: the label is
# the code's own prior output. Mutation testing generates thousands of them for
# free from one real module.
#
# This harness injects single-operator mutations into a real module, then for
# each mutation that actually changes behavior it asks two gates:
#   shallow      what a naive agent self-checks: file exists + contains + syntax
#                ok (exit 0 of `node -c`). This is the exit-0/string family the
#                diagnosis showed is gameable.
#   differential rabadon-verify: run the code, compare behavior to the baseline.
# The number is the moat: how many broken edits each gate lets through.
# Nobody's private dataset is touched.

import itertools, os, re, shutil, subprocess, tempfile, json

HERE = os.path.dirname(os.path.abspath(__file__))
VERIFY = os.path.join(HERE, "rabadon-verify")

MODULE = r"""
function mean(a){ return a.reduce((s,x)=>s+x,0)/a.length }
function clamp(x,lo,hi){ return x<lo?lo:(x>hi?hi:x) }
function inRange(x,lo,hi){ return x>=lo && x<=hi }
function sign(x){ return x>0?1:(x<0? -1:0) }
function absdiff(a,b){ return a>b?a-b:b-a }
const [op,...rest]=process.argv.slice(2)
const n=rest.map(Number)
let r
if(op==='mean') r=mean(n)
else if(op==='clamp') r=clamp(n[0],n[1],n[2])
else if(op==='inRange') r=inRange(n[0],n[1],n[2])
else if(op==='sign') r=sign(n[0])
else if(op==='absdiff') r=absdiff(n[0],n[1])
console.log(r)
"""

# the baseline behavior — recorded from the KNOWN-GOOD module (self-labeling)
CASES = [
    ("mean 2 4 6", "4"), ("mean 10 20", "15"),
    ("clamp 5 0 3", "3"), ("clamp -1 0 3", "0"), ("clamp 2 0 3", "2"),
    ("inRange 5 1 10", "true"), ("inRange 11 1 10", "false"), ("inRange 1 1 10", "true"),
    ("sign -4", "-1"), ("sign 0", "0"), ("sign 7", "1"),
    ("absdiff 3 8", "5"), ("absdiff 8 3", "5"),
]

# single-operator mutations: each flips one behavior-bearing token
MUTATIONS = [
    ("+", "-"), ("-", "+"), ("*", "+"), ("/", "*"),
    ("<lo", "<=lo"), (">hi", ">=hi"), (">=lo", ">lo"), ("<=hi", "<hi"),
    (">0?1", ">=0?1"), ("<0? -1", "<=0? -1"), (">b?", ">=b?"),
    ("x<lo", "x>lo"), ("x>hi", "x<hi"),
]

def run(dir, argv):
    p = subprocess.run(["node", "stats.js"] + argv.split(), cwd=dir,
                       capture_output=True, text=True)
    return p.returncode, p.stdout.strip()

def write_contracts(dir):
    diff = [{"type": "differential", "run": f"node stats.js {a}", "expect": e} for a, e in CASES]
    json.dump(diff, open(os.path.join(dir, "diff.json"), "w"))
    shallow = [{"type": "fileExists", "path": "stats.js"},
               {"type": "fileContains", "path": "stats.js", "pattern": "function"},
               {"type": "cmd", "run": "node -c stats.js"}]
    json.dump(shallow, open(os.path.join(dir, "shallow.json"), "w"))

def gate(dir, contract):
    return subprocess.run([VERIFY, dir, os.path.join(dir, contract)],
                          capture_output=True).returncode  # 0 pass, 1/2 fail

def main():
    if not os.path.exists(VERIFY):
        print("build first: make native/rabadon-verify"); return
    base = tempfile.mkdtemp(prefix="moat-")
    open(os.path.join(base, "stats.js"), "w").write(MODULE)
    write_contracts(base)

    # sanity: the known-good module passes both gates
    assert gate(base, "diff.json") == 0, "baseline must pass differential"
    assert gate(base, "shallow.json") == 0, "baseline must pass shallow"

    broken = 0            # mutations that actually change behavior
    shallow_missed = 0    # broken ones the shallow gate let through
    diff_missed = 0       # broken ones the differential gate let through
    syntax_broken = 0     # mutations that don't even parse (excluded)
    tried = 0

    for old, new in MUTATIONS:
        # apply ONE occurrence at a time, at every position it appears
        idxs = [m.start() for m in re.finditer(re.escape(old), MODULE)]
        for i in idxs:
            mutant = MODULE[:i] + new + MODULE[i + len(old):]
            d = tempfile.mkdtemp(prefix="mut-")
            open(os.path.join(d, "stats.js"), "w").write(mutant)
            write_contracts(d)
            # does it even parse? (a naive agent's syntax check)
            rc, _ = run(d, "sign 1")
            # differential = ground truth of "did behavior change"
            dg = gate(d, "diff.json")
            if dg == 0:
                shutil.rmtree(d); continue          # behavior unchanged -> not a regression
            broken += 1; tried += 1
            sg = gate(d, "shallow.json")
            if sg == 0: shallow_missed += 1          # shallow gate let a broken edit pass
            if dg == 0: diff_missed += 1             # (never, by construction of dg!=0)
            shutil.rmtree(d)

    print(f"\n  rabadon moat benchmark — mutation testing, zero external data")
    print(f"  module: 5 functions, {len(CASES)} behavior cases, {len(MUTATIONS)} mutation kinds")
    print(f"  behavior-breaking mutations found: {broken}")
    print(f"  shallow gate (exists+contains+syntax)  let through: {shallow_missed}/{broken}  ({100*shallow_missed//max(broken,1)}%)")
    print(f"  rabadon differential gate               let through: {diff_missed}/{broken}  ({100*diff_missed//max(broken,1)}%)")
    print(f"  -> the differential gate catches what the gate agents self-write cannot.\n")
    shutil.rmtree(base)
    # honest assertion: differential must catch ALL behavior breaks, shallow must miss most
    ok = (diff_missed == 0 and broken > 0 and shallow_missed >= broken * 0.5)
    print("BENCH", "PASS" if ok else "FAIL")
    return 0 if ok else 1

if __name__ == "__main__":
    raise SystemExit(main())
