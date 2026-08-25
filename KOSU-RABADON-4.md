# rabadon — koşu belgesi 4 (v4.0: sürücü yok, ayrı context'li fazlar, daimi tarafsız cevapçı, bekletmeyen kuyruk)

Bu dosya repo köküne `KOSU-RABADON-4.md` olarak konur ve **kalan koşunun tek
kaynağıdır**. `KOSU-RABADON.md` tur/ürün tanımları (R7, R8, M0–M4, Yasa 1–8)
için geçerli kalır. `KOSU-RABADON-2.md` ve `KOSU-RABADON-3.md`'nin **§B'leri
(orkestrasyon) BU BELGEYLE DEĞİŞTİRİLİR**; §A'ları bayattır. `CLAUDE.md`'nin
sekiz tartışılmazı ve `AGENTS-PROTOCOL.md`'nin devir kuralı + üç kapısı aynen
geçerlidir ve v4 onlara tabidir. Çelişkide sıra: kanıt > CLAUDE.md > bu belge >
eski koşu belgeleri.

Bu bir koşu protokolüdür, oturum brief'i değildir. Tek context'te baştan sona
okunmaz: her rol yalnız kendine düşen bölümleri okur (§3.2'deki manifesto).
Koşu kendi sıfırını kendisi koyar: eski "kapandı" cümleleri, eski raporlar ve
§1'in tamamı geçersizdir; her sayı F0'da yeniden ölçülür.

---

## 0. NEDEN 4 — koşu 3 çökmedi, DÖNMEDİ; koşu 2 ölmedi, BEKLEDİ

Üç ölçülmüş kök var. Üçü de mekanizmanın kendisinde, işin içinde değil.

**Kök 1 — v3 kuruldu, hiç dönmedi.** `kosu3` dalında iki commit var: `a994fba`
(v3 sürücüsü, `scripts/isci.sh`, `DURUM.md`, ön kontrol) ve `cfe5f25` (işçi
loglarının gitignore notu). `reports/kosu/` altında 23'üncü tur dosyası,
`DEVIR.md`, yeni `.karar` yok. Koşu 2'nin kendi hükmü bu duruma zaten ad
koymuştu: **"Kurulu ama dönmemiş döngü yok hükmündedir."** v3, kendi ölçütüyle
koşmamıştır ve bu belgede kanıt olarak sayılmaz.

**Kök 2 — döngünün canlılığı operatörün terminaline bağlıydı.** Koşu arka
planda, `tmux new -d -s rabadon scripts/kos.sh` ile, görünmeden yürüyordu.
Operatör oturduğu yerden kalktığında/projeyi kapattığında koşunun yaşayıp
yaşamadığı ancak `git log` ile anlaşılabiliyordu. Sessiz ölüm yasağı vardı
(v2 §B0) ama sessiz ölmemek görünür olmak demek değil.

**Kök 3 — ve asıl olan: durak sonsuzdur.** `kos.sh`'ın operatör durağı şudur:

    while ! grep -q '^ONAY[[:space:]]*$' reports/kosu/OPERATOR.md; do sleep 300; done

22 turun onunda (`GUNLUK.tsv`: 4·6·7·8·12·14·18·19·21·22) döngü buraya girdi.
Son giriş `6f5d301`'dir ve **çıkışı yoktur**: `reports/kosu/OPERATOR.md` bugün
cevapsız iki soruyla duruyor. Yani sistem sessizce ölmedi — **süresiz bekledi**,
ki iş açısından farkı yoktur. Üstelik bu durakların çoğu meşru bile değildi:
`docs/DEGERLENDIREN.md:16` "operatöre teknik soru GİTMEZ" der; 2b'nin
latans tavanı, `MIN_HISTORY` fixture'ı ve harness seçimi B4'ün beş
kategorisinin hiçbirine girmez. İhlal koşu 2'nin kendi DENEMELER kaydında
tur 3'te teşhis edildi, sonra tur 18·19·21·22'de tekrarlandı.

**v4'ün üç siparişi, bu üç kökün karşılığı:**

- **Koşucu script YOK.** Koşu Claude Code'da interaktif yürür. Operatörün
  mekanik işi ikiye iner: faz başında `/clear` + §8.2 bloğunu yapıştırmak,
  sonunda F11 raporunu okumak.
- **Fazların hiçbiri aynı context'te koşmaz.** Her faz taze bir şefle açılır,
  işini yapar, ÖLÜR. Devir dosyayladır (AGENTS-PROTOCOL). Koşu 3'ün ölçtüğü
  context yasaları (transkript değil DEVİR, işçi=süreç, `head -12` hükümdür)
  rol manifestolarına dönüşerek KORUNUR.
- **Koşu operatörü BEKLEMEZ.** Karar gerektiren her şey `OPERATOR-KUYRUK.md`'ye
  **VARSAYILANIYLA** düşer (§3.11); cevap gelmezse varsayılan yürür, cevap
  sonra gelirse bir sonraki fazın kartı olur. Varsayılansız tek sınıf geri
  dönüşsüz dış adımlardır (npm publish, PR, Show HN, fiyat) — onlar da koşuyu
  bloke etmez, PARK edilir ve koşu sıradaki faza geçer.

**Korunanlar (bunlar iyi çalıştı, dokunulmaz):** `scripts/isci.sh` (işçi ayrı
süreçtir, alt-ajan değil — koşu 3'ün ölçtüğü kazanç), DENEMELER hipotez-eleme
hafızası, tek yazar ilkesi, worktree dokunulmazlığı, `timeout` sarmalı, ONAY
mührü (cevap geldiğinde geçerli sayılması için hâlâ mühür gerekir),
`pusla()` disiplini, Yasa 7.

**Kasıtlı sapma (kayıt için).** Örnek aldığımız protokol işçileri alt-ajan
(Task) olarak salar. Bu repoda alt-ajan yolu **ölçülerek reddedildi**: alt-ajan
boşluğa değil ebeveynine ölür, raporu ebeveynin context'ine yazılır. Bu yüzden
v4'te işçi = `scripts/isci.sh` ile açılan **ayrı süreç**tir. Şef bir işçiyi
Task olarak salarsa bu kart ihlalidir ve hakem tutanağa yazar.

---

## 1. ZEMİN — 25 Ağu fotoğrafı: HİPOTEZ, KANIT DEĞİL

Bu bölümün tek işlevi F0 şefinin kartları isabetli kesmesidir. STATÜSÜ:
buradaki hiçbir sayı hiçbir kapıda kullanılamaz, hiçbir rapora atıf olarak
yazılamaz. F0 yeniden ölçmeden §1'in hiçbir satırı var sayılmaz; F0'ın ölçümü
§1 ile çelişirse §1 sessizce ölür, tartışma açılmaz.

1.1 **Dallar.** `main` = `30d5cbb`. `kosu2` = `6f5d301` (tur 22, OPERATÖR
    durağı). `kosu3` = `cfe5f25` (v3 kurulumu, tur yok). R7'nin **bütün işi**
    kosu2/kosu3'te durur, `main`'e hiç taşınmadı — squash-merge borcu açık.
    R8'in "yeşil main'den yayın" şartı bu yüzden bugün iki ayrı sebeple
    sağlanamaz durumda: disclosure kapısı ve taşınmamış tur işi.
1.2 **R7 = 23 yeşil / 3 kırmızı + 1 gizli kırmızı, NOT ACCEPTED**
    (`reports/kosu/DURUM.md`, `reports/R7/accept.tur22.out`). Kanıt kolu indi:
    `reports/R7/ab_run.jsonl`, 8 kayıt, A:4 / B:4 görev. GOAL 5 ve GOAL 8 tam
    yeşil (moves 21/0, signals 39/0, R2 19/0).
1.3 **2b latans — kırmızı, etiketi "bu makinede".** Tavan 1000 µs, 8 gözlem,
    min 1218,3 µs (`reports/R7/olc_2b.tur22.out`). Tek geçerli çıkarım
    `temiz ≤ 1218,3 µs`; bu 1000'i DIŞLAMAZ. Her gözlem üst sınır olduğu için
    bu worktree'de kırmızı **prensip olarak** kanıtlanamaz. Sekiz gözlemin
    tamamı 2 canlı `ctest` varken alındı; kirliliğin büyüklüğü ölçülmedi.
1.4 **6e / 7b — tek kök:** `MIN_HISTORY=3` yüzünden tek oturumluk koşuda
    `estimated_saved` üretilmiyor, sayaç doğrulanamıyor, yanlışlama-2
    hesaplanamıyor. `MIN_HISTORY` **ürün kodunda oynanmaz** (operatör
    bağlaması, deneme 26).
1.5 **5b — ön-kayıt sapması, accept.sh göremiyor.** `reports/R7/ON-KAYIT.md`
    koşudan önce donmuş: N = 6 görev × 2 kol. JSONL'de duran: 4 × 2. Eksik
    ikisi `joke2k__faker.8b401a7d` ve `pylint-dev__astroid.b114f6b5`.
    `accept.sh`'ın 5b'si kol başına sabit `>=2` arıyor — hedefi değil gevşemiş
    vekilini denetliyor. Bu, 2b'nin kirli ölçümüyle **aynı hata sınıfıdır**.
1.6 **İki kolun sonucu (n=4):** düzeltme oranı A %75 / B %75 — ÖZDEŞ; token
    A 35620 / B 33221 (%6,7); insan müdahalesi 0/0; yanlış pozitif 0/0.
    Yasa 7 ve ön-kayıtın kendi cümlesi gereği **gürültü içinde kalan fark
    "kurtarır" diye yayınlanmaz.** M3 yazısının ve fiyat hipotezinin zemini
    budur.
1.7 **R8 — bloklu.** `package.json` 0.2.3 · `npm view rabadon version` 404 ·
    tag yok. `make disclosure` tasarım gereği kırmızı: 53 isim, 12'si listede,
    41'i liste dışı (`reports/R8/DISCLOSURE.md`, ölçüm `ca1ea4e`); kural tam
    eşleşme + fail-closed. Karar gerektirmeyen açık işler: 17/18 binary
    uyuşmazlığı (rabadon-run her platform paketine), tag, plugin paketi
    (`.claude-plugin/plugin.json` + `hooks/hooks.json`, canonical dizin
    `anthropics/claude-plugins-official`), 10k `additionalContext` kesme testi,
    `RABADON_TIER=free` bayrağı.
1.8 **2c izlemede (kırmızı değil):** %3,35 → %6,50. Tavan %10 ama R1.3'ün
    %3,5–4,9 bandı aşıldı ve daemon paydası küçülttükçe oran büyür.
1.9 **Vitrin.** README'de duran iddialar: "not yet published to npm",
    `rabadon ui` stub, "unplanned breakage üzerinde tutulan onarım = 0".
    docs/POSITIONING.md'de "üretimde kimse yok" cümlesi **ölüdür** (Watcher /
    Apollo Research ve Mindlas sınıfı araçlar var; ayrışma boşlukta değil
    YÖNTEMDE: yerel binary, hot-path'te sıfır model, sıfır ağ, fail-same).
1.10 **M0–M4 hiç başlamadı.** POSITIONING M3'e, `docs/SAVUNMA.md` + landing
    M4'e bağlı. Fiyat açık (KOSU-RABADON.md M4: fiyat yazılmadan da koşulur).

---

## 2. SİPARİŞ HARİTASI — operatörün maddeleri, hangi faz kapatıyor

Bunlar yorum değil sipariştir. F11'de tek tek işaretlenir: ya kapandı (kanıt
yolu ile) ya açık (sebep + kuyruk satırı ile).

2.1 R7 kabulü yeşile döner ya da **dürüstçe** kapanır (kırmızı kalanın adı ve
    sebebi yazılı) → F1–F4.
2.2 Kabul betiği hedefi denetler, gevşemiş vekilini değil (5b dersi) → F1.
2.3 Kirli ölçümün üstüne etiket yapıştırılmaz; temiz referans ortam ya kurulur
    ya ölçüm PARK edilir → F2.
2.4 Sayaç yalnız ledger'dan doğrulanır; `MIN_HISTORY` ürün kodunda oynanmaz
    → F3.
2.5 Yayın kapısının anlamı kararlaştırılır ve **gevşetilerek** değil
    kapatılarak geçilir → F6.
2.6 npm + plugin paketi ilk kez gerçekten çıkar; kurulum iki cümleye iner
    → F5, F7.
2.7 Pazar cümlesi tazelenir: "kimse yok" silinir, yöntem ayrışması yazılır
    → F8.
2.8 Ölçülmemiş şey satılmaz; her kamuya giden sayı ledger'dan türetilir
    (Yasa 7) → F9, F10 kapıları.
2.9 Savunulabilir hikâye: `docs/SAVUNMA.md` — problem, mimari kararların
    NEDENleri, ölçülmüş sayılar ve bu orkestrasyonun kendisi → F10.
2.10 Fazlar arası kontrol, context sağlığı ve **operatöre kendi işi hakkında
    kendi cevabını vermemek** → §3, baştan sona.

---

## 3. ORKESTRASYON — v4'ün kalbi

### 3.1 Yürütme modeli

`scripts/kos.sh` **emekli edilir** ve geri gelmez (§0, Kök 2–3). Silinmez:
`scripts/arsiv/kos.sh` altına, başına tek satır iptal notuyla iner — koşu 2'nin
22 turu onunla döndü, delildir. `scripts/isci.sh` KALIR ve v4'ün işçi yoludur.
`docs/DEGERLENDIREN.md` emekli edilir; yerine §3.5 (hakem) ve §8.3 (tarafsız
cevapçı) geçer.

Koşu Claude Code'da interaktif yürür. Operatörün koşudaki mekanik işi:

a) Her faz başında `/clear` yapıp §8.2'deki faz açılış bloğunu yapıştırmak.
b) Kapanışta F11 raporunu okumak.
c) Canı isterse `reports/kosu/OPERATOR-KUYRUK.md`'ye `CEVAP:` satırları + en
   sona tek başına `ONAY` yazmak. **Bu koşuyu bloke etmez** (§3.11).

