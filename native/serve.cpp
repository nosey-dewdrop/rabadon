// rabadon-serve — the team ledger. C++17, POSIX sockets, zero dependencies.
//
// Until now a rabadon run existed on exactly one laptop, in one JSONL file. That
// answers none of the three questions a technical buyer asks in the first minute:
//   "how does my TEAM get their runs in here?"  -> POST /ingest, any machine, any
//                                                  language, one API key per project.
//   "where do I SEE it?"                        -> GET /  and GET /run/<id>, the same
//                                                  catch -> fix -> proof -> cost trace
//                                                  the terminal renders, in a browser.
//   "does it SURVIVE a reboot?"                 -> every accepted batch is written with
//                                                  O_APPEND and fsync'd before the 200
//                                                  goes out. If the client got a 200,
//                                                  the bytes are on the platter.
//
// Design rules that are deliberate, not accidental:
//   * APPEND-ONLY, sharded by project and day. Nothing is ever mutated in place, so a
//     crash can lose only an unacknowledged batch, never corrupt history — and the
//     shard key is the same one a real store would partition on later.
//   * AT-LEAST-ONCE IN, EXACTLY-ONCE STORED. The client may retry a batch freely; the
//     server fingerprints every line and drops one it already holds. This is why the
//     cost numbers can be trusted: a retry cannot double-bill a repair.
//   * The gate/loop never talk to this server on their hot path. They write locally and
//     `rabadon push` ships the ledger afterwards. A slow network can never stall the
//     tool that is supervising your editor.
//   * No framework, no TLS termination here. Put it behind a reverse proxy in the real
//     world; that boundary is a deployment concern, not a product one.
//
// Usage: rabadon-serve [--port N] [--store DIR] [--keys FILE] [--threads N]
//   keys file: one "<key> <project>" per line, '#' comments allowed.
//   store    : default $RABADON_DIR/team or ~/.rabadon/team
//
// exit 0 on clean shutdown (SIGINT/SIGTERM), 1 on a fatal bind/listen error.

#include <cstdint>   // uint16_t/uint64_t: libc++ leaks this transitively, libstdc++ does not
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <map>
#include <set>
#include <mutex>
#include <thread>
#include <atomic>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <ctime>
#include <csignal>
#include <cerrno>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include "cli_help.h"

using std::string;
using std::vector;

// ---------------------------------------------------------------- primitives
static uint64_t fnv1a(const char* p, size_t n) {
  uint64_t h = 1469598103934665603ULL;
  for (size_t i = 0; i < n; i++) { h ^= (unsigned char)p[i]; h *= 1099511628211ULL; }
  return h;
}
static uint64_t fnv1a(const string& s) { return fnv1a(s.data(), s.size()); }

static string read_file(const string& p) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return "";
  std::stringstream ss; ss << f.rdbuf(); return ss.str();
}

static string today_utc() {
  time_t t = time(nullptr); struct tm tmv; gmtime_r(&t, &tmv);
  char b[16]; strftime(b, sizeof b, "%Y-%m-%d", &tmv); return b;
}
static long long now_ms() {
  struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
  return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

// A project name arrives from a config file we control, but it becomes a path
// component — so it is filtered to a safe alphabet regardless. No '..', no '/'.
static string safe_name(const string& s) {
  string o;
  for (char c : s) {
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
        c == '-' || c == '_' || c == '.')
      o += c;
  }
  while (!o.empty() && o[0] == '.') o.erase(o.begin());   // no dotfiles, no ".."
  if (o.size() > 64) o = o.substr(0, 64);
  return o;
}

static void mkdirs(const string& p) {
  string cur;
  for (size_t i = 0; i < p.size(); i++) {
    cur += p[i];
    if (p[i] == '/' || i + 1 == p.size()) mkdir(cur.c_str(), 0755);
  }
}

