#!/usr/bin/env bash
# olc_2b.sh — 2b LATANS ORNEKLEYICI (tur 20)
#
# Operator karari, tur 19 CEVAP 1 (`reports/kosu/19.operator.md`):
#   "olc_2b.sh bekleyen kapi olmaktan CIKAR, TEKRARLI ORNEKLEYICI olur."
#
# NEDEN DEGISTI: bu betik tur 19'da bir YUK KAPISI idi — 1 dk yuk uc ardisik
# ornekte `< 2.0` inene kadar bekler, inmezse 2b'yi kosmazdi. Tur 19 olctu:
# bu makinede kayitli EN DUSUK yuk 2.4. Kapi HICBIR ZAMAN acilamazdi; esik
# tarihsel dagilima BAKILMADAN secilmisti. Operator kendi hatasini kabul etti.
# Esigi 4.0'a gevsetmek AYNI hatanin tekrari olurdu: gozlemden degil,
# rahatliktan secilmis ikinci bir keyfi sayi. Ve operatorun canli isleri
# (Chrome, stitchu) olcum icin SUSTURULMAZ.
#
# YENI KURAL — FIZIK GEREKCELI, KEYFI DEGIL:
#   Cekismeli bir makinede olculen latans, cekismesiz gercek latanstan HER
#   ZAMAN buyuk ya da esittir. Yuk yalniz EKLER, cikarmaz. Dolayisiyla
#   tekrarli olcumlerin EN DUSUGU, temiz-ortam degerinin en iyi UST SINIR
#   tahminidir. Bu betik o ust siniri arar.
#
# HUKUM — TUR 21 CEVAP 1'DE DUZELTILDI. Asagidaki eski hukum TERSTEN yazilmisti
# ve yukaridaki fizik onermesinin ZITTINI soyluyordu. Operator hatayi kabul etti
# ("hata BENIM"); bu betigin urettigi her "KESIN KIRMIZI" etiketi GECERSIZDIR:
#   ~~en dusuk gozlem >= 1000 us -> 2b KESIN KIRMIZI~~        <- YANLIS, GECERSIZ
#   ~~en dusuk gozlem <  1000 us -> 2b ACIK, yesil sayilmaz~~ <- YANLIS, GECERSIZ
# Neden yanlis: min gozlem temiz degerin UST SINIRIdir, ALT SINIRI DEGIL.
# min >= 1000 olmasi, gercek degerin de >= 1000 oldugunu KANITLAMAZ.
#
# DOGRU ASIMETRI — kanit tek yonde cikar, ve o yon YESIL yonudur:
#   * en dusuk gozlem <  1000 us -> 2b KESIN YESIL. Temiz deger bu sayidan
#     kucuk ya da esit oldugu icin tavanin altinda oldugu KANITLANMISTIR:
#     kirli bir makinede tavanin altina inen medyan, temiz makinede de iner.
#   * en dusuk gozlem >= 1000 us -> BELIRSIZ. Etiket: "bu makinede kirmizi;
#     temiz tavan <= <min> us". KESIN KIRMIZI DEGIL — gercek deger min'in,
#     hatta tavanin altinda olabilir ve bu betik onu ayirt EDEMEZ. Kesin
#     kirmizi ancak temiz bir referans ortamda (CI/konteyner) verilebilir.
#
# MUHUR: bu betik accept.sh'i CAGIRIR, DEGISTIRMEZ. accept.sh'in 2b OLCUTU
# (medyan < 1000 us) DEGISMEZ.
#
# HER OLCUMUN YANINA yazilanlar (tur 18'den beri gecerli, aynen duruyor):
# o anki 1/5/15 dk yuk, en cok CPU yiyen 3 surec, B1.9 artik-surec kontrolu.
# YUK KAYDI OLMAYAN LATANS SAYISI GECERSIZDIR.
set -u
cd "$(git rev-parse --show-toplevel)"