Bunun dışında koşu onu beklemez.

### 3.2 Oturum türleri ve context manifestoları

Beş rol vardır; hiçbiri diğerinin oturumunda yaşamaz. Her rolün context'i
aşağıdaki manifestoyla sınırlıdır — manifesto dışı dosya açmak kart ihlalidir
ve hakem bunu tutanağa yazar.

**ŞEF** (faz başına 1, sonra ölür)
  Okur: `CLAUDE.md` + `AGENTS-PROTOCOL.md` + bu belgenin §3, §4, §7 + kendi
  fazının §6'daki tanımı + `reports/kosu/DURUM.md` + `OPERATOR-KUYRUK.md`.
  Okumaz: diğer fazların tanımları, `KOSU-RABADON.md`'nin tamamı, eski koşu
  belgeleri, `reports/kosu/*.out`, işçi ham logları. Yazar: `reports/KART/`,
  `reports/F<n>/TUTANAK.md`, `DURUM.md`, `KAPI.md`, `OPERATOR-KUYRUK.md`.
  **Yazamaz: kaynak kod.** Şefin "küçük bir düzeltme" yapması dahi yasaktır.

**İŞÇİ** (faz başına 2–6, `scripts/isci.sh` ile ayrı süreç)
  Okur: `CLAUDE.md` + kendi kartı (≤80 satır) + kartın İSİM İSİM saydığı
  dosyalar. Okumaz: `DURUM.md`, bu belgenin tamamı, başka kartlar, başka
  işçilerin logları. Yazar: yalnız kartın ÇIKTI satırındaki yollar. Kart dışı
  dosyaya dokunmak = iş reddedilir, yan dala alınır.

