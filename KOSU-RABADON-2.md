# rabadon — koşu belgesi 2 (2026-08-24 — v2.12, on ikinci tur: değerlendiren rc kalkanı, pager/ls sadeleştirmeleri, R7 soket kuralı)

Bu dosya repo kökünde `KOSU-RABADON-2.md` olarak durur ve **koşunun tek kaynağıdır**.
`KOSU-RABADON.md` ürün/tur tanımları için geçerli kalır; çelişkide BU dosya kazanır.
AGENTS-PROTOCOL.md'nin devir kuralı ve üç kapısı aynen geçerli. Yasa 7 aynen
geçerli: kamuya giden her sayı ledger'dan türetilir, elle yazılmaz.

Bu belge iki şey tanımlar: (A) doğrulanmış durum ve kalan iş; (B) koşunun
operatörsüz, ajanlarla, şişmeyen context'le nasıl ilerleyeceği. **İlk iş (B)'yi
kurmak VE BİR TAM ÇEVRİM DÖNDÜRMEKTİR.** Kurulu ama dönmemiş döngü yok hükmündedir.

Tasarım ilkeleri:
- **Döngü hiçbir koşulda sessizce ölmez.** Her tıkanma (tavan, tekrar, bekleme)
  OPERATÖR-durağına akar: soru yazılır, döngü bekler, CEVAP gelince devam eder.
- **Hafıza dosyada yaşar.** Oturumlar taze, bilgi birikimli: DENEMELER.md,
  GUNLUK.tsv, raporlar, ledger, git.
- Bu sistem bir "günlerce dokunmadan biter" fantezisi değil, **denetimli hız
  makinesidir**: tıkandığı yerde soru sorar, CEVAP gelince kaldığı yerden koşar.

---

## A. Doğrulanmış durum (23.08 clone, commit a59138b + 23.08 web araştırması)

Kapalı: R0–R6 hepsi ACCEPTED. Üç iddia kodda: kapı+sinyaller (yakalar),
enjeksiyon+in-round repair (tamir ettirir), sayaç+kapanış satırı (parayı söyler).
T1/T2 kimlik işi kapalı. R8 için PREFLIGHT ve DISCLOSURE yazılmış.

### A0. PAZAR DÜZELTMESİ (23.08) — "üretimde kimse yok" iddiası ÖLDÜ
`KOSU-RABADON.md §1b`'nin "production boş" cümlesi artık yanlış:
- **Watcher (Apollo Research):** coding agent monitoring platformu. Blocking
  monitörler tool call'ı gerçek zamanlı allow/deny/escalate eder; trailing
  monitörler tüm oturum trajectory'sini arka planda değerlendirip sapma, yanlış
  fix, doğrulanmamış "done" desenlerini yakalar. Takım/policy/çapraz-model
  özellikleri var. Yöntemi: çok aşamalı MODEL pipeline'ı (ağ + LLM çağrıları).
- **Mindlas** ve benzeri hook-tabanlı araçlar: context rot, unverified done,
  patch sprawl, tool loop tespiti.
