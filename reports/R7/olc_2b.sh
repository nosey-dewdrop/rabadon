#!/usr/bin/env bash
# olc_2b.sh — 2b LATANS OLCUMUNUN YUK KAPISI
#
# Operator karari, tur 18 CEVAP 1 (`reports/kosu/18.operator.md`):
#   "2b olcumu, muhurlu accept.sh'a DOKUNMADAN, bir ON-KOSULA baglanir
#    (accept.sh'i cagiran sarmalayicida, kendi dosyasinda)."
#
# NEDEN VAR: 2b bugune kadar UC kez olculdu (8148,9 / 1385,2 / 2443,8 us) ve
# UCU DE yuk altinda alindi. Uc sayi birbirinden 6 kat farkli; hicbiri 1000 us
# tavanina karsi okunamaz. Kirli makinede alinan latans sayisi delil degildir.
#
# NE YAPAR:
#   1. 1 dk yuk ortalamasi UC ARDISIK ornekte de esigin altina inene kadar
#      bekler (60 sn araliklarla yoklar, tavan 90 dk).
#   2. Tavan dolarsa 2b KOSULMAZ. "Bu makinede olculemedi, yuk X" diye kayda
#      gecer ve KIRMIZI KALIR. SAYI UYDURULMAZ. (Yasa 7 / CLAUDE.md 8.)
#   3. Olcum alinirsa, sayinin YANINA o anki 1/5/15 dk yuk ortalamalari ve en
#      cok CPU yiyen 3 surec YAZILIR. Yuk kaydi olmayan latans sayisi
#      GECERSIZDIR.
#
# MUHUR: bu betik accept.sh'i CAGIRIR, DEGISTIRMEZ. KOSU-RABADON-2.md §A1
# "accept.sh oldugu gibi kalir" karari ihlal edilmez.
set -u
cd "$(git rev-parse --show-toplevel)"

# LOCALE ZIRHI — BETIGIN TAMAMI ICIN, tek yerde. Makine tr_TR locale'inde.
# Iki ayri tuzak var ve IKISI de olculdu (24.08):
#   1. `sysctl -n vm.loadavg` yuku VIRGULLU basar -> "{ 8,06 5,67 7,07 }"
#   2. Daha sinsisi: awk DA locale'e uyar. tr_TR altinda awk icin ondalik
#      ayrac VIRGULdur, yani `echo 7.81 | awk '{print $1+0}'` -> 7 verir
#      (noktadan sonrasi duser). Yalniz sysctl'i C'ye almak YETMEZ; kapi
#      sessizce YANLIS sayiyla karar verir.
# Bu yuzden LC_ALL butun betige export edilir: sysctl, awk, ps, date hepsi C.
export LC_ALL=C LC_NUMERIC=C

ESIK=${ESIK:-2.0}          # 1 dk yuk tavani
ORNEK=${ORNEK:-3}          # kac ardisik temiz ornek gerekiyor
ARA=${ARA:-60}             # ornekler arasi saniye
TAVAN=${TAVAN:-5400}       # 90 dk
LOG=reports/R7/YUK-2B-BEKLEME.log
OUT=reports/R7/accept.out
NCPU=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 1)

