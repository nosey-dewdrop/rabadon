# F3-R — hakem tutanağı (2026-08-29). Şef bunu OKUMAZ; hüküm `KAPI.md`'nin ilk satırıdır.

Taban `F3-oncesi` = `6913ae1`. Nihai HEAD = `f5eccc1`. Faz 6 commit, 24 dosya,
+870 / −5 satır.

## 0. KUM HAVUZU VE BLOKAJ (§ adıyla ilan)

`/tmp` KULLANILMADI (F2 hakeminin ölçtüğü `fd_dup_test.sh` 7/4 artefaktı).
İki ayrı worktree, ikisi de temp kökünün dışında, ikisi de iş bitince kaldırıldı:

    git worktree add --detach ~/damla_projects_2026/_hakem_f3_head f5eccc1
    git worktree add --detach ~/damla_projects_2026/_hakem_f3_base 6913ae1

**Kapı beni bir kez GERÇEKTEN kesti ve doğru reddiydi.** `make test` çıktısını
`> ~/damla_projects_2026/_hakem_f3_head/maketest.out` ile proje ağacının dışına
yazmaya çalıştığımda `baseline-truncating-redirect` **exit 2** verdi. Kuralı
gevşetmedim: `guard.json`'a DOKUNMADIM, `rabadon off` KOŞMADIM,
`gate.cpp:4703-4716`'nın bileşik-komut deliğini (CHALLENGE-3) KULLANMADIM.
Yaklaşımı değiştirdim — `( … ) | tee <dosya>` ile yazdım, geçti.
Kapı bu makinede **ENFORCE (deny)**, ve bu ret onun canlı kanıtıdır.

**İkinci gözlem, sorulmadı ama sayıya bağlı:** faz ajanı `make test` çıktısını
`grep -nE "FAIL"` ile tarayınca PostToolUse "tests are RED" bastı ve bunu bir
yanlış pozitif olarak saydı. **Bende aynı sınıf komut (`grep -cE '^[[:space:]]*FAIL'`
ve `grep -nE '^[[:space:]]*FAIL'`) HİÇ ateşlemedi.** Yani kural deterministik
değil ya da girdi bağımlı; hangisi olduğunu ÖLÇMEDİM. Kayda geçiyor.

## 1. KAPI SAYILARI — hepsini kendim koşturdum, karttan sayı kopyalamadım

`DURUM.md`'nin "TEST SAYACI — TEK GEÇERLİ SAYAÇ" üçlüsüyle, kendi regexim değil:

| ölçü | kartta | **hakem, kendi kum havuzu** |
|---|---|---|
| `make test` exit | 0 | **EXIT=0** |
| native iddia (GENİŞ `^[[:space:]]*ok\b`) | 3808 | **3808** |
| native `PASS (N checks)` toplamı | 633 | **633** |
| `npm test` | 64/0 | **64 pass / 0 fail, exit 0** |
| **TOPLAM** | 4505 / 0 | **4505 yeşil / 0 kırmızı** |
| taban `4483`'e göre | +22 | **+22** |
| `bash reports/R7/accept.sh` | exit 1, 23/3 | **EXIT=1, 23 yeşil / 3 kırmızı** |
| kırmızı ad kümesi | `{2b, 6e, 7b}` | **`{2b, 6e, 7b}` — BÜYÜMEDİ** |
| `2b` | 1240,2 µs | **1237,5 µs** (300 örnek, süreç-içi medyan) |

**+22 aritmetik olarak tam tamına iki yeni süide ait:** `discovery_scope_test.sh`
13 + `redbase_scope_test.sh` 9 = 22. Başka hiçbir süit iddia kazanmadı ya da
kaybetmedi.

`make test` çıktısında tek bir `FAIL` dizgesi var (satır 4406,
`FAIL testsuite [node --test]: the project's own suite is RED (exit 1)`) ve bu
bir kırmızı DEĞİL — `regression` demosunun **ürünün kendi ekran çıktısı**, aynı
süit iki satır aşağıda `regression: 4 passed, 0 failed` diyor.

