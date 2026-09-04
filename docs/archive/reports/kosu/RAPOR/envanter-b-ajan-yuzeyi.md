# ENVANTER B — AJAN YÜZEYİ: hangi ajan rabadon'a GERÇEKTEN bağlı?

Tarih: 2026-08-26. Repo: `/Users/damummyphus/damla_projects_2026/rabadon-kosu4` (dal: `kosu4`).
Kural: `STEP_START` KANIT DEĞİLDİR. Kanıt = `INJECT` / `INJECT_CAPPED` / `INJECT_HELD` / `SIGNAL` / `COUNTER`.

---

## SONUÇ (tek cümle)

Ledger'da bağlanma kanıtı olan TEK ajan yüzeyi **Claude Code**'dur. Cursor ve
"generic (agent-contract)" yüzeyleri KOD'da vardır ama hiçbir ledger satırı
üretmemiştir.

---

## 1. Ledger dosyalarının tam listesi

Ledger'ın gerçek adresi koddan sabitlendi:

```
grep -n "RABADON_DIR\s*=" /Users/damummyphus/damla_projects_2026/rabadon-kosu4/core/bus.mjs
29:export const RABADON_DIR = process.env.RABADON_DIR || path.join(os.homedir(), '.rabadon');
```
```
grep -n "spool\|jsonl" /Users/damummyphus/damla_projects_2026/rabadon-kosu4/core/bus.mjs
31:export const SPOOL_DIR = path.join(RABADON_DIR, 'spool');
158:  path.join(SPOOL_DIR, `${day}.jsonl`);
```

Yani canlı ledger = `~/.rabadon/spool/<gün>.jsonl`.

### 1a) Repo içindeki .jsonl dosyaları

```
find /Users/damummyphus/damla_projects_2026/rabadon-kosu4 -type f \( -name "*.jsonl" -o -name "ledger*" -o -name "events*" \) -not -path "*/node_modules/*"
```
```
native/precision_fixture.jsonl
native/ledger_utf8_test.sh
native/ledger_day_test.sh
redteam/ledger_replay.py
redteam/ledger_label.py
site/field.jsonl
site/findings.jsonl
demo/fixtures/live-repair-2026-07-26.jsonl
docs/cast/frames.jsonl
docs/kanit/2026-08-01-g3-first-held-repair/04-ledger-events.jsonl
reports/2026-08-01-g3-first-held-repair/04-ledger-events.jsonl
reports/R7/ab_run_INVALID_muted_hook.jsonl
reports/R7/ab_run_INVALID_global_hook.jsonl
reports/R7/ab_run.jsonl
```

### 1b) Yereldeki (ev dizini) ledger dizinleri

```
find /Users/damummyphus -maxdepth 4 -name ".rabadon" -type d
```
→ 90+ `.rabadon` dizini bulundu (çoğu boş iskelet). Bunlardan gerçekten spool
içerenler:

```
find /Users/damummyphus -maxdepth 6 -path "*/.rabadon/spool/*.jsonl"
```
- `/Users/damummyphus/.rabadon/spool/` → 29 günlük dosya + 3 `.unchained.jsonl` (ANA LEDGER)
- `/Users/damummyphus/damla_projects_2026/rabadon/.rabadon/spool/` → 12 dosya
- `/Users/damummyphus/damla_projects_2026/rabadon-kosu2/.rabadon/spool/2026-08-24.jsonl`
- `/Users/damummyphus/damla_projects_2026/rabadon-kosu3/.rabadon/spool/2026-08-24.jsonl`

---

## 2. Olay tipi sayımı

> NOT: bazı dosyalar UTF-8 dışı bayt içerdiği için düz `grep -c` "binary file"
> deyip 1 ile çıkıyor (ölçüm hatası). Aşağıdaki tüm sayımlar `grep -ac` ile alındı.
> Kanıt: `grep -c '"ev":"STEP_START"' 2026-07-30.jsonl` → exit=1, çıktı yok;
> `grep -ac ...` → `1843`.

### 2a) ANA LEDGER — `~/.rabadon/spool/`