Ayrışma HÂLÂ gerçek ama cümle değişir: fark boşluk değil, YÖNTEM — yerel
binary, hot-path'te sıfır model, sıfır ağ, deterministik, fail-same, ledger'dan
türetilmiş dolar. Taze koz: PreToolUse deny, `--dangerously-skip-permissions`
altında bile tool'u bloklar.
**Görev (M3'e bağlı):** docs/POSITIONING.md iki rakiple güncellenir, "kimse
yok" silinir (taslak: "Watcher asks a model to watch your model. rabadon reads
the moves — no network, no second model, no new attack surface."). Yasa 7 pazar
iddialarına da uygulanır: ölçüm tarihi yazılır, M4'ten önce yeniden doğrulanır.

Açık işler, sırasıyla:

### A1. R7 — iki kollu kanıt + daemon (hiç başlamadı, accept.sh kırmızı)
Tanım `KOSU-RABADON.md § R7`, kabul `reports/R7/accept.sh`. Özü: daemon
(rabadon-gated, unix socket, fail-SAME) ile kapı medyanı < 1 ms (in-process
probe; end-to-end cetvel YASAK); iki kollu koşu (A: ajan yalnız, B: ajan +
rabadon), harness YENİDEN kullanılır, tam repo adı + commit hash zorunlu,
beş sayı + ham JSONL.
**ÖNCELİK SORUSU (ilk OPERATÖR sorusu, R7 başlamadan):** saatlerle yarışılıyorsa
satan yarı KANIT, daemon ciladır. (a) accept.sh olduğu gibi; (b) R7a kanıt önce,
R7b daemon sonra, accept.sh ayrılır. Değerlendiren önerir, operatör seçer;
bu arada ortak iş (harness seçimi/kurulumu) başlayabilir.
**Yasa 7:** iki kol farkı gürültü içinde kalırsa "kurtarır" YAYINLANMAZ;
metrik + minimum örnek sayısı koşudan ÖNCE reports/R7/ altına (ön-kayıt).
**Mimari kural — soket yolu (24.08):** daemon soketi REPO/WORKTREE içine
AÇILMAZ. sockaddr_un.sun_path tavanı Linux 108 / macOS 104 bayttır; derin
worktree yolu + soket adı bunu sessizce aşar, bind() ENAMETOOLONG ile düşer
ve ajan bunu kod hatası sanıp C++'ı boşuna yeniden yazar. Soket yolu KISA ve
MUTLAK: `${XDG_RUNTIME_DIR:-/tmp}/rabadon-$UID.sock`, 0600 izin; yol uzunluğu
sınırı R7 testinde assert edilir. Değerlendiren bu kuralı ilk R7 talimatına
aynen taşır.

### A2. R8 — yayın (bloklu: "yeşil main" kararı OPERATÖR'e)
- npm 404; package.json 0.2.3, tag'siz. Kabul: `npm view rabadon version` sayı
  döndürür. darwin-arm64 iddiası çürük (PREFLIGHT §2); 17/18 binary uyuşmazlığı
  gerçek, kapanacak (rabadon-run her platform paketine).
- **BLOK:** "yeşil main" tanımsız — `make disclosure` tasarım gereği kırmızı
  (41 liste dışı isim, reports/R8/DISCLOSURE.md). Ya 41 isim listeye girer /
  temizlenir, ya disclosure kapısı yayın kapısı olmaktan çıkar. YAYIN kararı →
  OPERATÖR. Beklerken karar gerektirmeyen işler (17/18, tag, plugin paketi) OK.
- Plugin paketi: .claude-plugin/plugin.json + hooks/hooks.json, npm'dekiyle
  AYNI binary. Canonical dizin: anthropics/claude-plugins-official.
- **Teknik borç:** hook çıktıları (additionalContext dahil) 10.000 karakterde
  kesilir. Enjeksiyonun 10k'ya sığdığını gösteren test R8'den önce yazılır.
- Free/paid: sadece RABADON_TIER=free bayrağı; sayaç açık, enjeksiyon+repair
  kapalı, kapanış "yandı" der. Lisans altyapısı kapsam dışı.

### A3. M0–M4 — pazarlama (hiç başlamadı)
Tanımlar `KOSU-RABADON.md`'de; A0'ın POSITIONING görevi M3'e bağlı. M turu,
bağlı R turu yeşil olmadan kapanmaz. Fiyat ve her kamuya yayın adımı OPERATÖR.
Dogfooding ledger'ı (B1.4) devreye girdiğinde M1 makbuzudur.

**Kalıcı görev (operatör isteği, 24.08) — savunulabilir hikâye:** koşu yalnız
ürün değil, mülakatta/sunumda SAVUNULACAK anlatı da üretir. M4 ile birlikte iki
çıktı: (1) `docs/SAVUNMA.md` — problem, mimari kararlar ve NEDENleri (neden
native binary, neden model yok, neden fail-same), ölçülmüş sayılar, ve bu
orkestrasyonun KENDİSİ (yapan/değerlendiren döngüsü, Yasa 7, DENEMELER
hipotez-eleme sistemi) hikâyenin parçası olarak; (2) landing page — M4 yayın
haftası kapsamında, POSITIONING.md'den beslenir, her sayı ledger'dan.
İkisi de kamuya yayın adımı olarak OPERATÖR onayından geçer. Yapan oturumlar
tur kapanışlarında SAVUNMA.md'ye ham malzeme (karar + gerekçe + sayı) bırakır
ki M4'te sıfırdan yazılmasın.

### A4. Sıra
Döngü smoke-test (B6) → R7 önceliği OPERATÖR'e + harness işi → R7 → R8 kararı
OPERATÖR'e + karar gerektirmeyen R8 işleri → R8 → M3 → M4.
M0–M2'nin R tarafı kapalı; değerlendiren paralel oturumlara dağıtabilir,
kamuya YAYINLAMA hariç.

---

## B. Orkestrasyon v2.2 — ajanlarla, operatörsüz, şişmeyen, ÇÖKMEYEN

### B0. İlke (değişmez)
**Yapan oturum → değerlendiren oturum → yapan oturum.** Yapanın çıktısının
tamamı değerlendirene gider; değerlendiren sonraki talimatı YAZAR. Yapanın
metninde desen/keyword aranmaz. (Sürücünün değerlendiren CEVABININ ilk satırına
bakması istisna değil: değerlendirenin kendi üç-biçim protokolü.) "Soru" durum
bildirimidir, karar değil. **Operatör kurye değildir; hiçbir oturum çıktısı ona
taşınmaz.** Operatöre yalnız B4 listesi düşer; sistemin kendi tıkanmaları
(tavan, tekrar, bekleme) beşinci kategorinin (geri dönüşsüz kayıp) üyesidir.

Neden native /goal-/loop değil bash sürücü: (1) kontrol ajanda değil bash'te
kalmalı; (2) değerlendiren-rolü native primitive'lerde yok. Bilinçli karar.

### B1. Context ve güvenlik kuralları (yapan oturumlar için, zorunlu)
1. **Her tur taze oturum.** `claude -p`, sıfır miras. Devir dosyalardan.
2. **Ağır iş subagent'a.** Repo taraması, uzun derleme/bench çıktısı, log
   analizi Task subagent'ında; ~15 satır özet + dosya yolu döner.
3. **stdout ince.** İş özeti, kabul çıktısı, sayılar, commit hash'leri.
   Ham log dosyaya.
4. **DENEMELER.md — birikimli teşhis hafızası (yeni, zorunlu).** Bir tur
   kırmızıysa, o turda çalışan HER oturum `reports/<tur>/DENEMELER.md`'ye
   tek blok ekler: `## deneme N — <tarih>` altında DENENEN (1-2 cümle),
   SONUÇ (hata/ölçümün özü, 1-3 satır), ELENEN HİPOTEZ, KALAN HİPOTEZLER.
   Sürücü bu dosyayı değerlendirene verir; strateji kararları buradan
   verilir, tek satırlık günlük başlıklarından değil.
5. **Koşu izole; dogfooding ERTELİ ve ZIRHLI.** Döngü taze git worktree'de
   koşar. Rabadon kapısı başlangıçta BAĞLI DEĞİLDİR. B6 smoke + 5 temiz tur
   sonrasında değerlendiren talimatıyla observe modda bağlanır ve YALNIZ
   sarmalayıcıyla: `sh -c 'timeout 2 <gate> ... </dev/null; exit 0'` —
   segfault da assa da hook 2 saniyede ölür, daima 0 döner, oturumu tutamaz.
   Hook komutu `$CLAUDE_PROJECT_DIR` göreli yazılır (worktree yolu nereye
   düşerse düşsün çözülür), worktree'ye özgü ayar git'e girmeyen
   `settings.local.json`'a konur, binary O worktree'de derlenir.
   **Bağlama kabulü (Yasa 7 ruhu):** hook "bağlandı" SAYILMAZ — bağlayan
   oturum kasıtlı bir tool call tetikler ve ledger'da yeni satırı GÖSTERİR;
   ledger'da satır yoksa hook yok demektir (worktree settings'i working-tree
   dosyasıdır; doğru köke yazıldığı bu kanıtla doğrulanır, varsayımla değil).
   Deny moduna geçiş R8 kabulünden sonra ve OPERATÖR onayıyla.
