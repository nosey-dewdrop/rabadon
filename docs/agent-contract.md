# Supervising an agent rabadon has never heard of

rabadon's laws were never about Claude Code. `git push --force origin main` is
the same refusal whoever typed it, and the rule engine does not know or care
which editor the session is running in. What used to be agent-specific was the
*binding*: the field names an editor puts on stdin were read in five separate
places, so a second agent meant finding all five and getting all five right.

They are read in one place now (`native/hookev.h`), and three dialects are
understood.

| your agent | what to do |
|---|---|
| Claude Code | `rabadon init` — merges hooks into `.claude/settings.json` |
| Cursor | `rabadon init` — also writes `.cursor/hooks.json` |
| anything else | use the contract below. No change to rabadon is needed. |

---

## The contract

Run `rabadon-gate` before (and after) the actions you want supervised. Write one
JSON object to its stdin. Read its exit code.

```json
{"rabadon":1,"event":"pre_tool","tool":"bash",
 "command":"git push --force origin main",
 "cwd":"/path/to/project","session":"conv-42","call":"step-7"}
```

**Exit code is the verdict.** `2` means refuse — do not run the action, and give
the text on stderr back to the model. `0` means proceed. Any other code means
rabadon itself failed, and you should proceed: a supervisor that breaks your
agent when it crashes is worse than no supervisor.

### Fields

| field | required | meaning |
|---|---|---|
| `rabadon` | yes | `1`. This is what selects the contract. |
| `event` | yes | `pre_tool` · `post_tool` · `prompt` · `session_start` · `stop` |
| `tool` | for tool events | `bash` · `edit` · `write` · `read`. Anything else is passed through under its own name. |
| `cwd` | yes | the project root. Rules and path containment are resolved against it. |
| `command` | for `bash` | the full command line, exactly as it would run |
| `file_path` | for file tools | absolute path |
| `session` | recommended | your conversation id. Groups the ledger. |
| `call` | recommended | your step id. Lets the pre and post events for one action join into a single span, and stops a retried event being counted twice. |
| `output` | for `post_tool` | what the command printed. This is what the test analysis reads. |
| `old_string` / `new_string` / `content` | for edits | the edit itself, so the test-tamper law can see whether an assertion was removed |
| `prompt` | for `prompt` | the user's message. Used to capture the session goal. |

### The smallest useful integration

Two lines around your shell tool:

```sh
printf '{"rabadon":1,"event":"pre_tool","tool":"bash","command":%s,"cwd":%s}' \
  "$(jq -Rn --arg c "$CMD" '$c')" "$(jq -Rn --arg d "$PWD" '$d')" \
  | rabadon-gate || exit 2
```

That alone buys every compiled-in law, every rule in the project's
`.rabadon/guard.json`, and a hash-chained ledger entry for each refusal.

---

## What each agent can and cannot do

This table is the honest part, and it exists because a supervisor that quietly
supervises less than it claims is worse than one that says where it stops.

| | Claude Code | Cursor | generic contract |
|---|---|---|---|
| refuse a shell command **before** it runs | yes | yes | yes |
| refuse a file edit **before** it lands | yes | **no** | yes, if you call it before |
| observe a file edit after the fact | yes | yes | yes |
| refuse an MCP tool call | yes | yes | yes |
| capture the session goal from the prompt | yes | yes | yes |
| goal-drift verdict at the end of a turn | yes | yes | yes |
| ledger, audit, export, lens | yes | yes | yes |
| put a diagnosis into the agent's context | yes | **late** | yes, if you call it before an action |
| `rabadon remove` takes the wiring back out | yes | yes | n/a — you own the call site |
| a ledger line attributable to *this* agent | yes | **not yet** | not yet |

Two rows there are new and worth reading slowly. `rabadon remove` strips its
own `.cursor/hooks.json` entries as of 2026-08-26 (`native/exit_path_test.sh`
holds it); before that date it stripped `.claude/settings.json` only, and a
Cursor user had no exit path at all. The last row is a measured absence rather
than a guess: no field in the ledger names the agent, so on 2026-08-26 the
count of ledger lines attributable to Cursor was `0` — and it would have been
`0` even if Cursor had fired, because there is nothing to attribute with. That
row changes when the field exists, not when Cursor is believed to work.

**The injection channel.** When a *likely*-level signal fires, rabadon does not
stop the agent. It writes what the agent cannot see — the file last edited, the
readable form of the error, the contrast ("after this move the suite was green,
after this one red"), and which attempt this is — and delivers it on the
**next** `PreToolUse`, in the documented envelope:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"…"}}
```

It rides the *next* call and not the one it was computed in, because the signal
that needs it most (`root_migration`) is only knowable once a command has failed,
which is `PostToolUse`, and `additionalContext` exists only on `PreToolUse`. No
model is called to write it: every sentence is assembled from the move record and
the ledger. Never a line number (file-level localisation helps; line-level
context measurably hurts), never an instruction, never more than 400 characters,
and the same signal speaks at most twice per session — the third goes to the
ledger only. `RABADON_INJECT=0` turns it off. It never changes an exit code.

**On Cursor this arrives late, and that is not hidden.** With no
`beforeFileEdit`, there is no pre-edit moment to ride, so the diagnosis is
delivered at the next point that exists — the next `beforeShellExecution`. An
agent that edits several times before running anything gets the diagnosis after
those edits, not between them. Everything else about it is identical.

**The Cursor gap is real.** Cursor has `afterFileEdit` and no `beforeFileEdit`,
so an edit made by the agent's own edit tool is recorded but not stopped before
it happens. Two things still hold on Cursor: a shell write (`>`, `tee`, `sed -i`,
`rm`) goes through `beforeShellExecution` and is refused pre-spend, and
`rabadon exec -- <cmd>` compiles protected paths into an OS sandbox, so a
forbidden write fails with `EPERM` no matter who tried it.

---

## Adding a dialect properly

If your agent has a real hook system, a first-class dialect is one function in
`native/hookev.h`:

1. add its `hook_event_name` values to `detect()`
2. write `parse_yours(raw)` filling the same `HookEvent` struct
3. if it reads a verdict off stdout rather than the exit code, add that one
   branch to the refusal in `gate.cpp`

`native/agents_test.sh` is where you prove it. Every case there drives a **real**
refusal through a payload that shares no field names with the other dialects,
which is the only way to be sure the gate is reading your event and not
accidentally still reading somebody else's.