**HAKEM** (kapı çağrısı başına 1, temiz oturum)
  Okur: fazın çıktı dosyaları + fazın dokunduğu kabul betiği + iki kabul logu
  (faz öncesi / sonrası) + `CLAUDE.md` + bu belgenin §4. **Okumaz: kartlar,
  şefin tutanağı, fazın niyeti** — hakem ne HEDEFLENDİĞİNİ değil ne OLDUĞUNU
  okur. Yazar: `reports/kosu/KAPI.md`'ye tek hüküm satırı.

**KÂTİP** (faz kapanışı başına 1)
  Okur: fazın tutanağı + fazın `git diff`i + `docs/` ağacı + `README.md` +
  `site/`. Yazar: SADECE `docs/`, `README.md`, `site/`, `reports/INDEX.md`.
  Koda, `native/`'e, `core/`'a, kabul betiklerine dokunmaz. **Kâtibin commit'i
  olmayan faz kapanmamıştır.**

**TARAFSIZ CEVAPÇI** (çağrı başına 1, temiz oturum) → §3.7.

### 3.3 Şefin yaşam döngüsü — adım adım, atlama yok

1) Aç: `/clear` sonrası §8.2 bloğu yapıştırılmış taze oturum. Manifesto
   dosyalarını oku, başka hiçbir şey açma.
2) `DURUM.md`'den devir üç sayıyı al: **açık kırmızı ADLARI · son yeşil
   commit · bekleyen kuyruk satırları.**
3) `OPERATOR-KUYRUK.md`'yi oku: bu fazı etkileyen satırlarda cevap var mı;
   yoksa VARSAYILAN yürür ve tutanağa "varsayılanla koşuldu" yazılır.
4) Fazın kartlarını kes: kart başına tek iş, ≤80 satır, §3.8.a şablonu. Her
   kart setini SIRALI mı PARALEL mi diye etiketle (§3.9).
5) İşçileri `scripts/isci.sh` ile sal. Her işçiye SADECE manifesto context'ini
   ver; fazın "niye"sini anlatma — kartta NE yazar, niyet yazmaz.
6) ORAKÇI: 60 dakikada bitmeyen işçiyi kes (`ISCI_TIMEOUT`); o ana kadarki işi
   commit'let, kalanı yeni kart olarak kuyruğa yaz. Kesilen işçi **kırmızı
   değildir** (§3.10) ve hipotezi elenmiş saymaz.
7) Dönen `reports/kosu/RAPOR/<ad>.md` dosyalarını doğrula: her sayının yanında
   onu basan komut, her adımın yanında dosya yolu var mı. Yoksa iade et;
   **kendin tamamlama.**
8) Kapının alt kapılarını sırayla koştur (§4). Hakemi ve kâtibi AYRI temiz
   oturumlar olarak aç; sonuçlarını bekle, yorumlama.
9) Tutanağı `reports/F<n>/TUTANAK.md`'ye yaz (uzun, serbest, üç bölüm zorunlu);
   `DURUM.md`'yi §3.8.c şablonuyla güncelle (≤50 satır **sert tavan** — satır
   eklemek için satır sil; kâtip `wc -l` ile denetler).
10) Devir üç sayıyı yaz, commit + push et, **ÖL.** Sonraki fazın şefi sen
    değilsin; hiçbir şef iki faz yaşamaz.

### 3.4 İşçi sözleşmesi

- Tek iş, tek süreç, tek kart. Kart bittiğinde işçi biter.
- Çağrı: `scripts/isci.sh <ad> <komut...>`. Ham çıktı `reports/kosu/log/`'a,
  rapor `reports/kosu/RAPOR/<ad>.md`'ye gider ve **süreç kırpar** (`head -12`).
  "12 satırı aşma" niyet beyanıdır, `head -12` hükümdür.
- Aynı fazda aynı dosyaya TEK işçi yazar. Şef kart keserken dosya çakışmasını
  kontrol eder; çakışan kartlar sıralıya döner.
- Rapor formatı: yapılan (dosya yolu + commit hash) · ölçülen (sayı + onu basan
  komut) · yapılamayan (sebep) · kart dışı fark edilen (dokunma, yaz).
- "Baktım / doğru görünüyor / çalışıyor" raporda yasak (CLAUDE.md 4): ölçüm
  varsa komut çıktısı, dosya varsa yol.
- Alt-ajan (Task) salmak yasak (§0, kasıtlı sapma).
- Araştırma işçisi (her fazın R-kartı, §5) kod yazmaz; çıktısı kaynak + tarih +
  hüküm tablosudur.

### 3.5 Hakem protokolü

Girdi paketi (şef hazırlar, **brief KOYMAZ**): fazın çıktı dosya listesi +
dokunduğu kabul betiğinin kaynağı + iki kabul logu (faz öncesi/sonrası) +
`CLAUDE.md`. Hakemin soru seti, sırayla:

1) Bu çıktı, geçtiğini iddia ettiği şeyi gerçekten yapıyor mu, yoksa kabul
   betiğini geçmek için mi şekillendirilmiş?
2) Fazın eklediği/değiştirdiği denetim faz-öncesi artefakt üstünde KIRMIZI
   düşüyor mu (boş yeşil kontrolü, §4.2)? `accept.sh` başlığının kendi
   cümlesi ölçüttür: *no assertion may pass vacuously.*
3) Kırmızı **AD** kümesi büyüdü mü (sayı değil, ad)?
4) Eşik, tolerans, ön-kayıt ya da fixture değişti mi? Değiştiyse §4.6 prosedürü
   işlemiş mi — eski değer, yeni değer, ölçülmüş gerekçe commit mesajında mı?
5) Ölçüm **sevk edilen yoldan** mı alındı: süreç-İÇİ mi, ve `hooks/gate.mjs`
   yerine gerçek native binary mi? (Tur 16'nın dersi: bağlama yanlış binary'ye
   yapılınca sayılar "ölçüldü" görünüp hiçbir şey ölçmüyordu.)

Çıktı: `reports/kosu/KAPI.md`'ye tek satır — GEÇTİ/KALDI + tek cümle gerekçe +
baktığı dosyaların listesi. **Hakem KALDI derse faz kapanmaz; pazarlık yoktur.**

### 3.6 Kâtip protokolü

Her faz kapanışında artımlı çalışır (kapının 7. alt kapısı), F9'da tam tarama
yapar. Anayasası **Yasa 7**: `README`, `docs/`, `site/` ve landing'de
ledger'dan ya da bir testten türetilmeyen sayı bulunmaz. Duran-iddia yazılmaz
("ALL PASS", "zero issues", "bitti", tarihsiz "ölçüldü") — sayıyı basan
testin/aletin ADI ve ölçüm TARİHİ yazılır. Bayat cümle ya güncellenir ya
gerekçesiyle `docs/archive/`'a taşınır; sessiz silme yok. Rakip sayısı yalnız
rakibin kendi yayınından alınır ve `docs/POSITIONING.md`'de doğrulanmış
işaretli değilse dışarı yazılmaz.

### 3.7 TARAFSIZ CEVAPÇI — daimi kural, istisnasız

Tetikleyiciler (dördü de zorunlu yönlendirmedir):

