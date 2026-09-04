# f0-ortam — ortam sertleştirme tek canlı yerde (koşu 5)

Tarih: 2026-08-26 · Worktree: `/Users/damummyphus/damla_projects_2026/rabadon-kosu4`, dal `kosu4`
Makine: darwin 24.2.0 (arm64).

**Sorun:** koşu 5'in sürücüsü yok. `scripts/arsiv/kos.sh` başlığında "İPTAL 2026-08-25
(KOSU-RABADON-4 §3.1): bu sürücü emekli edildi, KOŞMAZ" yazıyor. Ortam sertleştirme
maddeleri o ölü betiğin gövdesinde kalmıştı — koşan hiçbir şey onları uygulamıyordu.

**Yapılan:** maddeler `scripts/onkontrol.sh` içinde toplandı. Her blok kaynağını
(`kos.sh:<satır>`) yorumda taşıyor; uydurma madde eklenmedi. Betik hem `source`
edilebilir (yalnız export + timeout shim yüklenir, hiçbir şey basılmaz) hem doğrudan
koşar (madde madde YEŞİL/KIRMIZI + tek satır hüküm, kırmızı varsa `exit 1`).
`set -u` var, `set -e` YOK. Betik gövdesi ASCII (kos.sh gibi).

## Madde tablosu

