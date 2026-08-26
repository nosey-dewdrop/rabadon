# F1e TUTANAK — "belge de yalan söylemez, ve kaçış kapısı gerçekten açılır"

Faz aralığı: `05ab1ac..HEAD`. Dal `main`, tek kök. Yeni dal açılmadı
(§8.2 için `--detach` geçici worktree kullanıldı ve kaldırıldı).
Kaynak: `reports/kosu/SAPMA-KARARLARI.md` · C1, C2, C5, C6 ve F1e-A…F1e-E.
Şef **kod yazmadı**; üç işçi salındı (tavan 3): A (kod), B (belge), C (yalnız ölçüm).
Kart A ve B **sırayla** koştu, kart C paralel — koda dokunmadığı için.

---

## 0. FAZIN SEBEBİ — şefin kendi ölçümü, faz başlamadan

Verbatim: `reports/kosu/RAPOR/f1e-0-onolcum.out`. Kum havuzu (`mktemp -d` proje +
`mktemp -d` RABADON_DIR + `mktemp -d` HOME), sevk edilen yüzey
(`package.json` bin = `native/rabadon-cli.sh`), gerçek `native/rabadon-gate`:

    $ export RABADON_MODE=silent
    $ rabadon status
    rabadon: SILENT — dormant everywhere, records nothing (`rabadon off` to watch again)
    $ gate <PreToolUse: git push --force origin main>   ->  EXIT=0  BYTES=0
    $ rabadon off                       # <- EKRANIN KENDİ VERDİĞİ KOMUT
    rabadon: SILENT — dormant everywhere, records nothing (`rabadon off` to watch again)
    $ gate <aynı olay>                  ->  EXIT=0  BYTES=0     # HÂLÂ SUSTURULMUŞ

Aynısı `<proje>/.rabadon/mode = silent` için de ölçüldü, aynı sonuç. Kontrol
hücresi `<RABADON_DIR>/mode = silent` DOĞRU çalışıyordu (`rabadon off` sonrası
gate 296 bayt bastı) — yani kusur üç mod katmanının ikisindeydi ve üçüncüsü
onu gizliyordu.

Ve F1d'nin kilidi bunu **göremiyordu**:
`grep -c RABADON_MODE native/status_truth_test.sh` → **0**.
Kırmızı ad kümesinde görünmemesinin sebebi düzelmiş olması değil, **hiç
ölçülmemiş olmasıydı** (§8.2). Bu bir belge kusuru değil, **ürün kusuru**:
fren "çıkış kapısı burada" diyor, kapı açılmıyor (§4.8, §4.9).

---

## 1. KABUL MADDELERİ — tek tek, kanıtla

### F1e-A · ÖNCE KOD: her susturucunun bastığı kaçış komutu GERÇEKTEN açar · KAPANDI

**Kod (işçi A, commit `e51e77a`).** `native/gate.cpp` `compute_state`: konuşan mod
katmanları toplanıyor ve `silent` diyenlerin baştan gelen kesintisiz dizisi
`Muter` olarak kaydediliyor. Yani "mod katmanı silent" artık ekranın gözünde bir
susturucudur ve F1d'nin yazdığı `silenced by: … / next: …` disclosure yolu
kendiliğinden çalışır. **İkinci kopya açılmadı** — ekran, `--statusline` ve sıcak
yol aynı struct'ı okur.

**ŞEF KENDİ ÖLÇTÜ — ALTI SUSTURUCU, EKRANDAN ÇEKİLİP VERBATIM KOŞULDU.**
Verbatim: `f1e-3-alti-susturucu.out` (ekran) ve `f1e-2-kacis-dogrulama.out`
(kapı gerçekten açılıyor mu). Şefin betiği komutu **ekrandan `sed` ile çeker**,
belgeden değil:

| susturucu | ekranın bastığı `next:` | komut koşulunca gate |
|---|---|---|
| `RABADON_OFF=1` | `unset RABADON_OFF` | — |
| `<project>/.rabadon/off` | `rm <project>/.rabadon/off` | — |
| `$RABADON_DIR/silent` | `rabadon off` | — |
| `$RABADON_DIR/mode` = `silent` | `rabadon off` | **exit 0 / 296 bayt → açıldı** |
| `<project>/.rabadon/mode` = `silent` | `rm <project>/.rabadon/mode` | **exit 0 / 296 bayt → açıldı** |
| `RABADON_MODE=silent` | `unset RABADON_MODE` | **exit 0 / 296 bayt → açıldı** |

Altısının altısı da ekranda **adıyla + yeriyle + tek komutuyla** duruyor.
Faz öncesi iki kırmızı hücrenin ikisi de yeşil.