Basan komut:
```
cd /Users/damummyphus/.rabadon/spool && for f in *.jsonl; do \
  printf "%s %s %s %s %s %s %s %s\n" "$f" "$(wc -l < $f)" \
  "$(grep -ac '"ev":"STEP_START"' $f)" "$(grep -ac '"ev":"SIGNAL"' $f)" \
  "$(grep -ac '"ev":"INJECT"' $f)" "$(grep -ac '"ev":"INJECT_CAPPED"' $f)" \
  "$(grep -ac '"ev":"INJECT_HELD"' $f)" "$(grep -ac '"ev":"COUNTER"' $f)"; done
```

| dosya | toplam | STEP_START | SIGNAL | INJECT | INJECT_CAPPED | INJECT_HELD | COUNTER | DENY | BLOCK |
|---|---|---|---|---|---|---|---|---|---|
| 2026-07-27.jsonl | 9182 | 3790 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-07-28.jsonl | 4042 | 1709 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-07-29.jsonl | 8117 | 3852 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-07-30.jsonl | 3902 | 1843 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-07-31.jsonl | 12439 | 6679 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-01.jsonl | 35553 | 21116 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-01.unchained.jsonl | 32 | 21 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-02.jsonl | 10017 | 6424 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-03.jsonl | 2649 | 1319 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-04.jsonl | 4963 | 2527 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-05.jsonl | 1782 | 818 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-08.jsonl | 747 | 309 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-09.jsonl | 1472 | 779 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-10.jsonl | 1044 | 561 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-11.jsonl | 460 | 261 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-12.jsonl | 501 | 273 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-13.jsonl | 969 | 489 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-14.jsonl | 3457 | 1762 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-15.jsonl | 1070 | 512 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-16.jsonl | 18947 | 11846 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-17.jsonl | 17830 | 13599 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-17.unchained.jsonl | 40 | 32 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-18.jsonl | 4849 | 2594 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-19.jsonl | 10219 | 6658 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-20.jsonl | 9616 | 6065 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-21.jsonl | 29589 | 23803 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2026-08-21.unchained.jsonl | 78 | 69 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| **2026-08-22.jsonl** | 8889 | 4713 | **303** | **1** | 0 | 0 | 0 | 0 | 0 |
| **2026-08-23.jsonl** | 6315 | 4044 | **135** | **3** | 0 | 0 | **46** | 0 | 0 |
| **2026-08-24.jsonl** | 22629 | 13912 | **607** | **1** | 0 | 0 | **310** | 0 | 0 |
| **2026-08-25.jsonl** | 14140 | 8906 | **1163** | **1** | 0 | **1** | **11** | 0 | 0 |
| **2026-08-26.jsonl** | 633 | 305 | **16** | 0 | 0 | 0 | **1** | 0 | 0 |

Tüm ledger'da olay tipi dağılımı (basan komut:
`cat *.jsonl | LC_ALL=C grep -ao '"ev":"[A-Z_]*"' | sort | uniq -c | sort -rn`):

```
151600 STEP_START   77944 STEP_OK      4591 CHECK_FAIL   2780 RUN_DONE
  2224 SIGNAL        1745 STOP         1607 WOULD_BLOCK  1174 RUN_START
   919 TEST_EVIDENCE_MISSING   542 REPAIR_START   368 COUNTER
   170 REPAIR_FAIL    152 PARSE_LIMIT   151 CONTRACT   107 REPAIR_OK
    80 MODE            16 PARSE_DEGRADED  11 CHECK_SKIPPED
     6 WRONG_REFUSAL    6 INJECT          1 INJECT_HELD
```
`DENY` ve `BLOCK` adında olay tipi ledger'da HİÇ YOK (0). Karşılığı `STOP`
(1745) ve `WOULD_BLOCK` (1607).

### 2b) Repo içindeki .jsonl dosyaları (fixture/kanıt/rapor)

Basan komut: yukarıdaki `grep -ac` döngüsünün repo yollarıyla çalıştırılmışı.