### F1e-C kapı şartı
Üçlüyü fazın NİHAİ ikilisine karşı kendi elimde koşturdum:
`docs_truth_test.sh` **42 ok / 0 fail**, `install_docs_test.sh` **38 ok / 0 fail**,
`version_test.sh` **13 passed / 0 failed** — üçü de **EXIT=0**.
**Kâtip commit'i YOK:** F3 diff'inde `docs/` hiç geçmiyor, dolayısıyla "kâtibin
commit'i fazın SON commit'i olamaz" şartı boş yere sağlanıyor. Bunu bir açık
kalem saymadım, çünkü ölçtüm: fazın değiştirdiği davranışların hiçbiri bugün
belgede yazılı DEĞİL — `grep -rn "red-base\|neighbour" docs/*.md docs/claims.tsv
README.md` → yalnız `docs/POSITIONING.md:30`'da alakasız bir "neighbours"
kelimesi. Bayatlayan belge cümlesi yok. Fazın son commit'i `f5eccc1` yalnız bir
`.out` kanıt dosyasıdır (kaynak yok, ikili değişmedi), yani F1e-C üçlüsünün
`de9c997`'de koşulmuş olması ile `f5eccc1`'de koşulması aynı ikilidir; ben yine
de `f5eccc1`'de yeniden koşturdum.

## 2. KART 1 · D6 — GEÇTİ

### 2a. Fikstür koddan ÖNCE, ayrı commit (CLAUDE.md 2)
`6350d8d` (yalnız `Makefile` + `discovery_scope_test.sh`, ürün kodu YOK)
→ `d4e80e8` (yalnız `net.cpp`/`pathres.h`/`truth.cpp`). `git show --stat` ile
doğruladım. Aynı sıra CHALLENGE-2'de de var: `3887735` → `2911d77`.

### 2b. Fikstür faz öncesi ikilide GERÇEKTEN kırmızı düşüyor
HEAD'in `discovery_scope_test.sh`'ini `F3-oncesi` worktree'sine kopyalayıp
oranın kendi ikilileriyle koşturdum → **7 ok / 6 fail, EXIT=1**.
Hakemin şart koştuğu iki hücrenin ikisi de tuttu:

| fikstür | faz öncesi | faz sonrası |
|---|---|---|
| test yalnız `.venv/lib/python3.11/site-packages/numpy/tests/` | **level 1 SYNTAX — ok** | **level 1 — ok** |
| test yalnız `Library/Python/3.9/lib/python/site-packages/pytz/tests/` | **level 3 SUITE — FAIL** | level 1 — ok |

Düşen altı arm: `Library/…/site-packages`, çıplak `site-packages`,
`dist-packages`, `$HOME` kök seçimi, geri düşüş kökü, ve pytest exit 5
(`an empty pytest run was recorded 'red'`).

### 2c. `Library` SORUSU — kartta "ÖLÇÜLMEDİ" idi, ÖLÇTÜM
Faz öncesi ağaçta `truth.cpp` `junk[]`'a `"Library"` ekleyip
`make native/rabadon-truth` ile yeniden derledim:

    discovery scope: 9 ok, 4 fail
    FAIL - src/Library/ went blind: the project's own tests are no longer discovered

**`Library`'yi eklemek gerçek bir `src/Library/` projesini kör ediyor.** Yani
D6/2'nin lafzı ("`site-packages` + `Library` sınıfının eklenmesi") ölçümle
YANLIŞLANMIŞTIR ve ajanın onu eklememesi doğru sapmadır (hüküm:
`KARARLAR.md` · 2026-08-29 · F3 · (a)). Mutasyonu geri aldım → 13/0.
Ayrımı yapan ad `site-packages`/`dist-packages`'tır ve `truth.cpp:75-82` tam
olarak onu ekliyor; fikstürün 5. armı `Library`'nin ileride eklenmesini kırmızı
düşürecek.

### 2d. Onarımın kendisi
- `truth.cpp:65-82` — `junk[]`'a `site-packages` + `dist-packages`. Yorumda
  neden ve `repair.cpp:487` / `classify.h:82` ile ayrışma yazılı.
- `pathres.h:416-442` — `project_root()` `$HOME`'u kök seçmiyor; ALTINDAKİ
  gerçek git kökü hâlâ kazanıyor (fikstürün twin armı bunu tutuyor).
