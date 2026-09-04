# ENVANTER — F0/KART 1

Ölçüm tarihi: 2026-08-26. Ölçüm yeri: `/Users/damummyphus/damla_projects_2026/rabadon-kosu4`,
dal `kosu4`, HEAD `e6deafe708550c9875837dd71721a27ebe42527d`.

**Bu dosya belgeye değil ÖLÇÜME dayanır.** Sonraki fazlar KOSU-RABADON-5.md §6'ya değil
buraya bakar. Her satırın yanında onu basan komut vardır. Ölçülemeyen "ÖLÇÜLEMEDİ: sebep"
diye yazılıdır.

Ayrıntılı işçi raporları:
`reports/kosu/RAPOR/envanter-a-sinyaller.md`,
`reports/kosu/RAPOR/envanter-b-ajan-yuzeyi.md`,
`reports/kosu/RAPOR/envanter-c-site-cli.md`,
`reports/kosu/RAPOR/envanter-d-test-npm.md` (+ `envanter-d-test.out`, `envanter-d-build.out`),
`reports/kosu/RAPOR/envanter-e-r7accept-before.out`.

---

## (a) SİNYALLER: tanımlı mı, çağrılıyor mu

Kaynak boyutları — `wc -l native/gate.cpp native/signals.h native/inject.h native/counter.h`:
gate.cpp **4733**, signals.h **224**, inject.h **201**, counter.h **339**.

| sinyal | tanım (dosya:satır) | gate'ten çağrılıyor mu | enjekte ediyor mu | koşul |
|---|---|---|---|---|
| `repeat` | signals.h:128 | EVET (gate.cpp:3162) | HAYIR (inject.h:87 `return false`) | sadece ledger satırı |
| `oscillation` | signals.h:149 | EVET (gate.cpp:3162) | EVET (inject.h:82) | son hamle edit, aynı path'te 6 edit, A-B-A-B-A-B |
| `root_migration` | signals.h:162 | EVET (gate.cpp:3162) | EVET; tek REPAIR tetikleyicisi (gate.cpp:3053) | `err_sig` dolu (PostToolUse), ≥3 farklı imza |
| `scope_drift` | signals.h:172 | EVET | HAYIR | eşik 5 dizin, sadece ledger |
| `green_redefined` (a) | signals.h:182 | EVET | HAYIR | bloklamayı ayrı kural `red-suite-test-write` yapıyor (gate.cpp:4648) |
| `green_redefined` (b) | signals.h:203 | EVET | EVET (inject.h:84-85) | `why` içinde "only the test side" aranıyor |
| `green_redefined` (c) | signals.h:214 | EVET | HAYIR | — |
| `semantic_repeat` | semantic.h:360 | KOŞULLU | EVET | `RABADON_SEM!=0` **ve** `RABADON_SIGNALS!=0` **ve** son hamle edit **ve** tier-0 hash eşleşmesi yok **ve** Jaccard≥0.80 **ve** 3 hit |

Komut: `grep -n "repeat\|oscillation\|root_migration\|green_redefined\|scope_drift" native/signals.h native/semantic.h native/gate.cpp native/inject.h`
(tam çıktı ve çağrı zinciri adım adım `reports/kosu/RAPOR/envanter-a-sinyaller.md` içinde).

- **TANIMLI AMA HİÇ ÇAĞRILMAYAN sinyal YOK.** Sinyal adı sayısı 8 (belgedeki 4 değil);
  **aksiyona (enjeksiyona) dönüşen sinyal sayısı 4**, kalan 4 yalnız ledger'a yazar.
- INJECT yolu gate'ten gerçekten çağrılıyor: kuyruklama `gate.cpp:3018` `rbinject::build`,
  teslim `gate.cpp:4707` `hookSpecificOutput` / `additionalContext`.
  4200–4697 arasında düz `return 0` yok, yani PreToolUse bloklanmadıysa teslim noktasına varılıyor.
- Ortak kapılar (gate.cpp): `RABADON_OFF` / `.rabadon/off` / `~/.rabadon/silent` (2658),
  yalnız Pre/PostToolUse (2876), yalnız Bash/Edit/Write/MultiEdit (2877),
  `RABADON_MOVES`, `RABADON_SIGNALS`, `RABADON_INJECT`, `CAP_PER_SIGNAL=2`, `MAX_CHARS=400`.