| dosya | toplam | STEP_START | SIGNAL | INJECT | CAPPED | HELD | COUNTER |
|---|---|---|---|---|---|---|---|
| native/precision_fixture.jsonl | 34 | 0 | 0 | 0 | 0 | 0 | 0 |
| site/field.jsonl | 592 | 0 | 0 | 0 | 0 | 0 | 0 |
| site/findings.jsonl | 45 | 0 | 0 | 0 | 0 | 0 | 0 |
| demo/fixtures/live-repair-2026-07-26.jsonl | 7 | 1 | 0 | 0 | 0 | 0 | 0 |
| docs/kanit/2026-08-01-g3-first-held-repair/04-ledger-events.jsonl | 10 | 0 | 0 | 0 | 0 | 0 | 0 |
| reports/2026-08-01-g3-first-held-repair/04-ledger-events.jsonl | 10 | 0 | 0 | 0 | 0 | 0 | 0 |
| reports/R7/ab_run.jsonl | 8 | 0 | 0 | 0 | 0 | 0 | 0 |
| reports/R7/ab_run_INVALID_muted_hook.jsonl | 2 | 0 | 0 | 0 | 0 | 0 | 0 |
| reports/R7/ab_run_INVALID_global_hook.jsonl | 2 | 0 | 0 | 0 | 0 | 0 | 0 |
| docs/cast/frames.jsonl | 9 | 0 | 0 | 0 | 0 | 0 | 0 |

→ **Repo içinde tek bir INJECT/SIGNAL/COUNTER satırı yok.** Kanıt yalnızca
`~/.rabadon/spool/` altında, git'e girmiyor.

### 2c) Proje-yerel spool'lar (RABADON_DIR override ile yazılmış)

| dosya | toplam | STEP_START | SIGNAL | INJECT | CAPPED | HELD | COUNTER |
|---|---|---|---|---|---|---|---|
| rabadon-kosu2/.rabadon/spool/2026-08-24.jsonl | 24 | 8 | 0 | 0 | 0 | 0 | 0 |
| rabadon-kosu3/.rabadon/spool/2026-08-24.jsonl | 3 | 1 | 0 | 0 | 0 | 0 | 0 |
| rabadon/.rabadon/spool/2026-08-04.jsonl | 6 | 0 | 0 | 0 | 0 | 0 | 0 |
| rabadon/.rabadon/spool/2026-08-05.jsonl | 33 | 11 | 0 | 0 | 0 | 0 | 0 |
| rabadon/.rabadon/spool/2026-08-08.jsonl | 18 | 6 | 0 | 0 | 0 | 0 | 0 |
| rabadon/.rabadon/spool/2026-08-14.jsonl | 45 | 15 | 0 | 0 | 0 | 0 | 0 |
| rabadon/.rabadon/spool/2026-08-15.jsonl | 21 | 7 | 0 | 0 | 0 | 0 | 0 |
| rabadon/.rabadon/spool/2026-08-16.jsonl | 12 | 4 | 0 | 0 | 0 | 0 | 0 |
| rabadon/.rabadon/spool/2026-08-17.jsonl | 33 | 11 | 0 | 0 | 0 | 0 | 0 |
| rabadon/.rabadon/spool/2026-08-20.jsonl | 66 | 22 | 0 | 0 | 0 | 0 | 0 |
| rabadon/.rabadon/spool/2026-08-21.jsonl | 12 | 4 | 0 | 0 | 0 | 0 | 0 |
| rabadon/.rabadon/spool/2026-08-22.jsonl | 75 | 25 | 0 | 0 | 0 | 0 | 0 |
| rabadon/.rabadon/spool/2026-08-23.jsonl | 12 | 4 | 0 | 0 | 0 | 0 | 0 |

Hepsi sıfır kanıt — bunlar test koşularının artığı.

---

## 3. INJECT / INJECT_HELD satırlarının tam dökümü (7 satırın hepsi)

Basan komut:
```
cd /Users/damummyphus/.rabadon/spool && for f in 2026-08-2{2,3,4,5}.jsonl; do \
  grep -ah '"ev":"INJECT"\|"ev":"INJECT_HELD"' $f; done
```

