#!/usr/bin/env bash
# scoreboard.sh — kuzey yıldızına göre neredeyiz.
#
# Her faz sınırında koşar, aynı sekiz sayıyı üretir, reports/scoreboard.tsv'ye
# EKLER (üzerine yazmaz). Kayma bir diff olarak görünür.
#
# TEK KURAL: ölçemediği şeye 0 yazmaz, ? yazar.
#   Ölçülmemiş = kanıtlanmamış. Eksik ölçüm, gerçek sıfır gibi görünmemeli —
#   bu projenin kendi standardı, tabelası da ona uymalı.

set -u
ROOT="${1:-$PWD}"
OUT="$ROOT/reports/scoreboard.tsv"
PHASE="${PHASE:-?}"
mkdir -p "$(dirname "$OUT")"

q() { [ -n "${1:-}" ] && [ "${1}" != "" ] && echo "$1" || echo "?"; }

# 1. cheat kolu — kaç aile
CHEAT=$(python3 - "$ROOT" <<'P' 2>/dev/null || echo ""
import json,sys
try:
    d=json.load(open(sys.argv[1]+"/site/measured.json"))
    print(d["corpus.cheats_refused"]["value"]["families"])
except Exception: print("")
P
)

# 2. dürüst kol — kaç doğrulanmış vaka (kırmızı+yeşil ikisi de koşmuş)
HONEST=$(find "$ROOT" -name 'case.env' -path '*honest*' 2>/dev/null | wc -l | tr -d ' ')
[ "$HONEST" = "0" ] && HONEST=""

# 3. VAHŞİDE tutulan tamir — planted değil. Şu an 0, ve 0 kalmalı ta ki olana dek.
WILD=$(grep -rhoE '"wild_repairs_held"\s*:\s*[0-9]+' "$ROOT/site/measured.json" 2>/dev/null | grep -oE '[0-9]+$' | head -1)

# 4. saha: durdurma ve yanlış red
STOPS=$(python3 - "$ROOT" <<'P' 2>/dev/null || echo ""
import json,sys
try:
    d=json.load(open(sys.argv[1]+"/site/measured.json"))
    print(d["field.stop"]["value"]["total"])
except Exception: print("")
P
)
WRONG=$(python3 - "$ROOT" <<'P' 2>/dev/null || echo ""
import json,sys
try:
    d=json.load(open(sys.argv[1]+"/site/measured.json"))
    print(d["field.wrong_refusals"]["value"])
except Exception: print("")
P
)

# 5. YÜZEY: kullanıcıya görünen verb sayısı. Bu sayı ARTMAMALI.
#    Artıyorsa kapsam kayması var.
VERBS=$(grep -cE '^## `rabadon ' "$ROOT/docs/commands.md" 2>/dev/null)

# 6. SEANS MALİYETİ: red mesajlarının ortalama uzunluğu (byte).
#    why+fix <= 200 hedefi. Bu sayı DÜŞMELİ.
WHYLEN=$(python3 - "$ROOT" <<'P' 2>/dev/null || echo ""
import json,glob,sys,os
tot=n=0
for f in glob.glob(os.path.join(sys.argv[1],"**",".rabadon","guard.json"),recursive=True):
    try: d=json.load(open(f))
    except Exception: continue
    for grp in d.values():
        if not isinstance(grp,list): continue
        for r in grp:
            if isinstance(r,dict) and "why" in r:
                tot+=len(r.get("why",""))+len(r.get("fix","")); n+=1
print(tot//n if n else "")
P
)

# 7. TAMİR SINIFLANDIRMASI: sonucu bilinen tamir denemesi oranı.
#    Faz 1'den önce ? olmalı. Sonra %100'e gitmeli.
CLASSED=$(grep -c 'repair_class' "$ROOT/reports/phase-1/discards.txt" 2>/dev/null)

# 8. YENİDEN ÜRETİLEBİLİRLİK: korpus temiz makinede çekilebiliyor mu
REPRO=$([ -f "$ROOT/../rabadon-corpus/fetch.sh" ] && echo yes || \
        ([ -f "$ROOT/corpus/fetch.sh" ] && echo yes || echo ""))

TS=$(date -u +%Y-%m-%dT%H:%MZ)
[ -s "$OUT" ] || printf 'ts\tphase\tcheat\thonest\twild_held\tstops\twrong\tverbs\twhy_len\tclassed\trepro\n' > "$OUT"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$TS" "$PHASE" "$(q "$CHEAT")" "$(q "$HONEST")" "$(q "$WILD")" "$(q "$STOPS")" \
  "$(q "$WRONG")" "$(q "$VERBS")" "$(q "$WHYLEN")" "$(q "$CLASSED")" "$(q "$REPRO")" >> "$OUT"

if command -v column >/dev/null 2>&1; then column -t -s "$(printf '\t')" "$OUT"; else cat "$OUT"; fi

# ---- KAYMA KONTROLÜ -------------------------------------------------------
# Sadece iki satır varsa kıyas yok. Üçten itibaren yön kontrol edilir.
python3 - "$OUT" <<'P'
import sys,csv
rows=list(csv.DictReader(open(sys.argv[1]),delimiter='\t'))
if len(rows)<2: sys.exit(0)
a,b=rows[-2],rows[-1]
def num(x):
    try: return float(x)
    except Exception: return None
# yön: bu sayılar ASLA geri gitmemeli
up=["cheat","honest","wild_held","classed"]
# bu sayılar ASLA artmamalı
down=["verbs","why_len","wrong"]
bad=[]
for k in up:
    x,y=num(a[k]),num(b[k])
    if x is not None and y is not None and y<x: bad.append(f"{k}: {a[k]} -> {b[k]} (geri gitti)")
for k in down:
    x,y=num(a[k]),num(b[k])
    if x is not None and y is not None and y>x: bad.append(f"{k}: {a[k]} -> {b[k]} (arttı)")
print()
if bad:
    print("KAYMA VAR — faz kendi testini geçse bile koşu DURUR:")
    for m in bad: print("  •",m)
    sys.exit(1)
print("kayma yok.")
P
