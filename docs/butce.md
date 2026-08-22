# butce.md — what the move record costs, and what it is allowed to cost

Every number here is measured on this repo's own machine and is reproducible with
the command printed beside it. Nothing in this file is a target; they are
observations, and where an observation is bad it says so.

## The shape

The move record is an append-only log, one file per session:

    <project>/.rabadon/sessions/<key>.moves.jsonl

One line per move. A completion — PostToolUse learning the exit claim, the error
signature, the suite verdict — is **another line with the same `seq`**, never an
edit of the line already on disk. The reader lets the later line win. Append-only
means append-only; a log you edit in place is a file with extra steps and a
torn-write window.

## Why it is a log and not an object

R1 stored the moves inside the session JSON. Recording one 200-byte fact meant
serialising the whole object and replacing the file through a temp and a rename.
At 200 moves that is roughly 60 KB of write per tool event, and it measured:

| arm | median |
|---|---|
| recording off | 4.636 ms |
| recording on (R1 storage) | 6.207 ms |
| **cost** | **+1571 µs** |

The between-rounds gate allows 300 µs. R1.1 tried dirty-tracking the write and
bought nothing (5.674 → 5.784 ms) because the measured path only wrote once
anyway. R1.2 changed the storage instead.

    reports/R1.2/accept.sh   # goal 4 measures this, 3 runs per arm, median

## The caps, and who enforces them

    CAP      = 200 moves     the newest, by seq
    RAW_KEEP = 50            moves that carry their raw text
    RAW_CLIP = 200 chars     per move

**The reader enforces them, not the file.** Any reader — the gate, R2's
detectors, a test — is handed the newest 200 moves with raw text on the newest
50. Between compactions the file on disk may hold more lines than that, and that
is exactly what makes an append cheap: nothing has to be rewritten to keep the
record bounded.

`seq` never resets. It is the only field that can still order two moves after
eviction has thrown the older one away.

## Yok artık: sıkıştırma

R1.3 kaydı **sabit genişlikli ikili bir halkaya** taşıdı: 200 kayıt × 320 bayt, 4096 baytlık
bir başlığın arkasında. Dosya sabit boyutlu (4096 + 64.000 = 68.096 bayt) ve oturum ne kadar
uzarsa uzasın büyümüyor. Sıkıştırılacak bir şey yok, o yüzden sıkıştırma da yok.

Neden metin bırakıldı: üç tur boyunca üç ayrı yeri ucuzlattık (tam-dosya yazımı → append,
çift yazım → tek, N hash → 1 hash) ve ölçüm her seferinde aynı şeyi söyledi — 200 satırlık
günlük 5.943 ms, 400 satırlık 6.647 ms. Maliyet optimize edilen yerlerde değil, **her olayda
tüm tarihçeye dokunmakta**ydı, ve dokunmayı pahalı yapan şey metindi. Artık yükleme, bilinen
boyutta tek bir `pread` ve ardından `memcpy`: tarama yok, alan arama yok, alan başına
ayırma yok.

**Atomiklik başlık `count`'udur.** Kayıt önce yazılır, `count` sonra artırılır. Elektrik
yarıda giderse yarım kayıt `count`'un dışında kalır — yani hiç var olmamıştır. Yarım kayıt
ayrıştırma sorunu diye bir şey yok, çünkü ayrıştırma yok.

**Metin bir dışa aktarımdır, depolama biçimi değil.** `rabadon audit --export <ring>` insan
ve test için JSONL üretir. Hot-path hiçbir zaman JSON üretmez.

## Durability: no fsync, on purpose

`append_move()` writes the record, then the header, and closes. **It does not fsync.**

The reasoning, stated so it can be argued with:

- fsync on every tool event would hand back the millisecond this round exists to
  remove. The gate runs on every action a developer's agent takes; a supervisor
  that is felt is a supervisor that is uninstalled.
- What is at risk is a **diagnostic record**, not the user's source and not the
  chained ledger. `~/.rabadon/spool/` — the thing `rabadon audit` verifies and the
  thing the counter will be derived from — is unchanged by this round and keeps
  its own durability behaviour.
- The honest cost is real: a crash or a power loss can lose the tail of the log.

So the tail is not *assumed* intact, it is *checked*. Every line carries `prev`,
the first 16 hex of the SHA-256 of the line before it. On load:

- a line whose `prev` does not match the previous line's hash means a line is
  **missing or was edited** — the record has a known hole rather than a quiet lie.
  Under `RABADON_MOVES_STRICT=1` the gate says so on stderr; otherwise it carries
  the hole forward silently, because a broken diagnostic record is not a reason to
  refuse the user's command.
- a half-written final line (no closing `}`) is **dropped**, not fatal. A torn
  record must never stop the gate from judging the next command.

That is the trade in one sentence: rabadon does not promise the move record
survives a crash; it promises it will never tell you something that did not
happen.
