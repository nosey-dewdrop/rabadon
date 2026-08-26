#!/bin/sh
# rabadon reference environment runner. MEASURES ONLY — it never edits the
# source tree, never edits a test, never edits the Makefile.
#
# WHY THIS FILE EXISTS
# The quality bar in CLAUDE.md says the reference environment is a clean
# container, not the maintainer's laptop. Until this script existed that claim
# was re-typed by hand every time somebody wondered, which means it was not
# reproducible and its result was an anecdote. This is the command, committed,
# so anyone can re-run the exact measurement and get the exact artifacts.
#
# WHAT IT DOES
#   1. clones the repo's committed HEAD into a throwaway directory
#      (a clone, NOT `git worktree add`: a worktree's .git is a *file* pointing
#      at the host's gitdir, and that path does not exist inside the container,
#      so every suite that touches git would fail for a reason that is about
#      the harness rather than about rabadon)
#   2. runs `make all` in the container, capturing the full output
#   3. runs EVERY suite named by the `test:` target ONE AT A TIME, so a red
#      suite cannot hide the ones behind it. `make test` stops at the first
#      failure by design; that is correct for a gate and useless for a census.
#   4. writes a per-suite table: name, exit code, ok count, fail count
#
# NETWORK: the measurement runs with `--network none`. Nothing is downloaded,
# nothing is phoned home. If the image is not already local this script says so
# and stops rather than silently reaching for the internet — pulling the image
# is a separate, deliberate command printed in the error.
#
# USAGE
#   native/refenv/run.sh [--out DIR] [--prefix STR] [--image REF]
#                        [--suite-timeout SECS] [--platform P] [--user U]
# Defaults: --out reports/refenv --prefix "" --image node:22-bookworm
#           --suite-timeout 300 --platform (host default) --user (image default, root)
#
#   --platform  passed straight to `docker run --platform`, e.g. linux/amd64.
#               On an arm64 host that means qemu emulation: it WORKS and it is
#               SLOW (raise --suite-timeout accordingly). The image variant for
#               that platform must already be local; the measurement will not
#               pull, because it runs with --network none. The error names the
#               one command to run: `docker pull --platform <P> <IMAGE>`.
#   --user      passed straight to `docker run --user`, e.g. 1000:1000. The
#               container defaults to root, and root is not who runs this tool
#               in real life: as root every permission-denied assertion is
#               unfalsifiable, and $HOME=/root makes "-root" a substring of
#               ordinary English prose. Measuring non-root is how those two
#               classes get separated from real defects.
#
# EVERY NUMBER THIS SCRIPT PRINTS CARRIES A FOUR-PART LABEL:
#   image · platform · user · network. A count measured on one is NOT a claim
# about another. "green in a container" is not a sentence; "102/105 green on
# node:22-bookworm · linux/arm64 · root · --network none" is.
#
# ARTIFACTS written under --out (with --prefix prepended to each name):
#   env.out      the container's uname/arch/toolchain, the image digest, LABEL
#   build.out    full output of `make all`, plus its exit code on the last line
#   suites.tsv   one row per suite: name, exit, ok, fail, secs, status
#   suites.out   full stdout+stderr of every suite, with headers
#
# PARTIAL RESULTS ARE RESULTS. The container writes the table row by row into a
# directory that is copied out on EVERY exit path, including a kill: if a run is
# cut off at a time ceiling, whatever suites finished are still on disk with
# their numbers. A census stopped early reports what it counted.
#
# EXIT: 0 if the census completed (even if suites were red — a census that
# refuses to report red is not a census). Non-zero only if the measurement
# itself could not run, and then the reason is printed in full.

set -eu

OUT=reports/refenv
PREFIX=""
IMAGE=node:22-bookworm
SUITE_TIMEOUT=300
PLATFORM=""
RUNUSER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --out)           OUT=$2; shift 2 ;;
    --prefix)        PREFIX=$2; shift 2 ;;
    --image)         IMAGE=$2; shift 2 ;;
    --suite-timeout) SUITE_TIMEOUT=$2; shift 2 ;;
    --platform)      PLATFORM=$2; shift 2 ;;
    --user)          RUNUSER=$2; shift 2 ;;
    -h|--help)       sed -n '1,70p' "$0"; exit 0 ;;
    *) echo "refenv: unknown argument: $1" >&2; exit 64 ;;
  esac