| dosya | olay | tarih (yerel) | pipe | call id |
|---|---|---|---|---|
| 2026-08-22.jsonl | INJECT | 2026-08-23 02:44:43 | stitchu:session | toolu_01PMAmp8bjyqNpb8omRiNVq9 |
| 2026-08-23.jsonl | INJECT | 2026-08-23 04:03:12 | video-essay:session | toolu_01AUFDnFw6YGv1pLLaLRBQ2u |
| 2026-08-23.jsonl | INJECT | 2026-08-23 04:04:36 | video-essay:session | toolu_016pYSCYwYuJgn88qGgf8EVf |
| 2026-08-23.jsonl | INJECT | 2026-08-23 04:04:36 | video-essay:session | toolu_01FR1vL1XmrYgaUJpbEAZN2v |
| 2026-08-24.jsonl | INJECT | 2026-08-24 17:08:55 | HIPS__autograd...pr_579__B:session | toolu_01Xkzbs7NXT77opwG8tKTFr6 |
| 2026-08-25.jsonl | INJECT_HELD | 2026-08-25 03:09:58 | stitchu:session | toolu_017TF4cXxMuq2NQdPhk7ybcK |
| 2026-08-25.jsonl | INJECT | 2026-08-25 03:10:56 | stitchu:session | toolu_01DJR1Wf3MtbBjCDm3mXmxSE |

### 3 örnek, verbatim (uzun `text` alanı 700 karakterde kesildi)

**(1) İlk INJECT — 2026-08-23 02:44:43, `~/.rabadon/spool/2026-08-22.jsonl`**
```json
{"v":1,"seq":2,"ts":1787442283973,"run":"ng-42283971-40439","pipe":"stitchu:session","ev":"INJECT","call":"toolu_01PMAmp8bjyqNpb8omRiNVq9","sess":"6e702d85-8a28-4d85-a80f-3eac2dfff422","signal":"root_migration","chars":400,"text":"rabadon: attempt 3 on the same failure. The file last edited is engine/CMakeLists.txt. The previous attempt ended with: {\"stdout\":\"error: unknown option `cached'\\nusage: git status [<options>] [--] [<pathspec>...]\\n\\n -v, --verbose be verbo. Contrast: no green move is on record this session; after `git add engine/src/bodice.cpp engine/src/bodice.hpp engine/CMakeLists.txt engine/tests/garment_` it ","prev":"587579364176613310cb295d14c3566f66d2117ab3875b4a67ce3
```

**(2) Tek INJECT_HELD — 2026-08-25 03:09:58, `~/.rabadon/spool/2026-08-25.jsonl`**
```json
{"v":1,"seq":4,"ts":1787616598320,"run":"ng-16598319-7519","pipe":"stitchu:session","ev":"INJECT_HELD","call":"toolu_017TF4cXxMuq2NQdPhk7ybcK","sess":"8e263345-d3ec-4210-a0b1-4691d84a6c1a","signal":"semantic_repeat","behind":"semantic_repeat","prev":"aa404f956939afe99860239dd198de43ed3da5a71498abd2babffa6b22ec0953"}
```

**(3) SIGNAL örneği — 2026-08-25, `~/.rabadon/spool/2026-08-25.jsonl`**
```json
{"v":1,"seq":1,"ts":1787616237160,"run":"ng-16237158-2137","pipe":"stitchu:session","ev":"SIGNAL","call":"toolu_01EH6XDYqmiNNPPh7ojNjChk","sess":"8e263345-d3ec-4210-a0b1-4691d84a6c1a","signal":"scope_drift","conf":0.40,"why":"5 directories touched","seqs":[2671],"prev":"004f3a20217a0bebab85d34672cfec2943b6d1e05e5988e6e26600ae95babddf"}
```

**COUNTER örneği — `~/.rabadon/spool/2026-08-24.jsonl`** (`model":"claude-opus-5"` alanına dikkat):
```json
{"v":1,"seq":2,"ts":1787533613125,"run":"ng-33612912-74971","pipe":"damummyphus:session","ev":"COUNTER","sess":"1d2a07be-3f48-4f0a-89c8-fc93bb9c81c0","chains_cut":0,"fixed":0,"injections":0,"saved_usd":null,"gross_usd":0,"reason":"no-chains","median_uncut":1,"median_n":3,"samples":[1,1,1],"avg_call_usd":null,"session_usd":0,"calls":0,"tok_in":0,"tok_cw":0,"tok_cr":0,"tok_out":0,"inject_usd":0,"inject_bound":"upper","repair_usd":0,"repair_tok_in":0,"repair_tok_out":0,"model":"claude-opus-5","pric
```

