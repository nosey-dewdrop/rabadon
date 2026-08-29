import re

p = 'native/guard_lint_test.sh'
t = open(p, encoding='utf8').read()

old_start = 'RULES_TARGETS="$(python3 - <<\'PY\'\n'
i = t.index(old_start)
j = t.index(')"', t.index("\nPY\n", i)) + 2
old = t[i:j]

new = '''# THE TARGET NAME IS READ OUT OF THE MAKEFILE, NOT GUESSED FROM THE SOURCE
# NAME. It used to be `native/rabadon-` + the stem, and native/gate_bench.cpp
# includes rules.h while its target is called `native/gate_bench`. `make -q`
# answered "No rule to make target native/rabadon-gate_bench" and exited 2, the
# outer `if` read that as "the tree is not built", and the WHOLE empirical arm
# took the skip branch — silently, on every run, on a fully built tree, since
# the day it was written. Measured 2026-08-29. That is the defect this card is
# about, hiding inside a suite written to catch it. A source that no rule
# builds is now a failure with a name, not a target nobody can make.
RULES_TARGETS="$(python3 - <<'RTS'
import os, re
mk = re.sub(r'\\\\\\n\\s*', ' ', open('Makefile', encoding='utf8').read())
rules = {}
for line in mk.splitlines():
    m = re.match(r'^(native/[A-Za-z0-9_-]+)\\s*:\\s*(.*)$', line)
    if m:
        rules[m.group(1)] = m.group(2).split()
for f in sorted(os.listdir('native')):
    if not f.endswith('.cpp'):
        continue
    src = os.path.join('native', f)
    if not re.search(r'#\\s*include\\s+"rules\\.h"',
                     open(src, encoding='utf8', errors='replace').read()):
        continue
    hit = [t for t, pre in rules.items() if src in pre]
    print(hit[0] if hit else 'NORULE:' + src)
RTS
)"
NORULE="$(printf '%s\\n' "$RULES_TARGETS" | sed -n 's/^NORULE://p')"
if [ -n "$NORULE" ]; then
  bad "a source includes rules.h but no Makefile rule builds it, so nothing holds it to the header: $(printf '%s' "$NORULE" | tr '\\n' ' ')"
fi
RULES_TARGETS="$(printf '%s\\n' "$RULES_TARGETS" | grep -v '^NORULE:' || true)"'''

t = t[:i] + new + t[j:]
open(p, 'w', encoding='utf8').write(t)
print('patched')
