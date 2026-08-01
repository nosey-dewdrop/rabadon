// rabadon-export — the ledger as OpenTelemetry, so any backend can render it
// (C++17, zero deps).
//
// rabadon's spool is honest but private. This binary speaks the standard:
// OTLP/JSON traces following the OpenTelemetry GenAI semantic conventions, so
// a rabadon session drops straight into Jaeger, Grafana Tempo, Honeycomb, or
// Langfuse's OTLP endpoint — no rabadon-specific viewer required. Observation
// is a solved, standardized problem; rabadon's edge is enforcement, so here it
// EXPORTS instead of reinventing a dashboard.
//
// Mapping:
//   - one TRACE per session pipe (traceId = 128-bit hash of the pipe name);
//   - one SPAN per meaningful event (STEP_START / CHECK_FAIL / STOP /
//     WOULD_BLOCK / REPAIR_OK / REPAIR_FAIL), spanId = 64-bit hash of run+seq+ts;
//   - a catch/refusal sets span status = ERROR with the rule as the message —
//     so a refused action is red in any trace viewer, which is exactly why the
//     drill rules here (drill.h, shared with rabadon-stats) have to be the same
//     four the local number uses: this is the surface strangers read;
//   - attributes: rabadon.ev, rabadon.rule, rabadon.detail, and the GenAI
//     conventions gen_ai.system / gen_ai.usage.* where token counts exist.
//
//   rabadon export --otlp [--days N]   -> OTLP/JSON on stdout
//   POST it:  rabadon export --otlp | curl -s localhost:4318/v1/traces \
//               -H 'content-type: application/json' --data-binary @-

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <dirent.h>
#include <pwd.h>
#include <sys/stat.h>
#include <unistd.h>
#include "cli_help.h"
#include "drill.h"

using std::string;
using std::vector;

static double now_ms() {
  const char* t = getenv("RABADON_NOW");
  if (t && t[0]) { double v = strtod(t, nullptr); if (v > 0) return v; }
  struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
  long long ms = (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
  return (double)ms;
}

static string read_file(const string& p) {
  struct stat st;
  if (stat(p.c_str(), &st) != 0 || !S_ISREG(st.st_mode)) return string();
  std::ifstream f(p, std::ios::binary);
  if (!f) return string();
  std::ostringstream ss; ss << f.rdbuf();
  return ss.str();
}

static string get_field(const string& line, const string& key) {
  string pat = "\"" + key + "\":\"";
  size_t k = line.find(pat);
  if (k == string::npos) return "";
  size_t i = k + pat.size();
  string out;
  while (i < line.size()) {
    char c = line[i];
    if (c == '\\' && i + 1 < line.size()) {
      char e = line[i + 1];
      if (e == 'n') out += '\n'; else if (e == 't') out += '\t'; else if (e == 'r') out += '\r'; else out += e;
      i += 2; continue;
    }
    if (c == '"') return out;
    out += c; i++;
  }
  return "";
}

static double get_num(const string& line, const string& key) {
  string pat = "\"" + key + "\":";
  size_t k = line.find(pat);
  if (k == string::npos) return 0;
  return strtod(line.c_str() + k + pat.size(), nullptr);
}

// FNV-1a 64-bit; two of them (salted) make a stable 128-bit trace id
static uint64_t fnv(const string& s, uint64_t seed) {
  uint64_t h = seed;
  for (unsigned char c : s) { h ^= c; h *= 1099511628211ULL; }
  return h;
}
static string hex64(uint64_t v) { char b[17]; snprintf(b, sizeof b, "%016llx", (unsigned long long)v); return b; }
static string trace_id(const string& pipe) { return hex64(fnv(pipe, 1469598103934665603ULL)) + hex64(fnv(pipe, 1099511628211ULL)); }
static string span_id(const string& s) { return hex64(fnv(s, 0xcbf29ce484222325ULL)); }

static string jesc(const string& s) {
  string o;
  for (unsigned char c : s) {
    switch (c) {
      case '"': o += "\\\""; break;
      case '\\': o += "\\\\"; break;
      case '\n': o += "\\n"; break;
      case '\r': o += "\\r"; break;
      case '\t': o += "\\t"; break;
      default: if (c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); o += b; } else o += (char)c;
    }
  }
  return o;
}
static string nanos(double ms) { char b[32]; snprintf(b, sizeof b, "%.0f", ms * 1e6); return b; }
static string attr_str(const string& k, const string& v) { return "{\"key\":\"" + k + "\",\"value\":{\"stringValue\":\"" + jesc(v) + "\"}}"; }
static string attr_int(const string& k, long long v) { return "{\"key\":\"" + k + "\",\"value\":{\"intValue\":\"" + std::to_string(v) + "\"}}"; }