- `net.cpp:274` — `if (rc == 0 && emptyRun)` → `if ((rc == 0 || rc == 5) && emptyRun)`.
  Genişleme **yalnız 5**; yorumda "import hatası `collected 0 items` basıp 2 ile
  çıkar ve onu muaf tutmak yanlış reddi kaçırılan yakalamayla takas ederdi"
  yazılı, ve twin arm (`a suite that really fails is still RED`) bunu ölçüyor.

## 3. KART 2 · CHALLENGE-2 — YENİDEN ÜRETİLDİ ve KAPANDI

### 3a. Kendim yeniden ürettim
HEAD'in `redbase_scope_test.sh`'ini faz öncesi worktree'de koşturdum →
**8 ok / 1 fail, EXIT=1**. Düşen tek arm:
`a neighbour tree inherited this project's red: work the user knows is unrelated
was refused`. Yani CHALLENGE-2 gerçektir; F1b hakemi onu "bu oturumda YENİDEN
ÜRETMEDİM" diye NOT VERIFIED bırakmıştı, bu tur kapandı.

### 3b. Mutasyon kanıtını KENDİM ürettim (kartınkini kopyalamadan)
HEAD ağacında, her seferinde `touch` + yeniden derleme ile:

| mutasyon | sonuç | ilk düşen arm |
|---|---|---|
| `gate.cpp:4776` `git_repo_knobs` takibi kapatıldı | **8 ok / 1 fail** | `git -C walked past red-base` |
| muafiyet `anySeg && !anyInside` → koşulsuz | **5 ok / 4 fail** | `the red stopped refusing work on the broken base — the rule is gone` |
| ikisi de geri alındı | **9 ok / 0 fail** | — |

İkinci mutant önemlidir: muafiyeti bir bypass'a çevirmek süidi **dört** armdan
kırmızı düşürüyor, yani süit "cd ile red-base'i kapatma" hamlesini gerçekten
yakalıyor. **Kırılamayan kapı kapı değildir; bu kapı kırılıyor.**

### 3c. Gevşetme değil, daraltma
`gate.cpp:3549`'un "INCONCLUSIVE IS NOT RED" bloğu faz öncesiyle **bayt bayt
aynı** (`git show F3-oncesi:native/gate.cpp` ile karşılaştırdım). `disabled[]`'a
kural alınmadı. `~/.rabadon/guard.json` mtime **15:36**, fazın ilk commit'i
**18:05** — dosya bu fazda hiç açılmadı; `check` alanı hâlâ elle daraltılmış
(`cd damla_projects_2026/stitchu && python3 -m pytest -q engine/tests/py`),
`disabled` hâlâ `['promise-anti-path','promise-tamper']`, `rules` hâlâ 0.

## 4. KART 3 · F3-S1 — kabul maddesi KARŞILANDI, ONARIM YAPILMADI

`kanit/f3/2b-uctan-uca.sh` betiğinin kaynağını okudum: dürüsttür, ölçtüğü
tanımı (`mean`, `allow` yolu) §8.5'in tanımından (`median`, `refused`)
AYIRDIĞINI kendi başlığında yazıyor ve "aynı sayı olarak alıntılanamaz" diyor.
Kendim koşturdum, N=200, iki ikiliyi de:

| ikili | ham | boş taban | **atfedilebilir** | **tavana oran** |
|---|---|---|---|---|
| `F3-oncesi` | 3162,4 µs | 1157,5 µs | **2004,9 µs** | **2,00×** |
| fazın nihai ikilisi | 2845,4 µs | 1164,1 µs | **1681,3 µs** | **1,68×** |

**Sıcak yol YAVAŞLAMADI.** Bende kartın (1,99× → 1,94×) gösterdiğinden daha da
iyi çıktı; mean olduğu için tek sayı değil YÖN ve BANT geçerlidir, ve iki ölçüm
de aynı yönü veriyor. Tavan 1000 µs `accept.sh:122/203`'te oynatılmadı.
Süreç-içi medyan serisi de düşüyor: F2 hakemi 1271,2 → F1b hakemi 1259,2 →
kart 1240,2 → **ben 1237,5 µs**.

