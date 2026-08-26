# envanter-d — test/kabul durumu + npm durumu

Repo: /Users/damummyphus/damla_projects_2026/rabadon-kosu4 (dal: kosu4)
Tarih: 2026-08-26
Makine: darwin arm64, Apple clang 17.0.0, node v26.5.0
  KOMUT: `node --version; c++ --version | head -2`

Hiçbir test veya kaynak dosya DEĞİŞTİRİLMEDİ. `npm publish` KOŞTURULMADI.
Ağa yazan komut koşturulmadı; sadece `npm view` (okuma) koşturuldu.

---

## (e) Kabul / test durumu

### e1. Test süiti hangi komutla koşuyor?

İKİ ayrı süit var. Biri ötekini çağırmıyor.

**Süit 1 — native C++ süiti: `make test`**
  KOMUT: `grep -n "^test[a-z0-9_-]*:" /Users/damummyphus/damla_projects_2026/rabadon-kosu4/Makefile`
  ÇIKTI: `104:test: all`

Hedefin tanımı: `test: all` — yani önce `all` (21 native binary) derlenir, sonra
gövdesindeki 100 kabuk süiti sırayla koşar.
  KOMUT (hedefin gövdesindeki komut satırlarını basar):
  `awk 'NR>=104{if(NR>104 && /^[a-zA-Z0-9_.\/-]+:/) exit; if(/^\t/) print NR": "$0}' /Users/damummyphus/damla_projects_2026/rabadon-kosu4/Makefile`
  ÇIKTI: 100 satır, hepsi `./native/<ad>_test.sh` biçiminde
  (ilk: 105 `./native/version_test.sh`, son: 912 `./native/identity_test.sh`).
  KOMUT (sayısı): aynı awk `| wc -l` → `100`

`all` hedefi (satır 12) 21 binary üretir:
  KOMUT: `grep -n "^all:" /Users/damummyphus/damla_projects_2026/rabadon-kosu4/Makefile`
  ÇIKTI: `12:all: native/rabadon-net native/rabadon-truth ... native/gate_bench`

**Süit 2 — node süiti: `npm test`**
  KOMUT: `grep -n '"test"' /Users/damummyphus/damla_projects_2026/rabadon-kosu4/package.json`
  ÇIKTI (satır 25):
  `"test": "node --test core/rabadon.test.mjs core/wrap.test.mjs core/bus.test.mjs core/store.test.mjs ui/server.test.mjs hooks/install.test.mjs hooks/gate.test.mjs hooks/guard-gen.test.mjs demo/live-repair-evidence.test.mjs"`

BULGU: `make test` içinde `npm test` YOK; `npm test` içinde de `make` yok. İki süit
birbirini çağırmıyor — "make test yeşil" tek başına node tarafını kapsamıyor.
  KOMUT: `grep -n "npm test\|npm run test" /Users/damummyphus/damla_projects_2026/rabadon-kosu4/Makefile` → çıktı yok (satır 104-942 aralığında hiçbir eşleşme).

### e2. Derleme (native/C++)

Derleme GEREKLİ ve BAŞARILI.
  KOMUT: `{ time make -C /Users/damummyphus/damla_projects_2026/rabadon-kosu4 all ; } > reports/kosu/RAPOR/envanter-d-build.out 2>&1; echo "BUILD EXIT=$?"`
  ÇIKTI: `BUILD EXIT=0`, 21 binary derlendi.
  SÜRE: `30,70s user 1,40s system 98% cpu 32,503 total` → **32,5 sn**

Derleme uyarısı (hata değil, tek uyarı):
  `native/drift.cpp:240:23: warning: unused function 'generated_patterns' [-Wunused-function]`
  `1 warning generated.`
  Tam derleme çıktısı: reports/kosu/RAPOR/envanter-d-build.out

"ÖLÇÜLEMEDİ: derleme kırık" DEĞİL — derleme temiz.

### e3. Süitler GERÇEKTEN koşturuldu