struct Ev { double ts, seq; string pipe, run, ev, rule, detail; long long tin = 0, tout = 0; };

static const char* kHelp =
  "rabadon-export — the ledger in OTLP/JSON on stdout, GenAI semantic conventions.\n"
  "Reads the local spool and emits spans any OpenTelemetry collector accepts, so\n"
  "rabadon runs land next to the rest of your traces. Drills never leave the\n"
  "machine, by the same four rules `rabadon usage` excludes them with: the emit\n"
  "tag, a fleet/doctor/drill session id, rabadon's own bench and demo pipes, and\n"
  "events inside a drill's 2-minute window. The count you read here and the count\n"
  "you read locally are the same count.\n"
  "\n"
  "usage: rabadon-export --otlp [--days N]\n"
  "\n"
  "  --otlp      emit OTLP/JSON. required — it is the only format today.\n"
  "  --days N    how far back to read (default 7).\n"
  "  -h, --help  this screen.\n"
  "\n"
  "environment:\n"
  "  RABADON_DIR   where the spool lives (default ~/.rabadon).\n"
  "\n"
  "example:\n"
  "  rabadon-export --otlp --days 1 | curl -s -X POST -H 'content-type: application/json' \\\n"
  "      --data-binary @- http://localhost:4318/v1/traces\n";