6. **Ortam interaktif-imkânsız + stall watchdog (B2).** Sürücü export eder:
   GIT_TERMINAL_PROMPT=0, CI=1, npm_config_yes=true,
   DEBIAN_FRONTEND=noninteractive; stdin /dev/null. Credential'lar koşudan
   önce helper'da (C.0 test eder). Yapan, interaktif prompt açabilecek
   komutları bayraklarıyla (-y, --yes, --no-input) çağırır. Env'i takmayan
   TTY-arayan araçlara karşı son savunma sürücünün stall watchdog'udur —
   İKİ NABIZLI: çıktı büyümesi VEYA worktree dosya aktivitesi (sessiz derleme
   .o üretir, öldürülmez; TTY bekleyen süreç hiçbir dosyaya dokunmaz,
   öldürülür). Kayıp en fazla ~20 dk, ve yanlış pozitif derlemeler korunur.
   Yapan yine de 15+ dk sessiz kalabilecek tek komutları parçalara böler.
7. **Tek yazar ilkesi.** Her state dosyasının tek yazarı vardır ve bu yüzden
   kilit gerekmez: GUNLUK.tsv'ye yalnız SÜRÜCÜ yazar; reports/<tur>/DENEMELER.md'ye
   yalnız o turun yapan oturumu yazar; OPERATOR.md'ye değerlendiren soru,
   operatör CEVAP ekler (sıralı, sürücü beklerken). A4'ün paralel M oturumları
   açıldığında da kural budur: paralel oturumlar FARKLI turların dosyalarına
   yazar, ortak dosyaya asla.
8. **Worktree dokunulmazdır.** kosu2 worktree'sinden çıkılmaz; `git checkout
   main`, `git branch -D`, geçmişe `reset --hard`, `.git` dosyasına/worktree
   yapısına dokunmak, worktree'yi silip yeniden kurmak YASAK. Repo geçmişi
   gerekiyorsa `git log`/`git show` salt-okunur kullanılır. main'e taşıma
   yalnız tur kabulü yeşilken değerlendiren talimatıyla squash-merge'dür.

### B2. Sürücü — `scripts/kos.sh`
v2.2 farkları: stall watchdog (stream çıktı + büyüme kontrolü), DENEMELER.md
değerlendiren girdisine eklendi.

```bash
#!/usr/bin/env bash
# yapan -> degerlendiren -> yapan. Sessiz olum yok: her tikanma OPERATOR-duragi.
set -u
set -m   # arka plan isler KENDI process grubunu alir -> agac halinde oldurulebilir
cd "$(git rev-parse --show-toplevel)"
mkdir -p reports/kosu
export GIT_TERMINAL_PROMPT=0 CI=1 npm_config_yes=true DEBIAN_FRONTEND=noninteractive GIT_PAGER=cat
export PYTHONIOENCODING=utf-8 PYTHONUTF8=1   # C/POSIX locale ASCII cokusune karsi parser zirhi
# TASINABILIRLIK: macOS'ta `timeout` YOKTUR (BSD userland). Shim olmadan her
# `timeout ...` cagrisi "command not found" ile 127 doner — degerlendiren HIC
# kosmaz, pusla her turda "basarisiz" saniir. gtimeout = GNU timeout (coreutils).
# Shim yoksa dongu sessizce degil, YANLIS kosar; o yuzden burasi sert baslar.
if ! command -v timeout >/dev/null 2>&1; then
  if command -v gtimeout >/dev/null 2>&1; then
    timeout() { gtimeout "$@"; }
  else
    echo "HATA: ne timeout ne gtimeout var (macOS'ta: brew install coreutils). Dongu baslamaz." >&2
    exit 2
  fi
fi
MAX_ITER=${MAX_ITER:-40}
SESSION_TIMEOUT=${SESSION_TIMEOUT:-7200}   # mutlak tavan (mesru uzun derleme/bench icin genis)
STALL_TIMEOUT=${STALL_TIMEOUT:-1200}       # cikti buyumezse 20 dk'da kes
MAX_WAIT_S=${MAX_WAIT_S:-21600}
RAW_MAX=${RAW_MAX:-15000000}   # tek oturum stream tavani (~token yanigi vekili)
BUTCE_DAR=0                     # context asiminda 1'e cekilir, basarili kararla sifirlanir
GUNLUK=reports/kosu/GUNLUK.tsv
bekle_toplam=0
AKTIF_PID=""
# ZIRH: surucu olurse (Ctrl+C, tmux kill, HUP) aktif yapanin TUM AGACI da gomulur —
# yetim claude gece boyu para yakamaz. -$$ ISE YARAMAZ: set -m ile yapan AYRI gruptadir,
# o yuzden hedef script'in grubu degil AKTIF_PID'in grubudur.
# iki supurge: grup_oldur AYRI gruptaki yapani, kill 0 AYNI gruptaki subshell'i
# (degerlendiren command-substitution'i) gomer. trap ONCE sokulur — kill 0
# script'in kendine de TERM yollar, reset'siz trap ozyinelemeye girer.
trap 'trap - INT TERM HUP; grup_oldur "$AKTIF_PID"; kill -TERM 0 2>/dev/null; exit 130' INT TERM HUP

grup_oldur() {  # tum surec AGACINI oldur: gruba TERM, 5 sn sonra KILL
  [ -n "${1:-}" ] || return 0
  kill -TERM -- "-$1" 2>/dev/null || kill -TERM "$1" 2>/dev/null
  sleep 5
  kill -KILL -- "-$1" 2>/dev/null || true
}

