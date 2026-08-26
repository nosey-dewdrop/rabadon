# F0 TUTANAK — Zemin

Tarih: 2026-08-26. Şef: F0 şefi (tek oturum, faz sonunda ölür).
Çalışılan dizin: kartlar 1/3/4 `…/rabadon-kosu4` (kosu4), kart 2 ve kapı
`…/rabadon` (main). **F0 sonrası tek çalışma dizini `…/rabadon`, tek dal `main`.**
Şef kaynak koda dokunmadı. F0'ın kendi commit aralığı **`e6deafe..ad26ff9`** (3 commit).
Kanıt: `git diff --name-only e6deafe..ad26ff9 -- native core site 'reports/*/accept.sh'`
→ **BOŞ**. F0'ın dokunduğu 17 dosyanın tamamı `docs/archive/`, `reports/kosu/`,
`scripts/onkontrol.sh` ve `PROJECT.md`'nin işaretçi paragrafıdır.

DÜZELTME (bu tutanakta önce yanlış yazıldı, düzeltildi): `30d5cbb..ad26ff9` aralığı
F0'ın işi DEĞİLDİR — içinde kosu4'ün 108 eski commit'i vardır ve onlar `native/`e
dokunur. F0'ın dokunmadığını gösteren doğru aralık `e6deafe..ad26ff9`'dur.

## KARTLAR VE HÜKÜMLERİ

| kart | işçi | hüküm | kanıt |
|---|---|---|---|
| 1 ENVANTER | 4 işçi (a,b,c,d) + şef (e,g) | BİTTİ | `reports/kosu/ENVANTER.md` + `RAPOR/envanter-*.md` |
| 2 TEK KÖK TEK DAL | şef | BİTTİ | `git merge --ff-only kosu4` → `Updating 30d5cbb..ad26ff9` |
| 3 TEK KOŞU BELGESİ | şef | BİTTİ | `docs/archive/KOSU-RABADON{,-2,-3,-4}.md`, hepsi iptal notlu |
| 4 ORTAM | 1 işçi | BİTTİ, 8/8 YEŞİL | `scripts/onkontrol.sh`, `RAPOR/f0-ortam.md` |

Toplam salınan işçi: **5** (tavan 6). Hiçbir işçi kesilmedi, hiçbiri alt ajan salmadı.

## KART 2 — ölçüm ve yapılan

- `git merge-base --is-ancestor main kosu4` → exit 0. `git rev-list --count kosu4..main` → **0**.
  Yani ileri sarma **gerçekten** mümkündü; varsayılmadı, ölçüldü.
- İlk `git merge --ff-only kosu4` denemesi **REDDEDİLDİ**: kök klonda commit'lenmemiş
  iki değişiklik vardı (`KOSU-RABADON-2.md`, `scripts/kos.sh` — koşu 2'den kalan
  `DISABLE_AUTOUPDATER=1` satırı). **Yutulmadı.** `git stash push` ile park edildi
  (`stash@{0}`), silinmedi, `reset --hard` KULLANILMADI. İçeriği zaten kosu4'te
  `scripts/arsiv/kos.sh:13`'te commit'li duruyor.
- Birleştirme sonrası `main` = `ad26ff9`, 111 commit ileri sardı, push edildi
  (`30d5cbb..ad26ff9  main -> main`).
- `git worktree remove` ile `rabadon-kosu2` ve `rabadon-kosu3` kaldırıldı.
  **DALLAR SİLİNMEDİ:** `git branch -a` → `kosu2`, `kosu3`, `kosu4` ve üçünün
  `origin/` karşılığı duruyor.
- `rabadon-kosu4` worktree'si şefin **son işi** olarak kaldırıldı (kendi ayağını
  kesmemek için sıra buna göre kuruldu: önce kosu4'te commit + push, sonra kök
  klonda birleştirme, sonra kosu2/kosu3, en son kosu4).