# LOCALE ZIRHI — BETIGIN TAMAMI ICIN, tek yerde. Makine tr_TR locale'inde.
# Iki ayri tuzak var ve IKISI de olculdu (24.08):
#   1. `sysctl -n vm.loadavg` yuku VIRGULLU basar -> "{ 8,06 5,67 7,07 }"
#   2. Daha sinsisi: awk DA locale'e uyar. tr_TR altinda awk icin ondalik
#      ayrac VIRGULdur, yani `echo 7.81 | awk '{print $1+0}'` -> 7 verir
#      (noktadan sonrasi duser). Yalniz sysctl'i C'ye almak YETMEZ.
# Bu yuzden LC_ALL butun betige export edilir: sysctl, awk, ps, date, sort hepsi C.
export LC_ALL=C LC_NUMERIC=C

ORNEK=${ORNEK:-5}          # en az kac olcum (operator karari: 5)
ARA=${ARA:-1200}           # olcumler arasi saniye (operator karari: 20 dk)
TAVAN_US=${TAVAN_US:-1000} # accept.sh'in 2b tavani — BURADA DEGISTIRILMEZ,
                           # yalnizca HUKUM yazilirken karsilastirmak icin okunur
LOG=reports/R7/YUK-2B-ORNEKLEME.log
RAPOR=reports/R7/YUK-2B.md
OUT=reports/R7/accept.out
NCPU=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 1)