**KİLİT (işçi A, commit `52c283d` — koddan ÖNCE).** `native/status_truth_test.sh`
+18 hücre / +68 iddia: `RABADON_MODE{unset,silent}` × `<proj>/.rabadon/mode{yok,watch,silent}`
× `<RABADON_DIR>/mode{watch,enforce,silent}`. Her hücrede `next:` komutu ekrandan
çekilir, yorumlanır (**tanımadığı komut = FAIL**, sessiz atlama yok), verbatim
koşulur, sonra gerçek gate aynı olayda yeniden ölçülür.
**94 iddiadan hiçbiri silinmedi/zayıflatılmadı** → **162 ok / 0 fail**.

**BOŞ YEŞİL (§8.2), AYRI WORKTREE.** `f1e-a-bosyesil.out`:
`git worktree add --detach` + faz öncesi HEAD `05ab1ac` + `make all` →
**130 ok / 32 fail**, ve 32 kırmızının hepsi üç katmanın `silent` hücreleri.
HEAD'de 162/0. Worktree kaldırıldı.

### F1e-B · SONRA BELGE: düzyazı-kod sapmasını yakalayan kilit · KAPANDI

**Kart B, kart A'nın hükmü düşmeden BAŞLAMADI** (şef önce kendi ölçümüyle
A'yı geçirdi, sonra B'yi saldı). F1d'nin kök sebebi commit sırasıydı; bu fazda
belge, **düzeltilmiş ekranın bastığını** yazdı.

`native/docs_truth_test.sh` (YENİ, `make test`'e bağlı, `docs/claims.tsv` 15 kayıt).
Beş değişmez, hepsi çevrimdışı, deterministik, yalnız git + POSIX shell:

1. **TABLO YÜRÜTÜLÜR, OKUNMAZ.** `docs/commands.md`'nin susturucu tablosu
   ayrıştırılıyor; her satır için kum havuzunda o hâl kuruluyor, gerçek gate ile
   SILENT doğrulanıyor, satırın kendi komutu **verbatim** koşuluyor, gate artık
   susturulmuş olmamalı. **Satır sayısı belgeden türetiliyor: satır eklemek test
   eklemektir.**
2. **KÜME EŞİTLİĞİ.** Belgedeki küme, ikilinin raporlayabildiği kümeye EŞİT olmak
   zorunda. Küme **ikiliden türetiliyor**, teste yazılmıyor. Bugün 6 = 6.
3. **EKRAN = BELGE, BAYT BAYT** (yalnız kum-havuzu yolları belgenin yer
   tutucularına normalize ediliyor; normalizasyon testin başında yazılı).
4. **DAVRANIŞ İDDİASI SİCİLİ.** Üç belgenin işaretli bloklarında dar bir gramere
   (`does NOT`, `will report`, `reports the`, `never`, `always`, `is not`) uyan her
   cümle `docs/claims.tsv`'de kayıtlı ve yürütülebilir bir kontrolü olmak zorunda.
   Sicilde olmayan iddia KIRMIZI; belgede olmayan sicil kaydı da KIRMIZI.
5. **Üç yanlış cümle ölçüme göre yeniden yazıldı, ESKİSİ SİLİNMEDİ** — olduğu gibi
   alıntılandı, "2026-08-26'da şu komutla ölçüldü, yanlış çıktı" gerekçesiyle
   işaretlendi (`docs/commands.md:96-125`).

**C1 ve C2 kapandı.** `docs/commands.md`'nin üç cümlesi de ölçümle değiştirildi;
tablo 3 satırdan **6 satıra** çıktı; 3. satırın yanlış komutu
`rm ~/.rabadon/silent` → **`rabadon off`** oldu.

**ŞEFİN AÇTIĞI SORU KAPANDI.** SAPMA-KARARLARI §5.5 "`docs/faq.md` ve
`docs/uninstall.md`'de de aynı yalan var mı — AÇIK SORU" diyordu. Şef ölçtü:
**EVET**, `docs/faq.md:20` ve `docs/uninstall.md:55-56` de `rm ~/.rabadon/silent`
diyordu; ikisi de düzeltildi. Ve `README.md`, `docs/quickstart.md`, `site/`:
`grep -rn "RABADON_OFF|\.rabadon/off|rabadon/silent"` → **hiç eşleşme yok**,
yani orada yalan YOKTU (susturuculardan hiç söz etmiyorlar).

**BOŞ YEŞİL (§8.2).** `f1e-b-bosyesil.out`: belgeler eskiyken **14 ok / 27 fail**,
ve dört kusurun dördü de adıyla düştü — tablo 3 satır / ikili 6 bildiriyor,
`rm ~/.rabadon/silent` verbatim koşuldu ve aynı olay **hâlâ exit 0 / 0 bayt**,
üç belgede işaretli blok yok. Düzeltilmiş belgelerle **40 ok / 0 fail**
(`f1e-b-sonra.out`).

**İŞÇİ B'NİN KENDİ ALETİNİ YAKALAMASI, yazıldı.** İlk yeşil denemede bir kontrol
yalan söyledi; işçi elle yeniden üretti, **iddia doğruydu, ÖLÇÜM ALETİ bozuktu**
(alt kabukta artan sayaç yüzünden probler birbirinin `.rabadon/off`'unu
devralıyordu). Hücreler `mktemp -d`'ye çevrildi (`9c3358d`) ve boş yeşil çıktısı
**düzeltilmiş süitle yeniden üretildi** — yani rapordaki kırmızıyı basan süit,
yeşili basan süidin ta kendisi.

### F1e-C · SIRA KURALI: kâtibin commit'i fazın SON commit'i olamaz · KAPANDI

Kâtip işi (`63e01f3`, yalnız `docs/`) fazın son commit'i DEĞİL. Ondan sonra
`74def5d` (rapor) ve `6385da1` (şefin ölçümleri) geldi, ve **üçlü, fazın NİHAİ
ikilisine karşı şefin kendi elinde yeniden koştu:**

    $ bash native/docs_truth_test.sh      -> docs truth: 40 ok / 0 fail       exit 0
    $ bash native/install_docs_test.sh    -> 38 ok / 0 fail                   exit 0
    $ bash native/version_test.sh         -> version: 13 passed, 0 failed     exit 0

Ayrıca `status_truth_test.sh` **162 ok / 0 fail** ve `heredoc_prose_test.sh`
**PASS (14 checks)**. Bu madde F1e'den itibaren §8'e ek bir kapı şartıdır.

### F1e-D · REFERANS ORTAM · ÖLÇÜLDÜ, ve KIRMIZI OLARAK YAZILIYOR

**a) Koşum commit'lendi ve yeniden koşulabilir.** `native/refenv/run.sh`
(işçi C). HEAD'i geçici bir klona çıkarır, konteynerde `make all` koşar, sonra
Makefile'ın **kendi `test:` listesinden** okuduğu her süiti **tek tek** koşturur —
`make` ilk kırmızıda durduğu için census yapamıyordu. `--network none`.
Kart `git worktree` demişti; işçi **gerekçesini yazarak** `git clone --no-hardlinks`
kullandı (worktree'nin `.git`'i konteynerde var olmayan bir host yoluna işaret
eden bir DOSYA'dır; git'e dokunan her süit harness yüzünden düşerdi).

