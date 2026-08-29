# F3b — HAKEM RAPORU (2026-08-29)

Kum havuzu: `~/damla_projects_2026/_hakem_f3b_head` (HEAD `411714d`) ve
`_hakem_f3b_base` (`F3b-oncesi` = `2f4c592`), iki ayrı `--detach` worktree,
**`/tmp` DIŞINDA** (DURUM.md:578 muafiyet artefaktı tuzağı), ikisi de kaldırıldı.
Karttaki hiçbir sayı kopyalanmadı; hepsi burada yeniden koşturuldu.

## 1. SAYAÇ — kartın 4513'ü BİREBİR TUTTU

DURUM.md "TEST SAYACI — TEK GEÇERLİ SAYAÇ" üç komutu, kendi kum havuzumda:

| ölçü | taban (F3 sonrası) | **hakem, bugün** |
|---|---|---|
| `make test` exit | 0 | **0** (`make: ***` satırı YOK) |
| native iddia (GENİŞ `^[[:space:]]*ok\b`) | 3808 | **3816** |
| native `PASS (N checks)` | 633 | **633** |
| `npm test` | 64/0 | **64 pass / 0 fail** |
| **TOPLAM** | 4505 | **4513 yeşil / 0 kırmızı (+8)** |

+8'in tamamı iki yeni koldan: `make_deps_test.sh` **7** + `day_cache_test.sh`'in
`COLD_FIRST_US` armı **1**. Aritmetik kapanıyor.

