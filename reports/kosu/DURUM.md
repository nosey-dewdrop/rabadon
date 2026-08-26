# DURUM — koşu 5, F0 sonrası (2026-08-26)

Koşunun kısa ve KANITLI durumu. Her satır bir ölçümden okundu.
Ayrıntı ve komutlar: `reports/kosu/ENVANTER.md`.
Koşu 3'ün DURUM'u `reports/kosu/arsiv/DURUM-kosu3.md`'de, iptal notuyla duruyor.

## KÖK VE DAL
- **Tek kök: `/Users/damummyphus/damla_projects_2026/rabadon`. Tek dal: `main`.**
- Bu koşuda çalışılacak dizin budur. Worktree açılmaz, yeni dal açılmaz.
- `main` = eski `kosu4` ucu `ad26ff9` (ileri sarma, `git merge --ff-only kosu4`, 111 commit).
- `kosu2` / `kosu3` / `kosu4` worktree'leri kaldırıldı; **dallar silinmedi**,
  `origin`'de duruyorlar.

## KOŞU BELGESİ
Kökte tek koşu belgesi: **`KOSU-RABADON-5.md`**.
`KOSU-RABADON.md`, `-2`, `-3`, `-4` → `docs/archive/`, her birinin başında tek satır
iptal notu. Silinmedi. `PROJECT.md` artık koşu 5'i gösteriyor.

## ÖLÇÜLEN GERÇEK (belgeye değil buna bak)
- **Sinyal:** kodda 8 sinyal adı; **4'ü enjekte ediyor** (`oscillation`, `root_migration`,
  `green_redefined`(b), `semantic_repeat`), 4'ü yalnız ledger'a yazıyor
  (`repeat`, `scope_drift`, `green_redefined`(a) ve (c)). Çağrılmayan sinyal yok.
- **Ajan yüzeyi:** ledger kanıtı yalnız **Claude Code**'da (6 INJECT, 1 INJECT_HELD,
  2224 SIGNAL, 368 COUNTER; 22–26 Ağu; `~/.rabadon/spool/`). Kanıtın çoğu **başka bir
  repodan** (`stitchu`) ve **23 Ağu tarihli bir ikiliden** geliyor. Cursor: 0 satır.
- **Enjeksiyonun (b) "ajan okudu" ve (c) "zarar vermedi" katmanları için HİÇ kanıt yok.**
- **Test:** `make test` 3438/0, `npm test` 64/0 → **3502 yeşil / 0 kırmızı**.
- **Kabul:** `reports/R7/accept.sh` → **23 yeşil / 3 kırmızı**, adlar **`2b`, `6e`, `7b`**.
- **CLI:** ana help 5 verb, `dev` 30, dispatcher 44. (Belgedeki "25 verb" hiçbir ölçümle eşleşmiyor.)
- **npm:** `rabadon` E404. `package.json` 0.2.3. `v0.2.3` etiketi yok.
- **Landing:** eski ürünü satıyor — başlık "guardrails and a verifiable record",
  kurulum `git clone && make`, komutlar `watch/on/usage/repair/audit`.
  "compound error" ve "injection" sayfada **0 kez** geçiyor.
- **Kapı bugün:** `~/.claude/settings.json` kök klonun `native/rabadon-gate` ikilisini
  çağırıyor, mod **watch (observe)**, deny değil. Öyle bırakıldı.

## KIRMIZI AD KÜMESİ (§8.3 için dondurulmuş)
F0 ÖNCESİ: `{ 2b, 6e, 7b }` (R7 kabul). Test süitlerinde kırmızı ad yok.
F0 SONRASI: `reports/kosu/RAPOR/f0-tutanak.md` — büyümedi.

## DEVİR SAYILARI
| sayı | değer |
|---|---|
| kapanan faz | F0 |
| §5'te gerçek olan adım | yok (F0'ın ADIM satırı yok, belgede yazılı tek istisna) |
| kesilen kart | 4 (envanter, tek kök tek dal, tek koşu belgesi, ortam) |
| salınan işçi | 5 |
| kırmızı ad kümesi | 3 → 3 (büyümedi) |
| ortam ön kontrol | 8/8 YEŞİL (`scripts/onkontrol.sh`) |
| durma koşulu tetiklendi mi | hayır |

## SIRA
**F1 — kurulabilen ürün.** Önkoşul: yok, F0 kapandı.
F1'in npm yayını **UYKUDA KOŞMAZ** (§13): operatör kararı, `UYANDIGINDA.md`'ye düşer.
F1 şefi bu dosyayı ve `ENVANTER.md`'yi okur; `KOSU-RABADON-5.md` §6'nın sayılarına
DEĞİL, `ENVANTER.md`'nin ölçümlerine güvenir.