pusla() {  # push; kalirsa rebase+tekrar; yine kalirsa LOGLA — sessiz yutma yok
  timeout 120 git push -q 2>/dev/null && return 0
  timeout 120 git pull --rebase -q 2>/dev/null || git rebase --abort >/dev/null 2>&1
  timeout 120 git push -q 2>/dev/null && return 0
  printf '%s\t%s\tpush BASARISIZ — remote guncel degil, OPERATOR.md YERELDEN izlenmeli\n' \
    "$(date +%Y-%m-%dT%H:%M:%S%z)" "$1" >> reports/kosu/PUSH-HATA.log   # BSD date'te -Is YOK
  return 1
}

operator_duragi() {  # $1: soru
  printf '\nOPERATÖR: %s\n' "$1" >> reports/kosu/OPERATOR.md
  git add -A; git commit -qm "kosu2: OPERATOR duragi" || true; pusla durak
  # muhur: CEVAP: satirlari yetmez, en sonda TEK BASINA 'ONAY' satiri gerekir
  # (yarim kaydedilmis Cmd+S cumlesini talimat sanmamak icin)
  while ! grep -q '^ONAY[[:space:]]*$' reports/kosu/OPERATOR.md 2>/dev/null; do sleep 300; done
  bekle_toplam=0
}

# oturumu watchdog ile kosar: $1 talimat, $2 cikti dosyasi. Donus: 0 normal, 9 stall-kill, 8 hard-timeout
yapan_kos() {
  # nabiz markeri WORKTREE icinde: worktree ile ayni dosya sistemi/saat;
  # git add'den once silindigi icin commit'e girmez
  local raw="$2.raw" mark="./.kosu-nabiz.$$"; touch "$mark"
  claude -p --dangerously-skip-permissions --output-format stream-json --verbose "$1" \
    < /dev/null > "$raw" 2> "$raw.err" &
  local pid=$! start=$(date +%s) last=0 stall=0 now size chg rc=0 durum=0 parse_ok=0
  AKTIF_PID=$pid
  while kill -0 "$pid" 2>/dev/null; do
    sleep 60
    now=$(date +%s); size=$(wc -c < "$raw" 2>/dev/null || echo 0)
    # thrash freni: cikti tasmasi = anlamli ilerleme olmadan hizli token yakma vekili
    if [ "$size" -gt "$RAW_MAX" ]; then durum=7; grup_oldur "$pid"; break; fi
    # iki nabiz: cikti buyumesi VEYA worktree dosya aktivitesi (sessiz derleme .o uretir)
    # -cnewer (ctime): tar/npm mtime'i GECMISE koruyabilir ama ctime kernel'indir, forge edilemez
    # node_modules prune'lu (150k dosyalik stat israfina karsi); build/ BILEREK iceride —
    # sessiz derlemenin tek yasam belirtisi orasi, prune etmek 5. turun false-kill'ini geri getirir.
    # -print -quit ilk eslesmede cikar: tam tarama yalniz aktivite yokken olur. timeout 10:
    # find asilirsa "aktivite VAR" sayilir — watchdog'un kendisi sistemi asamaz, oldurme yonunde degil
    # yasatma yonunde yanilir.
    chg="$(timeout 10 find . -path ./.git -prune -o -name node_modules -prune -o -type f -cnewer "$mark" -print -quit 2>/dev/null)"
    [ $? -eq 124 ] && chg="find-zamanasimi-aktivite-sayilir"
    if [ "$size" -gt "$last" ] || [ -n "$chg" ]; then last=$size; stall=0; touch "$mark"
    else stall=$((stall+60)); fi
    if [ "$stall" -ge "$STALL_TIMEOUT" ]; then durum=9; grup_oldur "$pid"; break; fi
    if [ $((now-start)) -ge "$SESSION_TIMEOUT" ]; then durum=8; grup_oldur "$pid"; break; fi
  done
  wait "$pid" 2>/dev/null; rc=$?
  AKTIF_PID=""
  rm -f "$mark"
  # stream-json'dan okunur metni cikar (asistan metinleri + sonuc); olmazsa ham kuyruk
  if timeout 60 python3 - "$raw" > "$2" 2>/dev/null <<'PY'
import json,sys,re
ANSI=re.compile(r'\x1b\[[0-9;]*[A-Za-z]|\r')
out=[]; saw_result=False
for line in open(sys.argv[1],encoding='utf-8',errors='replace'):
    line=line.strip()
    if not line: continue
    if len(line)>2_000_000:          # newline'siz dev binary cop: RAM'e/regex'e sokma
        out.append(f'[PARSER NOTU: {len(line)} baytlik tek dev satir atlandi]'); continue
    try: o=json.loads(line)          # once HAM dene: gecerli JSON'a asla dokunma
    except Exception:
        line=ANSI.sub('',line).strip()   # patladiysa ANSI/\r temizle, tekrar dene
        if not line: continue
        try: o=json.loads(line)
        except Exception: out.append(line); continue
    t=o.get('type')
    if t=='assistant':
        for b in (o.get('message') or {}).get('content',[]):
            if b.get('type')=='text': out.append(b['text'])
            elif b.get('type')=='tool_use': out.append(f"[tool: {b.get('name')}]")
    elif t=='result':
        saw_result=True; out.append(o.get('result') or '')
if not saw_result:
    out.append('[PARSER NOTU: result eventi gorulmedi — akis kesik olabilir, cikti EKSIK sayilmali]')
print('\n'.join(out))
PY
  then parse_ok=1
  else tail -c 200000 "$raw" > "$2"; fi   # fallback: raw adli delil olarak kalir
  if [ -s "$raw.err" ]; then              # CLI stderr'i etiketli+ANSI-temiz ekle
    ESC=$(printf '\033')
    { printf '\n[CLI STDERR kuyrugu:]\n'; tail -15 "$raw.err" | sed "s/${ESC}\[[0-9;]*[A-Za-z]//g"; } >> "$2"
  fi
  [ "$parse_ok" -eq 1 ] && rm -f "$raw" "$raw.err"   # basarili parse: geveze dosyalara gerek yok
  if [ "$durum" -eq 0 ] && [ "$rc" -ne 0 ]; then
    printf '\n[SÜRÜCÜ NOTU: oturum rc=%s ile KENDİLİĞİNDEN öldü (ağ/CLI hatası olabilir) — çıktı eksik sayılmalı.]\n' "$rc" >> "$2"
  fi
  return $durum
}

