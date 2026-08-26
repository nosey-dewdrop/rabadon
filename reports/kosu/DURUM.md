# DURUM — koşu 5, F1a sonrası (2026-08-26)

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

## F1a'NIN DEĞİŞTİRDİĞİ ÖLÇÜMLER (yukarıdaki satırlar F0 ölçümüdür, bunlar günceldir)
- **Test:** `make test` **3462**/0, `npm test` **64**/0 → **3526 yeşil / 0 kırmızı**.
  (F0'da 3502'ydi; hiçbir test silinmedi, +24 eklendi.)
- **Disclosure:** `make disclosure` **exit 0**. `53 found / 12 allowed / 41 off-list`
  → `12 / 12 / 0`. Yol: liste dışı her ad `(withheld)`. `site/published-projects.txt`
  BYTE BYTE AYNI — operatör onayı olmadan tek isim eklenmedi.
- **CI:** `gh run view 32924786346` → altı job, **altısı yeşil**: 2 OS × 2 Node = 4 hücre
  (`ubuntu-latest`/`macos-15` × `node20`/`node22`) + `disclosure` 2 platform.
  Matris artık elle koşulmuyor. `pages build and deployment` hâlâ kırmızı — ölü yayın
  yolu, F1a öncesinde de kırmızıydı, kart açılmadı.
- **`doctor`:** dört sessiz kurulum ölümü artık adıyla yakalanıyor (Node sürümü, ikili
  izni, PATH çakışması, eski kurulum kalıntısı). `doctor_test.sh` 24 → **43** ok.
- **Yüzey:** ana help 5 ürün verb'ü, artık **kırmızı düşebilir** (`cli_test.sh` 310 → 315).
  `dev`in 30 verb'ü duruyor, hiçbiri silinmedi.
- **Kurulum adım sayısı, ÖLÇÜLDÜ:** **N = 5 birleşik satır / 7 komut**, ~35,8 s.
  "iki komut" iddiası yanlış, fark +3/+5.
- **ÖLÇÜMÜN AÇTIĞI DELİK:** `rabadon on` hiçbir kurulum belgesinde yok ama zorunlu.
  README'yi harfiyen izleyen kullanıcı WATCH modda kalır ve guard hiçbir şeyi reddetmez.
- **Cursor:** hâlâ 0 ledger satırı. Ek olarak `removeCursorHooks` YOK — Cursor
  kullanıcısının çıkış yolu yok (§4.9 ihlali, kart açılmadı, tutanakta yazılı).

## KIRMIZI AD KÜMESİ (§8.3 için dondurulmuş)
F0 ÖNCESİ: `{ 2b, 6e, 7b }` (R7 kabul). Test süitlerinde kırmızı ad yok.
F0 SONRASI: `reports/kosu/RAPOR/f0-tutanak.md` — büyümedi.
**F1a SONRASI: `{ 2b, 6e, 7b }` — BÜYÜMEDİ.** `bash reports/R7/accept.sh` → 23 yeşil /
3 kırmızı, aynı üç ad. (`2b` bu makinede 1244,2 µs, tavan 1000 µs.)
CI tarafında kırmızı **küçüldü**: `disclosure` iki platformda kırmızıdan yeşile döndü.

## DEVİR SAYILARI
| sayı | değer (F0) | değer (F1a) |
|---|---|---|
| kapanan faz | F0 | F1a (hakem hükmü bekliyor) |
| §5'te gerçek olan adım | yok (belgedeki tek istisna) | **ADIM 2 "kurar" — YARIM**: soru sorulmuyor doğru, "iki komut" yanlış (5/7) |
| kesilen kart | 4 | 5 |
| salınan işçi | 5 | 5 (tavan 5) |
| kırmızı ad kümesi | 3 → 3 | 3 → 3 (büyümedi) |
| test sayısı | 3502 | 3526 (düşmedi) |
| durma koşulu tetiklendi mi | hayır | hayır |

## SIRA
**F1 ikiye bölündü** (`SAPMA-KARARLARI.md`): **F1a bitti**, **F1n** operatörü bekliyor.
Yeni sıra: F1a → **F2** → F1b → F1n → F3.
**SIRADAKİ FAZ: F2 (`rabadon scan`).** Önkoşulu F2-S3'tü — "F1a'nın disclosure kartı
kapanmadan açılmaz" — ve o kart kapandı, `make disclosure` exit 0.
F1n (npm yayını) **UYKUDA KOŞMAZ** (§13): operatör kararı, `UYANDIGINDA.md`'de.
Sonraki şef bu dosyayı ve `ENVANTER.md`'yi okur; `KOSU-RABADON-5.md` §6'nın sayılarına
DEĞİL, ölçümlere güvenir. F1a'nın ölçümleri ENVANTER'in F0 sayılarını GÜNCELLER.
