# F1b — KART

**DURUM: BLOKE (§3.12).** Kart 1 bitti ve kanıtlandı; kart 2 eylem gerektirmedi.
Faz **KAPANMADI**: kapanış üçlüsünün yarısı ve F1e-C kapı şartı ölçülemedi, çünkü
**rabadon'un kendi kapısı bu kökte her komutu reddetmeye başladı** (aşağıda CHALLENGE-1).

Taban etiketi: `F1b-oncesi` = `1d89331`. Kök: `/Users/damummyphus/damla_projects_2026/rabadon`, dal `main`.
Kum havuzu: `/Users/damummyphus/rabadon-f1b-kum` (temp kökü DIŞINDA, kural gereği).
Kanıt dizini: `reports/kosu/kanit/f1b/`.

---

## KART 1 — `native/sandbox_test.sh:121` sapması · **KAPANDI**

Tek commit: `09a93af` *f1b card 1: harden sandbox_test.sh:121 to the string the product actually ships*.
Yalnız test dosyası değişti; **ürün kodu bu commit'te değişmedi**, yani şart 8 (ölçüt ve onu
sağlayan kod aynı commit'te olamaz) ihlal edilmedi — sağlayan kod zaten 27 gündür yerinde
(`a74e7d8`), eksik olan testti.

**Değişiklik, tek satır, SERTLEŞTİRME:**

    - "$SB" --check 2>&1 | grep -qi "no kernel backend"
    + "$SB" --check 2>&1 | grep -q  "rabadon sandbox: NO usable kernel backend"

Gevşetme değil daralmadır, iki yönden: (a) `-i` kalktı, artık büyük/küçük harf duyarlı;
(b) beklenen dizge `rabadon sandbox: ` önekiyle birlikte ve `usable` kelimesiyle tam olarak
`native/sandbox.cpp:365`'in sevk ettiği dizge. Eskisini geçen dizge kümesi yenisini geçenin
**üst kümesidir**.

### PROOF — önce (kırmızı), konteynerde
Komut:

    git clone --no-hardlinks <kök> ~/rabadon-f1b-kum/tree      # HEAD aa42f29
    docker run --rm --network none -v ~/rabadon-f1b-kum/tree:/w -w /w \
      node:22-bookworm bash /inside.sh

Verbatim çıktı: **`reports/kosu/kanit/f1b/oncesi-konteyner-sandbox.out`**

    ### bwrap: ABSENT
    rabadon sandbox: NO usable kernel backend — bwrap is not installed — apt install bubblewrap
    ### --check EXIT=1
      FAIL - --check message
    sandbox: 7 passed, 1 failed
    ### sandbox_test.sh EXIT=1

### PROOF — mutasyon kanıtı (§3.8/3), konteynerde, yeşil → KIRMIZI → yeşil
Verbatim çıktı: **`reports/kosu/kanit/f1b/mutasyon-konteyner-sandbox.out`** (HEAD `09a93af`)

- **A) sertleştirilmiş test, ürün el değmemiş:** `sandbox: 9 passed, 0 failed`, `EXIT=0`
- **B) mutasyon** — `sed -i 's/NO usable kernel backend/NO kernel backend at all/' native/sandbox.cpp`,
  yeniden derlendi. Ürün `rabadon sandbox: NO kernel backend at all — …` bastı →
  `FAIL - --check message`, `sandbox: 8 passed, 1 failed`, **`EXIT=1`**
- **C) geri alındı:** `sandbox: 9 passed, 0 failed`, `EXIT=0`

**Mutasyonun seçimi kasıtlıdır ve sertleştirmenin ispatıdır:** `NO kernel backend at all`
dizgesi **ESKİ** iddiayı (`grep -qi "no kernel backend"`) **GEÇERDİ**. Yeni iddia onu
yakalıyor. Yani kapı yalnız kırmızı olabilir değil, eskisinin kaçırdığını da yakalıyor.