int main(int argc, char** argv) {
  rb_help(argc, argv, kHelp);

  double days = 7;
  bool otlp = false;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--days") == 0 && i + 1 < argc) { double v = strtod(argv[++i], nullptr); if (v > 0) days = v; }
    else if (strcmp(argv[i], "--otlp") == 0) otlp = true;
    // an unrecognised word used to be ignored, so `-h` fell through to the
    // format check and came back "pass --otlp" with exit 2.
    else rb_unknown_flag("rabadon-export", argv[i]);
  }
  if (!otlp) { fprintf(stderr, "rabadon export: pass --otlp (the only format today)\n  run `rabadon-export --help`\n"); return 2; }

  string rdir;
  const char* rd = getenv("RABADON_DIR");
  if (rd && rd[0]) rdir = rd;
  else { const char* h = getenv("HOME"); string home = (h && h[0]) ? h : "."; rdir = home + "/.rabadon"; }
  string spool = rdir + "/spool";
  const double cutoff = now_ms() - days * 86400000.0;

  vector<string> files;
  if (DIR* d = opendir(spool.c_str())) {
    while (struct dirent* ent = readdir(d)) { string n = ent->d_name; if (n.size() >= 6 && n.compare(n.size() - 6, 6, ".jsonl") == 0) files.push_back(n); }
    closedir(d);
  }
  std::sort(files.begin(), files.end());

  // Two passes over the same window. The first classifies EVERY in-window line
  // with the shared drill rules (drill.h) — every line, because rule 4 reads a
  // marker off events this exporter would never have shipped, and a drill's
  // fallout must not look like ordinary traffic just because the marker was a
  // heartbeat. The second keeps the exportable, non-drill ones.
  vector<RbDrillEv> classify;   // one per in-window line
  vector<Ev> parsed;            // the exportable payload, same indexing
  vector<char> exportable;
  for (const string& f : files) {
    string body = read_file(spool + "/" + f);
    size_t pos = 0;
    while (pos < body.size()) {
      size_t nl = body.find('\n', pos);
      string line = body.substr(pos, (nl == string::npos ? body.size() : nl) - pos);
      pos = (nl == string::npos) ? body.size() : nl + 1;
      if (line.empty()) continue;
      double ts = get_num(line, "ts");
      if (!(ts >= cutoff)) continue;
      Ev e; e.ts = ts; e.seq = get_num(line, "seq");
      e.pipe = get_field(line, "pipe"); e.run = get_field(line, "run"); e.ev = get_field(line, "ev");
      e.rule = get_field(line, "rule"); e.detail = get_field(line, "detail");
      e.tin = (long long)get_num(line, "tokensIn"); e.tout = (long long)get_num(line, "tokensOut");
      RbDrillEv c;
      c.has_pipe = line.find("\"pipe\":\"") != string::npos;
      c.pipe = e.pipe; c.ts = ts;
      c.tag = rb_drill_tag(line);
      c.marker = rb_drill_marker(line);
      static const char* kept[] = {"STEP_START", "CHECK_FAIL", "STOP", "WOULD_BLOCK", "REPAIR_OK", "REPAIR_FAIL", "RUN_START", "RUN_DONE"};
      bool k = false; for (const char* w : kept) if (e.ev == w) k = true;
      classify.push_back(std::move(c));
      parsed.push_back(std::move(e));
      exportable.push_back(k ? 1 : 0);
    }
  }

  // drills never leave the machine — all four rules, the same ones `rabadon
  // usage` counts with, so the two surfaces cannot tell different stories.
  vector<char> isDrill = rb_mark_drills(classify);
  vector<Ev> events;
  for (size_t i = 0; i < parsed.size(); i++) {
    if (!exportable[i] || isDrill[i]) continue;
    events.push_back(std::move(parsed[i]));
  }
  std::stable_sort(events.begin(), events.end(), [](const Ev& a, const Ev& b) { return a.ts != b.ts ? a.ts < b.ts : a.seq < b.seq; });

  // group spans by pipe (= trace)
  string spansJoined;
  string curPipe; bool firstPipe = true;
  string out = "{\"resourceSpans\":[{\"resource\":{\"attributes\":[" + attr_str("service.name", "rabadon") + "," + attr_str("telemetry.sdk.name", "rabadon-export") + "]},\"scopeSpans\":[{\"scope\":{\"name\":\"rabadon\"},\"spans\":[";
  bool firstSpan = true;
  for (const Ev& e : events) {
    string tid = trace_id(e.pipe.empty() ? "?" : e.pipe);
    string sid = span_id(e.run + ":" + std::to_string((long long)e.seq) + ":" + std::to_string((long long)e.ts));
    bool isCatch = (e.ev == "STOP" || e.ev == "CHECK_FAIL" || e.ev == "WOULD_BLOCK" || e.ev == "REPAIR_FAIL");
    string name = e.ev;
    if (!e.rule.empty()) name += ":" + e.rule;
    string attrs = attr_str("rabadon.ev", e.ev);
    if (!e.rule.empty()) attrs += "," + attr_str("rabadon.rule", e.rule);
    if (!e.detail.empty()) attrs += "," + attr_str("rabadon.detail", e.detail);
    attrs += "," + attr_str("rabadon.pipe", e.pipe);
    if (e.tin > 0 || e.tout > 0) {
      attrs += "," + attr_str("gen_ai.system", "anthropic");
      if (e.tin > 0) attrs += "," + attr_int("gen_ai.usage.input_tokens", e.tin);
      if (e.tout > 0) attrs += "," + attr_int("gen_ai.usage.output_tokens", e.tout);
    }
    // point-in-time event: start == end (trace viewers render a marker)
    string span = string("{\"traceId\":\"") + tid + "\",\"spanId\":\"" + sid +
      "\",\"name\":\"" + jesc(name) + "\",\"kind\":1,\"startTimeUnixNano\":\"" + nanos(e.ts) +
      "\",\"endTimeUnixNano\":\"" + nanos(e.ts) + "\",\"attributes\":[" + attrs + "]" +
      (isCatch ? ",\"status\":{\"code\":2,\"message\":\"" + jesc(e.rule.empty() ? e.ev : e.rule) + "\"}" : "") + "}";
    if (!firstSpan) out += ",";
    out += span; firstSpan = false;
    (void)curPipe; (void)firstPipe;
  }
  out += "]}]}]}\n";
  fwrite(out.data(), 1, out.size(), stdout);
  return 0;
}
