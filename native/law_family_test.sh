#!/usr/bin/env bash
# law_family_test.sh — A GUARD THAT CAN BE UNMADE IS NOT A GUARD.
#
# WHAT WAS MEASURED, and where. F3f closed ONE shape: `rm .rabadon/guard.json`
# stopped being suppressed. The shape was not the defect. The defect is that
# the law file was protected by NAME, and a name protects neither the directory
# that holds it nor the nine other verbs that take a file apart. Measured
# against the shipped binary on 2026-08-30, in a project sandbox under $HOME —
# deliberately NOT under ${TMPDIR:-/tmp}, because the scope law exempts a
# machine temp root and an earlier "live bypass" reading was inflated by
# exactly that (reports/kosu/kanit/f3g/k1-oncesi.txt), verbatim:
#
#     rm -rf .rabadon                             -> rc=0  ALLOWED
#     rm -rf ./.rabadon                           -> rc=0  ALLOWED
#     truncate -s 0 .rabadon/guard.json           -> rc=0  ALLOWED
#     cp /dev/null .rabadon/guard.json            -> rc=0  ALLOWED
#     chmod 000 .rabadon/guard.json               -> rc=0  ALLOWED
#     ln -sf /dev/null .rabadon/guard.json        -> rc=0  ALLOWED
#     install /dev/null .rabadon/guard.json       -> rc=0  ALLOWED
#     dd if=/dev/null of=.rabadon/guard.json      -> rc=0  ALLOWED
#     find .rabadon -name guard.json -delete      -> rc=0  ALLOWED
#
# Eight of those nine spell no verb any law knows. Enumerating verbs is how the
# list goes stale — `shred` is the standing proof in cmdtext.h. So this suite
# does not ask "is the verb one of ours". It asks the only question that closes
# a FAMILY instead of a shape: **after this segment runs, is the project's own
# copy of the law still there, still whole, still readable?** Anything that is
# not a known READ of that path is refused, and the known reads are asserted
# from the other side in ARM 3 so the narrowing cannot become a false positive.
#
# THE FIXTURE CARRIES NO DENY RULES. `bash` is empty on purpose: a green here
# is a claim about the BINARY, not about a regex in a JSON file that the next
# session can edit. The rule in .rabadon/guard.json may also refuse some of
# these; that is not what is being measured.
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"

PASSN=0; FAIL=0
pass() { printf '  ok   - %s\n' "$1"; PASSN=$((PASSN + 1)); }
fail() { printf '  FAIL - %s\n' "$1"; FAIL=$((FAIL + 1)); }
[ -x "$GATE" ] || { printf 'law_family: no gate binary at %s — run make first\n' "$GATE" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'law_family: python3 is required\n' >&2; exit 1; }

# OUTSIDE the machine temp roots, on purpose (see the header). $HOME is the one
# writable place every reference environment has, container root included.
LAB="${RABADON_LAB:-$HOME}"
T="$(mktemp -d "$LAB/.rb-lawfam.XXXXXX")" || { printf 'law_family: cannot make a sandbox under %s\n' "$LAB" >&2; exit 1; }
cleanup() { chmod -R u+rwX "$T" 2>/dev/null; /bin/rm -rf "$T"; }
trap cleanup EXIT

RD="$T/rd"; mkdir -p "$RD"; : > "$RD/enabled"
P="$T/proj"; mkdir -p "$P/.rabadon" "$P/.git" "$P/build" "$P/.rabadonx" "$P/notrabadon"
printf 'ref: refs/heads/main\n' > "$P/.git/HEAD"
printf '{"project":"lawfam","bash":[],"protectedPaths":[]}\n' > "$P/.rabadon/guard.json"
printf '{"promise":"x"}\n' > "$P/.rabadon/promise.json"
printf 'notes\n' > "$P/README.md"
printf 'log\n' > "$P/log.txt"
printf 'a\n' > "$P/a.txt"
: > "$P/.rabadon-backup"

verdict() { # verdict <cwd> <command> -> ALLOW|REFUSE
  python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","session_id":"lawfam","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]}}))' "$1" "$2" \
    | env RABADON_DIR="$RD" RABADON_JUDGE=0 RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1
  [ "$?" = "2" ] && printf 'REFUSE' || printf 'ALLOW'
}

echo "law_family: the law file, its directory, and everything that unmakes either"

# ---------------------------------------------------------------------------
# ARM 1 — THE EIGHT MEASURED SHAPES. Each is its own assertion, by name, so a
# repair that closes seven of eight cannot report green.
while IFS='|' read -r cmd label; do
  [ -n "$cmd" ] || continue
  v="$(verdict "$P" "$cmd")"
  [ "$v" = "REFUSE" ] && pass "shape refused: $label" \
                      || fail "ALLOWED: $label — the law can still be unmade"
done <<'CMDS'
rm -rf .rabadon|1/8 rm -rf of the law directory
rm -rf ./.rabadon|2/8 the same directory spelled with ./
truncate -s 0 .rabadon/guard.json|3/8 truncate empties it, inode intact
cp /dev/null .rabadon/guard.json|4/8 cp overwrites it with nothing
chmod 000 .rabadon/guard.json|5/8 chmod makes it unreadable to the gate
ln -sf /dev/null .rabadon/guard.json|6/8 ln replaces it with a symlink
install /dev/null .rabadon/guard.json|7/8 install overwrites it
dd if=/dev/null of=.rabadon/guard.json|8/8 dd opens of= for writing
find .rabadon -name guard.json -delete|8+1 find -delete removes what the walk matches
CMDS