| # | Madde | Kaynak | Sonuç | Hükmü basan komut |
|---|-------|--------|-------|-------------------|
| 1 | prompt/CI zırhı (`GIT_TERMINAL_PROMPT=0 CI=1 npm_config_yes=true DEBIAN_FRONTEND=noninteractive GIT_PAGER=cat`) | kos.sh:8 | YEŞİL | 5 değişkenin her biri beklenen değerle karşılaştırılır (betik içi `for v in ...`); tanık: `env \| grep -E "^(GIT_TERMINAL_PROMPT\|CI\|npm_config_yes\|DEBIAN_FRONTEND\|GIT_PAGER)="` |
| 2 | Python UTF-8 zırhı (`PYTHONIOENCODING=utf-8 PYTHONUTF8=1`) | kos.sh:9 | YEŞİL | `python3 -c "import sys;print(sys.stdout.encoding)"` → `utf-8` |
| 3 | Sürüm sabitleme + sürüm kaydı | kos.sh:10-13 | YEŞİL | `timeout 60 claude --version` → `2.1.172 (Claude Code)`; satır `reports/kosu/claude-surum.txt` dosyasına eklenir |
| 4 | `timeout` shim (macOS'ta `timeout` yok → `gtimeout`; ikisi de yoksa KIRMIZI) | kos.sh:14-25 / isci.sh:28-32 | YEŞİL | `command -v timeout` → `/opt/homebrew/bin/timeout`; canlılık: `timeout 5 true` rc=0 |
| 5 | git kilitleri — ÖNCE `index.lock`/`HEAD.lock` kırılır SONRA yarım rebase/merge temizlenir | kos.sh:183-190 (sıra yorumu birebir korundu) | YEŞİL | `GD=$(git rev-parse --git-dir); rm -f $GD/index.lock $GD/HEAD.lock; git rebase --abort; git merge --abort; git status --porcelain` |
| 6 | disk + inode + /tmp eşikleri (1 GB / 10000 inode / 512 MB) | kos.sh:196-203 (eşikler ve `df -Pi` yorumu aynen) | YEŞİL | `df -Pk .` / `df -Pi .` / `df -Pk /tmp` → boş=153329 MB, inode=314019152, /tmp=153329 MB |
| 7 | alt süreç gömme: SAYAR + isim isim LİSTELER, ÖLDÜRMEZ | yeni birleşim (kos.sh grup_oldur + ÖNKONTROL.md madde 5) | YEŞİL (4 süreç) | `pgrep -fl 'claude -p\|rabadon\|isci.sh\|kos.sh\|kos-smoke'` |
| 8 | `git push --dry-run` yutulmaz; rc!=0 → KIRMIZI + `exit != 0` | kos.sh:53-60 `pusla()`'nın tersi (orada yutuluyordu) | YEŞİL | `GIT_TERMINAL_PROMPT=0 timeout 120 git push --dry-run` → rc=0 |

**HÜKÜM: YEŞİL — 8/8, exit 0.** Kırmızı çıkmadı, dolayısıyla "kırmızıyı raporla"
maddesi devreye girmedi.

## Betiğin ham çıktısı

```
== ONKONTROL (2026-08-26T05:10:50+0300) — /Users/damummyphus/damla_projects_2026/rabadon-kosu4
                               > env | grep -E "^(GIT_TERMINAL_PROMPT|CI|npm_config_yes|DEBIAN_FRONTEND|GIT_PAGER)="
YESIL   1 prompt-zirhi         | GIT_TERMINAL_PROMPT=0 CI=1 npm_config_yes=true DEBIAN_FRONTEND=noninteractive GIT_PAGER=cat
                               > python3 -c "import sys;print(sys.stdout.encoding)"
YESIL   2 python-utf8          | PYTHONIOENCODING=utf-8 PYTHONUTF8=1; python3 stdout encoding=utf-8
                               > claude --version | tee reports/kosu/claude-surum.txt
YESIL   3 surum-sabitleme      | DISABLE_AUTOUPDATER=1; claude --version = 2.1.172 (Claude Code); kayit: reports/kosu/claude-surum.txt
                               > command -v timeout || command -v gtimeout
YESIL   4 timeout-shim         | timeout -> /opt/homebrew/bin/timeout; 'timeout 5 true' rc=0
                               > GD=$(git rev-parse --git-dir); rm -f $GD/index.lock $GD/HEAD.lock; git rebase --abort; git merge --abort; git status --porcelain
YESIL   5 git-kilit            | git-dir=/Users/damummyphus/damla_projects_2026/rabadon/.git/worktrees/rabadon-kosu4; kirilan kilit: yok; rebase/merge abort sonrasi git status calisiyor
                               > df -Pk . ; df -Pi . ; df -Pk /tmp   (esik: 1GB / 10000 inode / tmp 512MB)
YESIL   6 disk-inode           | bos=153329 MB (esik 1024) · inode=314019152 (esik 10000) · /tmp=153329 MB (esik 512)
                               > pgrep -fl 'claude -p|rabadon|isci.sh|kos.sh|kos-smoke' (oldurulmez, sayilir)
YESIL   7 alt-surec            | arka planda 4 aday surec — OLDURULMEDI, karar operatorun
          - 2372 tmux new -d -s rabadon scripts/kos.sh
          - 2373 bash scripts/kos.sh
          - 85131 node /Users/damummyphus/damla_projects_2026/rabadon/bin/rabadon.mjs ui --help
          - 85359 node /Users/damummyphus/damla_projects_2026/rabadon/bin/rabadon.mjs watch --help
                               > GIT_TERMINAL_PROMPT=0 timeout 120 git push --dry-run
YESIL   8 push-dry-run         | rc=0 | To https://github.com/nosey-dewdrop/rabadon.git    e6deafe..493f08c  kosu4 -> kosu4
HUKUM: YESIL — 8/8 madde gecti, ortam sertlestirildi.
EXIT=0
```

`source` modu ayrıca doğrulandı:
`bash -c 'set -u; source scripts/onkontrol.sh; echo "rc=$? GIT_TERMINAL_PROMPT=$GIT_TERMINAL_PROMPT DISABLE_AUTOUPDATER=$DISABLE_AUTOUPDATER"'`
→ `SOURCE-OK rc=0 GIT_TERMINAL_PROMPT=0 DISABLE_AUTOUPDATER=1`, hiçbir kontrol satırı basılmadı.
Sözdizimi: `bash -n scripts/onkontrol.sh` → temiz.

### Madde 7'nin listelediği süreçler (ÖLDÜRÜLMEDİ)

- **PID 2372 / 2373 — koşu 2'nin sürücüsü hâlâ canlı.** `tmux new -d -s rabadon scripts/kos.sh`
  + çocuğu `bash scripts/kos.sh`. ÖNKONTROL.md (koşu 3) bunu 25 Ağu'da da görmüştü;
  bugün hâlâ ayakta. `rabadon-kosu2/reports/kosu/OPERATOR.md`'ye `ONAY` yazılırsa
  koşu 2 kaldığı yerden koşmaya başlar. **Öldürme kararı operatörün, bu kart dokunmadı.**
- **PID 85131 / 85359 — iki yetim node süreci** (`rabadon.mjs ui --help`,
  `rabadon.mjs watch --help`, kök `/rabadon` kopyasından). Bunlar da koşu 3'ün
  ön kontrolünde vardı, yani en az 2 gündür ayaktalar. Dokunulmadı.

## rabadon'un kendi koşusuna bağlanma ölçümü (ÖLÇÜLDÜ, DEĞİŞTİRİLMEDİ)

| Soru | Ölçüm | Komut |
|---|---|---|
| Worktree'de `.claude/settings.json` var mı? | **YOK.** `.claude/` dizini bile yok. | `ls -la .claude/` → `No such file or directory` |
| `~/.claude/settings.json` içinde rabadon hook'u var mı? | **VAR.** | `grep -n -i 'rabadon\|hooks\|PreToolUse' ~/.claude/settings.json` |
| Hangi ikili çağrılıyor? | `/Users/damummyphus/damla_projects_2026/rabadon/native/rabadon-gate` (Mach-O arm64, 764416 bayt, 23 Ağu 04:53). Kök `/rabadon` kopyasından — **bu worktree'den değil.** | `ls -la .../native/rabadon-gate; file ...` |
| Hangi olaylara bağlı? | `PreToolUse` matcher `*` timeout 960; `PostToolUse` matcher `*` timeout 120; ayrıca 3 hook noktası daha aynı ikiliyi çağırıyor (settings.json satır 36, 55, 65, 85, 108). | `sed -n '79,115p' ~/.claude/settings.json` |
| Observe mi deny mi? | İkilinin tanıdığı modlar: `enforce\|watch\|silent` (hata metni: `rabadon: RABADON_MODE=%s is not enforce\|watch\|silent`). `RABADON_MODE` **hiçbir yerde set değil** (`~/.claude/settings.json` env bloğunda yalnız `RABADON_NOTIFY=0`, `RABADON_JUDGE=0`). Mod dosyası `<dir>/mode.last` okunuyor; **worktree'de `.rabadon/mode.last` YOK**, `~/.rabadon/mode.last` = **`watch`** (20 Ağu). `.rabadon/off` dosyası **yok**. İkilide `NO GUARD (observe only)` ve `"this project is in watch mode. I record what I would…"` metinleri var. | `env \| grep '^RABADON'`; `cat ~/.rabadon/mode.last`; `ls .rabadon/off`; `strings native/rabadon-gate \| grep -iE 'mode.last\|RABADON_MODE\|watch\|observe'` |
| Gate bu oturumda gerçekten koşuyor mu? | **EVET.** `.rabadon/sessions/286fd71d-….json` bu oturumun `goalPrompt`'unu (KOSU-RABADON-5.md orkestratör talimatı) taşıyor, `actionCount: 160`, `offTarget: 6`, `driftChallenged: 1`, dosya 05:11'de yazılmış. | `ls -lat .rabadon/sessions/` + `python3 -c "json.load(...)"` |

**Hüküm: rabadon KENDİ koşusuna BAĞLI — ama kök `/rabadon` kopyasındaki ikiliyle ve
`watch` (gözlem) modunda, `deny` modunda değil.** Bu oturumda tek bir STOP/BLOCKED
olayı üretmedi. Hiçbir hook ayarına, `mode.last`'a, `guard.json`'a **dokunulmadı —
öyle bırakıldı.**

## Yapılamayan (sebep)

- **Mod çözümlemesinin tam zinciri DOĞRULANMADI.** `mode.last` worktree'de yokken
  ikilinin `~/.rabadon/mode.last`'a mı düştüğü yoksa derlenmiş bir varsayılana mı
  düştüğü, ikiliyi çağırmadan kanıtlanamadı. Gate'i elle çağırmak = koşan bir kapıyı
  kurcalamak; kart "değiştirme" dediği için yapılmadı. Elimdeki dolaylı kanıt:
  `watch` yazan tek mod dosyası + bu oturumda sıfır deny.
- **Madde 8 gerçek push YAPMADI** (`--dry-run`). Yani kimlik bilgisi geçerli ve
  uzak dal ilerletilebilir görünüyor, ama gerçek yazma denenmedi (bilinçli).
- **Madde 6 macOS'ta `df -Pi` sütun farkı yüzünden pasif kalabilir** — kos.sh'ın
  kendi yorumu bunu söylüyor ("mac'te koruma pasif kalır ama YANLIŞ ALARM üretmez").
  Yorum korundu, davranış değiştirilmedi.
- **Kırmızı yol koşulmadı.** 8 maddenin hiçbiri kırmızı çıkmadığı için `exit 1` dalı
  ve kırmızı biçimlendirmesi CANLI OLARAK GÖZLENMEDİ (yalnız kod yolu var).

## Kart dışı fark edilen (dokunmadım, yazdım)

- **rabadon'un kendi `guard.json`'ı, koşunun kendi ön kontrol komutunu reddeder.**
  Kural `no-gnu-timeout-on-macos`: `deny: (^|[;&|]\s*)timeout\s+[0-9]`, gerekçe
  "`timeout` is not on macOS…". Oysa bu makinede `/opt/homebrew/bin/timeout` KURULU
  ve kos.sh'ın tüm mimarisi `timeout` üstüne kurulu. Bir ajan `timeout 120 git push
  --dry-run` komutunu doğrudan Bash'e yazarsa enforce modda REDDEDİLİR. `onkontrol.sh`
  bu komutu betik gövdesinin İÇİNDE koşar, o yüzden kapı yalnız `scripts/onkontrol.sh`
  görür ve tetiklenmez — kaza eseri değil, ama kural ile gerçeklik çelişiyor.
  Kurala DOKUNULMADI. (Bu, koşunun kendi aracına takılabileceği bir yanlış-red adayı.)
- **`reports/kosu/ONKONTROL.md` koşu 3'e ait ve dal/yol bilgisi bayat** (kosu3
  worktree'sini, `tmux new -d -s rabadon3` başlatmasını ve `scripts/kos.sh`'ı anlatıyor —
  o betik artık arşivde). Yeni bir dosya yazıldı, eskisi silinmedi/düzeltilmedi.
- **Bu turda başka f0 kartları paralel commit attı:** `70c9632` (f0 card 1) ve
  `493f08c` (f0 card 3) oturum başındaki `e6deafe`'nin üstüne binmiş; `git push
  --dry-run` çıktısındaki `e6deafe..493f08c` bundan. Uzakta henüz yok, şef push edecek.
- **`.gitignore` `*.log`** işçi loglarını eliyor (koşu 3 notu hâlâ geçerli), ama
  `reports/kosu/claude-surum.txt` `.txt` olduğu için commit'e girer — sürüm geçmişi
  uzaktan izlenebilir.
- **Madde 3'ün sürüm dosyası kartta listelenen iki çıktı yolunun dışında.** Kart
  "dosyaya kaydeder" diyordu ama yol vermemişti; `reports/kosu/claude-surum.txt`
  seçildi ve `ONK_SURUM_DOSYA` env'iyle değiştirilebilir bırakıldı.
- **`claude --version` = 2.1.172**, koşu 3'ün ön kontrolündeki sürümle AYNI —
  `DISABLE_AUTOUPDATER=1` bir gündür değil, iki gündür sürümü sabit tutuyor.