`bash reports/R7/accept.sh` → **EXIT=1, 23 yeşil / 3 kırmızı**, kırmızı **ad**
kümesi **`{2b, 6e, 7b}` BÜYÜMEDİ** (§3.6 tutuyor). Süreç-içi `2b` bende
**1220,0 µs** (300 örnek medyanı) — kart 1218,7, F3 hakemi 1237,5. **Yükselmedi.**
Tavan `accept.sh:122/203`'te hâlâ **1000 µs**; `git diff F3b-oncesi..HEAD --
reports/R7/accept.sh reports/R7/ON-KAYIT.md docs/claims.tsv .rabadon/` → **0 satır**.

F1e-C üçlüsü fazın NİHAİ ikilisine karşı, kendi elimde: `docs_truth_test.sh`
**42/0**, `install_docs_test.sh` **38/0**, `version_test.sh` **13/0**.
Kâtip commit'i **YOK** — fazda `docs/` hiç değişmedi. F3'te de böyleydi; şart
boşluğa düşerek sağlanıyor. **Bu iki fazdır üst üste böyle — O5'in altına yazdım.**

## 2. D7 — GERÇEKTEN KAPANDI (kartın kanıtını kopyalamadım, dördünü de kendim ürettim)

1. **BOŞ YEŞİL (§8.2).** `make_deps_test.sh`'i `F3b-oncesi` worktree'sine kopyalayıp
   koşturdum → **5 passed / 2 failed**, ve düşen 7 eksik önkoşulun adı kartın
   ilan ettiğinin aynısı: `rabadon-gate←testout.h`, `rabadon-gated←testout.h`,
   `rabadon-run←baseline.h`, `rabadon-run←gitcfg.h`, `rabadon-net←cmdtext.h`,
   `rabadon-net←pathres.h`, `rabadon-net←testout.h`. Süit gerçekten kırmızı düşüyor.
2. **SEMPTOM, iki ağaçta yan yana, aynı `touch native/pathres.h && make all`:**
   - `F3b-oncesi`: `rabadon-net` mtime **1788020777 → 1788020777 — DEĞİŞMEDİ** (bayat ikili).
   - `HEAD`: **1788020747 → 1788021132 — YENİDEN DERLENDİ.**
3. **MUTASYON, benim elimle:** HEAD'in `Makefile`'ından `native/rabadon-net`'in
   `pathres.h` önkoşulunu tek başına çıkardım → süit **7/0 → 5 passed / 2 failed**,
   ve düşen iki arm doğru adı söylüyor (`MISSING … net.cpp includes pathres.h`,
   `make answers 'up to date' … rabadon-net<-pathres.h`). Geri koydum → 7/0.
   **Kırılabilen kapı = kapı.** (Süidin kendi F armı da aynı şeyi içeriden yapıyor.)
4. **KAPSAM.** Süit bugün **20 derleme kuralı / 112 kaynak→başlık kenarı** tarıyor
   ve **111 (ikili, başlık) çiftini / 24 başlığı** ampirik olarak `make -q`'ya
   sorduruyor. `rabadon-truth`'un dar kuralı bir kusur DEĞİL: `truth.cpp` yalnız
   `cli_help.h` include ediyor (kaynaktan doğruladım).

**BAYAT-İKİLİ ŞÜPHESİ — SORULAN SORU, ÖLÇÜLDÜ.** D7 fazın **ilk iş commit'idir**:
`09ff870` (18:57:35) yalnız tahmin metnidir, ürün/test kodu içermez; ilk kod
commit'i `6ee07cf` (18:59:53, ölçüt) ve onarım `eff4541` (19:00:49). D7'den önce
bu fazın ürettiği **hiçbir yeşil iddia yoktur**, dolayısıyla bayat ikiliden gelmiş
olabilecek bir sayı da yoktur. Fazın bütün yeşilleri onarımdan SONRAKİ ağaçta
üretildi ve ben yukarıdaki 4513'ü zaten sıfırdan yeniden ürettim.

## 3. F3-S1 — İYİLEŞME GERÇEK, TAVAN TUTTURULMADI, VE KARTIN AÇIĞI EKSİK YAZILMIŞ

Kart üç sayıyı yan yana koyup uzlaştırmamış: süreç-içi `2b` 1218,7 · eşli A/B
HEAD medyanı 1330,5 · F3 hakeminin uçtan uca 1681,3. Üçü **üç ayrı alettir**:
`accept.sh`'in in-process probu (300 örnek MEDYAN), `2b-uctan-uca.sh` (N=200 MEAN,
süreç doğurma dahil, `/usr/bin/true` tabanı düşülmüş), ve aynı aletin farklı günkü
koşusu. Tek geçerli karşılaştırma **aynı gün, aynı makinede, eşli** olandır.

**KENDİ ÖLÇÜMÜM** (`reports/kosu/kanit/f3/2b-uctan-uca.sh`, N=200, gate exit
sağlamlık kontrolü her koşuda geçti, **8 eşli tekrar, sırayla BASE→HEAD**):

    rep1 BASE=2090.3 HEAD=1734.3   rep5 BASE=1914.1 HEAD=1619.0
    rep2 BASE=2024.5 HEAD=1686.9   rep6 BASE=1920.8 HEAD=1303.7
    rep3 BASE=1961.6 HEAD=1765.9   rep7 BASE=1612.0 HEAD=1046.1
    rep4 BASE=1986.1 HEAD=1657.0   rep8 BASE=1278.8 HEAD=990.1

- **BASE ortalama 1848,5 µs · HEAD ortalama 1475,4 µs · fark −373,1 µs, 8/10 değil 8/8 NEGATİF.**
- HEAD medyanı **1638,0 µs**, BASE medyanı 1941,2 µs.

**HÜKME BAĞLANAN TEK SAYI: bugünün atfedilebilir uçtan uca maliyeti
`1475,4 µs`, tavana kalan açık `475,4 µs` (1,48×).**

**NEGATİF SONUÇ, OLDUĞU GİBİ:** hedefe (1000 µs) **ULAŞILMADI**. Ve kartın
"kalan açık ~330 µs" cümlesi **bugün yeniden üretilmedi — açık daha büyük**.
Sebebi ödül hackleme değil ölçüm hijyeni: kart tek koşunun medyanını (1330,5)
tavana karşı koydu, oysa aletin tanımı MEAN'dir ve gürültü bandı çok geniş
(BASE bende 1278–2090 µs arası saçıyor). Onarımın kendisi sağlam — 8/8 negatif
eşli fark, ve süreç-içi `2b` de 1237,5 → 1220,0'a düştü. **İyileşme GERÇEK,
tavan AÇIK, ve açık kartın yazdığından ~145 µs BÜYÜK.**

`day_cache_test.sh`'in `COLD_FIRST_US` armı ölçüt-önce ayrı commit'te (`85a1fc9`,
582 µs KIRMIZI), onarım sonra (`3fda255`, 16 µs), ve `gmtime_r+strftime`'a karşı
64808 damgada 0 uyuşmazlık — bu zinciri commit sırasından doğruladım.

## 4. (b) ve (c) — ÜRÜN KAPSAMI ÜST ÜSTE İKİNCİ FAZDA %0

Kartın iddiasını kendi aletimle sınadım, ve **daha kötü çıktı**:

- `grep -rlh INJECT ~/.rabadon/spool/` → defterde **7 INJECT**. Yargılanabilir **0**.
- Halka dosyaları: `~/.rabadon/sessions/*.moves.bin`, header'dan `count` okudum →
  **39 halka, medyan `count` = 3, yalnız 2'si CAP=200'ü aşmış (%5,1)**.
  **AMA enjeksiyon taşıyan 2 halkanın 2'si de aşmış — %100.** Yani kayıp rastgele
  değil **seçici**: sinyal uzun oturumda doğar, uzun oturum halkayı yuvarlar,
  enjeksiyonun kanıtı tam da doğduğu yerde siliniyor.
- `grep -ln INJECT native/*_test.sh` → **0**. Enjeksiyonu uçtan uca süren tek süit
  yok; yani (b) fikstürde de ölçülmüyor, yalnız canlı defterden ölçülmeye çalışılıyor.
- `gate.cpp:5072` `INJECT` satırı `mseq` + `err` taşıyor ama **enjeksiyondan
  SONRAKİ hamle yalnız halkada yaşıyor**. Halka yuvarlanınca cevap yok olur.

**HÜKÜM: bugünkü halka tasarımıyla (b) canlı defterden ÖLÇÜLEMEZ.** Sentetik
kısa bir fikstür oturumunda ölçülebilir, ama öyle bir fikstür YOK. Yani (b)'yi
engelleyen şey ürün kodunun eksikliği değil **kanıt kalıcılığıdır** — ve bu
DURUM.md'de iki kez ilan edilmişti (F1c: 666 başlık / 527 diskte, 139 hamle
yedekten önce kayıp; F2: LOSS 1.417 / başlık 1.944, kayıp %72,9). Üçüncü kez
aynı duvara çarpıldı. **Sıradaki fazın İLK kartı ürün değil kanıt kalıcılığı
olmak zorundadır** (§3.7 yetkisi, gerekçe: yargılanabilir n = 0/7).

(c) negatif kontrolü **koşulmadı** ve ben de koşmadım (`ab_run.sh` ağ + `claude -p`
+ saatler ister; görev kümesi §3.8/2 ile mühürlü). `KOSU-RABADON-5.md` §F3:
**"Bu ölçüm yapılmadan F4 açılmaz."** Şart karşılanmadı → **F4 AÇILMAZ.**

## 5. §3.12 — TETİK BU FAZDA GERÇEKTEN YAZILIYDI

`git show 09ff870` → `2026-08-29 18:57:35`, tek dosya `reports/kosu/RAPOR/F3b.md`,
**yalnız tahmin metni**, içinde "Kart sayısı: 4. İki katı = 8" ve dört kalemin
üçüncü/dördüncüsü açıkça "ŞÜPHELİ" yazılı. İlk iş commit'i `6ee07cf` **18:59:53**,
yani tahmin **kartların kesilmesinden 2 dakika 18 saniye ÖNCE** commit'lendi.
Sonradan yazılmış bir tahmin değil. Kesilen kart **3 < 8** → tetik çalmadı, doğru.

## 6. §3.8 DENETİMİ — TEMİZ

- `git diff --diff-filter=D --name-only F3b-oncesi..HEAD` → **silinen dosya YOK**.
- `reports/R7/accept.sh` · `reports/R7/ON-KAYIT.md` · `docs/claims.tsv` · `.rabadon/`
  → diff'te **0 satır**. Eşik/tolerans/fikstür/ön-kayıt HİÇ oynatılmadı.
- Eklenen tek `skip` dizesi `make_deps_test.sh:233` — "ağaç derlenmemişse `make -q`
  armı atlanır, metinsel armlar yine koştu" dalı. `test: all` bağımlılığı yüzünden
  `make test` içinde bu dala **hiç girilmiyor** (bugünkü koşuda 7/0, E ve F armları
  koştu). Gevşetme değil; yine de **bir yumuşak nokta**: derlenmemiş ağaçta süit
  sessizce zayıflar. Kayda geçti, kart açmıyorum (§3.7 ile bir sonraki fazın
  kanıt kartına iliştirilebilir).
- **Ölçüt commit'leri koddan ÖNCE ve AYRI** (CLAUDE.md 2), iki kartın ikisinde de:
  D7 `6ee07cf` (yalnız `make_deps_test.sh` + `Makefile`'a tek `test:` satırı, ürün
  kuralı DEĞİŞMEMİŞ) → `eff4541` (onarım); F3-S1 `85a1fc9` (probe + test) →
  `3fda255` (`gate.cpp`). Diff'lerini satır satır okudum, karışma yok.

## 7. KAPI BENİ KESTİ — 1 KEZ, DOĞRU RED

`make test 2>&1 > .../maketest.out` denemem `baseline-truncating-redirect` ile
**BLOCKED** oldu (hedef proje ağacının dışında). §3.8/4 gereği **yaklaşımı
değiştirdim**: `| tee` ile yazdım. `guard.json`'a dokunmadım, `rabadon off`
kullanmadım, CHALLENGE-3 bileşik-komut deliğini kullanmadım, hiçbir blokajı aşmadım.
Ayrıca `F3b-oncesi` worktree'sinde boş-yeşil koşumu sırasında PostToolUse
"tests are RED" uyarısı aldım — o kırmızı **kastî ölçümün kendisidir** (faz öncesi
ağaç), çalışma ağacımın kırmızısı değil.

## 8. D5/3 TETİĞİ — ÇALDI

`SAPMA-KARARLARI.md:1760-1765`: *"fazın ürününden ÖNCE kapatılması gereken bir kod
kusuru … arka arkaya beşinci olursa bu bir faz sorunu değil bir koşu yapısı
sorunudur; cevapçının yetkisi biter ve soru `UYANDIGINDA.md`'ye O5 olarak düşer."*

Zincir, sayıyla: **1)** D1 (F2, yanlış RET) · **2)** D6 (F3, `truth.cpp` keşif
seçicisi) · **3)** CHALLENGE-2 (F3, `red-base` komşu ağaç) · **4)** D7 (F3b,
`Makefile` önkoşulları) · **5)** **F3b'nin kendi ölçümüyle: `moves.h` `CAP=200`
halkasının enjeksiyon kanıtını yok etmesi** — yargılanabilir n = **0/7**, ve bu
kusur kapanmadan (b) ne bu fazda ne sonrakinde ölçülebilir. **Beşincidir.**
Ve iki bağımsız sayı aynı şeyi söylüyor: **KOSU §F3'ün ürün kapsamından teslim
F3'te %0, F3b'de %0** (fazın diff'i `inject.h`/`signals.h`/`policy.h`'e hâlâ
HİÇ dokunmuyor). **O5 yazıldı.**

## NOT VERIFIED / ÖLÇEMEDİM

- **(c) negatif kontrolünü ÖLÇEMEDİM.** Koşmadım, koşamam (mühürlü görev kümesi + ağ).
- Konteyner / x86 koşumu **YOK**; her şey macOS 24.2.0, tek makine.
- `make test`'in exit kodunu doğrudan yakalayamadım (kapı `>` yönlendirmesini
  kesti, `| tee` kullandım); **dolaylı** doğruladım: çıktıda `make: ***` satırı
  yok ve hiçbir süit `N failed` (N>0) basmıyor. Bu bir zayıflıktır, yazıyorum.
- Uçtan uca sayı **makine gürültüsü altında** alındı (BASE 1278–2090 µs).
  8 tekrar eşli olduğu için FARK güvenilir; **mutlak sayı ±%20 bandındadır**
  ve bir sonraki faz onu tek koşudan alıntılamamalıdır.
- `make_deps_test.sh` yalnız macOS'ta ve yalnız GNU make ile koştu; BSD make /
  Linux make farkını sınamadım.
- Halka sayımını `~/.rabadon/sessions/*.moves.bin` header'ından okudum (39 dosya);
  silinmiş/süpürülmüş halkaları (`.swept`) sayamadım — gerçek kayıp bundan büyük olabilir.
- Kâtip commit'i yokluğunun muafiyetini F3 hakeminin emsaline dayandırdım;
  **bağımsız olarak "hiçbir kullanıcıya görünür cümle değişmedi" iddiasını
  `docs/` diff'inin boş olmasından çıkardım**, tek tek doğrulamadım.
