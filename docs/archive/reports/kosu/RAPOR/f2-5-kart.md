# f2-5-refenv — two new axes measured: linux/amd64, and non-root

Measuring card. Nothing under `native/` was touched except `native/refenv/run.sh`.
`native/sandbox_test.sh` was not edited; its CHALLENGE is still open and still red.

## The label law

Nothing here is "green in a container". Every count below carries
**image · platform · user · network**, and a count on one label is not a claim
about another. Restating the inherited F1e number under its correct label:

> **102/105 green** is true of `node:22-bookworm · linux/arm64 · root · --network none`
> and of nothing else. It is not "green on linux" and not "green on a clean machine".

## The two runs, with the exact commands

Both at HEAD **`c8a2ad61fd71ab1250fa724d563fef054fca7fea`**, both `--network none`,
both `--suite-timeout 1200`, both ran to completion (no ceiling hit, nothing cut short).
Cost: zero — local docker, no model call.

    # RUN 1 — amd64 (network used ONCE, for the pull only; the measurement is offline)
    docker pull --platform linux/amd64 node:22-bookworm
    bash native/refenv/run.sh --out reports/refenv --prefix f2-5-amd64-root- \
         --platform linux/amd64 --suite-timeout 1200

    # RUN 2 — non-root
    bash native/refenv/run.sh --out reports/refenv --prefix f2-5-arm64-nonroot- \
         --user 1000:1000 --suite-timeout 1200

| | RUN 1 | RUN 2 | F1e baseline |
|---|---|---|---|
| **LABEL** | `node:22-bookworm · linux/amd64 · root · --network none` | `node:22-bookworm · linux/arm64 · 1000:1000(node) · --network none` | `node:22-bookworm · linux/arm64 · root · --network none` |
| in-container `uname -m` | **x86_64** | aarch64 | aarch64 |
| in-container `id` | uid=0(root) | **uid=1000(node) gid=1000(node)** | uid=0(root) |
| `HOME` | /root | **/home/node** | /root |
| `make all` | **exit 0** | **exit 0** | exit 0 |
| suites run | **105** | **105** | 105 |
| GREEN | **102** | **102** | 102 |
| RED | 3 | 3 | 3 |
| TIMEOUT / NEVER RAN | **0 / 0** | **0 / 0** | 0 / 0 |
| suite wall time, summed | **1411 s** | 787 s | not recorded |

Raw evidence, committed: `reports/refenv/f2-5-amd64-root-{env,build,suites}.out`,
`f2-5-amd64-root-suites.tsv`, and the same four for `f2-5-arm64-nonroot-`.
`.gitignore` did not block them (`git check-ignore` → rc 1); no `-f` was needed.
Driver stdout: `reports/kosu/RAPOR/f2-5-amd64.out`, `f2-5-nonroot.out`.

## RUN 1 — what x86_64 says

**x86_64 builds and runs, and it found no architecture-specific defect.** `make all`
exit 0 under emulation, and the red set is *byte-identical in membership* to arm64:
`sandbox_test.sh`, `site_claims_test.sh`, `publish_redaction_test.sh`. No suite that
is green on arm64 is red on amd64, and none of the reverse. The alignment /
endianness / warning classes that F1e listed as invisible were looked for by this run
and did not appear at this HEAD.

The image variant is genuinely a different image: id `sha256:87a4f951f28b…e251ac`,
against arm64's `sha256:8a34c4ab3ea2…24c4d`. Note that the **RepoDigest reported for
BOTH is `sha256:8a34c4ab3ea2…24c4d`** — i.e. the digest string equals the *arm64*
image id. F1e flagged this as suspicious and marked it DOĞRULANMADI; this run
strengthens the suspicion into something closer to fact: a digest that is identical
across two demonstrably different image ids is not identifying the variant. **Pin by
image id, never by the RepoDigest this store reports.**

Emulation cost: 1411 s of suite time vs 787 s native, **1.8×** — far cheaper than
feared. `npm_install_test.sh` is 571 s on amd64 vs 564 s native (it is I/O and npm
bound, not CPU bound, so emulation barely touches it); the emulation tax lands on the
CPU-heavy suites (`signals_test.sh` 55 s, `moves_test.sh` 45 s).

## RUN 2 — the root-artefact claim is FALSIFIED

F1e §3.3 said `publish_redaction_test.sh`'s red was "a root environment artefact":
`HOME=/root` makes `-root` a substring of ordinary English prose in
`site/rule_census.json` (1 hit). The obvious inference was that a non-root run turns
it green. **It does not. Measured: still RED, still exit 1, still 27 ok / 1 fail.**

