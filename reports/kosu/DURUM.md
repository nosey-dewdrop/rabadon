# DURUM — koşu 5, F1c sonrası (2026-08-26)

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

## F1c'NİN DEĞİŞTİRDİĞİ ÖLÇÜMLER (bunlar EN GÜNCEL satırlardır)
Tam tutanak: `reports/kosu/RAPOR/f1c-tutanak.md`. Faz aralığı `3df7af3..HEAD`.
- **KANIT YEDEĞİ ALINDI (kart 0).** Replay korpusu repo DIŞINDA, salt-okunur:
  `~/.rabadon-korpus-snapshot-20260826/`. Kaynak = kopya: **34 oturum, 527 kayıt**,
  22–26 Ağu. **Ama 139 hamle yedekten ÖNCE kaybolmuştu** (başlık `count` toplamı
  666, diskte 527; dolu ring `CAP=200`). **Ve dolu ring koşan oturumun kendisi —
  her koşu korpusun en eski ucunu yiyor.** F2 bunu bilerek planlamalı.
- **F1a'nın açtığı delik KAPANDI:** `rabadon on` artık `README.md`, `docs/quickstart.md`
  ve `site/index.html`'in KURULUM BLOĞUNUN İÇİNDE, ve **kırmızı düşebilen bir testle
  kilitli** (`native/install_docs_test.sh`, 20/0). Boş yeşil turu üç belge için de
  kırmızı→yeşil gösterdi (`f1c-1-bosyesil.out`).
- **Kurulum adım sayısı, YENİDEN ÖLÇÜLDÜ:** **3 birleşik satır / 7 komut / 34,1 s /
  0 soru**, ve yolun sonunda gerçek `rabadon-gate` bir PreToolUse olayına **`exit 2`**
  veriyor. **Eski 5 sayısı silinmedi** — F1a'nın 5'i belgedeki satırları saydı ve
  WATCH'a varıyordu; F1c'nin 3'ü çalışır frene varan asgari yol. **2 kovalanmadı**,
  o F1n-S1'in kabul maddesi.
- **`init` ekranı artık modu ve TEK sıradaki komutu söylüyor** (§4.8):
  `right now: WATCH — every action is recorded and nothing is refused.` +
  neden (`watch is the default … enforcing is your call, not ours`) +
  `next: rabadon on`. Varsayılan **WATCH kaldı**, `init` `on`'a katlanmadı.
  Verbatim ekran: `f1c-2-init-ekrani.out`.
- **Cursor'ın ÇIKIŞ YOLU AÇILDI (§4.9):** `removeCursorHooks` yok idi, şimdi var
  (`grep -rn "removeCursorHooks" hooks/` BOŞ → 4 satır). `remove` `.cursor/hooks.json`'daki
  rabadon girdilerini söküyor, kullanıcının kendi hook'larına dokunmuyor, yalnız-rabadon
  dosyasını siliyor. `native/exit_path_test.sh` (22/0) pinliyor. **Yeni verb eklenmedi.**