done

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$REPO"

if [ ! -f Makefile ] || [ ! -d native ]; then
  echo "refenv: $REPO does not look like the rabadon repo (no Makefile/native)" >&2
  exit 66
fi

# --- preconditions, each one named ------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "refenv: COULD NOT MEASURE — docker is not on PATH." >&2
  echo "refenv: install Docker Desktop, or run this script on a Linux box with docker." >&2
  exit 69
fi
if ! docker info >/dev/null 2>&1; then
  echo "refenv: COULD NOT MEASURE — the docker daemon is not answering." >&2
  echo "refenv: start it (macOS: open -ga Docker) and re-run." >&2
  docker info >/dev/null 2>&1 || docker info 2>&1 | sed 's/^/refenv:   /' >&2 || true
  exit 69
fi
# Docker Desktop's containerd image store does not always answer `image inspect`
# for the short reference even when `docker images` lists it; the fully
# qualified docker.io/library/ name resolves. Try both before declaring absence,
# or this script reports "not present" about an image that is right there.
IMAGE_REF="$IMAGE"
if ! docker image inspect "$IMAGE_REF" >/dev/null 2>&1; then
  case "$IMAGE" in
    */*) : ;;
    *)   docker image inspect "docker.io/library/$IMAGE" >/dev/null 2>&1 \
           && IMAGE_REF="docker.io/library/$IMAGE" ;;
  esac
fi
if ! docker image inspect "$IMAGE_REF" >/dev/null 2>&1; then
  echo "refenv: COULD NOT MEASURE — image '$IMAGE' is not present locally." >&2
  echo "refenv: the measurement runs with --network none on purpose, so it will" >&2
  echo "refenv: not fetch it for you. Run this once, then re-run this script:" >&2
  echo "refenv:   docker pull ${PLATFORM:+--platform $PLATFORM }$IMAGE" >&2
  exit 69
fi

# "the image is local" is a claim about ONE platform variant. `docker pull` of a
# multi-arch tag brings down the host's variant only, so on an arm64 host the
# check above is satisfied by an arm64 image and a --platform linux/amd64 run
# would then fail inside `docker run` — with the network off, and therefore with
# a confusing error, at the end of a long setup. Ask about the variant that will
# actually be used, up front, and print the one command that fixes it.
if [ -n "$PLATFORM" ]; then
  if ! docker image inspect --platform "$PLATFORM" "$IMAGE_REF" >/dev/null 2>&1; then
    # `--platform` on `image inspect` is not in every docker; distinguish "the
    # flag is unsupported" from "the variant is absent" before accusing anyone.
    if docker image inspect --platform "$PLATFORM" "$IMAGE_REF" 2>&1 \
         | grep -qi 'unknown flag\|unknown shorthand'; then
      echo "refenv: NOTE — this docker's 'image inspect' has no --platform flag," >&2
      echo "refenv: so the $PLATFORM variant could not be checked before the run." >&2
      echo "refenv: if 'docker run' fails below, run: docker pull --platform $PLATFORM $IMAGE" >&2
    else
      echo "refenv: COULD NOT MEASURE — image '$IMAGE' is local, but NOT for platform" >&2
      echo "refenv: '$PLATFORM'. A multi-arch tag pulls the host's variant only." >&2
      echo "refenv: this is the one command that needs the network; the measurement" >&2
      echo "refenv: itself still runs --network none. Run it once, then re-run:" >&2
      echo "refenv:   docker pull --platform $PLATFORM $IMAGE" >&2
      exit 69
    fi
  fi
fi

mkdir -p "$OUT"
OUT_ABS=$(CDPATH= cd -- "$OUT" && pwd)
ENV_OUT="$OUT_ABS/${PREFIX}env.out"
BUILD_OUT="$OUT_ABS/${PREFIX}build.out"
TSV_OUT="$OUT_ABS/${PREFIX}suites.tsv"
SUITES_OUT="$OUT_ABS/${PREFIX}suites.out"

# --- the throwaway tree -----------------------------------------------------
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rabadon-refenv.XXXXXX")
TREE="$WORK/tree"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

git clone --quiet --no-hardlinks "$REPO" "$TREE"
HEAD_SHA=$(git -C "$TREE" rev-parse HEAD)
DIRTY=$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ')

# The in-container half. Written into the THROWAWAY tree, never into the repo.
cat > "$WORK/inside.sh" <<'INSIDE'
#!/bin/bash
# runs inside the container. /w is the throwaway clone.
set -u
cd /w

SUITE_TIMEOUT="${SUITE_TIMEOUT:-300}"

{
  echo "# container environment"
  echo "uname:        $(uname -a)"
  echo "arch:         $(uname -m)"
  # WHO is running matters as much as WHERE. Both of the environment-shaped reds
  # in the arm64/root census were about identity, not about rabadon.
  echo "id:           $(id 2>&1)"
  echo "whoami:       $(whoami 2>/dev/null || echo '(uid not in /etc/passwd)')"
  echo "HOME:         ${HOME:-(unset)}"
  echo "HOME-writable: $([ -w "${HOME:-/nonexistent}" ] && echo yes || echo NO)"
  echo "/w-writable:  $([ -w /w ] && echo yes || echo NO)"
  echo "os-release:   $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
  echo "c++:          $(command -v c++ || echo ABSENT)"
  echo "c++ version:  $(c++ --version 2>&1 | head -1 || true)"
  echo "git:          $(git --version 2>&1 || echo ABSENT)"
  echo "node:         $(node --version 2>&1 || echo ABSENT)"
  echo "python3:      $(python3 --version 2>&1 || echo ABSENT)"
  echo "bwrap:        $(command -v bwrap || echo ABSENT)"
  echo "unshare:      $(command -v unshare || echo ABSENT)"
  echo "network:      $(getent hosts registry.npmjs.org >/dev/null 2>&1 && echo 'RESOLVES (network is NOT off)' || echo 'no DNS (as intended with --network none)')"
} > /out/ENVFILE 2>&1

# git needs an identity for any suite that commits; the clone has none.
# Under --user this can fail (an unwritable or absent HOME); if it does, say so
# in the artifact instead of letting 40 suites fail for a reason about identity.
if ! git config --global user.email refenv@rabadon.invalid 2>>/out/ENVFILE; then
  echo "HARNESS WARNING: git config --global failed (HOME=${HOME:-unset} not writable?)." >> /out/ENVFILE
  echo "                 git-touching suites below fail for a HARNESS reason, not a product one." >> /out/ENVFILE
fi
git config --global user.name  "rabadon refenv" 2>/dev/null || true
git config --global init.defaultBranch main 2>/dev/null || true
git config --global --add safe.directory /w 2>/dev/null || true
git config --global --add safe.directory '*' 2>/dev/null || true

echo "### make all" > /out/BUILDFILE
make all >> /out/BUILDFILE 2>&1
BUILD_RC=$?
echo "### make all exit: $BUILD_RC" >> /out/BUILDFILE

# The suite list is READ from the Makefile's own test: target. It is not a
# second hand-maintained copy that can drift away from what `make test` runs.
START=$(grep -n '^test: all' Makefile | head -1 | cut -d: -f1)
END=$(awk -v s="$START" 'NR>s && /^[a-zA-Z][a-zA-Z0-9_.\/-]*:/ {print NR; exit}' Makefile)
SUITES=$(sed -n "$((START+1)),$((END-1))p" Makefile \
         | grep -oE '^[[:space:]]*\./native/[a-z0-9_]+\.(sh|py)' \
         | sed 's|.*/native/||')

