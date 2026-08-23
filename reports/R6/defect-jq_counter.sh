#!/usr/bin/env bash
# reports/R6/defect-jq_counter.sh — the runnable proof of ONE defect in
# reports/R6/accept.sh. That file is NOT edited, here or anywhere.
#
# THE DEFECT. accept.sh reads every counter field through this helper:
#
#     jq_counter() { python3 - "$2" <<PY 2>/dev/null
#     ...
#     try: d=json.loads(sys.stdin.read())
#     except Exception: sys.exit(1)
#     ...
#     PY
#     }
#
# and calls it as `printf '%s' "$UJ" | jq_counter - counter.saved_usd`.
#
# The heredoc IS the process's stdin, because `python3 -` reads its PROGRAM from
# stdin. python reads that stdin to EOF to get the program, so by the time the
# program runs, `sys.stdin.read()` returns the empty string and the piped JSON
# was never on that file descriptor at all. json.loads("") raises, the helper
# exits 1 with no output — for EVERY input, including a trivially correct one.
#
# A helper that returns nothing for `{"a":{"b":7}}` cannot read a counter out of
# any product, so claims 2a-2h, 3a, 3b and 4c cannot go green no matter what the
# code does, and 5b fails with them because EXP_NET is computed from 2a's rates.
#
# THE FIX IS ONE CHARACTER OF SHELL, NOT ONE LINE OF PRODUCT: pass the program
# as an argument (`python3 -c`) so stdin stays the pipe. Part 2 below runs
# accept.sh with that single substitution and NOTHING else changed.
set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

printf '== 1. the helper, verbatim from accept.sh, against a trivially correct input\n'

jq_counter() { # jq_counter <json> <dotted.path>   (copied byte-for-byte)
  python3 - "$2" <<PY 2>/dev/null
import json,sys
try: d=json.loads(sys.stdin.read())
except Exception: sys.exit(1)
cur=d
for k in sys.argv[1].split('.'):
    if not isinstance(cur,dict) or k not in cur: sys.exit(1)
    cur=cur[k]
print("" if cur is None else cur)
PY
}

OUT="$(printf '%s' '{"a":{"b":7}}' | jq_counter - a.b)"; RC=$?
printf '   input {"a":{"b":7}}, path a.b -> output [%s] exit %d  (expected [7] exit 0)\n' "$OUT" "$RC"

printf '   what python actually finds on stdin after reading its program: '
printf '%s' '{"a":{"b":7}}' | python3 - <<'PY'
import sys
print(repr(sys.stdin.read()))
PY

if [ -z "$OUT" ]; then
  printf '   PROVEN: the helper is blind. Every jq_counter-backed assertion is unreachable.\n'
else
  printf '   NOT REPRODUCED on this shell/python: the helper returned a value.\n'
  exit 1
fi

printf '\n== 2. accept.sh with ONLY that helper repaired (python3 -c), nothing else\n'
# the copy lives beside the exam on purpose: accept.sh resolves ROOT from its
# own directory, so a copy in /tmp would point at the wrong tree.
FIXED="$(mktemp "$HERE/.defect-fixed.XXXXXX.sh")"
trap 'rm -f "$FIXED"' EXIT
python3 - "$ROOT/reports/R6/accept.sh" "$FIXED" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
a = s.index('jq_counter() {')
b = s.index("# the dollar figure printed on the closing line")
new = '''jq_counter() { # jq_counter <json> <dotted.path>  [REPAIRED: program as argv, stdin stays the pipe]
  python3 -c 'import json,sys
try: d=json.loads(sys.stdin.read())
except Exception: sys.exit(1)
cur=d
for k in sys.argv[1].split("."):
    if not isinstance(cur,dict) or k not in cur: sys.exit(1)
    cur=cur[k]
print("" if cur is None else cur)' "$2" 2>/dev/null
}
'''
open(dst, 'w').write(s[:a] + new + s[b:])
PY
printf '   the only difference from the exam:\n'
diff "$ROOT/reports/R6/accept.sh" "$FIXED" | sed 's/^/   /'
printf '\n'
bash "$FIXED"
exit $?