**b) 54 süit ARTIK ÖLÇÜLDÜ — ve sayı da düzeltildi.** Önceki oturumun "54 süit
hiç koşmadı" rakamı bir tahmindi; işçi C saydı: `sandbox_test.sh` 103'ün
**#57**'siydi, arkasında kalan **46**'ydı. Şef kendi koşturdu, fazın NİHAİ
HEAD'inde (`6385da1`), `node:22-bookworm` linux/arm64, `--network none`:

| ölçü | değer |
|---|---|
| `make all` | **exit 0** |
| süit sayısı | **105** (F1e iki yeni süit ekledi) |
| GREEN | **102** |
| RED | **3** |
| TIMEOUT | **0** |
| **HİÇ KOŞMAYAN** | **0** |

Ham kanıt: `f1e-d-env.out`, `f1e-d-build.out`, `f1e-d-suites.tsv`,
`f1e-d-suites.out`. "Koşmadı" ile "yeşil" bir daha karıştırılamaz.

**c) Her kırmızı adıyla ve kök sebebiyle:**

| süit | exit | kök sebep |
|---|---|---|
| `sandbox_test.sh` | 1 (8 ok / 1 fail) | **GERÇEK ÜRÜN/TEST SAPMASI.** `sandbox.cpp:365` `NO **usable** kernel backend` basıyor; `sandbox_test.sh:121` `"no kernel backend"` arıyor. Dizgeyi `a74e7d8` (31 Tem) değiştirdi ve **yalnız** `sandbox.cpp` + `ci.yml`'e dokundu. Dal macOS'ta ölü (seatbelt var), backend'siz bir konteyner bu dalın **ilk kez koştuğu yer**. |
| `site_claims_test.sh` | 1 | **ORTAM.** `site/build.py:277` `gh` ikilisini çağırıyor; imajda yok ve `--network none` ile zaten kullanılamaz. `make test` içinde **beyan edilmemiş bir dış bağımlılık** — "yalnız git ve shell" barına karşı gerçek bir bulgu. |
| `publish_redaction_test.sh` | 1 (27 ok / 1 fail) | **ORTAM / YANLIŞ POZİTİF.** Konteyner `root` olarak koşuyor → `enc_home` = `-root`, ve bu dizge `site/rule_census.json`'daki **İngilizce düzyazıda** (`a $HOME-rooted tree`) geçiyor. Sızıntı YOK (işçi C her anahtarı tek tek gezdi). Süidin kendi yorumu (satır 136-140) aynı sınıfı `runner` için adıyla muaf tutuyor; `root` kapsam dışı kalmış. |