i=$(find reports/kosu -maxdepth 1 -name '*.out' 2>/dev/null | grep -c '')
talimat="KOSU-RABADON-2.md'yi oku. B1 kurallariyla calis: A4 sirasindaki acik isten basla, subagent kullan, stdout'u ince tut, DENEMELER.md'yi guncelle, kabul betigini kos, raporu yaz, commit+push et."
[ -f reports/kosu/son.talimat ] && talimat="$(cat reports/kosu/son.talimat)"

while true; do
  i=$((i+1))
  if [ "$i" -gt "$MAX_ITER" ]; then
    operator_duragi "iterasyon tavani ($MAX_ITER) doldu. CEVAP: satirlarini yaz, en sona tek basina ONAY yaz; tavan +40 kaydirilir."
    talimat="reports/kosu/OPERATOR.md'deki CEVAP satirlarini uygula, A4 sirasinda kaldigin yerden devam et. B1 kurallari gecerli."
    # i SIFIRLANMAZ (eski dosyalarin uzerine yazardi); tavan kaydirilir, dosyalar monoton
    mv reports/kosu/OPERATOR.md "reports/kosu/tavan-$i.operator.md"; MAX_ITER=$((i+40)); continue
  fi
  if [ "${#talimat}" -gt 50000 ]; then         # E2BIG sigortasi: dev talimat argv'ye degil dosyadan
    talimat="Talimatın tamamı reports/kosu/son.talimat dosyasında (argv sınırı için kısaltıldı). Önce onu oku, sonra uygula. B1 kurallarıyla çalış, DENEMELER.md'yi güncelle, kabul betiğini koş, raporu yaz, commit+push et."
  fi
  # SIRA ONEMLI: once kilit kirilir, sonra abort — index.lock dururken abort da
  # kilide takilir; ters sira bir turu ziyan eder. Worktree'de .git bir DOSYADIR,
  # kilit gercek git-dir'dedir. Guvenli: akis sirali, canli git sureci olamaz.
  GD="$(git rev-parse --git-dir 2>/dev/null)"
  [ -n "$GD" ] && rm -f "$GD/index.lock" "$GD/HEAD.lock" 2>/dev/null || true
  git rebase --abort >/dev/null 2>&1 || true   # stall-kill'in birakabilecegi yarim state
  git merge  --abort >/dev/null 2>&1 || true
  # worktree sagligi: ajan .git'e dokunduysa kilitlenme degil DURAK
  git status --porcelain >/dev/null 2>&1 || {
    operator_duragi "git worktree BOZUK gorunuyor (git status calismiyor) — ajan .git dosyasina/worktree yapisina dokunmus olabilir. Elle onar; CEVAP: yaz, en sona ONAY."
    mv reports/kosu/OPERATOR.md "reports/kosu/bozuk-$i.operator.md"
  }
  bos_kb=$(df -Pk . 2>/dev/null | awk 'NR==2{print $4}'); bos_kb=${bos_kb:-9999999}; case "$bos_kb" in *[!0-9]*|'') bos_kb=9999999;; esac
  # inode kitligi: npm 50MB'a 150k dosya yazar; blok bos, inode dolu olabilir.
  # macOS/BSD df -Pi sutunlari farklidir: orada yanlis (buyuk) sutun okunur,
  # yani mac'te koruma pasif kalir ama YANLIS ALARM uretmez — guvenli yone yanilir.
  bos_inode=$(df -Pi . 2>/dev/null | awk 'NR==2{print $4}'); bos_inode=${bos_inode:-9999999}; case "$bos_inode" in *[!0-9]*|'') bos_inode=9999999;; esac
  # cok-partisyon korlugune karsi: npm/gcc kucuk tmpfs'i doldurur, data diski genis gorunur
  tmp_kb=$(df -Pk /tmp 2>/dev/null | awk 'NR==2{print $4}'); tmp_kb=${tmp_kb:-9999999}; case "$tmp_kb" in *[!0-9]*|'') tmp_kb=9999999;; esac
  if [ "$bos_kb" -lt 1048576 ] || [ "$bos_inode" -lt 10000 ] || [ "$tmp_kb" -lt 524288 ]; then
    operator_duragi "disk 1GB altinda ($((bos_kb/1024)) MB) VEYA inode tukeniyor ($bos_inode) VEYA /tmp doluyor ($((tmp_kb/1024)) MB). Temizlik/karar gerekli. CEVAP: yaz, en sona ONAY."
    mv reports/kosu/OPERATOR.md "reports/kosu/disk-$i.operator.md"
  fi
  yapan_kos "$talimat" "reports/kosu/$i.out"; durum=$?
  if [ "$durum" -eq 9 ]; then
    printf '\n[SÜRÜCÜ NOTU: cikti %s sn buyumedi — STALL KILL. Interaktif prompt / TTY bekleyen arac olasiligini degerlendir; DENEMELER.md guncellenmemis olabilir. Bu bir KESINTIDIR: yurutulen hipotez ELENMIS SAYILMAZ.]\n' "$STALL_TIMEOUT" >> "reports/kosu/$i.out"
  elif [ "$durum" -eq 7 ]; then
    printf '\n[SÜRÜCÜ NOTU: ÇIKTI TAŞMASI — stream %s baytı aştı, muhtemel thrash (hızlı hata döngüsü). Hipotez ELENMEZ ama iş KÜÇÜK ADIMLARA bölünmeli.]\n' "$RAW_MAX" >> "reports/kosu/$i.out"
  elif [ "$durum" -eq 8 ]; then
    printf '\n[SÜRÜCÜ NOTU: oturum %s sn mutlak tavaninda kesildi — kismi cikti yukarida.]\n' "$SESSION_TIMEOUT" >> "reports/kosu/$i.out"
  elif [ ! -s "reports/kosu/$i.out" ] \
       || grep -qiE 'rate.?limit|usage limit|overloaded|too many requests' "reports/kosu/$i.out"; then
    bekle_toplam=$((bekle_toplam+900))
    if [ "$bekle_toplam" -ge "$MAX_WAIT_S" ]; then
      operator_duragi "toplam $((MAX_WAIT_S/3600)) saattir limit/bos-cikti beklemesindeyim. Plan/hesap kontrolu gerekebilir. CEVAP: yaz, en sona ONAY."
      mv reports/kosu/OPERATOR.md "reports/kosu/bekleme-$i.operator.md"
    fi
    echo "kosu2 $i: limit/bos — 15 dk" >> reports/kosu/bekleme.log
    i=$((i-1)); sleep 900; continue
  fi
  bekle_toplam=0
  git add -A; git commit -qm "kosu2 $i" || true; pusla "$i"
  if [ "$BUTCE_DAR" -eq 1 ]; then OUT_B=50000; DEN_T=25; else OUT_B=150000; DEN_T=60; fi
  karar_ham="$(
    { cat KOSU-RABADON-2.md
      echo '----- KARAR GUNLUGU (tekrar SAYACI; strateji icin DENEMELER oku) -----'
      tail -30 "$GUNLUK" 2>/dev/null || echo '(ilk tur)'
      echo '----- DENEMELER (en son degisen 2 tur; boyut butcesi) -----'
      # tek-yazar ilkesi geregi tur basina BIR dosya var (~15 tavan): glob+ls guvenli, xargs gereksiz
      ls -t reports/*/DENEMELER.md 2>/dev/null | head -2 | while read -r d; do echo "--- $d:"; tail -"$DEN_T" "$d"; done
      echo '----- ONCEKI 3 KARARIN TAMAMI -----'
      for k in $(ls reports/kosu/*.karar 2>/dev/null | sort -V | tail -3); do echo "--- $k:"; cat "$k"; done
      echo '----- YAPAN OTURUM CIKTISI -----'
      ob=$(wc -c < "reports/kosu/$i.out")
      [ "$ob" -gt "$OUT_B" ] && echo "[KISALTILDI: $ob bayttan son $OUT_B bayt — BOYUT butcesi; icerik filtrelenmedi, desen aranmadi]"
      tail -c "$OUT_B" "reports/kosu/$i.out"
      echo '----- GIT -----'
      git log --oneline -15
      git status --short
      echo '----- BEKLEYEN OPERATOR -----'
      cat reports/kosu/OPERATOR.md 2>/dev/null || echo '(yok)'
    } | timeout 900 claude -p --model sonnet "$(cat docs/DEGERLENDIREN.md)"
  )"
  rc_eval=$?
  # yarim-kusma kalkani: timeout(124) ya da ag olumuyle kesilen degerlendirenin
  # KISMI metni karar SAYILMAZ — aksi halde yarim cumle *) dalindan talimat olur
  if [ "$rc_eval" -ne 0 ]; then
    bekle_toplam=$((bekle_toplam+900))
    if [ "$bekle_toplam" -ge "$MAX_WAIT_S" ]; then
      operator_duragi "degerlendiren ust uste basarisiz bitiyor (son rc=$rc_eval; 124=timeout). CEVAP: yaz, en sona ONAY."
      mv reports/kosu/OPERATOR.md "reports/kosu/eval-$i.operator.md"
    fi
    echo "kosu2 $i: degerlendiren rc=$rc_eval — kismi cikti atildi, 15 dk" >> reports/kosu/bekleme.log
    sleep 900; i=$((i-1)); continue
  fi
  if [ -z "$karar_ham" ]; then
    echo "kosu2 $i: degerlendiren bos — 15 dk" >> reports/kosu/bekleme.log
    sleep 900; i=$((i-1)); continue
  fi
  if printf '%s\n' "$karar_ham" | grep -qiE 'prompt is too long|request too large|context (length|window)'; then
    if [ "$BUTCE_DAR" -eq 1 ]; then
      operator_duragi "degerlendiren girdisi DAR butcede bile context sinirini asiyor — DENEMELER/cikti temizligi karari gerek. CEVAP: yaz, en sona ONAY."
      mv reports/kosu/OPERATOR.md "reports/kosu/context-$i.operator.md"; BUTCE_DAR=0
    else
      BUTCE_DAR=1   # bekleme YOK: ayni girdi kuculmeden tekrar gondermek olu taklididir
    fi
    echo "kosu2 $i: context asimi — butce daraltilip tekrar" >> reports/kosu/bekleme.log
    i=$((i-1)); continue
  fi
  if printf '%s\n' "$karar_ham" | head -3 | grep -qiE '^(api )?error|rate.?limit|overloaded|bad gateway|too many requests'; then
    echo "kosu2 $i: degerlendiren HATA sizdirdi, karar degil — 15 dk" >> reports/kosu/bekleme.log
    sleep 900; i=$((i-1)); continue
  fi
  BUTCE_DAR=0
  printf '%s\n' "$karar_ham" > "reports/kosu/$i.karar"
  ilk="$(printf '%s\n' "$karar_ham" | sed -e 's/^[[:space:]>*#`-]*//' -e '/^$/d' | head -1)"
  printf '%s\t%s\n' "$i" "$ilk" >> "$GUNLUK"
  case "$ilk" in
    OPERATÖR*|OPERATOR*)
      printf '\n%s\n' "$karar_ham" >> reports/kosu/OPERATOR.md
      git add -A; git commit -qm "kosu2 $i: OPERATOR sorusu" || true; pusla "$i"
      while ! grep -q '^ONAY[[:space:]]*$' reports/kosu/OPERATOR.md 2>/dev/null; do sleep 300; done
      talimat="reports/kosu/OPERATOR.md'deki CEVAP satirlarini uygula, sonra A4 sirasinda kaldigin yerden devam et. B1 kurallari gecerli."
      mv reports/kosu/OPERATOR.md "reports/kosu/$i.operator.md" ;;
    BİTTİ*|BITTI*)
      printf '%s\n' "$karar_ham" >> reports/kosu/BITTI.md
      git add -A; git commit -qm "kosu2 bitti" || true; pusla son
      exit 0 ;;
    *) talimat="$karar_ham" ;;
  esac
  printf '%s\n' "$talimat" > reports/kosu/son.talimat
  sleep 20