- ÖLÇÜLEMEDİ: `move.suite` alanının nerede doldurulduğu izlenmedi. Hiç set edilmiyorsa
  `green_redefined` (a) ve (b) hiç ateşlemez. Ayrı ölçüm ister — F1b/F2'nin işi.

---

## (b) AJAN YÜZEYİ: kim GERÇEKTEN bağlı (kanıt = ledger satırı)

Kural: `STEP_START` kanıt sayılmaz. Kanıt `INJECT` / `INJECT_CAPPED` / `INJECT_HELD` /
`SIGNAL` / `COUNTER` satırıdır.

| ajan yüzeyi | ledger kanıtı | tarih | dosya |
|---|---|---|---|
| Claude Code | **VAR** — 6 `INJECT`, 1 `INJECT_HELD`, 2224 `SIGNAL`, 368 `COUNTER` | 2026-08-22 → 2026-08-26 | `~/.rabadon/spool/2026-08-2{2,3,4,5,6}.jsonl` |
| Cursor | **YOK** — 0 satır | — | `.cursor/hooks.json` 16 Ağu'dan beri var, tek satır üretmemiş |
| generic / `docs/agent-contract.md` | **YOK** — 0 satır, config de yok | — | — |
| Windsurf / Codex / Aider | kurulum kodu bile yok | — | — |

Komutlar (ayrıntı işçi raporunda): `find ~/.rabadon /Users/.../rabadon* -name '*.jsonl'`,
`grep -ac '"INJECT"' <dosya>` vb.

**Ölçümün açtığı ek gerçekler (sorulmadı, önemli):**
- `SIGNAL`/`INJECT`/`COUNTER` satırları **2026-08-22'de doğmuş**; ondan önceki 26 günün
  tamamı sıfır. "Ajana bağlı" iddiasının ledger ömrü **5 gün**.
- Kanıtın çoğu **başka bir repodan** geliyor (`stitchu`, 32946 satır). `rabadon-kosu4`
  yalnız 241 satır. Yani rabadon kendi koşusunda değil, komşu projede iz bırakmış.
- Global hook `rabadon/native/rabadon-gate` (23 Ağu tarihli ikili) çağırıyor —
  **kosu4'teki kaynak canlı değil**. kosu4 worktree'sinde `.claude` ve `.cursor` dizini yok.
- `DENY`/`BLOCK` diye olay tipi yok; karşılıkları `STOP` (1745) ve `WOULD_BLOCK` (1607).
  Ayrıca `WRONG_REFUSAL`: **6**.
- Repo içindeki hiçbir `.jsonl`'de INJECT/SIGNAL/COUNTER yok — kanıtın tamamı yerel,
  git'e girmiyor (`.gitignore`).
- 150 satır zincir dışında (`*.unchained.jsonl` × 3).
- **Ölçüm tuzağı:** UTF-8 dışı bayt yüzünden `grep -c` bazı günlük dosyalarda sessizce
  boş dönüyor. `grep -a` şart. Bu tuzağa düşen her önceki sayım şüphelidir.
- ÖLÇÜLEMEDİ: zincir bütünlüğü (`rabadon audit` koşulmadı); Cursor'un bu makinede kurulu
  olup olmadığı; 07-27 öncesi ve 08-06/08-07 günleri.

---

## (c) site/index.html HANGİ ÜRÜNÜ SATIYOR (verbatim)

- `<title>` — verbatim: `rabadon, guardrails and a verifiable record for coding agents`
- `<h1>` — verbatim: `run your coding agent without watching it.`
- İlk ekran cümlesi — verbatim: *"It refuses the destructive command before the process
  starts, writes a receipt you can verify afterwards, and when a check goes red it repairs
  the code without being able to buy its own green."*
- Kurulum satırı — verbatim:
  `git clone https://github.com/nosey-dewdrop/rabadon && cd rabadon && make`
  **`npm i -g` sayfada YOK.**
