#!/usr/bin/env python3
"""K2 -- separate the two causes that keep `repeat` at zero.

The F3e arbiter measured 81 sessions / 1766 moves and 0/81 sessions able to
fire `repeat`, then said the number is OVER-DETERMINED: two independent
blockers were present at once and nobody had split them.

native/signals.h:100-129 -- the rule, verbatim in structure:

    seen   = moves in the last REPEAT_WINDOW(20) whose sig == last.sig
    failed = of those, the ones with claimed_rc == 1
    fires when seen >= REPEAT_MIN(3) AND failed >= 2

So there are exactly two clauses and exactly two blockers:

  (i)  EXACT SIGNATURE  -- `seen` counts byte-identical command signatures, so
       twelve wordings of one command are twelve signatures and `seen` stays 1.
  (ii) NO COMPLETION FOR A FAILED CALL -- claimed_rc is only ever assigned on
       the completion branch, and until F3e a failing tool call never produced
       one. Every failing move stayed at claimed_rc = -1, so `failed` could not
       reach 2 no matter how the moves repeated.

This script asks each clause SEPARATELY over the corpus, so the answer is not
one number that two causes can hide behind:

  A  sessions where clause 1 alone is satisfiable  (seen >= 3, ignore `failed`)
     -> the ceiling if (ii) were perfectly fixed and every repeat failed.
  B  sessions where clause 2 alone is satisfiable  (>= 2 moves with
     claimed_rc == 1, ignoring whether they share a signature)
     -> the ceiling if (i) were perfectly relaxed.
  C  both, i.e. what the shipped rule would actually fire on.

It reads the rings through the shipped exporter and NEVER writes to them.
"""
import glob, json, os, subprocess, sys, collections

REPEAT_MIN, REPEAT_WINDOW = 3, 20
ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(ROOT, "..", "..", "..", ".."))
AUDIT = os.path.join(REPO, "native", "rabadon-audit")

SOURCES = [
    ("snapshot", os.path.expanduser("~/.rabadon-korpus-snapshot-20260826/sessions/*.moves.bin")),
    ("machine",  os.path.expanduser("~/.rabadon/sessions/*.moves.bin")),
    ("project",  os.path.join(REPO, ".rabadon", "sessions", "*.moves.bin")),
]

def load(path):
    p = subprocess.run([AUDIT, "--export", path], capture_output=True, text=True)
    if p.returncode != 0:
        return None
    out = []
    for line in p.stdout.splitlines():
        line = line.strip()
        if line:
            try: out.append(json.loads(line))
            except Exception: pass
    out.sort(key=lambda m: m.get("seq", 0))
    return out

sessions = []           # (label, moves)
unreadable = 0
for label, pat in SOURCES:
    for f in sorted(glob.glob(pat)):
        mv = load(f)
        if mv is None: unreadable += 1; continue
        if mv: sessions.append((label + ":" + os.path.basename(f), mv))

tot_moves = sum(len(m) for _, m in sessions)

A = B = C = 0
a_names, b_names, c_names = [], [], []
sig_hist = collections.Counter()      # max identical-sig count inside a window
fail_moves = 0
open_moves = 0
for name, m in sessions:
    n = len(m)
    best_seen, best_failed, both = 0, 0, False
    for i in range(n):
        lo = max(0, i + 1 - REPEAT_WINDOW)
        sig = m[i].get("sig")
        win = m[lo:i + 1]
        seen = sum(1 for x in win if x.get("sig") == sig)
        failed = sum(1 for x in win if x.get("sig") == sig and x.get("claimed_rc") == 1)
        best_seen = max(best_seen, seen)
        best_failed = max(best_failed, failed)
        if seen >= REPEAT_MIN and failed >= 2: both = True
    sig_hist[best_seen] += 1
    nfail = sum(1 for x in m if x.get("claimed_rc") == 1)
    fail_moves += nfail
    open_moves += sum(1 for x in m if x.get("claimed_rc") == -1)
    if best_seen >= REPEAT_MIN: A += 1; a_names.append((name, best_seen))
    if nfail >= 2:              B += 1; b_names.append((name, nfail))
    if both:                    C += 1; c_names.append(name)

S = len(sessions)
print("== K2: `repeat` neden ates etmiyor -- iki sebep AYRI AYRI olculdu")
print("kaynak halkalari:", ", ".join("%s=%d" % (l, len(glob.glob(p))) for l, p in SOURCES))
print("okunan oturum = %d, okunamayan halka = %d, toplam hamle = %d" % (S, unreadable, tot_moves))
print("kural: seen >= %d (ayni TAM imza, son %d hamle) VE failed >= 2 (claimed_rc == 1)"
      % (REPEAT_MIN, REPEAT_WINDOW))