**d) `native/sandbox_test.sh` DEĞİŞTİRİLMEDİ — CHALLENGE açık, KIRMIZI bırakıldı.**
Tam metin: `f1e-c-konteyner.md` §4, komut çıktılarıyla. Çözüm insan hükmü ister
ve kendi commit'inde, koddan ayrı gelmelidir (CLAUDE.md 1 ve 2). Cazip düzeltme
(grep'i gevşetmek) bu ürünün var olma sebebinin tersidir. **Bu kırmızı F1e'nin
açtığı bir kırmızı değildir; devralınmıştır ve bugün ilk kez ADI konmuştur.**

**e) F1e'nin KENDİ eklediği/değiştirdiği süitler temiz konteynerde, çevrimdışı,
YEŞİL:**

| süit | konteynerde |
|---|---|
| `status_truth_test.sh` | **162 ok / 0 fail, exit 0** |
| `docs_truth_test.sh` | **40 ok / 0 fail, exit 0** |
| `heredoc_prose_test.sh` | **exit 0** |
| `install_docs_test.sh` | 38 ok / 0 fail, exit 0 |
| `version_test.sh` | 13 ok / 0 fail, exit 0 |

**BONUS, sorulmamıştı ve önemli:** `npm_install_test.sh` konteynerde **çevrimdışı
yeşil, 12/12, 562 s** — yani yayımlanacak npm yolu, **derleyicisi hiç olmayan**
bir makinede (`cc/gcc/g++/clang/clang++/c++/make/cmake/ld` hepsi 127 dönen shim)
ve **ağsız** çalışıyor, ve README'nin ilk vaadi (force-push reddi) kurulu hook
üstünden ateşliyor. Bu F1n'in işine yarar.

### F1e-E · YANLIŞ POZİTİF (C6) · KAPANDI, ve sayı YAYIMLANIYOR

**Kök sebep ölçüldü, tahmin değil.** `native/rules.h`'nin `pattern_names_a_pipe`
kolu, deseni boruyu açıkça adlandıran kurallara **ek yüzey olarak HAM SATIRIN
TAMAMINI** veriyordu. `native/cmdtext.h` heredoc gövdelerini segment
yüzeylerinden zaten çıkarıyor; çıkarmadığı **tek** yüzey buydu. Düzeltme:
`rbtext::Parsed.line` (ön-işlenmiş satır — yorumlar ve heredoc gövdeleri yok,
borular ve ayraçlar yerinde) eklendi, `rules.h` artık onu veriyor.

**Fikstür koddan ÖNCE commit edildi** (`e64c1eb` → `6699efb`).
`native/heredoc_prose_test.sh`, `make test`'e bağlı, yalnız git + shell:

- **onarımdan ÖNCE:** ölçülen ret 5 hücrede yeniden üretildi
  (`f1e-a-c6-once.out`, `FAILED`, exit 1),
- **onarımdan SONRA:** `PASS (14 checks)`,
- **(c) maddesi — kural GEVŞEMEDİ:** gerçek `make test | tail -5` + `echo exit=$?`
  **HÂLÂ BLOCK**; heredoc VE gerçek ihlal aynı satırdaysa **yine BLOCK**,
- **(d) maddesi:** `no-gnu-timeout-on-macos` de `[;&|]` yazdığı için ham satırı
  alıyordu — `; timeout 5 …` içeren düz yazı önce reddediliyordu, artık geçiyor;
  ayrı hücre olarak fikstürde.

Kural silinmedi, eşik gevşetilmedi, `disabled[]`e dokunulmadı, `rabadon wrong`
hiç koşulmadı.

#### YANLIŞ POZİTİF SAYISI — sıfır olsun diye gizlenmiyor (§4.3, CLAUDE.md)

| olay | sınıf | durum |
|---|---|---|
| 1. heredoc gövdesindeki belge metni `no-exit-code-after-pipe`'ı ateşledi (cevapçının oturumu) | `no-exit-code-after-pipe` | **ONARILDI + kilitlendi**, kural gevşemedi |
| 2. `; timeout 5` içeren düz yazı `no-gnu-timeout-on-macos`'u ateşledi (işçi A, fikstürle ölçüldü) | aynı aile | **ONARILDI** aynı düzeltmeyle |
| 3-4. `red-suite-test-write` süit GERÇEKTE yeşilken **iki** meşru Write'ı reddetti (işçi A) | `red-suite-test-write` | **AÇIK. KART AÇILMADI.** |

