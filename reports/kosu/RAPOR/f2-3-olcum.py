#!/usr/bin/env python3
# f2-3-olcum.py — per-signal measurement over the FROZEN corpus snapshot.
#
# WHAT THIS IS. A re-implementation of native/signals.h detect() in python,
# replayed over every prefix of every session's move record, so that each
# signal's firing count n can be counted and every firing can be hand-labelled.
# The detectors themselves are NOT modified and NOT recompiled by this script.
#
# WHY A RE-IMPLEMENTATION. rabadon-gate computes signals in silent mode and does
# not print them; rabadon-audit has no signals subcommand (`rabadon-audit --help`).
# The only read door out of the ring is `rabadon-audit --export`, which is what
# this script consumes. The re-implementation is line-for-line from
# native/signals.h at commit 9cba3cd and the thresholds are copied, not chosen.
#
# INPUT IS READ-ONLY. The snapshot directory is never opened for writing.
#
#   usage: python3 f2-3-olcum.py <audit-binary> <snapshot-dir>

import json, os, subprocess, sys, struct, collections, glob

AUDIT = sys.argv[1] if len(sys.argv) > 1 else '/tmp/f23bin/rabadon-audit'
SNAP  = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser('~/.rabadon-korpus-snapshot-20260826')
SESS  = os.path.join(SNAP, 'sessions')

# thresholds — copied verbatim from native/signals.h
REPEAT_MIN, REPEAT_WINDOW = 3, 20
OSC_CYCLES = 3
ROOT_MIN_PATHS = 3
DRIFT_DIRS = 5
CAP = 200            # MOVES_CAP, native/moves_test.sh

def is_edit(m):  return m['tool'] in ('Edit', 'Write', 'MultiEdit')
def dir_of(p):   return p.rsplit('/', 1)[0] if '/' in p else '.'

def detect(m):
    """detect() over the whole list, asking only whether the NEWEST move
    completed a pattern. Mirrors rbsig::detect."""
    out = []
    if not m: return out
    last, n = m[-1], len(m)

    # 1. repeat
    seen = failed = 0; seqs = []
    for x in m[max(0, n - REPEAT_WINDOW):]:
        if x['sig'] == last['sig']:
            seen += 1; seqs.append(x['seq'])
            if x['claimed_rc'] == 1: failed += 1
    if seen >= REPEAT_MIN and failed >= 2:
        out.append(('repeat', seqs))

    # 2. oscillation
    if is_edit(last) and last['path']:
        same = []
        for i in range(n - 1, -1, -1):
            if len(same) >= OSC_CYCLES * 2: break
            if is_edit(m[i]) and m[i]['path'] == last['path']: same.append(m[i])
        if len(same) == OSC_CYCLES * 2:
            a, b = same[0]['sig'], same[1]['sig']
            alt = a != b
            for i, x in enumerate(same):
                if not alt: break
                if x['sig'] != (b if i % 2 else a): alt = False
            if alt: out.append(('oscillation', [x['seq'] for x in same]))

    # 3. root_migration
    if last['err_sig']:
        sigs, seqs = set(), []
        for x in m:
            if x['err_sig'] == last['err_sig']:
                sigs.add(x['sig']); seqs.append(x['seq'])
        if len(sigs) >= ROOT_MIN_PATHS:
            out.append(('root_migration', seqs))

    # 4. scope_drift
    if is_edit(last) and last['path']:
        dirs = {dir_of(x['path']) for x in m if is_edit(x) and x['path']}
        if len(dirs) >= DRIFT_DIRS: out.append(('scope_drift', [last['seq']]))

    # 5. green_redefined — three sub-rules.
    # (a) and (b) both require a move whose `suite` field is 0 (a RED suite).
    # (c) requires two edits to one path where `asserts` FELL.
    # decides_green()/is_source() call rbclass::classify(), whose source file is
    # outside this card's read list. So the sub-rules are evaluated here as the
    # CLASSIFY-INDEPENDENT SUPERSET: the classify test is dropped, which can only
    # ADD firings, never remove them. If the superset is empty, the true count is
    # 0 and the missing classify cannot change that. If the superset is NOT
    # empty, the true count is unknown and this script says so.
    ga = gb = gc = []
    sup = []
    if is_edit(last):
        suite = -1
        for i in range(n - 1, -1, -1):
            if m[i]['suite'] != -1: suite = m[i]['suite']; break
        if suite == 0: sup.append(('green_redefined/a-superset', [last['seq']]))
    if last['suite'] == 1:
        red = None
        for i in range(n - 2, -1, -1):
            if m[i]['suite'] == 0: red = i; break
            if m[i]['suite'] == 1: break
        if red is not None: sup.append(('green_redefined/b-superset', [last['seq']]))
    if is_edit(last) and last['asserts'] >= 0:
        for i in range(n - 2, -1, -1):
            if not is_edit(m[i]) or m[i]['path'] != last['path'] or m[i]['asserts'] < 0:
                continue
            if last['asserts'] < m[i]['asserts']:
                sup.append(('green_redefined/c-superset', [m[i]['seq'], last['seq']]))
            break
    return out + sup

# ---------------------------------------------------------------------------
def hdr_count(path):
    """ring header: 8-byte magic 'RBMV1\\0\\0\\0', then u64 total-ever-written."""
    with open(path, 'rb') as f: b = f.read(16)
    assert b[:5] == b'RBMV1', path
    return struct.unpack('<Q', b[8:16])[0]

def main():
    files = sorted(glob.glob(os.path.join(SESS, '*.moves.bin')))
    corpus = {}
    total_recs = total_count = 0
    fire = collections.defaultdict(list)   # signal -> [(session, seqs)]
    for f in files:
        out = subprocess.run([AUDIT, '--export', f], capture_output=True, text=True)
        recs = []
        bad = 0
        for line in out.stdout.splitlines():
            try: recs.append(json.loads(line))
            except Exception: bad += 1
        assert bad == 0, (f, bad)
        corpus[f] = recs
        total_recs += len(recs)
        total_count += hdr_count(f)
        for k in range(1, len(recs) + 1):
            for name, seqs in detect(recs[:k]):
                fire[name].append((f, recs[k - 1]['seq'], seqs))

    print('== CORPUS')
    print('sessions (*.moves.bin) :', len(files))
    print('records on disk        :', total_recs)
    print('header count total     :', total_count)
    print('LOST to the ring cap   :', total_count - total_recs)
    ts = [r['ts'] for rs in corpus.values() for r in rs]
    import datetime as dt
    fmt = lambda t: dt.datetime.utcfromtimestamp(t / 1000).strftime('%Y-%m-%d %H:%M UTC')
    print('date range             :', fmt(min(ts)), '->', fmt(max(ts)))
    print('unparsable export lines:', 0)

    print('\n== PER-SIGNAL n (firings, one per move that completed the pattern)')
    for name in ('repeat', 'oscillation', 'root_migration', 'scope_drift',
                 'green_redefined/a-superset', 'green_redefined/b-superset',
                 'green_redefined/c-superset'):
        hits = fire.get(name, [])
        print(f'{name:28s} n = {len(hits)}')
        for h in hits:
            print(f'    {os.path.basename(h[0])}  newest_seq={h[1]}  seqs={h[2]}')

    print('\n== SESSIONS THAT PRODUCED FIRINGS (for hand-labelling)')
    for name, hits in sorted(fire.items()):
        s = collections.Counter(os.path.basename(h[0]) for h in hits)
        print(name, dict(s))

if __name__ == '__main__':
    main()
