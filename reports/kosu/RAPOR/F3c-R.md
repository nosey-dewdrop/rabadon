# F3c — HAKEM TUTANAĞI (2026-08-29)

Taban `F3c-oncesi` = `94fa1ec`. Nihai ikili `64e1798`. Kartın hiçbir sayısı
kopyalanmadı; aşağıdaki her sayı benim iki worktree'imde (`~/damla_projects_2026/
_hakem_f3c_{head,base}`, ikisi de `--detach`, ikisi de **`/tmp` DIŞINDA**,
**ikisi de kaldırıldı**) yeniden üretildi. Kum havuzunu `/tmp`'de açmadım
(DURUM.md:578 muafiyet artefaktı). Kapı beni hiç kesmedi; `guard.json`'a
dokunmadım (mtime **29 Ağu 15:36**, fazın ilk commit'i 19:48 — dosya bu fazda da
hiç açılmadı), `rabadon off` kullanmadım, CHALLENGE-3 deliğini kullanmadım.

## 1. SAYAÇ — kartın üçlüsü BİREBİR tuttu

| bacak | kartta | **hakem** |
|---|---|---|
| `make test` EXIT | 0 | **0** (`make: ***` satırı 0, `N failed` satırı 0) |
| native GENİŞ `^\s*ok\b` | 3832 | **3832** |
| `PASS (N checks)` toplamı | 633 | **633** |
| `npm test` | 64/0 | **64 pass / 0 fail, EXIT=0** |
| **TOPLAM** | 4529 | **4529 yeşil / 0 kırmızı** |
| taban (`F3c-oncesi`, kendi worktree'imde koştum) | 4513 | **3816 + 633 + 64 = 4513** |

**Aritmetik kapanıyor ve süit süit doğrulandı.** Taban ve HEAD çıktılarının
özet satırlarını (`^ad: N passed, M failed`) sıralayıp `diff`'ledim: **71 → 72
süit, tek fark `inject-answer: 16 passed, 0 failed`**. Düşen süit yok, küçülen
süit yok, +16'nın tamamı yeni süit.

`bash reports/R7/accept.sh` → **EXIT=1, 23 yeşil / 3 kırmızı**, adlar
**`{2b, 6e, 7b}` — BÜYÜMEDİ** (§3.6). Süreç-içi `2b` bende **1249,2 µs**
(F3: 1237,5 · F3b: 1220,0 · kart: 1276,4 — hepsi aynı bantta).

F1e-C üçlüsü, fazın **NİHAİ ikilisine** karşı, tam derlenmiş ağaçta:
`docs_truth` **42/0**, `install_docs` **38/0**, `version` **13/0**, üçü de
EXIT=0. Kâtip commit'i `087e559` (`docs/agent-contract.md`) fazın **3.**
commit'i, sonuncusu (`64e1798`) değil — şart tutuldu, **iki fazlık boşluk
kapandı**.

## 2. KART 1 — KAPANDI. Kendi mutasyonlarım, kartınkiler değil.

Önce fazın kendi süiti benim elimde: `native/inject_answer_test.sh` → **16/0**,
ve kartın halka iddiası birebir çıktı: **başlık 218 hamle sayıyor, CAP 200,
enjeksiyonun bindiği `mseq=6` TAHLİYE EDİLMİŞ (en eski tutulan 18) — ve (b) o
hâlde hâlâ cevaplanıyor** (`5d8f862e04307ec4 → ba0290a38ead3d9b`, `same=false`).

**Boş yeşil turu (§8.2):** aynı süiti `F3c-oncesi` worktree'sine kopyalayıp o
ağacın kendi ikilisiyle koşturdum → **6 passed / KIRMIZI, EXIT=1**, 10 FAIL
satırı, hepsi `psig`/`INJECT_ANSWER` yokluğundan. Kartın 6/1'i doğru.

**ÜÇ MUTASYON, ÜÇÜ DE BENİM (kartınkileri kullanmadım):**

| # | mutasyon | sonuç |
|---|---|---|
| **M1** | serileştiriciden `injAnsAfterSeq` alanını düşür (relay süreçler arası taşınmasın) | **YEŞİL KALDI, 16/0 — TUTMADI** |
| **M2** | `psig`'i kuyruğa girerken değil **teslim anında** al (`ss.moves.back().sig`, yani taşıyıcı hamlenin imzası) | **KIRMIZI, 14/1** |
| **M3** | serileştiriciden `injPendingPrevSig`'i düşür (kuyruk→teslim relay'i süreçler arası kaybolsun) | **KIRMIZI, 11 passed / 5 FAIL satırı, EXIT=1** |

Sonra `git checkout -- native/gate.cpp` + yeniden derleme ile üçü de geri
alındı, süit **16/0**'a döndü.

**M1'İ AYRICA YAZIYORUM, ÇÜNKÜ SÜİTİN DELİĞİDİR.** `injAnsAfterSeq`
serileştirilmediğinde deserializer `get_num` üzerinden **0** okur ve "sıfırıncı
hamleden beri cevap borcu var" durumuna düşer; fikstürde cevaplayan hamle zaten
`seq=7 > 0` olduğu için süit bunu göremiyor. Kart da farklı bir mutasyonun
(`injAnsAfterSeq = -1` sıfırlaması) tutmadığını yazmıştı. **Aynı alanda iki
bağımsız delik**: süit `injAnsAfterSeq`'in ne kalıcılığını ne sıfırlanmasını
tek başına kilitliyor; yalnız ikisinin BİRDEN kaybını görüyor. Kapı kırmızı
olabiliyor (M2, M3) — yani §3.8/3 anlamında kapıdır — ama bu alanın kilidi
eksik. Sıradaki fazın kanıt kartına iliştirildi.

**CAP BÜYÜTÜLMEDİ, ERTELEME YOK.** `git diff F3c-oncesi..HEAD` içinde `CAP`/
`200` geçen **her** satırı okudum: hepsi yorum ya da yeni süidin iddiası;
`native/moves.h` diff'te **hiç yok**, `static const size_t CAP = 200;` (satır 63)
bayt bayt aynı.

**KORPUS/HALKA SİLİNMEDİ, SNAPSHOT'A DOKUNULMADI.** `~/.rabadon/sessions/
*.moves.bin` → **39 halka** (F3b hakeminin saydığıyla aynı). `~/.rabadon-korpus-
snapshot-20260826/` → izin **`dr-xr-xr-x`**, mtime **26 Ağu 06:48** — salt-okunur
ve dokunulmamış.

## 3. KART 2 — (b) FİKSTÜRDE n=1, CANLIDA n=0. HÜKÜM: (b) KARŞILANMADI.

Canlı defteri kendim saydım (`~/.rabadon/spool/*.jsonl`):

    INJECT toplam ....... 7
    INJECT, psig taşıyan  0
    INJECT_ANSWER ....... 0

Kartın sayısı **birebir doğru** ve kart bunu gizlemiyor. Yedi `INJECT`'in yedisi
de tek bir eski oturumdan (`db0ca780-…`, `signal:"root_migration"`) ve hepsi bu
fazdan eski, yani `psig` alanı doğmadan yazılmışlar.

`KOSU-RABADON-5.md` §F3'ün (b) maddesini kendi gözümle okudum (satır 142):

> **b) ajan okudu mu.** INJECT satırı yalnız rabadon'un yazdığını gösterir,
> ajanın kullandığını göstermez. Enjeksiyondan sonraki ilk hamlenin imzası,
> enjeksiyon öncesi tekrarlanan imzadan farklı olmalı. … **ve faz kapanmaz.**
> Ajanın metni okuduğunu iddia etmesi sayılmaz, **sonraki hamlenin imzası
> sayılır.**

Madde bir MEKANİZMA değil, bir **AJANIN** hamlesini istiyor. Fikstürdeki n=1'in
"ajanı" `inject_answer_test.sh`'in kendi ürettiği olaylardır — o imza bir ajanın
değil, testin imzasıdır. §F3 tam olarak bu ikamesi yasaklıyor ("ajanın … iddiası
sayılmaz, sonraki hamlenin imzası sayılır"). **Ölçülen sayı canlıda sıfırdır.**
Dolayısıyla: **fikstürde çalışan mekanizma (b)'yi KARŞILAMAZ.** Bu fazın gerçek
kazancı, (b)'nin ARTIK ÖLÇÜLEBİLİR olmasıdır — ölçülmüş olması değil.

**(c):** koşulmadı, kart da "ÖLÇEMEDİM" diyor, ben de koşamam (mühürlü görev
kümesi §3.8/2 + ağ + `claude -p`). §F3: *"Bu ölçüm yapılmadan F4 açılmaz."* →
**F4 KAPALI KALIR.**

**Merdivenin üçüncü basamağı (blok) yapılmadı** ve kartın gerekçesi
savunulabilir: `same=true` olgusu bu fazda doğdu, canlı yanlış-pozitif oranı
n=0, ve §F3'ün kendi kuralı "yeni sinyallerin varsayılanı enjeksiyon ve iz, blok
değil" (satır 137) + "yüzde beş üstündeki sinyal canlıya çıkmıyor" (satır 129).
n=0 bir olguya dayanıp exit kodu değiştirmek ürünün reddettiği compound error
olurdu. **Basamağın yapılmaması SAPMA DEĞİL; ama §F3 hâlâ teslim edilmedi.**

**(b) KANAL YENİDEN TASARIMI SAATİ HENÜZ GELMEDİ.** §F3 satır 136: *"(b) katmanı
iki koşuda üst üste **KIRMIZI** düşerse metnin biçimi ve kanalı yeniden
tasarlanır."* F3/F3b/F3c'de (b) **kırmızı düşmedi, ÖLÇÜLEMEDİ** — halka kanıtı
yok ediyordu. Ölçülemeyen kırmızı değildir. Sayaç bugün **0**'dır; F3d, (b)'nin
ölçülebildiği **birinci** koşudur.

## 4. KART 3 — `2b`: bu fazın katkısı GÜRÜLTÜ. Bugünün tek sayısı: 1378,9 µs.

Aleti kendim koşturdum: `reports/kosu/kanit/f3/2b-uctan-uca.sh`, eşli
(HEAD ikilisi ↔ `F3c-oncesi` ikilisi, ikisi de aynı derleyici satırıyla taze
derlendi, md5'leri farklı). Gate exit sağlamlık kontrolü (`sanity: … ALLOWED ->
gate exit 0`) **14 koşunun 14'ünde** geçti.

**N=200, 8 eşli tekrar — çözünürlük yetmiyor:** HEAD ort. **1657,9** · taban ort.
**1724,7** · fark **−66,8 µs**, işaretler **4 artı / 4 eksi**, tek eşli fark
**−1705,1 … +839,0 µs** saçıyor.

**N=500, 6 eşli tekrar — sıkı ve karar veren koşu:**

    HEAD  1453,3  1396,7  1309,5  1256,1  1535,1  1322,6  -> ort. 1378,9 us
    TABAN 1461,7  1325,9  1305,3  1443,1  1379,2  1496,0  -> ort. 1401,9 us
    fark  -8,4  +70,8  +4,2  -187,0  +155,9  -173,4      -> ort. -23,0 us, 3 arti / 3 eksi

**HÜKÜM — tek sayı: `2b` uçtan uca atfedilebilir maliyet bugün 1378,9 µs;
tavan 1000,0 µs; KALAN AÇIK 378,9 µs (1,38×).**

**Fark GÜRÜLTÜDÜR ve seri sahte olabilir.** Aynı `F3c-oncesi` ikilisi F3b
hakeminde **1475,4**, kartta iki ölçümde **1304,6 / 1374,2**, bende **1401,9**
çıktı — ikili değişmeden alet günler ve koşular arasında ~170 µs geziyor.
Yani **1681,3 → 1475,4 → 1424,1 → 1378,9 serisinin son iki adımı ölçüm gürültüsü
bandının içindedir**; "üç fazdır düşüyor" cümlesi kurulamaz. Gerçek olan tek
adım F3b'nin `1641,2 → 1287,1` eşli kazancıdır (algoritma değişti: timezone
yükü kalktı). **Kart bunu kendisi yazmış** ("bu faz `2b`'yi ölçülebilir biçimde
hızlandırmadı") — dürüstlük kaydedildi, CLAUDE.md 8'e uygun.

**Tavan oynatılmadı:** `reports/R7/accept.sh` diff'i **0 satır**; `1000` sabiti
satır 122 (yorum) ve 203 (`float(MED)<1000.0`) yerinde; dosyaya en son dokunan
commit `9cba3cd` (F2, KARARLAR'da onaylı).

## 5. KART 4 — KAPANDI, AMA SINIF KAPANMADI. Yeni bulgu: `version_test.sh`.

`make_deps_test.sh:233`'ün `skip`'i gerçekten `bad`'e döndü, gerekçe yorumda
sayıyla yazılı, `make test` sayacı değişmedi (`test: all` dalı hiç girmiyor).
Kart doğru.

**AMA SINIFIN GERİ KALANI DURUYOR, VE BİRİ F1e-C KAPI ÜÇLÜSÜNÜN İÇİNDE.**
`grep -c 'echo "  skip' native/*_test.sh` → **8 dosyada 9 satır** hâlâ duruyor
(`blind_switch`, `discovery_scope`, `guard_lint`×2, `redbase_scope`,
`sandbox`, `script_wrapper`, `unknown_wrapper`, **`version`**).

Ve `version_test.sh` teorik değil, **bugün benim elimde ateşledi**:

    make all ; bash native/version_test.sh   -> version: 13 passed, 0 failed
    touch native/gate.cpp                    (tek kaynak dosyaya dokun)
    bash native/version_test.sh              -> version: 11 passed, 0 failed, EXIT=0

**Bir kaynak dosyaya dokunmak, F1e-C kapı üçlüsünün bir bacağını sessizce
13'ten 11 iddiaya küçültüyor ve EXIT hâlâ 0.** Bu, kart 4'ün kendi yorumunda
tarif ettiği kusurun ta kendisidir ("a green that came from a check that did not
happen"), ve kapı şartının kendi aletinde yaşıyor. **Kart 4 bir örneği kapattı,
sınıfı kapattı diye ilan etmedi — ama sınıf açık.** Sıradaki fazın kartı.

## 6. §3.12 — tetik ÇALMADI, ve tahmin gerçekten ÖNCE commit'lendi

`git log` zaman damgalarıyla: tahmin `59a32e6` **19:48**, ilk kart commit'i
`d9a4907` **19:50**. **Tahmin kart kesilmeden önce commit'lenmiştir** — sonradan
yazılmış bir tahmin değil. 4 kart kesildi, tetik 8'de, **çalmadı**.

*(Sorulmadı, ölçtüm: fazın tamamı 19:48 → 20:18 = **30 dakika**, tahmin
**~5,2 saat**. §3.12 yalnız AŞMAYI kapı sayıyor, bu ihlal değil. Ama tahminin
kalibrasyonu 10× kaymış durumda ve §3.12 tetiği bu haliyle pratikte hiç
çalmayacak bir eşiktir — kayda geçiyorum, kural değiştirmiyorum.)*

## 7. §3.8 DENETİMİ — dört kilit de tuttu

- **Silinen dosya:** `git diff --diff-filter=D --name-only F3c-oncesi..HEAD` → **0**.
- **Mühürlü dörtlü:** `reports/R7/accept.sh` · `reports/R7/ON-KAYIT.md` ·
  `docs/claims.tsv` · `.rabadon/` → `git diff --stat` **boş, 0 satır**.
- **Silinen/atlanan iddia:** `native/` diff'indeki tek `-` satırı
  `make_deps_test.sh`'in **`skip`** satırıdır ve yerine **`bad`** geldi —
  gevşetme değil, sertleştirme. `xfail`/yoruma alınmış iddia **yok**.
- **Ölçüt önce, ayrı commit (CLAUDE.md 2):** `d9a4907` (ölçüt + `1-olcut-once-
  KIRMIZI.out`, 7/13 kırmızı) → `087e559` (kod). Ölçüt commit'i `Makefile`'a da
  16 satır eklemiş (yeni süidi `test:` hedefine bağlamak); bu koşum tesisatıdır,
  **ölçütü karşılayan kod değildir** — ihlal saymıyorum, ama kayda geçiyorum.
- **Kâtip (docs):** kullanıcıya görünen davranış değişti (defterde yeni
  `INJECT_ANSWER` olayı + `INJECT`'te yeni `psig` alanı) ve
  `docs/agent-contract.md` **aynı fazda, kodla aynı commit'te** güncellendi,
  örnek JSON zarfıyla. `docs/COUNTER.md` bir olay kataloğu değil, güncelleme
  gerekmiyor. **Şart iki fazdır düştüğü boşluktan çıktı.**

## 8. ÖLÇEMEDİM / NOT VERIFIED (hakemin kendi listesi)

- **(c) negatif kontrolü** — ben de koşamadım (mühürlü görev kümesi + ağ).
- **Canlı (b)** — ölçtüm, **n=0**; "mekanizma canlıda çalışıyor" iddiası
  **DOĞRULANMADI**, yalnız "canlıda henüz denenmedi" doğrulandı.
- Her şey **macOS 24.2.0 / arm64 / tek makine**. Konteyner ya da x86 koşumu
  **YOK**; yeni süit yalnız burada koştu.
- `2b`'nin mutlak sayısı makine yüküne duyarlı: benim N=200 turlarım kartın
  N=200 turlarından ~%16 yüksek çıktı (aynı ikili). Tek koşudan alıntılanamaz.
- Kartın "kapı beni hiç kesmedi" cümlesini **doğrulayamadım** (geriye dönük iz
  yok); benim oturumumda kapı kesmedi.
- Kartıma ait olmayan iki artık dizin duruyor ve **dokunmadım**:
  `~/damla_projects_2026/_f3b_prof`, `hakem-sbx-a`.
- `~/.rabadon/spool` dosyaları UTF-8 değil (bir satırda geçersiz bayt); saymayı
  `grep` ile yaptım, JSON ayrıştırmasıyla değil. Sayı (7/0/0) `grep` sayısıdır.