printf 'suite\texit\tok\tfail\tsecs\tstatus\n' > /out/TSVFILE
: > /out/SUITESFILE

for s in $SUITES; do
  if [ ! -x "native/$s" ] && [ ! -f "native/$s" ]; then
    printf '%s\t-\t-\t-\t-\tMISSING\n' "$s" >> /out/TSVFILE
    continue
  fi
  echo "===== $s =====" >> /out/SUITESFILE
  # Wall time per suite. The previous census had no timing, so when one suite
  # hit the ceiling there was no way to tell which of the other 102 were close
  # to it — the ceiling was a policy with no data behind it. Now there is data.
  t0=$(date +%s)
  o=$(timeout -k 10 "$SUITE_TIMEOUT" "./native/$s" 2>&1)
  rc=$?
  secs=$(( $(date +%s) - t0 ))
  printf '%s\n' "$o" >> /out/SUITESFILE
  echo "----- $s exit: $rc  secs: $secs -----" >> /out/SUITESFILE

  # every suite in this repo ends with "<name>: N passed, M failed"
  tally=$(printf '%s\n' "$o" | grep -oE '[0-9]+ passed, [0-9]+ failed' | tail -1)
  if [ -n "$tally" ]; then
    okn=$(printf '%s' "$tally" | awk '{print $1}')
    failn=$(printf '%s' "$tally" | awk '{print $3}')
  else
    okn=$(printf '%s\n' "$o" | grep -cE '^[[:space:]]*(ok|PASS|pass)[[:space:]]+-')
    failn=$(printf '%s\n' "$o" | grep -cE '^[[:space:]]*(FAIL|fail|bad)[[:space:]]+-')
    [ "$okn$failn" = "00" ] && { okn=-; failn=-; }
  fi

  case $rc in
    0)         st=GREEN ;;
    124|137)   st="TIMEOUT(${SUITE_TIMEOUT}s)" ;;
    *)         st=RED ;;
  esac
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$s" "$rc" "$okn" "$failn" "$secs" "$st" >> /out/TSVFILE
done

