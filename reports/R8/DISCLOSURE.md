# DISCLOSURE — the 41 off-list names

Investigation only. Nothing outside this file was changed.
Measured 2026-08-22 against the working tree at `ca1ea4e`.

---

## 1. THE RULE

`make disclosure` runs `native/published_allowlist_test.sh`, which runs
`site/allowlist.py` against the real `site/`.

**The rule, in one sentence:** `allowlist.py` collects every value of a
`project` key, at any depth, out of three artifacts — `site/measured.json`,
`site/rule_census.json`, `site/field.jsonl` — and a name is ALLOWED only if it
appears, matched exactly, as a non-comment line in `site/published-projects.txt`;
anything else is off-list and the process exits 1.

Properties worth stating, all read from the source:

- **Exact match.** No prefixes, no globs. `ir-globe` being allowed does nothing
  for `ir-globe-showcase`.
- **Fails closed.** A missing or empty allowlist allows NOTHING (`load_allowed`
  returns an empty set on `FileNotFoundError`). Cases 4 and 5 of the shell
  suite assert exactly this.
- **Declared names only.** It reads the `project` field, not free text. Its own
  docstring states the known limit: a name embedded inside an identifier is out
  of scope, and that is how the one real 2026-08-17 leak got through.
- **Inverted default.** The private withhold list at `~/.rabadon/redact/projects.txt`
  makes the question "is this secret" and is default-ALLOW and unenforceable in
  CI. This file asks "was this allowed" instead, so CI can enforce it without
  ever learning a private name.
- **Only case 6 is red.** Cases 1–5 run against a fixture and pass. The failing
  assertion is the last one, which points the checker at the real `site/`.

Current allowlist = 12 names: `rabadon`; the three non-name markers `(withheld)`,
`(lab)`, `(no project)`; and eight third-party public repos
(`rails redis terraform airflow apache-airflow discourse goose crush llama.cpp LMCache`
— that is 10 lines, of which 8 are matched by current artifacts).

```
53 name(s) found, 12 allowed, 41 off-list
```

---

## 2. THE 41, CLASSIFIED

Counts: **(a) 2 · (b) 23 · (c) 5 · (d) 11 = 41.** None unclassifiable.

Evidence base for every row: `gh repo list nosey-dewdrop --limit 200` for
repo existence and PUBLIC/PRIVATE visibility, `curl -o /dev/null -w %{http_code}`
for live-site reachability, and `find ~/damla_projects_2026 -maxdepth 4` for
on-disk directories.

### (a) real disclosure obligation — genuinely user-visible, must be declared — 2

The repo is PRIVATE but the product is served to the public, so the name is
already visible to any stranger and withholding it in the artifacts would be
theatre. These are the only two where "allow it, with the reason" is clearly the
correct decision on the evidence.

| name | records | evidence |
|---|---|---|
| `messageinabottle` | 7 | repo PRIVATE, but `https://messageinabottle.noseydewdrop.com` → **HTTP 200** |
| `snailmail-web` | 7 | repo PRIVATE, but `https://nosey-dewdrop.github.io/snailmail-web/` → **HTTP 200** |

### (b) internal name that leaked into a public surface — 23

No public repo, no reachable public URL. Each is a private working directory
name that reached the `project` column because the gate writes
`project = basename(cwd)`. Each one is a genuine disclosure decision and the
default answer for this class is *withhold*, not *allow*.

