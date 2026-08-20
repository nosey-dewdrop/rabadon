# rabadon — ürün protokolü

Tarih: 2026-08-20.
Bu dosya **projenin tamamını** kapsar. Tek bir katmanı değil.

`reports/phase-0..3` başka bir işti (dürüst-fix madenciliği ve kapsam düzeltmesi).
Bu protokol kendi numarasını kullanır: **T1..T8** (tur).
`AGENTS-PROTOCOL.md`'nin devir kuralı ve üç kapısı aynen geçerli.

---

## 0. Ürünün cümlesi

**rabadon, kodlama ajanının hatasını daha büyümeden yakalar ve düzeltir.**

Vaat, kullanıcının duyduğu haliyle: **sen uyurken ajan bozmaz.**

Ne değil, hepsi ayrı ayrı reddedilir:
gözcü değil, kapı değil, guardrail değil, izin sistemi değil,
**hafıza değil, geçmiş değil, history değil, ölçüm değil, ölçümcü değil,
rapor değil, dashboard değil.**
Bunların hepsi sonradan bakan ya da "hayır" diyen şeylerdir. rabadon sonradan
bakmaz ve hayır demez; hamle çalışmadan **o anda** müdahale eder ve düzeltir.

Kritik nokta, tasarımın her yerinde geçerli: **üçüncü tekrar beklenmez.**
Hata birikmeye başladığı **ilk anda** kesilir. "Aynı şeyi üç kez denedin"
bugünkü davranıştır ve yetersizdir; o noktada token çoktan yanmış, hata çoktan
ağaca girmiştir.

### Mekanizma: rabadon akıllı olmaya çalışmaz

rabadon'un içinde beyin yoktur ve olmayacaktır. Kullanıcı zaten bir ajan kurdu;
o ajan kodu nasıl yazacağını biliyor. Bilmediği tek şey **kendi kör noktası**:
ürettiği hatanın tarihçesini kendi context'inde göremiyor, o yüzden aynı köke
tekrar tekrar çarpıp token yakıyor.

Üç adımda çalışır:

1. **Bilgi ajandan gelir.** PreToolUse'da tool adı, argümanlar, dosya yolu;
   PostToolUse'da `tool_response`. Hepsi Claude Code'un kendi hook'undan akar.
   rabadon dışarıdan hiçbir şey sormaz, hiçbir yere bir şey göndermez.

2. **"Yanlış" kararı yargı değil, olgudur.** İki kaynağa dayanır:
   projenin **kendi testi** (süit yeşildi, bu hamleden sonra kırmızı) ve
   rabadon'un **kendi kaydı** (bu hata imzası daha önce çıktı, o hamle tutmadı).
   rabadon asla "bu kod kötü" demez, diyemez de. "Bu daha önce kırıldı" der.

3. **Tamiri ajan yapar.** rabadon `additionalContext` ile tek bir metin fısıldar
   ve çekilir. Ajan o bilgiyi okur, düzeltmeyi kendisi yazar. rabadon tek satır
   kod üretmez.

Ağır durumda (T7) devreye giren kontrollü deneyde de yazan ajandır: repo
kopyalanır, testler hash-kilitlenir, **ajan kopyada koşar**, sonuç aynı testle
doğrulanır. İşçi ajan, hakem rabadon.

Tek cümlede: **rabadon bir tamirci değil, tamircinin göremediğini ona gösteren
katalizördür.** Zekâ ajanda; rabadon o zekâyı doğru anda ve doğru bağlamla
tetikler, milisaniyede, yerel olarak.

Kullanıcının cümlesi:
*"Sabah kalktığımda ajanın gece ne bozduğunu temizlemiyorum artık."*

İlk gün hissettiği an: ajan yanlış bir düzeltme üretir, hamle henüz çalışmamıştır,
rabadon araya girer ve neyin yanlış olduğunu söyler, ajan doğrusunu yapar,
kullanıcı hiçbir şey yapmaz. Ürünün tamamı bu tek anı üretmek için vardır.

Bugün repo bu cümleyi söylemiyor: `package.json` "reliability runtime",
keywords'te `guardrails`, README'de "Supervise your coding agent". Üçü de T1'de
düşer.

### Görünürlük sorunu ve fatura

Bu ürünün en büyük riski teknik değil: **görünmezlik.** rabadon sessizce
çalışırsa kullanıcı ekranına bakar, her şey yolunda görünür ve şunu düşünür:
"acaba bunu silsem de aynı olur muydu, Claude zaten kendi düzeltiyordu belki."
Gizli kahramana kimse abonelik ödemez.

İkinci ve daha sert itiraz da bu: **"sen olmasan Claude dördüncü turda kendi
bulurdu."** Bu itiraz bazen haklı. Cevabı tek yerden gelir: müdahaleden sonra
aynı hata bir daha çıktı mı. Çıkmadıysa müdahale tuttu. Bu aynı oturumda,
ek maliyetsiz ölçülür.

Çözüm **fatura**, ve faturanın iki cümlesi vardır, ikisi de olgudur:

> Bu oturumda 7 birikme kesildi. Altısında hata bir daha çıkmadı.

Tahmin yok, karşı-olgusal sayı yok, ikisi de ledger'da duruyor, ikisi de
doğrulanabilir, ikisinin de maliyeti sıfır. (Yasa 5.)

**Maliyet neden sıfır:** rabadon ekstra hiçbir şey koşturmaz, ekstra LLM
çağırmaz, arka planda gizli test açmaz. Kesilen tur **zaten yanacaktı**;
kesilince yanmıyor. rabadon para harcatmaz, harcanacak parayı cüzdanda tutar.

**İlk gün aha anı** kuruluma değil ilk gerçek hataya bağlanır. Sahte demo yok:
ajan ilk kez saçmaladığında rabadon araya girer ve yeşil/kırmızı karşıtlığını
gösterir. O an ilk gün gelir, çünkü ajanlar ilk gün de saçmalar.