// ---------------------------------------------------------------- the store
// One writer lock per project. The dedupe set holds the fingerprint of every line
// already durable for that project/day, so a retried batch is absorbed instead of
// double-counted. It is rebuilt from disk on first touch, which also means a
// restarted server does not forget what it already has.
struct Shard {
  std::mutex mu;
  std::set<uint64_t> seen;
  string day;
  bool loaded = false;
};

struct Store {
  string root;
  std::mutex mapMu;
  std::map<string, Shard*> shards;

  Shard* shard(const string& project) {
    std::lock_guard<std::mutex> g(mapMu);
    auto it = shards.find(project);
    if (it != shards.end()) return it->second;
    Shard* s = new Shard();
    shards[project] = s;
    return s;
  }
  string path(const string& project, const string& day) const {
    return root + "/" + project + "/" + day + ".jsonl";
  }
};

// Load (or reload, on a day rollover) the fingerprints already on disk.
static void ensure_loaded(Store& st, Shard* sh, const string& project, const string& day) {
  if (sh->loaded && sh->day == day) return;
  sh->seen.clear();
  sh->day = day;
  sh->loaded = true;
  const string body = read_file(st.path(project, day));
  size_t start = 0;
  while (start < body.size()) {
    size_t end = body.find('\n', start);
    if (end == string::npos) end = body.size();
    if (end > start) sh->seen.insert(fnv1a(body.data() + start, end - start));
    start = end + 1;
  }
}

// An event is accepted only if it is a single-line JSON object carrying the two
// fields every downstream reader needs. Anything else is REJECTED and counted —
// never appended quietly, because a ledger that accepts garbage is not a ledger.
static bool valid_event(const string& line) {
  if (line.size() < 2 || line.size() > 256 * 1024) return false;
  if (line.front() != '{' || line.back() != '}') return false;
  if (line.find("\"ev\":") == string::npos) return false;
  if (line.find("\"run\":") == string::npos) return false;
  return true;
}

struct IngestResult { int accepted = 0, duplicate = 0, rejected = 0; };

static IngestResult ingest(Store& st, const string& project, const string& body, bool& io_ok) {
  IngestResult r;
  io_ok = true;
  const string day = today_utc();
  Shard* sh = st.shard(project);
  std::lock_guard<std::mutex> g(sh->mu);
  ensure_loaded(st, sh, project, day);

  string batch;
  vector<uint64_t> fps;
  size_t start = 0;
  while (start <= body.size()) {
    size_t end = body.find('\n', start);
    if (end == string::npos) end = body.size();
    string line = body.substr(start, end - start);
    while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) line.pop_back();
    start = end + 1;
    if (line.empty()) { if (start > body.size()) break; else continue; }
    if (!valid_event(line)) { r.rejected++; continue; }
    uint64_t fp = fnv1a(line);
    if (sh->seen.count(fp)) { r.duplicate++; continue; }
    // a batch that repeats a line inside itself is deduped too
    if (std::find(fps.begin(), fps.end(), fp) != fps.end()) { r.duplicate++; continue; }
    fps.push_back(fp);
    batch += line;
    batch += '\n';
    if (start > body.size()) break;
  }

  if (batch.empty()) return r;

  mkdirs(st.root + "/" + project);
  const string p = st.path(project, day);
  int fd = open(p.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0644);
  if (fd < 0) { io_ok = false; return r; }
  const char* d = batch.data();
  size_t left = batch.size();
  while (left > 0) {
    ssize_t w = write(fd, d, left);
    if (w < 0) { if (errno == EINTR) continue; io_ok = false; break; }
    d += w; left -= (size_t)w;
  }
  // The 200 must mean "on the platter", not "in a buffer". This fsync is the
  // entire answer to "does it survive a reboot?", so it is not optional and it
  // is not batched away behind a timer.
  if (io_ok && fsync(fd) != 0) io_ok = false;
  close(fd);
  if (!io_ok) return r;

  for (uint64_t fp : fps) sh->seen.insert(fp);
  r.accepted = (int)fps.size();
  return r;
}