### Bu satırlar HANGİ ajandan geldi? (yüzey ataması)

Ledger satırında "ajan adı" diye bir alan YOK. Ama `call` alanı yüzeyi ele
veriyor. Koddan: Claude Code'da `toolUseId = tool_use_id`, Cursor'da
`toolUseId = generation_id`:
```
grep -n "toolUseId" /Users/damummyphus/damla_projects_2026/rabadon-kosu4/native/hookev.h
  (Claude) e.toolUseId = rbrules::get_str(raw, "tool_use_id");
  (Cursor)  e.toolUseId = rbrules::get_str(raw, "generation_id");
```
Ledger'daki tüm call id prefiksleri (basan komut:
`grep -aho '"call":"[^"]\{0,12\}' *.jsonl | sed 's/"call":"//' | cut -c1-6 | sort | uniq -c | sort -rn`):
```
154526 toolu_
     4 fwd1
     3 fwd2
```
- `toolu_` = Anthropic tool_use_id formatı → **Claude Code**.
- `fwd1`/`fwd2` = 7 satır, hepsi `2026-08-20.jsonl`, `"sess":"phase1-fwd"`,
  `"pipe":"pg-live:session"` — bir push-gate test koşusunun sentetik id'si,
  ajan yüzeyi değil. (Bu 7 satırın hiçbiri INJECT/SIGNAL/COUNTER değil:
  REPAIR_START/REPAIR_FAIL/REPAIR_OK/CHECK_FAIL/WOULD_BLOCK/STEP_START.)
- Cursor `generation_id` formatında TEK BİR satır yok.

Ledger'da geçen "cursor" kelimeleri (basan komut: `grep -aiho "cursor[^\"]\{0,60\}" *.jsonl | sort | uniq -c`)
alakasız: `CursorPagination`, `cursor--50580`, benim çalıştırdığım grep
komutlarının kendi metni. Cursor yüzeyinden gelmiş olay YOK.

---

## 4. KAĞIT ÜSTÜNDE DESTEK (bu bir "bağlı" kanıtı DEĞİLDİR)

`rabadon init` hangi ajan için hangi dosyayı yazıyor — koddan:

```
grep -n "settingsPath\s*=\|hooksPath\s*=\|export function install" \
  /Users/damummyphus/damla_projects_2026/rabadon-kosu4/hooks/install.mjs
189:export function installHooks(dir, { gateCmd = GATE_BIN, ... })
190:  const settingsPath = path.join(dir, '.claude', 'settings.json');
255:export function installCursorHooks(dir, { gateCmd = GATE_BIN } = {})
256:  const hooksPath = path.join(dir, '.cursor', 'hooks.json');
289:  const settingsPath = path.join(dir, '.claude', 'settings.json');   // removeHooks
```
```
grep -n "installHooks(\|installCursorHooks(\|--global" \
  /Users/damummyphus/damla_projects_2026/rabadon-kosu4/hooks/manage.mjs
13://   - init/remove take --global to target ~/.claude/settings.json;
63:  const global = args.includes('--global');
144:  try { r = installHooks(dir); }
157:    try { cur = installCursorHooks(dir); }
```

Dialect tanıma (üç yüzey):
```
grep -n "DIALECT_" /Users/damummyphus/damla_projects_2026/rabadon-kosu4/native/hookev.h
106:  e.dialect = DIALECT_CLAUDE;    // hook_event_name ∈ {PreToolUse, PostToolUse,
                                    //   UserPromptSubmit, SessionStart, Stop, SessionEnd}
144:  e.dialect = DIALECT_CURSOR;    // hook_event_name ∈ {beforeShellExecution,
                                    //   afterShellExecution, beforeMCPExecution, ...}
212:  e.dialect = DIALECT_GENERIC;   // ham JSON'da "rabadon" anahtarı varsa
```

