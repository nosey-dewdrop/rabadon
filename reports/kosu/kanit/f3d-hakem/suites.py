import re, sys
pat = re.compile(r'^([a-z0-9_ ()/.-]+):\s*(\d+)\s*(?:passed|ok)\b', re.I)

def load(p):
    d = {}
    for line in open(p, errors='replace'):
        m = pat.match(line.rstrip())
        if m:
            d[m.group(1).strip()] = int(m.group(2))
    return d

a = load(sys.argv[1])
b = load(sys.argv[2])
print('base suites', len(a), 'head suites', len(b))
for k in sorted(set(a) | set(b)):
    va, vb = a.get(k), b.get(k)
    if va != vb:
        print(('SHRANK ' if (va is not None and vb is not None and vb < va) else
               'GONE   ' if vb is None else
               'NEW    ' if va is None else 'GREW   '), k, va, '->', vb)
