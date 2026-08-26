#!/usr/bin/env bash
# onkontrol.sh — ORTAM SERTLESTIRME, TEK CANLI YER (kosu5).
#
# NEDEN: kosu4'un surucusu (scripts/kos.sh) IPTAL edildi ve arsive tasindi
# (scripts/arsiv/kos.sh, "KOSMAZ, delil olarak durur"). Ortam sertlestirme
# maddeleri o OLU betigin govdesinde kalmisti; bir dahaki kosu onlari HIC
# uygulamadan baslardi. Bu betik o bloklari kos.sh'tan BIREBIR toplar.
# Kaynak satirlar her blogun basinda yazilidir; buraya UYDURMA madde girmez.
#
# Iki kullanim:
#   source scripts/onkontrol.sh   -> yalniz export'lar + timeout shim yuklenir,
#                                    hicbir kontrol kosmaz, hicbir sey basilmaz.
#   scripts/onkontrol.sh          -> her madde icin YESIL/KIRMIZI + kanit satiri,
#                                    en sonda tek satir hukum; kirmizi varsa exit 1.
#
# set -u VAR, set -e YOK: her kontrol kendi hukmunu basmali, ilk hatada
# betigin kacmasi hukumsuz bir cikis olurdu.
set -u

# ---------------------------------------------------------------- 1 + 2 + 3
# kos.sh:8 — kosu ortasinda kimlik/onay soran hicbir arac ASILAMAZ.
export GIT_TERMINAL_PROMPT=0 CI=1 npm_config_yes=true DEBIAN_FRONTEND=noninteractive GIT_PAGER=cat
# kos.sh:9 — C/POSIX locale ASCII cokusune karsi parser zirhi
export PYTHONIOENCODING=utf-8 PYTHONUTF8=1
# kos.sh:10-13 — SURUM SABITLEME: kosu ortasinda CLI guncellenirse flag/format
# degisir ve dongu sessizce YANLIS kosar. Global settings.json'a YAZILMAZ —
# operatorun diger oturumlarini etkilememesi icin yalniz bu ortama export.
export DISABLE_AUTOUPDATER=1

# ---------------------------------------------------------------- 4
# kos.sh:14-25 / isci.sh:28-32 — TASINABILIRLIK: macOS'ta `timeout` YOKTUR
# (BSD userland). Shim olmadan her `timeout ...` cagrisi "command not found"
# ile 127 doner — degerlendiren HIC kosmaz, pusla her turda "basarisiz" sanilir.
# gtimeout = GNU timeout (coreutils). Shim yoksa dongu sessizce degil, YANLIS
# kosar; o yuzden burasi sert baslar.
ONK_TIMEOUT_KAYNAK="timeout"
if ! command -v timeout >/dev/null 2>&1; then
  if command -v gtimeout >/dev/null 2>&1; then
    timeout() { gtimeout "$@"; }
    ONK_TIMEOUT_KAYNAK="gtimeout(shim)"
  else
    ONK_TIMEOUT_KAYNAK="YOK"
  fi
fi

# source edildiyse burada dur: ortam yuklendi, kontrol kosmaz.
# (bash: BASH_SOURCE[0] != $0 ise source edilmisizdir)
if [ "${BASH_SOURCE[0]:-$0}" != "$0" ]; then
  return 0
fi

# ================================ DOGRUDAN KOSU ================================
cd "$(git rev-parse --show-toplevel)" || { echo "KIRMIZI 0 depo-koku: git rev-parse --show-toplevel basarisiz"; exit 1; }
mkdir -p reports/kosu
SURUM_DOSYA="${ONK_SURUM_DOSYA:-reports/kosu/claude-surum.txt}"

KIRMIZI_SAYI=0
yesil() { printf 'YESIL   %-22s | %s\n' "$1" "$2"; }
kirmizi() { KIRMIZI_SAYI=$((KIRMIZI_SAYI+1)); printf 'KIRMIZI %-22s | %s\n' "$1" "$2"; }
komut() { printf '        %-22s > %s\n' "" "$1"; }

printf '== ONKONTROL (%s) — %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$(pwd)"

# ---- 1 ---- prompt/CI zirhi
komut 'env | grep -E "^(GIT_TERMINAL_PROMPT|CI|npm_config_yes|DEBIAN_FRONTEND|GIT_PAGER)="'
eksik=""
for v in GIT_TERMINAL_PROMPT=0 CI=1 npm_config_yes=true DEBIAN_FRONTEND=noninteractive GIT_PAGER=cat; do
  ad="${v%%=*}"; bek="${v#*=}"
  [ "$(eval "printf '%s' \"\${$ad:-}\"")" = "$bek" ] || eksik="$eksik $ad"
