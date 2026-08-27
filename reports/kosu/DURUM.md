# DURUM — koşu 5, F1e sonrası (2026-08-26)

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
  *(EMEKLİ SAYAÇ — aşağıdaki "TEST SAYACI" bölümüne bak; bu sayı `PASS (N checks)`
  basan 9 süidin 612 kontrolünü saymıyor ve yeni sayıyla KIYASLANAMAZ.)*
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
| ölçülmüş yanlış pozitif | **4 olay / 2 sınıf** — 2 onarıldı, 1 sınıf AÇIK (`red-suite-test-write`) |
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