- Sayfada duran komut adları (5): `watch`, `on`, `usage`, `repair`, `audit`.
- Kelime sayımı (`grep -c`): **"compound error" 0**, **"injection" 0** — iki sayfada da hiç geçmiyor.
- Kökteki `/index.html` başka bir ürün anlatıyor ("touch the grass!", "not a finished
  product yet") ve ölü bir github.io canonical'ı ilan ediyor. Yayınlanan dosya
  `site/index.html` (vercel → rabadon.noseydewdrop.com, `scripts/publish-field.sh:339`).
- Sayfa kendi sayılarıyla çelişiyor: headline **508** vs `usage` çıktısı **461** — sayfa
  bunu itiraf ediyor.
- Sayılar tam listesi ve geçtikleri cümleler: `reports/kosu/RAPOR/envanter-c-site-cli.md`.

**Hüküm:** landing, §1'in reddettiği ürünü satıyor (guardrail + makbuz + red).
Compound error, "sen uyurken ajan bozmaz" ve enjeksiyon sayfada hiç geçmiyor.

---

## (d) CLI YÜZEYİ: kaç verb

| ölçüm | sayı | komut |
|---|---|---|
| ana `--help` ekranındaki verb | **5** (`init`, `on\|off`, `usage`, `repair`, `doctor`) | `./native/rabadon-cli.sh --help` (exit 0) |
| `dev` ekranındaki verb | **30** | `./native/rabadon-cli.sh dev --help` |
| dispatcher'da yazılabilen toplam | **44** | `native/rabadon-cli.sh` case dalları sayımı |

- `--help` gerçekten koştu, exit 0, 19/19 ikili derli.
- Sayfadaki 5 komut ile help'teki 5 komut **aynı değil**: `watch` ve `audit` ana help'te
  yok, `init` sayfada yok.
- `guard`, `fleet`, `spin`, `pack`: çalışan ama hiçbir belgesi olmayan 4 verb.

---

## (e) TEST / KABUL DURUMU

**İki ayrı süit var, biri ötekini çağırmıyor.**

| süit | komut | sonuç | süre | kırmızı ADLARI |
|---|---|---|---|---|
| native | `make test` (Makefile:104, 100 adet `./native/*_test.sh`) | EXIT 0, **3438 ok / 0 failed** | 5 dk 17,73 s | YOK |
| node | `npm test` (package.json:25, `node --test`, 9 dosya) | EXIT 0, **64 pass / 0 fail** | 1,75 s | YOK |
| **toplam test** | | **3502 yeşil / 0 kırmızı** | | **kırmızı listesi BOŞ** |
| R7 kabul | `bash reports/R7/accept.sh` | EXIT 1, **23 yeşil / 3 kırmızı** | — | **`2b`, `6e`, `7b`** |

Derleme: `make all` EXIT 0, 21 ikili, 32,5 s. Tek uyarı: `drift.cpp:240 unused function`.
Derleme kırık DEĞİL.

Kırmızıların tam metni (`grep -n "^FAIL" reports/kosu/RAPOR/envanter-e-r7accept-before.out`):
- `FAIL  2b the gate's median is 1299.4 us with the daemon up, ceiling is 1000 us`
- `FAIL  6e counter validation impossible: no 'estimated_saved' total on arm B, or no per-arm total_cost_usd`
- `FAIL  7b falsification 2 is UNCHECKABLE — no deviation could be computed`

**F0 SONRASI KARŞILAŞTIRMA İÇİN DONDURULAN KIRMIZI AD KÜMESİ (§8.3):**
`{ 2b, 6e, 7b }` — test süitlerinde kırmızı ad yok.

Ölçüm tuzağı: `envanter-d-test.out:3917` satırındaki `FAIL testsuite [node --test]... RED`
**kırmızı değildir**, `regression_demo.sh`'ın fikstür çıktısıdır (hemen altında
`regression: 4 passed, 0 failed`). Bu satırı kırmızı sayan her sayım yanlıştır.

ÖLÇÜLEMEDİ: temiz makinede / fresh clone'da koşum, Linux'ta koşum, süitlerin tek tek koşumu.

---

## (f) npm DURUMU

- `npm view rabadon version` → **E404**, `rabadon` registry'de hiç yayımlanmamış.
- `@rabadon/{darwin,linux}-*` dört paketin dördü de E404.
- `package.json`: `name: rabadon`, `version: **0.2.3**`.
- `git tag --list`: `v0.2.0`, `v0.2.1`, `v0.2.2` — **v0.2.3 etiketi yok.**
- `npm publish --dry-run` KOŞULMADI (gece modu, para/geri alınamaz iş yasağı).