done
```

Notlar:
- **Watchdog:** oturum stream-json'la akar, sürücü dakikada bir dosya
  büyüklüğüne bakar; STALL_TIMEOUT (20 dk) büyümeyen oturum kesilir, kısmi
  çıktı sürücü notuyla değerlendirene gider. SESSION_TIMEOUT mutlak tavandır.
- **Değerlendirenin iki hafızası:** GUNLUK.tsv tekrar SAYACIDIR ("bu kaçıncı
  kırmızı"); DENEMELER.md STRATEJİ hafızasıdır ("ne denendi, ne elendi").
- Operatör cevabı her durakta aynı: OPERATOR.md'ye `CEVAP: ...` satırları
  + EN SONA TEK BAŞINA `ONAY` satırı. Mühür gelmeden döngü kımıldamaz —
  yarım kaydedilmiş cümle (refleks Ctrl+S) asla talimat olamaz.
- **Sürücü ölümsüz sızıntı bırakmaz:** INT/TERM/HUP trap'i önce kendini söker
  (özyineleme yok), sonra İKİ süpürgeyle temizler: grup_oldur AYRI gruptaki
  yapanı, kill 0 AYNI gruptaki subshell'i (değerlendiren dahil) gömer. Her tur
  başında ÖNCE git kilitleri kırılır SONRA yarım state abort edilir (ters sıra
  kilide takılır). Disk kontrolü blok VE inode bakar. Sayaç monotondur.
- **Entropi frenleri:** değerlendiren girdisi bayt bütçelidir (aşımda dar
  bütçeyle ANINDA tekrar, beklemek yok; dar da yetmezse DURAK). pusla'nın ağ
  komutları 120 sn timeout'ludur (TCP blackhole orkestratörü donduramaz).
  Tur başında worktree sağlığı denetlenir; /tmp ayrıca izlenir; tek oturum
  stream'i RAW_MAX'ı aşarsa thrash sayılıp kesilir.
- **Nabız markeri worktree içindedir** (ayni dosya sistemi → saat kayması
  etkisiz) ve git add'den önce silinir. CLI stderr'i stream'e KARIŞMAZ:
  ayrı dosyaya gider, kuyruğu ANSI-temiz ve etiketli olarak .out'a eklenir.
- **Branch hijyeni:** koşu `kosu2` branch'inde döner (worktree zaten ayrı
  branch ister). "kosu2 N" checkpoint'leri main'e ASLA taşınmaz; bir tur
  kabulü yeşil olunca değerlendiren, tur işini main'e TEK temiz squash-merge
  ile taşıtan talimatı yazar. Böylece main insan-okunur kalır ve R8'in
  "yeşil main'den yayın" şartıyla aynı kapıda birleşir.
- **pusla():** push başarısızsa bir kez rebase+tekrar, hâlâ olmuyorsa
  reports/kosu/PUSH-HATA.log'a damga. Sessiz yutma yok: log doluysa remote
  bayattır ve OPERATOR.md YERELDEN izlenmelidir.

### B3. Değerlendiren — `docs/DEGERLENDIREN.md`

```
Sen rabadon koşusunun değerlendirenisin. Sana KOSU-RABADON-2.md, karar günlüğü
(tekrar sayacı), aktif turların DENEMELER.md'leri (birikimli teşhis hafızası),
önceki 3 tam karar, yapan oturumun tam çıktısı, git durumu ve varsa bekleyen
operatör soruları verildi.