done
if [ -z "$eksik" ]; then
  yesil "1 prompt-zirhi" "GIT_TERMINAL_PROMPT=$GIT_TERMINAL_PROMPT CI=$CI npm_config_yes=$npm_config_yes DEBIAN_FRONTEND=$DEBIAN_FRONTEND GIT_PAGER=$GIT_PAGER"
else
  kirmizi "1 prompt-zirhi" "eksik/yanlis:$eksik"
fi

# ---- 2 ---- python utf-8 zirhi
komut 'python3 -c "import sys;print(sys.stdout.encoding)"'
pyenc="$(python3 -c 'import sys;print(sys.stdout.encoding)' 2>/dev/null)"
if [ "${PYTHONIOENCODING:-}" = "utf-8" ] && [ "${PYTHONUTF8:-}" = "1" ]; then
  yesil "2 python-utf8" "PYTHONIOENCODING=$PYTHONIOENCODING PYTHONUTF8=$PYTHONUTF8; python3 stdout encoding=${pyenc:-(python3 YOK)}"
else
  kirmizi "2 python-utf8" "PYTHONIOENCODING=${PYTHONIOENCODING:-} PYTHONUTF8=${PYTHONUTF8:-}"
fi

# ---- 3 ---- surum sabitleme + claude --version kaydi
komut 'claude --version | tee reports/kosu/claude-surum.txt'
if [ "${DISABLE_AUTOUPDATER:-}" != "1" ]; then
  kirmizi "3 surum-sabitleme" "DISABLE_AUTOUPDATER=${DISABLE_AUTOUPDATER:-} (1 olmali)"
elif ! command -v claude >/dev/null 2>&1; then
  kirmizi "3 surum-sabitleme" "DISABLE_AUTOUPDATER=1 ama PATH'te claude YOK — surum kaydedilemedi"
else
  srm="$(timeout 60 claude --version 2>&1 | head -1)"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$srm" ]; then
    kirmizi "3 surum-sabitleme" "claude --version rc=$rc cikti='$srm'"
  else
    printf '%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$srm" >> "$SURUM_DOSYA"
    yesil "3 surum-sabitleme" "DISABLE_AUTOUPDATER=1; claude --version = $srm; kayit: $SURUM_DOSYA"
  fi
fi

# ---- 4 ---- timeout shim
komut 'command -v timeout || command -v gtimeout'
case "$ONK_TIMEOUT_KAYNAK" in
  YOK) kirmizi "4 timeout-shim" "ne timeout ne gtimeout var (macOS'ta: brew install coreutils). Dongu baslamaz." ;;
  *)   yol="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null)"
       if timeout 5 true 2>/dev/null; then
         yesil "4 timeout-shim" "$ONK_TIMEOUT_KAYNAK -> ${yol:-fonksiyon}; 'timeout 5 true' rc=0"
       else
         kirmizi "4 timeout-shim" "$ONK_TIMEOUT_KAYNAK bulundu ama 'timeout 5 true' rc!=0"
       fi ;;
esac

# ---- 5 ---- git kilitleri (kos.sh:183-190)
# SIRA ONEMLI: once kilit kirilir, sonra abort — index.lock dururken abort da
# kilide takilir; ters sira bir turu ziyan eder. Worktree'de .git bir DOSYADIR,
# kilit gercek git-dir'dedir. Guvenli: akis sirali, canli git sureci olamaz.
komut 'GD=$(git rev-parse --git-dir); rm -f $GD/index.lock $GD/HEAD.lock; git rebase --abort; git merge --abort; git status --porcelain'
GD="$(git rev-parse --git-dir 2>/dev/null)"
kilit_vardi=""
if [ -n "$GD" ]; then
  for L in index.lock HEAD.lock; do
    [ -e "$GD/$L" ] && kilit_vardi="$kilit_vardi $L"
  done
  rm -f "$GD/index.lock" "$GD/HEAD.lock" 2>/dev/null || true
fi
git rebase --abort >/dev/null 2>&1 || true   # stall-kill'in birakabilecegi yarim state
git merge  --abort >/dev/null 2>&1 || true
if [ -z "$GD" ]; then
  kirmizi "5 git-kilit" "git-dir cozulemedi"