echo "### build exit: $BUILD_RC" >> /out/TSVFILE
INSIDE
chmod +x "$WORK/inside.sh"

RESULTS="$WORK/results"
mkdir -p "$RESULTS"

INSPECT_PLAT=""
[ -n "$PLATFORM" ] && docker image inspect --platform "$PLATFORM" "$IMAGE_REF" >/dev/null 2>&1 \
  && INSPECT_PLAT="--platform $PLATFORM"
# shellcheck disable=SC2086
DIGEST=$(docker image inspect $INSPECT_PLAT --format '{{index .RepoDigests 0}}' "$IMAGE_REF" 2>/dev/null || true)
[ -n "$DIGEST" ] || DIGEST="(no RepoDigest — image is local-only)"
# shellcheck disable=SC2086
IMAGE_ID=$(docker image inspect $INSPECT_PLAT --format '{{.Id}}' "$IMAGE_REF")
# shellcheck disable=SC2086
IMG_ARCH=$(docker image inspect $INSPECT_PLAT --format '{{.Architecture}}' "$IMAGE_REF")

# The four-part label. Every count produced by this run is a claim about THIS
# string and nothing wider. It is printed to the terminal and written into the
# artifact so a number can never travel without it.
LABEL="$IMAGE_REF · ${PLATFORM:-host-default($IMG_ARCH)} · ${RUNUSER:-image-default(root)} · --network none"

PLAT_ARG=""; [ -n "$PLATFORM" ] && PLAT_ARG="--platform $PLATFORM"
USER_ARG="";  [ -n "$RUNUSER" ]  && USER_ARG="--user $RUNUSER"

CNAME="rabadon-refenv-$$"
RUN_LINE="docker run --rm --name $CNAME --network none $PLAT_ARG $USER_ARG -v $TREE:/w -v $RESULTS:/out -w /w -e SUITE_TIMEOUT=$SUITE_TIMEOUT -v $WORK/inside.sh:/inside.sh:ro $IMAGE_REF bash /inside.sh"

echo "refenv: image   $IMAGE_REF"
echo "refenv: digest  $DIGEST"
echo "refenv: id      $IMAGE_ID"
echo "refenv: arch    $IMG_ARCH"
echo "refenv: LABEL   $LABEL"
echo "refenv: HEAD    $HEAD_SHA"
echo "refenv: running (this takes a while; --network none)"
echo "refenv: $RUN_LINE"