| name | records | evidence |
|---|---|---|
| `youkiddingme` | 33 | no repo in `gh repo list`, no directory on disk today; the ledger's own step text names it: `cd ~/damla_projects_2026/youkiddingme && cat >> lulumelon/tests/...` |
| `parmakestra` | 14 | dir `_arsiv_2026-08-18/00_currently_on_working/parmakestra`, no repo |
| `inf-baseline-kernel` | 12 | dir `_arsiv_2026-08-18/00_currently_on_working/inf-baseline-kernel`, no repo; this is the INFRA tree |
| `noseydewrites` | 9 | dir `_arsiv_2026-08-18/noseydewrites`, no repo |
| `vibecodedflopware` | 9 | no repo and no directory under this spelling; the public repo is `vibecodedslopware` (**slop**, not **flop**). Whether this is a rename, a typo or a separate tree is **DOĞRULANMADI** |
| `damla_portfolio` | 8 | dir exists, no repo |
| `idea-garden` | 8 | dir exists, no repo |
| `peek-a-book` | 8 | dir exists, no repo |
| `psikoloji-kitabi` | 8 | dir exists, no repo |
| `just-ballet` | 7 | dir exists, no repo |
| `ladybug` | 7 | dir exists, no repo |
| `mumucakes` | 7 | dir exists, no repo; `mumucakes.noseydewdrop.com` → **404**, `nosey-dewdrop.github.io/mumucakes/` → **404** |
| `wildflower.dev` | 7 | repo exists and is **PRIVATE**, homepage field empty |
| `creator-books` | 6 | dir exists, no repo |
| `houndhub` | 6 | dir exists, no repo |
| `idea-parking` | 6 | repo exists and is **PRIVATE** |
| `ir-globe-showcase` | 6 | dir exists, no repo (the base `ir-globe` is public; the showcase tree is not) |
| `sahaf` | 6 | dir exists, no repo |
| `seviyorsevmiyor-showcase` | 6 | dir exists, no repo (same split as above) |
| `synthjury` | 6 | dir `_arsiv_2026-08-18/00_currently_on_working/synthjury`, no repo |
| `visionboard` | 6 | dir `_arsiv_2026-08-18/00_currently_on_working/visionboard`, no repo |
| `benimstilim` | 5 | dir exists, no repo |
| `falmarx` | 1 | repo exists and is **PRIVATE**, homepage field empty |

### (c) noise — the label is not a project name at all — 5

These are the residue `site/identity.py` says outright it cannot resolve: a
ledger record carries only `basename(cwd)`, so a directory that is not a project
root arrives looking like one. They belong in `site/non-projects.txt` with
evidence, not on the allowlist — but note that file's own rule: a line is
admissible only with checkable evidence written beside it, and "it made the
count smaller" is not evidence.

| name | records | evidence that it names no project |
|---|---|---|
| `reports` | 47 | two `reports/` directories exist on this machine (`./rabadon/reports`, `./stitchu/reports`) and the record does not say which. `site/identity.py` names this case explicitly as unresolvable |
| `icerik` | 26 | `~/damla_projects_2026/icerik` is the content folder, not a repository |
| `blog` | 6 | ambiguous exactly like `reports`: `_arsiv_2026-08-18/blog` and `_arsiv_2026-08-18/musical-improvisation-tool/blog` |
| `pattern-bridge` | 2 | it is a SUBDIRECTORY of another project: `./stitchu/engine/pattern-bridge` |
| `2026-08-01-real-defect-mine` | 1 | it is a subdirectory of THIS repo's own `reports/` — confirmed by `ls reports/` |

### (d) already fine, the allow-list is just stale — 11

Public repo under `nosey-dewdrop`, most with a live homepage. Naming these
discloses nothing their own GitHub pages do not — the identical argument the
allowlist already accepts for `rails`, `redis`, `LMCache` and the rest. Still a
decision the operator has to make, but the evidence is one `gh` call away.

| name | records | evidence |
|---|---|---|
| `seviyorsevmiyor` | 19 | PUBLIC · `https://seviyorsevmiyor.noseydewdrop.com` |
| `ir-globe` | 17 | PUBLIC · `https://nosey-dewdrop.github.io/ir-globe/` |
| `kisalafinuzunu` | 11 | PUBLIC · `https://kisalafinuzunu.noseydewdrop.com` |
| `missingsemicolon` | 10 | PUBLIC · `https://missingsemicolon.noseydewdrop.com` |
| `moonlight` | 10 | PUBLIC · no homepage set |
| `nosey-dewdrop.github.io` | 10 | PUBLIC · `https://nosey-dewdrop.github.io/` — and already printed in this repo's own `package.json` and `index.html` |
| `sunflower` | 10 | PUBLIC · no homepage set |
| `shortstorylong` | 9 | PUBLIC · `https://shortstorylong.noseydewdrop.com` |
| `sightstone` | 9 | PUBLIC · no homepage set |
| `musical-improvisation-tool` | 7 | PUBLIC · `https://musicimprov.noseydewdrop.com` |
| `lingolingo` | 6 | PUBLIC · `https://nosey-dewdrop.github.io/lingolingo/` |