a) Operatör koşu sırasında HERHANGİ bir şey sorarsa ("neredeyiz", "bu sayı
   doğru mu", "faz gerçekten kapandı mı", "şu neden kırmızı"). Soruyu alan
   oturum — şef, işçi, kim olursa — CEVAP VERMEZ; §8.3 bloğuyla taze cevapçı
   açar ve onun cevabını **değiştirmeden** iletir.
b) Faz geçiş hükmü: "faz kapandı, sonraki açılabilir" cümlesini yalnız kapının
   hakem alt kapısı kurar ve bu HER fazda tekrarlanır.
c) "Ajan öldü mü, faz mı kırmızı" teşhisi (§3.10).
d) Sayı ihtilafı: iki oturum aynı büyüklük için farklı sayı basarsa hangisinin
   geçerli olduğunu cevapçı, **iki komutu da yeniden koşturarak** söyler.

Cevapçının girdi paketi: soru metni + ilgili kanıt dosyalarının YOLLARI +
`CLAUDE.md`. Girdi paketine GİRMEYENLER: fazın kartları, şefin tutanağındaki
niyet cümleleri, "ne yapılmaya çalışıyordu" anlatısı, bu belgenin §6'sı.

Çıktı: cevap ≤10 satır + dayandığı her cümle için dosya yolu ya da yeniden
koşturduğu komutun çıktısı. Yol gösteremediği cümleyi kuramaz; **"bu
ölçülmemiş" geçerli ve makbul bir cevaptır.**

Yorulmazlık: bu kural 1. fazda ne kadar geçerliyse 11. fazda da o kadar
geçerlidir. "Artık güven oluştu, direkt cevaplayayım" diye bir yol yoktur.

### 3.8 Teslim formatları — serbest metin yok, şablon var

a) **KART** (`reports/KART/F<n>-<ad>.md`, ≤80 satır):
   NE (tek cümle) · GİRDİ DOSYALARI (isim isim) · ÇIKTI (dosya yolu + hangi
   kapıya kanıt olduğu) · YASAKLAR (o karta özel) · SÜRE TAVANI (dk) ·
   SIRALI/PARALEL etiketi.

b) **TUTANAK** (`reports/F<n>/TUTANAK.md`): serbest uzunlukta, üç bölüm zorunlu —
   ÖLÇÜLEN (sayı + komut + hash) · KAPANAN/AÇILAN KIRMIZI (ad ad) · SONRAKİ
   FAZA DEVİR (üç sayı). Ayrıca: kuyruktan hangi satır varsayılanla yürüdü.

c) **DURUM.md** (≤50 satır, sert tavan): ŞU AN (faz + tek cümle + son yeşil
   commit) · KAPANMIŞ FAZLAR (faz başına tek satır + tutanak yolu) · AÇIK
   KIRMIZILAR (ad · nerede · ölçülen sayı) · DEVİR ÜÇ SAYI · KUYRUKTA BEKLEYEN
   (bloke etmez).

d) **OPERATOR-KUYRUK.md satırı**: KARAR GEREKEN (tek cümle) · SEÇENEKLER (A/B,
   her biri tek cümle + ölçülmüş yan bilgi) · **VARSAYILAN** (cevap gelmezse
   hangisi yürüyor) · HANGİ FAZI ETKİLER · SON KULLANMA (hangi faz açıldığında
   varsayılan yürür).

e) **KAPI.md satırı**: faz · alt kapı · GEÇTİ/KALDI · gerekçe (tek cümle) ·
   log yolu.

### 3.9 Paralellik ve dosya kilidi

Paralel yalnız şu durumda: kartlar kapalı bir listeden dağıtılmış, birbirinin
çıktısını okumuyor ve dosya kümeleri kesişmiyor. Üçünden biri bozulursa sıralı.
Kesişim kontrolü şefin 3.3/4 adımındaki görevidir; ihlalinde hakem fazı düşürür.
Tek yazar ilkesi (v3/B1.8) aynen: `DURUM.md` ve `KAPI.md` → yalnız şef;
`reports/F<n>/DENEMELER.md` → yalnız o fazın işçisi; `OPERATOR-KUYRUK.md` →
şef soru, operatör CEVAP.

### 3.10 Ajan ölümü ≠ kırmızı

API hatası, kota, zaman aşımı, kesilen oturum, kapatılan terminal = **KOŞMAMIŞ**
iş; kırmızı DEĞİLDİR, hipotezi elemez ve iş silinmez. Teşhisi tarafsız cevapçı
koyar: **diskte tutanak + commit varsa faz KOŞMUŞTUR, ikinci kez açılmaz.**
Tutanak yoksa faz yeniden açılır; yarım iş varsa önce commit'lenir, sonra
açılır. Reddedilen iş yan dala alınır, ana dal temiz kalır.

Bu kuralın ilk uygulaması bu belgenin kendisidir: **kosu2 tur 22 KOŞMUŞTUR**
(tutanak `reports/R7/TUR-22.md`, commit `6097bb9`, kabul logu
`accept.tur22.out`) ve tekrar açılmaz. **kosu3 KOŞMAMIŞTIR** (tutanak yok) ve
v3'ün üç iddiası (isci.sh · girdi<30KB · KOSMADI bloğu) kanıtsızdır; ikisi
v4'te zaten geçersiz, `isci.sh` ise F0'da kanıtlanır.

### 3.11 KUYRUK VE VARSAYILAN — bekletmeyen kanal

Kuralın tamamı beş cümledir:

1. Karar gerektiren her şey `reports/kosu/OPERATOR-KUYRUK.md`'ye §3.8.d
   formatında, **VARSAYILANIYLA** düşer. Varsayılansız satır yazmak kart
   ihlalidir.
2. Satırın SON KULLANMA'sı gelene kadar cevap gelmezse **varsayılan yürür**;
   faz durmaz, tutanağa "K-x varsayılanla yürüdü" yazılır.
3. Cevap sonradan gelirse (ONAY mühürlü) ölçüm **geri alınmaz**; fark bir
   sonraki fazın kartı olur ve hüküm yeniden verilir.