What actually happens is worse, and it is the finding of this card. Under
`--user 1000:1000` the account is `node`, so the scanner now hunts for the bare word
`node` — in a repository whose site is built by a Node toolchain. The single prose hit
becomes **107 hits across 13 published files**:

    FAIL  published artifacts under /w/site carry what may not be published:
            allowlist.py: 5      benchmarks.html: 9    build.py: 10
            catches.html: 14     effects.js: 3         field.html: 1
            field.jsonl: 27      identity.py: 1        index.html: 1
            measured.json: 5     patch-notes.html: 10  rule_census.json: 3
            rule_census.py: 18

So the same suite is red on root *and* on the most common non-root uid, for two
different false-positive reasons, and **neither is a leak**. The suite already knows
this failure class exists — its own section 7 exempts `runner` with the words *"a
generic CI account name that occurs in ordinary prose. Counting it would report the
word, not a leak"* — and that exemption is a hardcoded single name. `root` and `node`
are the two most common account names a container ever runs as, and the check is
structurally unable to pass under either. **This is a defect in the check's design,
not in the environment.** Not fixed here (out of card scope, and it is an acceptance
file). Left red, reported.

`sandbox_test.sh` and `site_claims_test.sh` fail identically under both new axes,
for the causes F1e already established (stale needle vs `NO usable kernel backend`;
missing `gh` + no network). No new red was produced by this card.

## Harness changes (`native/refenv/run.sh` only)

`b93f3bf` — `--platform` and `--user`; a precondition that asks whether the image
exists **for the requested platform** (a multi-arch pull fetches the host variant
only, so the old check passed on arm64 and the run then died offline with a confusing
error) and prints `docker pull --platform …` as the one fix; the four-part LABEL
printed and written into `env.out`; `id`/`whoami`/`HOME`/writability probed in-container;
**per-suite wall time** as a new `secs` column — F1e's own §7.6 named its absence as a
defect it had introduced, and it is now closed; and artifacts harvested on SIGINT/SIGTERM
so a run cut at a time ceiling still reports the rows it counted (not exercised — both
runs finished).

## Off-card, noticed, not touched

1. **Something deleted untracked files under `reports/` mid-run.** `reports/refenv/`
   was created at 11:51 and was gone at 12:06 with both censuses in flight; recreating
   it let both runs land. `reports/kosu/RAPOR/f2-5-nonroot.out` also lost its tail
   (9 lines; the `refenv: wrote …` summary is missing) while the script exited 0.
   HEAD also moved from `49fd73d` to `c8a2ad6` during the session. A parallel worker
   doing a `git clean`-shaped sweep is the fitting explanation but I did **not** prove
   it. Anyone measuring in this repo concurrently should commit artifacts early;
   I did, after each run.
2. `docker pull --platform linux/amd64` reported `Status: Image is up to date` while
   pulling ~10 layers — the containerd store's status line is about the tag, not the
   variant. Do not read it as "nothing was fetched".
3. `make all` is exit 0 but not warning-free on amd64 either; the warning text in
   `f2-5-amd64-root-build.out` is the same set F1e triaged (`-Wmisleading-indentation`
   at `gate.cpp`, `-Wunused-function` at `drift.cpp`). Not re-triaged here.

## NOT VERIFIED

- **amd64 non-root was not measured.** The two axes were moved one at a time on
  purpose (so each result has one cause), which leaves the corner `linux/amd64 · non-root`
  a blank.
- **Still only `node:22-bookworm`.** F1e called the fat-image gap its biggest;
  it is still open. `debian:bookworm-slim` and the local `rabadon-refenv:git-and-shell`
  were not run. "102 green" says nothing about a machine with only git and a shell.
- **Single sample per axis.** A flaky suite is indistinguishable from a stable one here.
- **`--user 1000:1000` is not a hostile test.** uid 1000 exists in this image with a
  writable `/home/node`, and `/w` was writable. An unmapped uid with no `/etc/passwd`
  entry and no writable HOME — the real "surprising user" case — was not tried.
- I did not confirm the RepoDigest against Docker Hub (offline); the id-vs-digest
  claim above rests on two local image ids, which is enough to distrust the digest and
  not enough to explain it.
- `promises_test.sh`, the `disclosure:` target, `make bench` and `make precision` were
  not run on either axis.