### Ürünün ölçeği neden bu tanıma bağlı

Hedef: 1000 ödeyen kullanıcı × ayda 200 dolar. Bu sayı küçük; dünyada milyonlarca
yazılımcı ajan kullanıyor, binde birinin ödemesi yetiyor. Yani sorun pazar
büyüklüğü değil, **ürünün gerçekten işe yarayıp yaramaması.**

İyi ürünün tanımı tek cümle: **kullanıcı kurar, ilk gün fark yaratır, silmez.**
Bugün rabadon bu testi geçmiyor; kendi kullanıcısının deneyimiyle projeleri
zorlaştırıyor. Bütün turlar bu testi geçirmek içindir.

---

## 1. Bugünün gerçeği (kod okunarak, iddiadan değil)

**Ölçek.** native/ altında 35 dosya, 18.865 satır C++. core/ altında 4 JS modülü
+ 4 test. 25 CLI verb'ü. npm paketi 0.2.3, dört platform binary'si, yayınlanmamış.

**Hız.** gate medyan 3.14 ms, p95 3.87 ms. Saf yargılama 245 µs (34 fixture,
200 yargı). Yani zamanın **%92'si süreç başlatmada**, hesaplamada değil.
node gate 100 ms. Native kazancı gerçek ve ölçülmüş.

**Katmanlar ve durumları:**