# LOCALE ZIRHI: makine tr_TR locale'inde ve hem `uptime` hem `sysctl` yuku
# VIRGULLU basiyor ("8,06"). LC_ALL=C olmadan awk bunu 8 okur (virguldan
# sonrasi duser) — yani kapi YANLIS yonde, GEVSEK yanilir. Olculdu 24.08:
#   sysctl -n vm.loadavg          -> { 8,06 5,67 7,07 }
#   LC_ALL=C sysctl -n vm.loadavg -> { 8.06 5.67 7.07 }
yuk(){ sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' \
       || uptime | sed 's/.*average[s]*://' | tr -d ','; }
yuk1(){ yuk | awk '{print $1+0}'; }
kucuk(){ awk -v a="$1" -v b="$2" 'BEGIN{exit !(a<b)}'; }

kayit(){ printf '%s  %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$*" | tee -a "$LOG"; }

baglam(){   # olcumun yanina giden kirlilik kaydi — bu olmadan sayi gecersiz
  echo "### olcum baglami — $(date +%Y-%m-%dT%H:%M:%S)"
  echo "cekirdek (hw.ncpu) : $NCPU"
  echo "yuk 1/5/15 dk      : $(yuk)"
  echo "en cok CPU yiyen 3 surec:"
  ps -Ao pcpu,pid,comm -r 2>/dev/null | sed -n '2,4p' | sed 's/^/  /'
  # B1.9: latans olcen tur, olcumden ONCE artik surec olmadigini DOGRULAR
  echo "artik surec kontrolu (B1.9):"
  for p in pytest pip ctest rabadon-gated rabadon-gate; do
    printf '  %-16s %s\n' "$p" "$(pgrep -c -f "$p" 2>/dev/null || echo 0)"
  done
}

kayit "2b yuk kapisi basladi: esik=$ESIK ardisik=$ORNEK ara=${ARA}s tavan=${TAVAN}s cekirdek=$NCPU"
kayit "baslangic yuku: $(yuk)"

gecen=0; temiz=0
while [ "$gecen" -lt "$TAVAN" ]; do
  L="$(yuk1)"
  if kucuk "$L" "$ESIK"; then
    temiz=$((temiz+1))
    kayit "ornek $temiz/$ORNEK TEMIZ (1dk yuk $L < $ESIK)"
    [ "$temiz" -ge "$ORNEK" ] && break
  else
    [ "$temiz" -gt 0 ] && kayit "sayac SIFIRLANDI (yuk $L >= $ESIK) — ardisiklik sarti"
    temiz=0
    kayit "bekleniyor: 1dk yuk $L >= $ESIK  (gecen ${gecen}s/${TAVAN}s)"
  fi
  sleep "$ARA"; gecen=$((gecen+ARA))
done

if [ "$temiz" -lt "$ORNEK" ]; then
  kayit "TAVAN DOLDU (${TAVAN}s) — 2b KOSULMADI."
  { echo; echo "== 2b OLCULEMEDI — $(date +%Y-%m-%dT%H:%M:%S)"
    echo "Sebep: ${TAVAN}s boyunca 1 dk yuk ortalamasi $ORNEK ardisik ornekte"
    echo "       $ESIK esiginin altina INMEDI. Kirli makinede latans olcumu"
    echo "       delil degildir; SAYI UYDURULMADI. 2b KIRMIZI KALIR."
    baglam
  } >> reports/R7/YUK-2B.md
  kayit "kayit reports/R7/YUK-2B.md'ye yazildi. 2b kirmizi kalir."
  exit 3
fi

kayit "YUK KAPISI ACILDI ($ORNEK ardisik ornek < $ESIK) — accept.sh kosuluyor"
{ echo; echo "== 2b OLCUM BAGLAMI (kapi acildi) — $(date +%Y-%m-%dT%H:%M:%S)"; baglam; } >> reports/R7/YUK-2B.md
# ATOMIK YAZIM: accept.sh'in ciktisi ONCE gecici dosyaya gider, ancak betik
# KENDI BASINA bittiginde accept.out'a tasinir. Neden: bu betik disaridan
# `timeout` ile sarilir (B1.9); tavan accept.sh'in ORTASINDA dolarsa dogrudan
# tee edilen accept.out YARIM kalir ve yarim bir kabul ciktisi "23 yesil / 3
# kirmizi" gibi OKUNUR — kesilmis oldugu hicbir yerde yazmaz. Yarim kabul
# ciktisi, yanlis kabul ciktisindan farksizdir.
TMPOUT="$(mktemp -t rb2b)"
bash reports/R7/accept.sh 2>&1 | tee "$TMPOUT"
rc=${PIPESTATUS[0]}
if grep -q 'R7 acceptance:' "$TMPOUT"; then
  mv "$TMPOUT" "$OUT"
else
  kayit "UYARI: accept.sh kapanis satirini ('R7 acceptance:') basmadan bitti —"
  kayit "       cikti YARIM sayilir, $OUT DEGISTIRILMEDI. Ham cikti: $TMPOUT"
  rc=4
fi
{ echo "== olcum SONRASI baglam (kayma kontrolu)"; baglam; } >> reports/R7/YUK-2B.md
kayit "accept.sh bitti (rc=$rc); cikti $OUT, baglam reports/R7/YUK-2B.md"
exit "$rc"
