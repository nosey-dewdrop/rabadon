#!/usr/bin/env bash
# B6 smoke harness — kos.sh'in KONTROL AKISINI izole bir kum havuzunda kanitlar.
#
# NEDEN AYRI HARNESS: B6.3 (OPERATOR yolu) ve B6.5 (watchdog) SURUCUNUN
# davranisidir, yapan oturumun degil. Canli dongunun icinden kosulamaz —
# yapan oturum zaten surucunun cocugudur. Bu betik /tmp'de tek kullanimlik
# bir git deposu + sahte `claude` ile GERCEK scripts/kos.sh'i kosturur.
#
# TEST EDILEN DOSYA DEGISTIRILMEZ: kos.sh birebir kopyalanir. Yalnizca
# BELGELENMIS env knob'lari (STALL_TIMEOUT) disaridan verilir. `sleep 300`
# operator anketi KISALTILMAZ — bekleme gercek suredir, aksi halde
# "bekliyor mu" iddiasi kanit degil temenni olur.
#
# Kullanim: scripts/kos-smoke.sh [sandbox-dizini]
# Cikti: her adim icin PASS/FAIL satiri; rc=0 hepsi yesilse.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SB="${1:-/tmp/kosu-smoke-$$}"
export SB
rm -rf "$SB"; mkdir -p "$SB/bin" "$SB/state" "$SB/remote"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
no()  { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
say() { printf '\n== %s\n' "$1"; }

# ---------- B6.0 TASINABILIRLIK: nabiz ifadesi kendini eslestirmemeli ----------
# 24.08'de bulunan hata: BSD/macOS find'da `-cnewer REF` REFERANSIN KENDISINI de
# eslestirir. kos.sh marker'i prune etmezse chg hep dolu olur, STALL KILL HIC
# atesle mez ve watchdog sessizce OLUR. Bu 2 saniyelik test o regresyonu tutar.
say "B6.0 watchdog nabzi (tasinabilirlik regresyonu)"
NB="$SB/nabiz"; mkdir -p "$NB"; ( cd "$NB" && touch ./.kosu-nabiz.test )
sleep 1
selfm="$(cd "$NB" && find . -path ./.git -prune -o -name node_modules -prune -o -name '.kosu-nabiz.*' -prune -o -type f -cnewer ./.kosu-nabiz.test -print -quit 2>/dev/null)"
if [ -z "$selfm" ]; then ok "nabiz ifadesi marker'in kendisini eslestirmiyor"; else no "marker KENDINI eslestiriyor ($selfm) — watchdog olu"; fi
( cd "$NB" && touch ./gercek-aktivite )
livem="$(cd "$NB" && find . -path ./.git -prune -o -name node_modules -prune -o -name '.kosu-nabiz.*' -prune -o -type f -cnewer ./.kosu-nabiz.test -print -quit 2>/dev/null)"
if [ -n "$livem" ]; then ok "gercek dosya aktivitesi HALA gorunuyor (yasatma yonu korundu)"; else no "prune gercek aktiviteyi de kor etti"; fi

# ---------- sahte claude ----------
# yapan cagrisi --output-format tasir; degerlendiren tasimaz. Tur numarasi
# state/n'den okunur, boylece her tur farkli senaryo oynayabilir.
cat > "$SB/bin/claude" <<'STUB'
#!/bin/sh
S="$SB/state"
case "$*" in
  *--output-format*)
    n=$(cat "$S/yapan_n" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$S/yapan_n"
    printf '%s\n' "$*" > "$S/argv_$n"
    if [ "$n" -eq 1 ]; then
      # SENARYO 1 (B6.5): hicbir sey basmadan, hicbir dosyaya dokunmadan asil.
      # TTY bekleyen bir aracin taklidi. Watchdog bunu oldurmek ZORUNDA.
      echo $$ > "$S/hang_pid"
      exec sleep 9999
    fi
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"sahte yapan turu '"$n"'"}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}'
    printf '%s\n' '{"type":"result","result":"sahte yapan sonuc '"$n"'"}'
    exit 0
    ;;
  *)
    cat > "$S/eval_stdin.$$" ; mv "$S/eval_stdin.$$" "$S/eval_stdin_son"
    n=$(cat "$S/eval_n" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$S/eval_n"
    if [ "$n" -eq 2 ]; then
      # SENARYO 2 (B6.3): sahiplik sorusu -> OPERATOR duragi
      printf 'OPERATÖR: smoke tatbikati — sahiplik sorusu. CEVAP: yaz, en sona ONAY.\n'
    else
      printf 'sahte talimat %s. B1 kurallariyla calis.\n' "$n"
    fi
    exit 0
    ;;
esac
STUB
chmod +x "$SB/bin/claude"

# ---------- kum havuzu deposu ----------
git init -q --bare "$SB/remote/o.git"
mkdir -p "$SB/repo/docs" "$SB/repo/scripts" "$SB/repo/reports/kosu"
cd "$SB/repo" || exit 2
git init -q -b kosu2 .
git config user.email smoke@local; git config user.name smoke
cp "$REPO/scripts/kos.sh" scripts/kos.sh; chmod +x scripts/kos.sh
echo "sahte kosu belgesi" > KOSU-RABADON-2.md
echo "sahte degerlendiren promptu" > docs/DEGERLENDIREN.md
git add -A; git commit -qm init
git remote add origin "$SB/remote/o.git"; git push -q -u origin kosu2

# ---------- surucuyu baslat ----------
say "surucu baslatiliyor (STALL_TIMEOUT=60, sahte claude PATH'te)"
# macOS'ta `setsid` YOKTUR; perl ile ayni sey yapilir. Amac: surucu KENDI
# process grubunda kalsin, testin sonunda AGAC halinde gomulebilsin.
PATH="$SB/bin:$PATH" STALL_TIMEOUT=60 SESSION_TIMEOUT=600 MAX_ITER=9 \
  perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die' -- ./scripts/kos.sh \
  > "$SB/surucu.log" 2>&1 &
DPID=$!
temizle() { kill -TERM -- "-$DPID" 2>/dev/null; sleep 2; kill -KILL -- "-$DPID" 2>/dev/null; }
trap 'temizle; exit 130' INT TERM

bekle() {  # $1 saniye tavani, $2 test komutu
  local t=0
  while [ "$t" -lt "$1" ]; do
    eval "$2" && return 0
    sleep 5; t=$((t+5))
  done
  return 1
}

# ---------- B6.5: WATCHDOG ----------
say "B6.5 watchdog: asili yapan 60 sn'de kesilmeli"
if bekle 240 '[ -f reports/kosu/1.out ]'; then ok "1.out uretildi (asili oturum kesildi)"; else no "1.out hic gelmedi"; temizle; exit 1; fi
if grep -q 'STALL KILL' reports/kosu/1.out; then ok "STALL KILL notu .out'a dustu"; else no "STALL KILL notu YOK"; fi
# TAM o pid'e bakilir; `pgrep -f sleep 9999` baska kosularin yetimlerini de
# gorup YANLIS kirmizi verir (24.08'de verdi).
HP="$(cat "$SB/state/hang_pid" 2>/dev/null || echo 0)"
if [ "$HP" -gt 0 ] && ! kill -0 "$HP" 2>/dev/null; then ok "asili cocuk gomuldu (pid $HP, yetim yok)"
elif [ "$HP" -eq 0 ]; then no "asili cocuk pid'i kaydedilmedi"
else no "asili cocuk HALA yasiyor (pid $HP — grup_oldur calismadi)"; fi

# ---------- B6.2: TAM CEVRIM ----------
say "B6.2 tam cevrim: raw -> out -> karar -> GUNLUK -> son.talimat"
if bekle 120 '[ -f reports/kosu/1.karar ]'; then ok "1.karar yazildi"; else no "1.karar yok"; fi
if [ -s reports/kosu/GUNLUK.tsv ] && grep -q '^1	' reports/kosu/GUNLUK.tsv; then ok "GUNLUK.tsv 1 nolu satiri aldi"; else no "GUNLUK satiri yok"; fi
if [ -s reports/kosu/son.talimat ]; then ok "son.talimat dustu"; else no "son.talimat yok"; fi
if git log --oneline | grep -q 'kosu2 1'; then ok "tur commit'lendi"; else no "commit yok"; fi
# bare depo HEAD'i refs/heads/main'e bakar ve kosu2 push EDILMIS OLSA BILE
# `git log` duser — ref ADIYLA dogrulanir.
if git -C "$SB/remote/o.git" rev-parse --verify -q refs/heads/kosu2 >/dev/null; then ok "pusla() remote'a bastirdi (refs/heads/kosu2)"; else no "push olmadi"; fi
if [ ! -s reports/kosu/PUSH-HATA.log ] 2>/dev/null; then ok "PUSH-HATA.log bos"; else no "PUSH-HATA.log dolu"; fi
if [ -f "$SB/state/eval_stdin_son" ] && grep -q 'YAPAN OTURUM CIKTISI' "$SB/state/eval_stdin_son"; then ok "degerlendirene tam paket gitti"; else no "degerlendiren girdisi eksik"; fi

# ---------- B6.3: OPERATOR YOLU ----------
say "B6.3 operator yolu: soru dusmeli, CEVAP tek basina KIMILDATMAMALI, ONAY kimildatmali"
if bekle 240 'grep -q "^OPERATÖR:" reports/kosu/OPERATOR.md 2>/dev/null'; then ok "OPERATOR.md'ye soru dustu"; else no "operator sorusu dusmedi"; temizle; exit 1; fi
if [ ! -f reports/kosu/2.operator.md ]; then ok "dongu bekliyor (2.operator.md henuz yok)"; else no "dongu beklemeden gecti"; fi

# muhursuz CEVAP: bir tam anket cevrimi (sleep 300) + pay boyunca KIMILDAMAMALI
printf 'CEVAP: bu satirin tek basina hicbir sey yapmamasi gerekiyor\n' >> reports/kosu/OPERATOR.md
echo "   ... muhursuz CEVAP yazildi; 330 sn (bir tam anket cevrimi) izleniyor"
sleep 330
if [ ! -f reports/kosu/2.operator.md ] && [ ! -f reports/kosu/3.out ]; then
  ok "ONAY'siz CEVAP donguyu KIMILDATMADI (330 sn)"
else no "ONAY'siz CEVAP dongusu ilerletti — MUHUR CALISMIYOR"; fi

printf 'ONAY\n' >> reports/kosu/OPERATOR.md
echo "   ... ONAY muhru vuruldu; hareket bekleniyor"
if bekle 400 '[ -f reports/kosu/2.operator.md ]'; then ok "ONAY sonrasi OPERATOR.md arsivlendi (2.operator.md)"; else no "ONAY sonrasi dongu kimildamadi"; fi
if grep -q "OPERATOR.md'deki CEVAP" reports/kosu/son.talimat 2>/dev/null; then ok "son.talimat CEVAP'i uygulamaya yonlendirdi"; else no "son.talimat CEVAP'a yonlendirmedi"; fi
if bekle 200 '[ -f reports/kosu/3.out ]'; then ok "dongu bir sonraki tura gecti (3.out)"; else no "sonraki tur baslamadi"; fi
if grep -q "OPERATOR.md'deki CEVAP" "$SB/state/argv_3" 2>/dev/null; then ok "tur 3 yapani talimati GERCEKTEN aldi"; else no "tur 3 yapanina CEVAP talimati gitmedi"; fi

temizle
say "SONUC: $PASS gecti, $FAIL kaldi   (kum havuzu: $SB)"
[ "$FAIL" -eq 0 ]