| katman | dosya | satır | durum |
|---|---|---|---|
| kapı | gate.cpp | 3370 | çalışıyor, 61 gerçek yakalama / 30 gün |
| kural tabanı | baseline.h, rules.h, cmdtext.h | 3966 | çalışıyor |
| onarım | repair.cpp | 1044 | çalışıyor, gerçek kırılmada 0 tutulmuş |
| plan koşturucu | loop.cpp | 340 | çalışıyor, **adı yanıltıcı** |
| kanıt/rapor | trace, export, stats | 2926 | çalışıyor |
| takım sunucusu | serve.cpp | 508 | çalışıyor, alıcısı yok |
| çekirdek sandbox | sandbox.cpp | 499 | Anthropic aynısını gönderiyor |
| JS katmanı | core/*.mjs | ~1600 | native'in gölgesi, çoğu ölü |
| **birikme motoru** | **yok** | **0** | **ürünün cümlesi burada yaşıyor** |

**Oturum içi tespitin tamamı,** gate.cpp:3348, sekiz satır:
`ss.lastCmd == command` tam eşitlik, arada kod düzenlemesi yoksa sayaç, üçte blok,
sadece `toolName == "Bash"`.

Oturum hafızası: `lastCmd` (tek string), `lastCmdTs`, `cmdRepeat`,
`recent` (30 etiket, 120 karaktere kırpık).

**Dolayısıyla bugün görünmeyen üç şey:**
1. Ajan aynı düzeltmeyi bir boşluk farkıyla yazarsa → görünmez.
2. A,B,A,B,A salınımı → sayaç her turda sıfırlanır, görünmez.
3. Edit tarafında hiçbir birikme → loop-stop Bash'e kilitli, oysa compound error
   asıl Edit'te birikir.

**En ağırı:** hamlenin sonucu tutulmuyor. `recent` sadece etiket tutar.
"Bu edit'ten sonra şu test kırıldı" cümlesi kurulamaz. Kurulamadığı için ajana
verilecek teşhis yoktur. Bu, "sadece durduruyor, iyileştirmiyor" şikâyetinin
kod seviyesindeki tam karşılığıdır. Sorun durduramamak değil, **söyleyecek sözü
olmaması.**

**Belge çelişkisi.** BENCHMARK.md üç ayrı yerde repair sayısını söylüyor:
§4 tablosu "0 on real breakage", §5 "repairs held = 2", Reproduce bölümü
"repairs-held = 0". §5 bu kaymayı uyarıyor ve aynı sayfada kaymış durumda.

---

## 2. Araştırmadan gelen beş yasa

Turların tasarımı bunlara dayanır. Tartışılmaz, uyulur.

**Yasa 1 — yanlış pozitif ürünü öldürür.**
SWE-agent semantik takılma tespitini denedi ve **terk etti**; yanlış pozitif çok
yüksekti. Kalan korumalarının hepsi %100 kesin: sadece kesin yanlış bir şey
varken ateşleniyorlar. OpenHands tespiti tuttu ama uzun süren işlemi bekleyen
ajanları öldürdü (issue #5355, #10350) ve kullanıcı bunu hata olarak açtı.
Google Tricorder eşiği: etkin yanlış pozitif **%10 altı**; üstünde geliştirici
aracı kapatıyor. FindBugs Google'da tam bu yüzden tutmadı.
→ Kesin olmayan hiçbir sinyal bloklamaz. Ölçülmemiş hiçbir kural enforce edilmez.

**Yasa 2 — satır göstermek zarar verir.**
arXiv 2604.05481, SWE-bench Verified 500 örnek, 61 yapılandırma:
dosya düzeyi yerelleştirme baskın faktör, dosyasız temele göre **15-17 kat**.
Satır düzeyi bağlam genişletmesi gürültü yükselttiği için performansı **sıklıkla
düşürüyor**. Başka çalışmada eklenen bilgi türleri arasında en büyük iyileşme
hata raporundan (%111), en azı yerelleştirmeden.
→ Enjeksiyon "şu satır yanlış" demez. Dosya bağlamı + neyin kırıldığı der.

**Yasa 3 — karşıtlık tek başına hatadan güçlü.**
ContrastRepair: sadece negatif geri bildirim kök nedeni bulmaya yetmiyor;
geçen ve kalan testten oluşan **karşıtlık çifti** verildiğinde model kökü
belirgin biçimde daha iyi buluyor.
→ Bizde bedava: ardışık iki hamlenin sonucu zaten kayıtta olacak.

**Yasa 4 — geri bildirim kalitesi yükselmeden tekrar sormak token yakar.**
Olausson et al. (arXiv 2306.09896): self-repair'in kazancı maliyet sayılınca
büyük ölçüde kayboluyor, çünkü model kendi kodunu eleştirme yeteneğiyle sınırlı.
Kazanç ancak geri bildirim kalitesi **dışarıdan** yükseltilince çıkıyor.
→ Birikme motorunun varlık sebebi tam olarak budur: ajanın göremediği tarihçeyi
ona söylemek. Bu bir "hayır" katmanı değil, bir düzeltme katmanıdır.

**Yasa 5 — olmamış dünya hakkında sayı yazılmaz.**
"Şu kadar token kurtardım" cümlesi karşı-olgusaldır: kesilmeseydi ajanın kaç tur
daha süreceğini kimse bilmiyor. Kullanıcı böyle bir sayıyı doğrulayamaz, bir
süre inanır, sonra inanmayı bırakır ve aracı siler.
→ Fatura tahmin etmez, **sayar**. Tahmini rakam ancak iki kollu koşudan sonra ve
kaynağını göstererek yazılır. Repo bu tavırda zaten: BENCHMARK.md ölçmediği
sayıyı yazmıyor, o disiplin faturaya da uygulanır.

---

## 3. Mimari karar

Üç kol olacak. İkisi var, ortadaki yok.

| kol | ne zaman | bütçe | rol |
|---|---|---|---|
| kapı (gate) | her tool call | 3.1 ms → hedef < 1 ms | **kesin** olanı durdurur |
| **birikme motoru** | her tool call | hedef < 1 ms | **birikmeyi görür, teşhis enjekte eder** |
| onarım (repair) | oturum seviyesi | saniye-dakika | kontrollü deney |

Ortadaki kolun adını sen koyacaksın. Bu belgede "birikme motoru" diye geçiyor,
tanım adı, marka adı değil.

Neden ayrı bir kol: repair.cpp klon + hash-kilit + tam test koşusu yapıyor.
Bu saniyeler-dakikalar sürer, tur içinde çalışamaz. gate ise milisaniyede karar
verir ama neyin biriktiğini göremez. Compound error tam ikisinin arasında
yaşıyor: gate'in göremeyeceği kadar bağlamlı, repair'in yetişemeyeceği kadar hızlı.

---

## 4. rabadon'u kim denetliyor

Bugünkü dürüst cevap: **hiç kimse.** Kendi ledger'ını kendi yazıyor, kendi
audit'ini kendi koşuyor. Zincir sağlam ama zincirin doğru olduğunu söyleyen
yine rabadon.

Bu T6'da ciddileşir. Enjeksiyon yaptığın an ajanın kararını etkiliyorsun.
Yanlış bilgi enjekte edersen ajanı **sen** bozarsın: "bu daha önce kırıldı"
cümlesi yanlışsa, ajan çalışan kodu bozmaya gider. Bir kapının yanlış pozitifi
kullanıcıyı kızdırır; bir enjeksiyonun yanlış pozitifi kodu bozar. Ağırlık farkı
budur.

Üç katman, üçü de zorunlu:

**Hakem rabadon değil, projedir.** Süit yeşil miydi kırmızı mı sorusunu proje
cevaplar. rabadon asla "bu kod kötü" demez, diyemez de; "bu daha önce kırıldı"
der. Bu ayrım repoda zaten var (repair.cpp'nin arbiter'ı ayrı bir binary,
proposer contract'ı hiç görmez) ve korunur.

**Yanlış pozitifi ölçen, sinyali yazan olamaz.** `AGENTS-PROTOCOL.md`'nin
Kapı 1'i burada da geçerli: bir sinyalin doğruluğunu değerlendiren kabul testi,
o sinyali uygulayan oturumdan **önce** ve **ayrı** yazılır. Kendi kendini
ölçen bir dedektör, ölçüm değil beyandır.

**Kullanıcı kendi başarısızlığımızı görebilmeli.** Fatura "7 müdahale,
6'sında hata bir daha çıkmadı" diyorsa, **yedincinin ne olduğu ledger'da açık
olmalı** ve `rabadon usage` ile görülebilmeli. Kendi hatasını göstermeyen fatura
fatura değildir, reklamdır. Bu aynı zamanda LLM-yargıç kullanmama gerekçesidir:
bir modelin kendi çıktısını değerlendirmesinde konum, uzunluk ve kendini kayırma
yanlılıkları ölçülmüştür; hakem deterministik kalır.

---

## 5. Hangi ajanlarla çalışır (karar: derin ve dar)

**Karar: sadece Claude Code, tam çalışan. Diğerleri T8 sonrası.**

Gerekçe ölçülü, tercih değil. Birikme motoru üç şeye ihtiyaç duyar:
(a) edit **çalışmadan önce** görülmesi, (b) sonucun yakalanması,
(c) **ajana** metin gönderilebilmesi.

| ajan | edit öncesi | sonuç | ajana mesaj | motor çalışır mı |
|---|---|---|---|---|
| Claude Code | PreToolUse | PostToolUse | `additionalContext` | **tam** |
| Cursor IDE | `preToolUse` var | `postToolUse` var | shell'de `agentMessage` var, `afterFileEdit` **yalnızca bildirim** | kısmî |
| Cursor CLI | yok | yok | yok | hayır (yalnız shell olayları geliyor) |
| Aider / Goose / Codex CLI / Gemini CLI | yüzeyler ayrı ve dengesiz | | | ölçülmedi |

Kritik ayrıntı: Cursor'ın `afterFileEdit` çağrısı `old_string`/`new_string`
taşır ama **bilgilendirmedir**; oradan ne ajana mesaj gider ne de ajan
durdurulur. Yani Cursor'da fren edit tarafında çalışmaz, sadece shell tarafında
çalışır. Cursor CLI'da ise yalnız shell olayları akıyor.

**Neden yarım destek vermiyoruz:** yarım çalışan bir fren, frensiz olmaktan
tehlikelidir. Kullanıcı korunduğunu sanar, korunmaz. Ve Yasa 1'in mantığı burada
da geçerli: bir ortamda güvenilmez çalışan araç, her ortamda silinir.

Bu karar `docs/agent-contract.md`'ye de yazılır, çünkü o belge bugün Cursor'ı
desteklenen sayıyor ve Cursor'ın hook yüzeyi o belge yazıldığından beri
değişmiş durumda. Kapsam dürüstçe daraltılır: **"rabadon'un freni bugün Claude
Code'da çalışır; diğer ajanlarda kapı çalışır, fren çalışmaz."**

---

## 6. Koşu protokolü (uzun koşu, ajan başına faz)

Bu proje tek oturumda bitmez ve bitmemeli. Uzun koşu üç şeyi bozar, üçünün de
karşılığı burada yazılı: **context şişmesi**, **inşa eden ajanın kendi compound
error'ı**, ve **hedeften kayma**.

### 6.1 Bir tur, bir ajan, sıfır devralınan context

Her tur **temiz bir oturumda** çalışır. Ajan bir öncekinin context'ini görmez,
konuşmasını okumaz, iddiasına güvenmez. Devir **dosyayla** yapılır
(`AGENTS-PROTOCOL.md` devir kuralı).

Bir ajanın okuduğu her şey şudur ve fazlası değildir:

1. bu belgenin **§0–§5** kısmı (ürün, yasalar, mimari, denetim, kapsam)
2. **kendi turunun** bölümü
3. bir önceki turun `reports/T{n-1}/CLAIM.md` ve `accept.sh` **çıktısı**
4. dokunacağı dosyalar

Okumadığı: önceki turların konuşmaları, diğer turların bölümleri, bu belgenin
gerekçe paragrafları dışındaki her şey.

**Tur içi halka.** Bir tur da tek seferde bitmeyebilir. O zaman tur halkalara
bölünür ve her halka sonunda `reports/T{n}/SAYAC.md` güncellenir: en fazla
150 satır, canlı durum, tamamlanan madde, açık madde, karar. Bir sonraki halka
**yalnız SAYAC.md'yi** devralır, konuşmayı değil.

**Sert kural:** bir ajan "önceki oturumda şunu konuşmuştuk" derse, o cümle
geçersizdir. Dosyada yazmıyorsa olmamıştır.

### 6.2 İnşa eden ajanın reward hacking'i

Bu projenin konusu ajanların sahte fix üretmesi. İnşa eden ajan da aynısını
yapar. Beklenen biçimler ve karşılıkları:

| biçim | nasıl görünür | karşılık |
|---|---|---|
| kabul testini zayıflatma | `accept.sh` düzenlenmiş | Kapı 1: uygulayan yazamaz, `git log -- reports/T{n}/accept.sh` tek commit ve uygulamadan önce |
| testi skip'leme / assert silme | `.skip`, `xit`, `GTEST_SKIP`, azalan assert | gate'in kendi `test-tamper` kuralı repoda zaten var, koşuda **açık** kalır |
| test dosyasını değiştirip yeşil alma | hash değişmiş | `sha256` kilidi, repair.cpp'de var, turda da uygulanır |
| sayıyı elle yazma | `make test` sayısı beyan edilmiş | sayı komut çıktısından okunur, CLAIM.md'ye **komutla birlikte** yazılır |
| kapsamı sessizce daraltma | madde yapılmamış ama "yapıldı" | `discards.txt` zorunlu: elenen her madde sebebiyle yazılır |
| yeşil için testi kaldırma | `make test` sayısı **düşmüş** | her turun kabulünde "test sayısı düşmedi" iddiası var |

**Hakem ayrı oturum.** Bir turun kabulünü değerlendiren ajan, o turu uygulayan
ajan olamaz. Uygulayan `accept.sh`'ı koşturur ve çıktısını yazar; **geçti/kaldı
kararını** temiz bir oturum verir ve o oturum brief'i görmez, yalnız çıktıyı ve
kabul maddelerini görür.

### 6.3 Hedef kontrolü: her turun başında ve sonunda

Compound error inşa sürecinde de olur: bir tur yanlış bir varsayım kurar, sonraki
turlar üstüne inşa eder, beşinci turda kimse neden orada olduğunu bilmez.

Her tur **iki kontrolle** çerçevelenir. İkisi de `CLAIM.md` içinde, üç cümleyi
geçmez:

**Açılış kontrolü (tur başında yazılır):**
- Ürünün cümlesi hâlâ §0'daki mi? Değiştiyse **dur**, tur başlamaz.
- Bu tur o cümleye hangi somut adımı ekliyor?
- Bir önceki turun `accept.sh`'ı temiz checkout'ta geçiyor mu? Geçmiyorsa
  `BLOCKED.md` yazılır ve tur başlamaz.

**Kapanış kontrolü (tur sonunda yazılır):**
- Kabul maddelerinin kaçı yeşil, kaçı kırmızı? Kırmızı varsa **kısmi** yazılır,
  "tamamlandı" yazılmaz.
- Bu turda kapsam dışına çıkıldı mı? Çıkıldıysa ne, neden.
- Bir sonraki tur için değişen bir varsayım var mı?

### 6.4 Kayma sayacı

`reports/DRIFT.md` tek dosya, her turun sonunda **bir satır** eklenir:

```
T{n} | tarih | kabul: X yeşil / Y kırmızı | kapsam dışı: yok|<ne> | varsayım değişti: yok|<ne>
```

Üç kırmızı bayrak, herhangi biri görülürse koşu **durur** ve yeniden
düşünülür:

1. Üst üste iki turda "kapsam dışı" dolu → yön kaymış.
2. Bir turun kabulü kısmi kaldı ve sonraki tur yine de başladı → kapı delinmiş.
3. `make test` sayısı bir turda düştü → yeşil satın alınmış.

### 6.5 Koşunun uzunluğu

Bu sekiz tur ay ölçeğinde bir iştir, hafta değil. T1 ve T2 hizalama;
gerçek motor T3–T6 arasında ve zor kısım orası. Takvim verilmez, **kapı verilir**:
bir tur, kabulü yeşil olmadan bitmiş sayılmaz, ve bir sonraki tur onsuz başlamaz.

---

# TURLAR

---

<!-- hedef kontrolü (§6.3): ürün ne olduğunu söylüyor mu -->
## T1 — proje ne olduğunu söyler

Bugün rabadon üç ayrı şey iddia ediyor: reliability runtime, guardrail, sandbox.
Hiçbiri §0'daki cümle değil. Kullanıcı ne aldığını bilmiyor.

**Kanonik cümle** (README ve package.json için, İngilizce):

> rabadon catches your coding agent's error before it compounds, and fixes it.

Devamı şu üç bilgiyi taşır: canlı oturumun içinde çalışır; hatayı onu yapan
hamlede görür; ajana kendi göremediğini verir (gerçekte ne kırıldı, bu deneme
çalışan son denemeden nerede ayrılıyor) ve **tamiri ajanın kendisi yapar**.
Kapanış: watchdog değil, gate değil, dashboard değil. Durdurmak ürün değil,
düzelmek ürün.

**Kapsam, beş iş.**

1. `README.md` ilk paragrafı kanonik cümle olur.
   "Supervise your coding agent..." düşer.
2. `package.json` `description` hizalanır. `keywords`ten `guardrails`,
   `sandbox`, `pipeline` düşer; `compound-error`, `agent-recovery` girer.
3. GitHub repo description ve topics aynı hizaya gelir.
4. **Repair sayısı tek olur.** Bugün çelişkili:
   `BENCHMARK.md` satır 160, 179, 216 sıfır diyor; satır 186 iki diyor.
   `README.md` satır 52 ve 64 sıfır gösteriyor; satır 72 iki diyor.
   Doğru sayı **2**, ve niteliği her yerde aynı yazılır: ikisi de **planlanmış**
   kırılma üzerinde, expressjs/express @ a3714473, o projenin kendi mocha süiti
   hakem, 91 test dosyası kilitli. **Planlanmamış kırılmada 0.**
   Sayı ledger'dan okunur, elle yazılmaz; `bench/reproduce.sh` üretir.
5. `README.md`'deki `npm i -g rabadon` düşer (paket yayınlanmamış, Status
   bölümü zaten bunu söylüyor, kurulum bloğu tersini söylüyor). Yerine
   kaynaktan kurulum. Status'teki "portable `npm i -g` install with prebuilt
   binaries" ibaresi de düşer. (Yayın T8'de.)

**Durma.** Mevcut bir test kırılıyorsa dur. Silme, zayıflatma.

**Kabul.** `reports/T1/accept.sh`, exit 0. Beş iddia:
1. `BENCHMARK.md` + `README.md` içinde repair sayısı geçen her satır **aynı**
   değeri gösteriyor
2. README'de yayınlanmamış kurulum komutu yok
3. "Supervise your coding agent" hiçbir yerde kalmamış
4. Kanonik cümle hem `README.md` hem `package.json` içinde var; `guardrails`
   keyword'ü yok, `compound-error` var
5. `make test` yeşil

Bitince `reports/T1/CLAIM.md` ve `reports/T1/discards.txt` yazılır.

---

<!-- hedef kontrolü (§6.3): yüzey daraldı mı, hiçbir kod silinmedi mi -->
## T2 — yüzey daralır

25 CLI verb'ü var: init, on, off, budget, lens, usage, report, trace, drift,
drill, audit, replay, exec, do, loop, repair, verify, net, truth, export, lint,
doctor, remove, watch, serve.

Bu bir güvensizlik belirtisi. Çok özellik koyan, tek özelliğinin yeterince iyi
olduğuna inanmıyordur. Ve her verb bir bakım yüzeyi, bir dokümantasyon borcu,
bir kullanıcı kafa karışıklığıdır.

**Kapsam.** Yüzey **beşe** iner:

| verb | ne yapar |
|---|---|
| `rabadon init` | kurar, hook'ları bağlar |
| `rabadon on` / `off` | proje bazında açar kapatır |
| `rabadon usage` | bu hafta ne oldu, tek ekran |
| `rabadon repair` | kontrollü deneyi elle çalıştırır |
| `rabadon doctor` | kurulum doğru mu |

Kalanların hepsi **silinmez**, `rabadon dev <verb>` altına iner. Kod duruyor,
testler duruyor, ama ana yüzeyde görünmüyor. Geri almak tek satır.

`loop.cpp` → `pipeline.cpp`, binary `rabadon-pipeline`. Bu bir plan koşturucu,
döngü tespitçisi değil; bugünkü adı her okuyucuyu yanıltıyor ve T3'ten sonra
gerçek döngü motoruyla çakışacak.

`sandbox.cpp` ana yolun dışına alınır. Anthropic 22 Ekim 2025'te Claude Code'a
OS düzeyi sandbox (Seatbelt/bubblewrap) gönderdi ve kendi ölçümüyle izin
sorularını %84 azalttı. Aynı mekanizmayı ikinci kez taşımanın kullanıcıya
faydası yok. Kod silinmez, `dev` altına iner.

`serve.cpp` aynı şekilde `dev` altına. Takım sunucusunun bugün alıcısı yok ve
tek kişilik kullanıcıya hiçbir şey vermiyor. Alıcı çıkarsa geri gelir.

**Durma.** Hiçbir kod silinmez. Her taşınan verb için `dev` altında çalıştığını
ispatlayan bir test kalır. Bir verb'ün testi kırılıyorsa dur.

**Kabul.** `reports/T2/accept.sh`:
- `rabadon --help` beş verb gösteriyor
- Taşınan 20 verb'ün her biri `rabadon dev <verb>` ile hâlâ çalışıyor
- `make test` sayısı **düşmedi**
- `rabadon-pipeline` var, `rabadon-loop` yok

---

<!-- hedef kontrolü (§6.3): kayıt doğru mu, karar yolu değişmedi mi -->
## T3 — hamle kaydı ve sonuç alanı

**Bu turda tespit yok, blok yok, enjeksiyon yok. Sadece kayıt.**

Sebebi: kayıt doğru olmadan üstüne kurulan hiçbir tespit doğrulanamaz, ve yanlış
pozitifin nereden geldiği asla bulunamaz. Yasa 1'in altyapısı budur.

**Kapsam.** `Sess` içine halka tampon:

```
struct Move {
  int       seq;          // oturum içi sıra, hiç sıfırlanmaz
  long long ts;
  string    tool;         // Bash | Edit | Write | MultiEdit
  string    path;         // repo köküne göreceli, boş olabilir
  string    sig;          // normalize imza, sha256 ilk 16 hex
  string    raw;          // 200 karaktere kırpık, teşhis metni için
  int       claimed_rc;   // -1 bilinmiyor
  string    err_sig;      // hata imzası, boş = hata yok
  int8_t    suite;        // -1 bilinmiyor, 0 kırmızı, 1 yeşil
};
```

Son 200 hamle. Serileştirmede `raw` sadece son 50 için yazılır; eski hamlelerin
imzası lazım, metni değil. ~300 bayt × 200 ≈ 60 KB.

`claimed_rc` ismi bilerek böyle. PostToolUse çıkış kodu vermiyor, `tool_response`
bir string; bu bir **iddia** ve iddia olduğu isimde durur. Repoda bu ayrım zaten
var (`Sess.lastTestPass` yorumu), korunur.

Kademe 0 normalizasyon, yeni bağımlılık yok, mevcut `sha256.h`:
- Bash: whitespace daralt, mutlak yolları repo köküne göreceleştir, geçici dizin
  adlarını `<tmp>` ile maskele, **sayıları koru** (port anlamlıdır).
- Edit/Write: `path` + `new_string`; girinti daralt, string literalleri `<str>`
  ile maskele, sayıları koru.

`err_sig`: `tool_response` içinden hata satırını çek, dosya yollarını ve satır
numaralarını maskele, hash'le. Crash bucketing'in (Windows Error Reporting,
ClusterFuzz) yaptığı iş; kanıtlanmış ve ucuz.

**Durma.** Gate'in mevcut karar yolu **tek satır değişmez**. Kayıt yan etkisizdir.

**Kabul.** `native/moves_test.sh`, en az 6 iddia:
1. Aynı komut iki farklı whitespace ile → aynı `sig`
2. Farklı komut → farklı `sig`
3. `/tmp/abc123/x` ve `/tmp/def456/x` → aynı `sig`
4. `--port 3000` ve `--port 8080` → **farklı** `sig`
5. Bash hamlesi + PostToolUse → aynı `seq`'in `claimed_rc` alanı dolu
6. 200 aşıldığında en eski düşer, `seq` artmaya devam eder

Ve: kayıt açıkken/kapalıyken gate çıkış kodları **bayt bayt aynı**.

---

<!-- hedef kontrolü (§6.3): sinyal ölçülüyor mu, hâlâ sessiz mi -->
## T4 — dört sinyal, sessiz mod

**Bu turda da blok yok, enjeksiyon yok.** Sinyal hesaplanır, spool'a yazılır,
kullanıcı hiçbir şey görmez.

Amaç: **yanlış pozitif oranını ölçmek.** Yasa 1 gereği ölçülmemiş bir sinyal
asla enforce edilmez. SWE-agent'ı geri adım attıran şey bu ölçümün yokluğuydu.

**Kapsam.** Dört dedektör, hepsi `moves` üzerinde, hepsi O(pencere):

1. **tekrar** — `sig` son 20 hamlede görüldü mü. Eşik **bir**: aynı imza
   ikinci kez görüldüğü anda sinyal. Bugünkü "üçüncü kez" eşiği ürünün vaadini
   ihlal ediyor, o noktada token yanmış ve hata ağaca girmiştir.
2. **salınım** — son 6 hamlede iki `sig` dönüşümlü mü. Bugün tamamen kör olan
   desen; OpenHands'in ayrı bir kalıp olarak tuttuğu şey.
3. **kök taşıma** — aynı `err_sig` **farklı** `sig`'lerden sonra tekrar çıkıyor
   mu. Projenin gerçek yeni kısmı budur: hamleler yeni, hata aynı kökten.
   Tekrar tespiti bunu yakalamaz; literatürdeki hiçbir üretim aracı da
   yakalamıyor. Eşik yine **bir**: aynı kök ikinci kez göründüğü anda sinyal.
4. **kapsam kayması** — `touchedDirs` oturum hedefine göre büyüyor mu.
   Alan zaten var, kullanılmıyor.

Her tetiklenme spool'a `SIGNAL` olarak yazılır: ad, güven, tetikleyen `seq`'ler.

**Durma.** Sinyal hiçbir çıkış kodunu değiştirmez. `permissionDecision`
üretilmez. stdout'a **tek bayt yazılmaz** (PostToolUse'un başarıda stdout'a
yazması token yakıyordu; o hata tekrar edilmez).

**Kabul.** `reports/T4/accept.sh`:
- Dört sinyalin her biri için sentetik oturum, sinyal ateşliyor
- Dört temiz oturum, hiçbiri ateşlemiyor
- Sinyalli/sinyalsiz koşuda gate çıkış kodları bayt bayt aynı
- Spool'daki `SIGNAL` satırları zincire dahil, `rabadon audit` yeşil

---

<!-- hedef kontrolü (§6.3): semantik eşleşme bütçede mi -->
## T5 — semantik imza

**Kapsam.** Kademe 0 tam eşitliktir; ajan aynı düzeltmeyi farklı yazınca kaçırır.
Kaskad kurulur: pahalı olan sadece aday varken çalışır.

Kademe 1, Edit için: `new_string` üzerinden token dizisi, tanımlayıcıları yerel
olarak yeniden adlandır (değişken adı değişmiş ama yapı aynıysa yakalansın),
sonra **winnowing** ile k-gram parmak izi. MOSS'un tekniği, otuz yıllık, saf
C++ ile mikrosaniye ölçeğinde, bağımlılık gerektirmez.

Kaskad: kademe 0 hash eşleşirse iş bitti. Eşleşmezse kademe 1 parmak izi
örtüşmesi; eşik üstündeyse "semantik tekrar", güven alanı kesirli.

**Kademe 2 (AST / tree-sitter) bu turda yazılmaz.** Bağımlılık getirir ve
kademe 1'in yeterli olup olmadığı henüz ölçülmedi. T8'de yeniden değerlendirilir.

**Durma.** Hâlâ sessiz mod. Kademe 1, kademe 0'ın verdiği hiçbir kararı
**değiştiremez**, sadece ekler.

**Kabul.**
- `x = a + b` ve `x  =  a+b` → tekrar
- `foo(x)` ve `bar(y)` (aynı yapı, farklı isim) → tekrar
- Gerçekten farklı iki düzeltme → tekrar **değil**
- Kademe 1'in eklediği gecikme 34 fixture üzerinde **medyan 245 µs + 500 µs
  altında**, `gate_bench.sh` ile ölçülür, tahmin edilmez

---

<!-- hedef kontrolü (§6.3): kullanıcı ürünü ilk kez görüyor mu -->
## T6 — enjeksiyon: katman iyileştirici olur

**Ürün bu turda ürün olur.** Öncekiler altyapıydı.

**Kapsam.** Sinyal ateşlediğinde ajana bir metin gider ve rabadon çekilir.
Düzeltmeyi ajan yazar; rabadon tek satır kod üretmez, bir LLM çağırmaz.
Metnin şekli Yasa 2 ve Yasa 3 tarafından belirlenir.

Yazılacak:
- hangi **dosya** bağlamında çalışıldığı
- önceki denemede **neyin kırıldığı** (`err_sig`'in okunabilir hali)
- **karşıtlık**: "şu hamleden sonra süit yeşildi, bu hamleden sonra kırmızı,
  fark bu"
- kaçıncı deneme olduğu

Yazılmayacak:
- satır numarası (Yasa 2: performansı düşürüyor)
- ajanın ne yapması gerektiği (öneri değil, bilgi)
- 400 karakteri aşan hiçbir şey

Üç seviye, sadece biri durdurur:
- **kesin** → blok. Bugün zaten var (test-tamper, tam eşit komut). Değişmez.
- **olası** → enjeksiyon, blok yok. Semantik tekrar, salınım, kök taşıma.
- **zayıf** → sadece ledger. Ajan görmez.

Terfi merdiveni: bir kural, T4'ün topladığı gerçek kullanım verisinde ölçülmüş
yanlış pozitif oranı **%10 altına inmeden** üst seviyeye geçmez.

**Durma.** Enjeksiyon PreToolUse'un `additionalContext` yolundan gider, stdout'a
değil. Aynı sinyal aynı oturumda **en fazla iki kez** enjekte edilir; üçüncüsü
ledger'a düşer. Tekrar eden uyarı, uyarı değil gürültüdür.

**Fatura bu turda doğar.** Enjeksiyon görünmez, fatura onu görünür kılar;
ikisi ayrı tur olamaz. Oturum sonunda terminale iki cümle düşer:

> Bu oturumda N birikme kesildi. M'sinde hata bir daha çıkmadı.

Yasa 5 burada bağlayıcıdır: **tahmini token/dolar rakamı yazılmaz.** İki sayı da
ledger'dan okunur. Tutmayan müdahaleler (N eksi M) `rabadon usage` ile
görülebilir; kendi başarısızlığını gizleyen fatura kabul edilmez (§4).

**Kabul.** `reports/T6/accept.sh`:
- Sentetik kök-taşıma oturumunda enjeksiyon metni üretiliyor
- Oturum sonunda fatura basılıyor, iki sayı da ledger'dan okunuyor
- Faturada tahmini token/dolar rakamı **yok** (grep ile ispat)
- Tutmayan müdahale `rabadon usage` çıktısında görünüyor
- Metin satır numarası içermiyor (grep ile ispat)
- Metin 400 karakteri aşmıyor
- Aynı sinyal üçüncü kez enjekte edilmiyor
- Enjeksiyon açık/kapalı gate çıkış kodları aynı (enjeksiyon bloklamaz)

---

<!-- hedef kontrolü (§6.3): onarım doğru anda mı tetikleniyor -->
## T7 — onarım tur içine iner

repair.cpp bugün oturum seviyesinde: klon, hash-kilit, kopyada öneri, aynı
kontrolle doğrula. Kontrollü deney gerçek ve çalışıyor. Ama saniyeler-dakikalar
sürüyor, ve gerçek kırılmada tutulmuş onarım sayısı sıfır.

Sebebi tasarım hatası değil, **tetikleme zamanı**: kullanıcı `rabadon repair`
yazana kadar hata çoktan birikmiş oluyor.

**Kapsam.**
T4'ün kök-taşıma sinyali onarımın tetikleyicisi olur. Sinyal ateşlediğinde
kullanıcıya tek satır düşer: *"aynı hata ikinci kez farklı yoldan çıktı,
kontrollü deneyi çalıştırayım mı?"* Onay verirse repair.cpp koşar.

Sessiz otomatik onarım **yok**. Yasa 4 gereği: onarım ancak geri bildirim
kalitesi yükselince kazanç veriyor, ve kullanıcının haberi olmadan token
harcamak ürünü sildirir.

Ayrıca repair.cpp'nin önericiye verdiği metin Yasa 2'ye hizalanır: bugün
arbiter'ın ham çıktısını veriyor, dosya bağlamı vermiyor. Dosya bağlamı eklenir
(15-17 kat), satır düzeyi eklenmez.

**Kim yazar.** Kopyada koşan proposer kullanıcının kendi ajanıdır
(`RABADON_PROPOSER`, varsayılan `claude -p`). rabadon yama üretmez; repoyu
kopyalar, test dosyalarını hash-kilitler, ajanı kopyada koşturur ve sonucu aynı
deterministik kontrolle doğrular. İşçi ajan, hakem rabadon.

**Durma.** Kullanıcı ağacı asla kendiliğinden değişmez. Bugünkü propose-and-hold
davranışı korunur: yama `.rabadon/repair-<ts>.patch` olarak tutulur, insan uygular.

**Kabul.** `reports/T7/accept.sh`:
- Kök-taşıma sinyali onarım teklifini üretiyor
- Onay olmadan hiçbir proposer çağrısı yapılmıyor (ledger'la ispat)
- Önericiye giden metinde dosya bağlamı var, satır numarası yok
- Kullanıcı ağacındaki dosyalar koşu boyunca değişmemiş (hash ile ispat)

---

<!-- hedef kontrolü (§6.3): iddia ölçüldü mü -->
## T8 — hız, iki kollu koşu, yayın

**Kapsam, üç parça.**

**Hız.** Bugün 3.14 ms'in 2.9 ms'i süreç başlatma. Kalıcı daemon + ince istemci
ile 245 µs'e iner; T5'in kademe 1'i üstüne binse bile bugünkünden hızlı olur.
`rabadon-gated`, unix socket, istemci ~50 satır. Daemon yoksa istemci **bugünkü
yola düşer** (fail-open değil, fail-same).

**Kanıt.** İki kollu koşu **bir kez, senin makinende, senin paranla** yapılır.
Kullanıcı asla iki kol koşturmaz; kimse aynı işi iki kez ödemez. Çıkan oran
faturanın arkasındaki teminattır: T6'nın faturası sayar, bu koşu o sayıların
neye karşılık geldiğini bir kez ölçer. Ancak bu koşudan sonra faturaya kaynağı
gösterilen bir tahmin eklenebilir ("40 görevlik açık koşuda ölçülen orana göre",
ham veri repoda).

Kurulum: aynı görev seti, A kolu ajan yalnız, B kolu ajan + birikme motoru.
Harness sıfırdan yazılmaz; SWE-smith veya terminal-bench yeniden
kullanılır. Dört sayı: gerçek fix oranı (held-out testle, ajanın kendi testiyle
değil), harcanan token, insan müdahalesi, yanlış pozitif oranı.
Ham JSONL `reports/T8/` altına, özet değil.

**Yayın.** npm paketi çıkar. Dört platform binary'si zaten hazır. README'deki
kurulum komutu ilk kez doğru olur.

**Kabul.** `reports/T8/accept.sh`:
- Daemon açıkken medyan < 1 ms
- Daemon kapalıyken davranış bugünküyle bayt bayt aynı
- İki kolun ham verisi mevcut ve `bench/reproduce.sh` ile yeniden üretilebilir
- `npm view rabadon version` yayınlanmış sürümü döndürüyor

---

## Yanlışlanma koşulu

T8 biterse ve B kolu A koluna göre **ne gerçek fix oranında ne net token'da**
gerçek bir iyileşme göstermiyorsa, enjeksiyon tezi yanlıştır.

O noktada birikme motoru sessiz moda geri döner ve ürün konumu yeniden düşünülür.

Bu koşul buraya **bugün** yazıldı, sonuç görüldükten sonra değil. Yanlışlanamayan
proje sonsuza kadar sürer, çünkü hiçbir zaman yanlış çıkmaz.

---

## Bu turlarda yapılmayacaklar

- kademe 2 / AST / tree-sitter (T8 sonrası, ölçüm olmadan değil)
- embedding, model çağrısı, LLM yargıç (bütçe dışı, ve yargıcın kendisi yanlış
  pozitif kaynağı: konum/uzunluk/kendini kayırma yanlılıkları)
- yeni CLI verb'ü (T2 beşe indiriyor, geri şişirilmez)
- OTLP, dashboard, UI genişletmesi
- README'de ölçülmemiş tek bir sayı

---

## Neden bu sıra

T1 önce, çünkü ne olduğunu söylemeyen ürün hiçbir turda değerlendirilemez.
T2 önce, çünkü 25 verb'lük yüzeyde yeni bir motor eklemek bakım borcunu
katlar; daraltmadan genişletme yapılmaz.
T3 olmadan T4 doğrulanamaz: kayıt yoksa sinyal test edilemez.
T4 olmadan T6 yapılamaz: yanlış pozitif ölçülmeden enforce etmek Yasa 1'in
ihlalidir, ve o ihlal SWE-agent'a semantik tespiti terk ettirdi.
T5, T6'dan önce gelir çünkü tam eşitlikle enjekte edilecek sinyal zaten bugün
bloklanıyor; yeni bir şey söylemek için semantik lazım.
T7, T4'ün sinyaline bağımlı: onarımın tetikleyicisi orada doğuyor.
T8 en sona kalır çünkü hızlandırma, doğru şeyi yaptığın kanıtlanmadan yapılan
optimizasyondur; ve yayın, ürün ürün olmadan yapılan gürültüdür.