**Bu koşuda ölçülmüş yanlış pozitif: 4 olay / 2 sınıf. İkisi onarıldı, biri açık.**
(3-4)'ün kök sebebi ölçülü: kural `sess.lastTestFail > sess.lastTestPass`'e bakıyor
ve `lastTestPass` **yalnız çıktısı GÖRÜNEN** bir test komutundan güncelleniyor —
`make test > dosya 2>&1` yeşil kapatıyor ama işareti temizlemiyor. Bu C6'nın
kardeşi bir sınıftır; kart açılmadı, kural DEĞİŞTİRİLMEDİ, olay yazıldı.

**Buna karşılık, kendi ürünümüz bu fazda kendi üstümüzde DOĞRU yakalamalar da
yaptı:** işçi C'nin `sed -i` ile yerinde yeniden yazma denemesi
(`no-blind-inplace-source-rewrite`) ve kırmızı-taban yasası (`tests are RED`)
— ikisi de doğru red, ikisi de kuralı ve sıradaki komutu adıyla bastı.

---

## 2. §8 KAPISI — dokuz madde, ŞEF HEPSİNİ KENDİ KOŞTURDU

Hiçbir sayı rapordan kopyalanmadı. Kaynak: `/tmp/f1e-f-{test,npm,accept,trio}.txt`.

**1. Fazın kabul betikleri yeşil.**

    $ bash native/status_truth_test.sh    -> 162 ok / 0 fail          exit 0   (öncesi 94/0, faz öncesi kodda 130/32)
    $ bash native/docs_truth_test.sh      -> 40 ok / 0 fail           exit 0   (belgeler eskiyken 14/27)
    $ bash native/heredoc_prose_test.sh   -> PASS (14 checks)         exit 0   (onarımdan önce FAILED)
    $ bash native/install_docs_test.sh    -> 38 ok / 0 fail           exit 0
    $ bash native/version_test.sh         -> 13 passed / 0 failed     exit 0
    $ make all                            -> exit 0
    $ make test                           -> exit 0
    $ npm test                            -> 64 pass / 0 fail         exit 0
    $ bash reports/R7/accept.sh           -> exit 1, 23 yeşil / 3 kırmızı

**2. BOŞ YEŞİL KONTROLÜ (§8.2).** İki yeni/genişletilmiş kilidin ikisi de faz
öncesi artefakt üstünde KIRMIZI düştü:
- `status_truth_test.sh`: ayrı worktree, faz öncesi HEAD `05ab1ac`, **130 ok / 32 fail**
  (`f1e-a-bosyesil.out`) — 32 kırmızının hepsi üç mod katmanının `silent` hücreleri.
- `docs_truth_test.sh`: faz öncesi belgeler, **14 ok / 27 fail**
  (`f1e-b-bosyesil.out`) — tablo 3 != ikili 6, ve `rm ~/.rabadon/silent`
  verbatim koşulduğunda gate **hâlâ exit 0 / 0 bayt**.
- `heredoc_prose_test.sh`: onarım öncesi ikilide **FAILED / exit 1**
  (`f1e-a-c6-once.out`).

**3. Kırmızı AD kümesi büyümedi.** `bash reports/R7/accept.sh` → exit 1,
**23 yeşil / 3 kırmızı**, adlar **`{2b, 6e, 7b}`** — aynı üç ad, aynı üç gerekçe.
Test süitlerinde kırmızı ad YOK. Konteynerde üç kırmızı var (§1/F1e-D/c); üçü de
**bu makinede yeşil olan ve konteynerde ilk kez koşan** dallar, F1e'nin açtığı
değil, F1e'nin ölçtüğü kırmızılardır ve adları yazıldı.

**4. Eşik / tolerans / ön-kayıt / fixture değişimi: HİÇBİRİ.**

    $ git diff --name-only 05ab1ac..HEAD | grep -iE "fixture|threshold|accept|prereg|R7/"
    (boş)
    $ git log --diff-filter=D --name-only 05ab1ac..HEAD
    (boş — silinen dosya yok)

Mevcut hiçbir test değiştirilmedi, zayıflatılmadı, atlandı ya da yeniden
adlandırıldı. `status_truth_test.sh`'in 94 iddiası duruyor, üstüne 68 eklendi.

**5. Ölçüm sevk edilen yoldan alındı.** Her hücrede gerçek `native/rabadon-gate`
ikilisi, gerçek `native/rabadon-cli.sh` dispatcher'ı, `package.json` `bin`'inin
gösterdiği yol. Vekil yok, mock yok. Susturucu kümesi de belgeden değil
**ikiliden** türetiliyor.

**5.5 · §8.5 — `2b` İÇİN İKİ SAYI YAN YANA. NEGATİF SONUÇ, OLDUĞU GİBİ.**
Ölçüm: `reports/kosu/RAPOR/f1e-4-2b-iki-sayi.out`, N=300, daemon açık, sessiz makine.

