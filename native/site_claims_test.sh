#!/bin/bash
# site_claims_test.sh — every number on the site must be produced, not typed.
#
# Two failures this file exists to make impossible, both of which shipped:
#
#   1. The benchmarks page carried "42.0µs to judge one command" and named
#      native/gate_bench.sh as where it was measured. That file did not exist.
#      A page that cites a command nobody can run is a page that cannot be
#      checked, which is the whole thing this project sells.
#
#   2. The overview said 207 commands refused and the catches page, built from
#      the same ledger minutes later, said 219. Both were true when they were
#      written. The catches page regenerates itself and the overview did not,
#      so the overview started lying the moment the next command was refused.
#      The invariant is not "207 is right", it is "the two pages cannot
#      disagree", and only a generated overview can hold it.
#
# So: every source path the site names must exist and be runnable, the overview
# must be generated from a template that contains no measured numbers at all,
# and any number that appears on two pages must be the same number.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
cd "$REPO" || exit 1

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "site claims — a number with no command behind it is a slogan"
echo

# ---------------------------------------------------------------------------
# 1. every path the site names as its source exists and is runnable
# ---------------------------------------------------------------------------
echo "1. the sources the site names"
SRCS=$(python3 - <<'PY'
import re
s = open('site/build.py', encoding='utf-8').read()
# the fourth field of every GATE row, and every "cmd" in measured.json's loader
for m in re.finditer(r'"(native/[A-Za-z0-9_./-]+)"', s):
    print(m.group(1))
PY
)
[ -n "$SRCS" ] || bad "no source paths found in site/build.py (the GATE table lost its 'where' column?)"
for p in $SRCS; do
  if [ ! -e "$p" ]; then
    bad "site/build.py cites $p — it does not exist"
  elif [ ! -r "$p" ]; then
    bad "site/build.py cites $p — it is not readable"
  else
    ok "$p exists"
  fi
done

# measured.json is the one place a bench number is allowed to live, and every
# entry in it has to name the script that produced it.
if [ -f site/measured.json ]; then
  MJ=$(python3 - <<'PY'
import json, os, sys
d = json.load(open('site/measured.json', encoding='utf-8'))
bad = 0
for k, v in d.items():
    if k.startswith('_'):
        continue
    cmd = v.get('cmd', '')
    # a cmd is either a path (native/gate_bench.sh) or a one-liner that NAMES a
    # path (grep -c ... reports/.../06-locks.txt). either way at least one word
    # of it has to be a file in this repository, or the number is unsourced.
    words = [w.strip("'\"") for w in cmd.split()]
    if not cmd:
        print('MISSING-CMD', k); bad += 1
    elif not any(os.path.exists(w) for w in words):
        print('MISSING-FILE', k, cmd); bad += 1
    else:
        print('OK', k, cmd)
sys.exit(1 if bad else 0)
PY
)
  if [ $? -eq 0 ]; then ok "site/measured.json: every entry names a script that exists"
  else bad "site/measured.json entries with no runnable source:"; echo "$MJ" | sed 's/^/        /'; fi
else
  bad "site/measured.json missing — bench numbers are still typed into the page by hand"
fi
echo

# ---------------------------------------------------------------------------
# 2. the overview is generated, and its template holds no measured numbers
# ---------------------------------------------------------------------------
echo "2. the overview is built, not typed"
if [ ! -f site/index.tmpl.html ]; then
  bad "site/index.tmpl.html missing — site/index.html is still hand-maintained"
else
  ok "site/index.tmpl.html exists"
  LEFT=$(python3 - <<'PY'
import re
s = open('site/index.tmpl.html', encoding='utf-8').read()
# a headline stat is <span class="n ...">VALUE</span>; VALUE must be a placeholder
left = []
for m in re.finditer(r'class="n[^"]*">([^<]*)</span>', s):
    v = m.group(1).strip()
    if not (v.startswith('{{') and v.endswith('}}')):
        left.append(v)
print('\n'.join(left))
PY
)
  if [ -z "$LEFT" ]; then ok "no measured number left in the template's headline stats"
  else bad "numbers still typed into site/index.tmpl.html:"; echo "$LEFT" | sed 's/^/        /'; fi
fi

python3 site/build.py > /tmp/rb_site_build.$$ 2>&1
if [ $? -ne 0 ]; then
  bad "site/build.py failed"; sed 's/^/        /' /tmp/rb_site_build.$$ | tail -20
else
  ok "site/build.py ran"
fi
rm -f /tmp/rb_site_build.$$

# no placeholder may survive into the shipped page
UNFILLED=$(grep -o '{{[a-zA-Z0-9_.]*}}' site/index.html 2>/dev/null | sort -u)
if [ -z "$UNFILLED" ]; then ok "no unfilled placeholder in site/index.html"
else bad "placeholders left unrendered in site/index.html:"; echo "$UNFILLED" | sed 's/^/        /'; fi
echo

# ---------------------------------------------------------------------------
# 3. the same fact may not have two values
# ---------------------------------------------------------------------------
echo "3. two pages, one number"
CROSS=$(python3 - <<'PY'
import re, sys

def first_stat(path, needle):
    """the number in the stat block whose caption contains `needle`"""
    s = open(path, encoding='utf-8').read()
    for m in re.finditer(r'class="n[^"]*">([0-9,]+)</span><span class="t">([^<]*)', s):
        if needle in m.group(2):
            return m.group(1).replace(',', '')
    return None

def proof_stat(path, needle):
    s = open(path, encoding='utf-8').read()
    for m in re.finditer(r'class="n[^"]*">([0-9,]+)</span><span class="t">([^<]*)', s):
        if needle in m.group(2):
            return m.group(1).replace(',', '')
    return None

checks = [
    ('commands refused',
     first_stat('site/index.html', 'commands refused'),
     proof_stat('site/catches.html', 'commands refused')),
    ('commits in this repository',
     first_stat('site/index.html', 'commits in this repository'),
     proof_stat('site/patch-notes.html', 'commits')),
]
bad = 0
for name, a, b in checks:
    if a is None or b is None:
        print('UNREADABLE %-28s overview=%s other=%s' % (name, a, b)); bad += 1
    elif a != b:
        print('DISAGREE   %-28s overview=%s other=%s' % (name, a, b)); bad += 1
    else:
        print('AGREE      %-28s %s' % (name, a))
sys.exit(1 if bad else 0)
PY
)
rc=$?
echo "$CROSS" | sed 's/^/        /'
if [ $rc -eq 0 ]; then ok "the overview and the pages it summarises agree"
else bad "the overview disagrees with the page built from the same source"; fi
echo

echo "  pass $pass   fail $fail"
[ "$fail" -eq 0 ] && echo "  site claims: GREEN" || echo "  site claims: RED"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