---

## (g) REPO TOPOLOJİSİ

`git worktree list`:
```
/Users/damummyphus/damla_projects_2026/rabadon        30d5cbb [main]
/Users/damummyphus/damla_projects_2026/rabadon-kosu2  6f5d301 [kosu2]
/Users/damummyphus/damla_projects_2026/rabadon-kosu3  cfe5f25 [kosu3]
/Users/damummyphus/damla_projects_2026/rabadon-kosu4  e6deafe [kosu4]
```
Asıl klon **`/Users/damummyphus/damla_projects_2026/rabadon`** (main), diğer üçü onun worktree'si.

- `git log --oneline main..kosu4 | wc -l` → **108** (belge 107 diyor, bkz. ÇELİŞKİLER).
- `git log --oneline kosu4..main | wc -l` → **0**.
- `git merge-base --is-ancestor main kosu4` → **exit 0**, yani `main` `kosu4`'ün atası.
  **`git merge --ff-only kosu4` MÜMKÜNDÜR.**
- `git log --branches --not --remotes --oneline | wc -l` → **0**. Uzağa gitmemiş commit YOK.
- Dallar: `kosu2` (6f5d301), `kosu3` (cfe5f25), `kosu4` (e6deafe), `main` (30d5cbb);
  dördünün de `origin/` karşılığı aynı hash'te.

---

## ÇELİŞKİLER: KOSU-RABADON-5.md §6 vs ÖLÇÜM

| § 6 ne diyor | ölçüm ne diyor | kanıt |
|---|---|---|
| "arada 107 commit" | **108** | `git log --oneline main..kosu4 \| wc -l` |
| "Dört sinyal adıyla kodda" | **8 sinyal adı**; 4'ü enjekte ediyor, 4'ü yalnız ledger'a yazıyor | (a) tablosu |
| "ledger'da 51 satırın 51'i STEP_START, sıfır INJECT" | **`~/.rabadon/spool/` içinde 6 INJECT + 1 INJECT_HELD + 2224 SIGNAL + 368 COUNTER var** (22–26 Ağu). §6'nın baktığı ledger repo içindeki R7 koşusu; canlı spool başka yerde. §6 cümlesi eksik, yanlış değil — ama "enjeksiyon hiç ulaşmadı" hükmü bu spool'a bakarak yeniden ölçülmelidir | (b) tablosu |
| "Kabul 23 yeşil 3 kırmızı" | **DOĞRULANDI** — R7 accept.sh 23/3, adlar `2b`, `6e`, `7b` | `bash reports/R7/accept.sh` |
| "Yüzey 25 verb" | ana help **5**, dev **30**, dispatcher **44**. 25 rakamı hiçbir ölçümle eşleşmiyor | `native/rabadon-cli.sh` |
| "npm 404, sürüm 0.2.3" | **DOĞRULANDI** | `npm view rabadon version`, `package.json` |
| §7/F7: "başlık bugün *guardrails and a verifiable record for coding agents* diyor" | **DOĞRULANDI**, verbatim | `site/index.html` `<title>` |
| §7/F7: "sayfadaki beş komut (`watch`, `on`, `usage`, `repair`, `audit`)" | **DOĞRULANDI** | `site/index.html` |
| §7/F7: "kurulum satırı `git clone && make`" | **DOĞRULANDI**, verbatim | `site/index.html` |
| §7/F0: "Uzağa gitmemiş commit yok, ff-only mümkün" | **DOĞRULANDI** | `git merge-base --is-ancestor` |

**En büyük çelişki:** §6 "enjeksiyon hiç ulaşmadı" diyor. Ölçüm, canlı spool'da 6 INJECT
satırı gösteriyor — ama bunlar **başka bir repoda** (`stitchu`) ve **23 Ağu tarihli bir
ikiliden** doğmuş; kosu4'teki kaynak canlı değil. Yani "yazdı" katmanı (§4.12/a) için zayıf
bir kanıt vardır, "okundu" (b) ve "zarar vermedi" (c) katmanları için HİÇ kanıt yoktur.
F3'ün kabulü bu ayrımı korumalıdır.
