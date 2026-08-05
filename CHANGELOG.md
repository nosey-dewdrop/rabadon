# Changelog

All notable changes to rabadon. Dates are the day the tag was pushed.

## 0.2.1 — 2026-08-05

- The v0.2.0 release build failed on the macOS runner and took the publish job with it. A test that stands up a throwaway git remote let the host name the branch, so a box configured for `master` produced `src refspec main does not match any` while the same test passed here. The lab now names its own branch. Reproduced with the host forced to `master`: 144 passed and 2 failed before, 146 passed and 0 failed after.
- Published site data is written through a redactor rather than beside one. Absolute home paths are rewritten and records matching a private-project list are dropped and counted, so a published file states how many records it withheld instead of quietly shrinking. A test reads what the domain would serve and fails if either ever reappears.

## 0.2.0 — 2026-08-05

First published release. `npm i -g rabadon`.

### The gate
- Deny decisions are made in native C++ before a command is produced, not after it runs. Force-push to a protected branch, recursive deletes outside a project, and untested pushes are refused at emit time.
- Three laws are compiled into the binary and cannot be disabled from a project file. Everything else lives in a project's `.rabadon/guard.json`, and a rule born from a real incident carries `authoredBy: incident`.
- `rabadon drill` produces a real refusal on a throwaway command so a new user sees the mechanism in one step. Drills are tagged at emit and excluded from the ledger, so they never inflate `rabadon usage`.

### The repair loop
- When a suite goes red, a proposer writes a patch in an isolated copy and the arbiter runs the project's own check command. The verdict is that command's exit code. No model is asked whether the repair is real.
- Test files and the harness are hash-locked before the proposer starts. A patch that edits, deletes, skips, or neuters a locked test is refused, and the accepted-repair counter does not move.
- A red result is re-sampled. If two samples disagree the verdict is FLAKY rather than verified.

### The ledger
- Every gated event is appended to a hash-chained day file. `rabadon audit` detects an edited character, a dropped line, a truncated tail, a stripped `prev`, a re-forged chain, and a deleted day file.
- Events carry the calling tool's id and the session id, so a trace can be rebuilt per session without instrumenting anything.

### Install
- Prebuilt binaries ship as `@rabadon/<platform>` optional dependencies with npm provenance. Where no prebuilt matches, `postinstall` compiles the native core from the source in the package.
- Verified on a clean HOME from the packed tarball: install, `rabadon init`, `rabadon on`, `rabadon drill`, and the gate refuses with exit 2.

### Packaging
- The published tarball carries 53 files at 360.3 kB. Unit tests, demo fixtures, example guard packs, and maintainer release scripts are no longer shipped.