| yüzey | init'in yazdığı dosya | kod referansı |
|---|---|---|
| Claude Code (proje) | `<dir>/.claude/settings.json` | hooks/install.mjs:190 |
| Claude Code (global, `--global`) | `~/.claude/settings.json` | hooks/manage.mjs:13, hooks/install.mjs:289 |
| Cursor (proje) | `<dir>/.cursor/hooks.json` | hooks/install.mjs:256, hooks/manage.mjs:157 |
| "diğer her şey" | dosya yazmaz — `docs/agent-contract.md` sözleşmesi, `{"rabadon":1,...}` stdin | native/hookev.h:212, docs/agent-contract.md:14-16 |

Kodda YAZILI Cursor kısıtı (`native/gate.cpp:995`):
`"Cursor has no pre-edit hook: I see file edits AFTER they land, not before"`
— Cursor'da dosya kuralları post-hoc, sadece shell komutları pre-spend.

Windsurf / Codex / Aider / Continue için ayrı kurulum kodu YOK; hepsi
"generic contract" kovasında.

---

## 5. Bu makinede gerçekten kurulu hook var mı?

### 5a) Global — `~/.claude/settings.json` → VAR
```
grep -n "rabadon" /Users/damummyphus/.claude/settings.json
36:  "command": "/Users/damummyphus/damla_projects_2026/rabadon/native/rabadon-gate"
55:  "command": "/Users/damummyphus/damla_projects_2026/rabadon/native/rabadon-gate"
65:  "command": "/Users/damummyphus/damla_projects_2026/rabadon/native/rabadon-gate"
85:  "command": "/Users/damummyphus/damla_projects_2026/rabadon/native/rabadon-gate",
108: "command": "/Users/damummyphus/damla_projects_2026/rabadon/native/rabadon-gate",
```
Binary yaşıyor:
```
ls -la /Users/damummyphus/damla_projects_2026/rabadon/native/rabadon-gate
-rwxr-xr-x@ 1 damummyphus staff 764416 23 Ağu 04:53 .../rabadon-gate
```
**DİKKAT:** global hook `rabadon/` deposunu (23 Ağu tarihli binary) işaret
ediyor, bu depoyu (`rabadon-kosu4`) DEĞİL. Yani şu an makinede koşan gate,
kosu4 dalındaki kod değil.

### 5b) Bu repo — `rabadon-kosu4/.claude/settings.json` → YOK
```
ls -la /Users/damummyphus/damla_projects_2026/rabadon-kosu4/.claude
ls: .../rabadon-kosu4/.claude: No such file or directory
ls -la /Users/damummyphus/damla_projects_2026/rabadon-kosu4/.cursor
ls: .../rabadon-kosu4/.cursor: No such file or directory
```
kosu4 deposunda ne `.claude` ne `.cursor` var. Buradaki koşular global hook
üzerinden ledger'a düşüyor (`"pipe":"rabadon-kosu4:session"` — 241 satır,
2026-08-22..26 aralığı).

### 5c) Cursor — makinede TEK bir hooks.json var, o da başka depoda
```
find /Users/damummyphus -maxdepth 5 -path "*/.cursor/hooks.json"
/Users/damummyphus/damla_projects_2026/rabadon/.cursor/hooks.json

grep -n "rabadon" /Users/damummyphus/damla_projects_2026/rabadon/.cursor/hooks.json
6,11,16,21,26:  "command": ".../rabadon/native/rabadon-gate"

ls -la /Users/damummyphus/damla_projects_2026/rabadon/.cursor/hooks.json
-rw-r--r--@ 1 damummyphus staff 714 16 Ağu 14:00 ...
```
Dosya 16 Ağu'dan beri duruyor; ledger'a o dosyadan ÇIKMIŞ tek bir satır yok
(bkz. §3 call-id analizi). Yani config yazılmış ama Cursor hiç koşmamış.

---

## 6. KARAR TABLOSU

| ajan yüzeyi | kurulum kodu | bu makinede config | LEDGER KANITI (INJECT/SIGNAL/COUNTER) |
|---|---|---|---|
| **Claude Code** | VAR (.claude/settings.json) | VAR (`~/.claude/settings.json`, 5 hook) | **VAR** — 6 INJECT + 1 INJECT_HELD + 2224 SIGNAL + 368 COUNTER, 2026-08-22 → 2026-08-26, `~/.rabadon/spool/2026-08-2{2,3,4,5,6}.jsonl` |
| **Cursor** | VAR (.cursor/hooks.json) | VAR ama başka depoda (`rabadon/.cursor/hooks.json`, 16 Ağu) | **YOK** — 0 satır. Cursor `generation_id` formatında tek call id yok |
| **generic / agent-contract** | VAR (dosya yazmaz, stdin sözleşmesi) | YOK | **YOK** — 0 satır |
| Windsurf / Codex / Aider / Continue | YOK (ayrı kod yok) | YOK | **YOK** |