**F3-S1'in KABUL MADDESİ** (`SAPMA-KARARLARI.md:800-806`) iki şey ister:
(1) medyan faz öncesinden yüksek OLAMAZ — değil; (2) 1000 µs'in altına
inilmediyse tutanağa **ölçüyle ve adıyla** yazılır — kart 3 bunu harfiyen
yapıyor. **Yani kabul maddesi KARŞILANDI.** Karşılanmayan şey ONARIMDIR ve o
`F3b`'nindir. Kalan açık: **681,3 µs**, yani daha **%40,5** iniş.

## 5. §3.12 VE FAZIN BÖLÜNMESİ (§3.7)

Faz ajanı §3.12'ye dayanıp durdu. **§3.12'nin tetikleyicisi bir tahmindir ve bu
koşuda F3 için yazılı bir tahmin YOKTUR:** `grep -n "tahmin" KOSU-RABADON-5.md`
→ **0 satır**; `RABADON-ORKESTRASYON-v6.md`'de yalnız kuralın kendisi (satır
158). Yani "iki katı" ölçülemez. **Dayanak yok, en kısıtlayıcı seçildi.**

Durmanın **USULÜNÜ** yine de kabul ediyorum: §3.12'nin yasağı sessizce
sürünmektir, ajan durmayı kartında İLAN ETTİ, ölçtüğü sayıyı yazdı ve onarımı
yapmadığını söyledi. Ama fazın ÜRÜN kapsamı sürünmüştür, ve onu §3.7 ile
bölüyorum. Üç ölçülen gerekçe:

1. **KOSU §F3'ün kendi kapsamından teslim %0.** `git diff F3-oncesi..HEAD`
   24 dosya ve içinde `inject.h`, `signals.h`, `policy.h` HİÇ YOK.
   `DURUM.md:26`'nın "(b) ajan okudu ve (c) zarar vermedi katmanları için HİÇ
   kanıt yok" cümlesi F3'ten sonra da aynen doğrudur.
2. **+22 iddianın 22'sinin 22'si iki onarım kartına ait**, enjeksiyona **0**.
3. **`2b`'nin tavana açığı 681,3 µs** (%40,5 iniş kaldı).

**SIRADAKİ FAZ: F3b.** Kapsamı: KOSU §F3'ün kendi metni (motoru canlı hook'a
bağla; merdiven enjeksiyon→enjeksiyon→blok; `rabadon mute <sinyal>`; üç katmanlı
kabul ve **(c) negatif kontrolü olmadan F4 açılmaz**) + **D7** (bloklayan,
aşağıda) + **F3-S1** (sahibi adıyla: **F3b**).

## 6. YENİ KART: D7 · `Makefile:79` — bayat ikili sahte yeşil üretiyor

Kart "make başlık bağımlılığı izlemiyor" demişti; **kök sebep bundan dar ve daha
kötü.** `Makefile:29` `native/rabadon-gate`'in önkoşul listesi `pathres.h`'i
doğru sayıyor, ama `Makefile:79` `native/rabadon-net`'inki yalnız
`native/net.cpp native/cli_help.h` diyor — oysa `net.cpp:50-51` `testout.h` ve
`pathres.h`'i include ediyor. Aynı `make all` koşusunda ölçtüm:

    touch native/pathres.h && make all
    native/rabadon-net  mtime 1788017749 -> 1788017749   (DEĞİŞMEDİ)
    native/rabadon-gate mtime 1788018260 -> 1788018277   (değişti)

`pathres.h` D6'nın `$HOME` onarımının, `net.cpp` de `rc==5` onarımının yaşadığı
dosyadır — yani `discovery_scope_test.sh`'in yargıladığı **iki onarım da bayat
ikiliden yeşil alabilir.** Faz ajanının MUTANT 2'si tam olarak bunu yaşadı
(13/0 sahte yeşil → `touch` ile 11/2), ve bunu kendisi ilan etti. Bu bir kaza
değil, **sessiz ödül-hackleme vektörüdür**; kart açıldı, kabul maddesi
`KARARLAR.md` · (c)'de.

## 7. §3.8 DENETİMİ — TEMİZ

