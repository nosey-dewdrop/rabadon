# F1a/KART 5 — KURULUM ADIM SAYISI + CURSOR SATIRI

Ölçüm tarihi: 2026-08-26. Ölçüm yeri: `mktemp -d` altında YEREL klon.
Kaynak: `/Users/damummyphus/damla_projects_2026/rabadon` (dal `main`).
Klon HEAD: `43e3cdae70bf5803c3cbe0afd072375572972193`, dal `main`.
Kum havuzu: `TMP=/tmp/f1a.sqcNcG` (klon `$TMP/rabadon`, proje `$TMP/proj`,
sahte ev `$TMP/home`, npm prefix `$TMP/npmprefix`).
Her komut `HOME=$TMP/home RABADON_DIR=$TMP/home/.rabadon
PATH=$TMP/npmprefix/bin:$PATH` altında koştu.
Gerçek `~/.claude/settings.json`, gerçek `~/.rabadon`, asıl repo **yazılmadı**;
`npm link` `npm_config_prefix` ile kum havuzuna yönlendirildi (kanıt: §1 adım 4).
`npm i -g rabadon` KOŞULMADI, ölçülmedi, bu raporda ona atıf yok.

---

## 1. KURULUMDAN ÇALIŞIR GUARD'A: NUMARALI ADIM LİSTESİ

Belgelenmiş yol iki yerde İKİ FARKLI şey diyor (ölçümden önceki bulgu):

| belge | kurulum satırı verbatim |
|---|---|
| `README.md:24-25` | `git clone https://github.com/nosey-dewdrop/rabadon && cd rabadon` <br> `npm install && npm link` |
| `site/index.html` (ENVANTER (c)) | `git clone https://github.com/nosey-dewdrop/rabadon && cd rabadon && make` |

Ölçüm README yolunu izledi (`make` de ayrıca koşturuldu, adım 2).

| # | kullanıcının yazdığı komut | ne bastı | soru sordu mu | süre |
|---|---|---|---|---|
| 1 | `git clone <repo> $TMP/rabadon` | `Cloning into '/tmp/f1a.sqcNcG/rabadon'... done.` exit 0 | HAYIR | 2,136 s |
| 2 | `cd $TMP/rabadon && make` | 19 ikili derlendi, son satır `c++ ... -o native/gate_bench`; 24 satır çıktı, exit 0 | HAYIR | 31,246 s |
| 3 | `npm install` | `> rabadon@0.2.3 postinstall` → `rabadon: native binaries already built (19/19).` / `up to date, audited 1 package in 2s` exit 0 | HAYIR | 1,615 s |
| 4 | `npm link` | `added 1 package, and audited 4 packages in 138ms` + 4 satır `npm warn allow-scripts ... Run \`npm approve-scripts --allow-scripts-pending\``; sonuç `$TMP/npmprefix/bin/rabadon -> ../lib/node_modules/rabadon/native/rabadon-cli.sh` | HAYIR (uyarı var, prompt yok) | 0,199 s |
| 5 | `cd $TMP/proj` | — | HAYIR | 0 s |
| 6 | `rabadon init` | §2'deki tam ekran | **HAYIR** | 0,546 s |
| 7 | `rabadon on` | `rabadon: ON — the arbiter acts: refuses, repairs, proves` exit 0 | HAYIR | 0,017 s |
| 8 | `rabadon drill` *(kanıt adımı)* | gate FIRE etti, aşağıda | HAYIR | 0,023 s |

Toplam duvar saati: **≈ 35,8 s**.

### N kaç?

| sayma biçimi | N |
|---|---|
| yazılan kabuk komutu, `cd`'ler ve `&&` ayrık (yukarıdaki 1-7, kanıt hariç) | **7** |
| README'deki gibi `&&` ile birleşik SATIR sayısı (`clone&&cd`, `npm install&&npm link`, `cd proj`, `init`, `on`) | **5** |
| kanıt adımı (`rabadon drill`) dahil, birleşik satır | **6** |

**"iki komut" iddiası ile yan yana:** iddia = 2 (kurulum + `rabadon init`).
Ölçülen = **5** birleşik satır / **7** ayrık komut. Fark **+3 satır / +5 komut**.