---

## 3. HISTORY — was it ever green?

**No. Not for one commit. It was authored red and has never been anything else.**

`git log` touches only three commits, all on 2026-08-17:

```
4045665 2026-08-17  a project name is published by decision, not by default:
                    a public allowlist and the check that enforces it
bca018c 2026-08-17  everything under site/ is deployed, comments included:
                    describe the withheld class, never the name
f278d2d 2026-08-17  the published project field carries an identity, and two
                    withheld projects stop being published under their nicknames
```

`4045665` created all three files at once — `site/allowlist.py`,
`site/published-projects.txt` and `native/published_allowlist_test.sh`. There is
no earlier revision of any of them.

Running each historical revision's own checker against that revision's own
artifacts:

| commit | exit | names found | allowed | off-list |
|---|---|---|---|---|
| `4045665` (birth) | **1** | 72 | 12 | **60** |
| `bca018c` | **1** | 72 | 12 | **60** |
| `f278d2d` | **1** | 53 | 12 | **41** |
| `HEAD` (`ca1ea4e`) | **1** | 53 | 12 | **41** |

Three things follow.

1. **The 12 were set once, at birth, and have never moved.** No name has been
   added to the allowlist since it was created — which is what
   `Makefile` claims ("no name was added to the allowlist to shrink the number")
   and the history confirms.
2. **It did NOT go red gradually.** This is the opposite of the README
   line-count pattern. There was no green baseline that drift ate into. Commit
   one produced exit 1 with 60 off-list names, and the checker's own header says
   so in advance: *"The last case runs the checker against the REAL site/ and is
   expected to be red until the operator has triaged the list. That is the point
   of it."*
3. **The only movement was downward, and it was a correctness fix, not a
   loosening.** `f278d2d` introduced `site/identity.py`, which collapsed 72
   labels to 53 by resolving markers and non-project directories — 60 → 41
   off-list. The allowlist itself was untouched. So the number shrank by 19
   without a single disclosure decision being made.

**The R8 conflict is therefore structural, not a regression.** "Publish only from
a green main" is unsatisfiable because `ci.yml` runs `make disclosure` as a
required job on both `ubuntu-latest` and `macos-15` (`.github/workflows/ci.yml`
lines 96–106), and that job is designed never to pass until a human triages the
list. Nothing broke. The two rules were written to be incompatible and one of
them has to give.

---

## 4. DOES ANYTHING PUBLISHED TODAY CONTAIN A NAME THAT SHOULD NOT BE THERE?

**YES.** Not on the deployed domain, but on the public GitHub surface, which is
the same thing for disclosure purposes.

**The deployed domain is currently narrow.** Probed 2026-08-22:

```
200  https://noseydewdrop.com
200  https://noseydewdrop.com/index.html
404  https://noseydewdrop.com/field        (site/vercel.json sets cleanUrls: true)
404  https://noseydewdrop.com/catches
404  https://noseydewdrop.com/field.html
404  https://noseydewdrop.com/measured.json
404  https://noseydewdrop.com/build.py
```

So `allowlist.py`'s docstring warning — *"everything under site/ is uploaded by
`vercel deploy`, source included — the domain answers 200 for build.py"* — does
NOT describe the domain as it answers today. That is a good thing and it is the
only mitigating fact here.

**But `github.com/nosey-dewdrop/rabadon` is a PUBLIC repository**, and the
artifacts are on `main`. Fetched from `raw.githubusercontent.com`, unauthenticated:

```
$ curl https://raw.githubusercontent.com/nosey-dewdrop/rabadon/main/site/rule_census.json
HTTP 200, 287889 bytes
     31  icerik
     13  idea-parking          <- repo visibility: PRIVATE
     27  parmakestra
     66  seviyorsevmiyor
     22  vibecodedflopware
     17  wildflower.dev        <- repo visibility: PRIVATE
      1  youkiddingme

$ curl .../main/site/field.html
HTTP 200
      7  icerik
      1  parmakestra
     10  youkiddingme

$ curl .../main/site/catches.html
HTTP 200
      2  falmarx               <- repo visibility: PRIVATE
```

**Three names of repositories the operator has deliberately marked PRIVATE on
GitHub are readable by any stranger on the public main branch of this repo:
`idea-parking`, `wildflower.dev`, `falmarx`.** Alongside them, `youkiddingme`,
`parmakestra`, `inf-baseline-kernel` and the rest of class (b) — private working
trees with no public existence at all.

The names also reach rendered HTML, not only the JSON sources: `site/field.html`,
`site/catches.html`, `site/pull-requests.html`. And a handful reach files outside
`site/` entirely — `docs/kanit/2026-08-01-g3-first-held-repair/05-stats-after.txt`
and `10-stats-final.txt` carry `youkiddingme`, `icerik` and `damla_portfolio`,
which is a surface `allowlist.py` does not scan at all.

`README.md` is clean. `package.json` contains only `nosey-dewdrop.github.io`,
which is a public repo and correct.

**So the gate is not crying wolf.** It is red for a true reason. Whatever is done
about R8, class (b) is a real leak that exists on a public URL right now.

---

## 5. OPTIONS

Not a recommendation. Each of these touches what gets published, so the choice
belongs to the operator. Costs are stated as honestly as I can state them; where
I have not verified a cost I say so.

**Option 1 — Triage all 41 by hand. The design intent.**
The operator decides each of the 41: allowed names go into
`site/published-projects.txt` with their reason, the rest go on the private
withhold list and `redact.py` takes them out, then the artifacts are regenerated
and the gate goes green on merit.
*Cost:* 41 disclosure decisions, plus an artifact regeneration pass. Blocks
publishing until finished. This is hours of the operator's own attention and
cannot be delegated — that is the point of the file.
*Gives up:* nothing in rigor. It gives up time, now, and the numbers on the
published pages change once withheld names collapse into `(withheld)`.

**Option 2 — Land the (d) group only: 11 names with public evidence.**
Add the 11 names that already have PUBLIC repos and, mostly, live homepages,
each with its `gh`-checkable reason. 41 → 30.
*Cost:* 11 lines and 11 quick verifications. Small.
*Gives up:* nothing — but it does NOT make the gate green, so R8 stays blocked.
It is a real dent, not a fix.

**Option 3 — Fix the data defect at the source, then re-measure.**
The 5 class-(c) labels are not names. Extend `site/non-projects.txt` with
evidence lines for `reports`, `icerik`, `blog`, `pattern-bridge` and
`2026-08-01-real-defect-mine`, and fix the gate so `project` stops being
`basename(cwd)`. 41 → 36.
*Cost:* a `native/gate.cpp` change plus evidence lines, and the gate fix only
helps records written afterwards — `identity.py` says outright that history is
not recoverable, because a ledger record carries no path.
*Gives up:* nothing, but it is the option most easily abused. `non-projects.txt`
forbids adding a line to turn a check green, and two of these five (`reports`,
`blog`) are ambiguous precisely because they name real directories. It also does
not make the gate green on its own.

**Option 4 — Make the publisher refuse, instead of the checker.**
Move enforcement upstream: `build.py` / `rule_census.py` emit `(withheld)` for
any name not on the allowlist, so an undecided name can never reach an artifact.
The gate then passes by construction.
*Cost:* a change in the generators; **DOĞRULANMADI** how large — I read
`allowlist.py`, `identity.py` and `non-projects.txt` but did not audit
`build.py` or `rule_census.py` for this.
*Gives up:* a great deal, and quietly. The gate stops being able to turn red at
all, which is the failure mode the checker's own header calls out ("an allowlist
seeded with everything already published would be a check that cannot turn red").
It converts a disclosure question into a rendering default, and the published
field data loses its named records without anyone deciding that it should.

