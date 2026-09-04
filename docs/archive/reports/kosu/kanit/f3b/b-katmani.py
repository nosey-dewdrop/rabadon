#!/usr/bin/env python3
"""b-katmani.py — KOSU §F3 layer (b), "did the agent read it", measured.

(b) says: an INJECT line only proves rabadon WROTE something. What proves the
agent USED it is that the signature of the first move AFTER the injection is
not the signature that was repeating BEFORE it. This script asks that question
of the evidence that exists on this machine, and it is written to be able to
answer NO. Read-only: it opens the ledger and the move rings and writes nothing.

It reads the ledger (~/.rabadon/spool/*.jsonl) for INJECT events, then locates
each session's move ring and compares the signature either side of the move the
injection rode on (`mseq`).

Ring format is native/moves.h: 4096-byte header ("RBMV1", count, nextSeq) then
CAP=200 fixed 320-byte records. Parsed here rather than through the binary on
purpose — a measurement that runs through the thing being measured is not an
independent measurement.

Run:  python3 reports/kosu/kanit/f3b/b-katmani.py
"""
import json, glob, os, struct, hashlib

CAP, REC, HDR = 200, 320, 4096


def skey(sid):
    """session_key() from gate.cpp: first 16 safe chars + sha256[:12]."""
    safe = ''.join(c if (c.isalnum() or c in '-_.') else '_' for c in sid)[:16] or 's'
    return safe + '-' + hashlib.sha256(sid.encode()).hexdigest()[:12]


def ring(path):
    b = open(path, 'rb').read()
    if len(b) < HDR or b[:5] != b'RBMV1':
        return None, []
    count, _next = struct.unpack_from('<qq', b, 8)
    body, out = b[HDR:], []
    n = min(count, CAP)
    for i in range(n):
        idx = (count - n + i) % CAP
        r = body[idx * REC:(idx + 1) * REC]
        if len(r) < REC:
            continue
        seq, ts, rc, suite, _asserts, _tool = struct.unpack_from('<qqiiii', r, 0)
        g = lambda o, c: r[o:o + c].split(b'\0')[0].decode('utf8', 'replace')
        out.append(dict(seq=seq, ts=ts, rc=rc, suite=suite,
                        sig=g(40, 17), err=g(57, 17), path=g(84, 140), raw=g(224, 96)))
    return count, out


def main():
    inj = []
    for f in sorted(glob.glob(os.path.expanduser('~/.rabadon/spool/*.jsonl'))):
        for line in open(f, encoding='utf8', errors='replace'):
            if '"ev":"INJECT"' not in line:
                continue
            try:
                o = json.loads(line)
            except Exception:
                continue
            if o.get('ev') == 'INJECT':
                inj.append(o)

    judgeable = [o for o in inj if o.get('mseq') is not None and o.get('err')]
    print(f'INJECT events on the ledger: {len(inj)}')
    print(f'  carrying mseq+err (judgeable at all): {len(judgeable)}')

    found = judged = changed = 0
    for o in inj:
        sid, ms, err = o.get('sess', ''), o.get('mseq'), o.get('err')
        if not sid or ms is None or not err:
            continue
        k = skey(sid)
        hits = (glob.glob(os.path.expanduser(f'~/damla_projects_2026/*/.rabadon/sessions/{k}.moves.bin')) +
                glob.glob(os.path.expanduser(f'~/damla_projects_2026/*/*/.rabadon/sessions/{k}.moves.bin')) +
                glob.glob(os.path.expanduser(f'~/.rabadon-korpus-snapshot-20260826/sessions/{k}.moves.bin')))
        if not hits:
            print(f'  MISS    sess={sid[:12]} signal={o.get("signal")} mseq={ms} — no move ring on this machine')
            continue
        found += 1
        _count, recs = ring(hits[0])
        before = [r for r in recs if r['seq'] <= ms]
        after = [r for r in recs if r['seq'] > ms and (r['raw'] or r['sig'])]
        if not before or not after:
            print(f'  NOJUDGE sess={sid[:12]} ring holds {len(recs)} records, '
                  f'{len(before)} at-or-before mseq and {len(after)} after — '
                  f'the CAP={CAP} ring rolled past the injection')
            continue
        judged += 1
        prev, nxt = before[-1]['sig'], after[0]['sig']
        same = prev == nxt
        if not same:
            changed += 1
        print(f'  JUDGED  sess={sid[:12]} signal={o.get("signal")} '
              f'sig_before={prev} sig_after={nxt} -> '
              f'{"SAME (the injection did not move it)" if same else "DIFFERENT (the next move changed)"}')

    print(f'\n(b) rings found {found}/{len(inj)}, judgeable {judged}, signature changed {changed}')
    if judged == 0:
        print('(b) NOT MEASURED — n=0. The per-injection reason is printed above. '
              'n=0 is not a pass and must never be quoted as one.')


if __name__ == '__main__':
    main()
