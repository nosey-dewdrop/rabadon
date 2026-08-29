// day_cache_probe.cpp — the harness for native/day_cache_test.sh.
//
// It links the REAL gate the way rabadon-gated does (gate.cpp with main()
// renamed), so what it measures is the shipped function, not a copy of it. The
// probe itself asserts nothing: it prints numbers and strings, and the shell
// test decides. Keeping the verdict out of C++ is deliberate — a probe that
// judged itself could be made to pass by editing the probe.
#define main rb_gate_main
#include "gate.cpp"
#undef main

#include <sys/wait.h>

static long long micros() {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (long long)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

// what the line at gate.cpp:2754 did before the cache: the whole computation,
// every time. This is the reference answer the cache must reproduce EXACTLY.
static void uncached(time_t t, char out[16]) {
  struct tm tmv;
  gmtime_r(&t, &tmv);
  strftime(out, 16, "%Y-%m-%d", &tmv);
}

int main() {
  char a[16], b[16];

  // 0) COLD FIRST CALL — and it has to be first, before anything below warms
  // anything. This is the number the SHIPPED gate actually pays. rabadon-gate
  // is one process per hook event: it never gets a second call, so a cache
  // "for the process" saves it nothing and the cold path is the ONLY path it
  // ever walks. The existing arms below measure a repeat call and a forked
  // child, which are the daemon's shape; neither of them is the shape a user's
  // hook has. Measured 2026-08-29 with gmtime_r+strftime here: ~300 us on every
  // single event, ~18% of the whole end-to-end 1641 us the R7 `2b` ceiling is
  // about.
  {
    const long long z0 = micros();
    rb_day_str_at(1700000000, a);
    printf("COLD_FIRST_US %lld %s\n", micros() - z0, a);
  }

  // 1) AGREEMENT. Every timestamp the cache is asked about must come back with
  // the string the uncached computation would have produced. The list walks
  // forward in one-hour steps for 200 days from a fixed epoch and includes the
  // seconds either side of midnight, a leap day, and a year boundary — the
  // three places a "it is the same all day" cache goes stale.
  long long checked = 0, mismatch = 0;
  const time_t start = 1700000000;  // 2023-11-14T22:13:20Z
  for (long long i = 0; i < 200 * 24; i++) {
    const time_t t = start + i * 3600;
    rb_day_str_at(t, a);
    uncached(t, b);
    checked++;
    if (strcmp(a, b) != 0) {
      mismatch++;
      if (mismatch <= 3) printf("MISMATCH %lld cached=%s uncached=%s\n", (long long)t, a, b);
    }
  }
  const time_t edges[] = {
      0,           // the epoch itself
      86399,       // 1970-01-01T23:59:59Z
      86400,       // 1970-01-02T00:00:00Z
      1709164799,  // 2024-02-28T23:59:59Z, the second before a leap day
      1709164800,  // 2024-02-29T00:00:00Z
      1709251200,  // 2024-03-01T00:00:00Z
      1735689599,  // 2024-12-31T23:59:59Z
      1735689600,  // 2025-01-01T00:00:00Z
  };
  for (size_t i = 0; i < sizeof edges / sizeof *edges; i++) {
    rb_day_str_at(edges[i], a);
    uncached(edges[i], b);
    checked++;
    if (strcmp(a, b) != 0) {
      mismatch++;
      printf("MISMATCH-EDGE %lld cached=%s uncached=%s\n", (long long)edges[i], a, b);
    }
  }
  // A WIDE sweep as well, one call per day from the epoch to 2134, still
  // against gmtime_r+strftime. The 200-day walk above is enough to catch a
  // stale cache; it is NOT enough to catch a calendar computed some other way
  // getting a century leap year wrong (1900, 2100) or drifting after a few
  // decades. If this file ever stops calling gmtime_r on the cold path, this
  // is the arm that says the replacement means the same thing.
  for (long long d = 0; d < 60000; d++) {
    const time_t t = d * 86400 + 43200;
    rb_day_str_at(t, a);
    uncached(t, b);
    checked++;
    if (strcmp(a, b) != 0) {
      mismatch++;
      if (mismatch <= 6) printf("MISMATCH-WIDE %lld cached=%s uncached=%s\n", (long long)t, a, b);
    }
  }

  // and the boundary walked backwards as well: a cache keyed on "have I been
  // asked before" rather than on WHICH day would pass the forward walk above
  // and fail here.
  rb_day_str_at(1735689600, a);
  rb_day_str_at(1735689599, b);
  printf("BOUNDARY %s %s\n", b, a);
  printf("AGREE %lld %lld\n", checked, mismatch);

  // 2) TODAY. The live entry point, the one the gate actually calls, must
  // answer with today's UTC date. `date -u +%F` in the shell test is the
  // independent witness.
  rb_day_str(a);
  printf("TODAY %s\n", a);

  // 3) REPEAT COST. Same-day calls after the first must not re-enter the
  // timezone machinery. Measured as total microseconds for 100k calls; the
  // uncached line was 269-483 us for the FIRST call alone.
  const long long t0 = micros();
  for (int i = 0; i < 100000; i++) rb_day_str(a);
  printf("REPEAT_US_100K %lld\n", micros() - t0);

  // 4) THE POINT OF ALL THIS: a forked child inherits the warm cache. This is
  // the daemon's shape — rabadon-gated warms it once, then forks a worker per
  // request — and it is the only reason the 28.5% goes away. Measured in the
  // CHILD, which is where the cost used to land.
  fflush(stdout);
  const pid_t pid = fork();
  if (pid == 0) {
    const long long c0 = micros();
    rb_day_str(a);
    printf("CHILD_FIRST_US %lld %s\n", micros() - c0, a);
    fflush(stdout);
    _exit(0);
  }
  int st = 0;
  waitpid(pid, &st, 0);
  return 0;
}