elif git status --porcelain >/dev/null 2>&1; then
  yesil "5 git-kilit" "git-dir=$GD; kirilan kilit:${kilit_vardi:- yok}; rebase/merge abort sonrasi git status calisiyor"
else
  kirmizi "5 git-kilit" "git status --porcelain BASARISIZ — worktree BOZUK gorunuyor (ajan .git'e dokunmus olabilir)"
fi

# ---- 6 ---- disk + inode (kos.sh:196-203)
komut 'df -Pk . ; df -Pi . ; df -Pk /tmp   (esik: 1GB / 10000 inode / tmp 512MB)'
bos_kb=$(df -Pk . 2>/dev/null | awk 'NR==2{print $4}'); bos_kb=${bos_kb:-9999999}; case "$bos_kb" in *[!0-9]*|'') bos_kb=9999999;; esac
# inode kitligi: npm 50MB'a 150k dosya yazar; blok bos, inode dolu olabilir.
# macOS/BSD df -Pi sutunlari farklidir: orada yanlis (buyuk) sutun okunur,
# yani mac'te koruma pasif kalir ama YANLIS ALARM uretmez — guvenli yone yanilir.
bos_inode=$(df -Pi . 2>/dev/null | awk 'NR==2{print $4}'); bos_inode=${bos_inode:-9999999}; case "$bos_inode" in *[!0-9]*|'') bos_inode=9999999;; esac
# cok-partisyon korlugune karsi: npm/gcc kucuk tmpfs'i doldurur, data diski genis gorunur
tmp_kb=$(df -Pk /tmp 2>/dev/null | awk 'NR==2{print $4}'); tmp_kb=${tmp_kb:-9999999}; case "$tmp_kb" in *[!0-9]*|'') tmp_kb=9999999;; esac
disk_kanit="bos=$((bos_kb/1024)) MB (esik 1024) · inode=$bos_inode (esik 10000) · /tmp=$((tmp_kb/1024)) MB (esik 512)"
if [ "$bos_kb" -lt 1048576 ] || [ "$bos_inode" -lt 10000 ] || [ "$tmp_kb" -lt 524288 ]; then
  kirmizi "6 disk-inode" "$disk_kanit — temizlik/karar gerekli (OPERATOR)"
else
  yesil "6 disk-inode" "$disk_kanit"
fi

# ---- 7 ---- alt surec gomme: SAY ve LISTELE, OLDURME (oldurme operator karari)
komut "pgrep -fl 'claude -p|rabadon|isci.sh|kos.sh|kos-smoke' (oldurulmez, sayilir)"
YETIM_DESEN="${ONK_YETIM_DESEN:-claude -p|rabadon|isci\.sh|kos\.sh|kos-smoke}"
yetim_ham="$(pgrep -fl "$YETIM_DESEN" 2>/dev/null | grep -v "onkontrol.sh" | grep -v "^$$ ")"
if [ -z "$yetim_ham" ]; then
  yetim_n=0
else
  yetim_n=$(printf '%s\n' "$yetim_ham" | grep -c '')
fi
yesil "7 alt-surec" "arka planda $yetim_n aday surec — OLDURULMEDI, karar operatorun"
if [ "$yetim_n" -gt 0 ]; then
  printf '%s\n' "$yetim_ham" | while IFS= read -r s; do printf '          - %s\n' "$s"; done
fi

# ---- 8 ---- push --dry-run YUTULMAZ
komut 'GIT_TERMINAL_PROMPT=0 timeout 120 git push --dry-run'
push_ciktisi="$(GIT_TERMINAL_PROMPT=0 timeout 120 git push --dry-run 2>&1)"
push_rc=$?
push_ozet="$(printf '%s' "$push_ciktisi" | tr '\n' ' ' | cut -c1-220)"
if [ "$push_rc" -eq 0 ]; then
  yesil "8 push-dry-run" "rc=0 | ${push_ozet:-(cikti yok)}"
else
  kirmizi "8 push-dry-run" "rc=$push_rc | ${push_ozet:-(cikti yok)}"
fi

# -------------------------------- HUKUM --------------------------------
if [ "$KIRMIZI_SAYI" -eq 0 ]; then
  printf 'HUKUM: YESIL — 8/8 madde gecti, ortam sertlestirildi.\n'
  exit 0
else
  printf 'HUKUM: KIRMIZI — %s madde kaldi; kosu BASLATILMAZ, once bunlar cozulur.\n' "$KIRMIZI_SAYI"
  exit 1
fi