- **Test:** `make test` **3490**/0 (F1a'da 3448, +42), 56 süit, exit 0. `npm test` 64/0.
  `make disclosure` exit 0. Mevcut hiçbir test/fixture/eşik değişmedi, hiçbir dosya silinmedi.
- **Cursor hâlâ 0 ledger satırı** ve **ledger'da ajanı ayırt eden alan HÂLÂ YOK** —
  yani Cursor ateşlese bile atfedilemezdi. `docs/agent-contract.md` bunu artık tabloda yazıyor.
- **AÇILMAMIŞ ve AÇILMASI GEREKEN KART:** `installCursorHooks` okunamayan bir
  `hooks.json`'ı **yedeksiz üstüne yazıyor**; `.claude` tarafında aynı durum
  `process.exit(1)` ile reddediliyor. İki yüzey, iki farklı yasa.
- **BELGE ÇELİŞKİSİ (kart dışı):** README "npm'de değil, kaynaktan kur" derken
  `docs/quickstart.md` `## 1. Install` `npm i -g rabadon` diyor — bugün ölü bir komut. F1n.
- **DÜZELTME:** işçi 2'nin "`cli_test.sh` beş-yüzey yasasını tutmuyor" notu YANLIŞTIR.
  `native/cli_test.sh:271,282,299` tavanı açıkça tutuyor; F1a hakemi altıncı verb'ü
  enjekte edip 315/0 → 312/3 kırmızısını görmüştü. **Yüzey tavanı KİLİTLİDİR.**

## KIRMIZI AD KÜMESİ (§8.3 için dondurulmuş)
F0 ÖNCESİ: `{ 2b, 6e, 7b }` (R7 kabul). Test süitlerinde kırmızı ad yok.
F0 SONRASI: `reports/kosu/RAPOR/f0-tutanak.md` — büyümedi.
**F1a SONRASI: `{ 2b, 6e, 7b }` — BÜYÜMEDİ.** `bash reports/R7/accept.sh` → 23 yeşil /
3 kırmızı, aynı üç ad. (`2b` bu makinede 1244,2 µs, tavan 1000 µs.)
CI tarafında kırmızı **küçüldü**: `disclosure` iki platformda kırmızıdan yeşile döndü.
**F1c SONRASI: `{ 2b, 6e, 7b }` — BÜYÜMEDİ.** `bash reports/R7/accept.sh` → exit 1,
23 yeşil / 3 kırmızı, aynı üç ad. (`2b` bu koşuda 1261,0 µs; aynı ad, aynı kusur,
makine gürültüsü — **tavan oynatılmadı**.) Test süitlerinde kırmızı ad yok.
**F1c KAPANIŞINDA, ŞEF KENDİ KOŞTURDU:** aynı komut, aynı küme, `2b` **1310,8 µs**.
Üç ölçüm: 1244,2 → 1261,0 → 1310,8 µs. Tavan 1000 µs sabit; `2b` kapatılmadı ve
kapatılmış gibi yazılmadı. **`2b` yukarı sürükleniyor — F2/F3 bunu bilerek okusun.**

## DEVİR SAYILARI
| sayı | değer (F0) | değer (F1a) | değer (F1c) |
|---|---|---|---|
| kapanan faz | F0 | F1a | **F1c** |
| §5'te gerçek olan adım | yok (belgedeki tek istisna) | **ADIM 2 "kurar" — YARIM**: soru sorulmuyor doğru, "iki komut" yanlış (5/7) | **ADIM 2 "kurar" — GERÇEK**: 3 satır / 0 soru / 34,1 s ve yolun sonunda `exit 2` |
| kesilen kart | 4 | 5 | 4 (kart 0 dahil) |
| salınan işçi | 5 | 5 (tavan 5) | **2** (tavan 2) |
| kırmızı ad kümesi | 3 → 3 | 3 → 3 (büyümedi) | 3 → 3 (büyümedi) |
| test sayısı | 3502 | 3526 (düşmedi) | **3554** (`make test` 3490 + `npm test` 64) |
| durma koşulu tetiklendi mi | hayır | hayır | hayır |

## SIRA
**F1 üçe bölündü** (`SAPMA-KARARLARI.md`): **F1a bitti**, **F1c bitti**,
**F1n** operatörü bekliyor.
Yeni sıra: F1a → **F1c** → **F2** → F1b → F1n → F3.
**SIRADAKİ FAZ: F2 (`rabadon scan`).** Önkoşulu F2-S3'tü — "F1a'nın disclosure kartı
kapanmadan açılmaz" — ve o kart kapandı, `make disclosure` exit 0.
F1c, F2'nin önüne konmuştu çünkü §11 "kırmızıyı sonraki faza taşımak" yasağı
KIRMIZI-A'yı bu gece kapatılabilir buluyordu; kapandı, F2 artık kırmızı zeminin
üstüne basmıyor.
**F2'YE UYARI, ÖLÇÜLÜ:** replay korpusu 527 kayıt / 34 oturum / 4-5 gündür
(7 gün DEĞİL), salt-okunur yedeği `~/.rabadon-korpus-snapshot-20260826/` altındadır,
ve **her koşu ring'in en eski ucunu yiyor** — F2 kendi ölçümünü canlı korpustan
değil, gerekiyorsa yedekten almalı ve hangisini kullandığını yazmalıdır.
F1n (npm yayını) **UYKUDA KOŞMAZ** (§13): operatör kararı, `UYANDIGINDA.md`'de.
Sonraki şef bu dosyayı ve `ENVANTER.md`'yi okur; `KOSU-RABADON-5.md` §6'nın sayılarına
DEĞİL, ölçümlere güvenir. F1a'nın ölçümleri ENVANTER'in F0 sayılarını GÜNCELLER.