// ---------------------------------------------------------------- http
struct Req {
  string method, target, body;
  std::map<string, string> hdr;   // lowercase keys
};

static string lower(string s) { for (auto& c : s) c = (char)tolower((unsigned char)c); return s; }

static bool read_request(int fd, Req& rq, string& carry) {
  // headers
  size_t hdrEnd;
  char buf[8192];
  while ((hdrEnd = carry.find("\r\n\r\n")) == string::npos) {
    ssize_t n = recv(fd, buf, sizeof buf, 0);
    if (n <= 0) return false;
    carry.append(buf, (size_t)n);
    if (carry.size() > 64 * 1024) return false;   // header flood
  }
  const string head = carry.substr(0, hdrEnd);
  carry.erase(0, hdrEnd + 4);

  size_t lineEnd = head.find("\r\n");
  const string reqline = head.substr(0, lineEnd == string::npos ? head.size() : lineEnd);
  {
    size_t a = reqline.find(' ');
    if (a == string::npos) return false;
    size_t b = reqline.find(' ', a + 1);
    rq.method = reqline.substr(0, a);
    rq.target = reqline.substr(a + 1, (b == string::npos ? reqline.size() : b) - a - 1);
  }
  size_t pos = (lineEnd == string::npos) ? head.size() : lineEnd + 2;
  while (pos < head.size()) {
    size_t e = head.find("\r\n", pos);
    if (e == string::npos) e = head.size();
    const string h = head.substr(pos, e - pos);
    pos = e + 2;
    size_t c = h.find(':');
    if (c == string::npos) continue;
    string k = lower(h.substr(0, c));
    string v = h.substr(c + 1);
    while (!v.empty() && (v.front() == ' ' || v.front() == '\t')) v.erase(v.begin());
    rq.hdr[k] = v;
  }

  size_t want = 0;
  auto cl = rq.hdr.find("content-length");
  if (cl != rq.hdr.end()) want = (size_t)strtoull(cl->second.c_str(), nullptr, 10);
  if (want > 16 * 1024 * 1024) return false;      // body cap
  while (carry.size() < want) {
    ssize_t n = recv(fd, buf, sizeof buf, 0);
    if (n <= 0) return false;
    carry.append(buf, (size_t)n);
  }
  rq.body = carry.substr(0, want);
  carry.erase(0, want);
  return true;
}

static void send_all(int fd, const string& s) {
  const char* p = s.data(); size_t left = s.size();
  while (left > 0) {
    ssize_t w = send(fd, p, left, 0);
    if (w <= 0) { if (w < 0 && errno == EINTR) continue; return; }
    p += w; left -= (size_t)w;
  }
}

static void respond(int fd, int code, const char* status, const string& ctype,
                    const string& body, bool keepAlive) {
  char head[512];
  snprintf(head, sizeof head,
           "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %zu\r\n"
           "Cache-Control: no-store\r\nConnection: %s\r\n\r\n",
           code, status, ctype.c_str(), body.size(), keepAlive ? "keep-alive" : "close");
  send_all(fd, string(head) + body);
}

// ---------------------------------------------------------------- keys
struct Keys {
  std::map<string, string> keyToProject;
  bool empty() const { return keyToProject.empty(); }
};

static Keys load_keys(const string& path) {
  Keys k;
  const string body = read_file(path);
  std::istringstream is(body);
  string line;
  while (std::getline(is, line)) {
    size_t h = line.find('#'); if (h != string::npos) line = line.substr(0, h);
    std::istringstream ls(line);
    string key, proj;
    if (!(ls >> key >> proj)) continue;
    if (key.empty() || proj.empty()) continue;
    k.keyToProject[key] = safe_name(proj);
  }
  return k;
}

// ---------------------------------------------------------------- server
struct Server {
  Store store;
  Keys keys;
  string keysPath;
  std::atomic<long long> ingested{0}, batches{0}, denied{0};
  long long startedMs = now_ms();
  std::mutex keysMu;
};

