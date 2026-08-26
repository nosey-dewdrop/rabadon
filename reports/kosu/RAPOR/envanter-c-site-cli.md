# ENVANTER C+D — site/index.html ne satiyor + CLI yuzeyi

Olcum tarihi: 2026-08-26. Dal: kosu4. Kok: `/Users/damummyphus/damla_projects_2026/rabadon-kosu4`.
Hicbir dosya degistirilmedi; sadece `grep`, `diff`, `sed`, `python3` (salt okuma) ve `--help` kosuldu.

---

## (c) site/index.html hangi urunu satiyor

### c1. `<title>` ve `<h1>` — VERBATIM

KOMUT:
```
grep -n -o '<title>[^<]*</title>' site/index.html
grep -n -A5 '<h1' site/index.html
```

CIKTI (birebir):

- satir 6: `<title>rabadon, guardrails and a verifiable record for coding agents</title>`
- satir 53: `<h1>run your coding agent without watching it.</h1>`

### c2. Ilk ekranda duran cumle (hero alt cumlesi) — VERBATIM

KOMUT: `sed -n '55,66p' site/index.html` (ayni grep -A5 ciktisindan)

satir 56-57, lede:

> It refuses the destructive command before the process starts, writes a receipt you can verify
> afterwards, and when a check goes red it repairs the code without being able to buy its own green.