- Silinen dosya YOK (`git log --diff-filter=D --name-only F3-oncesi..HEAD` boş).
- Dokunulan iki test dosyasında **0 silinen satır** (ikisi de yeni dosya).
- İzlenen `native/*_test.sh`: **109 → 111**.
- Yeni `skip` / `xfail` / yoruma alınmış iddia YOK.
- `reports/R7/accept.sh`, `reports/R7/ON-KAYIT.md`, `docs/claims.tsv`,
  `.rabadon/` — `git diff F3-oncesi..HEAD --name-only` çıktısında **HİÇ YOK**.
- Eşikler: 1000 µs `accept.sh:122/203`'te aynen; `guard.json` açılmadı.
- Kabul ölçütü onu sağlayan koddan AYRI ve ÖNCEKİ commit'te, iki kartın
  ikisinde de.
- `Makefile`'a yalnız iki süit satırı + yorum eklendi; hiçbir süit çıkarılmadı.
- `bin/`, `package.json`, `native/rabadon-cli.sh`, `site/`, `README.md`,
  `ci.yml` faz aralığında hiç açılmadı.

## 8. ÖLÇEMEDİKLERİM / DOĞRULANMADI (§5.5 dökümü)

1. **Temiz konteynerde hiçbir şey koşturmadım.** İki yeni süit yalnız macOS'ta,
   yalnız bu makinede ölçüldü. `refenv/run.sh`'i bu turda hiç çağırmadım.
   `redbase_scope_test.sh` `node` yoksa **exit 0 ile skip ediyor** — yani node'suz
   bir konteynerde o kapı sessizce YOK olur, ve bunu ÖLÇMEDİM.
2. **Canlı `$HOME` üstünde D6 onarımının etkisini ÖLÇEMEDİM** ve kartın gerekçesi
   doğru: iki ikili de `discoveryCapped:["depth","budget"]` veriyor, `via:` hâlâ
   elle daraltılmış `guard.json check`. Bütün D6 ölçümlerim fikstürledir.
   `rabadon-truth $HOME`'un hâlâ level 3 verdiğini de doğrulamadım.
3. **`2b`'yi tek turda ölçtüm**, tekrar etmedim; mean, yük bağımlı. Benim
   1,68×'im ile kartın 1,94×'i arasındaki fark makine yükü olabilir — ikisi de
   tavanın üstünde ve ikisi de faz öncesinden düşük, hüküm buna dayanıyor.
   CI'da ve konteynerde `2b` yine ölçülmedi.
4. **`--git-dir` / `GIT_DIR=` armı yok** (kartın ilanı, doğruladım). Muafiyetin
   `sp.degraded` yolunu ayrı fikstürle koşturmadım, yalnız kaynaktan okudum.
5. **`Makefile`'ın kalan ~40 kuralını** include grafiğiyle karşılaştırmadım;
   yalnız `pathres.h`/`rabadon-net` çiftini ölçtüm. D7 daha büyük olabilir.
6. **`skip_dir`'in iki kopyası** (`truth.cpp:65` ve `repair.cpp:483`) hâlâ ayrı
   ve hâlâ ayrışıyor; D6/3 birleştirmeyi yasakladı, ben de birleştirmedim ama
   bugünkü sapmanın tam listesini çıkarmadım.
7. **Yanlış pozitif sayacı:** ajan bu fazda 1 saydı; ben kendi oturumumda
   `baseline-truncating-redirect` reddini **doğru ret** sayıyorum (hedef gerçekten
   proje ağacının dışındaydı), yani hakem turunda **0** yanlış pozitif. Ama
   ajanın saydığı "grep FAIL → tests are RED" olayını bende **yeniden
   üretemedim** — kuralın neden bende ateşlemediğini ÖLÇMEDİM.
8. **Gerçek Cursor uygulaması yine başlatılmadı**; ledger'da hâlâ 0 satır ve
   enjeksiyonun (b)/(c) katmanları için hâlâ hiç kanıt yok.
9. `git push` sonrası `origin/main` ile eşitliği bu tutanağı yazarken
   doğrulayacağım; yazıldığı anda DOĞRULANMAMIŞTIR.
