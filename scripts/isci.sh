#!/usr/bin/env bash
# isci.sh — v3/B1.2: AGIR IS ALT-AJANA DEGIL AYRI SURECE gider.
#
# Neden: alt-ajan (Task) bosluga olmez, EBEVEYNINE olur — son raporu yapanin
# context'ine yazilir ve kisa olmaz. Bir surecin donusu yoktur; birak tigi DOSYA
# vardir. Bu betik isi ayri surecte kosar, HAM ciktiyi reports/kosu/log/'a
# gomer, ve yapanin OKUMAYI SECEBILECEGI 12 satirlik bir rapor birakir.
#
# Kullanim:
#   scripts/isci.sh <ad> <komut...>
#   scripts/isci.sh tarama grep -rn "MIN_HISTORY" core/
#
# Cikti sozlesmesi (B6.1'in kanitladigi sey):
#   - komutun stdout/stderr'inin TEK BAYTI bu betigin stdout'una gecmez.
#   - ham cikti: reports/kosu/log/<ad>.log
#   - rapor    : reports/kosu/RAPOR/<ad>.md   (SUREC kirpar: head -12, B1.3)
#   - bu betik stdout'a YALNIZ bir satir basar: rapor yolu + rc.
#
# Cevre degiskenleri:
#   ISCI_TIMEOUT (vars. 3600 sn)  ISCI_TAIL (vars. 6 satir ozet)
set -u
cd "$(git rev-parse --show-toplevel)"

if [ "$#" -lt 2 ]; then
  echo "kullanim: scripts/isci.sh <ad> <komut...>" >&2; exit 2
fi

# TASINABILIRLIK (kos.sh ile ayni sart): macOS'ta `timeout` yoktur.
if ! command -v timeout >/dev/null 2>&1; then
  if command -v gtimeout >/dev/null 2>&1; then timeout() { gtimeout "$@"; }
  else echo "HATA: timeout/gtimeout yok (brew install coreutils)." >&2; exit 2; fi
fi

AD="$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"; shift
ISCI_TIMEOUT=${ISCI_TIMEOUT:-3600}
ISCI_TAIL=${ISCI_TAIL:-6}
mkdir -p reports/kosu/log reports/kosu/RAPOR
LOG="reports/kosu/log/$AD.log"
RAPOR="reports/kosu/RAPOR/$AD.md"

# B1.7: interaktif IMKANSIZ. stdin /dev/null — TTY bekleyen arac aninda doner.
# B1.10: her arka plan isi timeout sarili; -k ile inatci surec KILL edilir,
# artik surec birakilmaz.
BAS=$(date +%s)
timeout -k 10 "$ISCI_TIMEOUT" "$@" < /dev/null > "$LOG" 2>&1
RC=$?
SURE=$(( $(date +%s) - BAS ))

BAYT=$(wc -c < "$LOG" 2>/dev/null | tr -d ' '); BAYT=${BAYT:-0}
SATIR=$(wc -l < "$LOG" 2>/dev/null | tr -d ' '); SATIR=${SATIR:-0}
case "$RC" in
  0)   HUKUM="OK" ;;
  124) HUKUM="ZAMANASIMI (${ISCI_TIMEOUT}s) — is BITMEDI, hipotez ELENMIS SAYILMAZ" ;;
  *)   HUKUM="HATA rc=$RC" ;;
esac

# Rapor once TASLAK'a yazilir, sonra SUREC kirpar (B1.3: "12 satiri asma" niyet
# beyanidir, `head -12` hukumdur). Ozet satirlari 200 sutunda kesilir — tek
# satirlik 2 MB'lik bir log satiri raporu sisiremesin.
{ printf 'ISCI: %s · HUKUM: %s · SURE: %ss\n' "$AD" "$HUKUM" "$SURE"
  printf 'KOMUT: %s\n' "$*"
  printf 'LOG (tam cikti, okumak SECIMDIR): %s — %s bayt / %s satir\n' "$LOG" "$BAYT" "$SATIR"
  printf 'SON %s SATIR:\n' "$ISCI_TAIL"
  tail -"$ISCI_TAIL" "$LOG" 2>/dev/null | cut -c1-200
} > "$RAPOR.t"
if [ "$(wc -l < "$RAPOR.t")" -gt 12 ]; then
  head -11 "$RAPOR.t" > "$RAPOR"          # 11 + kirpma notu = TAM 12 satir
  echo '[ISCI: 12 satirda kirpildi — tam cikti LOG yolunda]' >> "$RAPOR"
else
  cp "$RAPOR.t" "$RAPOR"
fi
rm -f "$RAPOR.t"

# stdout'a TEK satir: yapan ne okuyacagini bilsin diye yol + rc. Isci ciktisi degil.
printf '%s (rc=%s)\n' "$RAPOR" "$RC"
exit "$RC"