# ---------------------------------------------------------------------------
# ARM 2 — THE SIBLINGS. The eight above are a sample of the family, not the
# family. Anything that removes, empties, replaces, renames, or locks the law
# out of reach belongs here, whatever it is called.
while IFS='|' read -r cmd label; do
  [ -n "$cmd" ] || continue
  v="$(verdict "$P" "$cmd")"
  [ "$v" = "REFUSE" ] && pass "sibling refused: $label" \
                      || fail "ALLOWED: $label"
done <<'CMDS'
rm .rabadon/guard.json|rm by name, the one shape F3f closed
rm -f .rabadon/promise.json|rm -f of the promise
rm -rf .rabadon/|the directory with a trailing slash
rmdir .rabadon|rmdir of the law directory
mv .rabadon /somewhere-else|moving the whole directory away
mv .rabadon/guard.json ./guard.json.bak|renaming the law out from under itself
chmod 000 .rabadon|locking the directory instead of the file
chmod -R 000 .rabadon|the recursive form
unlink .rabadon/guard.json|unlink, which is rm without the name rm
shred -u .rabadon/guard.json|shred, in the delete family since it existed
truncate --size 0 .rabadon/promise.json|the long form of the size flag
dd of=.rabadon/guard.json if=/dev/null|dd with its operands the other way round
install -m 000 /dev/null .rabadon/guard.json|install with a mode
ln -sf /dev/null .rabadon/promise.json|the symlink swap on the promise
cp /dev/null ./.rabadon/promise.json|cp with a ./ spelling
echo {} > .rabadon/guard.json|a truncating redirect, the original 2026-08-03 incident
echo {} >> .rabadon/guard.json|an appending redirect still corrupts the document
cat /dev/null > .rabadon/promise.json|the same redirect with a different producer
tee .rabadon/guard.json < /dev/null|tee writes its operand
tee -a .rabadon/guard.json < /dev/null|tee -a appends to it
sed -i '' s/a/b/ .rabadon/guard.json|an in-place editor
perl -pi -e s/a/b/ .rabadon/guard.json|the same, one interpreter over
find .rabadon -name '*.json' -exec rm {} ;|find -exec of a delete
git rm -f .rabadon/guard.json|git rm is still an rm
cd .rabadon && rm guard.json|the path assembled by a cd, never spelled whole
chown nobody .rabadon/guard.json|handing the file to somebody else
find . -name guard.json -delete|the walk started from the project root
CMDS

# ---------------------------------------------------------------------------
# ARM 3 — THE TWIN ARM, and the reason this is a narrowing and not a wall.
# READING the law is the most ordinary thing an operator does with it, and
# §4.3 counts a false positive as the expensive kind of wrong. Every one of
# these must still be ALLOWED, in the same suite, against the same binary.
while IFS='|' read -r cmd label; do
  [ -n "$cmd" ] || continue
  v="$(verdict "$P" "$cmd")"
  [ "$v" = "ALLOW" ] && pass "read stays allowed: $label" \
                     || fail "FALSE POSITIVE: $label"
done <<'CMDS'
cat .rabadon/guard.json|cat
grep -c rm .rabadon/guard.json|grep whose PATTERN is the word rm
grep -n deny .rabadon/guard.json|grep -n
head -5 .rabadon/guard.json|head
tail -5 .rabadon/guard.json|tail
wc -l .rabadon/guard.json|wc
ls -la .rabadon|listing the directory
git diff .rabadon/guard.json|git diff
git log --oneline .rabadon/guard.json|git log
python3 -m json.tool .rabadon/guard.json|an interpreter READING it
sed -n 1,5p .rabadon/guard.json|sed WITHOUT an in-place flag
diff .rabadon/guard.json /dev/null|diff
stat .rabadon/guard.json|stat
cp .rabadon/guard.json ./guard-copy.json|copying it OUT is a read of the law
CMDS

# ---------------------------------------------------------------------------
# ARM 4 — ordinary destructive work in the same project, unchanged. If this arm
# reddens the law stopped being about the law.
while IFS='|' read -r cmd label; do
  [ -n "$cmd" ] || continue
  v="$(verdict "$P" "$cmd")"
  [ "$v" = "ALLOW" ] && pass "ordinary work stays allowed: $label" \
                     || fail "REFUSED: $label — the law widened past its subject"
done <<'CMDS'
rm -rf build|the project's own build directory
rm -f README.md|an ordinary file in the tree
chmod 755 README.md|an ordinary chmod
truncate -s 0 log.txt|an ordinary truncate
dd if=/dev/null of=log.txt|an ordinary dd
mv a.txt b.txt|an ordinary rename
cp /dev/null log.txt|an ordinary overwrite
echo x > log.txt|an ordinary redirect
find . -name '*.tmp' -delete|an ordinary find -delete
rm -rf .rabadonx|a directory whose name merely STARTS with the law's
rm -rf notrabadon|a directory whose name merely CONTAINS it
rm -f .rabadon-backup|a file beside the directory, not inside it
CMDS

printf 'law_family: %d passed, %d failed\n' "$PASSN" "$FAIL"
[ "$FAIL" = "0" ] || exit 1