**make test**
  KOMUT: `{ time make -C /Users/damummyphus/damla_projects_2026/rabadon-kosu4 test ; } 2>&1 | tee reports/kosu/RAPOR/envanter-d-test.out`
  ÇIKIŞ KODU: `MAKE_TEST_PIPESTATUS=0`
  SÜRE: `104,07s user 38,06s system 44% cpu 5:17,73 total` → **5 dk 17,73 sn**
  ÇIKTI DOSYASI: /Users/damummyphus/damla_projects_2026/rabadon-kosu4/reports/kosu/RAPOR/envanter-d-test.out (4306 satır)

**npm test**
  KOMUT: `{ time npm test --prefix /Users/damummyphus/damla_projects_2026/rabadon-kosu4 ; } 2>&1 | tee -a reports/kosu/RAPOR/envanter-d-test.out`
  ÇIKIŞ KODU: `NPM_TEST_EXIT=0`
  SÜRE: `1,36s user 0,32s system 95% cpu 1,754 total` → **1,75 sn** (node'un kendi ölçümü: `duration_ms 1592.479208`)
  Aynı .out dosyasının sonuna `########## IKINCI SUITE: npm test ##########` başlığıyla eklendi.

### e4. Kaç YEŞİL, kaç KIRMIZI

**make test (native, 100 süit):**
  Koşan süit sayısı: **100**
    KOMUT: `grep -cE "^\./native/[a-z0-9_]+(_test|_demo)\.sh$" envanter-d-test.out` → `100`
  Geçen tekil iddia (assertion) satırı: **3438 ok**
    KOMUT: `grep -cE "^\s*ok\b" envanter-d-test.out` → `3438`
  Özet satırı basan 53 süitin toplamı: **1944 passed / 0 failed**
    KOMUT: `grep -oE "[0-9]+ passed, [0-9]+ failed" envanter-d-test.out | awk '{p+=$1;f+=$3} END{print "passed="p" failed="f}'`
    ÇIKTI: `passed=1944 failed=0`
    (53 süit kendi özetini basıyor, kalan 47'si basmıyor — bu yüzden 3438 ok sayısı asıl ölçü.)
  KIRMIZI: **0**

**npm test (node --test):**
  `tests 64 / suites 0 / pass 64 / fail 0 / cancelled 0 / skipped 0 / todo 0`
    KOMUT: `grep -nE "^ℹ (tests|pass|fail|skipped|todo)" envanter-d-test.out`
  KIRMIZI: **0**

**TOPLAM: 0 KIRMIZI. İki süit de yeşil.**

### e5. KIRMIZILARIN ADLARI

**Kırmızı YOK — liste boş.**

Adları basacak komutlar (hepsi boş döndü):
```
# 1) failed>0 olan süit özet satırları
grep -nE "[0-9]+ passed, [1-9][0-9]* failed" \
  /Users/damummyphus/damla_projects_2026/rabadon-kosu4/reports/kosu/RAPOR/envanter-d-test.out
#   -> çıktı yok (exit 1)

# 2) make'in durduğu yer / hata satırı
grep -nE "make: \*\*\*|Error [0-9]+$" \
  /Users/damummyphus/damla_projects_2026/rabadon-kosu4/reports/kosu/RAPOR/envanter-d-test.out
#   -> çıktı yok

# 3) node --test kırmızı adları
grep -nE "^✖|^not ok|^ℹ fail [1-9]" \
  /Users/damummyphus/damla_projects_2026/rabadon-kosu4/reports/kosu/RAPOR/envanter-d-test.out
#   -> çıktı yok
```

TUZAK (yanlış okumaya açık tek satır): .out dosyasının 3917. satırında
`FAIL testsuite [node --test]: the project's own suite is RED (exit 1)` yazıyor.
Bu bir KIRMIZI DEĞİL — `./native/regression_demo.sh`'ın kasten kırdığı sahte
projede rabadon'un ne rapor ettiğini gösteren FİKSTÜR çıktısı. Hemen altındaki
satır: `regression: 4 passed, 0 failed`.
  KOMUT: `sed -n '3910,3920p' .../envanter-d-test.out`

### e6. make test'in yapısal sınırı (bulgu)

100 süitin hepsi TEK bir make recipe'inin satırları. Bir satır kırmızıya
düşerse make orada durur ve kalan süitler HİÇ koşmaz; `make -k` de bunu
değiştirmez (aynı recipe içi). Yani `make test` "kaç kırmızı" sorusuna değil,
"ilk kırmızı nerede" sorusuna cevap veren bir süit. Bu koşuda hepsi yeşil
olduğu için fark etmedi, ama kırmızı bir günde tam kırmızı listesi ancak
süitler tek tek koşturularak çıkar.

---

## (f) npm durumu

### f1. `npm view rabadon version`

  KOMUT: `npm view rabadon version`
  ÇIKIŞ KODU: 1
  TAM ÇIKTI:
```
npm error code E404
npm error 404 Not Found - GET https://registry.npmjs.org/rabadon - Not found
npm error 404
npm error 404  The requested resource 'rabadon@*' could not be found or you do not have permission to access it.
npm error 404
npm error 404 Note that you can also install from a
npm error 404 tarball, folder, http url, or git url.
npm error A complete log of this run can be found in: /Users/damummyphus/.npm/_logs/2026-08-26T01_57_17_867Z-debug-0.log
```
SONUÇ: `rabadon` adı npm registry'de YOK. Hiç yayımlanmamış.

Ek ölçüm — package.json'ın optionalDependencies'inde adı geçen 4 platform paketi de yok:
  KOMUT: `for p in @rabadon/darwin-arm64 @rabadon/darwin-x64 @rabadon/linux-x64 @rabadon/linux-arm64; do printf "%s: " "$p"; npm view "$p" version 2>&1 | head -2 | tr '\n' ' '; echo; done`
  ÇIKTI: dördü de `npm error code E404 ... Not found`.
BULGU: `npm i -g rabadon` bugün çalışmaz; postinstall kaynaktan derlemeye
düşer (`"postinstall": "node scripts/build.mjs"`, package.json:24).

### f2. package.json "name" ve "version"

  KOMUT: `grep -n '"version"\|"name"' /Users/damummyphus/damla_projects_2026/rabadon-kosu4/package.json`
  ÇIKTI:
```
2:  "name": "rabadon",
3:  "version": "0.2.3",
```
optionalDependencies içindeki 4 platform paketi de `0.2.3` pinli (package.json:18-21).
  KOMUT: `grep -n '@rabadon/' /Users/damummyphus/damla_projects_2026/rabadon-kosu4/package.json`

### f3. `git tag --list`

  KOMUT: `git -C /Users/damummyphus/damla_projects_2026/rabadon-kosu4 tag --list`
  ÇIKTI:
```
v0.2.0
v0.2.1
v0.2.2
```
BULGU: package.json 0.2.3 diyor, ama v0.2.3 etiketi YOK. Etiketler yayımdan bir
sürüm geride; 0.2.3 ne etiketli ne yayımlanmış.

---

## ÖLÇÜLEMEDİ / DOĞRULANMADI

- **Temiz makinede (fresh clone, boş container) koşum: ÖLÇÜLEMEDİ.** Her şey bu
  Mac'te, mevcut çalışma ağacında koştu. CLAUDE.md'nin referans ortamı temiz bir
  container; bu koşu onu temsil etmiyor.
- **Linux'ta koşum: ÖLÇÜLEMEDİ.** Sadece darwin/arm64 ölçüldü.
- **Süit tek tek koşturulmadı**, `make test` toplu koşturuldu; bu yüzden "her süit
  tek başına da yeşil mi" DOĞRULANMADI (süitler arası paylaşılan durum olabilir).
- **npm publish kuru koşusu (`npm publish --dry-run`) KOŞTURULMADI** — kart ağa
  yazan/publish komutlarını yasakladı; --dry-run yazmasa da riske girilmedi.
  Dolayısıyla `files[]` listesinin gerçekten doğru tarball ürettiği DOĞRULANMADI.
- **`make bench` / `make promises` gibi diğer hedefler koşturulmadı** — kart
  test süitini istedi.
- 47 native süit kendi passed/failed özetini basmıyor; onların iç iddia sayısı
  `ok` satırı sayımıyla toplandı, süit bazında ayrıştırılmadı.