- **Veri kaybı önlendi:** kosu3 worktree'sinde commit'lenmemiş `TUR.md` bulundu
  (4732 bayt, git'e hiç girmemiş). Worktree kaldırılsaydı silinecekti.
  `docs/archive/TUR-kosu3.md` olarak iptal notuyla korundu.
  Ayrıca kosu3'teki commit'lenmemiş `AGENTS-PROTOCOL.md` silmesi `git restore` ile geri alındı.

## KART 3 — arşivleme

Dört koşu belgesi `git mv` ile `docs/archive/` altına indi, her birinin başına
tek satır: `İPTAL: KOSU-RABADON-5.md ile değiştirildi, 2026-08-26.` Silme yok.
Kökte tek koşu belgesi kaldı: `KOSU-RABADON-5.md` (`ls | grep -i kosu` tek satır basıyor).

İki yan iş, ikisi de tutanağa yazılı (sessiz değil):
- `docs/arsiv/` ile `docs/archive/` aynı anda duruyordu (iki arşiv kökü =
  F0'ın öldürmeye geldiği belirsizliğin ta kendisi). Tek dosyası
  `DEGERLENDIREN.md` `docs/archive/`e taşındı, boş dizin kaldırıldı.
- `PROJECT.md:9` **arşive inen bir dosyayı** "the current run" diye gösteriyordu.
  Sarkan işaretçi düzeltildi: artık `KOSU-RABADON-5.md`'yi gösteriyor ve dördünün
  nereye indiğini yazıyor. **Değiştirilen tek şey işaretçi**; PROJECT.md'nin
  mühürlü invariants bloğuna DOKUNULMADI.

## KART 4 — ortam

`scripts/onkontrol.sh` yazıldı: sertleştirme maddeleri emekli sürücüden
(`scripts/arsiv/kos.sh`, "KOSMAZ") çıkarılıp tek canlı yere toplandı, uydurulmadı.
Koşuldu: **8/8 YEŞİL, exit 0.**

| madde | hüküm |
|---|---|
| prompt/CI zırhı (`GIT_TERMINAL_PROMPT=0` vd.) | YEŞİL |
| `PYTHONIOENCODING=utf-8` + `PYTHONUTF8=1` | YEŞİL |
| `DISABLE_AUTOUPDATER=1` + sürüm kaydı (`claude --version` = 2.1.172) | YEŞİL |
| `timeout` shim (macOS'ta yok; `/opt/homebrew/bin/timeout` bulundu) | YEŞİL |
| git kilitleri — ÖNCE lock kırılır SONRA yarım rebase temizlenir | YEŞİL |
| disk + inode + /tmp eşikleri (`df -Pi`) | YEŞİL |
| alt süreç: 4 aday SAYILDI ve isim isim LİSTELENDİ, **öldürülmedi** (operatör kararı) | YEŞİL |
| `git push --dry-run` reddi yutulmaz | YEŞİL, rc=0 |

**rabadon'un kendi koşusuna bağlanması — ölçüldü, DEĞİŞTİRİLMEDİ:**
`~/.claude/settings.json` PreToolUse(*) + PostToolUse(*) ile kök klonun
`native/rabadon-gate` ikilisini çağırıyor. `RABADON_MODE` set değil, `.rabadon/off`
yok, `~/.rabadon/mode.last` = **watch**. Yani **observe modda**, deny değil.
Ayrı bir sarmalayıcı betik YOK; yalıtımı sağlayan şey ikilinin kök klondan gelmesi
(koşulan kaynak canlı değil). Bu bir eksiklik olarak yazılıdır, F0'da değiştirilmedi.

## KAPI (§8)

| # | madde | hüküm | kanıt |
|---|---|---|---|
| 1 | fazın kabul betiği yeşil | GEÇTİ | F0'ın kabul betiği `scripts/onkontrol.sh`, 8/8, exit 0 |
| 2 | boş yeşil kontrolü | GEÇTİ | `onkontrol.sh` madde 8, `git push --dry-run` rc!=0'da KIRMIZI basıp exit 1 veriyor; madde 4 `timeout`/`gtimeout` yoksa KIRMIZI. Denetimler yokluk halinde kırmızı düşebiliyor |
| 3 | **kırmızı AD kümesi büyümedi** | GEÇTİ | aşağıda |
| 4 | eşik/tolerans/ön-kayıt/fixture değişti mi | GEÇTİ — **hiçbiri değişmedi** (`git diff --name-only e6deafe..ad26ff9 -- native core site 'reports/*/accept.sh'` → boş) |
| 5 | ölçüm sevk edilen yoldan alındı mı | GEÇTİ | `make all` (21 gerçek ikili) + `reports/R7/accept.sh` gerçek native ikiliyle koştu |
| 6 | **UX kapısı** | **UYGULANMAZ** | F0'ın ADIM satırı YOKTUR; §7/F0 son satırı: "**ADIM:** yok. Tek istisna, ve bu yüzden en kısa faz." Bu, belgede yazılı tek istisnadır ve tutanağa açıkça yazılmıştır |
| 7 | hakem hükmü | ŞEFİN İŞİ DEĞİL — orkestratör hakemi doğuracak, `reports/kosu/KAPI.md` |
| 8 | kâtibin commit'i | GEÇTİ | §9: küçük fazda kâtip ayrı oturum açmaz, şefin son işi olarak koşar. F0'ın docs değişikliği YALNIZ arşivleme notudur: `docs/archive/*` iptal satırları + `PROJECT.md` işaretçisi. Yeni iddia, yeni sayı, yeni yayın metni YAZILMADI |
| 9 | SAPMA satırı | aşağıda |

### §8.3 — kırmızı AD kümesi, iki ölçüm

| süit | F0 ÖNCESİ (kosu4, e6deafe) | F0 SONRASI (main, ad26ff9) | kırmızı ADLAR |
|---|---|---|---|
| `reports/R7/accept.sh` | 23 yeşil / 3 kırmızı, exit 1 | 23 yeşil / 3 kırmızı, exit 1 | **`2b`, `6e`, `7b`** — İKİSİNDE DE AYNI |
| `make test` | exit 0, 0 kırmızı | exit 0, 0 kırmızı | yok |
| `npm test` | exit 0, 64/64 | exit 0, 64/64 (`ℹ fail 0`) | yok |

Kırmızıların tam metni F0 SONRASI
(`grep -n "^FAIL" reports/kosu/RAPOR/f0-after-r7accept.out`):
- `FAIL  2b the gate's median is 1254.3 us with the daemon up, ceiling is 1000 us`
- `FAIL  6e counter validation impossible: no 'estimated_saved' total on arm B, or no per-arm total_cost_usd`
- `FAIL  7b falsification 2 is UNCHECKABLE — no deviation could be computed`

**KIRMIZI AD KÜMESİ: `{2b, 6e, 7b}` → `{2b, 6e, 7b}`. BÜYÜMEDİ.**
(2b'nin sayısı 1299,4 µs → 1254,3 µs; ikisi de tavanın üstünde, hüküm değişmedi.
Bu sayı bir iyileşme İDDİASI DEĞİLDİR — aynı makinede gürültü bandındadır.)

Yeşil tarafın kaymadığının kanıtı: 26 adlandırılmış süit özet satırı
(`… passed, … failed`) F0 öncesi ve sonrası **birebir aynı** —
`diff reports/kosu/RAPOR/f0-suites-before.txt reports/kosu/RAPOR/f0-suites-after.txt`
çıktısı BOŞ, exit 0.

## SAPMA SATIRI (§8.9)

**F0 §5'in hiçbir adımını gerçek yapmadı ve yapması da beklenmiyordu** — F0'ın
ADIM satırı yoktur, belgede yazılı tek istisnadır. F0'ın ürettiği şey adım değil,
**zemin**: tek kök, tek dal, tek koşu belgesi, ölçülmüş envanter, 8/8 yeşil ortam.
Gösteren sayı: 4 worktree → 1 kök; 5 koşu belgesi → 1 canlı belge; kırmızı ad
kümesi 3 → 3. **Sapmadık.**

Ama zeminin altından çıkan şey yazılmalı: **§6'nın anlattığı ürün ile ölçülen ürün
aynı değil** (bkz. `ENVANTER.md` ÇELİŞKİLER). Sinyal sayısı 4 değil 8, verb sayısı
25 değil 5/30/44, ve "enjeksiyon hiç ulaşmadı" cümlesi eksik: canlı spool'da 6 INJECT
satırı var — ama başka bir repoda, 23 Ağu tarihli bir ikiliden. Sonraki fazlar
§6'ya değil `ENVANTER.md`'ye bakacak.

## NOT VERIFIED / ÖLÇÜLEMEDİ

- **Temiz makine / fresh clone / Linux:** hiçbir ölçüm temiz konteynerde yapılmadı.
  `make test` ve `accept.sh` yeşilleri YALNIZ bu makinede geçerlidir. F1'in kurulum
  matrisi bunu kapatacak.
- **`scripts/onkontrol.sh` yalnız macOS/arm64'te koştu.** Linux'ta koşmadı.
- **Kapının runtime davranışı ölçülmedi:** gate ikilisinin gerçekten enjekte edip
  etmediği canlı olarak sınanmadı; `ENVANTER.md` (a) statik çağrı zinciri ölçümüdür.
- **`move.suite` alanının nerede doldurulduğu izlenmedi.** Hiç set edilmiyorsa
  `green_redefined` (a) ve (b) hiç ateşlemez — F1b/F2'nin ölçmesi gereken şey.
- **Ledger zincir bütünlüğü doğrulanmadı** (`rabadon audit` koşulmadı); 150 satır
  zincir dışında (`*.unchained.jsonl` × 3).
- `stash@{0}` kök klonda duruyor; kimse uygulamadı, kimse silmedi.

## PARKED / kart dışı fark edilenler (DOKUNULMADI)

- `guard.json`'daki `no-gnu-timeout-on-macos` kuralı `timeout <sayı>` ile başlayan
  komutu reddediyor; oysa koşu mimarisi `timeout`a dayanıyor. **Kapı enforce moda
  geçerse koşunun kendi ön kontrolü kendi kapısına takılır.** Kurala dokunulmadı.
- `KAPI-PROMPT.md` hâlâ `KOSU-RABADON.md`'nin turlarına atıf yapıyor; koşu 5'in
  hakem şablonu §15.3'tür. Bayat, dokunulmadı.
- İki yetim süreç (PID 85131, 85359 — `rabadon.mjs *--help*`) ve koşu 2'nin sürücüsü
  (PID 2372/2373) hâlâ canlı. Öldürmek operatör kararı, F0 dokunmadı.
- `~/.rabadon/spool/` içindeki bazı günlük dosyalarda UTF-8 dışı bayt var; `grep -c`
  sessizce boş dönüyor, `grep -a` şart. **Bu tuzağa düşen her önceki sayım şüphelidir.**
- Kökteki `/index.html` ile yayınlanan `site/index.html` iki farklı ürün anlatıyor.
- `v0.2.3` etiketi yok (`package.json` 0.2.3 diyor).

## DURMA KOŞULU (§13)

Sekiz durma koşulunun **hiçbiri** tetiklenmedi. Push reddedilmedi (iki push da rc=0),
kırmızı ad kümesi büyümedi, hiçbir kabul ölçüsü değiştirilmedi, aynı kırmızı iki kez
üst üste denenmedi, ortam kartı 8/8 yeşil. `UYANDIGINDA.md` F0 için AÇILMADI.
Para harcayan ya da geri alınamaz hiçbir iş yapılmadı: npm yayını yok, duyuru yok,
`reset --hard` yok, dal silme yok, force push yok.