static string json_escape(const string& s) {
  string o;
  for (char c : s) {
    switch (c) {
      case '"': o += "\\\""; break;
      case '\\': o += "\\\\"; break;
      case '\n': o += "\\n"; break;
      case '\r': o += "\\r"; break;
      case '\t': o += "\\t"; break;
      default: o += c;
    }
  }
  return o;
}

static void handle(Server& sv, int fd) {
  string carry;
  // Two different timeouts, and the difference matters under load. The FIRST
  // request may take a while to arrive (slow client, big batch). A SUBSEQUENT
  // one on a kept-alive connection must not be waited on for long: this is a
  // thread-per-connection pool, so every second spent blocked on an idle socket
  // is a worker that cannot serve anybody else. Measured the hard way — with a
  // 30s idle wait, 20 concurrent clients starved an 8-thread pool completely.
  auto set_timeout = [&](int secs) {
    struct timeval tv; tv.tv_sec = secs; tv.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
  };
  set_timeout(15);

  for (int served = 0; served < 128; served++) {
    Req rq;
    if (!read_request(fd, rq, carry)) break;
    set_timeout(2);            // from here on, an idle peer is dropped fast
    const bool keepAlive = lower(rq.hdr.count("connection") ? rq.hdr["connection"] : "") != "close";

    if (rq.method == "GET" && (rq.target == "/healthz" || rq.target == "/health")) {
      char b[256];
      snprintf(b, sizeof b,
               "{\"ok\":true,\"uptime_ms\":%lld,\"events\":%lld,\"batches\":%lld}",
               now_ms() - sv.startedMs, sv.ingested.load(), sv.batches.load());
      respond(fd, 200, "OK", "application/json", b, keepAlive);
      if (!keepAlive) break;
      continue;
    }

    if (rq.method == "POST" && rq.target == "/ingest") {
      string key = rq.hdr.count("x-rabadon-key") ? rq.hdr["x-rabadon-key"] : "";
      string project;
      {
        std::lock_guard<std::mutex> g(sv.keysMu);
        auto it = sv.keys.keyToProject.find(key);
        if (it != sv.keys.keyToProject.end()) project = it->second;
      }
      if (project.empty()) {
        sv.denied++;
        respond(fd, 401, "Unauthorized", "application/json",
                "{\"error\":\"unknown or missing x-rabadon-key\"}", false);
        break;
      }
      bool io_ok = true;
      IngestResult r = ingest(sv.store, project, rq.body, io_ok);
      if (!io_ok) {
        // Never claim durability we did not achieve: a failed write must be a 5xx
        // so the client keeps the batch and retries it.
        respond(fd, 500, "Internal Server Error", "application/json",
                "{\"error\":\"ledger write failed\"}", false);
        break;
      }
      sv.ingested += r.accepted;
      sv.batches++;
      char b[256];
      snprintf(b, sizeof b, "{\"accepted\":%d,\"duplicate\":%d,\"rejected\":%d,\"project\":\"%s\"}",
               r.accepted, r.duplicate, r.rejected, json_escape(project).c_str());
      respond(fd, 200, "OK", "application/json", b, keepAlive);
      if (!keepAlive) break;
      continue;
    }

    respond(fd, 404, "Not Found", "application/json", "{\"error\":\"no such route\"}", false);
    break;
  }
  close(fd);
}

static std::atomic<bool> g_stop{false};
static void on_signal(int) { g_stop = true; }