### FARKIN NEREDEN GELDİĞİ (savunma değil, ölçüm)

1. `npm install` ve `npm link` iki ayrı komut, tek "kurulum" değil.
2. `cd` iki kez yazılıyor (klona gir, projeye gir).
3. **`rabadon on` — belgelerde YOK ama zorunlu.** `rabadon init` sonrası mod
   WATCH'tır; gate hiçbir şeyi durdurmaz. Ölçüm:

```
=== A) hook olayı, 'rabadon on' ÖNCESİ ===
rabadon (watch) would have blocked this.
Rule: no-force-push-main — force-pushing a shared branch destroys history
command matched deny rule: git push --force origin main
Nothing was stopped. `rabadon on` makes this a real refusal.
exit=0

=== C) hook olayı, 'rabadon on' SONRASI ===
rabadon BLOCKED this action.
Rule: no-force-push-main — force-pushing a shared branch destroys history
command matched deny rule: git push --force origin main
Adjust the approach instead of retrying the same action.
(user override: add "no-force-push-main" to disabled[] in .rabadon/guard.json, or `rabadon off` to pause supervision)
exit=2
```

Basan komut (ikisi de aynı):
```sh
printf '{"hook_event_name":"PreToolUse","session_id":"m1","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' "$TMP/proj" \
  | "$TMP/rabadon/native/rabadon-gate"; echo "exit=$?"
```

`grep -n 'rabadon on' README.md` → kurulum bloğunda **tek eşleşme yok**
(tek eşleşme satır 132, kurulumla ilgisiz bir cümle içinde).
Yani **README'yi harfiyen izleyen kullanıcı, hiçbir şeyi reddetmeyen bir
kuruluma sahip olur.** "Çalışır guard = exit 2" tanımına README yolu tek
başına ULAŞMIYOR.

### `rabadon drill` (kanıt adımı, 8) çıktısı