SEN MÜHENDİS DEĞİLSİN, YÖNLENDİRİCİSİN. Kod yazmazsın, teknik detay
UYDURMAZSIN. Bilgin bir karara yetmiyorsa talimatın, o bilgiyi ÜRETTIRMEKTIR:
"şu teşhisi yap, bulguları reports/<tur>/TESHIS.md'ye yaz, stdout'a 10 satır
özet bas" gibi. Emin olmadığın teknik iddiayı talimata yazmak yasaktır. Kararın KISA olur:
talimata log/döküm yapıştırmazsın; uzun malzemeyi yapana dosya yolundan
okutursun. 150 satırı aşan karar, biçim ihlalidir.

Yapanın gerekçelerini değil KANITLARINI okursun: kabul betiği çıktısı, test
sayıları, ölçümler, commit'ler. "Yapamadım/durdum/soru" durum bildirimidir;
kararı sen verirsin. Yapanın teknik sorusuna cevap sende YOKSA cevabı yapana
ürettirirsin; operatöre teknik soru GİTMEZ.

TEKRAR KONTROLÜ (her kararda ilk iş): GUNLUK'a bak — bu kaçıncı aynı kırmızı?
STRATEJİ KARARI DENEMELER.md'DEN VERİLİR: hangi hipotezler denendi ve elendi,
hangileri duruyor. Yeni talimatın DENENMEMİŞ bir hipotezi hedeflemeli; elenen
bir yolu tekrar yazmak yasaktır. Yapan DENEMELER.md'yi güncellememişse ilk
talimat onu güncelletmektir. 3. aynı kırmızıda yaklaşımı kökten değiştir
(farklı teşhis yolu, farklı araç, sorunu bölme); 6.'da OPERATÖR'e taşı
("geri dönüşsüz zaman kaybı") — durumu ve DENEMELER özetini tek paragrafta ver.
İSTİSNA: STALL KILL / rc-notu / "akış kesik" damgalı oturum TEKRAR SAYILMAZ ve
hipotezi ELENMİŞ SAYILMAZ — o bir kesintidir, kanıt değil. Aynı hipotezi
adımlara bölerek (uzun sessiz komutları parçalayıp ara çıktı bastırarak)
sürdürmek meşru ve genelde doğru karardır.
THRASH: çıktıda aynı hatanın hızlı oku-değiştir-hata döngüsünü ya da "ÇIKTI
TAŞMASI" notunu görürsen tek uzun oturum verme; işi küçük, tek-adımlı
talimatlara böl. [KISALTILDI] işaretli girdi yalnız BOYUT bütçesinden
kırpılmıştır — içerik filtrelenmemiş, desen aranmamıştır; gerekirse dosyanın
tamamını yapana okutturursun.

