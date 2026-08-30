# DURUM — koşu 5, F1e sonrası (2026-08-26)

Koşunun kısa ve KANITLI durumu. Her satır bir ölçümden okundu.
Ayrıntı ve komutlar: `reports/kosu/ENVANTER.md`.
Koşu 3'ün DURUM'u `reports/kosu/arsiv/DURUM-kosu3.md`'de, iptal notuyla duruyor.

## SON HÜKÜM — F3h: **KALDI** (2026-08-30, `KAPI.md`)

Kapı sayıları kartla **birebir** ve hakem tarafından yeniden koşturuldu:
`make test` **EXIT=0** · native **4022** iddia + **633** kontrol + `npm test`
**64/0** = **4719 yeşil / 0 kırmızı** (taban 4664, **+55**; +55'in tamamı
süit-diff'iyle ayrıldı: `law_family` 68→117, yeni `home_isolation` 0→6).
`accept.sh` **EXIT=1, 23/3, `{2b, 6e, 7b}` BÜYÜMEDİ**. Süit **116 → 117**.
Küçülen 0 · kaybolan 0 · silinen dosya 0.

**GEÇEN:** K0 (`~/.claude/settings.json` bayt bayt aynı, mutasyon 4/2 kırmızı) ·
K1 (beş yanlış pozitif kapandı, daraltma bypass açmadı, çift yönde pinlendi) ·
K3 (911 µs yeniden üretildi ve karttan **daha ağır** çıktı: daemon +530,4 µs,
8/8, bandı **aşıyor**).

**KAPATMAYAN:** yasanın ailesinde ölçülmüş, yasayı gerçekten yok eden bir şekil
sınıfı var (`ls -a | xargs rm -rf`, `find . -delete` ve dört `-not` varyantı,
`cd .. && rm -rf proj` — sekizi de ALLOW + law-GONE) ve **ürün bunu
söylemiyor**: `blind spots:` ekranı bu fazın diff'inde hiç yok. Kartta ilan,
ilan değildir (Promise 1). Ayrıntı: `reports/kosu/RAPOR/F3h-R.md`.

### SÜİT SAYACI — TEK GEÇERLİ SAYAÇ (F3h hükmü, log regex'i EMEKLİ)

Üç faz üç farklı sayı verdi çünkü herkes `make test` **çıktısını** regex'liyordu.
Süit sayısı bundan sonra **kaynaktan** okunur:

    awk '/^test:/{f=1} f&&/^$/{exit} f' Makefile \
      | grep -oE 'native/[a-zA-Z0-9_.-]+\.sh' | sort -u | wc -l

`F3h-oncesi` → **116** · `F3i-oncesi` → **117** · HEAD (`c9c7887`) → **119**.
(Aynı şey logdan sayılınca 115/116 çıkıyor — bu yüzden log regex'i emekli.)

**F3i hakemi, 2026-08-30, hepsini kendi koşturdu — GÜNCEL SAYAÇ SATIRI BUDUR:**
`make test` **EXIT=0** · native **4045** + `PASS (N checks)` **633** + `npm test` **64/0**
= **4742 yeşil / 0 kırmızı**. Taban `c48c0e4` de kendi worktree'sinde koşuldu
(`$HOME` altında, `/tmp` değil): **4022 + 633 + 64 = 4719**, yani **+23**, ve +23'ün
tamamı süit-diff'iyle ayrıldı (`brake_persist` yok→**13**, `law_blind` yok→**10**;
**küçülen 0 · kaybolan 0**). `accept.sh` **EXIT=1, 23 yeşil / 3 kırmızı**, ad kümesi
**`{2b, 6e, 7b}` büyümedi**.

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
  *(EMEKLİ SAYAÇ — aşağıdaki "TEST SAYACI" bölümüne bak; bu sayı `PASS (N checks)`
  basan 9 süidin 612 kontrolünü saymıyor ve yeni sayıyla KIYASLANAMAZ.)*
- **Kabul:** `reports/R7/accept.sh` → **23 yeşil / 3 kırmızı**, adlar **`2b`, `6e`, `7b`**.
- **CLI:** ana help 5 verb, `dev` 30, dispatcher 44. (Belgedeki "25 verb" hiçbir ölçümle eşleşmiyor.)
- **npm:** `rabadon` E404. `package.json` 0.2.3. `v0.2.3` etiketi yok.
- **Landing:** eski ürünü satıyor — başlık "guardrails and a verifiable record",
  kurulum `git clone && make`, komutlar `watch/on/usage/repair/audit`.
  "compound error" ve "injection" sayfada **0 kez** geçiyor.
- **⚠⚠ KAPI BUGÜN (2026-08-30 04:12, F3i hakemi ölçtü — GÜNCEL SATIR BUDUR;
  aşağıdaki F3h satırı da 2026-08-29 satırı da ARTIK EKSİK, silinmiyor):**
  mod **WATCH**, `enabled` **YOK** (mtime 30 Ağu 03:22) — operatörün kalemi,
  hakem **dokunmadı**. **AMA ASIL BULGU MODDA DEĞİLDİ:** sevk edilen
  `native/rabadon-gate` ikilisi **17 baytlık bir `#!/bin/sh` + `exit 0` PUÇU**
  idi (gerçek ikili `rabadon-gate.gercek` olarak yana alınmış, ikisinin de mtime
  **30 Ağu 03:48**), ve `~/.claude/settings.json`'ın **altı** kancası da o yolu
  çağırıyor → **03:48→04:12 arası rabadon bu makinede her çağrıda sessizce
  `exit 0` verdi**: kurulu görünen, hiçbir şey görmeyen guard (Promise 1 ihlali,
  `exit 126`'dan beter). Aynı sha'lı puçun ikizi (`306c6ca740756034`)
  `_hakem_f3g_base/native/rabadon-drift`'e de konmuştu. **`make` bunu onarmıyor**
  (mtime kaynaklardan yeni → "up to date"); yakalayan **`version_test.sh`** oldu
  (`DRIFT rabadon-gate --version says ""`, EXIT=2, ilk 3 saniye). Hakem gerçek
  ikiliyi geri yazdı ve kaynaktan yeniden derleyip **bayt bayt aynı** olduğunu
  doğruladı (`a2ffd11c371447b1`). **Kim puçladı ÖLÇÜLEMEDİ.**
  Hüküm: `KARARLAR.md` · 2026-08-30 · F3i · (2).
- **`~/.claude/settings.json` (2026-08-30, F3i hakemi):** zehirli yol **0** —
  her `command` yolu tek tek varlık kontrolünden geçti, üçü de mevcut
  (`orkestra/src/tick.py` yabancı kancalar · `orkestra/src/bar.py` paylaşımlı
  statusLine · altı girdide kanonik `…/rabadon/native/rabadon-gate`); makinedeki
  **41** `settings*.json` tarandı, canlı `_hakem_` referansı **0**. Dosya hakemin
  **dört** `make test` koşusunun dördünde de **bayt bayt aynı** kaldı
  (`adcb41a93f858d6b`) — kök klon ×2, taban worktree'si ×1. **Kök sebep yine de
  ürün tarafındadır ve F3j'nin ilk kartıdır:** self-heal koşan ikilinin MUTLAK
  yolunu yazıyor (`KARARLAR.md` · F3i · (3)).
- **KAPI 2026-08-30'da (F3h hakemi ölçtü — artık eksik, yukarıya bak):** mod **WATCH**, `enabled` YOK,
  yani **kullanıcının freni KAPALI.** Üç yoldan ölçüldü: `cat ~/.rabadon/mode`
  → `watch`; `ls ~/.rabadon/enabled` → yok; sevk edilen ikiliye gerçek
  `PreToolUse` (`git push --force origin main`) → *"rabadon (watch) would have
  blocked this. Nothing was stopped."* **EXIT=0.** `mode` mtime **30 Ağu
  02:03:16**, F3h penceresinin (01:48→02:36) ortası; `enabled`'ın kalkması
  `rabadon off` imzasıdır ama **kimin yaptığı ÖLÇÜLEMEDİ** (aynı dakikalarda
  makinede ilgisiz ikinci bir Claude oturumu koşuyordu). Hakem kapı durumunu
  **DEĞİŞTİRMEDİ.** Hüküm: `KARARLAR.md` · 2026-08-30 · F3h · (4).
  **F3i'nin ilk işi: freni geri açmak ve bu satırı ölçümle tazelemek.**
- **Kapı 2026-08-29'da (hakem ölçtü — ARTIK GÜNCEL DEĞİL, yukarıya bak):**
  `~/.claude/settings.json` kök klonun `native/rabadon-gate` ikilisini çağırıyor,
  mod **ENFORCE (deny)**. Üç yoldan ölçüldü: `~/.rabadon/mode` içeriği `enforce`;
  `rabadon status` → "ON — the arbiter acts"; sevk edilen ikiliye gerçek
  PreToolUse olayı → **BLOCKED, EXIT=2**. Ayrıca kapı hakem oturumunda üç gerçek
  komutu kesti. Kapı durumu hakem tarafından DEĞİŞTİRİLMEDİ.
  *(Was: "mod **watch (observe)**, deny değil." — 2026-08-29'da ÖLÇÜLDÜ ve YANLIŞ
  çıktı; hüküm `KARARLAR.md` · 2026-08-29 · F1b · (c). Eski cümle silinmiyor.)*

## F1b HAKEM HÜKMÜ: **GEÇTİ** (2026-08-29, `KAPI.md`) — aşağıdaki blok DÜZELTİLDİ

Kart kendini "BLOKE" ve "F1e-C KARŞILANMADI" ilan etmişti. **O, 27 Ağu'daki
`red-base` blokajı altında doğruydu; bugün DEĞİL.** Hakem HEAD `16631f3`'te,
temp kökü DIŞINDAKİ kendi kum havuzunda ölçtü:

| bacak | kartta | **hakem, 2026-08-29** |
|---|---|---|
| `make test` (konak) | EXIT=0, 3786 + 633 | **EXIT=0, 3786 + 633** |
| `npm test` | ÖLÇÜLEMEDİ | **64 pass / 0 fail, EXIT=0** |
| `bash reports/R7/accept.sh` | ÖLÇÜLEMEDİ | **EXIT=1, 23 yeşil / 3 kırmızı** |
| kırmızı ad kümesi | ölçülmedi | **`{2b, 6e, 7b}` — BÜYÜMEDİ** (`2b` 1259,2 µs) |
| F1e-C üçlüsü | KARŞILANMADI | **KARŞILANDI: 42/0 · 38/0 · 13/0, üçü de EXIT=0** |
| **TOPLAM** | — | **4483 yeşil / 0 kırmızı** (F2 tabanıyla BİREBİR) |

Sıfır büyüme beklenendir: sertleştirilen kol macOS'ta hiç koşmuyor. **Sayaç
DÜŞMEDİ.** Hakem mutasyon kanıtını kartınkini kopyalamadan KONAKTA yeniden
üretti (`sandbox-exec` içermeyen PATH gölgesiyle kolu açtı → 9/0; ürün dizgesini
`NO kernel backend at all` yaptı → **8/1 EXIT=1**, ve o mutant dizgeyi **eski
iddia GEÇİRİYORDU** → daralma kanıtlandı; geri aldı → 9/0).
**FAZI BLOKE EDEN KIRMIZI BUGÜN ATEŞLEMİYOR** — ama onarıldığı için değil:
`~/.rabadon/guard.json` `check` alanı 29 Ağu'da elle `stitchu`'nun süitine
daraltıldı, yani semptom susturuldu, kusur duruyor (D6).
Ayrıntı, NOT VERIFIED ve §5.5 dökümü: **`reports/kosu/RAPOR/F1b-R.md`**.

## F1b'NİN DEĞİŞTİRDİĞİ ÖLÇÜMLER (2026-08-27 · kartın kendi yazdığı hâl, tarihsel)

- **`native/sandbox_test.sh:121` sapması KAPANDI** (`09a93af`, tek satır, SERTLEŞTİRME:
  `grep -qi "no kernel backend"` → `grep -q "rabadon sandbox: NO usable kernel backend"`).
  Konteynerde süit **7/1 KIRMIZI → 9/0 YEŞİL**. Mutasyon kanıtı konteynerde koştu
  (yeşil→kırmızı→yeşil); seçilen mutant dizge (`NO kernel backend at all`) **eski iddiayı
  geçerdi**, yenisi yakalıyor — gevşetme değil daralma.
- **KARTIN GEREKÇESİNDEKİ CÜMLE YANLIŞ ÇIKTI, ÖLÇÜLDÜ.** "konteynerde `make test`'i exit 2'de
  tutan **tek kalem**" iddiası (`KARARLAR.md`, `DURUM.md:551`) doğru değil: `sandbox_test.sh`
  **tek** kalem değil **ilk** kalemdi. Onarımdan sonra konteynerde **`make test` HÂLÂ EXIT=2**,
  şimdi `site_claims_test.sh`'te duruyor (`site/build.py:277` → `gh` ikilisi imajda YOK,
  koşu `--network none`). Kanıt: `reports/kosu/kanit/f1b/sonrasi-konteyner-make-test.out`.
- **Konteyner nüfusu** (`node:22-bookworm · arm64 · root · --network none`, HEAD `09a93af`,
  `reports/refenv/f1b-arm64-root-suites.tsv`): 106 süit / **103 YEŞİL / 2 KIRMIZI** /
  1 TIMEOUT. Kırmızılar: `site_claims_test.sh`, `publish_redaction_test.sh`.
  TIMEOUT (`npm_install_test.sh`) **regresyon değil**, benim `--suite-timeout 300`
  parametremin artefaktı — o süit F2'nin üç sayımında 562/571/564 s sürüp YEŞİL'di.
- **Konak `make test`: EXIT=0, 3786 iddia + 633 kontrol** — F2 tabanıyla BİREBİR AYNI.
  Beklenen: sertleştirilen iddia macOS'ta hiç koşmuyor (Seatbelt hep mevcut).
- **`8b` tuzağı kurulmadı:** `signals_test.sh` **39/0**, tek iddia eklenmedi,
  `reports/R7/accept.sh` bu fazda hiç değişmedi. Eşitlik gevşetilmedi, `>=` yapılmadı.
- **KIRMIZI AD KÜMESİ BU FAZDA ÖLÇÜLEMEDİ.** `accept.sh` koşturulamadı (aşağı bak).
  Büyüdüğü iddia edilmiyor; **ölçülmediği** yazılıyor.
- **FAZI BLOKE EDEN YENİ KIRMIZI — rabadon kendi kökünde kendini kilitledi (FALSE REJECT):**
  kapı `red-base` ile her komutu reddediyor, kırmızı sandığı çek `python3 -m pytest -q`.
  Ölçüm: repoda `pytest.ini` YOK, `conftest.py` YOK, `test_*.py` YOK; pytest "no tests ran"
  deyip **exit 5** dönüyor. Kök sebep `native/truth.cpp:336-337` — `s.py > 0` + herhangi bir
  test dosyası görünce süiti "python" sayıyor. Bu kırmızı **temizlenemez**.
  Reddedilenler arasında **`git status` (salt-okunur)**, **`npm test`**, ve **`make test`**
  (yani ekranın "re-run that check" tavsiyesinin ta kendisi) var. Ayrıca ret komşu dizine
  sızıyor, ve ilk segmenti çekin kendisi olan bileşik komutlar kapıdan geçiyor (delik
  bildirildi, **kullanılmadı**). Ayrıntı ve kanıt: kartta CHALLENGE-1/2/3.
- **Bu yüzden F1e-C kapı şartı KARŞILANMADI** (`docs_truth_test.sh` + `install_docs_test.sh`
  + `version_test.sh` koşturulamadı) ve **faz kapanmadı**. Kart ve bu bölüm diskte;
  **commit atılamadı**, git de reddedildi.
- Not: `DURUM.md:36-37` kapının **watch (observe)** modda bırakıldığını yazıyor. Bugün
  ölçülen davranış **deny**'dir. İkisinden biri güncel değil; ajan kapı durumunu
  değiştirmedi.

## F1a'NIN DEĞİŞTİRDİĞİ ÖLÇÜMLER (yukarıdaki satırlar F0 ölçümüdür, bunlar günceldir)
- **Test:** `make test` **3462**/0, `npm test` **64**/0 → **3526 yeşil / 0 kırmızı**.
  (F0'da 3502'ydi; hiçbir test silinmedi, +24 eklendi.)
  *(EMEKLİ SAYAÇ, GENİŞ regex `^\s*ok\b`. Aşağıdaki "TEST SAYACI"na bak.)*
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
  *(EMEKLİ SAYAÇ, DAR regex `^  ok`. Aşağıdaki "TEST SAYACI"na bak — bu regex
  bir süidin 14 gerçek iddiasını sessizce düşürüyordu.)*
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

## F1d'NİN DEĞİŞTİRDİĞİ ÖLÇÜMLER (BUNLAR EN GÜNCEL SATIRLARDIR)
Tam tutanak: `reports/kosu/RAPOR/f1d-tutanak.md`. Faz aralığı `1ea32c4..HEAD`.

- **"AÇTIM" DİYEN VE AÇMAYAN YÜZEY KAPANDI.** Faz öncesi ölçüm (şefin kendi kum
  havuzu, sevk edilen yol): `.rabadon/off` dururken `rabadon on` ve `status`
  **"ON — the arbiter acts"** basıyordu, aynı olay gerçek gate'te **EXIT=0 / 0 BAYT**,
  ve aynı ikilinin `--statusline`'ı **"rabadon off"** diyordu. Şimdi ekran
  susturucuyu **adıyla + tam yoluyla + onu kaldıran TEK komutla** basıyor (§4.8),
  ve o komut koşulunca `status` ON diyor, gate **EXIT=2** veriyor, lamba yanıyor.
  Verbatim: `reports/kosu/RAPOR/f1d-0-ekran.out`.
- **TEK KAYNAK.** `native/gate.cpp`'de tek `compute_state(dir)`: üç susturucu
  (`RABADON_OFF=1`, `<proje>/.rabadon/off`, `<RABADON_DIR>/silent`) + katmanlı mod
  (`RABADON_MODE` → proje `mode` → proje `on` → makine `mode` → `enabled`) + `blind`.
  **Sıcak yol ikinci kopya tutmuyor**, aynı fonksiyonu çağırıyor; `--statusline` da.
- **KIRMIZI DÜŞEBİLEN KİLİT:** `native/status_truth_test.sh` (yeni) — 16 hücre
  (`mode` × `.rabadon/off` × `RABADON_OFF` × `silent`) × 3 iddia (`status`/`on`/`off`),
  her iddia **gerçek `native/rabadon-gate` ikilisinin çıkış kodu + çıktı bayt
  sayısıyla** karşılaştırılıyor. "ON" + `EXIT=0` KIRMIZIDIR. Ayrıca `status` ile
  `--statusline` her hücrede aynı hükmü vermek zorunda. **17 ok / 77 fail → 94 ok / 0 fail.**
- **ÖLÇÜM HAKEMİN BULDUĞUNDAN DAHA KÖTÜ ÇIKTI:** `--statusline` `<RABADON_DIR>/mode`
  dosyasını **hiç okumuyordu** — susturucu OLMAYAN düz `mode=enforce` hücresinde bile
  "watch" diyordu. Üçüncü bir okuma vardı; o da kapandı.
- **`bin/rabadon.mjs` EDİTLENMEDİ** (donmuş anti-path, O3, varsayılan donuk).
  `git diff --name-only 1ea32c4..HEAD` çıktısında `bin/` YOK. Yerine kilit:
  "sevk edilen hiçbir yol `on|off|status|toggle`'ı oraya götürmez" — bugün **4/4 yeşil**,
  yarın biri geri bağlarsa kırmızı düşer.
- **`.rabadon/off` BELGELENDİ** (kâtip, yalnız `docs/`): `docs/commands.md`,
  `docs/faq.md`, `docs/uninstall.md`. Ve ÖLÇÜLEREK yazıldı ki **`rabadon off` bu
  dosyayı KALDIRMAZ** — yalnız modu watch'a çeker, susturucu yerinde kalır.
- **B2 KAPANDI:** `native/install_docs_test.sh` **20 ok → 38 ok** (hiçbir eski ok
  düşmedi). Değişmez: *`package.json` sürümünün `v<sürüm>` etiketi `git tag --list`'te
  YOKKEN sevk edilen hiçbir belge `npm i -g rabadon`'u yazılabilir komut olarak
  taşıyamaz.* **Çevrimdışı** (ağ isteği YOK, temiz konteynerde koşar) ve **F1n gününde
  kendiliğinden serbest bırakır** — `v0.2.3` etiketli geçici repoda gerçek koşuyla
  kanıtlandı. `docs/quickstart.md` §1 artık kaynaktan-kurma yolunu satıyor; eski npm
  cümlesi SİLİNMEDİ, "henüz npm'de değil / E404 / ölçüm 2026-08-26" gerekçesiyle
  prose olarak duruyor. `git tag --list | grep -c '^v0.2.3$'` → **0**, etiket atılmadı.
- **BOŞ YEŞİL (§8.2), AYRI WORKTREE:** `git worktree add --detach /tmp/f1d-pre 1ea32c4`
  + `make all` → iki yeni kilit de faz öncesi kodda KIRMIZI:
  `status_truth_test.sh` **17/77 exit 1**, `install_docs_test.sh` **35/3 exit 1**.
  HEAD'de ikisi de yeşil. Verbatim: `reports/kosu/RAPOR/f1d-bosyesil-worktree.out`.
  Worktree kaldırıldı.
- **Test:** `make test` exit **0**, native **3616** iddia + **612** kontrol = **4228**,
  `npm test` **64/0** → **TOPLAM 4292 yeşil / 0 kırmızı** (F1c tabanı 4180, **+112**).
  Silinen/zayıflatılan/atlanan test YOK; eşik/tolerans/fixture/ön-kayıt HİÇ değişmedi.
- **Yüzey:** `native/rabadon-cli.sh` `1ea32c4` ile **BAYT BAYT AYNI** — yeni verb yok,
  ana ekran hâlâ 5 ürün verb'ü, varsayılan hâlâ WATCH.
- **KENDİ ÜRÜNÜMÜZ KENDİ ÜSTÜMÜZDE İKİ GERÇEK YAKALAMA YAPTI** (kart açılmadı, F1b'ye
  aday): şefin `... | grep ...; echo "EXIT=$?"` komutu `no-exit-code-after-pipe` ile,
  işçi C'nin ve şefin `sed -i` ile yerinde yeniden yazma denemesi
  `no-blind-inplace-source-rewrite` ile reddedildi. İkisi de doğru red.
- **Devralınan `version_test.sh` de bir gerçek yakalama yaptı:** kâtip commit'i
  `docs/quickstart.md`'ye `0.2.3`/`v0.2.3` sürümlerini düz metne yazmıştı, DRIFT olarak
  yakalandı, `make test` kırmızı düştü. **Test değiştirilmedi**, cümle yeniden yazıldı
  (`cf34caf`). `version_test.sh` 12/1 → **13/0**.

## F1e'NİN DEĞİŞTİRDİĞİ ÖLÇÜMLER (BUNLAR EN GÜNCEL SATIRLARDIR)
Tam tutanak: `reports/kosu/RAPOR/f1e-tutanak.md`. Faz aralığı `05ab1ac..HEAD`.

- **AÇILMAYAN KAÇIŞ KAPISI KAPANDI.** Faz öncesi (şefin kendi kum havuzu, sevk
  edilen yol, `f1e-0-onolcum.out`): `RABADON_MODE=silent` ve
  `<proje>/.rabadon/mode=silent` hâllerinde ekran `` `rabadon off` to watch again ``
  diyor, kullanıcı VERBATIM koşuyor, gate **hâlâ EXIT=0 / 0 BAYT**. Şimdi ekran
  susturucuyu **adıyla + yeriyle + gerçekten açan tek komutuyla** basıyor
  (`unset RABADON_MODE` / `rm <proje>/.rabadon/mode` / `rabadon off`), ve şef
  komutu **ekrandan çekip verbatim koşturdu**: altı susturucunun **altısında** da
  gate aynı olayda konuşmaya başlıyor (`f1e-2-kacis-dogrulama.out`,
  `f1e-3-alti-susturucu.out`).
- **TEK KAYNAK KORUNDU.** `gate.cpp` `compute_state`: mod katmanı `silent`
  dediğinde bu artık bir `Muter`'dır, yani F1d'nin disclosure yolu
  kendiliğinden çalışır. İkinci kopya açılmadı; ekran, `--statusline` ve sıcak
  yol aynı struct'ı okur.
- **KİLİT GENİŞLEDİ, HİÇBİR İDDİA DÜŞMEDİ:** `native/status_truth_test.sh`
  `RABADON_MODE` ve proje/makine `mode` katmanlarını da geziyor
  (`grep -c RABADON_MODE` **0 → 11**). Her hücrede `next:` komutu **ekrandan
  çekilip** verbatim koşuluyor, sonra gerçek gate yeniden ölçülüyor;
  tanımadığı komut = FAIL. **94 → 162 ok / 0 fail.**
- **BELGE ARTIK OKUNMUYOR, YÜRÜTÜLÜYOR.** `native/docs_truth_test.sh` (YENİ) +
  `docs/claims.tsv` (15 kayıt). Susturucu tablosunun HER satırı için kum havuzunda
  o hâl kuruluyor, satırın kendi komutu verbatim koşuluyor, gate yeniden ölçülüyor.
  Belgedeki küme **ikiliden türetilen** kümeye EŞİT olmak zorunda, ve ekranın
  bastığı komutla belgenin komutu **bayt bayt aynı** olmak zorunda. **40 ok / 0 fail.**
- **C1 + C2 KAPANDI.** `docs/commands.md`'nin üç cümlesi de ölçümle yanlış
  bulundu ve düzeltildi (`rabadon off` susturucuların **hiçbirini** kaldırmaz →
  YANLIŞ, `silent` dosyasını ve `mode=silent`'ı kaldırır; `rabadon on` ENFORCE
  basar → YANLIŞ, SILENT basar; `status` susturucuyu basmaz → YANLIŞ, basar).
  **Eski cümleler SİLİNMEDİ**, ölçüm tarihi + komutuyla alıntılanıp düzeltildi.
  Tablo **3 satır → 6 satır**; 3. satırın yanlış komutu `rm ~/.rabadon/silent`
  → **`rabadon off`**.
- **AÇIK SORU KAPANDI:** SAPMA-KARARLARI aynı yalanın `docs/faq.md` ve
  `docs/uninstall.md`'de olup olmadığını açık bırakmıştı. Şef ölçtü: **EVET**,
  ikisinde de vardı, ikisi de düzeltildi. `README.md` / `docs/quickstart.md` /
  `site/` susturuculardan **hiç söz etmiyor** — orada yalan yoktu.
- **C6 (YANLIŞ POZİTİF) ONARILDI, KURAL GEVŞEMEDİ.** Kök sebep ölçüldü:
  `rules.h:pattern_names_a_pipe` boruyu adlandıran kurallara ek yüzey olarak
  **ham satırı** veriyordu, `cmdtext.h` heredoc gövdelerini çıkarmasına rağmen.
  `rbtext::Parsed.line` (heredoc gövdesiz ön-işlenmiş satır) eklendi.
  **Fikstür koddan ÖNCE** commit edildi (`e64c1eb` → `6699efb`);
  `native/heredoc_prose_test.sh` onarım öncesi **FAILED**, sonrası
  **PASS (14 checks)**, ve gerçek `cmd | grep x ; echo $?` **HÂLÂ REDDEDİLİYOR**.
- **YANLIŞ POZİTİF SAYISI, YAYIMLANIYOR:** bu koşuda ölçülmüş **4 olay / 2 sınıf**.
  İkisi onarıldı (`no-exit-code-after-pipe`, `no-gnu-timeout-on-macos` düzyazıda).
  **AÇIK:** `red-suite-test-write` süit gerçekte yeşilken **iki** meşru Write'ı
  reddetti — `lastTestPass` yalnız çıktısı GÖRÜNEN test komutundan güncelleniyor.
  Kart açılmadı, kural değiştirilmedi, olay yazıldı.
- **REFERANS KONTEYNER: 46 ÖLÇÜLMEMİŞ SÜİT → 0.** `native/refenv/run.sh` (YENİ,
  yalnız ÖLÇER) commit'lendi ve şef fazın NİHAİ HEAD'inde (`6385da1`) koşturdu:
  `node:22-bookworm` linux/arm64, **`--network none`**, `make all` **exit 0**,
  **105 süit: 102 GREEN / 3 RED / 0 TIMEOUT / 0 HİÇ KOŞMAYAN.**
  Önceki oturumun "54 süit koşmadı" rakamı bir tahmindi; gerçek sayı 46'ydı ve
  bugün 0. Ham kanıt: `f1e-d-{env,build,suites.tsv,suites.out}`.
  **F1e'nin kendi süitleri konteynerde çevrimdışı YEŞİL:** `status_truth` 162/0,
  `docs_truth` 40/0, `heredoc_prose` exit 0, `install_docs` 38/0, `version` 13/0.
- **KONTEYNERDEKİ ÜÇ KIRMIZI, ADIYLA VE KÖK SEBEBİYLE** (F1e'nin açtığı değil,
  F1e'nin ölçtüğü; hepsi macOS'ta ölü dallar):
  `sandbox_test.sh` (**GERÇEK SAPMA**: ürün `NO **usable** kernel backend` basıyor,
  test `"no kernel backend"` arıyor; dizgeyi `a74e7d8` değiştirdi ve testi
  güncellemedi) · `site_claims_test.sh` (`site/build.py:277` `gh` istiyor —
  `make test` içinde **beyan edilmemiş dış bağımlılık**) ·
  `publish_redaction_test.sh` (konteyner `root` koşuyor, `-root` dizgesi
  `rule_census.json`'un İngilizce düzyazısında geçiyor; **sızıntı YOK**).
- **`native/sandbox_test.sh` YEŞİL İÇİN DEĞİŞTİRİLMEDİ.** CHALLENGE yazıldı
  (`f1e-c-konteyner.md` §4), **KIRMIZI bırakıldı, insan hükmü bekliyor**
  (CLAUDE.md 1 ve 2). Cazip düzeltme (grep'i gevşetmek) bu ürünün var olma
  sebebinin tersidir.
- **BONUS, ÖLÇÜLDÜ (F1n'in işine yarar):** `npm_install_test.sh` konteynerde
  **çevrimdışı yeşil, 12/12, 562 s** — yayımlanacak npm yolu **derleyicisi hiç
  olmayan** bir makinede (tüm derleyiciler 127 dönen shim) ve **ağsız** çalışıyor,
  ve README'nin ilk vaadi (force-push reddi) kurulu hook üstünden ateşliyor.
- **BOŞ YEŞİL (§8.2), ÜÇ KİLİDİN ÜÇÜ DE:** `status_truth_test.sh` ayrı worktree'de
  faz öncesi HEAD `05ab1ac`'te **130 ok / 32 fail** (32'nin hepsi `silent` hücreleri);
  `docs_truth_test.sh` eski belgelerde **14 ok / 27 fail**;
  `heredoc_prose_test.sh` onarım öncesi ikilide **FAILED**.
  Verbatim: `f1e-a-bosyesil.out`, `f1e-b-bosyesil.out`, `f1e-a-c6-once.out`.
- **F1e-C (YENİ KAPI ŞARTI, bundan sonra her fazda):** kâtibin commit'i (`63e01f3`)
  fazın SON commit'i değil; `docs_truth` + `install_docs` + `version` üçlüsü
  fazın **NİHAİ ikilisine karşı** şefin elinde yeniden yeşil koştu (40/0, 38/0, 13/0).
- **Test:** `make test` exit **0**, native **3738** iddia + **626** kontrol = **4364**,
  `npm test` **64/0** → **TOPLAM 4428 yeşil / 0 kırmızı** (F1d tabanı 4292, **+136**).
  Silinen/zayıflatılan/atlanan test YOK; eşik/tolerans/fikstür/ön-kayıt HİÇ değişmedi.
- **Yüzey:** `native/rabadon-cli.sh` `05ab1ac` ile **BAYT BAYT AYNI** — yeni verb yok,
  ana ekran hâlâ 5 ürün verb'ü, varsayılan hâlâ WATCH. `git diff --name-only
  05ab1ac..HEAD` çıktısında `bin/` **YOK** (anti-path donuk kaldı).
- **KART DIŞI, İŞÇİ A'NIN İLAN ETTİĞİ SAPMA:** C6 onarımı `native/`'i 23366 satıra
  çıkardı ve `site_claims_test.sh` README'nin "~20k" cümlesini kırmızıya düşürdü;
  işçi sayıyı ölçüp `~23k` yazdı. Kart `README.md`'yi saymıyordu — ilan edildi.

## F2'NİN DEĞİŞTİRDİĞİ ÖLÇÜMLER (BUNLAR EN GÜNCEL SATIRLARDIR)
Tam tutanak: `reports/kosu/RAPOR/F2.md`. Faz aralığı `f03320f..HEAD`.
Kart raporları: `RAPOR/f2-0-kart.md` … `f2-5-kart.md`.

- **§5'in ADIM 3'ü GERÇEK OLDU (ilk ekran, kendi verisinden).**
  `rabadon usage --signals` — yeni ürün verb'ü değil, `usage`'ın bayrağı.
  **Kullanıcı 2 komutta varıyor** (`rabadon --help` → `--signals` geçen 1
  satır, sonra tek komut), 0 ayar / 0 dosya / `real 0,02 sn`, tek ekran
  37 satır, ekran görüntüsü alınabilir. Salt okunur: `RABADON_DIR`'ın
  dosya+mtime hash'i ekrandan önce ve sonra AYNI. Verbatim ekran:
  `RAPOR/f2-2-ekran-snapshot.out`, adım ölçümü `f2-2-adim.out`.
  `cli_test.sh` beş-verb tavanı yeşil (315/0), `PRODUCT` listesi değişmedi.
- **KABUL SAYISI DONDURULMUŞ YEDEKTEN OKUNDU (S8), canlı ring'den DEĞİL:**
  `~/.rabadon-korpus-snapshot-20260826/` → **34 oturum / 527 hamle diskte /
  başlık 654 / KAYIP 127**, kaybı üreten ring ekranda ADIYLA. Canlı korpus
  yalnız bilgi olarak ayrı basıldı (`f2-2-ekran.out`: LOSS **1.417**,
  başlık 1.944 — canlı ring bu oturumda büyüdü, kayıp %72,9).
- **ÖLÇÜM BEKLENENDEN KÖTÜ: BEŞ DEDEKTÖRDEN DÖRDÜ HİÇ ATEŞLEMEDİ.**
  Dondurulmuş korpusta `repeat`, `oscillation`, `root_migration`,
  `green_redefined` **n=0 = NOT MEASURED**, her biri sıfırın SEBEBİYLE.
  Ateşleyen tek dedektör `scope_drift` (**n=17**) ve elle etiketlemede
  **17/17 YANLIŞ POZİTİF** (`f2-3-etiketleme.md`). **HİÇBİR SİNYAL CANLIYA
  ÇIKMADI.** Zemin (ii) monorepo: ÖLÇÜLMEDİ, korpusta monorepo yok.
- **S12 (BLOKLAYAN İLK KART) KAPANDI.** Tırnaklanmış bir kelimenin içindeki
  boru artık boru hattı sayılmıyor: beş şekil (`printf` çift/tek tırnak,
  `echo … >> dosya`, `python3 -c`, **`git commit -m`**) faz öncesi ikilide
  BLOCK'tu (`f2-0-bosyesil.out`), şimdi ALLOW. Kural GEVŞEMEDİ: çıplak
  `make test | grep -c ok ; echo exit=$?` ve mevcut yedi pozitif BLOCK kaldı,
  **ve `bash -c "<gerçek boru hattı>"` hücresi de BLOCK** — tırnaklı dizge bir
  kabuğa verildiğinde program sayılıyor. `heredoc_prose_test.sh` 14 → **21**
  iddia. `.rabadon/guard.json` (regex, eşik, `disabled[]`) HİÇ değişmedi.
  **S12/d için CHALLENGE gerekmedi.**
- **S13: YANLIŞ POZİTİF SAYACI ARTIK DEFTERDEN TÜRÜYOR.**
  `native/refusal_rate.sh <sid-öneki>` (bash + grep/sed/awk; python3/jq/node/ağ
  YOK). **İki payda tanımı da ayrı basılıyor:** `STOP+BLOCKED` **16**,
  `WOULD_BLOCK` **24**, toplam **40**. Yayımlanan eski "15" yalnız STOP'tu ve o
  tanımla bugün 16. **16 retin 16'sı tek tek hükme bağlandı** (`f2-0-hukum.md`):
  **DOĞRU 6 / YANLIŞ 6 / HÜKÜMSÜZ 4**. Hükümsüz 4'ün sebebi ölçüldü ve ilan
  edildi: `STOP.detail` komutu **160 baytta kesiyor**. İki yeni `rabadon wrong`
  gerçekten koşuldu. **Eski "4 olay / 2 sınıf" sayısı SİLİNMEDİ**, "elle
  sayıldı, defterle uyuşmuyor" etiketiyle durur ve yeni sayılarla KIYASLANMAZ.
  **İLAN EDİLEN BOŞLUK (S13/e):** `WRONG_REFUSAL` satırında `sess`/`sid`/`call`
  YOK, `STOP`'ta VAR → pay ile payda yalnız KURAL ADI üzerinden birleşiyor.
- **S5: İKİLİ HAMLE RING'İNDEN ÇIKAN TEK KAPI ONARILDI.** `native/audit.cpp`
  her dizge alanını RFC 8259'a göre kaçışlıyor. Ölçüm: **281/608 satır
  ayrışmıyordu → 527/527 ayrışıyor, 0 bayt kayıp** (`f2-1-once.out`,
  `f2-1-sonra.out`). 608 → 527 farkı veri kaybı DEĞİL: 608 bozuk yazıcının
  FİZİKSEL satırıydı, 527 ring başlıklarının taahhüt ettiği kayıt sayısı;
  527 kaydın hepsi ikiliden `struct` ile açılıp bayt bayt karşılaştırıldı.
  **`moves_test.sh`'in sessiz `except: continue` yutucusu artık SAYIYOR ve
  ADLANDIRIYOR** (CLAIM 8; 21 → 22 iddia, kırmızı düşebilirliği ölçüldü).
- **S14: KİLİDİN KARDİNALİTESİ ARTIK İKİLİDEN GELİYOR.** `gate.cpp` tek
  `kSilencers` tablosu, her `Muter` oradan kuruluyor, `rabadon-gate --silencers`
  ilan ediyor; `docs_truth_test.sh` bölüm 2b `SITUATIONS` kümesinin ikilinin
  ilan ettiği kümeye EŞİT olmasını şart koşuyor. **Boş yeşil:** geçici yedinci
  susturucu eklendi → **41 ok / 1 fail, EXIT=1**, satır adıyla söylendi; geri
  alındı → **42 ok / 0 fail** (`f2-4-bosyesil.out`). 40 iddianın hiçbiri
  silinmedi. `--silencers` `argc == 1` olan sıcak yola HİÇ girmiyor,
  `kKnownFlags`'te ve `--help`'te LİSTELENMİYOR; yeni ürün verb'ü YOK.
- **S15 + S10: REFERANS ORTAM ÜÇ EKSENDE ÖLÇÜLDÜ, HAM ÇIKTI COMMIT'LENDİ.**
  `reports/refenv/` artık git'te izli (S15/d kapandı).
  | koşum | HEAD | süit | yeşil | kırmızı | timeout / hiç koşmayan |
  |---|---|---|---|---|---|
  | `linux/amd64` root (emülasyon) | `c8a2ad6` | 105 | 102 | 3 | 0 / 0 |
  | `linux/arm64` **non-root** `1000:1000` | `c8a2ad6` | 105 | 102 | 3 | 0 / 0 |
  | `linux/arm64` root, **fazın NİHAİ HEAD'i** | **`6a6b03a`** | **106** | **103** | **3** | **0 / 0** |
  Üçü de `--network none`. Etiket yasası: bu sayılar
  `node:22-bookworm · <platform> · <user> · --network none` hakkındadır,
  "linux'ta yeşil" ya da "temiz makinede yeşil" DEĞİLDİR.
  **F2'nin kendi süiti `signals_screen_test.sh` konteynerde 38/0 YEŞİL**
  (kart 5'in koşumları o süit doğmadan önceydi; boşluğu faz kapanışı kapattı).
  **F2 YENİ KIRMIZI ÜRETMEDİ** — üç kırmızı devralınan üçün aynısı.
- **NEGATİF SONUÇ: F1e'NİN BİR AÇIKLAMASI YANLIŞLANDI.** "`publish_redaction_
  test.sh` kırmızısı root ortam artefaktıdır" iddiası ölçülünce ÇÖKTÜ: non-root
  koşumda da KIRMIZI, ve daha kötü — uid 1000 = `node` olduğu için tek düzyazı
  eşleşmesi **13 dosyada 107 eşleşmeye** çıktı. Sızıntı YOK; kusur kontrolün
  tasarımında (muafiyet listesi tek sabit ad, `runner`). Onarım kapsam dışı.
- **`docs/commands.md` ARTIK SEVK EDİLEN `--signals` YÜZEYİNİ BELGELİYOR**
  (kâtip kartı): başlık bayrağı taşıyor, bölüm LOSS bloğunu, `NOT MEASURED`'ın
  ne demek olduğunu, oran-yok kuralını ve `--signals --json`'ın reddini yazıyor.
  Düzyazı `<!-- rabadon:claims-begin -->` bloğunun DIŞINDA (blok susturucu
  tablosudur), o yüzden `docs/claims.tsv` değişmedi; bunun yerine
  `signals_screen_test.sh`'e üç yeni iddia eklendi ve sayfayı **aynı süitin
  gerçek ikiliden ölçtüğü ekrana** bağlıyor. Kırmızı düşebilirliği ölçüldü:
  **35/3 EXIT=1** (`f2-6-kirmizi-once.out`) → **38/0 EXIT=0**
  (`f2-6-yesil-sonra.out`).
- **F1e-C KAPI ŞARTI TUTULDU:** kâtip commit'i (`6a6b03a`) fazın SON commit'i
  değil; `docs_truth` **42/0**, `install_docs` **38/0**, `version` **13/0**
  fazın NİHAİ ikilisine karşı yeniden koşuldu (`f2-6-f1ec-uclu.out`).
- **S9: F2 HOT-PATH'E HİÇBİR ŞEY EKLEMEDİ.** `--signals` spool açılmadan önce
  dönen erken-çıkışlı bir kol; `grep -c 'rabadon-stats' native/gate.cpp` → **0**.
  Kart 0'ın iki ikiliyi aynı dakikada ölçen bench'i: **228,7 → 231,8 µs (+%1,4)**.
  Sevk edilen hiçbir yüzeyde `sub-ms`/`sub-millisecond` YOK (ölçüldü); ve
  `signals_screen_test.sh` o kelimeyi ekranda YASAKLIYOR.
- **Test:** `make test` exit **0**, native **3786** iddia + **633** kontrol =
  **4419**, `npm test` **64/0** → **TOPLAM 4483 yeşil / 0 kırmızı**
  (F1e tabanı 4428, **+55**). Silinen/zayıflatılan/atlanan test YOK;
  eşik/tolerans/fikstür HİÇ değişmedi. **TEK KABUL-DOSYASI DEĞİŞİKLİĞİ:**
  `reports/R7/accept.sh` `8a` sabiti 21 → 22 (`9cba3cd`), tam eşitlik KORUNDU,
  uygulayan işçi değil ayrı bir işçi yaptı, kendi commit'inde — **hakemin
  onayını bekler**, aşağıya bak.
- **Yüzey:** yeni ürün verb'ü YOK. `git diff --name-only f03320f..HEAD`
  çıktısında `bin/` **YOK** (anti-path donuk kaldı, O3).

## F3 HAKEM HÜKMÜ: **GEÇTİ** (2026-08-29, `KAPI.md`) — FAZ §3.7 İLE BÖLÜNDÜ

Kartın iki BLOKLAYAN kartı gerçekten kapandı; kartın **tek sayısını
kopyalamadan** hepsini temp kökü DIŞINDAKİ kendi kum havuzumda yeniden ürettim
(`~/damla_projects_2026/_hakem_f3_{head,base}`, iki worktree, ikisi de
kaldırıldı) ve BİREBİR tuttular:

| ölçü | kartta | **hakem** |
|---|---|---|
| `make test` | EXIT=0, 3808 + 633 | **EXIT=0, 3808 + 633** |
| `npm test` | 64/0 | **64 pass / 0 fail** |
| **TOPLAM** | 4505 / 0 | **4505 yeşil / 0 kırmızı** (taban 4483, **+22**) |
| `reports/R7/accept.sh` | exit 1, 23/3 | **EXIT=1, 23 yeşil / 3 kırmızı** |
| kırmızı ad kümesi | `{2b,6e,7b}` | **`{2b,6e,7b}` — BÜYÜMEDİ** |
| `2b` | 1240,2 µs | **1237,5 µs** (tavan 1000 µs oynatılmadı) |
| F1e-C üçlüsü | 42/0 · 38/0 · 13/0 | **42/0 · 38/0 · 13/0, üçü de EXIT=0** |

**+22 aritmetik olarak tam tamına iki yeni süide ait** (13 + 9). F3'te `docs/`
commit'i YOK, yani kâtip şartı boş yere sağlanıyor — ve bayatlayan belge cümlesi
de yok (`grep -rn "red-base" docs/ README.md docs/claims.tsv` → 0 satır).

**HAKEMİN KENDİ MUTASYONLARI (kartınkiler kopyalanmadı):** fikstürler faz öncesi
ikilide gerçekten kırmızı düşüyor (`discovery_scope` **7/6**, `redbase_scope`
**8/1**, `/tmp` DIŞINDA ayrı worktree); `gate.cpp:4776` `git -C` takibi
kapatılınca **8/1**, muafiyet koşulsuza çevrilince **5/4** ve ilk düşen arm
`the red stopped refusing work on the broken base — the rule is gone`; ikisi de
geri alındı → 9/0.

**KARTIN "ÖLÇÜLMEDİ" BIRAKTIĞI `Library` SORUSU ÖLÇÜLDÜ:** faz öncesi ağaçta
`skip_dir`'e `Library` eklendi → **9 ok / 4 fail**, düşen arm
`src/Library/ went blind`. **D6/2'nin lafzı ölçümle YANLIŞLANDI**, ajanın
`Library`'yi eklememesi DOĞRU sapmadır (`KARARLAR.md` · F3 · (a)).

**KURAL GEVŞETİLMEDİ:** `gate.cpp:3549` inconclusive bloğu faz öncesiyle bayt
bayt aynı; `disabled[]` değişmedi; `~/.rabadon/guard.json` mtime **15:36**,
fazın ilk commit'i **18:05** — dosya açılmadı; `accept.sh` / `ON-KAYIT.md` /
`claims.tsv` / `.rabadon/` diff'te HİÇ YOK. CHALLENGE-2'nin muafiyeti
`red-base`'i zayıflatmıyor, **kapsamını daraltıyor** ve dört twin arm
daralttığının bypass olmadığını ölçüyor.

**YENİ KART: D7 · `Makefile:79` — F3b'nin BLOKLAYAN İLK KARTI.** Kartın "make
başlık bağımlılığı izlemiyor" ilanının kök sebebi bulundu ve DAHA DAR/DAHA KÖTÜ:
`Makefile:29` `rabadon-gate` `pathres.h`'i sayıyor ama `Makefile:79`
`rabadon-net` yalnız `net.cpp cli_help.h` diyor, oysa `net.cpp:50-51`
`testout.h` + `pathres.h` include ediyor. Ölçüldü: `touch native/pathres.h &&
make all` sonrası `rabadon-net` mtime **DEĞİŞMİYOR**, `rabadon-gate` değişiyor.
`pathres.h` D6'nın `$HOME` onarımının, `net.cpp` `rc==5` onarımının yaşadığı
dosyadır — **iki onarım da bayat ikiliden yeşil alabilir.** Gerekçe ve kabul
maddesi: `KARARLAR.md` · F3 · (c).

**§3.12 HÜKMÜ:** ajan §3.12'ye dayanıp durdu, ama bu koşuda F3 için **yazılı bir
tahmin YOKTUR** (`grep -n "tahmin" KOSU-RABADON-5.md` → 0 satır), yani
tetikleyici nicelik hiç ölçülmemiştir. **Dayanak yok, en kısıtlayıcı seçildi:**
durmanın USULÜ kabul (ajan durmayı İLAN ETTİ, §3.12'nin yasağı sessizce
sürünmektir), ama fazın ÜRÜN kapsamı sürünmüştür ve **§3.7 ile bölünmüştür.**
Bölme gerekçesi üç sayı: (i) KOSU §F3'ün kendi kapsamından teslim **%0**
(diff'te `inject.h`/`signals.h`/`policy.h` HİÇ YOK; aşağıdaki "(b) ve (c) için
HİÇ kanıt yok" satırı hâlâ doğru); (ii) +22 iddianın 22'si onarım kartlarına,
enjeksiyona **0**; (iii) `2b`'nin tavana açığı **681,3 µs** (%40,5 iniş kaldı).

**F3-S1'İN KABUL MADDESİ KARŞILANDI, ONARIMI DEĞİL.** Medyan yükselmedi
(F2 1271,2 → F1b 1259,2 → kart 1240,2 → **hakem 1237,5 µs**) ve kart eksiği
ölçüyle+adıyla yazdı — `SAPMA-KARARLARI.md:800-806`'nın istediği budur.
Hakem `2b`'yi uçtan uca kendi de ölçtü (N=200 mean): faz öncesi
**2004,9 µs = 2,00×**, nihai ikili **1681,3 µs = 1,68×** — **sıcak yol
yavaşlamadı.** **F3-S1'İN SAHİBİ ADIYLA: F3b.**

Ayrıntı, NOT VERIFIED ve §5.5 dökümü: **`reports/kosu/RAPOR/F3-R.md`**.

## F3'ÜN DEĞİŞTİRDİĞİ ÖLÇÜMLER (BUNLAR EN GÜNCEL SATIRLARDIR)
Kart: `reports/kosu/RAPOR/F3.md`. Kanıt: `reports/kosu/kanit/f3/`. Aralık `6913ae1..HEAD`.

- **D6 KAPANDI, ÜÇ KÖKÜN ÜÇÜ DE.** `truth.cpp skip_dir()`'e **`site-packages` +
  `dist-packages`** eklendi (`Library` EKLENMEDİ — ölçüldü, eklemek `src/Library/`
  projesini kör ediyor); `pathres.h project_root()` artık **`$HOME`'u kök seçmiyor**,
  altındaki gerçek git kökü hâlâ kazanıyor; `net.cpp:274` boş-koşu muafiyeti
  `(rc==0 || rc==5)` oldu, yani pytest'in "no tests ran" çıkışı artık **inconclusive**,
  kırmızı değil. Fikstür koddan ÖNCE (`6350d8d` → `d4e80e8`).
  Kilit: `native/discovery_scope_test.sh` — faz öncesi ikilide **7 ok / 6 fail**,
  bugün **13/0**. Hakemin iki hücresi: `.venv/...` level 1 YEŞİL kaldı,
  `Library/Python/3.9/.../site-packages` **level 3 → level 1** düştü.
- **CHALLENGE-2 YENİDEN ÜRETİLDİ ve KAPANDI.** Sevk edilen ikilide ölçüldü: P kırmızıyken
  hook cwd=P iken `cd <komşu> && git commit` **exit 2**, hook cwd=komşu iken **exit 0** —
  ret eylemin dokunduğuna değil oturumun nerede başladığına bakıyordu. `gate.cpp` red-base
  artık her segmentin kendi kökünü soruyor. Muafiyet dar: bir segment içerideyse satır
  reddedilir, `git -C` izlenir, degraded satıra muafiyet yok.
  Kilit: `native/redbase_scope_test.sh` — faz öncesi **8/1**, bugün **9/0**.
- **MUTASYON KANITI, dört mutant:** site-packages geri alındı → **10/3**; `$HOME` koruması
  geri alındı → **11/2**; `rc==5` geri alındı → **12/1**; red-base muafiyeti `git -C`
  takibini bıraktı → **8/1**. Hepsi geri alındı, `f3-mutasyon.out`.
- **BOŞ YEŞİL (§8.2), iki kilidin ikisi de:** `git worktree add --detach /tmp/f3-pre
  F3-oncesi` üstünde `discovery_scope_test.sh` **7/6 KIRMIZI**, `redbase_scope_test.sh`
  **8/1 KIRMIZI**. Worktree kaldırıldı.
- **§8.5 ÜÇÜNCÜ HARNESS'TA DOĞRULANDI, ONARILMADI.** `reports/kosu/kanit/f3/2b-uctan-uca.sh`
  (yeni, yalnız ölçer, MEAN/allow-yolu — §8.5'in MEDIAN/refused sayısıyla aynı büyüklük
  ama aynı sayı DEĞİL): `F3-oncesi` **1985,7 µs atfedilebilir = 1,99×**, fazın nihai
  ikilisi **1941,3 µs = 1,94×**. **Tavan 1000 µs oynatılmadı**, sıcak yol yavaşlamadı.
  **F3-S1 onarımı BAŞLAMADI** (§3.12, kartta gerekçeli).
- **CANLI `$HOME` ÜSTÜNDE ONARIM ÖLÇÜLEMEZ:** eski ikili 20657 kod / 2797 test, yeni ikili
  20672 / 2804 — ama **ikisi de `discoveryCapped:["depth","budget"]`**, yani sayı ağacın
  değil sınırın şekli (Kapı 2), ve `via:` hâlâ elle daraltılmış `.rabadon/guard.json check`.
  Bütün D6 ölçümleri bu yüzden **fikstürle** üretildi. `rabadon-truth $HOME` doğrudan
  çağrılınca hâlâ level 3'tür: kökü orada kullanıcı açıkça veriyor.
- **İLAN EDİLEN, KART AÇILMADI:** `make` başlık bağımlılığı izlemiyor — `pathres.h`
  düzenlenip `make all` koşulduğunda ikili yeniden derlenMEDİ ve bir mutant sahte yeşil
  verdi (`touch` ile yakalandı). **Bayat ikiliyle yeşil üretilebilir.**
- **Test:** `make test` exit **0**, native **3808** iddia + **633** kontrol = **4441**,
  `npm test` **64/0** → **TOPLAM 4505 yeşil / 0 kırmızı** (F2 tabanı 4483, **+22**).
  Silinen/zayıflatılan/atlanan test YOK; eşik/tolerans/fikstür/ön-kayıt HİÇ değişmedi.
  Kabul dosyasına dokunulmadı. `Makefile`'a yalnız iki süit satırı eklendi.
- **F3 SONRASI KIRMIZI AD KÜMESİ: `{2b, 6e, 7b}` — BÜYÜMEDİ.** `bash reports/R7/accept.sh`
  → exit 1, **23 yeşil / 3 kırmızı**. `2b` bu koşuda **1240,2 µs** (on üçüncü ölçüm; seri
  1299,4 → … → 1164,0 → 1257,5 → **1240,2**). Test süitlerinde kırmızı ad YOK.
- **ÖLÇÜLMÜŞ YANLIŞ POZİTİF, bu faz: 1.** `make test` çıktısını `grep -nE "FAIL"` ile
  taradığım komuta PostToolUse **"tests are RED"** bastı; `make test` EXIT=0'dı ve kural
  benim grep çıktımı süit çıktısı sandı. Sayılıyor, mazur görülmüyor.

## F2 · KIRMIZI AD KÜMESİ VE BİR KABUL-DOSYASI KARARI
**F2 SONRASI: `{ 2b, 6e, 7b }` — BÜYÜMEDİ.** `bash reports/R7/accept.sh` →
exit 1, **23 yeşil / 3 kırmızı**. `2b` bu koşuda **1164,0 µs** (aynı ajanın faz
ortası okuması 1305,2 µs). On iki ölçümün serisi: 1299,4 → 1244,2 → 1261,0 →
1310,8 → 1248,8 → 1229,9 → 1184,7 → 1270,3 → 1293,2 → 1229,0 → 1305,2 →
**1164,0** µs. **Tavan 1000 µs oynatılmadı ve on ikisi de üstünde.**
Test süitlerinde kırmızı ad YOK.

**FAZ İÇİNDE GEÇİCİ OLARAK DÖRDE ÇIKTI:** kart 1'in yeni CLAIM 8'i
`moves_test.sh`'i 21 → 22 iddiaya taşıdı, `reports/R7/accept.sh` `8a` sayıyı TAM
EŞİTLİKLE pinliyordu, küme `{2b, 6e, 7b, 8a}` oldu. Kart 1 işçisi onarmayı
**REDDETTİ** (kabul dosyası; CLAUDE.md 2) ve CHALLENGE yazdı. Ayrı bir işçi
(kart 3) kendi commit'inde `9cba3cd` sabiti 21 → 22 yaptı ve **tam eşitliği
korudu** (`>=` yapmadı). `8a` bugün yeşil. **BU BİR KABUL-DOSYASI
DEĞİŞİKLİĞİDİR VE HAKEM ONAYI BEKLER.**

## §8.5 — `2b` İÇİN İKİ SAYI YAN YANA (NEGATİF SONUÇ, olduğu gibi)
Ölçüm: `reports/kosu/RAPOR/f1e-4-2b-iki-sayi.out`, N=300, daemon açık, şef koşturdu.
Betik önce olayın gerçekten reddedildiğini (gate exit **2**) doğruluyor — yoksa
bir no-op ölçülmüş olurdu.

| alet | sayı |
|---|---|
| süreç-içi prob (`reports/R7/accept.sh`, regresyon cetveli) | **1229,0 µs** |
| **GERÇEK `native/rabadon-gate`, uçtan uca, ham** | **3381,3 µs** (p10 3147,7 / p90 3919,0) |
| aynı harness'ta boş taban (`/usr/bin/true`) | 1386,8 µs |
| → **rabadon'a ATFEDİLEBİLİR maliyet** | **1994,5 µs** |
| tavan (`2b`) | 1000,0 µs — **hiç oynatılmadı** |
| **atfedilebilir / tavan** | **1,99×** |

Cevapçının aynı gün aldığı sayılarla (ham 3201,8–3224,5; atfedilebilir
1677,4–2056,5 µs) aynı yere düşüyor — üçüncü bağımsız harness aynı yönü doğruluyor.
**Kullanıcının hook'unda geçen süre yayımlanan prob sayısı DEĞİLDİR.** Ham sayı
probun **2,75 katı**; boş taban düşülünce bile tavanın **iki katı**.
Sahibi atanmış: ölçüm+yasak **F2-S9(d,e)**, onarım **F3-S1** (prob değil,
**sevk edilen ikilinin uçtan uca sayısı** hedeftir).

## TEST SAYACI — TEK GEÇERLİ SAYAÇ (cevapçı hükmü, 2026-08-26, §10)

Bu dosyada iki farklı sayaç uzlaştırılmadan yan yana duruyordu. Cevapçı iki
komutu da KENDİ koşturdu (§10) ve teşhis, hakemin sandığından farklı çıktı:
ortada "make'in süit özetleri" diye bir sayaç YOK; **iki farklı regex** vardı,
ve **ikisi de eksik sayıyordu**. Tam gerekçe:
`reports/kosu/SAPMA-KARARLARI.md` · B5.

- **DAR** `grep -c '^  ok'` → bugün **3490**. **EMEKLİ.** Sebep: `ok`'u sütun
  0'dan basan bir süidin **14 gerçek iddiasını sessizce düşürüyor**
  (`make test` çıktısı satır 3951-3965). Süit düşürebilen sayaç §8.2'dir.
- **GENİŞ** `grep -cE '^[[:space:]]*ok\b'` → bugün **3504**.
- **Her iki regexin de görmediği:** `PASS (N checks)` basan 9 süidin
  **612 kontrolü**, ve hiç sayı basmayan **3** süit.
- DURUM.md'nin F1a satırı GENİŞ (3462+64=3526), F1c satırı DAR (3490+64=3554)
  sayaçla yazılmıştı. İki birim yan yana konunca büyüme +28 gibi okunuyor;
  **tek sayaçla gerçek büyüme +42'dir** (3462→3504 ve 3448→3490).

**BUNDAN SONRA HER FAZ ŞU ÜÇLÜYÜ BASAR, TEK KOMUTTAN:**

    make test ; echo "EXIT=$?"                              # 0 OLMALI
    grep -cE '^[[:space:]]*ok\b'          <çıktı>           # native iddia
    grep -oE 'PASS \([0-9]+ checks?\)'    <çıktı> | grep -oE '[0-9]+' | paste -sd+ - | bc
    npm test                                                # 'ℹ pass' / 'ℹ fail'

**BUGÜNKÜ TABAN (2026-08-26, F1c sonrası, cevapçı koşturdu):**

| ölçü | değer |
|---|---|
| `make test` exit | **0** |
| native iddia satırı (GENİŞ) | **3504** |
| native `PASS (N checks)` toplamı | **612** |
| native toplam | **4116** |
| sayı basmayan native süit | **3** (bilinen boşluk, adı ölçülmedi) |
| `npm test` | **64 pass / 0 fail**, exit 0 |
| **TOPLAM** | **4180 yeşil / 0 kırmızı** |

**F1d SONRASI TABAN (2026-08-26, şef kendi koşturdu, AYNI ÜÇ KOMUT):**

| ölçü | F1c sonrası | **F1d sonrası** |
|---|---|---|
| `make test` exit | 0 | **0** |
| native iddia (GENİŞ) | 3504 | **3616** |
| native `PASS (N checks)` | 612 | **612** |
| native toplam | 4116 | **4228** |
| `npm test` | 64/0 | **64/0** |
| **TOPLAM** | 4180 | **4292 yeşil / 0 kırmızı** (+112) |

**F1e SONRASI TABAN (2026-08-26, şef kendi koşturdu, AYNI ÜÇ KOMUT):**

| ölçü | F1c sonrası | F1d sonrası | **F1e sonrası** |
|---|---|---|---|
| `make test` exit | 0 | 0 | **0** |
| native iddia (GENİŞ) | 3504 | 3616 | **3738** |
| native `PASS (N checks)` | 612 | 612 | **626** |
| native toplam | 4116 | 4228 | **4364** |
| `npm test` | 64/0 | 64/0 | **64/0** |
| **TOPLAM** | 4180 | 4292 | **4428 yeşil / 0 kırmızı** (+136) |

`make test` çıktısındaki tek `FAIL` dizesi `regression_demo.sh`'in FİKSTÜRÜDÜR
(satır 4112); o süit `regression: 4 passed, 0 failed` diyor, exit 0.

Eski sayılar (3502 / 3526 / 3554) **silinmedi**, yukarıda emekli etiketiyle
duruyorlar ve yeni sayılarla KIYASLANMAZLAR. Değişen ölçüm YÖNTEMİ, ölçüt
değil; ve yön sertleşmedir — yeni sayaç eskisinin görmediği 612 kontrolü ve
düşürdüğü 14 iddiayı görür.

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
kapatılmış gibi yazılmadı.
**CEVAPÇI ÖLÇÜMÜ (2026-08-26):** aynı komut → exit 1, 23/3, `2b` **1184,7 µs**
(300 örnek medyanı, daemon açık). Yedi ölçümün serisi:
1299,4 → 1244,2 → 1261,0 → 1310,8 → 1248,8 → 1229,9 → **1184,7** µs.
Sürüklenme yok; **yedisi de tavanın üstünde — kalıcı bir §1 hedef ihlali,
gürültü değil.** Sahibi atandı: ölçüm+yasak **F2-S9**, onarım **F3-S1**
(`SAPMA-KARARLARI.md` · B3).
**F1d SONRASI, ŞEF KENDİ KOŞTURDU:** `bash reports/R7/accept.sh` → exit 1,
**23 yeşil / 3 kırmızı**, adlar **`{2b, 6e, 7b}`** — **BÜYÜMEDİ**.
`2b` bu koşuda **1293,2 µs**; dokuz ölçümün serisi 1299,4 → 1244,2 → 1261,0 →
1310,8 → 1248,8 → 1229,9 → 1184,7 → 1270,3 → **1293,2** µs. Tavan 1000 µs
oynatılmadı; bant içinde, regresyon yok. Test süitlerinde kırmızı ad YOK.
**F1e SONRASI, ŞEF KENDİ KOŞTURDU:** `bash reports/R7/accept.sh` → exit 1,
**23 yeşil / 3 kırmızı**, adlar **`{2b, 6e, 7b}`** — **BÜYÜMEDİ**.
`2b` bu koşuda **1229,0 µs** (süreç-içi prob); on ölçümün serisi
1299,4 → 1244,2 → 1261,0 → 1310,8 → 1248,8 → 1229,9 → 1184,7 → 1270,3 →
1293,2 → **1229,0** µs. Tavan 1000 µs oynatılmadı. Test süitlerinde kırmızı
ad YOK. **AMA §8.5'e bak: aynı gün, aynı makine, GERÇEK sevk edilen ikilinin
uçtan uca sayısı 3381,3 µs ham / 1994,5 µs atfedilebilir — prob tek başına
`2b`'nin gerçek büyüklüğünü göstermiyor.**
**KONTEYNERDE (ilk kez ölçüldü):** üç süit kırmızı — `sandbox_test.sh`
(gerçek sapma, CHALLENGE, kırmızı bırakıldı), `site_claims_test.sh` (`gh` yok),
`publish_redaction_test.sh` (`root` altında düzyazı eşleşmesi, sızıntı yok).
Üçü de macOS'ta ölü dallar; **devralınmıştır, F1e'nin açtığı değildir**, ve
bugüne kadar hiç ölçülmemişlerdi.

## DEVİR SAYILARI (F1e)
| sayı | **değer (F1e)** |
|---|---|
| kapanan faz | **F1e** |
| §5'te gerçek olan adım | **YENİ adım YOK — ADIM 7'nin ("rahatsız olursa kaçar") ÇIKIŞ KAPISI gerçek oldu**: altı susturucunun altısında da ekranın bastığı tek komut koşulunca gate aynı olayda konuşuyor (faz öncesi **6'da 3** — tutanaktaki "6'da 4" YANLIŞTI: cevapçı `05ab1ac`'ı ayrı klonda derleyip aynı probu iki ikiliye de koşturdu, üç hücre `next:` satırını HİÇ basmıyordu. Düzeltme: SAPMA-KARARLARI.md D2. Sayı silinmedi, düzeltildi). ADIM 2/4'ün BELGESİNDEKİ yalan da kalktı. |
| kesilen kart | **3** (A kod / B belge / C yalnız ölçüm) |
| salınan işçi | **3** (tavan 3) |
| kırmızı ad kümesi | **3 → 3 (büyümedi)** — `{2b, 6e, 7b}` |
| test sayısı, TEK GEÇERLİ SAYAÇ | **4428** = native (3738 iddia + 626 kontrol) + node 64 |
| konteyner census | **105 süit: 102 yeşil / 3 kırmızı / 0 hiç koşmayan** (öncesi: 46 süit ölçülmemiş) |
| ölçülmüş yanlış pozitif | *(F1d satırı, EMEKLİ)* 4 olay / 2 sınıf. **GÜNCEL, 2026-08-30 F3g hakemi: 11 olay / 4 sınıf — 6 onarıldı (`red-suite-test-write` 4, F3f'in `grep -c rm` 1, F3g'nin `cd .rabadon` 1), 5 ŞEKİL / 1 SINIF AÇIK** (`baseline-law-unmade` bilinmeyen verb + herhangi bir `.rabadon` yolu: `mkdir`, mutlak yol, `$VAR`, `tar -cf` yedekleme, `find -not -path`) |
| durma koşulu tetiklendi mi | **hayır** |

## DEVİR SAYILARI (geçmiş)
| sayı | değer (F0) | değer (F1a) | değer (F1c) | **değer (F1d)** |
|---|---|---|---|---|
| kapanan faz | F0 | F1a | F1c | **F1d** |
| §5'te gerçek olan adım | yok (belgedeki tek istisna) | **ADIM 2 "kurar" — YARIM**: soru sorulmuyor doğru, "iki komut" yanlış (5/7) | **ADIM 2 "kurar" — GERÇEK**: 3 satır / 0 soru / 34,1 s ve yolun sonunda `exit 2` | **YENİ adım YOK — ADIM 2 ve 4'ün altındaki YALAN kalktı**: ekran ne diyorsa gate onu yapıyor, susturucudan çalışır frene **1 komut** |
| kesilen kart | 4 | 5 | 4 (kart 0 dahil) | **3** (A/B/C) |
| salınan işçi | 5 | 5 (tavan 5) | 2 (tavan 2) | **3** (tavan 3) |
| kırmızı ad kümesi | 3 → 3 | 3 → 3 (büyümedi) | 3 → 3 (büyümedi) | **3 → 3 (büyümedi)** |
| test sayısı (EMEKLİ sayaçlar, kıyaslanmaz) | 3502 (geniş) | 3526 (geniş) | 3554 (dar) | — |
| **test sayısı, TEK GEÇERLİ SAYAÇ** (yukarıdaki bölüm) | ölçülmedi | ölçülmedi | **4180** = native (3504 iddia + 612 kontrol) + node 64 | **4292** = native (3616 + 612) + node 64 |
| durma koşulu tetiklendi mi | hayır | hayır | hayır | **hayır** |

## SIRA

### F3g HAKEM HÜKMÜ (2026-08-30) — EN GÜNCEL SATIR, ÖNCE BUNU OKU

**`F3g: KALDI`. SIRADAKİ FAZ F3h.** Tek satır hüküm `KAPI.md`'nin başında,
ayrıntı `RAPOR/F3g-R.md`'de. Altı açık kalem hükme bağlandı
(`KARARLAR.md`, 2026-08-30 · F3g · (1)–(6)).

**TEST SAYACI, HAKEM KENDİ KOŞTURDU (üç komut, §10):**

| ölçü | F3f sonrası (taban) | **F3g sonrası** |
|---|---|---|
| `make test` exit | 0 | **0** |
| native iddia (GENİŞ) | 3893 | **3967** |
| native `PASS (N checks)` | 633 | **633** |
| `npm test` | 64 / 0 | **64 / 0** |
| **TOPLAM** | **4590** | **4664 yeşil / 0 kırmızı** (**+74**) |
| süit | 114 | **115** |

Taban `906b1e1`'i `$HOME` altındaki kendi worktree'imde koşturdum: 3893+633+64
= 4590. **Süit diff'i bölüm bölüm: `guard_delete_test.sh` 16 → 22 (+6),
`law_family_test.sh` YOK → 68 (yeni). Küçülen 0 · kaybolan 0 · başka hiçbir
süidin sayısı değişmedi.** Kartın "114 → 115"i **DOĞRU**; F3f hakeminin
113→115'i ile görünen çelişki, `net_test.sh`'in stderr'e bastığı
`./native/net_test.sh: line 111: <PID> Killed: 9 …` satırının PID'i her koşuda
değiştiği için ayrı bir "süit" gibi sayılmasıydı — artefakt, çözüldü.

**KIRMIZI AD KÜMESİ, F3g SONRASI: `{2b, 6e, 7b}` — BÜYÜMEDİ** (hakem koşturdu,
`accept.sh` EXIT=1, 23 yeşil / 3 kırmızı).

**`2b` DURUMU — TANIMI DEĞİŞTİ, TAVANI DEĞİŞMEDİ. BUGÜNKÜ SAYI: 1942,8 µs ·
tavan 1000 µs · KALAN AÇIK 942,8 µs.** Hakem `reports/R7/accept.sh`'i okudu
(satır 154-207): `2b`'nin aleti `gate.cpp` kopyasında **`main()`'in ilk
satırına** enjekte edilen in-process bir probe'tur. **Yani `2b` = leg 3
(main→exit) ve exec/dyld/imaj yüklemesini HİÇ İÇERMEZ.** F3g kartının "tavan
ulaşılmaz çünkü maliyetin %70'i dyld" muhakemesi `2b`'nin ölçmediği bir bacağa
dayanıyor; kartın "atfedilebilir = gate − boş taban = 1965 µs" tanımı kartın
kendi uydurmasıdır, `accept.sh`'te taban çıkarma YOKTUR. **`2b` açığının %100'ü
rabadon'un kendi kodudur; tavan ulaşılamaz DEĞİLDİR, oynatılmadı, `accept.sh`
diff'te yok.** Profil kısmı doğru ve hakem bağımsız yeniden üretti (N=200):
leg1 **2202,9 µs %68,2** · leg2 2,0 µs · leg3 **1031,5 µs %31,9**; 13 deny
kuralının tamamı **156,5 µs = %4,7** → F3e'nin "%70 kural yolu" iddiası çürük.
**AÇIKLANMAYAN 911 µs:** sevk edilen ikilinin leg 3'ü 1031,5 µs, `accept.sh`'in
daemon-ayakta probe'u 1942,8 µs, aynı `-O2` (Makefile:10 = accept.sh:182).
**§3.7: `2b`'nin sahibi F3-S1 → F3h (tek kart); F3h önce bu 911 µs'yi ölçecek.**

**F3g'DE GERÇEKTEN OLAN, ALTI SATIR:**
1. **DOKUZ ŞEKİL GERÇEKTEN KAPANDI ve onarım verbe değil EYLEME bakıyor** —
   hakem kendi probe'uyla (`$HOME` altında, boş `bash[]` fikstür) dokuzunu da
   ve kartın listelemediği **28 kardeşi** de REFUSE ölçtü.
2. **AMA AİLE KAPANMADI.** Aynı etkiyi üreten sekiz şekil hâlâ rc=0 ALLOW:
   `rm -rf .r*` · `rm -rf .rabado?` · `python3 -c os.remove/shutil.rmtree` ·
   `perl -e unlink` · `cd .. && rm -rf proj` · **`mv . ../renamed`** ·
   **`tar -xf … -C .`** (son ikisini kart hiç ilan etmedi, hakem buldu);
   ayrıca `git worktree remove --force` bütün ağacı yasayla birlikte siliyor.
   **İş geri alınmaz, AD düzeltilir: teslim edilen 37 ŞEKİLDİR, aile değil.**
3. **KART 2 GEÇTİ.** `grep -c rm .rabadon/guard.json` ve `cd .rabadon` bugün
   ALLOW; 37 gerçek ihlal hâlâ BLOCK; daraltma bypass AÇMADI; `guard.json`
   diff'te yok, kural gevşetilmedi.
4. **⚠ YANLIŞ POZİTİF SAYACI +5 ŞEKİL / 1 SINIF, ONARILMAMIŞ.** Hakem sıradan
   iş yaparken kendi elinde: `mkdir -p .rabadon` (kurulumun ilk adımı) ·
   `mkdir -p /baska/yer/.rabadon` (projeyle ilgisiz MUTLAK yol) ·
   `mkdir -p "$VAR/.rabadon"` · `tar -cf backup.tar .rabadon` (YEDEKLEME) ·
   `find … -not -path '*/.rabadon/*' -delete` (yasayı AÇIKÇA hariç tutan komut).
   Sınıf tek: **bilinmeyen verb + `.rabadon` ile biten HERHANGİ bir yol, diskte
   nerede olursa olsun, kapalı düşüyor** — bu, sevk edilen `docs/guard.md`'nin
   *"this project's own copy of the law"* cümlesini YANLIŞ çıkarır.
   **F3h'nin İLK BLOKLAYAN KARTI budur.**
5. **⚠ `make test` KULLANICININ CANLI `~/.claude/settings.json`'INI EZİYOR.**
   Hakem deterministik üretti: `$HOME` altındaki bir `--detach` worktree'de
   `make test` koşunca canlı settings.json'ın **altı hook girdisi birden**
   worktree ikilisini gösterir oldu; geri yazıp tekrarladım, yine oldu.
   Tek başına `SessionStart` bunu YAPMIYOR → sebep F3f self-heal'i değil,
   gerçek `$HOME`'a yazan beş süit (`doctor_test` · `exit_path_test` ·
   `failed_call_test` · `hook_upgrade_test` · `npm_install_test`). Worktree
   kaldırılınca kullanıcının freni var olmayan bir ikiliyi gösterir ve
   **sessizce ölür** — üstelik bu koşunun protokolü her fazda worktree istiyor.
   Hakem 6 pointer'ı kök klona geri yazdı ve doğruladı.
6. **ÇIKIŞ KAPISI: §4.9 İHLALİ YOK, ama kart YANLIŞ ADRES YAYIMLADI.** Kartın
   ilan ettiği `RABADON_OFF=1 rm -rf …` hakemin elinde **REFUSE** (env ön eki
   komut metnidir; `gate.cpp:228` onu susturucu olarak listeler). Çalışan
   kapılar ölçüldü, dördü de rc=0: `rabadon off` · `<proje>/.rabadon/mode=silent`
   · `disabled[]` · ajan dışı düz kabuk. **Ayrı sapma:** belgelenen
   "env → proje → makine" katman sırası tutmuyor, `RABADON_MODE=silent` gate
   env'inde rc=2 verdi.

**§3.8 / §3.12 DENETİMİ TEMİZ:** silinen dosya **0** · silinen/`skip`/`xfail`
iddia **0** · mühürlü set (`accept.sh` · `ON-KAYIT.md` · `docs/claims.tsv` ·
`.rabadon/guard.json` · korpus/snapshot) ve **`bin/rabadon.mjs` (O3)** diff'te
**HİÇ YOK** · `CAP=200` yerinde (`native/moves.h:63`) · ölçüt commit'leri
`acbbee4`/`3b4e85b` koddan ÖNCE ve **KODSUZ** (ürün kodu `1f0f811`'de) ·
§3.12 tahmini `ce199e9` fazın **İLK** commit'i · `cli` **315/0** (beş-verb
tavanı) · `doctor` **43/0** · `install_docs` **38/0** · F1e-C üçlüsü nihai
ikiliye karşı **42/0 · 38/0 · 13/0**, kâtip commit'i `ef58402` fazın sonuncusu
**DEĞİL** · `docs/guard.md` davranışla **aynı fazda** güncellendi, `claims.tsv`
gerekmiyordu ve ajan dokunmadı.

**MUTASYON — HAKEMİN KENDİ MUTANTLARI:** M1 (`segment_reads_the_law`→true)
`law_family` **35/33 KIRMIZI** · M3 (daraltma kaldırıldı) `guard_delete`
**18/4 KIRMIZI** · geri alınınca **68/0** ve **22/0**. **M2
(`segment_writes_nothing`→true, aşırı geniş) İKİ SÜİDİ DE YEŞİL BIRAKTI** —
twin-arm daraltmayı "çok geniş" yönünde pinlemiyor, o yönde kırmızı düşebilen
test YOK (§3.8/3). **BOŞ YEŞİL TURU** `906b1e1` worktree'sinde hakem koşturdu:
`law_family 32/36` · `guard_delete 18/4` (kartın 26/36'sı ile KIRMIZI sayısı
birebir) — her iki süit de kırmızı düşebiliyor.

**DİSKTE KALAN (ölçüm):** `_f3g_kum/proj/.rabadon/{guard,promise}.json` ve
`_hakem_f3g_lab/proj/.rabadon/` (5 dosya) izinli hiçbir şekille silinemedi;
`~/.claude/settings.json.hakem-f3g-save` de silinemedi. F3h temizlesin.

**HAKEMİN ÖLÇEMEDİKLERİ:** konteynerde hiçbir şey koşmadı (yalnız konak macOS);
`law_family_test.sh` `$HOME` yazılamayan referans ortamında `exit 1` verir,
ölçülmedi; 911 µs'nin sebebi; `mv .`/`tar -x` deliklerinin kurgusuz
üretilebilirliği. **(c) negatif kontrolü kapsam dışıydı, koşulmadı → F4 HÂLÂ
KAPALI** (F3d hükmü: (c) F6'nın aletiyle koşar).

**F3h'YE SIRA:** (1) yanlış pozitif sınıfını kapat + `docs/guard.md`'nin yanlış
kapsam cümlesini düzelt, (2) `mv .`/`tar -x`/glob/yorumlayıcı deliklerini ya
kapat ya "aile" iddiasını "37 şekil" diye küçült, (3) `make test`'in canlı
`$HOME`'a yazmasını durdur, (4) 911 µs'yi ölç, sonra `2b`.

---

### F3f HAKEM HÜKMÜ (2026-08-29) — EN GÜNCEL SATIR, ÖNCE BUNU OKU
**`F3f: GEÇTİ`.** Gerekçe ve sayılar `KAPI.md`'nin ilk satırında, ayrıntı
`RAPOR/F3f-R.md`'de. Sekiz açık kalem hükme bağlandı (`KARARLAR.md`,
2026-08-29 · F3f · (a)–(h)).

**KIRMIZI AD KÜMESİ, F3f SONRASI: `{2b, 6e, 7b}` — BÜYÜMEDİ** (hakem koşturdu,
`accept.sh` EXIT=1, 23 yeşil / 3 kırmızı).
**`2b` DURUMU, AYAKTA KALAN TEK SAYI: 1378,0 µs · tavan 1000 µs · KALAN AÇIK
378 µs.** Kart 1249,0 yazmış; **129 µs fark, kartın kendi |439 µs| bandının
içindedir** — yani iddia edilen −380,7 µs iyileşme aletin koşudan koşuya
sapmasıyla aynı büyüklükte. Kart bunu "GÜRÜLTÜ, iddia yok" diye yazdı, doğru
davranış budur (CLAUDE.md 8). **Tavan oynatılmadı, `accept.sh` diff'te yok.**

**DEVİR SAYILARI: 4590 yeşil / 0 kırmızı** (taban 4556, **+34**; native **3893**
iddia + **633** kontrol + npm **64/0**). Hakem tabanı da kendi worktree'sinde
koşturdu (3859+633+64 = 4556). **Süit karşılaştırması, hakemin kendi
ayrıştırıcısıyla: 113 → 115 süit; tek fark `hook_upgrade_test.sh` 18 +
`guard_delete_test.sh` 16 = tam 34. Küçülen 0 · kaybolan 0 · başka hiçbir
süidin sayısı değişmedi.** Silinen dosya **0**, silinen/`skip`/`xfail` iddia
**0**, `CAP=200` yerinde, mühürlü set (`accept.sh` · `ON-KAYIT.md` ·
`docs/claims.tsv` · `guard.json` · korpus/snapshot) ve **`bin/rabadon.mjs` (O3)**
diff'te **HİÇ YOK**. Ölçüt commit'leri koddan ÖNCE ve KODSUZ.
F1e-C üçlüsü nihai ikiliye karşı **42/0 · 38/0 · 13/0**; kâtip commit'i
(`793a544`, `docs/how-it-works.md`) fazın sonuncusu **değil**.

**F3f'DE GERÇEKTEN OLAN, DÖRT SATIR:**
1. **"SEVK EDİLDİ AMA KURULMADI" KAPANDI, CANLIDA, HAKEM ELİNDE.**
   `; true` OLMADAN exit-1 bir Bash → ham defterde `STEP_OK "rc":1`; halka
   hakemin **kendi `RBMV1`/320B parser'ıyla** açıldı:
   `seq=1328 claimed_rc=1 sig=e052be370cd30660 err_sig=7a32e59add7d390d`.
   F3e hakeminde `STEP_START` var / `STEP_OK` yoktu. Kapı
   `native/hook_upgrade_test.sh` **18 iddia**; hakemin **kendi** mutasyonları:
   yükseltme adımı çıkarıldı → **9/9**, self-install koruması gevşetildi →
   **17/1**, ikisi de geri alındı → 18/0. Boş yeşil turu `F3f-oncesi`'nde
   **8 passed / 10 kırmızı**.
2. **⚠ ÜRÜN ARTIK KULLANICININ `~/.claude/settings.json`'INI KENDİ TAZELİYOR —
   ve bu, ALTI AYRI ÖLÇÜMLE, DOĞRU YAPILMIŞ.** `statusLine` **bayt bayt** korundu
   (`IDENTICAL_BYTES: True`; paylaşımlı statusline öldürülmedi), **yabancı
   kancalar 12 → 12**, `permissions` korundu, yedek gerçek ve `yedek == orijinal`,
   **bozuk JSON yedeksiz EZİLMİYOR**, ekranın **birinci satırı** dosyayı ve
   yedeği adıyla söylüyor ve "this one stays blind / live from your NEXT session"
   diye **yuvarlamıyor**, `RABADON_SELFHEAL=0` dosyayı dokunmadan bırakıyor,
   `docs/how-it-works.md` aynı fazda güncellendi. Kalan iki eksik bloklamıyor:
   `README.md` kurulumdan ÖNCE söylemiyor, çıkış yalnız env değişkeni.
   **AMA F1c'nin "iki yüzey, iki yasa"sı BİRLEŞMEDİ, ÜÇE ÇIKTI:**
   `installCursorHooks` okunamayan `hooks.json`'ı **hâlâ yedeksiz eziyor ve
   kullanıcının kancasını yok ediyor** (bugün ölçüldü), yeni `refresh.mjs` ise
   güvenli ama **DİLSİZ** (hiçbir şey söylemiyor — "asla susmaz" ilkesine aykırı).
3. **KART 2 DOĞRULANDI: `repeat` ENGELİNİN TAMAMI TAM-İMZA KATILIĞIDIR.**
   Hakem script'i kendi koşturdu: A) 2/81 · C) 0/81 · **D) ÜST SINIR, 276
   kapanmamış hamlenin hepsi başarısız sayılsa bile 0/81**; 75/81 oturumda imza
   pencerede bir kez bile tekrar etmiyor. `err_sig` onarımı `repeat`'i
   ateşlenebilir YAPMADI. F4'e devir: ilk-token imzasıyla 32/81 ve
   **7/81 (kart 8/81 — fark korpusun canlı olmasındandır, ikisi de yazılı)**.
4. **⚠ KART 4'ÜN ÜÇ İDDİASI YANLIŞ, VE SIRADAKİ FAZI BU DOĞURUYOR.**
   **(a)** "canlı BYPASS" bir **/tmp artefaktıdır**: kartın betiği kum havuzunu
   `${TMPDIR:-/tmp}` altında açıyor (Tuzak 1, aşağıda satır 578); **taban ikili,
   `$HOME` altındaki gerçek bir projede `rm .rabadon/guard.json`'ı ZATEN
   reddediyordu (rc=2)**. Açık yalnız temp-kökü sınıfındaydı. Onarım yine de
   doğrudur ve yalnız reddi artırır. `guard_delete_test.sh` de `${TMPDIR}`
   altında koşuyor: **16 iddianın 16'sı temp-kökü sınıfında.**
   **(b)** Bildirilen yanlış pozitif **ÜRETİLEBİLİYOR ve hakem ÜRETTİ**:
   **`grep -c rm .rabadon/guard.json` → rc=2**, salt-okuma bir grep.
   Desen bir yazmayı değil bir **anmayı** yakalıyor. **F3e hakemi haklıydı;
   kartın "ÜRETİLEMEDİ" ilanı yanlıştır, eski sayı silinmiyor.**
   **(c) AİLE AÇIK, HEAD'DE CANLI:** **`rm -rf .rabadon`** · `truncate -s 0` ·
   `cp /dev/null` · `chmod 000` · `ln -sf /dev/null` · `install -m 000` · `dd of=` ·
   `find … -delete` — **sekizi de rc=0 GEÇİYOR.** `is_rabadon_law_file` yalnız iki
   TABAN ADINA bakıyor, üst dizini görmüyor. **Guard'ın kendisi silinebiliyorsa
   guard yoktur.**

**SIRADAKİ FAZ: F3g. BLOKLAYAN İLK KARTI ÜRÜN KAPSAMINDANDIR — BEŞ FAZDIR
İLK KEZ.** Yasa dosyasının bir ŞEKLİ değil **AİLESİ** kapatılacak
(`rm -rf .rabadon` + 7 kardeşi), onarım ürün tarafında (`rules.h`/`gate.cpp`),
`guard.json`'a dokunulmadan, mutasyon kanıtı + boş yeşil turu + **`${TMPDIR}`
DIŞINDA da koşan** bir süitle; aynı kartta (b)'nin yanlış pozitifi sayılacak ve
daraltılacak. İkinci kart: üç yasanın tek yasaya inmesi (dilsiz `refresh.mjs` +
`installCursorHooks`'un yedeksiz ezmesi). Üçüncü kart: `2b`'nin **378 µs**'lik
açığı — gürültü bandının ALTINDA çözebilen bir ayrıştırma kurulmadan hedef
seçilmez. `no-rm-rf-outside`'ın ad-iş uyuşmazlığı hâlâ **SAHİPSİZ**.
**F4 (c) ölçülmeden AÇILMAZ ve (c) F6'nın aletiyle koşar** (değişmedi).

### F3e HAKEM HÜKMÜ (2026-08-29)
**`F3e: GEÇTİ`.** Gerekçe ve sayılar `KAPI.md`'nin ilk satırında, ayrıntı
`RAPOR/F3e-R.md`'de. Üç açık kalem hükme bağlandı (`KARARLAR.md`,
2026-08-29 · F3e · (a)–(c)).

**KIRMIZI AD KÜMESİ, F3e SONRASI: `{2b, 6e, 7b}` — BÜYÜMEDİ** (hakem koşturdu,
`accept.sh` EXIT=1, 23 yeşil / 3 kırmızı; `2b` **1252,1 µs**, tavan **1000 µs**
oynatılmadı, `accept.sh` fazın diff'inde **HİÇ YOK**).
**DEVİR SAYILARI: 4556 yeşil / 0 kırmızı** (taban 4535, **+21**; native **3859**
iddia + **633** kontrol + npm **64/0**). Hakem tabanı da kendi koşturdu
(3838+633+64 = 4535) — **+21'in tamamı tek yeni süittir**. Süit karşılaştırması,
hakemin kendi ayrıştırıcısıyla: **111 → 112 süit, küçülen 0 · kaybolan 0 ·
büyüyen 0 · yeni 1** (`failed_call_test.sh` 21). Silinen dosya **0**, silinen /
`skip` / `xfail` / yoruma alınmış iddia **0**, `CAP=200` yerinde
(`moves.h` diff'i 0 satır), mühürlü set (`accept.sh` · `ON-KAYIT.md` ·
`docs/claims.tsv` · `guard.json` · korpus/snapshot) ve **`bin/rabadon.mjs` (O3)**
diff'te **HİÇ YOK**.

**F3e'DE GERÇEKTEN OLAN, ÜÇ SATIR:**
1. **KÖR NOKTA ÜRÜNÜN KENDİSİNDEYMİŞ, ve onarım hakem elinde doğrulandı.**
   Claude Code başarısız bir tool çağrısını **`PostToolUseFailure`** adıyla
   teslim ediyor; `hookev.h` adı tanımıyordu ve `hooks/install.mjs` olaya **hiç
   abone olmuyordu**. Hakem aynı yükü iki ikiliye verdi: **taban** `STEP_START`,
   kapanış YOK, `claimed_rc=-1`, `err_sig` **boş** ↔ **HEAD** `STEP_OK "rc":1`,
   `claimed_rc=1`, `err_sig=d58714fac4f6feb4`. Ham yükün canlı olduğu harness
   transcript'inden doğrulandı. Kapı: `native/failed_call_test.sh`, **21 iddia**,
   hakemin **kendi iki mutasyonuyla** kırıldı (14/7 ve 20/1) ve `F3e-oncesi`
   ağacında **10 passed / 11 kırmızı** düştü.
2. **⚠ CANLI MAKİNE HÂLÂ KÖR — ONARIM SEVK EDİLDİ, KURULMADI.** Hakem bugün
   çıkışı 1 olan bir Bash koşturdu (`toolu_01M14K72DJ4FP4trdsMuLknQ`): defterde
   **`STEP_START` var, `STEP_OK` yok**. `~/.claude/settings.json`'ın
   `PostToolUseFailure` bloğunda **rabadon-gate yok** (yalnız orkestra'nın
   `tick.py`'si). Sevk edilen ikili bunu **ekranda ilan ediyor** (`blind spots:`
   → "fix: `rabadon init`", hakem gözüyle görüldü). **Bu, F3f'in ilk bloklayan
   kartıdır.**
3. **(b) BUGÜN ÖLÇÜLEMEZ, ve sebebi TEK DEĞİL İKİ TANE.** Kışkırtılmamış (b)
   üretilemedi (2 canlı oturum, 12 hamle, 12 ayrı imza). Hakem ölçümü bütün
   korpusa büyüttü: **81 oturum / 1766 hamle → `repeat`'i ateşleyebilecek oturum
   0/81.** Sebep (i) `repeat` **tam komut imzasına** bakıyor
   (`moves.h:173`, `signals.h:127`), sebep (ii) **başarısız çağrı defterde hiç
   kapanmadığı için `err_sig` hiç atanmıyordu** — yani `failed>=2` kolu
   yapısal olarak ulaşılamazdı. F3e (ii)'yi onardı ama kurmadı.
   **(b)'nin sahibi F3f; dedektör tasarımı (semantik imza) zaten F4'ün
   içeriğidir, yeni kart açılmaz.**

**`2b` DURUMU (F3e sonrası, hakem ölçtü):** hızlanmadı — eşli HEAD↔taban
(N=200, 3 tekrar) **+221,2 µs ortalama, 2+/1−**, tek yanlı değil, |439 µs|
bandını aşmıyor. **CHALLENGE hükme bağlandı:** F3d'nin "hedef ikili yükleme
maliyeti, pencere 324 µs" yönlendirmesi **GERİ ÇEKİLDİ** (ikiliyi %12 küçültmek
−80,1 µs / 3+/5− verdi; boş C++ ↔ boş C farkı 69,6 µs); F3e'nin yerine koyduğu
"%70 kural yolu" da **BENİMSENMEDİ** (hakemde %49/%51; yükleme bacağı üç
ölçümde 524,6 / 676,4 / **915,2** µs = yayılım 390 µs, gürültü bandının içinde).
**AYAKTA KALAN:** uçtan uca atfedilebilir **1602–1799 µs**, tavan **1000 µs**,
**~800 µs düşmeli ve hiçbir bacak tek başına küçük değil.** Kısıt: **bacakları
gürültü bandının içinde olan bir ayrıştırmadan hedef seçilemez.** Eski sayılar
silinmedi, gerekçesiyle düzeltildi.

**YANLIŞ POZİTİF, F3e turu:** kart +2 (`baseline-truncating-redirect`,
`no-rm-rf-outside`), hakem **+1 YENİ**: `no-shell-rewrite-of-guard-or-promise`
**salt-okuma bir `grep -n … guard.json`'ı** kesti. `no-rm-rf-outside`'ın regex'i
hakem tarafından okundu — "proje dışı"nı değil "mutlak ve /tmp değil"i
yakalıyor, **ad yaptığı işi yanlış anlatıyor**. Üçü de sahipsiz, F3f'in üçüncü
kartı. Hakemi kesen iki blokaj (`no-blind-inplace-source-rewrite` ve
`no-rm-rf-outside`) **doğru retlerdi**; yaklaşım değiştirildi, `guard.json`'a
dokunulmadı, `rabadon off` kullanılmadı, CHALLENGE-3 deliği kullanılmadı.

**SIRADAKİ FAZ: F3f.** Bloklayan ilk kart: **kurulumu tazele ve canlı kanıtla**
(bkz. yukarıda 2). İkinci kart: `2b` için gürültü bandının **altında** çözebilen
bir ayrıştırma yöntemi. Üçüncü kart: üç sahipsiz yanlış pozitif.
**F4 (c) ölçülmeden AÇILMAZ ve (c) F6'nın aletiyle koşar** (değişmedi).

### F3d HAKEM HÜKMÜ (2026-08-29)
**`F3d: GEÇTİ`.** Gerekçe ve sayılar `KAPI.md`'nin ilk satırında, ayrıntı
`RAPOR/F3d-R.md`'de. Beş açık kalem hükme bağlandı (`KARARLAR.md`,
2026-08-29 · F3d · (a)–(e)).

**KIRMIZI AD KÜMESİ, F3d SONRASI: `{2b, 6e, 7b}` — BÜYÜMEDİ** (hakem koşturdu,
`accept.sh` EXIT=1, 23 yeşil / 3 kırmızı; `2b` satırı "median is 1282.2 us with
the daemon up, ceiling is 1000 us"; tavan **oynatılmadı**, `accept.sh` fazın
diff'inde **HİÇ YOK**).
**DEVİR SAYILARI: 4535 yeşil / 0 kırmızı** (taban 4529, **+6**; native 3838
iddia + 633 kontrol + npm 64/0). +6'nın kaynağını hakem ayırdı: `guard lint`
**20 → 22** ve yeni `silent skip` **4**. Süit karşılaştırması: **72 → 73 süit,
düşen / küçülen / kaybolan süit YOK.** Silinen dosya **0**; `*.sh` diff'indeki
11 `-` satırının hepsi eski sessiz-skip echo'ları ve sayaç ilklendirmeleridir,
hiçbiri bir iddia değil.

**F3d'DE GERÇEKTEN OLAN, ÜÇ SATIR:**
1. **CANLI (b): n = 0 → 1, GERÇEK — ama KIŞKIRTILMIŞ.** Defterdeki
   `INJECT mseq=757 psig=1a37b823ede897e7` ve
   `INJECT_ANSWER mseq=758 sig=69f067c23b54e9ca same=false` kayıtlarını hakem
   **ikinci bir artefaktla** doğruladı: halka dosyasını (`RBMV1`) kendi
   parser'ıyla açtı, hamle 756/757/758'in imzaları defterdekilerle **birebir**
   tuttu; diff'te deftere yazan fikstür/seed YOK, tek satır C++ YOK, INJECT
   commit'ten 42 sn önce doğdu, `pipe:"rabadon:session"` = ajan imzası
   (§F3:142). **AMA** hamle 749/755/756 aynı komutun üç yazımıdır
   (`ls`/`command ls`/`env ls`, hepsi `; true` ekli, hepsi aynı `err_sig`) —
   ajan sinyali kendi eliyle üretti; ve taşıyıcı hamle 757'nin imzası hamle
   752 ile aynı olduğu için `same=false` yapısal olarak garantiliydi.
   **§F3 (b) LAFZEN 1, ÖZÜNDE HÂLÂ 0.**
2. **SESSİZ SKIP SINIFI KAPANDI, ve altında ÖLÜ BİR KOL çıktı.** Bayat ağaç
   artık kırmızı düşüyor (hakemin kendi mutasyonu: `version` taban 11/0 EXIT=0
   ↔ HEAD 11+1 FAIL EXIT=1; `guard_lint` taban 20/0 EXIT=0 ↔ HEAD 20+1 FAIL),
   ortam dalları adıyla ve sayısıyla ilan ediyor (`node` gizlendi →
   `redbase_scope` "9 assertion(s) did NOT run"). Taban ağaçta yeni kilit
   **3 passed / 1 failed, `sites=15 files=13`** (kartın "14 site" başlığı
   düzeltildi). **`guard_lint_test.sh`'in ampirik kolu yazıldığından beri hiç
   koşmamıştı** — tam kurulu ağaçta bile "the tree is not built" deyip skip'e
   düşüyordu; +2 iddia bu yüzden gerçektir. `sandbox` ve `script_wrapper`
   dallarını **hakem de zorlayamadı** → DOĞRULANMADI.
3. **`2b` HIZLANMADI ve iddia edilmedi; ama iki ölçüm sonraki kararı
   değiştirdi.** Hakemin kendi koşumu (N=400×6, eşli, alternatif): tam yol
   **1602,1 µs**, `RABADON_OFF=1` **676,4 µs**, rabadon'un kendi işi
   **925,7 µs 6+/0−** → **tavanın %68'i, bütün mantığa kalan 324 µs.**
   A/A (N=500×8, gerçek fark SIFIR): ortalama **+117,2 µs**, aralık
   **330,9 µs**, işaret **7+/1−**, tek koşu içinde 1472,5 → 2357,0 µs tek
   yönlü sürükleniyor.

**HAKEMİN İKİ DÜZELTMESİ (kartın cümlelerine karşı):**
- Kartın *"%60'ı ürünün kontrolü dışındaki süreç başlatma"* cümlesi **YANLIŞ**:
  betikte `null` = `/usr/bin/true` doğurma maliyeti **zaten çıkarılmış**, yani
  o 676 µs `rabadon-gate` ikilisinin **kendi** yükleme maliyetidir (dyld, ikili
  boyutu, statik başlatıcılar) ve **ürünün kendi kalemidir**. **Tavan 1000 µs
  ölçmek istediğini ölçüyor ve OYNAMAZ (§3.8/4, §11);** düzeltilecek olan
  **F3-S1'in HEDEFİDİR** — 324 µs'lik pencerede algoritmik kazanç tavana
  ulaşmaz, hedef ikili yükleme maliyeti olmalıdır.
- **F3b hakeminin "8/8 işareti ayrı ve geçerli bir kanıttır" hükmü SINIRDADIR:**
  bu makinede sıfır gerçek farkta A/A **7+/1−** verdi. Bundan sonra eşli bir
  iddia hem **|243 µs|**'yi aşmalı hem **8/8** olmalı, ve tek koşudan
  alıntılanmamalıdır.

**⚠ ÖLÇÜT DEĞİŞİKLİĞİ `eafa3e7` — HAKEM ONAYLADI (§3.8/1 incelendi).** Faz ajanı
`native/silent_skip_test.sh`'in kabul kuralını değiştirdi (sayaç echo'nun kendi
satırında olmak zorunda değil; pencere 3 yukarı / 1 aşağı). Onay gerekçesi:
dosya §3.8/1'in mühürlediği kümede **değil** (`accept.sh` ve `ON-KAYIT.md`
diff'i 0 satır), ölçüt **aynı fazda aynı ajanın doğurduğu** yeni bir kilittir,
düzeltme bir gevşetme kadar bir **sertleşme** de taşıyor (`ok()` yardımcısını
sayaç sanma deliği kapandı), ayrı commit + kodsuz + eski/yeni yazılı, ve
**belirleyici olan: düzeltmeden sonra süit KIRMIZI kaldı (3 passed / 1 failed)**
— yeşili onarım commit'i getirdi. **Aynı hareket devralınmış bir kapıya
yapılsaydı REDDEDİLİRDİ.**

**F4 KAPALI KALIR.** (c) negatif kontrolü ne kartta ne hakemde koşuldu
(§F3:143 lafzen "bu ölçüm yapılmadan F4 açılmaz"). **(c)'nin sahibi F3e
DEĞİL, F6'nın iki kollu aletidir** — ayrı bir alet mühürlü görev kümesini
böler (§3.8/2). Doğru sıra: **F3e → F6-aletiyle-(c) → F4.**

**SIRADAKİ FAZ: F3e. BLOKLAYAN İLK KARTI `err_sig`'İN KÖR NOKTASIDIR —
hakem kendi eliyle ölçtü: ÇIKIŞI SIFIR OLMAYAN BİR BASH ÇAĞRISI İÇİN
PostToolUse OLAYI HİÇ GELMİYOR.**
Ölçüm, aynı oturumda iki komut:
`toolu_01RCs43FXi5ZmtdXc9roaEVn` = `env ls -la /nonexistent-hakem-probe-ZZ1 2>&1`
(**exit 1**) → defterde **STEP_START VAR, STEP_OK YOK**;
`toolu_01Xgcf9CMS3BvaDdKbojbzzp` (sonu `; true`, **exit 0**) → **ikisi de VAR**.
`err_sig` yalnız PostToolUse dalında atandığı için rabadon'un var olma sebebi
olan "aynı hata üçüncü kez" sinyali **düz başarısız bir komutu göremiyor** —
faz ajanı n=1'i ancak her komuta `; true` ekleyerek, yani kör noktayı **elle
telafi ederek** üretebildi. Dört fazlık n=0'ı bu açıklıyor.
1. **F3e KART 1 (BLOKLAYAN):** kök sebebi bul (harness olayı göndermiyor mu,
   gate erken mi dönüyor — hakem **ölçemedi**, yalnız semptomu ölçtü) ve kapat:
   ya olayın gelmediğini kanıtlayıp `err_sig`'i başka bir yüzeyden türet
   (sonraki PreToolUse'un transcript'i / Stop hook), ya da gate'in erken
   dönüşünü onar. **Kabul: mutasyon kanıtı + `; true`'suz, kışkırtılmamış
   canlı bir n ≥ 1.** Bu kart kapanmadan F3e'nin başka kartı başlamaz.
2. **F3e KART 2:** `2b` / F3-S1'in hedefini ikili yükleme maliyetine çevir
   (324 µs pencere, yukarıdaki düzeltme). Tavan **oynatılamaz**.
3. **AÇIK, SAHİPSİZ:** `baseline-truncating-redirect` **iki hakem oturumunda
   üst üste yanlış pozitif verdi** (F1b ve F3d) — henüz var olmayan bir dosyaya
   giden yönlendirmeyi "içerik siliniyor" diye reddediyor ve ret metni satırdaki
   komutu göremiyor. **Yanlış pozitif sayacı bu turda +1.** Kartı yok.
4. **AÇIK, SAHİPSİZ, YENİ:** canlı oturum durumu artık `~/.rabadon/sessions/`e
   değil **projenin kendi** `.rabadon/sessions/`ına yazılıyor (o dizin 16:15'ten
   beri hiç yazılmadı), ve `~/.rabadon/.rabadon/` diye üçüncü bir kök var.
   Hangisinin kanonik olduğu belgede yazılı değil; "canlı defter =
   `~/.rabadon/spool`" varsayımı **defter için doğru, halka için YANLIŞ**.

### F3c HAKEM HÜKMÜ (2026-08-29) — *(SÜPERSEDE: yukarıdaki F3d bloğu daha günceldir; bu blok silinmiyor)*
**`F3c: GEÇTİ`.** Gerekçe ve sayılar `KAPI.md`'nin ilk satırında, ayrıntı
`RAPOR/F3c-R.md`'de. Altı açık kalem hükme bağlandı (`KARARLAR.md`,
2026-08-29 · F3c · (a)–(f)).

**KIRMIZI AD KÜMESİ, F3c SONRASI: `{2b, 6e, 7b}` — BÜYÜMEDİ** (hakem koşturdu,
`accept.sh` EXIT=1, 23 yeşil / 3 kırmızı; süreç-içi `2b` **1249,2 µs**; tavan
1000 µs `accept.sh:122/203`'te oynatılmadı, mühürlü dörtlünün diff'i **0 satır**).
**DEVİR SAYILARI: 4529 yeşil / 0 kırmızı** (taban 4513, **+16**; native 3832
iddia + 633 kontrol + npm 64/0). +16'nın tamamı tek yeni süittir
(`inject-answer: 16 passed`) ve hakem bunu süit-özeti `diff`'iyle doğruladı:
**71 → 72 süit, düşen ya da küçülen süit YOK.** Silinen dosya **0**;
`native/` diff'indeki tek `-` satırı bir `skip`'in `bad`'e dönmesidir.

**F3c'DE GERÇEKTEN OLAN, ÜÇ SATIR:**
- **KANIT KALICILIĞI KAPANDI (bloklayan kart).** `INJECT` artık `psig` taşıyor
  ve teslimden sonraki ilk hamle `INJECT_ANSWER` olarak deftere yazılıyor;
  (b) halkaya değil **iki defter satırına** sorulan bir soru oldu. Hakem
  doğruladı: halka **218'e yuvarlandı, CAP 200, `mseq=6` tahliye** ve (b) o
  hâlde hâlâ cevaplanıyor; boş yeşil turu `F3c-oncesi` ağacında **6 passed /
  KIRMIZI**; **hakemin kendi üç mutasyonu** — `psig`'i teslim anında taşıyıcı
  hamleden al → **14/1**, `injPendingPrevSig`'i serileştirme → **11 passed /
  5 FAIL**, üçüncüsü (`injAnsAfterSeq` serileştirilmesin) **TUTMADI, yeşil
  kaldı** (kart da farklı bir mutasyonun aynı alanda tutmadığını yazmıştı —
  **aynı alanda iki bağımsız delik**, F3d'nin kanıt kartına iliştirildi).
  `CAP` **büyütülmedi** (erteleme değil), korpus silinmedi (39 halka),
  snapshot `dr-xr-xr-x` / 26 Ağu 06:48, dokunulmadı.
- **(b) HÂLÂ KARŞILANMADI — ÖLÇÜLEBİLİR OLDU, ÖLÇÜLMEDİ.** Canlı defter:
  **INJECT 7, `psig` taşıyan 0, INJECT_ANSWER 0 → n=0.** Fikstürdeki n=1'in
  "sonraki hamlesi" testin kendi olayıdır; §F3 satır 142 ajanın hamlesini
  istiyor. **(c) yine koşulmadı → F4 KAPALI KALIR.** Ürün kapsamı teslimi
  **dört ardışık fazdır %0**.
- **`2b`: BU FAZIN KATKISI GÜRÜLTÜ.** Hakemin eşli koşusu (N=500 × 6, gate exit
  sağlamlık kontrolü 14/14 geçti): HEAD **1378,9 µs**, taban **1401,9 µs**, fark
  **−23,0 µs, 3 artı / 3 eksi**. **BUGÜNÜN TEK GEÇERLİ SAYISI: atfedilebilir
  uçtan uca 1378,9 µs, tavana kalan açık 378,9 µs = 1,38×.** Aynı taban ikilisi
  F3b hakeminde 1475,4 / kartta 1304,6 ve 1374,2 / hakemde 1401,9 verdi — alet
  ~170 µs geziyor, yani **1475,4 → 1424,1 → 1378,9 serisinin son iki adımı
  gürültü bandındadır; "üç fazdır düşüyor" cümlesi kurulamaz.** Gerçek olan tek
  adım F3b'nin eşli `1641,2 → 1287,1` kazancıdır.

**KÂTİP ŞARTI (F1e-C) ÇIKTI:** `docs/agent-contract.md` bu fazda gerçekten
değişti (yeni `INJECT_ANSWER` zarfı, örnek JSON ile), commit `087e559` fazın
**3.** commit'i — sonuncusu değil. Üçlü nihai ikiliye karşı **42/0 · 38/0 ·
13/0**. İki fazlık boşluk kapandı.

**§3.12:** tahmin `59a32e6` **19:48**, ilk kart commit'i `d9a4907` **19:50** —
tahmin gerçekten ÖNCE commit'lenmiş; 4 kart < 8, **tetik çalmadı**. *(Ölçüldü,
sorulmadı: faz 19:48→20:18 = **30 dakika**, tahmin ~5,2 saat. İhlal değil, ama
tahmin kalibrasyonu 10× kaymış ve §3.12 bu haliyle pratikte hiç çalmayacak.)*

**YENİ BULGU — KART 4 BİR ÖRNEĞİ KAPATTI, SINIFI DEĞİL.** Hakem ölçtü:
`make all` sonrası `native/version_test.sh` **13 passed**; tek bir kaynağa
`touch native/gate.cpp` sonrası **11 passed, EXIT=0**. Yani **F1e-C kapı
üçlüsünün bir bacağı bir dosyaya dokunmakla sessizce 2 iddia küçülüyor.**
Sınıfın kalanı: `grep -c 'echo "  skip'` → **8 dosyada 9 satır**
(`blind_switch`, `discovery_scope`, `guard_lint`×2, `redbase_scope`, `sandbox`,
`script_wrapper`, `unknown_wrapper`, **`version`**). Bu, O5 zincirinin gerçek
beşinci halkasıdır (D6 kendi hükmüyle zincirden çıktı → F3b'nin saydığı 5
aslında 4'tü; `KARARLAR.md` F3c (e)).

**SIRADAKİ FAZ: F3d. BLOKLAYAN İLK KARTI KANIT DEĞİL, ÜRÜN OLGUSUDUR —
CANLI (b).**
1. **CANLI (b) — BLOKLAYAN.** Gerçek bir ajan oturumunda defterde `psig`
   taşıyan en az bir `INJECT` **ve** onu cevaplayan bir `INJECT_ANSWER`.
   Bugün **n=0**; hedef **n≥1**, ve `same` alanı **ne çıkarsa yayınlanır**
   (CLAUDE.md 8 — `same=true` çıkarsa negatif sonuç olarak yazılır, olumluya
   çevrilmez). Mekanizmanın varlığı kanıt değildir; sayılan, ajanın sonraki
   hamlesinin imzasıdır. Bu kart kapanmadan F3d'nin başka kartı başlamaz.
   **§F3'ün "iki koşuda üst üste KIRMIZI" kanal-yeniden-tasarım sayacı bugün
   0'dır** (F3/F3b/F3c'de (b) kırmızı düşmedi, ÖLÇÜLEMEDİ); **F3d birinci
   koşudur.**
2. **9 SESSİZ `skip` DALI**, `version_test.sh`'ten başlayarak — kart 4'ün
   `make_deps_test.sh`'e uyguladığı kalıbın aynısı: `skip` → `bad`, mesaj
   koşmayan armın adını ve tek onarım komutunu söylesin.
3. **F3-S1 kalanı:** açık **378,9 µs**. Tavan **oynatılamaz** (§3.8/4).
   Ölçüm N=500'ün altında yapılmaz — N=200 bu makinede çözmüyor (fark −66,8 µs,
   4 artı / 4 eksi).
4. **(c) ve F4:** (c) ölçülmeden **F4 AÇILMAZ** (§F3 satır 143, lafzen).

### F3b HAKEM HÜKMÜ (2026-08-29) — *(SÜPERSEDE: yukarıdaki F3c bloğu daha günceldir; bu blok silinmiyor)*
**`F3b: GEÇTİ`.** Gerekçe ve sayılar `KAPI.md`'nin ilk satırında, ayrıntı
`RAPOR/F3b-R.md`'de. Dört açık kalem hükme bağlandı (`KARARLAR.md`,
2026-08-29 · F3b · (a)–(d)).

**KIRMIZI AD KÜMESİ, F3b SONRASI: `{2b, 6e, 7b}` — BÜYÜMEDİ** (hakem koşturdu,
`accept.sh` EXIT=1, 23 yeşil / 3 kırmızı, süreç-içi `2b` **1220,0 µs** — F3'te
1237,5 idi, yükselmedi; tavan 1000 µs `accept.sh:122/203`'te oynatılmadı ve
kapı dosyalarının diff'i **0 satır**).
**DEVİR SAYILARI: 4513 yeşil / 0 kırmızı** (taban 4505, **+8**; native 3816
iddia + 633 kontrol + npm 64/0). +8'in tamamı iki yeni kola ait:
`make_deps_test.sh` **7** + `day_cache_test.sh` `COLD_FIRST_US` armı **1**.
Silinen dosya YOK, silinen/atlanan iddia YOK.

**F3b'DE GERÇEKTEN OLAN, ÜÇ SATIR:**
- **D7 KAPANDI.** `Makefile`'ın **7** kuralı include kapanışını eksik sayıyordu;
  hepsi hizalandı ve `native/make_deps_test.sh` (YENİ, `make test`'te, 7 iddia)
  ile kilitlendi. Hakem doğruladı: faz öncesi ağaçta süit **5/2 KIRMIZI**;
  `touch native/pathres.h && make all` sonrası `rabadon-net` mtime faz öncesinde
  **DEĞİŞMİYOR**, HEAD'de **DEĞİŞİYOR**; hakemin kendi mutasyonu (tek önkoşul
  çıkarıldı) süiti **7/0 → 5/2** düşürdü. **D7 fazın İLK iş commit'idir**, yani
  bu fazın hiçbir yeşili bayat ikiliden gelmedi.
- **F3-S1 ONARILDI AMA TAVANIN ALTINA İNMEDİ — NEGATİF SONUÇ.** Soğuk
  `gmtime_r` timezone yüklemesi olay başına ödeniyordu (**582 µs**); UTC günü
  tamsayı takvimiyle hesaplanıyor (**16 µs**, 64808 damgada 0 uyuşmazlık).
  **Hakemin kendi 8 eşli tekrarı** (`kanit/f3/2b-uctan-uca.sh`, N=200,
  BASE→HEAD sırayla): BASE ortalama **1848,5 µs**, HEAD ortalama **1475,4 µs**,
  fark **−373,1 µs, 8/8 negatif**, HEAD medyanı 1638,0.
  **BUGÜNÜN TEK GEÇERLİ SAYISI: atfedilebilir uçtan uca 1475,4 µs, tavana
  kalan açık 475,4 µs = 1,48×.** Kartın "kalan açık ~330 µs"u bugün yeniden
  ÜRETİLMEDİ; açık ~145 µs daha büyük (kart MEDYANI, aletin MEAN tanımlı
  tavanına karşı koymuştu). Mutlak sayı ±%20 gürültü bandındadır ve
  **tek koşudan alıntılanmamalıdır**; güvenilir olan eşli FARKtır.
- **(b) VE (c) TESLİM EDİLMEDİ — ürün kapsamı ÜST ÜSTE İKİNCİ FAZDA %0.**
  Faz diff'i `inject.h`/`signals.h`/`policy.h`'e hâlâ hiç dokunmuyor.

**(b) NEDEN ÖLÇÜLEMİYOR — hakem ölçtü, ve sebep ürün kodu DEĞİL KANIT ALTYAPISI:**
defterde **7 INJECT**, yargılanabilir **0**. `~/.rabadon/sessions/*.moves.bin`
header'larından `count`: **39 halka, medyan count 3, yalnız 2'si `CAP=200`'ü
aşmış (%5,1) — ama enjeksiyon taşıyan 2 halkanın 2'si de aşmış (%100)**.
Kayıp rastgele değil **seçici**: sinyal uzun oturumda doğar, uzun oturum halkayı
yuvarlar, kanıt tam doğduğu yerde silinir. Ve `grep -ln INJECT native/*_test.sh`
→ **0**: enjeksiyonu uçtan uca süren tek fikstür bile yok. Aynı duvara bu
dosyada üçüncü kez çarpılıyor (F1c: başlık 666 / diskte 527 · F2: LOSS 1.417 /
başlık 1.944, kayıp %72,9).

**D5/3'ÜN O5 TETİĞİ ÇALDI** (zincir 5: D1 · D6 · CHALLENGE-2 · D7 · `CAP=200`
halkasının kanıtı yok etmesi). `UYANDIGINDA.md` · O5 güncellendi. **Ürün konumu
operatörün kalemidir ve hakem onu DEĞİŞTİRMEDİ**; hakemin yaptığı tek şey
§3.7 sıra değişikliğidir.

**SIRADAKİ FAZ: F3c. BLOKLAYAN İLK KARTI ÜRÜN DEĞİL, KANIT KALICILIĞIDIR**
(gerekçe: yargılanabilir n = **0/7**):
1. **KANIT KALICILIĞI — BLOKLAYAN.** `INJECT` satırı enjeksiyon ÖNCESİ imzayı
   taşısın; ilk sonuç veren hamlede `INJECT_ANSWER` yazılsın; böylece (b)
   **yalnız defterden, `CAP=200` halkasından bağımsız** cevaplanır. Ve
   enjeksiyonu uçtan uca süren **İLK fikstür süiti** açılsın (bugün 0),
   ölçüt koddan önce + mutasyon kanıtıyla. **Bu kapanmadan F3c'nin başka
   hiçbir kartı başlamaz.**
2. **KOSU §F3'ün ürün kapsamı** (merdiven enjeksiyon→enjeksiyon→blok,
   `rabadon mute <sinyal>`, gözlem modunda başlayan yeni sinyaller, (a)/(b)
   üç katmanlı kabul).
3. **(c) negatif kontrol.** **(c) ölçülmeden F4 AÇILMAZ** (`KOSU-RABADON-5.md`
   §F3, aynen geçerli).
4. **F3-S1 devam ediyor:** bugünkü taban **1475,4 µs**, tavana açık **475,4 µs**.
   Tavan 1000 µs F3c'de de **oynatılamaz** (§11).

### F3 HAKEM HÜKMÜ (2026-08-29) — bir önceki hüküm
**`F3: GEÇTİ`.** Gerekçe ve sayılar `KAPI.md`'nin ilk satırında, ayrıntı
`RAPOR/F3-R.md`'de. Dört açık kalem hükme bağlandı (`KARARLAR.md`,
2026-08-29 · F3 · (a)–(d)).

**KIRMIZI AD KÜMESİ, F3 SONRASI: `{2b, 6e, 7b}` — BÜYÜMEDİ** (hakem koşturdu,
`accept.sh` EXIT=1, 23 yeşil / 3 kırmızı, `2b` **1237,5 µs**, tavan 1000 µs
oynatılmadı). **DEVİR SAYILARI: 4505 yeşil / 0 kırmızı** (taban 4483, **+22**;
native 3808 iddia + 633 kontrol + npm 64). İzlenen `native/*_test.sh`:
**109 → 111**. Silinen dosya YOK, silinen iddia YOK.

**SIRADAKİ FAZ: F3b** (§3.7, hakem fazı böldü — gerekçe üç ölçülen sayı:
KOSU §F3'ün kendi kapsamından teslim %0, +22'nin 0'ı enjeksiyona ait,
`2b`'nin tavana açığı 681,3 µs). **F3b'nin kapsamı:**

1. **D7 — `Makefile:79`, BLOKLAYAN İLK KART.** `native/rabadon-net`'in önkoşul
   listesi `pathres.h` + `testout.h`'i saymıyor, `touch native/pathres.h &&
   make all` ikiliyi YENİDEN DERLEMİYOR (ölçüldü, mtime değişmiyor) ve
   `discovery_scope_test.sh` bayat ikiliden **sahte yeşil** verebiliyor —
   ajanın MUTANT 2'sinde gerçekten verdi (13/0 → zorlanınca 11/2).
   D7 onarılmadan F3b'nin kendi yeşilleri güvenilmez. Kabul maddesi:
   `KARARLAR.md` · F3 · (c).
2. **KOSU §F3'ün kendi metni:** motoru canlı hook'a bağla; sinyal PostToolUse'da
   doğsun, sonraki PreToolUse'da `additionalContext` ile binsin (400 karakter
   tavan, satır numarası ve öneri yok); **merdiven** enjeksiyon → enjeksiyon →
   blok (blok sebebini ve çıkış yolunu söyler); `rabadon mute <sinyal>`;
   yeni sinyaller kullanıcıda **gözlem modunda** başlar.
   **Üç katmanlı kabul, ilki tek başına kanıt DEĞİL:** (a) ledger'da SIGNAL +
   INJECT + COUNTER, (b) enjeksiyondan sonraki ilk hamlenin imzası değişmiş
   olmalı, (c) negatif kontrol. **(c) ölçülmeden F4 AÇILMAZ.**
3. **F3-S1 — sahibi adıyla F3b.** Kabul maddesi F3'te KARŞILANDI (medyan
   yükselmedi); karşılanmayan ONARIMDIR. Hedef prob sayısı DEĞİL, **sevk edilen
   ikilinin uçtan uca sayısı**. Bugünkü taban (hakem, N=200 mean): faz öncesi
   **2004,9 µs = 2,00×**, nihai ikili **1681,3 µs = 1,68×**. Tavan 1000 µs
   F3b'de de OYNATILAMAZ (§11).

**F3b ŞEFİNE BAĞLAYICI İKİ SATIR:**
(1) **Faz açılırken tahmin SAYIYLA yazılır.** §3.12 ("tahminin iki katı") bu
koşuda uygulanamaz hâldedir çünkü hiçbir faza yazılı tahmin konmamıştır; hakem
sayı uydurmadı, kuralı koydu.
(2) **F1e-C her fazda geçerli:** kâtibin commit'i fazın SON commit'i olamaz ve
`docs_truth` + `install_docs` + `version` üçlüsü fazın NİHAİ ikilisine karşı
yeşil koşmadan faz kapanmaz. F3'te `docs/` hiç değişmediği için şart boş yere
sağlandı; F3b canlı enjeksiyon ekranı üreteceği için **kâtip commit'i
ZORUNLUDUR** ve `docs/claims.tsv`'ye kayıtsız iddia cümlesi KIRMIZIDIR.

### F1b HAKEM HÜKMÜ (2026-08-29)
**`F1b: GEÇTİ`.** Gerekçe ve sayılar `KAPI.md`'nin ilk satırında, ayrıntı
`RAPOR/F1b-R.md`'de. §3.4'ün üç açık kalemi **hakem tarafından hükme bağlandı**
(`KARARLAR.md`, 2026-08-29 · F1b · (b) ve (c)):

- **(b) D6'nın sahibi: F2 DEĞİL, F3.** F2 **2026-08-27'de GEÇTİ** ve D6'nın
  "önce kapanır" dediği D1 = S12 iki gün ÖNCE kapandı (`DURUM.md`'nin S12
  satırı). Kapalı faz §3.11 gereği açılmaz. D6'nın kusuru bugün ölçüldü ve
  DURUYOR: `rabadon-truth /Users/damummyphus` → `level 3 SUITE`,
  **20705 kod dosyası / 2850 test dosyası** tek proje sayılıyor (29 Ağu'da
  20698/2849'du — büyüyor), ve `via:` satırı **`.rabadon/guard.json check`**
  diyor, yani keşif yolu onarılmadı, elle daraltılmış bir `check` ile atlanıyor.
  `truth.cpp:64-71` `skip_dir()`'de `site-packages` ve `Library` hâlâ YOK.
- **(c) Kapı modu: ENFORCE (deny).** `DURUM.md`'nin "watch (observe)" satırı
  BAYATTI, yukarıda düzeltildi. Üç ölçüm + üç canlı ret.

**SIRADAKİ FAZ: F3.** Gerekçe: kalan sıra `F1b → F1n → F3`, ve **F1n §13 gereği
uykuda KOŞMAZ** (operatör kararı, `UYANDIGINDA.md`), dolayısıyla sıradaki
KOŞULABİLİR faz F3'tür.

**F3 İKİ BLOKLAYAN KARTLA AÇILIR** (§3.7, hakem sırayı yeniden yazdı):
1. **D6 — keşif seçicisi.** `truth.cpp:336-337` + `truth.cpp:64-71` `skip_dir()`
   + `pathres.h:416-426` `project_root()` + `net.cpp:274` boş-koşu muafiyeti.
   Kural GEVŞETİLMEZ (D6/2 aynen): fikstür koddan ÖNCE, mutasyon kanıtıyla,
   `.venv` satırı YEŞİL kalacak, `Library/…/site-packages` satırı KIRMIZI düşecek.
   `~/.rabadon/guard.json`'ın elle daraltılmış `check` alanı bir onarım DEĞİLDİR
   ve kapanış ölçümü onun ARKASINDAN yapılamaz.
2. **CHALLENGE-2 — kapsam sızıntısı.** Aynı `project_root()` çıktısı; komşu
   dizin bu projenin kırmızısını miras alıyor. Aynı kart, ayrı kabul maddesi.
   (Hakem bu oturumda YENİDEN ÜRETMEDİ — F3 önce üretecek, sonra onaracak.)

**F3'E DEVREDEN, SAHİBİ OLMAYAN ÜÇ KALEM** (kart değil, kapanışta bakılmalı):
- `site_claims_test.sh` **`gh` ikilisine ve ağa bağımlı** (`site_claims_test.sh:126`
  → `site/build.py:277,285`). Temiz konteynerde `make test`'i **exit 2'de tutan
  yeni ilk kalem**. CLAUDE.md kalite barının ("yalnız git ve shell") doğrudan ihlali.
- `no-blind-inplace-source-rewrite` **yalnız kabuk yüzeyini kapsıyor**: aynı bayt
  değişikliği `sed -i` yolundan REDDEDİLDİ, `Edit` aracından GEÇTİ (hakem ölçtü).
- **CHALLENGE-3 deliği hâlâ açık** ve hiçbir hakem/faz onu KULLANMADI.

**YANLIŞ POZİTİF SAYACI, bu hakem oturumu: 1** (`baseline-truncating-redirect`,
henüz var olmayan bir çıktı dosyasına yönlendirme; ret metni "there is no command
on the line to name" dedi, oysa satırda `make all` vardı). CLAUDE.md gereği
sayılıyor, mazur görülmüyor.

### F2 HAKEM HÜKMÜ (2026-08-27)
2026-08-27 · `F2: GEÇTİ` · Kartın sayılarını kopyalamadan hepsini kendi kum havuzumda yeniden ürettim ve tuttular: `make test` **EXIT=0**, native **3786** iddia + **633** kontrol + `npm test` **64/0** = **4483 yeşil / 0 kırmızı** (taban 4428, tam **+55**), `bash reports/R7/accept.sh` **exit 1, 23/3** ve kırmızı ad kümesi **`{2b, 6e, 7b}` büyümedi** (`2b` bende 1271,2 µs, tavan 1000 µs), F1e-C üçlüsü nihai ikiliye karşı 42/0 + 38/0 + 13/0 ve kâtip commit'i fazın sonuncusu değil; §3.8 temiz — zayıflatılan/silinen test YOK, eşikler oynatılmadı, beş kartın beşinde de ölçüt koddan ayrı ve önceki commit'te, ve mutasyon kanıtını kendim ürettim (`kSilencers`'a yedinci susturucu → `docs_truth_test.sh` 42/0'dan **41 ok / 1 fail EXIT=1**'e düştü; LOSS fikstürü 250→300 → `signals_screen_test.sh` 38/0'dan **37/1 EXIT=1**'e düştü — ekran kaybı gerçekten hesaplıyor). Tam gerekçe ve NOT VERIFIED listesi `KAPI.md`'de.

**§3.4 AÇIK KALEMLER — İKİSİ DE HÜKME BAĞLANDI** (`reports/kosu/KARARLAR.md`):
- **(a) `reports/R7/accept.sh` `8a` 21 → 22 (`9cba3cd`): ONAYLANDI.** Eski **21**, yeni **22**, karşılaştırma **tam eşitlik olarak kaldı** (`>=` yapılmadı); commit tek satırlık ve KODSUZ; sayıyı büyüten `827baa7` salt eklemedir (5 silinen satırın hepsi `except: pass` yutucusu, yerine sayan-adlandıran CLAIM 8 geldi); uygulayan işçi dokunmayı **yazılı olarak reddetti** (`f2-1-kart.md:122-126`).
- **(b) `native/sandbox_test.sh` CHALLENGE'ı: KIRMIZI KALIR, kart AÇILDI → F1b.** Ölçüm: ürün `sandbox.cpp:365` `NO usable kernel backend` basıyor, test `sandbox_test.sh:121` `no kernel backend` arıyor — sapma tek kelime, **yanlış olan testtir**, `a74e7d8` (2026-07-31) açtı, **27 gündür kırmızı**; maliyeti 4483 yeşilin **1'i**, macOS'ta hiç koşmuyor (Seatbelt var, süit 17/0), ama **konteynerin `make test`'ini exit 2 yapan tek kalem**. Onarım testi sertleştirir, zayıflatmaz — ama faz ajanının işi değildi, F2'nin dokunmaması doğruydu.

**SIRADAKİ FAZ: F1b** (sıra değişmedi: F2 → **F1b** → F1n → F3). Ölçülen sayıya bağlı iki EKLEME:
1. **F1b'ye yeni kart, yukarıdaki (b):** `sandbox_test.sh:121` beklentisi ürünün sevk ettiği dizgeye sertleştirilir (tek satır) + **mutasyon kanıtı** (ürün dizgesini geçici bozup kırmızı düştüğünü görmek), ve kapanışta konteynerde `make test` exit'i yeniden ölçülür. Gerekçe ölçülü: bu tek iddia, temiz konteynerde `make test`'i exit 2'de tutan tek kalemdir (F1e'de de aynıydı) — R7'nin dürüst kapanışı bu yüzden bir string sapmasına takılı duruyor.
2. **F1b'ye bağlayıcı satır, `8b` tuzağı:** `reports/R7/accept.sh` `8b` (`signals_test.sh 39/0`) `8a`'nın AYNI tam-eşitlik tuzağını taşıyor; `signals_test.sh`'e eklenecek ilk iddia kırmızı ad kümesini yine büyütür. Ölçülü: `8a` bu fazda tam olarak böyle geçici olarak dörde çıktı. Kural aynı kalır (eşitlik gevşetilmez, `>=` YAPILMAZ) ama sayı değişikliği uygulayandan AYRI bir işçinin kendi commit'inde yapılır ve hakeme gelir.

**ETİKET DÜZELTMESİ, F1b AÇILMADAN ÖNCE:** `F2-oncesi` etiketi `c7b229c`'yi gösteriyor ama o commit fazın **İÇİNDE** (kart-2 kanıt commit'i); gerçek faz tabanı **`f03320f`**'tür. `git diff F2-oncesi..HEAD` fazın 83 dosyasından yalnız 16'sını gösteriyor — **hakeme incelemesi verilen `9cba3cd` dahil 67 dosya etiketin dışında kalıyordu**. Bu denetim `f03320f..HEAD` üstünde yapıldı. Etiket taşınmalı, ve `F1b-oncesi` `main`'in bugünkü ucuna (`0f7904b`) konmalı.

**ETİKET DÜZELTİLDİ (2026-08-27, şef):** `F2-oncesi` c7b229c → **f03320f** (hakemin ölçtüğü gerçek faz tabanı); `F2-yesil` = 1d89331; `F1b-oncesi` = 1d89331.

**HAZIR, tek komut bekliyor (§3.4 geri dönüşsüz dış adım):** `git push --tags` rabadon'un kendi `no-release-tag-push` kuralıyla reddedildi — `.github/workflows/release.yml` tag push'u yayın sayıyor. Etiketler YEREL. Koşu beklemedi.

**SIRADAKİ FAZ: F1b** — açıldı (şef, 2026-08-27).

**KUM HAVUZU KURALI, ÖLÇÜLDÜ:** hakem kum havuzu **`/tmp`'de AÇILMAZ**. `/tmp/hakem-f2`'de koşan `make test` **EXIT=2** verdi (`fd_dup_test.sh` 7/4) — regresyon değil, `fd_dup_test.sh:36-42`'nin kendi başlığının uyardığı artefakt: `/tmp` bir makine temp köküdür ve kapsam yasası orayı muaf tutar, yani süit kuralı değil muafiyeti ölçer. Temp kökü dışında aynı HEAD **EXIT=0**. Sonraki hakem kum havuzunu temp kökü dışına açar.

**F1 üçe bölündü** (`SAPMA-KARARLARI.md`): **F1a bitti**, **F1c bitti**,
**F1n** operatörü bekliyor.
**CEVAPÇI KARARI (2026-08-26, F1c hakem hükümleri sonrası):** araya **F1d**
girdi. Yeni sıra: F1a → F1c → **F1d** → **F2** → F1b → F1n → F3.
**F1d BİTTİ (şef hükmü; hakem hükmü ayrıdır ve orkestratörün işidir, §9).**
B1'in yalanı da B2'nin ölü kurulum yolu da kapandı — ikisi de kırmızı düşebilen
birer testle kilitli ve iki kilit de faz öncesi artefakt üstünde AYRI WORKTREE'de
kırmızı düştü. Ayrıntı yukarıda "F1d'NİN DEĞİŞTİRDİĞİ ÖLÇÜMLER".
**F1d HAKEM HÜKMÜ: GEÇTİ** (`KAPI.md`). **Ama cevapçı araya son bir mini-faz
koydu: F1e.** Yeni sıra: F1a → F1c → F1d → **F1e** → **F2** → F1b → F1n → F3.
**F1e BİTTİ (şef hükmü; hakem hükmü ayrıdır ve orkestratörün işidir, §9).**
C1, C2, C5, C6 ve F1e-A…F1e-E'nin hepsi kapandı; ayrıntı yukarıda
"F1e'NİN DEĞİŞTİRDİĞİ ÖLÇÜMLER" ve `reports/kosu/RAPOR/f1e-tutanak.md`.
**SIRADAKİ FAZ: F2** — ama **F1e hakem hükmü GEÇTİ demeden AÇILMAZ** (§11).
F2'nin nihai kapsamı (S1-S11) `SAPMA-KARARLARI.md` · "F2'NİN NİHAİ KAPSAM SINIRI".
**F2 ŞEFİNE İKİ YENİ BAĞLAYICI SATIR, F1e'den doğdu:**
(1) **F1e-C artık her fazda geçerli bir kapı şartıdır:** kâtibin commit'i fazın
SON commit'i olamaz; `docs_truth_test.sh` + `install_docs_test.sh` +
`version_test.sh` üçlüsü fazın NİHAİ ikilisine karşı yeşil koşmadan faz kapanmaz.
(2) **F2 yeni bir ekran ve yeni düzyazı üretecek:** `docs/commands.md`'nin
işaretli davranış bloğuna giren her iddia cümlesi `docs/claims.tsv`'ye kayıtlı
ve yürütülebilir bir kontrolü olmak zorunda; sicilde olmayan iddia KIRMIZIDIR.
Ve `native/refenv/run.sh` ile temiz konteyner koşumu artık **tek komut**
(S10'un ölçüm aleti hazır).

Aşağıdaki blok F1e'nin SEBEBİDİR ve tarihsel kayıt olarak duruyor:
`docs/commands.md:90-95`'in üç cümlesi de bugün YANLIŞ; belgenin verdiği
"kaldıran tek komut" ürünün kendi yolundan girilen SILENT'ı kaldırmıyor;
**ekranın kendisi iki hâlde çalışmayan bir kaçış komutu basıyor**
(`RABADON_MODE=silent`, `<proje>/.rabadon/mode=silent` → `rabadon off` koşuluyor,
gate hâlâ EXIT=0) ve `status_truth_test.sh` bu hücreleri hiç gezmiyor
(`grep -c RABADON_MODE` → 0); susturucu tablosu 3 satır, gerçek sayı **6**.
Ayrıca temiz KONTEYNER ilk kez koştu: `make all` exit 0, **`make test` exit 2**
(`sandbox_test.sh:121 --check message`, ve 54 süit hiç koşmadı).
**F2 F1e hakem hükmü GEÇTİ demeden AÇILMAZ.**
**F2'nin nihai kapsamı** (S1-S11, S9 sertleşti, S10/S11 yeni):
`SAPMA-KARARLARI.md` · "F2'NİN NİHAİ KAPSAM SINIRI ... (BU SÜRÜM GEÇERLİ)".
F2'nin önkoşulu F2-S3'tü — "F1a'nın disclosure kartı kapanmadan açılmaz" — ve
o kart kapandı, `make disclosure` exit 0.
F1c, F2'nin önüne konmuştu çünkü §11 "kırmızıyı sonraki faza taşımak" yasağı
KIRMIZI-A'yı bu gece kapatılabilir buluyordu; kapandı, F2 artık kırmızı zeminin
üstüne basmıyor.
**F2'YE UYARI, ÖLÇÜLÜ VE GÜNCELLENDİ:** replay korpusu 527 kayıt / 34 oturum /
4-5 gündür (7 gün DEĞİL). **Cevapçının kendi sayımı (2026-08-26): canlı korpusta
başlık `count` toplamı 933, diskte 527 → 406 hamle (%43,5) KAYIP.** Yedek anında
kayıp 127'ydi; dolu ring (`286fd71d…`) o günden bu yana `count` 327 → **606**,
yani **279 hamle daha üzerine yazıldı** ve dolu ring bu koşuyu koşan oturumun
kendisi. Salt-okunur yedek: `~/.rabadon-korpus-snapshot-20260826/` (654 `count`
/ 527 diskte / 127 kayıp).
**F2 kabul sayısını CANLI korpustan ALMAZ (F2-S8)** — canlı sayı yarın yeniden
üretilemez, hakem sınayamaz (§9, §4.5). Ölçüm dondurulmuş yedekte koşar ve
hangisinin okunduğu tutanağa yazılır. Ekran kaybı da ilan eder (F2-S4).
F1n (npm yayını) **UYKUDA KOŞMAZ** (§13): operatör kararı, `UYANDIGINDA.md`'de.
Sonraki şef bu dosyayı ve `ENVANTER.md`'yi okur; `KOSU-RABADON-5.md` §6'nın sayılarına
DEĞİL, ölçümlere güvenir. F1a'nın ölçümleri ENVANTER'in F0 sayılarını GÜNCELLER.
