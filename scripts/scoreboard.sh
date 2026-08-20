#!/usr/bin/env bash
# scoreboard.sh — kuzey yıldızına göre neredeyiz.
#
# Her faz sınırında koşar, aynı sekiz sayıyı üretir, reports/scoreboard.tsv'ye
# EKLER (üzerine yazmaz). Kayma bir diff olarak görünür.
#
# TEK KURAL: ölçemediği şeye 0 yazmaz, ? yazar.
#   Ölçülmemiş = kanıtlanmamış. Eksik ölçüm, gerçek sıfır gibi görünmemeli —
#   bu projenin kendi standardı, tabelası da ona uymalı.

#
# İKİNCİ KURAL: bir metriğin TANIMI değişirse eski satırlarla kıyaslanmaz.
#   Kayma kontrolü "bu sayı geri gitmesin" diyor; sayının ne olduğu değişince
#   o kıyas anlamsızlaşır ve sahte alarm üretir. Tanım değişince aşağıdaki
#   DEFS artırılır, eski dosya yanına kaydırılır (silinmez), yeni dosya başlar.
#   Ölçüm tanımını değiştirip eski çizgiyle övünmek de, sahte alarmla durmak da
#   aynı hatanın iki yüzü.
DEFS=2   # 1 -> 2: cheat/stops sözlük yerine sayı okunuyor, verbs fiil sayıyor,
         #         why_len "allow" alanını da topluyor (bkz. reports/phase-0/review.md)

set -u
ROOT="${1:-$PWD}"
OUT="$ROOT/reports/scoreboard.tsv"
DEFSFILE="$ROOT/reports/scoreboard.defs"
PHASE="${PHASE:-?}"
mkdir -p "$(dirname "$OUT")"

OLDDEFS=$(cat "$DEFSFILE" 2>/dev/null || echo "1")
if [ -s "$OUT" ] && [ "$OLDDEFS" != "$DEFS" ]; then
  ARCHIVE="$OUT.defs$OLDDEFS.old"
  mv "$OUT" "$ARCHIVE"
  echo "ÖLÇÜM TANIMI DEĞİŞTİ ($OLDDEFS -> $DEFS)." >&2
  echo "  Eski satırlar silinmedi, $ARCHIVE içinde." >&2
  echo "  Yeni dosya sıfırdan başlıyor; tanım değişmeden önceki sayılarla" >&2
  echo "  kıyaslanmaz — o kıyas sahte alarm ya da sahte övünme üretir." >&2
fi
echo "$DEFS" > "$DEFSFILE"

q() { [ -n "${1:-}" ] && [ "${1}" != "" ] && echo "$1" || echo "?"; }

# Ortak okuyucu: measured.json'daki bir anahtarın "value"su. O value bazen
# düz sayı, bazen sözlük. Sözlükse alt anahtar aranır, sayıysa doğrudan alınır.
# Eskiden ikisi de sözlük varsayılıyordu; sayı olan iki metrik (cheats_refused,
# field.stop) her koşuda istisna atıp "?" yazdırıyordu — yani ölçülmüş iki
# sayı ölçülmemiş gibi görünüyordu ve kayma kontrolü o sütunlarda hiç çalışmadı.
measured() {  # measured <anahtar> [alt-anahtar]
  python3 - "$ROOT" "$1" "${2:-}" <<'P' 2>/dev/null || echo ""
import json,sys
root,key,sub=sys.argv[1],sys.argv[2],sys.argv[3]
try:
    d=json.load(open(root+"/site/measured.json"))
except Exception:
    print(""); sys.exit(0)
if key not in d:
    print(""); sys.exit(0)
v=d[key].get("value") if isinstance(d[key],dict) else None
if isinstance(v,dict):
    v=v.get(sub) if sub else None
elif isinstance(v,list):
    v=len(v) if not sub else None
print("" if v is None or isinstance(v,(dict,list)) else v)
P
}

# 1. cheat kolu — kaç aile reddedildi
CHEAT=$(measured corpus.cheats_refused families)

# 2. dürüst kol — kaç doğrulanmış vaka (kırmızı+yeşil ikisi de koşmuş)
HONEST=$(find "$ROOT" -name 'case.env' -path '*honest*' 2>/dev/null | wc -l | tr -d ' ')
[ "$HONEST" = "0" ] && HONEST=""

# 3. VAHŞİDE tutulan tamir — planted değil. Şu an ölçen bir şey yok:
#    measured.json'da "wild_repairs_held" anahtarı hiç yok, o yüzden "?".
#    0 YAZILMAZ — 0 "ölçtük, hiç yok" demek olurdu, oysa henüz kimse ölçmedi.
WILD=$(measured wild_repairs_held)

# 4. saha: durdurma ve yanlış red
STOPS=$(measured field.stop total)
WRONG=$(measured field.wrong_refusals)

# 5. YÜZEY: kullanıcıya görünen verb sayısı. Bu sayı ARTMAMALI.
#    Artıyorsa kapsam kayması var.
#    Başlık değil FİİL sayılır: "## `rabadon on | off | status | toggle`" tek
#    başlıkta dört fiil. Başlık sayarsan iki başlığı birleştirerek yüzey
#    küçülmeden sayıyı düşürebilirsin — ölçülen şeyi ölçmeyi bırakmadan
#    metriği iyileştirmek, tam da bu projenin reddettiği hamle.
VERBS=$(grep -oE '^## `rabadon [a-z |]+' "$ROOT/docs/commands.md" 2>/dev/null \
        | sed 's/^## `rabadon //' | tr '|' '\n' | tr -d ' ' | grep -c . )
[ "${VERBS:-0}" = "0" ] && [ ! -f "$ROOT/docs/commands.md" ] && VERBS=""

# 6. SEANS MALİYETİ: red mesajlarının ortalama uzunluğu (byte).
#    why+fix <= 200 hedefi. Bu sayı DÜŞMELİ.
#    guard.json'daki kuralların anahtarları: id/deny/why/allow/catches — "fix"
#    diye bir alan yok, "insanın bundan sonra ne yapacağı" alanının adı "allow".
#    Eskiden len(fix) hep 0 dönüyordu, yani hedefin yarısı hiç ölçülmüyordu.
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
                nxt=r.get("fix") or r.get("allow") or ""
                if not isinstance(nxt,str): nxt=str(nxt)
                tot+=len(r.get("why",""))+len(nxt); n+=1
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

# ---- ÖLÇÜLEMEYENİ SÖYLE ---------------------------------------------------
# "?" sessiz kalmamalı: hangi sütun neden ölçülemedi, stderr'e yazılır.
for pair in "cheat:$CHEAT" "honest:$HONEST" "wild_held:$WILD" "stops:$STOPS" \
            "wrong:$WRONG" "verbs:$VERBS" "why_len:$WHYLEN" "classed:$CLASSED" "repro:$REPRO"; do
  [ -z "${pair#*:}" ] && echo "  ? ${pair%%:*} — ölçülemedi (kaynak yok ya da beklenen şekilde değil)" >&2
done

# ---- KAYMA KONTROLÜ -------------------------------------------------------
# İki satırdan itibaren son iki satır kıyaslanır. Tek satırda kıyas yoktur.
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