4. **Varsayılansız tek sınıf geri dönüşsüz dış adımlardır:** npm publish,
   marketplace PR'ı, Show HN, fiyat yazımı, sahiplik. Bunlar varsayılanla
   yürümez — **PARK** edilir (`DURUM.md`'de "HAZIR, operatör komutu bekliyor")
   ve koşu sıradaki faza geçer. Koşu hiçbir koşulda bunları beklemek için
   durmaz.
5. Teknik soru operatöre GİTMEZ. Bir şef "bunu operatör bilmeli" diye
   düşünürse önce §8.3 cevapçısını açar; cevapçı "bu ölçülmemiş" derse iş
   ölçüm kartıdır, kuyruk satırı değil.

**Devralınan kuyruk (koşu 2'nin cevapsız iki sorusu + R8 blokları) §6'nın
başında K1–K6 olarak açılır ve varsayılanları oradadır.**

---

## 4. KAPI PROTOKOLÜ — yedi alt kapı, sırayla, pazarlıksız

Hiçbir faz kendini "geçti" ilan edemez. Faz sonu sırası:

**4.1 Makine kapısı.** `make && make test` + `npm test` + fazın ilgili kabul
betiği (`reports/R7/accept.sh`, `reports/R8/accept.sh`) tam koşusu. Miras
kırmızı **AD** kümesi büyüyemez; yeni kırmızı ad doğuran değişiklik geri alınır
ve iki log commit'e girer. **SEVK PARİTESİ:** sevk edilen şey native
binary'dir; `hooks/gate.mjs` üstünden alınan yeşil hiçbir şey kanıtlamaz —
fazın dokunduğu yol npm paketindeki binary yoluyla da koşulur. **ÖLÇÜM
YÖNTEMİ:** her bütçe sayısı süreç-İÇİ ölçülür; uçtan uca cetvel 500 µs'yi
çözemez ve bu ölçülmüştür (`3567026`). Uçtan uca alınan sayı rapora "süreç
başlatma dahil" etiketi olmadan giremez.

**4.2 Boş yeşil kapısı.** Fazın eklediği/sıkılaştırdığı her denetim, faz-öncesi
artefakt üstünde KIRMIZI düşmek zorundadır. BİRİNCİL USUL: faz-öncesi
commit'in ürettiği çıktı artefaktı (JSONL, ledger, kabul logu) yeni denetime
verilir. Düşmüyorsa denetim boştur ve tek başına fazı çürütür. AGENTS-PROTOCOL
Kapı 1 aynen geçerlidir: **kabul betiğini uygulayan ajan yazmaz**; değişiklik
gerekiyorsa ayrı ajan, ayrı commit, uygulamadan ÖNCE.

**4.3 Kanıt kapısı.** Tutanaktaki her dosya yolu `test -f` ile, her sayı onu
basan komut yeniden koşturularak doğrulanır. Olmayan yol = yapılmamış adım.

**4.4 Hakem kapısı.** §3.5. Temiz oturum, brief görmez, beş soru, tek satır
hüküm.

**4.5 Mutasyon kanıtı.** Yeni kurulan ya da düzeltilen her denetim için en az
bir kasıtlı bozma denetimi kırmalı ve geri alınınca yeşile dönmeli; iki log da
kanıta girer. **Kırılamayan kapı süs demektir** — bunun bedeli bu repoda
ölçüldü: B1.9'un artık-süreç kontrolü `pgrep -c` yüzünden hiçbir zaman kırmızı
düşemiyordu ve beş ölçüm boyunca "0" bastı.

**4.6 Eşik / ön-kayıt değişikliği bir HAMLEDİR.** Eski değer, yeni değer,
ölçülmüş gerekçe ve kaynağı commit mesajına yazılır; kuyruğa bilgi satırı
düşer. Kapsam: 1000 µs latans tavanı, `MIN_HISTORY`, `ON-KAYIT.md`'nin N'i,
%50 sapma eşiği, %10 uzunluk tavanı. **Ön-kayıt koşudan sonra değiştirilemez**;
değişirse yeni ön-kayıttır ve eski koşunun sayısı onunla yayınlanamaz.
Sessiz gevşetme fazı düşürür.

**4.7 Kırmızı raporlama kuralı.** Her kırmızı yanında kök teşhis + en az bir
ÖLÇÜLMÜŞ çözüm adayı taşır; ölçülüp reddedilen hamle de `DENEMELER.md`'ye
ELENEN HİPOTEZ olarak geçer. "Burada sorun var" tek başına çıktı sayılmaz.

Ardından **yazma kapısı** (`DURUM.md` + `KAPI.md` commit'i) ve **kâtip kapısı**
(docs commit'i). Kapı kırmızıysa faz kapanmaz, sonraki faz açılmaz; reddedilen
iş yan dala. Tek istisna: kırmızı operatör kararına bağlıysa §3.8.d satırı
düşer ve koşu **varsayılanla** devam eder. Kırmızı sonraki faza taşınmaz.

---

## 5. ARAŞTIRMA REJİMİ — her fazın içinde, tek büyük tarama fazı yok

5.1 Her fazın İLK kartı R-kartıdır: o fazın eşiği, yöntemi ve dış iddiaları
    için yayınlanmış kaynak arar. Kaynaksız eşik kapıya giremez; kaynak yoksa
    "yayınlanmış pratik YOK, bant şu ölçümden" açıkça yazılır.
5.2 Kaynak sınıfları: **ölçüm pratiği** (süreç-içi mikro-benchmark, ön-kayıt
    disiplini, gürültü tabanı); **yayın hattı** (npm provenance, platform
    paketleri, plugin marketplace'in canonical dizini
    `anthropics/claude-plugins-official`); **rakip/pazar** (Watcher/Apollo,
    Mindlas, ccusage, Lineman, LangWatch — her biri KENDİ yayınladığı sayıyla,
    ölçüm tarihiyle); **standart** (OTLP / GenAI semconv).
5.3 Rakip iddiası `docs/POSITIONING.md`'de "doğrulandı + tarih" işaretli
    değilse dışarı yazılamaz (Yasa 7).
5.4 Dünya ölçüsü TABANDIR, tavan değil. "Başkası yapmış, biz yapamayız"
    cümlesi yasaktır.
5.5 **Kalıcı veto:** hot-path'te model çağrısı, ağ, telemetri; yeni ağır
    bağımlılık; harici API anahtarı. Kendiliğinden kurulmaz — kuyruğa karar
    satırı düşer (Yasa 6, CLAUDE.md 7).

---

## 6. FAZLAR

Sıra: **F0 → F1 → F2 → F3 → F4** (R7 hattı) **→ F5 → F6 → F7** (R8 hattı)
**→ F8** (M3) **→ F9 → F10 → F11** (kapanış üçlüsü, KOŞULSUZ).

ANTİ-BAHANE KURALI: yarım kalan ya da hiç açılamayan faz "süre yetmedi" tek
cümlesiyle gerekçelenemez. F11 raporu hangi fazın hangi bütçeyi ne kadar
aştığını sayıyla yazar; yarım kalan iş kart olarak kuyruğa girer ve
"yapılmadı" satırında adıyla durur.

### DEVRALINAN KUYRUK — F0 açılırken yazılır, varsayılanlarıyla

Bu altı satır `reports/kosu/OPERATOR-KUYRUK.md`'nin ilk hâlidir. Varsayılanlar
uydurma değildir: K1 ve K2'nin varsayılanı koşu 2'nin kendi değerlendireninin
`6f5d301`'de yazdığı öneridir; K3'ünki §7.1'in yönüdür (kapı gevşetilerek
geçilmez); K4–K6 varsayılansız sınıftır (§3.11/4).

- **K1 · 2b latans nasıl kapanacak?** (a) CI/konteyner temiz ortam kurulur;
  (b) tavan bu makinenin gerçeğine çekilir; (c) 2b R7'den KOPARILIR, CI
  artefaktına bağlanır ("CI'da yeşil değilse geçmez"), R7'nin geri kalanı
  bloke edilmez. **VARSAYILAN: (c).** Yan bilgi: 8 gözlem, min 1218,3 µs, her
  gözlem üst sınır. **Etkiler: F2, F4. Son kullanma: F2 açılışı.**
- **K2 · 6e/7b nasıl yeşile döner?** (a) fixture zinciri `MIN_HISTORY=1` ile
  kurar, ürün kodu değişmez; (b) "veri yok" uyarısını yeşil saymak — **bu
  seçenek zayıflatmadır, teklif edilmez**; (c) paralı çok-oturumlu koşu.
  **VARSAYILAN: (a).** **Etkiler: F3, F4. Son kullanma: F3 açılışı.**
- **K3 · "yeşil main" ne demek?** (a) 41 ismin `DISCLOSURE.md`'deki
  sınıflaması uygulanır (listeye girecek girer, girmeyecek `site/`
  artefaktlarından çıkar), disclosure kapısı yayın kapısı olarak KALIR;
  (b) disclosure kapısı yayın kapısı olmaktan çıkarılır. **VARSAYILAN: (a)** —
  (b) kapıyı gevşeterek geçmektir (§7.1). **Etkiler: F6, F7. Son kullanma:
  F6 açılışı.**
- **K4 · `npm publish` ve tag.** **VARSAYILAN YOK — PARK.** Hazırlık F5/F6'da
  biter, `DURUM.md`'ye "R8 HAZIR" satırı düşer, koşu F8'e geçer.
- **K5 · marketplace PR + Show HN.** **VARSAYILAN YOK — PARK** (F10 malzemeyi
  hazırlar, gönderim operatörün).
- **K6 · fiyat.** **VARSAYILAN YOK.** KOSU-RABADON.md M4'ün kendi hükmü
  geçerli: M4 fiyat yazılmadan da koşar; üç orandan ikisi fiyattan bağımsız
  ölçülür, üçüncüsü raporda "bilinen boşluk" olarak durur.

### F0 — DÜRÜST ENVANTER (60–90 dk) · ölçüm var, onarım yok

Bu fazda hiçbir şey düzeltilmez. Şef 4 işçiyi paralel salar (kapalı liste):

- **0A kabul.** `make && make test`, `npm test`, `bash reports/R7/accept.sh`
  tam koşusu → yeşil/kırmızı sayısı ve kırmızıların ADLARI, log yolları.
  §1.2'nin 23/3'ü bugün de 23/3 mü? Ayrıca `reports/R8/accept.sh` ve
  `make disclosure` koşulur (41 hâlâ 41 mi).
- **0B dal ve devir.** `main`/`kosu2`/`kosu3` farkı: hangi commit hangi dalda,
  R7 işinin main'e taşınmamış hacmi, `git status` temiz mi. kosu3'ün üç
  iddiasından yalnız `scripts/isci.sh` kanıtlanır: bir işçi koşulur ve
  (1) `RAPOR/*.md` 12 satırda kırpılmış, (2) işçinin çıktısından şefin
  stdout'una tek bayt geçmemiş olduğu **gösterilir**.
- **0C vitrin.** `README.md`, `docs/`, `site/`, `index.html` altındaki her
  iddia cümlesi tablolanır: iddia · hâlâ doğru mu · kanıtlayan test/alet ·
  hüküm ADAYI (kal/güncelle/sil). Ölü link taraması. Ledger'dan
  türetilmeyen her sayı YALAN listesine. Bu tablo F9 ve F10'un girdisidir.
  İşçi hüküm vermez, sayar.
- **0D ölçüm hijyeni.** `pgrep -f rabadon | wc -l` doğru sayı basıyor mu;
  makinede canlı artık süreç var mı; `ON-KAYIT.md`'nin N'i ile
  `ab_run.jsonl`'in içeriği yan yana. `olc_2b.sh`'ın bugünkü hükmü "temiz ≤
  min" mi.

Kapı: her maddenin en az bir dosya yolu / komut çıktısı var mı; F0'ın ölçümü
§1 ile çeliştiği her yerde §1 ölü ilan edildi mi; `DURUM.md` F0 sayılarıyla
yeniden yazıldı mı; K1–K6 kuyruğa varsayılanlarıyla yazıldı mı.

### F1 — KABUL BETİĞİ DÜRÜSTLÜĞÜ (1–1.5 s) · çekirdeğe sıfır taşıma-kırmızısıyla girmek

Tek konu: **kabul betiği hedefi mi, gevşemiş vekilini mi denetliyor.**

- `5b` düzeltilir: sabit `>=2` yerine `ON-KAYIT.md`'deki N okunur; N ile
  jsonl'deki görev sayısı uyuşmuyorsa 5b KIRMIZI düşer. Bu değişiklik
  AGENTS-PROTOCOL Kapı 1'e tabidir: betiği **uygulayan ajan yazmaz**, ayrı
  ajan ayrı commit'te yazar ve commit uygulamadan öncedir.
- Aynı sınıf tarama: `accept.sh`'ın kalan assert'lerinde "hedef yerine vekil"
  deseni var mı (sabit sayı, `head -1`, varlık kontrolüyle yetinen yeşil).
  Bulunan her biri ya düzeltilir ya `DENEMELER.md`'ye gerekçesiyle yazılır.
- 5b düzeltildikten sonra 7a'nın hükmü **n=4'te** verilmiş olur: A %75 / B %75
  özdeş, fark yalnız token'da %6,7 → Yasa 7 gereği "kurtarır" yayınlanmaz.
  Bu cümle F8'in (M3) girdisidir ve F4'te hükme bağlanır.
- Eksik iki görev (`joke2k__faker.8b401a7d`, `pylint-dev__astroid.b114f6b5`)
  ya koşulur ya sebebi `ON-KAYIT.md`'ye **ek** olarak yazılır (ön-kayıtın
  kendisi değiştirilmez, §4.6).

Kapı: 4.2 (5b düzeltmesi faz-öncesi jsonl üstünde kırmızı düşüyor mu) + 4.5
(kasıtlı bozma: jsonl'den bir görev silinince 5b kırmızıya dönüyor mu) + hakem.

### F2 — 2b LATANS: temiz ortam ya da dürüst park (1.5–2.5 s)

K1'in varsayılanı (c) yürüyorsa fazın işi **koparma ve bağlama**dır, ölçüm
kovalamak değil:
- 2b `reports/R7/accept.sh`'tan çıkarılıp CI artefaktına bağlanır; R7'nin
  hükmü "23/26, 2b CI'da PARKED" olur ve bu **etiket dosyaya yazılır**, kabul
  betiği artık olmayan bir şeyi ölçüyor gibi yapmaz.
- CI adımı yazılır: temiz runner'da süreç-içi ölçüm, çıktı artefakt olarak
  saklanır. Adımın kendisi bu fazda **kırmızı** doğar (ölçüm henüz yok) ve bu
  dürüsttür.
- R-kartı: gürültü tabanı nasıl raporlanır (kaç örnek, hangi yüzdelik, hangi
  ortam beyanı) — yayınlanmış pratik aranır; yoksa "yayın YOK, bant şu
  ölçümden" yazılır.
- Yasak: tavanı sessizce yükseltmek (§4.6), kirli ölçüme etiket yapıştırmak,
  "daha çok örnek al" (her gözlem üst sınırdır, yön değişmez).

Kapı: 4.6 (koparma bir hamledir, commit mesajında eski/yeni/gerekçe) + hakem.

### F3 — SAYAÇ DOĞRULAMASI: 6e / 7b (1.5–2.5 s)

K2'nin varsayılanı (a): fixture zinciri `MIN_HISTORY=1` ile kurar. Sert
şartlar:
- **`MIN_HISTORY` ürün kodunda değişmez.** Fixture yalnız testin gördüğü
  zincir uzunluğunu kurar; sevk edilen davranış aynı kalır ve bu, gerçek
  çok-oturum davranışının R8 sahne testine bırakıldığı **yazılarak** kabul
  edilir (bilinen boşluk, saklanmaz).
- 6e: B kolunun `estimated_saved` toplamı gerçek değer mi, `null` mı — sayı
  ledger'dan türetilir, elle yazılmaz (Yasa 5).
- 7b: sapma yüzdesi hesaplanır. **%50'yi aşarsa** ön-kayıtın kendi hükmü
  yürür: dolar cümlesi README'den ve landing'den aynı gün kalkar (bu, F9/F10
  için bağlayıcı bir devir sayısıdır).
- 6e'nin dolar-token karşılaştırması aynı birimde mi (tur 19'un CHALLENGE-4
  bulgusu) — düzeltildiyse mutasyon kanıtı istenir.

Kapı: 4.2 (fixture'sız hâlde 6e/7b kırmızı mı) + 4.5 + 4.6 (fixture bir
hamledir) + hakem.

### F4 — R7 HÜKMÜ (0.5–1 s) · yeşile dönmek ya da dürüstçe kapatmak

- `reports/R7/accept.sh` tam koşusu; yeşil/kırmızı sayısı ve **adları**.
- Kalan her kırmızının yanında kök teşhis + ölçülmüş çözüm adayı (§4.7).
- **Yayın hükmü (Yasa 7):** iki kolun farkı gürültü içindeyse "rabadon
  kurtarır" cümlesi **yayınlanmaz**; sonuç negatif de olsa yayınlanır ve
  ön-kayıtın çürütme koşulu uygulanır. Bu hüküm tek cümleyle
  `reports/R7/KOSU.md`'ye yazılır ve F8'in girdisidir.
- Tur işi `main`'e **tek temiz squash-merge** ile taşınır (checkpoint
  commit'leri asla). Bu, R8'in "yeşil main" şartıyla aynı kapıda birleşir.

Kapı: hakem + kâtip. Hakem KALDI derse R8 hattı açılmaz.

### F5 — R8'İN KARAR GEREKTİRMEYEN İŞLERİ (2–3 s)

Kapalı liste, paralel kartlar (dosya kümeleri kesişmez):
- **17/18 uyuşmazlığı:** `release.yml`'in kopyaladığı binary listesi ile dört
  platform paketinin dosya listesi **bire bir** aynı olur (`rabadon-run` her
  pakete). Kabul: iki listeyi karşılaştıran test.
- **Plugin paketi:** `.claude-plugin/plugin.json` + `hooks/hooks.json`;
  hook'lar npm'deki **aynı** binary'yi çağırır, ikinci kod yolu yoktur.
  Kabul: `claude --plugin-dir .` ile yükleniyor ve çağrı yolu diff'i sıfır.
- **10k kesme testi:** hook çıktısı (`additionalContext` dahil) 10.000
  karakterde kesiliyor; enjeksiyonun 10k'ya sığdığını gösteren test yazılır.
  Bu test faz-öncesi kodda **kırmızı düşmeli** (§4.2) — düşmüyorsa borç yoktu,
  o zaman borcun olmadığı ölçümle yazılır.
- **Free bayrağı:** `RABADON_TIER=free` → sinyaller + sayaç açık, enjeksiyon +
  repair kapalı, kapanış satırı "düzeltme kapalıydı, tahmini X $ yandı" der.
  İki tier'da da kapanış metni testle sabitlenir.
- Tag ve sürüm hazırlığı (yayın DEĞİL, hazırlık).

Kapı: 4.1 (sevk paritesi: npm paketindeki binary yoluyla) + 4.2 + hakem.

### F6 — YAYIN KAPISININ ANLAMI (1–1.5 s)

K3'ün varsayılanı (a) yürür: `DISCLOSURE.md`'nin 41 isim sınıflaması uygulanır
— listeye girecekler `site/published-projects.txt`'e girer, girmeyecekler
`site/measured.json` · `rule_census.json` · `field.jsonl` artefaktlarından
çıkar. Disclosure kapısı **yayın kapısı olarak kalır**.

Şartlar: `allowlist.py`'nin tam-eşleşme ve fail-closed davranışı
**gevşetilmez** (kural değişmez, veri düzelir); mutasyon kanıtı zorunlu
(listeden bir isim çıkarılınca kapı kırmızıya dönmeli). Kapanışta `make
disclosure` yeşil ve `ci.yml` `main` üstünde yeşil — "yeşil main" ilk kez
**tanımlı ve sağlanmış** olur.

Kapı: 4.5 (mutasyon) + 4.1 (`main`'de yeşil CI) + hakem.

### F7 — R8 YAYIN HAZIRLIĞI VE PARK (0.5–1 s)

Yayının kendisi K4'tür ve **varsayılansızdır**. Bu fazın işi yayını
tetiklenebilir hâle getirmektir:
- `reports/R8/accept.sh`'ın yayın-öncesi maddeleri yeşil (paket listesi,
  plugin, free bayrağı, README kurulum bölümü hazır ama "not on npm yet" notu
  **henüz kalkmaz** — o not yalnız yayın gerçekleştiğinde kalkar).
- `DURUM.md`'ye tek satır: **"R8 HAZIR — `npm publish` operatör komutu
  bekliyor; koşu bloke değil."**
- Koşu F8'e geçer. Yayın sonradan olursa README notunun kalkması ve
  `npm view rabadon version` kabulü bir sonraki fazın kartıdır (§3.11/3).

### F8 — M3: KANIT YAZISI + POSITIONING (2–3 s)

- **POSITIONING tazelenir:** "üretimde kimse yok" cümlesi silinir; yerine
  yöntem ayrışması yazılır (yerel binary · hot-path'te sıfır model · sıfır ağ ·
  deterministik · fail-same · ledger'dan türetilmiş dolar). Watcher ve Mindlas
  adıyla, kendi yayınladıkları tanımla, **ölçüm tarihiyle** girer.
- **M3 yazısı:** başlık iddiasız ("We measured whether rabadon pays for
  itself"), beş sayı, ham JSONL linki, `bench/reproduce.sh` komutu. F4'ün
  hükmü ne çıktıysa o yazılır — özdeş oran ve gürültüdeki token farkı
  **saklanmaz**, "kurtarır" diye de çevrilmez (Yasa 8 + Yasa 7).
- Karşılaştırma tablosu: rabadon vs ccusage vs guardrail sınıfı — her sütunda
  ne ölçer, ne engeller, hot-path'te ağ/model var mı. Rakip sütunundaki her
  sayı linkli ve POSITIONING'de "doğrulandı + tarih" işaretli.
- Yayın adımı (gönderme) K5'tir: PARK.

Kapı: Yasa 7 denetimi (yazıdaki her sayı bir ledger satırına ya da bir teste
bağlı mı) + hakem.

### F9 — DOCS BÜYÜK TURU (kapanış, koşulsuz, 1–1.5 s)

Kâtip `docs/` ağacının tamamını + `README.md`'yi bugünkü koda karşı okur;
0C tablosunu girdi alır ve her iddia için kal/güncelle/sil hükmünü **uygular**.
Sert maddeler:
- "Not yet published to npm" · `rabadon ui` stub · "unplanned breakage üstünde
  tutulan onarım 0" — üçü de bugünkü gerçeğe göre yeniden yazılır; iyileşmediyse
  **aynen kalır**.
- 7b'nin sapması %50'yi aştıysa dolar cümlesi kaldırılır (F3'ün devri).
- `reports/INDEX.md` son hâline getirilir: koşunun ürettiği her kalıcı dosya
  yönlendirme tablosuna girer.
- Kapı `docs_truth_check` (mekanik): duran-iddia kalıbı 0 adet; her sayısal
  iddianın yanında onu basan test/alet ADI. Test §4.2 usulüyle faz-öncesinde
  kırmızı düşmeli — düşmüyorsa ya docs zaten temizdir (ölç, kanıtla) ya test
  boştur.

### F10 — LANDING + SAVUNMA (kapanış, koşulsuz, 2–3 s)

Sıra kesindir: **ÖNCE ÖLÇÜM, SONRA TASARIM.**
- 10a envanter (işçi 1): 0C tablosu tazelenir; `site/` ve `index.html`'deki her
  iddia · ölü link · UI'ın söylediği ile ledger'ın yaptığı her fark.
- 10b sayfa (işçi 2, 10a bitmeden başlamaz): sayfa ŞU ürünü anlatır — oturum
  içi kapı + zincirli defter + tutulan onarım + kapanış satırı. Ölçülen
  gerçekleştiyse canlı sayıyla; gerçekleşmediyse **VİZYON etiketi + gelecek
  zaman** — ikisi asla karışmaz.
- 10c `docs/SAVUNMA.md`: problem, mimari kararlar ve NEDENleri (neden native
  binary, neden hot-path'te model yok, neden fail-same), ölçülmüş sayılar, ve
  **bu orkestrasyonun kendisi** (şef/işçi/hakem/kâtip/cevapçı döngüsü, Yasa 7,
  DENEMELER hipotez-eleme sistemi) hikâyenin parçası olarak. Ham malzeme
  fazların tutanaklarından toplanır, sıfırdan yazılmaz.
- Kapı `landing_truth_check` (mekanik): sayfadaki her sayı ve özellik iddiası
  ya repoda bir test/alet adıyla eşleşir ya sayfada durmaz; vizyon bölümleri
  şimdiki zamanla yazılmaz; ölü link 0. Gönderim (Show HN, PR) K5'tir: PARK.

### F11 — KAPANIŞ (koşulsuz, atlanmaz)

1) Kabul: F0'ın saydığı kırmızı kümesinden kaçı kapandı, **isim isim**; yeni
   kırmızı ad 0 mı.
2) R7'nin beş sayısı F0'ın yazılı yöntemiyle yeniden; kımıldamadıysa açıkça
   yazılır.
3) 2c oranı yeniden ölçülür (%6,50 nereye gitti); tavan aşıldıysa hamle olarak
   raporlanır.
4) §2 sipariş haritası madde madde işaretlenir: kapandı (kanıt yolu) / açık
   (sebep + kuyruk satırı).
5) Kuyruk tablosu: hangi satır varsayılanla yürüdü, hangisi cevaplandı,
   hangisi PARK'ta bekliyor.
6) `DURUM.md` son hâli + yalnız **push'tan SONRA** rapor. "Bitti/hazır" toptan
   cümlesi yasak.