**Option 5 — Redefine "green main" so this job does not count.**
Mark the `disclosure` job non-required, or `continue-on-error`, or define R8's
"green main" as the required jobs only. The red stays visible; it stops blocking.
*Cost:* near zero, minutes.
*Gives up:* the most. The `Makefile` records that making this gate lenient or
advisory was considered on 2026-08-17 and explicitly refused as "the move this
product exists to refuse". Choosing it now reverses a decision that is written
down in three files, and does it while three PRIVATE repo names are sitting on a
public URL (section 4). It makes R8 satisfiable by making the gate mean nothing.

**Option 6 — Stop publishing the `project` column.**
Drop `project` from the three artifacts, or publish only the marker constants.
No names, no disclosure question.
*Cost:* one change in the generators, plus whatever the field/catches pages lose.
*Gives up:* the pages' ability to say which project a record came from.
`identity.py` argues against exactly this: deleting the column turns "we cannot
say" into "there was nothing". It is the bluntest instrument here and it is also
the only one that is unambiguously safe on the leak.

**A note on sequencing, offered because it is cheap and not a recommendation:**
options 2 and 3 are additive and reduce 41 to roughly 25 with evidence rather
than judgement, leaving a smaller pile of genuine decisions for option 1. They
do not conflict with any of 4, 5 or 6. But class (b) — 23 names, three of them
PRIVATE repos, live on a public URL today — is untouched by every option except
1, 4 and 6.

---

## APPENDIX — everything else this investigation turned up

Recorded because it was seen, not because it was asked for.

- **`vibecodedflopware` vs `vibecodedslopware`.** The artifacts publish
  `vibecodedflopware` 22 times in `rule_census.json` and once in `field.jsonl`.
  The public repo and the on-disk tree are both spelled `vibecodedslopware`. One
  letter apart, and I could not determine which is canonical or whether a rename
  happened. **DOĞRULANMADI.**
- **`youkiddingme` has no directory on this machine today**, yet
  `MEMORY.md` lists it as an active project with 151 commits in 30 days, and the
  ledger's step text shows it as a real working directory containing `lulumelon`
  — which is now a top-level directory. Something was renamed or moved. Not
  investigated further.
- **`docs/kanit/` is an unscanned public surface.** `allowlist.py` reads three
  files under `site/`. `docs/kanit/2026-08-01-g3-first-held-repair/05-stats-after.txt`
  and `10-stats-final.txt` also carry project names (`youkiddingme`, `icerik`,
  `damla_portfolio`) and no check looks at them. Widening `SOURCES` would raise
  the count, not lower it.
- **Names appear in source comments too.** `site/rule_census.py` contains
  `messageinabottle` and `idea-garden`; `site/identity.py` contains `just-ballet`,
  `idea-garden` and `damla_portfolio`. These are `.py` files on a public branch.
  `allowlist.py`'s own docstring warns about precisely this class ("Describe the
  class, never the name") after being caught by it once.
- **The 8 third-party repos on the allowlist are carrying their weight** — the
  file lists 10 such lines but only 8 are matched by current artifacts, which is
  why 12 allowed rather than 14. Not a problem, just an explanation of the
  arithmetic.
- **`site/vercel.json` sets `cleanUrls: true` and `trailingSlash: false`.** I
  probed both extensioned and clean paths before concluding the pages are not
  deployed. Whether they were EVER deployed — the `allowlist.py` docstring says
  the domain once answered 200 for `build.py` — is **DOĞRULANMADI**; I only
  measured today.
- **What I did not look at:** `native/gate.cpp` and `.github/` beyond reading the
  disclosure job, both off-limits for this task; `site/build.py` and
  `site/rule_census.py` internals; the private withhold list at
  `~/.rabadon/redact/projects.txt`, which I did not open.
