# CHALLENGE 3 — KOSU-RABADON-2.md A1 claims a test that does not exist

Status: OPEN. Raised tur 8 (2026-08-24). A challenged step is treated as RED.
This challenge does NOT touch the invariants block. It needs a human-approved
diff to KOSU-RABADON-2.md in its own commit.

## The claim

`KOSU-RABADON-2.md:63-69`, the "Mimari kural — soket yolu (24.08)" block, ends:

> Soket yolu KISA ve MUTLAK: `${XDG_RUNTIME_DIR:-/tmp}/rabadon-$UID.sock`, 0600
> izin; **yol uzunluğu sınırı R7 testinde assert edilir.**

("the path length limit is asserted in the R7 test")

## The evidence that it is false

```
$ grep -niE 'sun_path|ENAMETOOLONG|104|108|path.*(length|len|too long)' reports/R7/accept.sh
>>> no match
```

`reports/R7/accept.sh` contains no socket-path-length assertion of any kind.
Its only length-related work is GOAL 2c, which is about *ledger* length
dependence (`accept.sh:145`, `210-241`) — a different quantity entirely.

Nor is the assertion anywhere else: a grep for `sun_path` / `ENAMETOOLONG`
across `native/*.cpp`, `native/*.h` and `native/*.sh` finds the guard only
inside the product (`native/gated.cpp:157`, `native/gated_client.h:98`) and in
no test. `reports/R7/DENEMELER.md:113-114` measured one path once (79 bytes);
that is a measurement, not a check, and it cannot fail.

So the document asserts that a risk is covered by a test, and it is not
covered by anything. This is exactly the failure mode the architectural rule
itself was written to prevent: an agent hits a truncated-path failure, believes
a test would have caught it, and looks for the bug in the C++.

## Why it is not merely cosmetic

The unguarded path is reachable in this project's own reference environment.
A `mktemp -d` HOME — what the acceptance script itself uses — yields a
`sockPath` of ~85 bytes against a macOS cap of 104: **19 bytes of headroom,
unguarded**. And the consequence of overrunning it is not a clean failure; see
the separate finding on `native/gate.cpp:721`, where truncation silently
connects to a *different* socket and ships the ledger stream there.

## Proposed diff (NOT applied — needs human approval)

Either make the sentence true, or delete it. Making it true is preferred and
is the smaller change, because the test is worth having on its own merits:

```diff
--- a/KOSU-RABADON-2.md
+++ b/KOSU-RABADON-2.md
@@ -66,8 +66,10 @@
 MUTLAK: `${XDG_RUNTIME_DIR:-/tmp}/rabadon-$UID.sock`, 0600 izin; yol uzunluğu
-sınırı R7 testinde assert edilir. Değerlendiren bu kuralı ilk R7 talimatına
-aynen taşır.
+sınırı `native/sock_path_test.sh`'ta assert edilir (24.08'e kadar HİÇBİR
+testte assert EDİLMİYORDU — CHALLENGE-3). Test, kapasitenin aşıldığı durumda
+(a) kesik yola HİÇBİR bayt gitmediğini ve (b) sebebin stderr'e yazıldığını
+kanıtlar. Değerlendiren bu kuralı ilk R7 talimatına aynen taşır.
```

The maker of tur 8 did NOT apply this diff and did not edit KOSU-RABADON-2.md.
The accompanying test is being written separately; until a human approves the
diff above, the document and the tree still disagree, and this stays OPEN.