---

## ÖLÇÜLEMEDİ

- **ÖLÇÜLEMEDİ: Cursor'un gerçekten çalışıp çalışmadığı.** Cursor uygulaması
  bu makinede kurulu mu, `~/.cursor` ayarları ne durumda — bakmadım, görev
  kapsamı ledger + init koduydu. Ledger'da izi olmaması "Cursor bozuk"
  demek değil, "Cursor bu makinede rabadon ile hiç koşmamış" demek.
- **ÖLÇÜLEMEDİ: 2026-07-27 öncesi.** `~/.rabadon/spool/` en eski dosya
  2026-07-27. Daha eski ledger silinmiş ya da hiç olmamış — ayırt edemedim.
- **ÖLÇÜLEMEDİ: 2026-08-06, 08-07 günleri.** O günlerin dosyası yok; hiç
  koşulmadı mı yoksa silindi mi bilinmiyor.
- **ÖLÇÜLEMEDİ: zincir bütünlüğü.** `rabadon audit` koşmadım; satırların
  `prev` hash zinciri doğrulanmadı. Sayımlar ham grep sayımıdır.

## SORULMADI AMA ÖNEMLİ

1. **SIGNAL/INJECT/COUNTER özelliği 2026-08-22'de doğdu.** 2026-07-27 →
   2026-08-21 arası 26 günün TAMAMINDA bu olayların sayısı sıfır. Yani
   "rabadon ajana bağlı" iddiasının ledger ömrü 5 gündür (08-22 → 08-26),
   26 günlük geçmiş sadece STEP_START/STEP_OK gözlemidir.
2. **INJECT sayısı 6.** 154 bin STEP_START'a karşı 6 enjeksiyon. SIGNAL 2224
   ama bunların sadece 7'si enjeksiyona dönüşmüş. SIGNAL→INJECT dönüşüm
   oranı ~%0.3.
3. **En çok kanıt üreten proje rabadon'un kendisi değil, `stitchu`**
   (32946 satır, 08-22..26). `rabadon-kosu4` sadece 241 satır. Yani ürün
   dışarıda bir projede test edilmiş, kendi üstünde değil.
4. **Ledger git'e girmiyor.** Repo içindeki hiçbir .jsonl'de INJECT/SIGNAL/
   COUNTER yok; tüm kanıt `~/.rabadon/spool/` altında yerel. `reports/R7/`
   altındaki iki dosyanın adı zaten `_INVALID_` ile işaretli.
5. **Global hook eski koda bağlı.** `~/.claude/settings.json` `rabadon/`
   deposunun 23 Ağu tarihli binary'sini çağırıyor. kosu4'te yapılan hiçbir
   gate değişikliği şu anda canlı değil.
6. **`DENY`/`BLOCK` diye bir olay tipi yok.** Kart bunları sordu; ledger'da
   karşılıkları `STOP` (1745) ve `WOULD_BLOCK` (1607). `WRONG_REFUSAL` de
   var: 6 adet (yanlış ret sayacı, sıfır değil).
7. **`grep -c` bu ledger'da yalan söylüyor.** UTF-8 dışı bayt yüzünden 7
   günlük dosyada sayım sessizce boş dönüyor. `grep -a` şart. Bu, bu
   dosyaları okuyan her rapor için bir tuzak.
8. **3 adet `.unchained.jsonl` var** (08-01: 32, 08-17: 40, 08-21: 78 satır)
   — kilit alınamadığında zincir dışına düşen satırlar. Toplam 150 satır
   zincirin dışında.
9. **Makinede 90+ boş `.rabadon` dizini var** — çoğu Downloads ve arşiv
   altında, hiçbirinde spool yok. `rabadon init` izleri.