7) Rapor operatöre dört satırla başlar: kaç kapı yeşile döndü · kaç yeni
   kırmızı doğdu (hedef 0) · R7'nin hükmü tek cümle · R8/M için PARK'ta ne
   duruyor ve tek komutla ne olur.

---

## 7. YASAKLAR (kalıcı vetolar dahil, koşu boyunca)

7.1 Kapıyı **gevşeterek** geçmek · kırmızıyı sonraki faza taşımak · boş yeşil ·
    hedef yerine vekil denetlemek · testi/fixture'ı yeşil için değiştirmek
    (CLAUDE.md 1).
7.2 Kirli ölçümün üstüne etiket yapıştırmak · ön-kayıtı koşudan sonra
    değiştirmek · `MIN_HISTORY`'yi ürün kodunda yeşil için oynatmak · sabit
    eşiği kaynaksız uydurmak.
7.3 Hot-path'te model çağrısı, ağ, telemetri · yeni ağır bağımlılık · harici
    API anahtarı · ledger'dan türetilmeyen sayıyı kamuya yazmak (Yasa 5–7).
7.4 Şefin kod yazması · işçinin `DURUM.md`/`KAPI.md`'ye dokunması · kâtibin
    koda dokunması · şefin ya da işçinin operatöre **kendi işi hakkında hüküm
    cümlesi** kurması (§3.7) · manifesto dışı dosya açmak · alt-ajan (Task)
    salmak.