satir 61-64, hero sag kolon (ilk ekranda, h1'in yaninda):

> On this machine it has refused 508 commands outright, recorded a further
> 446 verdicts in watch mode where nothing was blocked, and found 31 real
> defects in express, commander.js, lodash, ajv, click, jinja, markupsafe and pyyaml.

### c3. Kurulum satiri — VERBATIM

KOMUT: `grep -n -iE 'npm i|npm install|git clone|make |curl |cargo |brew ' site/index.html`

TEK sonuc, satir 80:

```
git clone https://github.com/nosey-dewdrop/rabadon && cd rabadon && make
```

(HTML'de `&amp;&amp;` olarak kacisli.) **`npm i -g rabadon` sayfada YOK.**
KANIT: `grep -c 'npm i' site/index.html` -> 0 (yukaridaki grep tek satir dondurdu).

Kurulum satirinin ustundeki cerceve cumlesi (satir 79, VERBATIM):

> Five commands. It starts in watch mode and stays there until you say otherwise, because a tool that blocks your work on the first day is a tool you delete on the second.

Kurulum satirinin altindaki cerceve cumlesi (satir 89, VERBATIM):

> A dependency-free C++ core. Nothing is uploaded, nothing calls home, and the ledger is a file on your own disk.

### c4. Sayfada duran TUM komut/verb isimleri

KOMUT A (ham `rabadon <kelime>` taramasi):
```
grep -o -E 'rabadon [a-z][a-z-]+' site/index.html | sort | uniq -c | sort -rn
```
CIKTI:
```
   2 rabadon usage
   1 rabadon watch
   1 rabadon sits
   1 rabadon repair
   1 rabadon proposes
   1 rabadon on
   1 rabadon is
   1 rabadon audit
```
(`sits`, `proposes`, `is` = duz ingilizce fiil, komut degil.)

KOMUT B (CLI verb listesiyle kesisim):
```
for v in $(grep -oE '^  [A-Za-z|_*-]+\)' native/rabadon-cli.sh | tr -d ' )' | tr '|' '\n' | grep -vE '^-|^\*$' | sort -u); do rc=$(grep -oE "rabadon $v\b" site/index.html | wc -l | tr -d ' '); [ "$rc" -gt 0 ] && echo "rabadon $v -> $rc"; done
```
CIKTI:
```
rabadon audit -> 1
rabadon on -> 1
rabadon repair -> 1
rabadon usage -> 2
rabadon watch -> 1
```

KOMUT C (terminal blogundaki kod span'leri):
```
grep -n -o -E '<span class="c">[^<]*</span>' site/index.html
```
CIKTI:
- satir 80: `git clone https://github.com/nosey-dewdrop/rabadon && cd rabadon && make`
- satir 135: `./native/precision_test.sh`
- satir 202: `rabadon usage --days 30`

**SAYFADAKI KOMUT ADLARI (5 adet), satir 82-86 VERBATIM:**

| komut | sayfadaki aciklama |
|---|---|
| `rabadon watch` | record what it would have refused, block nothing |
| `rabadon on` | arm the gate. off, and the binary stops acting |
| `rabadon usage` | what was refused, what passed, what the session cost |
| `rabadon repair --cmd "npm test"` | catch a red check, hold a fix only if the proof survives |
| `rabadon audit` | verify the ledger chain back to the first line written |

Sayfada ayrica gecen ama komut listesinde OLMAYAN kabuk satirlari: `./native/precision_test.sh`,
`./native/harness_lock_test.sh`, `./native/heldout_test.sh` (kanit tablolarinin icinde).
KOMUT: `grep -o -E '\./native/[a-z_]+\.sh' site/index.html | sort -u`

**DIKKAT: sayfadaki 5 komut ile `rabadon --help` ekranindaki 5 komut AYNI DEGIL.**
sayfa: watch, on, usage, repair, audit
help : init, on|off, usage, repair, doctor
Ortak olan sadece 3: `on`, `usage`, `repair`. Sayfa `init` ve `doctor`'u hic anmiyor
(`grep -c 'rabadon init' site/index.html` -> 0, `grep -c 'rabadon doctor' site/index.html` -> 0).

### c5. Sayfada duran TUM sayilar, gectikleri cumleyle

KOMUT:
```
python3 -c "
import re,html
s=open('site/index.html').read()
s=re.sub(r'(?is)<(script|style|svg)\b.*?</\1>',' ',s)
s=re.sub(r'(?s)<!--.*?-->',' ',s); s=re.sub(r'(?s)<[^>]+>',' ',s)
s=html.unescape(s); s=re.sub(r'\s+',' ',s)
for x in re.split(r'(?<=[.!?]) ',s):
    if re.search(r'\d',x): print(x.strip())
"
```

CIKTI (24 cumle, sirasiyla):

1. **508 / 446 / 31** — "On this machine it has refused 508 commands outright, recorded a further 446 verdicts in watch mode where nothing was blocked, and found 31 real defects in express, commander.js, lodash, ajv, click, jinja, markupsafe and pyyaml."
2. **508** — "508 commands refused outright in enforce mode, so they never ran."
3. **446 / 26 / 100.0% / 34 / 100.0%** — "a further 446 verdicts were recorded in watch mode across 26 repositories, where nothing was blocked | 100.0% precision over the 34 cases lifted out of real sessions, recall 100.0%."
4. **26.3% / 93.8% / 0** — "On this machine's whole ledger the same binary reads 26.3%, and 93.8% once its own test labs are taken out | 0 fake repairs accepted, on every run there is a record of."
5. **32 / 262.4us / Five** — "32 named ways past the gate are still open, and it stays in watch mode until they are not | 262.4µs to judge one command, so the gate is not what you switch off to go faster | run it Five commands."
6. **34 / eleven / eleven** — "34 cases lifted out of real sessions, eleven of them genuinely destructive, and the gate refuses all eleven and nothing else."
7. **23** — "The other 23 are the harder half."
8. **31 / 8 / 545** — "31 defects across 8 open-source projects, mined out of 545 commits of their own history."
9. **proje tablosu** — express 4 defect / 46 satir / 6.5; commander.js 4 / 31 / 6.5; lodash 4 / 218 / 10.5; ajv 3 / 110 / 5.0; click 4 / 48 / 6.5; jinja 4 / 35 / 8.0; markupsafe 4 / 30 / 4.5; pyyaml 4 / 27 / 1.0; **total 31 / 545 / 6.0**; "28 changed behaviour, 3 deletions only"; "The smallest defect is one source line, the largest 33."
10. **31 / uc kez** — "All 31 are deterministic: the red run was repeated three times and the same tests fell every time."
11. **commit a3714473** — "A live run against expressjs/express at commit a3714473, with the arbiter being that project's own mocha suite."
12. **2 / 0 / 91 / 1,260 / 1 / 2 / 3 / 31 / 31 of 31 / 6 lines / 1 test** — "repairs held 2 on a foreign repository, live tree edits 0 ... test files locked 91 sha256 of the pristine copy, suite 1,260 tests ... cases 31 mined out of eight projects' own history, deterministic 31 of 31, median source 6 lines, median falling 1 test."
13. **precision_test tablosu / 34** — "rule must block must not block: baseline-force-push 1 0; baseline-rm-rf-outside 1 2; no-force-push-main 3 10; no-hard-reset-main 1 1; no-rm-rf-outside 1 0; no-rm-rf-outside-project 1 9; no-wrangler-deploy 3 1. Canaries intact after judging 34 commands."
14. **(1/1) / exit 1** — "fix-add failed, repairing (1/1) FAIL testsuite ... loop exit code 1 fail-closed"
15. **eight / exit 2 / exit 0 / six / three-three** — "show the eight ways of buying a green ... The same six cases against the previous binary come back three pass and three fail, and all three failures are the product printing VERIFIED over a fix that repaired nothing."
16. **25 July** — "The ledger had been recording since 25 July and nothing had ever surfaced it..."
17. **443 / 418 / 5 days** — "443 commands it would have refused during real work, 418 of them in this engineer's own repositories rather than in a fixture, recorded across 5 days."
18. **13 / 14 / 15** — "13 laws it wrote for itself after an incident and that are in a guard file right now, of 14 distinct laws it recorded writing across 15 incidents."
19. **19 / 508 / 6** — "19 pushes it refused on a red tree, each held until the project's own suite went green | 508 commands it refused outright once it was armed, so they never ran | 6 of those, reported wrong by the operator..."
20. **115 / 81 / 44** — "Most of it was three laws: 115 a force push aimed at a shared branch; 81 a recursive delete whose target resolved outside the project tree; 44 semantic-commit-required."
21. **461 / 66,749 / 2 / 443 / 0 / 508 / 120-second** — `$ rabadon usage --days 30` tablosu: "461 destructive actions refused before they happened; 66,749 actions handed to the gate to be judged; 2 repairs held after the proof survived the judge; 443 refusals recorded in watch mode, where nothing is blocked; 0 fake repairs accepted... it is lower than the 508 in the headline because the two apply different rehearsal filters: the binary also excludes events inside a 120-second window around a drill marker..."
22. **23 days / one machine / one engineer** — "everything it has been run through so far: 23 days, one machine, one engineer."
23. **123,911 / 66,749 / 246 / 31 / 545 / 8 / 31,316 / 12** — "123,911 lines written to the hash-chained ledger, every one carrying the sha256 of the line before it | 66,749 actions handed to the gate to be judged, across 246 repositories | 31 real defects mined out of 545 commits in 8 open-source projects | 31,316 tests in the 12 suites it was run against."
24. **520** — "520 commits in this repository."

**Sayfanin kendi itiraf ettigi celiski (satir 202, cap):** headline 508 diyor, binarinin kendi
sayimi 461. Sayfa bunu "Reconciling them onto one definition is open work." diye yaziyor.
Ayni sekilde hero 446 watch-verdict diyor, `usage` tablosu 443 diyor.

### c6. Kokteki /index.html vs site/index.html

KOMUT:
```
diff index.html site/index.html > /dev/null && echo IDENTICAL || echo DIFFERENT
diff index.html site/index.html | wc -l
wc -c index.html site/index.html
```
CIKTI:
```
DIFFERENT
528        (diff cikti satiri)
17696 index.html
26778 site/index.html
```

**TAMAMEN FARKLI IKI SAYFA, FARKLI URUN ANLATIYORLAR.**

KOMUT: `grep -n -o '<title>[^<]*</title>' index.html; grep -n -A6 '<h1' index.html`

kok `/index.html`:
- `<title>rabadon · the runtime that repairs your pipeline (in development)</title>`
- `<h1>it knows what is going wrong through your code, so you can touch the grass!</h1>`
- lead: "rabadon runs your pipeline and checks itself while it runs. a step breaks silently, it catches it before it spreads, and repairs it. no babysitting."
- lead 2: "i started building it to solve my own problem, after shipping 20+ projects where the plumbing broke quietly. **it is not a finished product yet.** the core runs; the rest is being built in the open."
- CTA: "follow on github" / "how it works" — **kurulum satiri YOK.**
  KOMUT: `grep -n -iE 'npm i|npm install|git clone|make$|curl ' index.html` -> **0 sonuc.**

**HANGISI YAYINLANIYOR — KANIT:**

KOMUT: `grep -n -iE 'canonical|og:url' index.html site/index.html`
```
index.html:9       <link rel="canonical" href="https://nosey-dewdrop.github.io/rabadon/">
index.html:16      <meta property="og:url" content="https://nosey-dewdrop.github.io/rabadon/">
site/index.html:9  <link rel="canonical" href="https://rabadon.noseydewdrop.com/">
site/index.html:13 <meta property="og:url" content="https://rabadon.noseydewdrop.com/">
```

KOMUT: `find . -name CNAME -not -path './node_modules/*'` -> **0 sonuc. GitHub Pages CNAME YOK.**

KOMUT: `grep -rn -iE 'pages|deploy|vercel|site/|index.html' .github/workflows/*.yml`
-> tek sonuc: `ci.yml:95: # No compiler and no build: it reads python3 and site/.`
**Hicbir workflow deploy yapmiyor. GitHub Pages workflow'u YOK.**

KOMUT: `grep -n 'vercel\|DOMAIN' scripts/publish-field.sh`
```
69:  DOMAIN="${RABADON_PUBLISH_DOMAIN:-rabadon.noseydewdrop.com}"
93:  ARTIFACTS="site/index.html site/field.html site/catches.html site/benchmarks.html \
339: ( cd "$REPO/site" && vercel deploy --prod --yes ) > "$TMP/dep.out"
351: vercel alias set "$DEPLOY_URL" "$DOMAIN"
```
KOMUT: `cat site/vercel.json` -> `{"cleanUrls": true, "trailingSlash": false}`

**SONUC (kanitli): yayinlanan `site/index.html`.** `scripts/publish-field.sh`
`site/` dizinini `vercel deploy --prod` ile yukleyip `rabadon.noseydewdrop.com`
alias'ini o deployment'a cekiyor. Kokteki `index.html` kendini
`nosey-dewdrop.github.io/rabadon/` icin canonical ilan ediyor ama o adresi yayina
alan hicbir CNAME/workflow yok — **kokteki sayfa OLU bir artifact.**

Git gecmisi de bunu dogruluyor:
KOMUT: `git log --oneline -3 -- index.html` -> en son `a528c21 the landing page declared a canonical url for a repo that does not exist`
KOMUT: `git log --oneline -3 -- site/index.html` -> `6776ccf the field numbers, regenerated from the ledger at 443 recorded and 508 refused` (aktif, surekli guncel)

NOT: `site/index.html` elle yazilmiyor — `site/index.tmpl.html` (13KB sablon) + `site/build.py`
(114KB) uretiyor. KOMUT: `ls -la site/ | grep -E 'tmpl|build.py'`

### c7. Anahtar kelime sayimlari

KOMUT:
```
for w in guardrail watch audit receipt record "compound error" injection; do printf "%-16s %s\n" "$w" "$(grep -o -i "$w" site/index.html | wc -l | tr -d ' ')"; done
```

| kelime | site/index.html | kok index.html |
|---|---|---|
| guardrail | **7** | 0 |
| watch | **11** | 1 |
| audit | **1** | 0 |
| receipt | **1** | 0 |
| record | **18** | 7 |
| compound error | **0** | 0 |
| injection | **0** | 0 |

(kok index.html icin ayni dongu `index.html` uzerinde kosuldu.)

Onemli: **"compound error" ve "injection" iki sayfada da SIFIR.** CLAUDE.md'nin
"iki dusman"indan biri (compound error) satis sayfasinda hic gecmiyor.
"receipt" ve "audit" birer kez geciyor — ikisi de hero lede'de/komut listesinde,
baslik seviyesinde degil.

---

## (d) CLI yuzeyi — kac verb, adlari ne

### d1. Kaynak koddan verb tablosu

Gercek dispatcher: `/Users/damummyphus/damla_projects_2026/rabadon-kosu4/native/rabadon-cli.sh` (295 satir).
`bin/rabadon.mjs` ondan sonra gelen JS yardimcisi; `index.mjs` kutuphane API'si (CLI degil).

KOMUT:
```
grep -oE '^  [A-Za-z|_*-]+\)' native/rabadon-cli.sh | tr -d ' )' | tr '|' '\n' | grep -vE '^-|^\*$' | sort -u
```

CIKTI (44 isim + `*` fallback):
```
audit budget claims cost dev do doctor drift drill exec export fleet gated
guard help init lens lint loop net off on pack remove repair replay report
run sandbox serve spin stats status statusline toggle trace truth ui
uninstall usage verify version watch wrong
```

satir numarali dokum: `grep -nE '^  [A-Za-z|_*-]+\)' native/rabadon-cli.sh`
```
 87  toggle)
 96  version|--version|-V)   #unlisted
103  help|--help|-h)         #unlisted
138  dev)
203  on|off|status)
204  statusline)             #unlisted
210  lens|cost)
211  stats|usage)
212  report)
213  trace)
214  audit)
215  claims)
216  wrong)
217  repair)
218  exec)
219  sandbox)
220  run)
221  replay)
222  lint)
223  export)
229  budget)
230  do)
231  drift)
235  loop)
236  net)
237  truth)
238  verify)
239  serve)
244  gated)
245  init|remove|uninstall|doctor)
247  drill)
276  ui|watch)
277  guard|fleet|spin|pack)  #unlisted: no help/README/docs entry
```

`bin/rabadon.mjs` icindeki JS-tarafi verbler (15 adet):
KOMUT: `grep -oE "cmd === '[a-z]+'" bin/rabadon.mjs | grep -oE "'[a-z]+'" | sort -u`
```
'do' 'doctor' 'exec' 'fleet' 'guard' 'init' 'off' 'on' 'pack' 'spin'
'stats' 'statusline' 'ui' 'usage' 'watch'
```

Derlenmis native ikili sayisi: **19**
KOMUT: `ls native/rabadon-* | grep -v '\.sh$' | wc -l` -> `19`
(audit budget claims do drift export gate gated lens net pipeline repair run
sandbox serve stats trace truth verify)

### d2. `--help` KOSULDU (OLCULDU, tahmin degil)

KOMUT: `bash native/rabadon-cli.sh --help` -> **EXIT=0**, cikti VERBATIM:

```
rabadon — a deterministic gate for coding agents. It refuses a bad action
before it happens, records what it refused, and can prove a repair.

usage: rabadon <command> [args]
       rabadon                     show whether supervision is on, change nothing

  init [dir]          write the hooks into a project and author its guard.json
  on | off            turn enforcement on or off for this project
  usage [--days N]    what was refused, in which project, by which rule
  repair              attempt a bounded, re-checked fix for a failing check
  doctor              check the install: binaries, hooks, sandbox backend

  version             the version of the installed native core, and where it is
  dev <command>       everything else, still here and still supported

examples
  rabadon init                    set up the project you are standing in
  rabadon usage --days 7          what it caught this week
  rabadon dev drill               see the refusal an agent would get

Five commands is the whole product. The rest did not go anywhere — they are
under `rabadon dev`, which lists them. Nothing was removed, and putting one
back on this screen is one line.

docs: https://github.com/nosey-dewdrop/rabadon
```

Ana ekranda **5 verb** (+ version + dev).

KOMUT: `bash native/rabadon-cli.sh dev --help | grep -cE '^  [a-z]'` -> **30**

`rabadon dev` ekranindaki 30 satir, sayfadaki gruplarla:
- supervision: toggle, status, budget, drill
- setting up: lint, truth, remove, uninstall
- seeing what happened: lens, cost, stats, report, trace, drift, audit, claims, wrong, replay, export
- acting: run, exec, sandbox, do, loop, verify, net, watch, ui, serve, gated

KOMUT: `bash native/rabadon-cli.sh doctor` -> EXIT=0
```
  ok   native core built (19/19 binaries)
  ok   version 0.2.3 (binary matches package.json)
  ok   kernel sandbox: available — macOS Seatbelt (sandbox-exec)
```
Yani ikili derli, `--help` gercekten kosuldu. **ÖLÇÜLEMEDİ yok bu bolumde.**

Alt-ikili ornegi, KOMUT: `native/rabadon-gate --help` -> EXIT 0, kendi bayrak
ekranini basiyor (`--status --on --off --toggle --silent --lint --statusline --version`).

### d3. Toplam verb sayisini basan TEK komut

KOMUT:
```
grep -oE '^  [A-Za-z|_*-]+\)' /Users/damummyphus/damla_projects_2026/rabadon-kosu4/native/rabadon-cli.sh \
  | tr -d ' )' | tr '|' '\n' | grep -vE '^-|^\*$' | sort -u | wc -l
```
CIKTI: **44**

Bayrak-takma-adlari (`--help`, `-h`, `--version`, `-V`) zaten elendi. `help` ve
`version`'i da "gercek is yapan verb degil" sayarsan **42**:
```
... | grep -vE '^(help|version)$' | wc -l    ->  42
```

**UC FARKLI SAYI, hepsi dogru, tanima gore:**
| tanim | sayi | komut |
|---|---|---|
| `rabadon --help` ana ekraninda gorunen | **5** | `bash native/rabadon-cli.sh --help \| grep -cE '^  (init\|on\|usage\|repair\|doctor)'` |
| `rabadon dev --help` ekraninda listelenen | **30** | `bash native/rabadon-cli.sh dev --help \| grep -cE '^  [a-z]'` |
| dispatcher'da gercekten yazilabilen (unlisted dahil) | **44** | yukaridaki tek komut |

Fark: 5 + 30 = 35. Kalan 9: `version`, `help`, `dev`, `statusline`, `guard`,
`fleet`, `spin`, `pack` (bunlar kaynakta `#unlisted` diye isaretli) + `init/on/off/
usage/repair/doctor`in ana ekranla ortusen kismindan gelen sayim farki.
`guard fleet spin pack` icin kaynaktaki yorum aynen: `#unlisted: no help/README/docs entry`
— yani **4 verb hicbir yerde belgeli degil ama calisiyor.**

---

## SORULMAYAN AMA ONEMLI BULGULAR

1. **Site 5 komut satiyor, help 5 komut listeliyor, ama AYNI 5 DEGIL.** Site:
   watch/on/usage/repair/audit. Help: init/on/off/usage/repair/doctor. Sayfayi
   okuyup gelen kullanici `rabadon watch` yaziyor — o `dev` grubunda
   (`native/rabadon-cli.sh:276`), ana ekranda yok. `rabadon audit` de `dev`de
   (satir 214/171). Yani **sayfadaki 5 komuttan 2'si urunun kendi help ekraninda
   gorunmuyor**, ve sayfa `init`'i hic anmiyor — kurulumdan sonra ilk yapilmasi
   gereken komut sayfada yok.

2. **Kurulum `git clone && make`. `npm i -g rabadon` hicbir sayfada yok** ama
   `package.json` var ve CLAUDE.md T8'de npm'i "documented install" yapacagini
   soyluyor. `npm/` dizini repoda mevcut. DOGRULANMADI: npm'de yayinlanmis mi.

3. **Kokteki `/index.html` bambaska bir urun anlatiyor** ("the runtime that
   repairs your pipeline", "touch the grass!", "it is not a finished product
   yet") ve `nosey-dewdrop.github.io/rabadon/` icin canonical ilan ediyor — o
   adresi yayina alan CNAME/workflow YOK. Repoyu GitHub'da acan biri README'nin
   yaninda bu olu sayfayi goruyor. Kendi commit mesaji zaten kabul ediyor:
   "the landing page declared a canonical url for a repo that does not exist".

4. **Sayfa kendi sayilariyla celisiyor ve bunu yaziyor:** headline 508 vs
   `usage` tablosu 461; hero 446 watch-verdict vs tablo 443. Sayfa: "Reconciling
   them onto one definition is open work." Disariya "508" demeden once bu
   secilmeli — yoksa biri `rabadon usage` kosup 461 gorur.

5. **"32 named ways past the gate are still open"** — sayfanin kendi hero'sunda,
   0 fake-repair rakaminin yaninda duruyor. Bu satis sayfasinda duran bir
   guvenlik acigi itirafi.

6. **`site/.vercelignore` bir sizinti kazasini belgeliyor:**
   "https://rabadon.noseydewdrop.com/build.py answers 200 today, which is how
   this was found." Yani `site/build.py` (114KB kaynak) canli olarak servis
   edilmis. `.vercelignore` sadece `.rabadon/`, `__pycache__/`, `*.pyc`, `.env*`,
   `.vercel`'i disliyor — **`build.py`, `rule_census.py`, `redact.py`,
   `field.jsonl`, `measured.json`, `findings.jsonl` hala yayinlaniyor.**
   DOGRULANMADI: bugun hala 200 donuyor mu (ag erisimi kullanmadim).

7. **`scripts/publish-field.PAUSED` diye bir dosya var** — yayin akisi duraklatilmis
   olabilir. Iceriğini okumadim. ÖLÇÜLEMEDİ: neden duraklatildigi.

8. **`guard`, `fleet`, `spin`, `pack` verbleri hicbir help/README/docs kaydi
   olmadan calisiyor** (kaynakta `#unlisted: no help/README/docs entry`).
   "Zero-config, five commands" iddiasiyla ceilisen 4 gizli yuzey.

9. `site/index.html` uretilmis dosya (`index.tmpl.html` + `build.py`). Sayfadaki
   sayilari elle degistirmek anlamsiz — kaynak `measured.json` / `field.jsonl`.

## ÖLÇÜLEMEDİ

- `https://rabadon.noseydewdrop.com/` canli olarak ne donuyor (ag cagrisi yapmadim).
- `https://rabadon.noseydewdrop.com/build.py` hala 200 mu (ayni sebep).
- npm registry'de `rabadon` paketi yayinda mi (ag cagrisi yapmadim).
- `scripts/publish-field.PAUSED` neden var (dosyayi acmadim, gorev disi).
- `site/index.html`'deki sayilarin `measured.json`/`field.jsonl` ile tutarliligi
  (kanit dosyalarini karsilastirmadim — bu ayri bir envanter isi).