```
rabadon drill — feeding a synthetic dangerous command through the REAL gate:
    $ git push --force origin main

rabadon (watch) would have blocked this.
Rule: no-force-push-main — force-pushing a shared branch destroys history
command matched deny rule: git push --force origin main
Nothing was stopped. `rabadon on` makes this a real refusal.

the rule FIRED in watch mode — `rabadon on` makes this a real refusal (exit 2).
this was a drill: tagged at emit, excluded from the ledger. `rabadon usage` counts only real catches.
```
(bu koşum `rabadon on`'dan ÖNCEYDİ; `drill` `RABADON_DRILL=1` ile koşar ve
ledger'a yazmaz, exit 0.)

### `rabadon init` NE YAZDI (dosya listesi, ölçüldü)

`find $TMP/proj -name .git -prune -o -type f -print`:
```
/tmp/f1a.sqcNcG/proj/.claude/settings.json      (5 hook olayı + statusLine)
/tmp/f1a.sqcNcG/proj/.cursor/hooks.json         (5 Cursor olayı)
/tmp/f1a.sqcNcG/proj/.gitignore                 (+2 satır eklendi)
/tmp/f1a.sqcNcG/proj/.rabadon/guard.json        (4 baseline deny kuralı)
/tmp/f1a.sqcNcG/proj/.rabadon/state.json
/tmp/f1a.sqcNcG/home/.rabadon/config.json       (repair.mode="ask")
```

---

## 2. `rabadon init` EKRANI — VERBATIM

Komut: `cd $TMP/proj && rabadon init` (exit 0, 0,546 s, **hiçbir soru sorulmadı**)

```
rabadon init: authoring failed (rabadon guard: no evidence found in /private/tmp/f1a.sqcNcG/proj (no README/CONTRIBUTING/CLAUDE.md/AGENTS.md, no manifes) — wrote a baseline guard instead. Refine it with `rabadon guard`.

rabadon init — done.

  wired in:
    /private/tmp/f1a.sqcNcG/proj/.rabadon/guard.json   — the law, REVIEW it (deny rules + protected paths)
    /private/tmp/f1a.sqcNcG/proj/.claude/settings.json   — gate hooks merged
    /tmp/f1a.sqcNcG/home/.rabadon/config.json   — repair.mode = "ask"  (ask | auto-propose | off)
    /private/tmp/f1a.sqcNcG/proj/.cursor/hooks.json   — the same gate, for Cursor

  see it work in 30 seconds:
    rabadon drill        one tagged test event through the real gate
    rabadon usage        the ledger — drills excluded by design

  from here:
    claude               work normally in /private/tmp/f1a.sqcNcG/proj — the session is supervised
    rabadon on|off       enforce, or pause to watch-only
    rabadon remove       take it all back out (add --global here if you used it)

  disable exactly one rule with  "disabled": ["<rule-id>"]  in .rabadon/guard.json.

  the repair arm (the one place rabadon may call a model), set once, in config.json:
    "ask"           default. one line when the same error survives a third different
                    move after two hints; it runs on `rabadon repair --approve`.
    "auto-propose"  for unattended runs. runs without asking and NEVER touches your
                    tree — the patch waits at .rabadon/repair-<ts>.patch until you
                    type `rabadon repair --apply`.
    "off"           the arm is not there. the signals still reach the ledger.
```

Ekranla ilgili ölçülen kusurlar:
- İlk satırdaki hata metni **kesik**: `no manifes` (`manifest` değil).
  Sebep `hooks/manage.mjs:94` `String(e.message).slice(0, 120)`.
  Kullanıcının gördüğü ilk cümle yarım bir kelimeyle bitiyor.
- `claude` CLI makinede KURULU (`command -v claude` → `/opt/homebrew/bin/claude`)
  ama yazarlama yine de başarısız oldu: boş projede kanıt dosyası yok.
  Yani model ÇAĞRILMADI; ölçülen 0,546 s bu yüzden. LLM yazarlamalı bir
  projede süre ÖLÇÜLMEDİ.
- Ekran `rabadon on|off` diyor ama **hangi modda olduğunu söylemiyor**;
  kurulum sonrası modun WATCH olduğu bu ekranda hiçbir yerde yazmıyor.

---

## 3. KULLANICI NASIL KAÇAR — GERÇEK ÇIKTILAR

### `rabadon off` (0,018 s, exit 0)
```
rabadon: WATCH — recording what it WOULD have caught, touching nothing (`rabadon on` to act)
```
`off` = KAPALI DEĞİL, WATCH. Sonrasında aynı hook olayı:
```
rabadon (watch) would have blocked this.
...
exit=0
```
Gate her tool çağrısında hâlâ koşuyor ve ledger'a hâlâ yazıyor.

`rabadon status` (off sonrası):
```
rabadon: WATCH — recording what it WOULD have caught, touching nothing (`rabadon on` to act)
  read from: /tmp/f1a.sqcNcG/home/.rabadon/mode (absent — no file means WATCH)
```

### `rabadon remove` (0,043 s, exit 0)
```
rabadon remove: stripped 7 rabadon hook(s) from /private/tmp/f1a.sqcNcG/proj/.claude/settings.json
    - SessionStart: /private/tmp/f1a.sqcNcG/rabadon/native/rabadon-gate
    - UserPromptSubmit: /private/tmp/f1a.sqcNcG/rabadon/native/rabadon-gate
    - Stop: /private/tmp/f1a.sqcNcG/rabadon/native/rabadon-gate
    - Stop: /private/tmp/f1a.sqcNcG/rabadon/native/rabadon-drift
    - PreToolUse: /private/tmp/f1a.sqcNcG/rabadon/native/rabadon-gate
    - PostToolUse: /private/tmp/f1a.sqcNcG/rabadon/native/rabadon-gate
    - statusLine: /private/tmp/f1a.sqcNcG/rabadon/native/rabadon-gate --statusline
  (original backed up: settings.json.bak-rabadon)

  the ledger at ~/.rabadon/spool is yours and was left in place.
  fully uninstall the CLI with:  npm rm -g rabadon
```
`cat .claude/settings.json` sonrası → `{}`. Claude tarafı **temiz**.

### `rabadon uninstall --purge` (exit 0)
```
rabadon remove: no rabadon hooks found in /private/tmp/f1a.sqcNcG/proj/.claude/settings.json — nothing to strip.
  purged /private/tmp/f1a.sqcNcG/proj/.rabadon

  the ledger at ~/.rabadon/spool is yours and was left in place.
  fully uninstall the CLI with:  npm rm -g rabadon
```

### Kaçıştan sonra GERİDE KALANLAR (ölçüldü)
`find $TMP/proj -name .git -prune -o -type f -print` (remove + uninstall --purge sonrası):
```
/tmp/f1a.sqcNcG/proj/.claude/settings.json
/tmp/f1a.sqcNcG/proj/.claude/settings.json.bak-rabadon
/tmp/f1a.sqcNcG/proj/.cursor/hooks.json      <-- HÂLÂ TAM, HİÇ DOKUNULMADI
/tmp/f1a.sqcNcG/proj/.gitignore              <-- rabadon'un eklediği 2 satır duruyor
/tmp/f1a.sqcNcG/proj/index.js
```

`cat .cursor/hooks.json` (remove SONRASI): beş olayın beşi de hâlâ
`/private/tmp/f1a.sqcNcG/rabadon/native/rabadon-gate` çağırıyor.

`cat .gitignore` (purge sonrası):
```

.rabadon/state.json
.rabadon/handoff.md
```

Kod tarafı doğrulaması —
`grep -rn "removeCursorHooks\|\.cursor" hooks/`:
```
hooks/manage.mjs:158:    catch { /* an unwritable .cursor must not fail an otherwise good install */ }
hooks/install.mjs:240: * Merge the rabadon gate into <dir>/.cursor/hooks.json.
hooks/install.mjs:256:  const hooksPath = path.join(dir, '.cursor', 'hooks.json');
hooks/guard-gen.mjs:26:  'RULES.md', 'ENV.md', 'CLAUDE.md', 'AGENTS.md', '.cursorrules',
```
**`removeCursorHooks` diye bir fonksiyon yok.** `installCursorHooks` var,
karşılığı yok. Kaçış Claude için tam, Cursor için **hiç yok**.

**Hüküm:** geri dönüş VAR ama tam değil. Claude Code kullanıcısı tek komutla
(`rabadon remove`) çıkar. Cursor kullanıcısı ÇIKAMAZ — elle
`rm .cursor/hooks.json` yazmak zorunda, ve bunu hiçbir çıktı söylemiyor.

---

## 4. CURSOR SATIRI — YAPIYOR / YAPMIYOR / ÖLÇÜLEMEDİ

ENVANTER (b) "Cursor: 0 ledger satırı" diyordu. Yeniden ölçüldü, **doğrulandı**.

| # | konu | YAPIYOR | YAPMIYOR | ÖLÇÜLEMEDİ | basan komut |
|---|---|---|---|---|---|
| 1 | `rabadon init` `.cursor/hooks.json` yazıyor | ✔ 5 olay: `beforeShellExecution`, `beforeMCPExecution`, `afterFileEdit`, `beforeSubmitPrompt`, `stop` | | | `rabadon init && cat $TMP/proj/.cursor/hooks.json` |
| 2 | Cursor payload'ı gate'e verildiğinde REDDEDİYOR | ✔ **exit 2**, stdout'ta `{"permission":"deny",...}` | | | §4.2'deki `printf ... \| rabadon-gate` |
| 3 | Ledger'da Cursor kaynaklı SIGNAL/INJECT/COUNTER | | ✘ **0 satır** | | §4.3 `grep -a` |
| 4 | Ledger'da ajanı ayırt eden alan (`agent`/`dialect`/`editor`/`client`) | | ✘ **hiç yok** — Cursor ateşlese bile ledger'dan ATFEDİLEMEZ | | §4.3 ikinci `grep -a` |
| 5 | `rabadon remove` Cursor hook'unu siliyor | | ✘ silmiyor, `removeCursorHooks` yok | | §3 `find` + `grep -rn` |
| 6 | Dosya düzenlemesini ÖNCEDEN reddetme | | ✘ Cursor'da `beforeFileEdit` yok (`docs/agent-contract.md:74-76`) | | belge, kodla eşleşiyor (`install.mjs:257`) |
| 7 | Cursor bu makinede kurulu mu | ✔ `/Applications/Cursor.app` var, `~/.cursor/` var (argv.json, extensions, skills) | ✘ `command -v cursor` → PATH'te YOK; `~/.cursor` içinde `hooks.json` YOK | | `command -v cursor`, `ls /Applications \| grep -i cursor`, `ls -la ~/.cursor` |
| 8 | Cursor gerçek bir oturumda rabadon'u çağırdı mı | | | **ÖLÇÜLEMEDİ**: Cursor uygulaması bu ölçümde başlatılmadı (GUI, kart kapsamı dışı). Dolaylı kanıt: `~/.cursor/extensions` son değişim 25 Tem, repodaki `.cursor/hooks.json` 16 Ağu — hook dosyası yazıldıktan sonra Cursor'un o repoda koştuğuna dair iz yok | `ls -la ~/.cursor`, `ls -la <repo>/.cursor` |
| 9 | Cursor'da enjeksiyonun "geç" geldiği iddiası | | | **ÖLÇÜLEMEDİ**: enjeksiyon `likely` seviyeli sinyal ister; sentetik tek olayla üretilemedi | — |

### 4.2 Cursor payload'ı GERÇEKTEN reddediliyor (kanıt)

```sh
printf '{"hook_event_name":"beforeShellExecution","conversation_id":"cur-1","generation_id":"g1","cwd":"%s","command":"git push --force origin main"}' "$TMP/proj" \
  | "$TMP/rabadon/native/rabadon-gate"; echo "exit=$?"
```
stdout:
```json
{"permission":"deny","user_message":"rabadon: no-force-push-main — force-pushing a shared branch destroys history","agent_message":"rabadon BLOCKED this action.\nRule: no-force-push-main — force-pushing a shared branch destroys history\ncommand matched deny rule: git push --force origin main\nAdjust the approach instead of retrying the same action.\n(user override: add \"no-force-push-main\" to disabled[] in .rabadon/guard.json, or `rabadon off` to pause supervision)\n"}
```
`exit=2`.

Bu olayın ledger'a yazdığı iki satır (`grep -a 'cur-1' $TMP/home/.rabadon/spool/*.jsonl`):
```json
{"v":1,"seq":1,"ts":1787713572721,"run":"ng-13572720-38725","pipe":"proj:session","ev":"CHECK_FAIL","call":"g1","sess":"cur-1","step":"Bash","mode":"enforce","fails":[{"check":"no-force-push-main","why":"command matched deny rule: git push --force origin main — force-pushing a shared branch destroys history"}],"prev":"efa2e060..."}
{"v":1,"seq":2,"ts":1787713572721,"run":"ng-13572720-38725","pipe":"proj:session","ev":"STOP","call":"g1","sess":"cur-1","reason":"BLOCKED","rule":"no-force-push-main","sid":"cur-1","detail":"command matched deny rule: git push --force origin main","prev":"ab5f2d1d..."}
```
İki satırda da ajanı belirten HİÇBİR alan yok. `sess`/`call` yalnızca
Cursor'un `conversation_id`/`generation_id` değerlerini taşıyor —
bunlar Cursor'a özgü olmayan serbest metin.

### 4.3 SIFIR KANITI BASAN KOMUTLAR (birebir)

```sh
grep -ah "cursor" ~/.rabadon/spool/*.jsonl | grep -ac '"ev":"\(SIGNAL\|INJECT[A-Z_]*\|COUNTER\)"'
```
→ **`0`**

Cursor kelimesi geçen satırların TAMAMI (30 satır, 5 dosya) yalnızca şu tipler:
```sh
grep -ah cursor ~/.rabadon/spool/*.jsonl | grep -ao '"ev":"[A-Z_]*"' | sort | uniq -c
```
→
```
   1 "ev":"RUN_START"
  15 "ev":"STEP_OK"
  15 "ev":"STEP_START"
```
(ENVANTER kuralı: `STEP_*` kanıt sayılmaz. `RUN_START` de sayılmaz.)

Ajan alanı hiç yok:
```sh
grep -ah -o '"\(agent\|dialect\|editor\|client\)":"[a-z]*"' ~/.rabadon/spool/*.jsonl | sort | uniq -c
```
→ **boş çıktı**.

Karşılaştırma için tüm spool'un olay sayımı
(`for t in ...; do grep -ah -o "\"ev\":\"$t\"" ~/.rabadon/spool/*.jsonl | wc -l; done`):

| olay | sayı |
|---|---|
| `SIGNAL` | 2271 |
| `INJECT` | 6 |
| `INJECT_HELD` | 1 |
| `INJECT_CAPPED` | 0 |
| `COUNTER` | 368 |
| `STOP` | 1745 |
| `WOULD_BLOCK` | 1633 |
| `STEP_START` | 152125 |

(ENVANTER (b) `SIGNAL` için 2224 diyordu; bugünkü yeniden ölçüm **2271**.
Fark 47, aradan geçen sürede aynı makinede yazılan yeni satırlar.
`INJECT`=6, `INJECT_HELD`=1, `COUNTER`=368 birebir aynı.)

### 4.4 Cursor için tek cümlelik hüküm

Cursor payload'ı gate'te **mekanik olarak çalışıyor** (exit 2 + `permission:deny`
ölçüldü), `rabadon init` config'i **yazıyor**, ama **gerçek bir Cursor
oturumundan gelen tek bir ledger satırı yok**, ledger ajanı **ayırt edemiyor**,
ve `rabadon remove` Cursor hook'unu **sökmüyor**.

---

## BULDUĞUM AMA SORULMAYAN ŞEYLER

1. **`rabadon on` belgesiz ve zorunlu.** README'nin kurulum bloğu tamamlanınca
   guard WATCH modda kalır, hiçbir şeyi reddetmez. Ürün iddiası ("refuses
   the destructive command before the process starts") README'yi izleyen
   kullanıcıda GERÇEKLEŞMEZ. Bu, adım sayısından daha büyük bir bulgudur.
2. **`rabadon off` kapatmıyor**, WATCH'a düşürüyor: gate her tool çağrısında
   hâlâ koşar, ledger'a hâlâ yazar. "off" kelimesi yaptığı işi anlatmıyor.
3. **README ile site kurulum satırı ÇELİŞİYOR** (`npm install && npm link` vs
   `make`). İkisi de çalışıyor (ikisi de ölçüldü), ama kullanıcı hangisini
   okuduğuna göre farklı sayıda komut yazıyor.
4. **`npm link` 4 satır `npm warn allow-scripts` uyarısı basıyor** ve
   `npm approve-scripts` çalıştırmayı öneriyor — "zero-config, no questions"
   çıtasına göre bu, kurulumun ortasında kullanıcıya sorulmuş bir sorunun
   yarısıdır.
5. **`init` hata mesajı kesik**: `no manifes` (`manage.mjs:94`, `slice(0,120)`).
6. **`init` `.gitignore`'a yazıyor** ve `remove --purge` bunu geri almıyor.
7. **`rabadon remove` çıktısı `npm rm -g rabadon` diyor** — ama README kurulumu
   `npm link` ile yapıyor; doğru komut `npm rm -g rabadon` değil `npm unlink`
   olurdu. DOĞRULANMADI: `npm rm -g rabadon`'un link'lenmiş kurulumda işe
   yarayıp yaramadığı koşulmadı (gerçek makineye dokunurdu).
8. **ÖLÇÜLEMEDİ**: temiz bir Linux konteynerde kurulum; `npm i -g rabadon`
   (yayımlanmamış, kart dışı); LLM yazarlamalı `init`in süresi ve ekranı;
   `rabadon init --global` yolu (gerçek `~/.claude/settings.json`'a yazardı);
   Cursor uygulamasını başlatıp gerçek bir hook olayı üretmek.
9. Kum havuzu ölçüm sonunda silinmedi: `/tmp/f1a.sqcNcG`. İçinde klon, derlenmiş
   ikililer, sahte ev ve `npmprefix` var. Gerçek `rabadon` PATH'te hâlâ
   `/opt/homebrew/bin/rabadon` (ölçüm sırasında doğrulandı, değişmedi).
