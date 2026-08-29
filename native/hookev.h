// hookev.h — one place that turns SOMEBODY ELSE'S event into rabadon's event.
//
// WHY THIS FILE EXISTS
// The laws are agent-agnostic. `git push --force origin main` is the same
// refusal whoever typed it, and none of gate.cpp's rule engine cares which
// editor the session is running in. The binding was not agnostic: the fields
// Claude Code puts on stdin were read in five separate places inside main(),
// each with its own spelling and its own fallback, so supporting a second agent
// meant finding all five and getting all five right. A person will miss one.
// That is not a portability inconvenience, it is the reason a user opens
// rabadon, sees "Claude Code" and closes the tab.
//
// So: every dialect is parsed HERE, into one struct, and main() reads the
// struct. Adding an agent is writing one function in this file.
//
// THREE DIALECTS ARE UNDERSTOOD
//   claude   Claude Code hooks. hook_event_name is PreToolUse / PostToolUse /
//            PostToolUseFailure / UserPromptSubmit / SessionStart / Stop.
//
//            PostToolUseFailure IS THE COMPLETION OF A TOOL CALL THAT FAILED,
//            and it is a separate event name, not a flag on PostToolUse. That
//            one fact was a hole straight through this product for four
//            phases: `err_sig` -- the only signature "the same error came
//            back" is ever measured against -- is assigned in the completion
//            branch and nowhere else, so a command that exited non-zero left a
//            STEP_START with nothing closing it and no signature at all. The
//            calls rabadon exists for were the calls it could not see.
//            Measured live 2026-08-29 and kept verbatim in
//            reports/kosu/RAPOR/f3e-1-posttooluse-failure-payload.json:
//              {"hook_event_name":"PostToolUseFailure","tool_name":"Bash",
//               "tool_input":{...},"tool_use_id":"toolu_...",
//               "error":"Exit code 1\nls: /nope: No such file or directory",
//               "is_interrupt":false,"duration_ms":184}
//            There is no tool_response on it; the output lives in `error`. It
//            is normalised to PostToolUse here, because downstream this IS a
//            completion, and the one thing the name adds -- that the call
//            really failed, as a fact from the harness rather than a guess
//            from the text -- is carried on `failed`.
//   cursor   Cursor agent hooks. hook_event_name is beforeShellExecution /
//            afterFileEdit / beforeReadFile / beforeSubmitPrompt / stop /
//            sessionStart. Cursor reads exit 2 as a block, same as Claude Code,
//            and additionally reads a permission verdict off stdout.
//   generic  rabadon's OWN shape, documented in docs/agent-contract.md, for the
//            fourth agent nobody has written a parser for. Anything that can run
//            a subprocess and pipe JSON can be supervised without a line of new
//            code here. That is the difference between supporting agents and
//            being portable.
//
// The dialect is decided by the VALUE of hook_event_name, never by guessing at
// the shape, because two agents can easily send a `command` and a `cwd` and mean
// different things by them. An event nobody recognises returns UNKNOWN and the
// gate falls open, which is the same thing it already did for an unknown Claude
// Code hook name.
//
// WHAT IS DELIBERATELY NOT HERE: the OUTPUT side lives in gate.cpp next to the
// refusal it renders, because a refusal has to name a rule and quote a detail
// that only that code path has. This file answers "what happened"; gate.cpp
// answers "what do we say about it".
#pragma once

#include <string>
#include "rules.h"

namespace rbhook {

using std::string;

enum Dialect { DIALECT_UNKNOWN = 0, DIALECT_CLAUDE, DIALECT_CURSOR, DIALECT_GENERIC };

struct HookEvent {
  Dialect dialect = DIALECT_UNKNOWN;

  // rabadon's internal vocabulary is Claude Code's, because that is what every
  // downstream branch in gate.cpp is already written against. Renaming it would
  // be a second refactor riding on this one, and would touch the rule engine
  // this change is supposed to leave alone.
  //   "PreToolUse" "PostToolUse" "UserPromptSubmit" "SessionStart" "Stop"
  //   "SessionEnd"  — R6's close hook. Stop fires at the end of every turn;
  //   SessionEnd fires once, when the session is actually over, which is the
  //   only moment a session-total is a session-total.
  string hook;

  string cwd;
  string toolName;        // Bash / Edit / Write / Read / MultiEdit / NotebookEdit
  string command;         // Bash
  string filePath;        // Edit / Write / Read
  string sessionId;
  string toolUseId;
  string toolResponse;    // the tool's output, for the post-run test analysis
  string prompt;          // UserPromptSubmit
  string transcriptPath;