7.5 Operatöre **teknik** soru göndermek. Beş kategori dışına çıkan her soru
    önce cevapçıya, sonra ölçüm kartına döner.
7.6 `kosu` dalından çıkmak · `git checkout main` · `branch -D` · geçmişe
    `reset --hard` · `.git`/worktree yapısına dokunmak · checkpoint commit'ini
    `main`'e taşımak. `main`'e giriş yalnız tur kabulü yeşilken tek
    squash-merge'dür.
7.7 Rapor dili: virtüöz raporu yok. Cevaplanan soru "kaç mikrosaniye" değil —
    "bu kapı kırılabiliyor mu, bu sayı ledger'dan mı geliyor, bu cümle
    yayınlanabilir mi".

---

## 8. AÇILIŞ BLOKLARI

### 8.1 Koşu açılışı (bir kez, ilk oturuma)

    1) Bu dosyayı repo köküne commit et. scripts/kos.sh'ı scripts/arsiv/'e
       taşı, başına tek satır iptal notu koy (silme). docs/DEGERLENDIREN.md'yi
       aynı şekilde arşive indir.
    2) reports/kosu/OPERATOR-KUYRUK.md'yi §6'daki K1–K6 satırlarıyla,
       VARSAYILANLARIYLA yaz.
    3) Koşu dalı: kosu3'ten devam eden taze worktree, dal adı `kosu4`.
       Rabadon kapısını BAĞLAMA (F0'da observe modda ve sarmalayıcıyla).
    4) F0 şefini §8.2 bloğuyla aç. Koşucu script KURMA. tmux'ta arka plan
       döngüsü BAŞLATMA.