| alet | sayı |
|---|---|
| süreç-içi prob (`reports/R7/accept.sh`, regresyon cetveli) | **1229,0 µs** |
| **GERÇEK `native/rabadon-gate`, uçtan uca, ham** | **3381,3 µs** (p10 3147,7 / p90 3919,0) |
| aynı harness'ta boş taban (`/usr/bin/true`) | 1386,8 µs |
| → **rabadon'a ATFEDİLEBİLİR uçtan uca maliyet** | **1994,5 µs** |
| tavan (`2b`) | 1000,0 µs |
| **atfedilebilir / tavan** | **1,99×** |

Sağlamlık kontrolü betiğin içinde: ölçülen olayın gerçekten reddedildiği
(gate exit **2**) doğrulanmadan hiçbir sayı basılmıyor — yoksa bir no-op
ölçülmüş olurdu. Cevapçının aynı gün aldığı sayılarla (ham 3201,8–3224,5 µs,
atfedilebilir 1677,4–2056,5 µs) **aynı yere düşüyor**; üçüncü bir bağımsız
harness aynı yönü doğruluyor.

**Bu bir negatiftir ve olumluya çevrilmiyor:** kullanıcının hook'unda geçen süre
yayımlanan prob sayısı değil; ham uçtan uca sayı probun **2,75 katı**, boş taban
düşülünce bile tavanın **iki katı**. `2b` DEVRALINAN bir kırmızıdır (dokuz
ölçümdür tavanın üstünde), sahibi atanmış: ölçüm+yasak **F2-S9**, onarım
**F3-S1**. Tavan 1000 µs **hiç oynatılmadı**.

**6. UX KAPISI — üç satır (§8.6).**
- **Kaç adım:** her susturucudan çalışır frene **1 adım**. Ekran o tek komutu
  yazıyor, kullanıcı onu koşuyor, gate aynı olayda konuşmaya başlıyor.
  Altı susturucunun **altısında** ölçüldü (`f1e-2-kacis-dogrulama.out`);
  faz öncesi bu, altıda **dördünde** doğruydu.
- **Ekranda ne yazıyor:** `f1e-3-alti-susturucu.out` verbatim — durum satırı +
  `silenced by: <ad> (<yol>)` + `next: <tek komut>` + `read from:` katmanı.
  §4.8'in üçü: NE (gate susturulmuş, hiçbir kural koşmuyor), NEDEN (susturucunun
  adı ve tam yeri), SIRADAKİ TEK KOMUT (ve o komut gerçekten açıyor).
- **Kullanıcı nasıl kaçıyor:** altı susturucunun altısı da artık **BELGELİ**
  (`docs/commands.md` altı satırlık tablo, `docs/faq.md`, `docs/uninstall.md`),
  ve belgedeki komut **ekranın bastığıyla bayt bayt aynı olmak zorunda** — bunu
  bir test tutuyor. §4.9 "her kuralın çıkış yolu vardır" ancak çıkış yolu
  BİLİNİYORSA ve GERÇEKTEN AÇIYORSA gerçektir; bugün ikisi de öyle.

**7. Hakem hükmü:** orkestratörün işi, bu tutanağın dışında (§9, §14).
Şef hakemi doğurmadı.

**8. Kâtibin commit'i var:** `63e01f3` (`docs/commands.md`, `docs/faq.md`,
`docs/uninstall.md`, `docs/claims.tsv`). Ve **F1e-C gereği fazın son commit'i
DEĞİL** — üçlü ondan sonra nihai ikiliye karşı yeşil koştu (§1/F1e-C).

**9. SAPMA satırı:** aşağıda §4.

---

## 3. DEVİR SAYILARI — B5'in TEK GEÇERLİ SAYACIYLA

Yeni lehçe uydurulmadı; `DURUM.md`'nin ilan ettiği üçlü komut koşuldu.

| ölçü | F1d sonrası (taban) | **F1e sonrası** |
|---|---|---|
| `make test` exit | 0 | **0** |
| native iddia (`^[[:space:]]*ok\b`) | 3616 | **3738** (+122) |
| native `PASS (N checks)` toplamı | 612 | **626** (+14) |
| native toplam | 4228 | **4364** |
| `npm test` | 64 / 0 | **64 / 0** |
| **TOPLAM** | **4292 yeşil / 0 kırmızı** | **4428 yeşil / 0 kırmızı** (+136) |

Sayaç **DÜŞMEDİ**. +136'nın tamamı yeni iddia: `status_truth` +68,
`docs_truth` +40, `heredoc_prose` +14 (`PASS` sayacında), kalanı yeni hücrelerin
ürettiği iddialar. Silinen/zayıflatılan/atlanan test YOK.