print()
print("A) YALNIZ 1. sart (tam-imza tekrari >= %d), failed yok sayildi : %d / %d oturum" % (REPEAT_MIN, A, S))
print("B) YALNIZ 2. sart (>= 2 hamle claimed_rc == 1), imza yok sayildi: %d / %d oturum" % (B, S))
print("C) IKISI BIRDEN = sevk edilen kuralin gercekten atesledigi        : %d / %d oturum" % (C, S))
print()
print("hamle duzeyinde: claimed_rc==1 (basarisiz, KAPANMIS) = %d, claimed_rc==-1 (hic kapanmamis) = %d, toplam = %d"
      % (fail_moves, open_moves, tot_moves))
print()
print("oturum basina en yuksek 'ayni imza pencerede kac kez' dagilimi:")
for k in sorted(sig_hist):
    print("   seen=%-3d -> %d oturum" % (k, sig_hist[k]))
if a_names:
    print("\n1. sarti saglayan oturumlar (ad, en yuksek seen):")
    for nm, s in sorted(a_names, key=lambda t: -t[1])[:12]: print("   %-52s seen=%d" % (nm, s))
if b_names:
    print("\n2. sarti saglayan oturumlar (ad, kapanmis basarisiz hamle sayisi):")
    for nm, s in sorted(b_names, key=lambda t: -t[1])[:12]: print("   %-52s failed=%d" % (nm, s))
if c_names:
    print("\nHER IKI SARTI saglayan oturumlar:")
    for nm in c_names: print("   " + nm)

# ---------------------------------------------------------------------------
# D) THE DECISIVE COUNTERFACTUAL. K1 made a failing call produce a completion,
# so moves that used to stay at claimed_rc = -1 now close with a real rc. The
# question the F3e arbiter left open is whether that ALONE unblocks `repeat`.
# Answered as generously as the data allows: pretend EVERY never-closed move
# was a failure (claimed_rc = -1 -> 1). That is an upper bound -- the true
# number cannot be higher -- so if it is still 0, cause (ii) was never the
# binding constraint and the whole of the block is cause (i).
D = 0; d_names = []
for name, m in sessions:
    n = len(m)
    for i in range(n):
        lo = max(0, i + 1 - REPEAT_WINDOW)
        sig = m[i].get("sig"); win = m[lo:i + 1]
        seen = sum(1 for x in win if x.get("sig") == sig)
        failed = sum(1 for x in win if x.get("sig") == sig and x.get("claimed_rc") in (1, -1))
        if seen >= REPEAT_MIN and failed >= 2:
            D += 1; d_names.append(name); break
print()
print("D) UST SINIR: her KAPANMAMIS hamle aslinda basarisizdi varsayilirsa")
print("   (yani K1 onarimi gecmise donuk uygulanmis gibi)              : %d / %d oturum" % (D, len(sessions)))
for nm in d_names[:12]: print("   " + nm)

# ---------------------------------------------------------------------------
# E) A NUMBER FOR F4, MEASURED HERE AND CHANGED NOWHERE. The detector is not
# touched: this only asks what clause 1 would count if a signature were the
# command's FIRST TOKEN instead of the whole command line. It is the cheapest
# possible loosening and therefore a floor for any semantic signature F4 picks.
def head(mv):
    raw = (mv.get("raw") or "").strip()
    return raw.split()[0] if raw else mv.get("sig")
for label, keyf in (("ilk token", head),):
    E = 0; both_e = 0
    for name, m in sessions:
        n = len(m); hit = False; hit2 = False
        for i in range(n):
            lo = max(0, i + 1 - REPEAT_WINDOW)
            k = keyf(m[i]); win = m[lo:i + 1]
            seen = sum(1 for x in win if keyf(x) == k)
            failed = sum(1 for x in win if keyf(x) == k and x.get("claimed_rc") == 1)
            if seen >= REPEAT_MIN: hit = True
            if seen >= REPEAT_MIN and failed >= 2: hit2 = True
        E += hit; both_e += hit2
    print()
    print("E) F4'E DEVREDILEN OLCUM (dedektor DEGISTIRILMEDI, yalniz olculdu):")
    print("   imza '%s' olsaydi -> 1. sart: %d / %d oturum, iki sart birden: %d / %d"
          % (label, E, len(sessions), both_e, len(sessions)))