Kural: A4 sırası ve tur kabul betikleri ölçüttür. Kabul yeşil olmadan tur
kapanmaz; kısmi kabulle sonraki tur başlamaz. Yapan B1'i çiğnediyse sonraki
talimatta düzelttir. B1.5 zamanı geldiğinde (smoke + 5 temiz tur) dogfooding'i
observe modda ve sarmalayıcıyla bağlatmak da senin talimatınla olur.

Cevabın yalnız üç biçimden biridir; İLK SATIR biçimi belirler; başka hiçbir
şey (selamlama, başlık, açıklama) yazmazsın:

1. Sonraki yapan oturumun talimatı. Tek parça, kendi kendine yeterli, dosya
   yollarıyla; şu cümleyle biter: "B1 kurallarıyla çalış, DENEMELER.md'yi
   güncelle, kabul betiğini koş, raporu yaz, commit+push et."

2. İlk satır "OPERATÖR:" — YALNIZ: fiyat, ürün konumlandırma, kamuya yayın,
   sahiplik, geri dönüşü olmayan işler (sistem tıkanmaları dahil). Tek
   paragraf: durum + seçenekler + senin önerin.

3. İlk satır "BİTTİ:" tek satır özet — yalnız R8 ve M4 kabulleri yeşilse.
```

### B4. Operatöre giden beş kategori (değişmez)
fiyat · ürün konumlandırma · kamuya yayın · sahiplik · geri dönüşsüz işler
(sürücünün tavan/bekleme durakları beşincinin üyesi).
Bilinen ilk iki soru: R7 önceliği (A1), R8 "yeşil main / 41 isim" (A2).

### B5. Bütçe ve fren
Sürücü: MAX_ITER (tavanda durak), SESSION_TIMEOUT, STALL_TIMEOUT, MAX_WAIT_S.
Değerlendiren: DENEMELER tabanlı hipotez eleme, 3-tekrar yaklaşım değişimi,
6-tekrar OPERATÖR. DRIFT.md'nin üç kırmızı bayrağı aynen geçerli.

### B6. Döngünün kendi kabulü (SMOKE TEST — ilk turun asıl işi)
1. scripts/kos.sh + docs/DEGERLENDIREN.md repoda, commit'li; C.0 yeşil.
2. DENEME talimatıyla EN AZ BİR TAM ÇEVRİM: .out.raw aktı → .out çıkarıldı →
   .karar yazıldı → GUNLUK satır aldı → son.talimat düştü. Hepsi commit'li.
3. OPERATÖR yolu tatbik: kasıtlı sahiplik sorusu OPERATOR.md'ye düştü, döngü
   bekledi, CEVAP + ONAY yazıldı, devam etti; ONAY'sız CEVAP'ın döngüyü
   KIMILDATMADIĞI da gösterildi.
4. TEKRAR freni tatbik: kasıtlı hep-kırmızı deneme kabulüyle 3 çevrim;
   DENEMELER.md'nin dolduğu ve 3. kararın elenmemiş hipoteze yöneldiği
   GUNLUK + DENEMELER'den gösterilir.
5. WATCHDOG tatbik: kasıtlı asılan bir komutla (ör. read bekleyen script)
   bir çevrim; STALL KILL notunun .out'a düştüğü ve değerlendirenin bunu
   görüp karar verdiği gösterilir.
Bu beşi olmadan hiçbir R turuna başlanmaz.

---

## C. Başlatma (operatörün yapacağı TEK şey)

0. ÖN KONTROL (ilk oturum yapar): worktree'de `git push --dry-run` credential
   sormadan geçiyor mu; GIT_TERMINAL_PROMPT=0 altında test komutu asılmadan
   dönüyor mu; python3 mevcut mu; `claude --version` ONKONTROL.md'ye
   KAYDEDİLDİ mi (sürüm sabitleme: koşu boyunca auto-update kapalı, CLI
   sürümü koşu ortasında değiştirilmez — flag/format değişikliği riskine
   karşı tek gerçek sigorta). Kırmızıysa döngü BAŞLAMAZ, eksik OPERATOR.md'ye
   yazılır (tek elle-kurulum istisnası budur).

1. Claude Code'a tek talimat:

   "KOSU-RABADON-2.md repo köküne kondu. Oku. İlk işin: B2'deki scripts/kos.sh
   ve B3'teki docs/DEGERLENDIREN.md dosyalarını birebir yazıp commit+push
   etmek, koşu için `kosu2` branch'inde taze bir git worktree hazırlamak ve C.0 ön kontrolünü
   koşup sonucu reports/kosu/ONKONTROL.md'ye yazmak. Rabadon kapısını
   BAĞLAMA (B1.5: smoke + 5 temiz tur sonrası). Turlara BAŞLAMA."

2. O commit gelince terminalde (worktree içinde):

   tmux new -d -s rabadon scripts/kos.sh

   İlk çevrimler B6 smoke testidir; döngü onu kendisi koşar.

3. Sonrası: reports/kosu/OPERATOR.md'ye ara sıra `CEVAP: ...` satırları yazıp
   EN SONA tek başına `ONAY` yazmak (mühürsüz cevap işlenmez). İlk iki
   soru muhtemelen R7 önceliği ve R8 "yeşil main". Oturum çıktısı okumak yok.
   Uzaktan (GitHub'dan) izliyorsan önce PUSH-HATA.log boş mu bak; doluysa
   remote bayattır, sorular yerel OPERATOR.md'dedir.