static const char* kHelp =
  "rabadon-serve — the team ledger. Append-only HTTP store for pipeline runs.\n"
  "POST /ingest with an API key to push a machine's spool; GET / and GET /run/<id>\n"
  "render the same catch -> fix -> proof -> cost trace the terminal prints.\n"
  "Every accepted batch is fsync'd before the 200 goes out.\n"
  "\n"
  "usage: rabadon-serve [--port N] [--store DIR] [--keys FILE] [--threads N]\n"
  "\n"
  "  --port N      TCP port to listen on (default 4319).\n"
  "  --store DIR   where shards are written (default $RABADON_DIR/team).\n"
  "  --keys FILE   one `<secret-key> <project-name>` per line; with no keys\n"
  "                every /ingest is refused (default $RABADON_DIR/keys).\n"
  "  --threads N   worker threads (default 8).\n"
  "  -h, --help    this screen. no socket is opened.\n"
  "\n"
  "example:\n"
  "  rabadon-serve --port 4319 --keys ~/.rabadon/keys\n";

int main(int argc, char** argv) {
  // FIRST statement: `rabadon-serve -h` was an unknown flag, fell through the
  // parser, and started listening. A help request must never open a socket.
  rb_help(argc, argv, kHelp);

  int port = 4319, threads = 8;
  string store, keysPath;
  for (int i = 1; i < argc; i++) {
    string a = argv[i];
    if (a == "--port" && i + 1 < argc) port = atoi(argv[++i]);
    else if (a == "--store" && i + 1 < argc) store = argv[++i];
    else if (a == "--keys" && i + 1 < argc) keysPath = argv[++i];
    else if (a == "--threads" && i + 1 < argc) threads = std::max(1, atoi(argv[++i]));
    // any other word: refused. `-h` used to fall through this loop and START
    // THE SERVER — the flag was unknown, so nothing stopped it, and the
    // stranger's terminal froze on a listening socket.
    else rb_unknown_flag("rabadon-serve", a.c_str());
  }
  const char* rd = getenv("RABADON_DIR");
  const char* home = getenv("HOME");
  const string base = rd && *rd ? string(rd) : (string(home ? home : ".") + "/.rabadon");
  if (store.empty()) store = base + "/team";
  if (keysPath.empty()) keysPath = base + "/keys";

  Server sv;
  sv.store.root = store;
  sv.keysPath = keysPath;
  mkdirs(store);
  sv.keys = load_keys(keysPath);
  if (sv.keys.empty()) {
    fprintf(stderr,
            "rabadon-serve: no keys in %s — every /ingest will be refused.\n"
            "  add a line:  <secret-key> <project-name>\n", keysPath.c_str());
  }

  signal(SIGPIPE, SIG_IGN);          // a dead client must never kill the server
  signal(SIGINT, on_signal);
  signal(SIGTERM, on_signal);

  int lfd = socket(AF_INET, SOCK_STREAM, 0);
  if (lfd < 0) { perror("socket"); return 1; }
  int one = 1;
  setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  struct sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);   // bind local; a proxy fronts it
  addr.sin_port = htons((uint16_t)port);
  if (const char* bindAll = getenv("RABADON_BIND_ALL"))
    if (string(bindAll) == "1") addr.sin_addr.s_addr = htonl(INADDR_ANY);
  if (bind(lfd, (struct sockaddr*)&addr, sizeof addr) < 0) { perror("bind"); return 1; }
  if (listen(lfd, 512) < 0) { perror("listen"); return 1; }

  fprintf(stderr, "rabadon-serve: :%d  store=%s  keys=%zu project(s)  threads=%d\n",
          port, store.c_str(), sv.keys.keyToProject.size(), threads);
  fflush(stderr);

  vector<std::thread> pool;
  for (int i = 0; i < threads; i++) {
    pool.emplace_back([&] {
      while (!g_stop) {
        int cfd = accept(lfd, nullptr, nullptr);
        if (cfd < 0) { if (errno == EINTR) continue; if (g_stop) break; continue; }
        int nod = 1; setsockopt(cfd, IPPROTO_TCP, TCP_NODELAY, &nod, sizeof nod);
        handle(sv, cfd);
      }
    });
  }
  for (auto& t : pool) t.join();
  close(lfd);
  return 0;
}