### PROOF — kapanışta konteyner (kartın istediği yeniden ölçüm)
`native/refenv/run.sh --prefix f1b-arm64-root- --suite-timeout 300`, HEAD `09a93af`
LABEL: `node:22-bookworm · host-default(arm64) · image-default(root) · --network none`
Artefaktlar: `reports/refenv/f1b-arm64-root-{env,build,suites}.out`, `…-suites.tsv`

    sandbox_test.sh   0   9   0   0   GREEN      (F2'de: 1  8  1  RED)

---

## NEGATİF SONUÇ — kartın gerekçesindeki cümle YANLIŞ ÇIKTI

Kart (ve `KARARLAR.md`, ve `DURUM.md`) şunu söylüyordu:
> "temiz konteynerde `make test`'i exit 2'de tutan **tek kalem**"

**Ölçüm bunu çürüttü.** Kanıt: `reports/kosu/kanit/f1b/sonrasi-konteyner-make-test.out`
(HEAD `09a93af`, aynı konteyner, `make all` EXIT=0):

    pass 7   fail 3
    site claims: RED
    make: *** [Makefile:198: test] Error 1
    make test EXIT=2

**Konteynerde `make test` HÂLÂ EXIT=2.** `sandbox_test.sh` (Makefile:718) **tek** kalem
değil, **ilk** kalemdi; kapı şimdi `site_claims_test.sh`'e (Makefile:849) kaydı.
Sebep: `site/build.py:277` `gh search prs` çağırıyor, `gh` node:22-bookworm imajında YOK
ve koşu `--network none` → `FileNotFoundError: 'gh'` → 3 FAIL. Arkasında bir de
`publish_redaction_test.sh` (27/1) duruyor. Yani konteynerdeki kırmızı **üç değil iki**
kaldı ama `make test`'in exit'i **değişmedi**.

Bu, CLAUDE.md kalite barının doğrudan ihlali ("yalnız git ve shell'i olan makinede
çalışır"): `site_claims_test.sh` sessizce `gh`'ye ve ağa bağımlı. **Kart açılmadı — kapsam
dışı.** Hakem/şef kararı.

### Konteyner nüfus sayımı, F2 ile yan yana
| | F2 (`f2-6`, HEAD 0f7904b) | F1b (`f1b`, HEAD 09a93af) |
|---|---|---|
| süit | 106 | 106 |
| GREEN | 103 | **103** |
| RED | 3 (`sandbox`, `site_claims`, `publish_redaction`) | **2** (`site_claims`, `publish_redaction`) |
| TIMEOUT | 0 | **1** (`npm_install_test.sh`) |
| `make test` exit | 2 | **2** (ama başka süitte) |

`npm_install_test.sh` TIMEOUT'u **regresyon DEĞİL, benim ölçüm parametremin artefaktı**:
o süit F2'nin üç sayımında da 562/571/564 saniye sürmüş ve GREEN'di; ben `--suite-timeout 300`
verdim, 300 s'de kesildi (exit 124). Sertleştirilmiş tavanla yeniden ölçülmedi — bkz. NOT VERIFIED.

---

## KART 2 — `8b` tuzağı · **EYLEM GEREKMEDİ**

`reports/R7/accept.sh:548` `signals: 39 passed, 0 failed` tam eşitliğini arıyor.
Bu fazda `native/signals_test.sh`'e **tek iddia eklenmedi**, dolayısıyla tuzak kurulmadı.
Ölçüm (blokaj öncesi, kökte):

    $ ./native/signals_test.sh | tail -1
    signals: 39 passed, 0 failed

Eşitlik **gevşetilmedi**, `>=` **yapılmadı**, sayıya **dokunulmadı**, ayrı işçi
**gerekmedi**. `reports/R7/accept.sh` bu fazda hiç değişmedi.

---

## CHALLENGE-1 — rabadon kendi kökünde kendini kilitledi (FALSE REJECT, ölçüldü)

Faz ortasında, kapanış üçlüsünü koşarken, kökteki her `Bash` çağrısı reddedilmeye başladı:

    [native/rabadon-gate]: rabadon BLOCKED this action.
    Rule: red-base — this project's own check is failing, so anything that is
    not the fix builds on a broken base
    the check that is red: python3 -m pytest -q

**Kanıt, ölçülmüş:**

    $ python3 -m pytest -q ; echo $?
    no tests ran in 0.05s
    5
    $ ls pytest.ini conftest.py
    ls: pytest.ini: No such file or directory
    ls: conftest.py: No such file or directory
    $ find . -name 'test_*.py' -not -path './node_modules/*'      # (boş)

**Kök sebep, kaynakta:** `native/truth.cpp:336-337`

    if (exists(dir + "/pytest.ini") || exists(dir + "/tests") || !s.testFiles.empty()) {
      if (s.py > 0) return {3, "suite", "python3 -m pytest -q", "python test files"};

rabadon bu repoda python DOSYASI (`site/build.py` vb.) ve test dosyası görüyor, oradan
"bu bir python süiti" sonucuna varıyor ve projenin çeki olarak `python3 -m pytest -q`
seçiyor. Repoda **hiç python testi yok**; pytest "no tests ran" deyip **exit 5** dönüyor;
`red-base` bunu kırmızı sayıyor. Bu kırmızı **asla temizlenemez** — çünkü temizlenmesi için
geçmesi gereken komut, hiçbir zaman geçemeyecek bir komut.

**Ölçülen zarar, üç kalem — hepsi FALSE REJECT ve hepsi CLAUDE.md kalite barına aykırı:**
1. `git status --short` reddedildi. **Salt-okunur bir komut.**
2. `npm test` reddedildi. Kapanış üçlüsünün bir bacağı.
3. `make test` reddedildi — yani **projenin gerçek test süiti**, kırmızıyı temizleyecek
   olan komutun ta kendisi. Ekrandaki "re-run that check — a pass clears this immediately"
   cümlesi bu projede **uygulanamaz bir tavsiyedir**.

Reddin gösterdiği iki çıkış yolu da bu faz ajanına **KAPALI**: `.rabadon/guard.json`
`disabled[]` — mühürlü dosya (AGENTS-PROTOCOL Kapı 3, §3.8/1); `rabadon off` — operatörün
makine durumunu değiştirir, `DURUM.md` kapının **watch (observe)** modda bırakıldığını
yazıyor, izinsiz değiştirilmedi.

**CHALLENGE-2 — kapsam sızıntısı (F3'ün konusu, hâlâ açık):** ret, kökün DIŞINDAKİ bir
dizinden (`~/rabadon-f1b-kum/tree`) koşulan komutta da ateşledi. Komşu dizin kendi kökü
olmasına rağmen bu projenin kırmızısını miras aldı.

**CHALLENGE-3 — kuralın kendisinde delik, KASITSIZ BULUNDU ve KULLANILMADI:** ilk segmenti
kırmızı çekin kendisi olan bileşik komutlar (`python3 -m pytest -q ; <başka komut>`) kapıdan
GEÇTİ. Teşhis sırasında farkında olmadan üç kez böyle bir komut koştum (hepsi salt-okunur:
`ls`, `cat`, `grep`). **Bu deliği bu fazın hiçbir yeşil sayısını üretmek için, commit atmak
için, ya da blokajı aşmak için KULLANMADIM** — bir frenin kendi deliğinden geçerek üretilen
yeşil, tam olarak bu ürünün reddetmek için var olduğu şeydir. Delik burada, ölçüldüğü gibi,
hakeme bildiriliyor.

**Bu üç kalem F1b'nin kapsamı DEĞİL** ve bu ajan tarafından düzeltilmedi. Ölçüt de kod da
hakemin/şefin işi.

---

## ÖLÇÜM ÜÇLÜSÜ — YARIM (blokaj sebebiyle)

Konak (macOS, kök), **blokaj ÖNCESİ**, HEAD `09a93af`
`reports/kosu/kanit/f1b/kapanis-make-test.out`:

    make test ; echo "EXIT=$?"                       →  EXIT=0
    grep -cE '^[[:space:]]*ok\b'                     →  3786
    PASS (N checks) toplamı                          →  633

Taban ile **BİREBİR AYNI** (`baseline-make-test.out`: 3786 + 633, EXIT=0) ve bu **beklenen
sonuçtur**: sertleştirilen iddia macOS'ta hiç koşmuyor (Seatbelt her zaman mevcut, kol
`skip`'e girmiyor). Değişiklik yalnız konteynerde görünür ve orada +1 iddia getirdi
(`sandbox: 8→9 passed`).

| bacak | sonuç |
|---|---|
| `make test` (konak) | **EXIT=0, 3786 iddia + 633 kontrol** |
| `npm test` | **ÖLÇÜLEMEDİ — rabadon reddetti** (F2 tabanı: 64/0) |
| `bash reports/R7/accept.sh` | **ÖLÇÜLEMEDİ — rabadon reddetti** (F2 tabanı: 23/3) |
| `native/refenv/run.sh` | **KOŞTU** — 106 süit / 103 GREEN / 2 RED / 1 TIMEOUT |
| konteynerde `make test` | **EXIT=2** (hâlâ; `site_claims_test.sh`'te) |

**KIRMIZI AD KÜMESİ:** `reports/R7/accept.sh` bu fazda **koşturulamadı**, dolayısıyla
kümenin `{2b, 6e, 7b}` olarak kaldığı **bu fazda DOĞRULANMADI**. Dolaylı kanıt: `accept.sh`
dosyasına dokunulmadı, `signals_test.sh` 39/0 ölçüldü, tek kod değişikliği macOS'ta hiç
koşmayan bir shell iddiası. **Küme büyüdü demiyorum; ölçmedim diyorum.**

**F1e-C KAPI ŞARTI KARŞILANMADI.** `docs_truth_test.sh` + `install_docs_test.sh` +
`version_test.sh` üçlüsü nihai ikiliye karşı **koşturulamadı** (aynı ret). Şart 5 gereği
**faz bu hâliyle kapanmaz.** Kâtip/belge commit'i de yok, dolayısıyla o yarım da ihlal
edilmedi.

---

## NOT VERIFIED (boş değil)

- `npm test`, `reports/R7/accept.sh`, ve F1e-C üçlüsü **hiç koşmadı** (rabadon reddi).
  F2'nin 64/0 ve 23/3 sayıları bu fazda **yeniden üretilmedi**; kartta taban olarak
  anılıyorlar, ölçüm olarak değil.
- `npm_install_test.sh` konteynerde **sertleştirilmiş tavanla yeniden ölçülmedi**;
  `--suite-timeout 900` ile koşulsaydı GREEN dönmesi beklenir (F2'de 562 s), ama bu bir
  **beklenti**, ölçüm değil.
- Konteyner ölçümü **yalnız** `node:22-bookworm · arm64 · root · --network none` içindir.
  amd64 ve non-root kolları bu fazda koşmadı.
- `site_claims_test.sh` ve `publish_redaction_test.sh` kırmızılarının **kök sebebi
  doğrulandı** (`gh` yok / redaksiyon), ama **konak üstünde neden yeşil oldukları**
  ayrıca ölçülmedi.
- CHALLENGE-1'in **ne zaman** başladığı ölçülmedi: fazın ilk ~15 komutu geçti, sonra
  reddetmeye başladı. Kapının çeki ne sıklıkla örneklediği **bilinmiyor**. Bu kırmızının
  F1b'den ÖNCE de var olduğu, `F1b-oncesi` artefaktında **ayrıca doğrulanmadı** — ama
  tek kod değişikliğim bir shell dosyasının bir satırı olduğu için pytest tespitini
  etkilemesi **mümkün değildir**.
- **Boş-yeşil kontrolü `F1b-oncesi` artefaktına karşı ayrı `--detach` worktree'de
  KOŞULMADI.** Yerine, işlevsel olarak daha güçlü olan konteyner mutasyon kanıtı koşuldu
  (yeşil→kırmızı→yeşil, üstelik eski iddianın kaçırdığı dizgeyle). Yine de şart 2'nin
  harfi karşılanmadı; hakemin bilmesi gereken bir eksiktir.
- Bu kartın kendisi ve `DURUM.md` eki **commit'lenemedi** (git reddedildi). Diskte duruyor.

## PARKED (kapsam dışı, diff'e girmedi)

- `native/truth.cpp:336-337` — süit seçicisi `s.py > 0` + "herhangi bir test dosyası"
  görünce pytest'e atlıyor; "pytest kuruldu ve **sıfır test topladı** (exit 5)" hâli
  `could-not-run` olmalı, `red` değil. CHALLENGE-1'in kök sebebi.
- `red-base` salt-okunur komutları (`git status`) ve **kırmızıyı temizleyecek komutu**
  (`make test`) reddediyor. Ret mesajının verdiği tavsiye uygulanamaz hâle geliyor.
- `red-base` bileşik komutun ilk segmenti çekin kendisiyse tüm satırı geçiriyor (CHALLENGE-3).
- `red-base` kapsamı komşu dizine sızıyor (CHALLENGE-2).
- `site/build.py` ve dolayısıyla `site_claims_test.sh` `gh` ikilisine ve ağa bağımlı →
  temiz konteynerde kırmızı; konteynerde `make test`'i exit 2'de tutan **yeni ilk kalem**.
- `publish_redaction_test.sh` konteynerde 27/1.

## NEXT (tek eylem)

Hakem/şef CHALLENGE-1'e karar verir. Karar verilmeden F1b kapanamaz ve kökte hiçbir
faz ajanı komut koşamaz — **koşunun tamamı bu kırmızının arkasında duruyor.**