`make test` çıktısındaki `FAIL` dizgileri fikstür metnidir
(`regression_demo.sh`'in kasıtlı demo satırı); o süit exit 0 ve `make test` exit 0.

---

## 4. SAPMA SATIRI (§8.9)

**F1e, §5'in hiçbir YENİ adımını gerçek yapmadı — ADIM 7'nin ("rahatsız olursa
tek sinyali kısar, komple silmez") altındaki ÇIKIŞ KAPISINI gerçek yaptı ve
ADIM 2/4'ün belgesindeki yalanı kaldırdı.**

Gösteren sayı: ekranın bastığı kaçış komutunu verbatim koşup gerçek gate'i
yeniden ölçen kilit, faz öncesi ikilide **130 ok / 32 fail**, faz sonrası
**162 ok / 0 fail** — 32 çelişkinin 32'si "kapı açık" diyen bir ekranla kapalı
kalan bir kapı arasındaydı. Ve belge tarafında: **14 ok / 27 fail → 40 ok / 0 fail**,
susturucu tablosu **3 satır → 6 satır**, hepsi ikiliden türetilmiş.

**Saptık mı: HAYIR.** Ölçü gevşetilmedi, sertleşti:
- `status_truth_test.sh` 94 → 162 iddia, hiçbiri silinmeden;
- belge artık bir test tarafından **yürütülüyor**, okunmuyor;
- referans konteyner ilk kez fazın NİHAİ HEAD'inde tam census ile koştu ve
  **hiç koşmayan süit sayısı 46'dan 0'a indi**;
- `sandbox_test.sh` yeşil için DEĞİŞTİRİLMEDİ, CHALLENGE olarak kırmızı bırakıldı;
- `2b` için tek sayı yerine **iki sayı** yayımlanıyor ve ikincisi daha kötü.

Yeni verb YOK (`native/rabadon-cli.sh` `05ab1ac` ile **bayt bayt aynı**), yüzey
hâlâ beş, varsayılan hâlâ WATCH, `bin/rabadon.mjs` hâlâ donuk
(`git diff --name-only 05ab1ac..HEAD` çıktısında `bin/` YOK).

---

## 5. İŞÇİLERİN KART METNİNDEN SAPMASI — açıkça yazılı

1. **İşçi A, `README.md`'yi editledi.** Kartı `README.md`'yi saymıyordu.
   Sebep: C6 onarımı `rules.h`'ye satır ekledi, `native/` 23366 satıra çıktı,
   ve `site_claims_test.sh` README'nin "~20k lines" cümlesini (izin 21k–25k)
   kırmızıya düşürdü. İşçi sayıyı ölçtü ve `~23k` yazdı, aynı commit'te
   ("docs move with behavior"). **Kart dışıdır ve burada ilan edilmiştir**;
   ölçülmüş bir sayının düzeltilmesidir, bir iddianın gevşetilmesi değil.
2. **İşçi A, kartın önerdiği hücre eksenlerini genişletti** — kart
   `<proje>/.rabadon/mode ∈ {watch, enforce, silent}` demişti, işçi
   `{yok, watch, silent}` + ayrı makine ekseni kurdu ve `silent`'ı **üç
   katmanın üçünde de** gezdi. Kartın istediği asgariden geniş.
3. **İşçi C, `git worktree` yerine `git clone --no-hardlinks` kullandı.**
   Gerekçesi ölçüm: worktree'nin `.git`'i konteynerde var olmayan bir host
   yoluna işaret eden bir dosyadır. Ve `make -k` yerine süitleri tek tek
   koşturdu — `make -k` tek bir toplu hüküm basıyor, census yapamıyor.
   İkisi de raporunda gerekçeleriyle yazılı.
4. **İşçi C 300 s süit tavanı seçti ve YANLIŞTI** — `npm_install_test.sh`'i
   sahte bir TIMEOUT'a düşürdü. İşçi bunu kendi buldu, 900 s'de yeniden
   koşturdu, **562 s'de yeşil** olduğunu ölçtü ve **ilk tahmininin yanlış
   olduğunu raporunda sildmeden yazdı.** Şefin koşumu 1200 s ile alındı.

---

## 6. NOT VERIFIED / ÖLÇMEDİĞİM (§5.5, CLAUDE.md kural 8)

- **`x86_64` hiç ölçülmedi.** Bütün konteyner ölçümleri `linux/arm64`.
- **Yalnız `node:22-bookworm` ölçüldü.** CLAUDE.md'nin barı "yalnız git ve shell
  olan bir makine"dir; bu imaj şişman (g++, python3, node, git taşıyor).
  Yerelde duran `rabadon-refenv:git-and-shell` imajı bu fazda KULLANILMADI.
  **Bu, konteyner ölçümünün en büyük boşluğudur.** "102 yeşil" = "şişman imajda
  yeşil", "git ve shell'de yeşil" DEĞİL.
- **Konteyner `root` olarak koştu.** `publish_redaction_test.sh` kırmızısının
  doğrudan sebebi bu, ve izin tabanlı hiçbir iddianın root altında sahte yeşil
  vermediği **denetlenmedi**.
- **`make test` konteynerde uçtan uca hiç koşulmadı** — census süitleri tek tek
  koşturuyor; süitler arası sıra/paylaşılan durum semantiği varsa görülmezdi.
- **`2b` yalnız bu makinede ölçüldü.** CI referans ortamı ölçümü F2-S9c'nin işi.
  Uçtan uca sayı konteynerde de ölçülmedi.
- **Gerçek Cursor uygulaması başlatılmadı.** Altı susturucunun hiçbiri Cursor
  tarafında sınanmadı.
- **`docs/claims.tsv`'nin grameri dar ve bilinçli dar:** işaretli blokların
  DIŞINDAKİ hiçbir cümle taranmıyor, ve gramere uymayan bir davranış iddiası
  (ör. "shows the mode") işaretli blokta bile yakalanmıyor.
- **Sicilin `expect` sütunu, ölçümün 2026-08-26'daki cevabıdır.** Makine
  cümlenin DOĞRU olduğunu değil, ölçümün hâlâ aynı çıktığını ve hiçbir iddia
  satırının sicilden kaçmadığını kanıtlar. Cümleyi hâlâ bir insan okuyor.
- **C6'nın kural motorundaki kök sebep ölçüldü ama tam kapsamı ölçülmedi:**
  `pattern_names_a_pipe`'ın ham satırı verdiği DİĞER kuralların hangileri olduğu
  ve onların da düzyazıda yanlış pozitif üretip üretmediği taranmadı.
- **`make test` tek bir kez koşuldu; flaky süit tespiti için ikinci örnek yok.**
- **Konteyner ölçümü fazın NİHAİ HEAD'i `6385da1`'dedir**; bu tutanak ve
  `DURUM.md` commit'leri ondan sonradır ve **koda dokunmaz** (yalnız `reports/`).

---

## 7. PARKED — kart açılmadı, dokunulmadı, yazıldı

1. **`red-suite-test-write` bayat kırmızı okuyor** — `lastTestPass` yalnız
   çıktısı GÖRÜNEN test komutundan güncelleniyor; `make test > dosya 2>&1`
   yeşil kapatıyor ama işareti temizlemiyor. Bu koşuda iki meşru Write'ı
   reddetti. **C6'nın kardeşi bir WRONG_REFUSAL sınıfı.** F1b'ye aday.
2. **`site_claims_test.sh` `gh` ve ağ istiyor** ve `make test` içinde.
   "Yalnız git ve shell" barını `make test` bugün karşılamıyor. Kararı
   (çevrimdışı atla mı, `make test`'ten çıkar mı) planlama koşusunun.
3. **`publish_redaction_test.sh`'in `root` kör noktası** — süit `runner` için
   adıyla muafiyet yazmış, `root` kapsam dışı kalmış. Sızıntı yok.
4. **`docs/commands.md:57` hâlâ modu `~/.rabadon/enabled` diye tarif ediyor.**
   `gate.cpp` bunu **legacy** olarak okuyor; asıl anahtar `$RABADON_DIR/mode`
   ve katmanları. Belge modun nerede durduğu konusunda bir nesil geride.
5. **`native/cmdtext_test.sh:178` olay JSON'unu `python3` ile kuruyor** —
   "yalnız git ve shell" barı o dosyada tutulmuyor (konteynerde python3 olduğu
   için yeşil geçti).
6. **`make all` konteynerde exit 0 ama temiz değil:** `gate.cpp:454`
   `-Wmisleading-indentation` ve `drift.cpp:240` `-Wunused-function`.
   Birincisi `run_claude`'un yazma döngüsünde; gerçek bir hata mı yoksa çirkin
   biçimlendirme mi **belirlenmedi**.
7. **`make test`'in tek bir üyesi 9,4 dakika sürüyor** (`npm_install_test.sh`,
   562 s, konteynerde). Kusur değil, ama planlama koşusunun görmesi gereken
   bir sayı.
8. **`gate.cpp:2697-2705`'teki YAZILI, çözülmemiş CHALLENGE** (`enabled` +
   `mode.last` birleştirmesi vs `cli_test.sh:210`) hâlâ insan hükmü bekliyor;
   bu koşuda hiçbir faz sahiplenmedi.
9. **`installCursorHooks` okunamayan `hooks.json`'ı yedeksiz üstüne yazıyor**
   (F1c'den devralındı, hâlâ açık).