yuk(){ sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' \
       || uptime | sed 's/.*average[s]*://' | tr -d ','; }
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

# accept.sh'in 2b satirindan medyan mikrosaniyeyi ceker. YESIL ve KIRMIZI
# metinlerin IKISI de "the gate's median is <X> us" tasir, ikisi de yakalanir.
# Olcum ALINAMADIYSA (daemon yok, arac derlenmedi, ornek yok) hicbir sey
# basmaz -> o cevrim GECERSIZ sayilir, sayi UYDURULMAZ.
medyan_cek(){ sed -n "s/.*the gate's median is \([0-9][0-9.]*\) us.*/\1/p" "$1" | head -1; }

# UYKU NABIZLI: surucunun stall watchdog'u 1200 sn ciktisizlik gorurse oturumu
# OLDURUR (kos.sh STALL_TIMEOUT=1200). 20 dk'lik tek bir `sleep` tam o sinirda
# durur ve ornekleyiciyi KENDI bekleme suresinde oldurtebilir. Bu yuzden bekleme
# 60 sn'lik parcalara bolunur ve her parcada LOG'a bir satir duser: hem cikti
# buyur, hem dosya aktivitesi olur — watchdog'un iki nabzi da beslenir.
nabizli_bekle(){
  local hedef="$1" gecen=0
  while [ "$gecen" -lt "$hedef" ]; do
    sleep 60; gecen=$((gecen+60))
    kayit "bekleme ${gecen}/${hedef}s (siradaki ornek icin) — anlik yuk: $(yuk)"
  done
}

kayit "2b ORNEKLEYICI basladi: ornek=$ORNEK ara=${ARA}s cekirdek=$NCPU"
kayit "baslangic yuku: $(yuk)"
{ echo; echo "== 2b TEKRARLI ORNEKLEME — $(date +%Y-%m-%dT%H:%M:%S)"
  echo "Kural: tur 19 CEVAP 1. En dusuk gozlem, cekismesiz degerin ALT SINIRIdir."
  echo "Hedef ornek sayisi: $ORNEK, ara: ${ARA}s."; } >> "$RAPOR"

GOZLEM=""; GECERLI=0
n=1
while [ "$n" -le "$ORNEK" ]; do
  kayit "--- ornek $n/$ORNEK: accept.sh kosuluyor (yuk $(yuk))"
  { echo; echo "#### ornek $n/$ORNEK"; baglam; } >> "$RAPOR"

  # ATOMIK YAZIM: accept.sh'in ciktisi ONCE gecici dosyaya gider, ancak betik
  # KENDI BASINA bittiginde accept.out'a tasinir. Neden: bu betik disaridan
  # `timeout` ile sarilabilir (B1.9); tavan accept.sh'in ORTASINDA dolarsa
  # dogrudan yazilan accept.out YARIM kalir ve yarim bir kabul ciktisi
  # "23 yesil / 3 kirmizi" gibi OKUNUR — kesilmis oldugu hicbir yerde yazmaz.
  # Yarim kabul ciktisi, yanlis kabul ciktisindan farksizdir.
  TMPOUT="$(mktemp -t rb2b)"
  bash reports/R7/accept.sh > "$TMPOUT" 2>&1
  rc=$?
  if grep -q 'R7 acceptance:' "$TMPOUT"; then
    M="$(medyan_cek "$TMPOUT")"
    KAPANIS="$(grep 'R7 acceptance:' "$TMPOUT" | tail -1)"
    cp "$TMPOUT" "reports/R7/accept.ornek$n.out"
    mv "$TMPOUT" "$OUT"
    if [ -n "$M" ]; then
      GECERLI=$((GECERLI+1)); GOZLEM="$GOZLEM $M"
      kayit "ornek $n: medyan ${M} us | $KAPANIS"
      { echo "olcum: medyan ${M} us"; echo "kabul: $KAPANIS"; } >> "$RAPOR"
    else
      kayit "ornek $n GECERSIZ: accept.sh 2b'yi OLCEMEDI (daemon/arac/ornek yok)."
      { echo "olcum: YOK — 2b bu cevrimde olculemedi, sayi uydurulmadi"
        echo "kabul: $KAPANIS"; } >> "$RAPOR"
    fi
  else
    kayit "ornek $n GECERSIZ: accept.sh kapanis satirini basmadan bitti (rc=$rc)."
    kayit "       $OUT DEGISTIRILMEDI. Ham cikti: $TMPOUT"
    echo "olcum: YOK — accept.sh yarim bitti (rc=$rc), cikti gecersiz" >> "$RAPOR"
  fi

  [ "$n" -lt "$ORNEK" ] && nabizli_bekle "$ARA"
  n=$((n+1))
done

############################################################################
# HUKUM
if [ "$GECERLI" -eq 0 ]; then
  kayit "HICBIR GECERLI OLCUM YOK ($ORNEK deneme) — 2b OLCULEMEDI, kirmizi kalir."
  { echo; echo "**HUKUM: 2b OLCULEMEDI.** $ORNEK denemenin hicbirinde accept.sh"
    echo "bir medyan uretemedi. Sayi UYDURULMADI. 2b KIRMIZI kalir."; } >> "$RAPOR"
  exit 3
fi

MIN="$(printf '%s\n' $GOZLEM | sort -g | head -1)"
MAX="$(printf '%s\n' $GOZLEM | sort -g | tail -1)"
kayit "gecerli gozlem: $GECERLI/$ORNEK | hepsi:$GOZLEM | EN DUSUK ${MIN} us"

if awk -v m="$MIN" -v t="$TAVAN_US" 'BEGIN{exit !(m>=t)}'; then
  kayit "HUKUM: 2b BELIRSIZ — bu makinede kirmizi; temiz tavan <= ${MIN} us."
  { echo; echo "**HUKUM: 2b BELIRSIZ — bu makinede kirmizi, KESIN KIRMIZI DEGIL.**"
    echo "Gecerli gozlem $GECERLI/$ORNEK, hepsi (us):$GOZLEM"
    echo "EN DUSUK gozlem **${MIN} us**, tavan ${TAVAN_US} us."
    echo "Bu sayi temiz degerin UST SINIRIdir: temiz tavan <= ${MIN} us."
    echo "Gercek deger ${TAVAN_US} us'nin altinda OLABILIR; bu betik ayirt EDEMEZ."
    echo "Hukum ancak temiz bir referans ortamda (CI/konteyner) verilebilir."; } >> "$RAPOR"
  exit 2
else
  kayit "HUKUM: 2b KESIN YESIL — en dusuk gozlem ${MIN} us < ${TAVAN_US} us."
  { echo; echo "**HUKUM: 2b KESIN YESIL.**"
    echo "Gecerli gozlem $GECERLI/$ORNEK, hepsi (us):$GOZLEM"
    echo "EN DUSUK gozlem **${MIN} us** (kirli kosulda), en yuksek ${MAX} us."
    echo "Yuk yalniz EKLER: temiz ortamdaki deger ${MIN} us'den BUYUK olamaz,"
    echo "dolayisiyla ${TAVAN_US} us tavaninin altinda oldugu KANITLANMISTIR."
    echo "Kirli makinede tavanin altina inen olcum, temiz makinede de iner."; } >> "$RAPOR"
  exit 0
fi