  // Edit payloads. Read here rather than re-parsed downstream: these three were
  // pulled straight out of the raw text at four different offsets in main(),
  // which is exactly the spread this file exists to end.
  string oldString;
  string newString;
  string content;

  string raw;             // kept for the fields no dialect has normalised yet
  bool   sawToolInput = false;  // "tool_input was present at all", which is not
                                // the same question as "command is empty"

  // THE HARNESS SAID SO. Not "the output looked like an error" -- that guess
  // already exists downstream as err_sig, and it is silent for a command that
  // fails with no message. This is the agent telling us the call did not
  // succeed, which is a different and stronger fact, and it is the only one
  // that can honestly close a record.
  bool   failed = false;
};

// ---------- dialect detection ----------
// One string decides it. Cursor and Claude Code both send hook_event_name and
// their value spaces do not overlap, so this is a lookup and not a heuristic.
inline Dialect detect(const string& raw) {
  if (raw.find("\"rabadon\"") != string::npos) return DIALECT_GENERIC;
  const string h = rbrules::get_str(raw, "hook_event_name");
  if (h == "PreToolUse" || h == "PostToolUse" || h == "PostToolUseFailure" ||
      h == "UserPromptSubmit" ||
      h == "SessionStart" || h == "Stop" || h == "SessionEnd")
    return DIALECT_CLAUDE;
  if (h == "beforeShellExecution" || h == "afterShellExecution" ||
      h == "beforeMCPExecution"   || h == "afterMCPExecution"   ||
      h == "beforeReadFile"       || h == "afterFileEdit"       ||
      h == "beforeSubmitPrompt"   || h == "sessionStart"        ||
      h == "sessionEnd"           || h == "stop")
    return DIALECT_CURSOR;
  return DIALECT_UNKNOWN;
}

// ---------- Claude Code ----------
inline HookEvent parse_claude(const string& raw) {
  HookEvent e;
  e.dialect = DIALECT_CLAUDE;
  e.raw = raw;
  e.hook = rbrules::get_str(raw, "hook_event_name");
  // A failed call is a completion. Normalised here so that not one downstream
  // branch has to learn a second name for the same moment -- the alternative
  // was a second `hook ==` test in every one of them, and the missed one is
  // how this hole stayed open.
  if (e.hook == "PostToolUseFailure") {
    e.hook = "PostToolUse";
    e.failed = true;
    // The output of a failed call is on `error`; there is no tool_response.
    e.toolResponse = rbrules::get_str(raw, "error");
  }
  e.cwd = rbrules::get_str(raw, "cwd");
  e.toolName = rbrules::get_str(raw, "tool_name");
  e.sessionId = rbrules::get_str(raw, "session_id");
  e.toolUseId = rbrules::get_str(raw, "tool_use_id");
  e.prompt = rbrules::get_str(raw, "prompt");
  e.transcriptPath = rbrules::get_str(raw, "transcript_path");

  const size_t ti = raw.find("\"tool_input\"");
  e.sawToolInput = ti != string::npos;
  if (e.sawToolInput) {
    e.command = rbrules::get_str(raw, "command", ti);
    e.filePath = rbrules::get_str(raw, "file_path", ti);
    if (e.filePath.empty()) e.filePath = rbrules::get_str(raw, "notebook_path", ti);
    e.oldString = rbrules::get_str(raw, "old_string", ti);
    e.newString = rbrules::get_str(raw, "new_string", ti);
    e.content = rbrules::get_str(raw, "content", ti);
  }
  return e;
}

// ---------- Cursor ----------
// Mapped against cursor.com/docs/hooks. Two honest gaps, stated rather than
// papered over, because a supervisor that quietly supervises less than it claims
// is worse than one that says where it stops:
//
//   1. Cursor has afterFileEdit and no beforeFileEdit. An edit by the agent's
//      edit tool can be OBSERVED but not refused before it lands. Shell writes
//      still go through beforeShellExecution and are refused before they run,
//      and `rabadon exec` still holds the kernel fence. So on Cursor the file
//      rules are post-hoc and the command rules are pre-spend.
//   2. Cursor's edit payload is a LIST. Only the first edit is normalised into
//      oldString/newString; the raw text is kept so a caller that needs the rest
//      can still reach it.
inline HookEvent parse_cursor(const string& raw) {
  HookEvent e;
  e.dialect = DIALECT_CURSOR;
  e.raw = raw;
  const string h = rbrules::get_str(raw, "hook_event_name");

  e.cwd = rbrules::get_str(raw, "cwd");
  if (e.cwd.empty()) {
    // workspace_roots is an array of paths; the first is the project root.
    const std::vector<string> roots = rbrules::get_str_array(raw, "workspace_roots");
    if (!roots.empty()) e.cwd = roots[0];
  }
  e.sessionId = rbrules::get_str(raw, "conversation_id");
  e.toolUseId = rbrules::get_str(raw, "generation_id");
  e.transcriptPath = rbrules::get_str(raw, "transcript_path");

  if (h == "beforeShellExecution" || h == "beforeMCPExecution") {
    e.hook = "PreToolUse";
    e.toolName = "Bash";
    e.command = rbrules::get_str(raw, "command");
    e.sawToolInput = true;
  } else if (h == "afterShellExecution" || h == "afterMCPExecution") {
    e.hook = "PostToolUse";
    e.toolName = "Bash";
    e.command = rbrules::get_str(raw, "command");
    e.toolResponse = rbrules::get_str(raw, "output");
    e.sawToolInput = true;
  } else if (h == "beforeReadFile") {
    e.hook = "PreToolUse";
    e.toolName = "Read";
    e.filePath = rbrules::get_str(raw, "file_path");
    e.sawToolInput = true;
  } else if (h == "afterFileEdit") {
    e.hook = "PostToolUse";
    e.toolName = "Edit";
    e.filePath = rbrules::get_str(raw, "file_path");
    const size_t ed = raw.find("\"edits\"");
    if (ed != string::npos) {
      e.oldString = rbrules::get_str(raw, "old_string", ed);
      e.newString = rbrules::get_str(raw, "new_string", ed);
    }
    e.sawToolInput = true;
  } else if (h == "beforeSubmitPrompt") {
    e.hook = "UserPromptSubmit";
    e.prompt = rbrules::get_str(raw, "prompt");
  } else if (h == "sessionStart") {
    e.hook = "SessionStart";
  } else if (h == "sessionEnd") {
    // Cursor's close event, mapped to the close event — not to Stop. R6 prints
    // the session's total here, and a total printed at the end of every turn is
    // a different number wearing the same sentence.
    e.hook = "SessionEnd";
  } else if (h == "stop") {
    e.hook = "Stop";
  }
  return e;
}

// ---------- rabadon's own contract ----------
// The point of this dialect is that agent number four needs no code here. It is
// documented in docs/agent-contract.md and it is deliberately small: the five
// things the laws actually read.
//
//   {"rabadon":1,"event":"pre_tool","tool":"bash","command":"git push --force",
//    "cwd":"/path","session":"s1","call":"c1"}
//
// event: pre_tool | post_tool | prompt | session_start | stop
// tool:  bash | edit | write | read   (anything else is passed through verbatim)
inline HookEvent parse_generic(const string& raw) {
  HookEvent e;
  e.dialect = DIALECT_GENERIC;
  e.raw = raw;
  const string ev = rbrules::get_str(raw, "event");
  if (ev == "pre_tool") e.hook = "PreToolUse";
  else if (ev == "post_tool") e.hook = "PostToolUse";
  else if (ev == "prompt") e.hook = "UserPromptSubmit";
  else if (ev == "session_start") e.hook = "SessionStart";
  else if (ev == "stop") e.hook = "Stop";
  else if (ev == "session_end") e.hook = "SessionEnd";

  const string t = rbrules::get_str(raw, "tool");
  if (t == "bash") e.toolName = "Bash";
  else if (t == "edit") e.toolName = "Edit";
  else if (t == "write") e.toolName = "Write";
  else if (t == "read") e.toolName = "Read";
  else e.toolName = t;

  e.cwd = rbrules::get_str(raw, "cwd");
  e.command = rbrules::get_str(raw, "command");
  e.filePath = rbrules::get_str(raw, "file_path");
  e.sessionId = rbrules::get_str(raw, "session");
  e.toolUseId = rbrules::get_str(raw, "call");
  e.toolResponse = rbrules::get_str(raw, "output");
  e.prompt = rbrules::get_str(raw, "prompt");
  e.oldString = rbrules::get_str(raw, "old_string");
  e.newString = rbrules::get_str(raw, "new_string");
  e.content = rbrules::get_str(raw, "content");
  e.sawToolInput = !e.command.empty() || !e.filePath.empty();
  return e;
}

inline HookEvent parse(const string& raw) {
  switch (detect(raw)) {
    case DIALECT_CLAUDE:  return parse_claude(raw);
    case DIALECT_CURSOR:  return parse_cursor(raw);
    case DIALECT_GENERIC: return parse_generic(raw);
    default: { HookEvent e; e.raw = raw; return e; }
  }
}

inline const char* dialect_name(Dialect d) {
  switch (d) {
    case DIALECT_CLAUDE:  return "claude-code";
    case DIALECT_CURSOR:  return "cursor";
    case DIALECT_GENERIC: return "generic";
    default: return "unknown";
  }
}

} // namespace rbhook