### 8.2 Faz açılış bloğu (her faz başında operatör `/clear` + bunu yapıştırır)

    Sen F<n> ŞEFİSİN ve yalnız bu fazı yaşayacaksın. Oku (başka hiçbir şey
    açma): CLAUDE.md + AGENTS-PROTOCOL.md + KOSU-RABADON-4.md §3, §4, §7 ve
    §6/F<n> + reports/kosu/DURUM.md + reports/kosu/OPERATOR-KUYRUK.md.
    Sonra §3.3'teki on adımı sırayla uygula: devir üç sayıyı al → kuyruğu oku
    (cevap yoksa VARSAYILAN yürür) → kartları kes ve SIRALI/PARALEL etiketle →
    işçileri scripts/isci.sh ile ayrı süreçlerde sal (kod yazma, sen şefsin;
    alt-ajan salma) → orakçıyı işlet → raporları kanıtla doğrula → §4'ün alt
    kapılarını sırayla koştur, hakemi ve kâtibi AYRI temiz oturumlar olarak aç
    → tutanak + DURUM.md + KAPI.md + commit+push → devir üç sayıyı yaz → ÖL.
    Operatörden soru gelirse CEVAPLAMA: §8.3 bloğuyla tarafsız cevapçı aç ve
    cevabını değiştirmeden ilet.

### 8.3 Tarafsız cevapçı bloğu (soru geldiğinde şefin açacağı temiz oturum)

    Sen tarafsız cevapçısın. Sana bir soru ve kanıt dosyası yolları verildi;
    fazın ne yapmaya çalıştığı sana SÖYLENMEDİ ve sormayacaksın. CLAUDE.md'yi
    oku, kanıt dosyalarını aç, gerekiyorsa ölçümü yeniden koştur. Cevabın
    ≤10 satır ve her cümlenin yanında dosya yolu ya da komut çıktısı olacak.
    Yol gösteremediğin cümleyi kurma; "bu ölçülmemiş" geçerli bir cevaptır.
    Kimseyi memnun etmek için yazmıyorsun.

### 8.4 İşçi çağrısı (şefin kullanacağı tek biçim)

    scripts/isci.sh <ad> <komut...>
    # ham çıktı: reports/kosu/log/<ad>.log
    # rapor    : reports/kosu/RAPOR/<ad>.md   (süreç head -12 ile kırpar)
    # şefin stdout'una işçiden tek bayt girmez; şef raporu OKUMAYI SEÇER.

---

## 9. BÜTÇE (yol gösterici, kapı değil)

F0 60–90 dk · F1 1–1.5 s · F2 1.5–2.5 s · F3 1.5–2.5 s · F4 0.5–1 s ·
F5 2–3 s · F6 1–1.5 s · F7 0.5–1 s · F8 2–3 s · F9 1–1.5 s · F10 2–3 s ·
F11 0.5–1 s.

Çekirdek sığmazsa kesilen faz **atlanmaz**: kalan iş kart olarak kuyruğa
yazılır ve F11 raporunda "yapılmadı" satırında adıyla durur. Kapanış üçlüsü
(F9→F10→F11) her koşulda koşar — docs ve vitrin bayattır ve bu koşunun açık
siparişidir.
