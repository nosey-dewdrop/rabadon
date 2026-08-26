# Uninstalling rabadon

rabadon uninstalls cleanly. It strips exactly its own hooks and leaves your
settings and your ledger untouched unless you ask otherwise.

## Remove rabadon from a project

```
rabadon remove
```

This strips exactly rabadon's hooks (and a rabadon-owned statusLine, if any)
from `<project>/.claude/settings.json`, leaving every other hook in place. It
backs up the file to `settings.json.bak-rabadon` before editing.

**Cursor comes out too.** `rabadon init` writes `.cursor/hooks.json` as well,
and since 2026-08-26 `remove` takes those entries back out: your own Cursor
hooks stay exactly as they were, the file stays valid JSON, and if the file
held nothing but rabadon's own entries it is deleted rather than left as an
empty shell. A `.cursor/hooks.json.bak-rabadon` from the install is *not*
deleted — you may have edited it since, and restoring a backup is not a
removal's job. Before that date `remove` did not touch `.cursor/` at all, so a
Cursor user who installed earlier should run `remove` again on the current
build. Held by `native/exit_path_test.sh`.

Add `--purge` to also delete the project's `.rabadon/` directory (its
`guard.json` and any held repair patches):

```
rabadon remove --purge
```

Add `--global` to remove the hooks rabadon installed in
`~/.claude/settings.json` with `rabadon init --global`:

```
rabadon remove --global
```

`rabadon uninstall` is an alias for `rabadon remove`.

## Restore settings by hand

If you would rather revert wholesale instead of stripping, restore the backup
rabadon made the first time it wrote to your settings:

```
cp .claude/settings.json.bak-rabadon .claude/settings.json
```

(For a global install, the backup is `~/.claude/settings.json.bak-rabadon`.)

## Remove the CLI

```
npm rm -g rabadon
```

## The ledger is yours

The spool at `~/.rabadon` is your data and is **not** touched by `rabadon
remove` or by `npm rm -g rabadon`. Keep it, or delete it manually whenever you
like:

```
rm -rf ~/.rabadon
```

That directory holds the hash-chained event spool and the mode flag. Deleting it
resets rabadon's local state entirely; nothing there was ever sent off the
machine.
