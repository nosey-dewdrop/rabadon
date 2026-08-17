#!/bin/bash
# field_redaction_test.sh — the published field file may not carry a home path,
# and a HALF of one is still one.
#
# site/field_stats.py rewrites the home directory to `~`, replaces the account
# name with `home`, and then refuses to write at all if the account name
# survived. Every one of those three steps matches a WHOLE string, and the
# details it is redacting were already clipped by the gate that wrote them. So a
# line the gate cut mid-path arrives as
#
#     ... && R=/Users/damu
#
# and there is nothing left for `replace(HOME, "~")` to match, nothing for
# `replace(USER, "home")` to match, and nothing for the refusal check to see —
# because the account name it looks for was cut in half two steps earlier. Two
# records shaped exactly like that reached site/field.jsonl and were published.
#
# The invariant this file holds is not "the account name is replaced". It is
# that no absolute path under a user's home reaches the published file, whole or
# truncated, and that a record carrying one stops the write instead of riding
# along in it.
#
# Everything runs against a spool and a repository built here in a temp tree, so
# the real ledger and the real site/ directory are never read or written.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# an isolated home, an isolated spool, an isolated copy of the script under an
# isolated site/ — field_stats.py locates the spool from $HOME and the output
# from its own path, so redirecting both is enough to make this hermetic.
FAKEHOME="$T/alicewonder"
mkdir -p "$FAKEHOME/.rabadon/spool" "$T/repo/site"
cp "$REPO/site/field_stats.py" "$T/repo/site/field_stats.py"
# the redactor moved out of field_stats.py into site/redact.py so the census
# generator could publish through the same one; the isolated site/ needs both
# files or the script under test cannot import itself into existence.
cp "$REPO/site/redact.py" "$T/repo/site/redact.py"
# field_stats.py imports site/identity.py to answer what a project label
# denotes; a fixture without it tests an ImportError, not a generator.
cp "$REPO/site/identity.py" "$T/repo/site/identity.py"
cp "$REPO/site/non-projects.txt" "$T/repo/site/non-projects.txt"

# the record the gate really wrote, with the home path cut mid-account-name.
# `alicewond` is what is left of `$FAKEHOME` after a clip, the same shape as the
# `/Users/damu` that shipped.
CUT="${FAKEHOME%???}"          # drop the last three characters: a truncated home
python3 - "$FAKEHOME/.rabadon/spool/2026-08-03.jsonl" "$FAKEHOME" "$CUT" <<'PY'
import json, sys
out, home, cut = sys.argv[1], sys.argv[2], sys.argv[3]
rows = [
    # 1. a whole home path — the case redaction already handled
    {"ev": "WOULD_BLOCK", "rule": "no-force-push-main", "pipe": "proj:session", "ts": 1785510757908,
     "detail": "command matched deny rule: git push --force origin main from " + home + "/work/proj"},
    # 2. a home path the gate clipped mid-account-name — the case that shipped
    {"ev": "WOULD_BLOCK", "rule": "no-force-push-main", "pipe": "proj:session", "ts": 1785510746415,
     "detail": "command matched deny rule: cd /tmp/x && G=~/proj/native/rabadon-gate && R=" + cut},
    # 3. a foreign absolute home path, from somebody else's CI output
    {"ev": "STOP", "rule": "push-gate", "pipe": "proj:session", "ts": 1785510746500,
     "detail": "FAIL /home/runner/work/proj/proj/test/index.js"},
    # 4. a clean record, which must survive all of this
    {"ev": "STOP", "rule": "push-gate", "pipe": "proj:session", "ts": 1785510746600,
     "detail": "the suite was red when the push was attempted"},
]
with open(out, "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY

echo "field redaction — a truncated home path is still a home path"
echo

OUT="$T/run.log"
HOME="$FAKEHOME" python3 "$T/repo/site/field_stats.py" --write >"$OUT" 2>&1
rc=$?

PUB="$T/repo/site/field.jsonl"

# ---------------------------------------------------------------------------
# 1. the write either refuses, or it produces a file with nothing to hide
# ---------------------------------------------------------------------------
echo "1. what reached the published file"
if [ $rc -ne 0 ]; then
  # refusing is a legitimate answer, but only if it says why
  if grep -q "REFUSING TO WRITE" "$OUT"; then
    ok "refused to write and said so (exit $rc)"
  else
    bad "exited $rc without saying why"
    sed -n '1,20p' "$OUT"
  fi
  [ -f "$PUB" ] && bad "refused, yet still wrote $PUB"
else
  if [ ! -f "$PUB" ]; then
    bad "exit 0 but no field.jsonl was written"
  else
    ok "wrote the published file"
  fi
fi

if [ -f "$PUB" ]; then
  for pat in "$FAKEHOME" "$CUT" "alicewonder" "alicewond" "/Users/" "/home/"; do
    if grep -qF -- "$pat" "$PUB"; then
      bad "published file still carries '$pat'"
      grep -nF -- "$pat" "$PUB" | head -2 | sed 's/^/        /'
    else
      ok "no '$pat' in the published file"
    fi
  done

  # the clean record has to survive: a redactor that solves the problem by
  # dropping every record is not a redactor.
  if grep -q "the suite was red when the push was attempted" "$PUB"; then
    ok "the record with nothing to hide was published unchanged"
  else
    bad "the clean record did not survive redaction"
  fi

  # and the file has to still be one JSON object per line
  if python3 - "$PUB" <<'PY'
import json, sys
for i, line in enumerate(open(sys.argv[1], encoding="utf-8"), 1):
    line = line.strip()
    if line:
        json.loads(line)
PY
  then ok "every published line is valid JSON"
  else bad "the published file is not line-delimited JSON any more"
  fi
fi

# ---------------------------------------------------------------------------
# 2. a record that CANNOT be redacted must stop the write, not ride along
# ---------------------------------------------------------------------------
# The account name spelled out in prose, with no path around it, is the case the
# existing check was written for. It must still stop the write.
echo
echo "2. the refusal still works when redaction cannot reach"
rm -f "$PUB"
python3 - "$FAKEHOME/.rabadon/spool/2026-08-03.jsonl" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write(json.dumps({"ev": "WOULD_BLOCK", "rule": "r", "pipe": "alicewonder:session",
                        "ts": 1, "detail": "nothing to see"}, ensure_ascii=False) + "\n")
PY
HOME="$FAKEHOME" python3 "$T/repo/site/field_stats.py" --write >"$OUT" 2>&1
if [ -f "$PUB" ] && grep -qF "alicewonder" "$PUB"; then
  bad "a session named after the account published the account name"
else
  ok "a session named after the account did not leak it"
fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