# Copy artifacts out on EVERY exit path, kill included, so a run cut off at a
# time ceiling still leaves the rows it managed to measure. Without this the
# copy happened only after a clean finish and an interrupted census reported
# nothing at all — which is the one outcome that is never allowed here.
harvest() {
  [ -f "$RESULTS/ENVFILE" ]    && cp "$RESULTS/ENVFILE"    "$ENV_OUT"    2>/dev/null
  [ -f "$RESULTS/BUILDFILE" ]  && cp "$RESULTS/BUILDFILE"  "$BUILD_OUT"  2>/dev/null
  [ -f "$RESULTS/TSVFILE" ]    && cp "$RESULTS/TSVFILE"    "$TSV_OUT"    2>/dev/null
  [ -f "$RESULTS/SUITESFILE" ] && cp "$RESULTS/SUITESFILE" "$SUITES_OUT" 2>/dev/null
  return 0
}
cut_short() {
  echo "refenv: INTERRUPTED — harvesting partial results (a partial count is still a count)" >&2
  docker kill "$CNAME" >/dev/null 2>&1 || true
  harvest
  { echo; echo "### RUN INTERRUPTED — the rows above are a PARTIAL census."
    echo "### LABEL: $LABEL"
    echo "### command: $RUN_LINE"; } >> "$TSV_OUT" 2>/dev/null || true
  { echo; echo "### RUN INTERRUPTED before the header could be written."
    echo "LABEL:        $LABEL"
    echo "HEAD:         $HEAD_SHA"
    echo "command:      $RUN_LINE"; } >> "$ENV_OUT" 2>/dev/null || true
  awk -F'\t' 'NR>1 && $6!="" {c[$6]++} END {for (k in c) printf "refenv: PARTIAL %-16s %d\n", k, c[k]}' \
    "$TSV_OUT" 2>/dev/null || true
  cleanup
  exit 75
}
trap cut_short INT TERM

set +e
# shellcheck disable=SC2086
docker run --rm --name "$CNAME" --network none $PLAT_ARG $USER_ARG \
  -v "$TREE:/w" \
  -v "$RESULTS:/out" \
  -v "$WORK/inside.sh:/inside.sh:ro" \
  -e "SUITE_TIMEOUT=$SUITE_TIMEOUT" \
  -w /w \
  "$IMAGE_REF" bash /inside.sh
DOCKER_RC=$?
set -e

{
  echo "# rabadon reference environment measurement"
  echo "LABEL:        $LABEL"
  echo "              (every count from this run is a claim about THIS label only)"
  echo "date-utc:     $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "repo:         $REPO"
  echo "HEAD:         $HEAD_SHA"
  echo "host-dirty:   $DIRTY file(s) uncommitted in the source tree at measure time"
  echo "              (the container measured the COMMITTED tree; a clone, not the working copy)"
  echo "image:        $IMAGE_REF"
  echo "image-digest: $DIGEST"
  echo "image-id:     $IMAGE_ID"
  echo "image-arch:   $IMG_ARCH"
  echo "run-platform: ${PLATFORM:-(host default)}"
  echo "run-user:     ${RUNUSER:-(image default — root)}"
  echo "host-arch:    $(uname -m)  (emulation is in play when this differs from image-arch)"
  echo "docker:       $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo unknown)"
  echo "docker exit:  $DOCKER_RC"
  echo "command:"
  echo "  $RUN_LINE"
  echo
  [ -f "$RESULTS/ENVFILE" ] && cat "$RESULTS/ENVFILE"
} > "$ENV_OUT.tmp"
mv "$ENV_OUT.tmp" "$ENV_OUT"

[ -f "$RESULTS/BUILDFILE" ]  && cp "$RESULTS/BUILDFILE"  "$BUILD_OUT"
[ -f "$RESULTS/TSVFILE" ]    && cp "$RESULTS/TSVFILE"    "$TSV_OUT"
[ -f "$RESULTS/SUITESFILE" ] && cp "$RESULTS/SUITESFILE" "$SUITES_OUT"

echo "refenv: wrote $ENV_OUT"
echo "refenv: wrote $BUILD_OUT"
echo "refenv: wrote $TSV_OUT"
echo "refenv: wrote $SUITES_OUT"

if [ ! -f "$TSV_OUT" ]; then
  echo "refenv: COULD NOT MEASURE — the container produced no suite table (docker exit $DOCKER_RC)." >&2
  exit 70
fi

echo "refenv: LABEL   $LABEL"
awk -F'\t' 'NR>1 && $6!="" {c[$6]++} END {for (k in c) printf "refenv: %-16s %d\n", k, c[k]}' "$TSV_OUT"
exit 0
