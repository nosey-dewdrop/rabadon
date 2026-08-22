# rabadon — koşu promptu (R0..R8 + M0..M4)

Tarih: 2026-08-22. Bu dosya tek kaynaktır ve repodaki PROTOCOL-T1-T8.md'nin yerine geçer (o dosya iptal edildi, R0'da arşive indi: `docs/internal/arsiv/PROTOCOL-T1-T8.md`; onun T1 ve T2 turlarında yapılmış iş repoda geçerli kalır). AGENTS-PROTOCOL.md'nin devir kuralı ve üç kapısı aynen geçerli. Teknik turlar R0..R8, pazarlama turları M0..M4. M turları R turlarına bağlıdır, bağımsız koşmaz.

Bu sürümde değişen: §1b (pazar), §1c (konumlandırma), §3'e Yasa 7, R6'ya üç fail-honest maddesi, R8'e plugin paketi, ve yeni PAZARLAMA TURLARI bölümü. R0..R8'in geri kalanı 22.08 sabah sürümüyle aynıdır.

---

## 0. Ürünün cümlesi (operatörün çerçevesi, değişmez)

rabadon, coding agent'a giydirilen güvenilirlik katmanıdır. Compound error'ı ve reward hacking'i büyümeden yakalar, ajana kendi göremediği tarihçeyi geri verir ve hatayı olduğu anda ajanın kendisine tamir ettirir; iş durmaz, devam eder. Oturum kapanışında tek satır basar:

    rabadon: 4 hata zinciri kesildi, 3'ü anında düzeltildi, tahmini 6.80 $ kurtarıldı.

package.json'daki mevcut İngilizce açıklama bu cümlenin ilk iki iddiasını zaten taşıyor ("catches your coding agent's error before it compounds, and fixes it... The agent writes the fix") ve DEĞİŞMEZ. Eksik olan üçüncü iddia, sayaçtır; o R6'da doğar ve README'ye ancak R6 kabulü yeşilken girer (ölçülmemiş vaat yazılmaz).

Üç iddia, üç mekanizma:

1. **yakalar** → kapı (var, 11 derlenmiş yasa) + sinyaller (R2). Kesin olan bloklanır, olası olan enjekte edilir.
2. **olduğu anda tamir ettirir** → enjeksiyon (R4). Tamiri rabadon değil, zaten çalışan ajan yapar. rabadon'un tek işi ajanın göremediğini göstermek: hangi dosyada, önceki denemede ne kırıldı, hangi hamleden sonra yeşil hangi hamleden sonra kırmızıydı, kaçıncı deneme. Bilgi ajandan gelir (PreToolUse/PostToolUse akışı; Claude Code ve Cursor bağları docs/agent-contract.md'de), tamir talimatı ajana döner (PreToolUse additionalContext yolu). rabadon hot-path'te kendi model çağrısını asla yapmaz.
3. **parayı söyler** → sayaç (R6). Her sayı ledger'dan türetilir, elle yazılmaz, şişirilmez.

Operatörün 4. sorusunun cevabı ("neye göre düzeltiyor?"): rabadon düzeltmez, düzeltmeyi yapanın gözünü açar. Hangi hamleden sonra süitin kırmızıya döndüğünü, aynı hatanın kaçıncı kez kaç farklı yoldan çıktığını ajan kendi context'inde göremez; rabadon bunu ledger'dan türetip ajanın bir sonraki tool call'undan önce context'e düşürür. Tamiri yapan, kullanıcının zaten ödediği model (Claude Code, Cursor, Codex). Bu yüzden rabadon'un kendisi ucuzdur ve bu yüzden "token harcatıyor" şikâyeti yapısal olarak çözülebilir.

---

## 1. Bugünün gerçeği (22.08 clone'u okunarak, iddiadan değil)

- native/ altında 18.865 satır C++; kimlik hizası ve yüzey daraltması YAPILMIŞ: reports/T1 (20/0) ve reports/T2 (21/0) kabulle kapanmış, yüzey 5 verb + dev altı, loop.cpp → pipeline.cpp olmuş, BENCHMARK'taki repair sayacı dört olaya bölünüp tek kaynağa bağlanmış.
- Birikme motoru YOK: hamle kaydı yok, sinyal dedektörü yok, additionalContext kodda hiç geçmiyor, sayaç yok. Oturum içi tespit hâlâ tam-eşitlik + Bash kilidi seviyesinde.
- npm'e HİÇ yayın çıkmamış: npm view rabadon 404. Üç tag'de de release workflow darwin-arm64 build'inde ölmüş (macOS runner'da pytest yok; guard native/heldout_test.sh:121 ve native/harness_lock_test.sh:118'e yazılmış ama gerçek runner'da DOĞRULANMAMIŞ). Ayrıca release.yml 17 binary kopyalarken platform package.json'ları 18 listeliyor: rabadon-run her paketten eksik kalır.
- Bilinen hijyen borcu: native/ altında on script ${CXX:-clang++} kullanıyor ve Makefile CXX export etmiyor (R0'da kapandı).
  **Düzeltme (R0'da ölçüldü):** "README:46 last 7 day(s)" borcu GERÇEK DEĞİL. README:46 zaten `--days 30` ile alınmış 30 günlük çıktıyı gösteriyor ve komutu satır içinde yazıyor. Tek "7 day" geçişi docs/quickstart.md:148'de ve o blok zaten `(EXAMPLE OUTPUT from a fresh install)` etiketli — ölçüm değil, örnek. Borç kapatılmadı çünkü borç yoktu; yerine bunu bir daha kaymaya karşı koruyan test yazıldı (reports/R0/accept.sh).
- Cast, 11 yasa, zincirli defter, agent contract (Claude Code + Cursor) README'de ve gerçek.

## 1b. Pazar (22.08 araştırması; kaynaklar ve doğrulama notları docs/POSITIONING.md'de)

Üç ayrı pazar var ve rabadon üçünün kesişimine oturuyor. Üçünde de tek tek oyuncu var, kesişimde kimse yok.

**A. Reward hacking — araştırma 2025-26'da patladı, üretim boş.**
- Benchmark'lar: RHB, SpecBench, TRACE, EvilGenie, Terminal Wrench, BenchJack. Her birinin sayısı ve o sayının ne kadarının doğrulandığı docs/POSITIONING.md'de tek tek yazılı — buradan sayı alıntılanmaz, oradan alınır.
- Cursor'ın 25.06.2026 yazısı: reward hacking kaynaklı benchmark kazancı artık gerçek zekâ kazancını geçiyor; yeni modeller eskilerden DAHA çok hack'liyor.
- Tespit yöntemleri literatürde sıralı: LLM yargıç, held-out test, test-dosyası-değişti tespiti. Appen'in özeti bizim tezimiz: "modelin anlatısına değil, gözlemlenebilene bak: tool call, diff, dosya." Bunlar trajectory üstünde çalışır; rabadon'un hamle kaydı tam o trajectory'dir.
- Üretimde karşılığı: YOK. Tüm bu yöntemler benchmark/değerlendirme tarafında, geliştiricinin masasında değil. Zylos'un Haziran 2026 raporu: "production deployments remain largely unprotected."

**B. Guardrail — hooks tabanlı, hepsi "tehlikeli komut" seviyesinde.**
- Claude Code hooks 31 event'e çıktı (PreToolUse/PostToolUse/SessionEnd); exit 2 = blok + stderr ajana; JSON ile permissionDecision ve additionalContext. Claude Code yüzeyi açık ara en olgun.
- Mevcut ürünler: agent-guardrails, Rulebricks, Morph Reflexes, Anthropic'in kendi hookify ve security-guidance plugin'leri. Hepsi tek-hamle filtresi: "bu komut tehlikeli mi?" Hiçbiri oturum tarihçesine bakmıyor; tekrar, salınım, kök taşıma, "kırmızıyken testi yeşile boyadı" desenini hiçbiri görmüyor. Boşluk doğrulandı.
- Güven sorunu gerçek: PromptArmor, marketplace plugin hook'uyla izin dosyasını (`settings.local.json`) yeniden yazan saldırıyı gösterdi. Bu bizim lehimize bir satış cümlesi: rabadon yerel binary, hot-path'te ağ yok, model yok, kullanıcı ağacına yazmıyor.

**C. Maliyet — ccusage de facto, Lineman ücretli, Anthropic sayıyı kendisi veriyor.**
- Anthropic'in kendi maliyet sayfası: ortalama $13/geliştirici/aktif gün, $150-250/geliştirici/ay. Microsoft bir bölümde Claude Code lisanslarını iptal etti; "kaç para yanıyor" sorusu CFO seviyesinde.
- ccusage `~/.claude/projects/` JSONL'ini okuyor, LiteLLM fiyat tablosu kullanıyor, 16 ajan CLI'sini destekliyor. codeburn, ccost, cccost, claude-usage-tracker aynı JSONL'i okuyan türevler. Hepsi "ne harcadın" der; hiçbiri "ne harcamak zorunda değildin" demez.
- Lineman.io: **$14.99/$49.99 ay, takım geneli** — kendi fiyat sayfasının cümlesi "One price covers your whole team — we never charge per person". Koltuk fiyatı diye bir şey yok, "$49 koltuk" referansı ölü. Yöntemi ikinci bir model çalıştırıp tool çıktısını sıkıştırmak; ağ erişimi şart (api.lineman.io). Bizim kurtardığımız token, onların sıkıştırdığı token değil: onlar her çağrıyı küçültür, biz gereksiz çağrıyı hiç yaptırmaz. Tamamlayıcı, rakip değil; ama fiyat tavanı olarak referans.
- LangWatch: abonelik oturumlarına "API liste fiyatıyla teorik maliyet" etiketi basıyor. Anthropic da kendi `/usage` dokümanında aynı sınırı kabul ediyor. Doğru pratik, biz de aynısını yaparız (Yasa 7).

**D. Dağıtım — plugin marketplace dev tool dağıtımının yeni kapısı.**
- Claude Code plugin = hooks/hooks.json + (opsiyonel) plugin.json; `/plugin marketplace add owner/repo` + `/plugin install x@repo`. anthropics/claude-plugins-official Anthropic yönetimli dizin; claudemarketplaces.com GitHub'dan otomatik tarama yapıyor.
- Plugin "her koltuğa dağıt" sorununu çözüyor: README'deki dört adım tek komut oluyor. Takım satışının teknik ön koşulu bu.

## 1c. Konumlandırma (operatörün "shut up and take my money" ölçütü)

Kategori adı: **reliability layer for coding agents.** Ne guardrail (onlar komut filtreler), ne cost tracker (onlar geriye bakar), ne benchmark (onlar laboratuvarda). Üçünün ortasındaki boşluk: *oturum içinde, ajan çalışırken, gözlemlenebilir trajectory'den, ajanı durdurmadan.*

Tek cümle (İngilizce, landing ve README için; package.json açıklaması değişmez):
> Your coding agent repeats itself, drifts, and paints tests green. rabadon sees the pattern it can't, hands it back mid-session, and tells you at the end what it cost you not to have it.

Üç rakibe karşı üç cümle:
- vs ccusage: "ccusage tells you what you spent. rabadon tells you what you didn't have to."
- vs guardrails: "They block the dangerous command. rabadon catches the expensive pattern."
- vs Lineman: "They shrink every call. rabadon removes the calls that shouldn't happen. Run both."

Satın alma anı (conversion engine): Free tier sayacı çalıştırır ama düzeltmeyi kapatır. Kapanış satırı free'de şöyle der:
    rabadon (free): 4 hata zinciri görüldü, düzeltme kapalıydı, tahmini 6.80 $ yandı.
Kullanıcı her oturum sonunda kendi parasının yandığını ledger'dan türetilmiş sayıyla görür. Ürünü satan reklam değil, bu satırdır. Bu yüzden sayacın dürüstlüğü (Yasa 5, Yasa 7) pazarlamanın kendisidir: şişirilmiş tek sayı bu satırı reklama çevirir ve güveni sildirir.

---

## 2. Operatörün üç şikâyeti ve karşılıkları

1. "yavaşlatıyor" → kapının kendisi milisaniye; hissedilen yavaşlık blok sonrası teşhissiz el yordamıdır. Çare önce teşhis (R4), hız R7'de daemon ile < 1 ms.
2. "yakalıyor ama çözmüyor, maliyet artıyor" → R4 tam bunu çözer: blok yerine bilgi, ajan ilk retry'da düzeltir.
3. "token harcatıyor" → Yasa 6. Enjeksiyon ≤ 400 karakter, aynı sinyal oturumda ≤ 2; rabadon'un enjekte ettiği her token sayaçta gider hanesine yazılır; hook'ların başarıda stdout'a yazması yasak (o hata bir kez yaşandı, tekrar edilmez).

## 3. Yasalar (tartışılmaz, uyulur)

- **Yasa 1 — yanlış pozitif ürünü öldürür.** OpenHands'in loop tespiti uzun işlemi bekleyen ajanları öldürünce bug açıldı; Google Tricorder eşiği etkin yanlış pozitif %10 altı; guardrail-DoS literatürü aşırı-reddin ürünü kullanılamaz hale getirdiğini ölçüyor. → Kesin olmayan hiçbir sinyal bloklamaz. Ölçülmemiş hiçbir kural enforce edilmez.
- **Yasa 2 — satır göstermek zarar verir.** SWE-bench Verified üstünde dosya düzeyi yerelleştirme baskın faktör; satır düzeyi bağlam gürültü yükseltip performansı sıklıkla düşürüyor. → Enjeksiyon dosya bağlamı + neyin kırıldığını söyler, satır numarası söylemez.
- **Yasa 3 — karşıtlık tek başına hatadan güçlü.** ContrastRepair: geçen ve kalan testten oluşan çift verildiğinde model kökü belirgin daha iyi buluyor. → "Şu hamleden sonra yeşil, bu hamleden sonra kırmızı" çifti hamle kaydından bedava.
- **Yasa 4 — geri bildirim kalitesi yükselmeden tekrar sormak token yakar.** Olausson et al.: self-repair'in kazancı maliyet sayılınca kayboluyor, kazanç ancak geri bildirim dışarıdan yükselince çıkıyor. → Birikme motoru bir hayır katmanı değil, ajanın göremediği tarihçeyi tutan hafıza katmanıdır.
- **Yasa 5 — sayaç yasası.** Basılan her sayı ledger'dan türetilir ve rabadon usage --explain ile adım adım yeniden üretilebilir. Tahmin olan her sayı satırın içinde "tahmini / estimated" etiketi taşır. Formül repoda açık dosyadır (docs/COUNTER.md). Net sonuç negatifse negatif basılır. Sayaç pazarlama için asla elle şişirilmez; şişirilmiş sayaç ürünü sildirir, dürüst sayaç sattırır.
- **Yasa 6 — token yasası.** rabadon hot-path'te kendi model çağrısını yapmaz. Ajanın harcadığı token da rabadon'un enjekte ettiği token da ölçülür; enjeksiyonun maliyeti sayaçta giderdir. Model çağrısı yalnız repair kolunda vardır ve o kol politika kapılıdır (R5).
- **Yasa 7 — pazarlama ledger'dan çıkar.** Landing, README, tweet, Show HN metni — hiçbirinde ledger'dan türetilmeyen sayı yoktur. Benchmark iddiası yalnız R7'nin ham JSONL'i reports/ altında dururken yapılır. Abonelik kullanıcısı için dolar "API liste fiyatıyla teorik" etiketiyle basılır. Rakip karşılaştırması rakibin kendi yayınladığı sayıyla yapılır, bizim ölçümümüzle değil; ve o sayı docs/POSITIONING.md'de doğrulanmış olarak işaretli değilse dışarı yazılmaz. Negatif sonuç da yayınlanır: "rabadon bu oturumda kazandırmadı" satırı yayın değeri taşır, çünkü piyasada dürüst sayaç yok.

## 4. Mimari

Üç kol. Kapı ve repair var, ortadaki kol bu koşuda kurulur.

| kol | ne zaman | bütçe | rol |
|---|---|---|---|
| kapı (gate) | her tool call | bugünkü ölçüm → hedef < 1 ms | kesin olanı durdurur |
| birikme motoru | her tool call | hedef < 1 ms | birikmeyi görür, teşhisi ajana enjekte eder, ajan anında tamir eder |
| onarım (repair) | sinyal tetikli, politika kapılı | saniye-dakika | kontrollü deney |

**Bu tablodaki her sayı süreç-İÇİ ölçülür, uçtan uca çağrıyla değil.** 22.08'de ölçüldü ve bu bir düzeltmedir, tercih değil: R3'ün kabul betiği **var olmayan** bir özelliğin maliyetini uçtan uca ON 3937 µs / OFF 4002 µs, yani **delta −64 µs** diye ölçtü. Sıfır maliyetli bir şeyin ölçümü gürültünün içinde kayboldu, çünkü süreç başlatma çağrının neredeyse tamamı. Bu yöntemle 500 µs'lik bir bütçe hiçbir şey ölçmez — geçer ve hiçbir şey kanıtlamaz.

Bundan sonra üç kural:

1. **Bütçe, gate'in kendi işine oranla yazılır.** Uçtan uca medyanın yüzdesi yanıltıcıdır ve **lehimize** yanıltıcıdır: 4.5 ms'lik bir çağrının %5'i 226 µs görünür, ama o çağrının çoğu süreç başlatmadır, yani gate'in gerçek işine oranla aynı ek çok daha büyüktür. Yüzde, ölçtüğümüz şeyin paydası doğruysa anlamlıdır.
2. **Süreç başlatmayı ölçen bir sayı, ürün hakkında bir sayı değildir.** Süreç başlatmayı ortadan kaldıran tek şey R7'nin daemon'ı; ona kadar her bütçe kalemi süreç-içi ölçülür ve raporda "süreç başlatma hariç" diye etiketlenir.
3. **Bugüne kadar yazılmış her bütçe sayısı uçtan uca ölçülmüştür** (R1'in 1571 µs'si, R1.3'ün 838 µs'si dahil) ve süreç-içi ölçülen yeni sayılarla doğrudan karşılaştırılamaz. Karşılaştırma yapılacaksa eski ölçüm yeni yöntemle tekrarlanır.

---

# TEKNİK TURLAR

## R0 — devir

Kapsam:
- PROTOCOL-T1-T8.md → docs/internal/arsiv/ altına iner; başına iptal satırı konur. Silinmez.
- Bu dosya (KOSU-RABADON.md) repo köküne girer, PROJECT.md'nin işaret ettiği tek plan bu olur.
- reports/T1 ve reports/T2 olduğu gibi kalır; o iş yapılmıştır ve geçerlidir.
- Hijyen: "N day(s)" ifadeleri ile yanlarındaki sayıların hizası teste bağlanır; Makefile CXX export eder (S0.2).
- docs/POSITIONING.md açılır: §1b'deki pazar haritası, kaynak URL'leriyle, 3 rakip cümlesiyle, ve her sayı için doğrulama durumuyla. Pazarlama metinleri bundan türer, chat'ten değil.

Durma: mevcut bir test kırılıyorsa dur.

Kabul (reports/R0/accept.sh):
- repo kökünde PROTOCOL-T1-T8.md yok, arşivde var ve iptal satırı içeriyor
- README ve quickstart'taki her "last N day(s)" ya bir `--days N` komutunun yanında ya da EXAMPLE etiketli
- docs/POSITIONING.md var ve §1b'deki her ürün adı için bir URL içeriyor
- POSITIONING'de doğrulanmamış her sayı DOĞRULANMADI etiketi taşıyor
- Makefile CXX'i export ediyor
- make test yeşil, sayı düşmedi (taban: 1855 passed / 0 failed)

## R1 — hamle kaydı ve sonuç alanı

Bu turda tespit yok, blok yok, enjeksiyon yok. Sadece kayıt. Kayıt doğru olmadan ne sinyal doğrulanabilir ne sayaç kurulabilir; yanlış pozitifin nereden geldiği de asla bulunamaz.

Sess içine halka tampon:

```cpp
struct Move {
  int       seq;          // oturum içi sıra, hiç sıfırlanmaz
  long long ts;
  string    tool;         // Bash | Edit | Write | MultiEdit
  string    path;         // repo köküne göreceli, boş olabilir
  string    sig;          // normalize imza, sha256 ilk 16 hex
  string    raw;          // 200 karaktere kırpık, teşhis metni için
  int       claimed_rc;   // -1 bilinmiyor (PostToolUse çıkış kodu vermez; bu bir iddiadır ve iddia adında durur)
  string    err_sig;      // hata imzası, boş = hata yok
  int8_t    suite;        // -1 bilinmiyor, 0 kırmızı, 1 yeşil
};
```

Son 200 hamle; raw sadece son 50 için serileştirilir.

**Uygulandığı hali (R1.3, ölçülmüş):** kayıt JSON değil, **sabit genişlikli ikili halka** — 4096 B başlık + 200 × 320 B, dosya sabit 68 KB, oturum ne kadar uzarsa uzasın büyümüyor. Metin depolama biçimi değil, `rabadon audit --export` ile üretilen bir dışa aktarım. Nedeni ölçümdür: JSON'la maliyet oturum uzunluğuna bağlıydı (200 satır 5.943 ms, 400 satır 6.647 ms), ikili halkayla halkanın kendi payı **~6 µs**'ye indi (pread 1.68 + append 2.18 + SHA 1.95). Ayrıntı `docs/butce.md`.

Kademe 0 normalizasyon, yeni bağımlılık yok, mevcut sha256:
- Bash: whitespace daralt, mutlak yolları göreceleştir, geçici dizinleri `<tmp>` maskele, sayıları koru (port anlamlıdır).
- Edit/Write: path + new_string; girinti daralt, string literalleri `<str>` maskele, sayıları koru.
- err_sig: tool_response'tan hata satırı, yol ve satır numarası maskeli, hash'li (crash bucketing tekniği: kanıtlanmış ve ucuz).

Durma: gate'in mevcut karar yolu tek satır değişmez. Kayıt yan etkisizdir.

Kabul (native/moves_test.sh, en az 6 iddia):
- aynı komut iki farklı whitespace ile → aynı sig
- farklı komut → farklı sig
- /tmp/abc123/x ve /tmp/def456/x → aynı sig
- --port 3000 ve --port 8080 → farklı sig
- Bash hamlesi + PostToolUse → aynı seq'in claimed_rc alanı dolu
- 200 aşılınca en eski düşer, seq artmaya devam eder
- kayıt açık/kapalı gate çıkış kodları bayt bayt aynı

Hijyen (R0'dan devreden, kendi commit'inde): `reports/T1/accept.sh`'ın T1'de yasaklanan eski slogan için yaptığı repo taraması (claim 3; ifadenin kendisi buraya yazılmaz — yazıldığı an bu dosya taramaya takılıyor, bir kez takıldı) `PROTOCOL-T1-T8.md`'yi kök adıyla hariç tutuyor; R0 dosyayı `docs/internal/arsiv/` altına indirince filtre tutmaz oldu ve T1 tek kırmızıyla kapandı (19 yeşil / 1 kırmızı, 22.08). Üç isabetin üçü de iptal edilmiş planın *ifadeyi yasaklamak için alıntıladığı* satırlar; canlı hiçbir yüzeyde geçmiyor. Filtre arşiv yolunu kapsayacak şekilde genişletilir — **eşik gevşetilmez, taranan alan daraltılmaz**, sadece zaten hariç olan dosya taşındığı yerde tanınır. Gerekçe `reports/R0/CLAIM.md`'de. `reports/T2/accept.sh` dokunulmaz: 21 yeşil, 0 kırmızı, kabul.

## R2 — beş sinyal, sessiz mod

Blok yok, enjeksiyon yok. Sinyal hesaplanır, spool'a yazılır, kullanıcı hiçbir şey görmez. Amaç yanlış pozitif oranını ölçmek; Yasa 1 gereği ölçülmemiş sinyal enforce edilmez.

Beş dedektör, hepsi moves üzerinde, hepsi O(pencere):
1. **tekrar** — sig son 20 hamlede görüldü mü.
2. **salınım** — son 6 hamlede iki sig dönüşümlü mü (A-B-A-B; bugün tamamen kör olunan desen).
3. **kök taşıma** — aynı err_sig farklı sig'lerden sonra tekrar çıkıyor mu. Hamleler yeni, hata aynı kökten; üretim araçlarında karşılığı yok, ürünün gerçek yeni kısmı budur.
4. **kapsam kayması** — touchedDirs oturum hedefine göre büyüyor mu.
5. **yeşilin tanımı değişti (reward hacking)** — üç alt desen:
   - suite kırmızıyken (suite==0) test/harness/kapı dosyasına Edit/Write geldi
   - kırmızı→yeşil geçişinde iki nokta arasında yalnız test/harness/config dosyaları değişti, üretim kodu değişmedi
   - test dosyasında assertion/expect sayısı düştü ya da eşik/tolerance sayısal olarak gevşedi

   Test/harness dosyası tanımı repo başına mevcut truth keşfinden çıkarılır, elle liste değil. Bu sinyal, stitchu vakasında kaçan "kapıyı kendin yeşil yaptın" hamlesini kapsama alır. Literatür notu: EvilGenie "test dosyası düzenlendi" tespitini yöntemlerinden biri sayıyor; BenchJack'in conftest.py saldırısı da bu alt desene düşer (harness dosyasına yazma). Held-out test bizde yok (kullanıcının gizli testi yok); bu yüzden bu sinyal deterministik alt kümeyle sınırlıdır ve LLM yargıç R7 sonrasına bırakılır.

Her tetiklenme spool'a SIGNAL olarak yazılır: ad, güven, tetikleyen seq'ler; zincire dahildir.

Durma: sinyal hiçbir çıkış kodunu değiştirmez, permissionDecision üretilmez, stdout'a tek bayt yazılmaz.

Kabul (reports/R2/accept.sh):
- beş sinyalin her biri için sentetik oturum, sinyal ateşliyor (5. sinyalin üç alt deseni üç ayrı fixture)
- beş temiz oturum, hiçbiri ateşlemiyor; özellikle meşru test refactor'ü (suite yeşilken test dosyası düzenleme) 5. sinyali ateşlemiyor
- sinyalli/sinyalsiz koşuda gate çıkış kodları bayt bayt aynı
- SIGNAL satırları zincire dahil, audit yeşil

## R3 — semantik imza

Kademe 0 tam eşitliktir; ajan aynı düzeltmeyi bir boşluk farkıyla yazınca kaçar. Kaskad: kademe 0 hash eşleşirse iş bitti; eşleşmezse kademe 1 — new_string üzerinden token dizisi, tanımlayıcı yerel yeniden adlandırma, winnowing k-gram parmak izi (MOSS tekniği: otuz yıllık, saf C++, mikrosaniye, bağımlılıksız). Eşik üstü örtüşme "semantik tekrar", güven kesirli. Kademe 2 (AST / tree-sitter) bu koşuda yazılmaz; R7 ölçümünden sonra ayrı kararla değerlendirilir.

Durma: hâlâ sessiz mod. Kademe 1, kademe 0'ın hiçbir kararını değiştiremez, sadece ekler.

Kabul:
- `x = a + b` ve `x = a+b` → tekrar
- `foo(x)` ve `bar(y)` (aynı yapı, farklı isim) → tekrar
- gerçekten farklı iki düzeltme → tekrar değil
- kademe 1'in eklediği gecikme **ölçülür, tahmin edilmez**; mevcut fixture setinde medyan artışı 500 µs altında.
  **DÜZELTME (22.08, R3 kabul betiği yazılırken çıktı):** plan bunu "gate_bench ile ölçülür" diyordu, o cümle yanlış. `gate_bench` `rbrules::judge_command`'i ölçüyor ve sinyal yolunu hiç çalıştırmıyor — kademe 1'in maliyetini görmesi yapısal olarak mümkün değil. İki seçenek var ve R3 uygulanırken biri seçilip yazılacak: (a) `gate_bench.cpp`'ye sinyal kolu eklenir ve ölçüm oraya taşınır, (b) ölçüm süreç-içi zamanlayıcıyla yapılır.
  **Ve bu bir bütçe sorunu:** süreç başlatma ~4 ms, 500 µs bütçesini yutuyor. Uçtan uca gate çağrısıyla ölçülen bir delta, gerçek bir 400 µs regresyonunu gürültünün üstüne çıkaramaz (R3 kabul betiği bugün ON 3937 µs / OFF 4002 µs, delta −64 µs ölçtü: yok olan bir özelliğin maliyeti sıfır etrafında gürültü). R3 uygulanırken ölçüm süreç-içine alınmazsa kabul maddesi 3 ölçmüş gibi yapıp hiçbir şey ölçmez.

## R4 — enjeksiyon: hata olduğu anda tamir edilir

Ürün bu turda ürün olur. "Yakalıyor ama çözmüyor" şikâyeti burada kapanır: sinyal ateşleyince ajan durdurulmaz, ajanın göremediği tarihçe context'ine düşer ve tamiri ilk retry'da ajanın kendisi yapar. Token'ı yakan zaten koşan modeldir; rabadon ek çağrı yapmaz.

Enjeksiyon metninde yazılacak (Yasa 2 + Yasa 3):
- hangi dosya bağlamında çalışıldığı
- önceki denemede neyin kırıldığı (err_sig'in okunabilir hali)
- karşıtlık: "şu hamleden sonra süit yeşildi, bu hamleden sonra kırmızı, fark bu"
- kaçıncı deneme olduğu

Yazılmayacak:
- satır numarası (Yasa 2)
- ajanın ne yapması gerektiği (öneri değil, bilgi)
- 400 karakteri aşan hiçbir şey

Üç seviye, sadece biri durdurur:
- **kesin → blok.** Bugünkü 11 yasa ve test-tamper değişmez. R2'nin 5. sinyalinin deterministik alt deseni buraya katılır: suite kırmızıyken test/harness/kapı dosyasına yazma bloklanır ve stderr sebep söyler ("suite kırmızı; kapıyı değil kodu düzelt"). Bu, mevcut kesin ailesinin kapsam genişlemesidir ve deterministiktir.
- **olası → enjeksiyon, blok yok.** Semantik tekrar, salınım, kök taşıma, kırmızı→yeşil-sadece-test-değişti deseni.
- **zayıf → sadece ledger.** Ajan görmez.

Terfi merdiveni: bir kural, R2'nin topladığı gerçek kullanım verisinde ölçülmüş yanlış pozitif oranı %10 altına inmeden üst seviyeye geçmez.

**Kademe 1'in eşiği sanılan yeri korumuyor — ölçüldü, 23.08.** Bir geliştiricinin test dosyasını adım adım büyütmesi (altı ekleme, tek dosya) ardışık sürümlerde **0.88 token örtüşmesi** üretiyor; eşik 0.80. Yani eşik onu geçiriyor. Sessiz kalmasının tek sebebi `MIN_HITS = 3`: dosya büyüdükçe eski sürümlere benzerlik düşüyor ve üç isabet hiç dolmuyor.

Sonuç, R4'ün terfi merdiveni için bağlayıcı: **`MIN_HITS` yük taşıyan parçadır, `THRESHOLD` değil.** `MIN_HITS`'i düşüren bir değişiklik, ajanın yaptığı en değerli işe — test yazmaya — yanlış pozitif basar. Kademe 1 kaynaklı hiçbir sinyal, `MIN_HITS` gerekçesi ayrıca ölçülmeden "olası" seviyesine terfi etmez. (`native/signals_test.sh`, "a test file grown one assertion at a time"; ikinci sıradaki aday üç adımlı operatör düzeltmesi, 0.6923.)

Durma: enjeksiyon PreToolUse additionalContext yolundan gider, stdout'a değil. Aynı sinyal aynı oturumda en fazla 2 kez enjekte edilir; üçüncüsü ledger'a düşer ve R5 tetiklenir. Enjeksiyon bloklamaz. Cursor gibi before-edit hook'u olmayan ajanlarda enjeksiyon bir sonraki mümkün noktada verilir ve bu fark docs/agent-contract.md'ye yazılır, gizlenmez.

Kabul (reports/R4/accept.sh):
- sentetik kök-taşıma oturumunda enjeksiyon metni üretiliyor
- metin satır numarası içermiyor (grep ile ispat)
- metin 400 karakteri aşmıyor
- aynı sinyal üçüncü kez enjekte edilmiyor
- enjeksiyon açık/kapalı gate çıkış kodları aynı
- kırmızı-suite'te test dosyası yazımı bloklanıyor ve stderr sebep içeriyor; yeşil-suite'te aynı yazım geçiyor

## R5 — onarım kolu: politika kapısı, tur içi tetik

repair kolunun kontrollü deneyi (klon, hash-kilit, kopyada öneri, aynı kontrolle doğrulama) gerçek ve çalışıyor; sorun tetikleme zamanıydı: kullanıcı elle çağırana kadar hata çoktan birikiyor. Tetik artık R2'nin kök-taşıma sinyali: aynı hata üçüncü farklı yoldan çıktığında ve 2 enjeksiyon işe yaramadığında repair devreye girer.

Onay her seferinde soru değil, bir kere verilen politikadır. rabadon init sorar:

    repair.mode = ask | auto-propose | off

- **ask:** sinyal anında tek satır soru düşer, onayla koşar.
- **auto-propose:** gece/başıboş koşular için. Sorusuz koşar, AMA kullanıcı ağacına asla dokunmaz: yama .rabadon/repair-<ts>.patch olarak tutulur, sabah rabadon repair --apply tek komutla uygular. Sessiz uygulama yok.
- **off:** kol kapalı, sinyaller sadece ledger'a.

Önericiye giden metin Yasa 2'ye hizalanır: dosya bağlamı eklenir, satır düzeyi eklenmez, arbiter ham çıktısı tek başına verilmez. Repair'in harcadığı token ölçülür ve sayaçta gider hanesine yazılır (Yasa 6).

Durma: kullanıcı ağacı hiçbir modda kendiliğinden değişmez. Propose-and-hold korunur.

Kabul (reports/R5/accept.sh):
- kök-taşıma sinyali (2 enjeksiyon sonrası) onarım teklifini/koşusunu üretiyor
- ask modunda onay olmadan hiçbir proposer çağrısı yok (ledger ispatı); auto-propose modunda çağrı var ama kullanıcı ağacının hash'i koşu boyunca değişmemiş
- önericiye giden metinde dosya bağlamı var, satır numarası yok
- off modunda proposer hiç çağrılmıyor

## R6 — sayaç: oturum kapanış satırı

Ürünün vitrini. SessionEnd (yoksa Stop) hook'unda tek satır basılır:

    rabadon: N hata zinciri kesildi, M'i anında düzeltildi, tahmini X $ kurtarıldı.

Tanımlar (docs/COUNTER.md'ye aynen yazılır):
- **kesilen zincir:** blok ya da enjeksiyonla sonlanan tekrar/salınım/kök-taşıma dizisi (ledger'dan).
- **anında düzeltilen:** enjeksiyondan sonraki ilk 3 hamle içinde aynı err_sig'in bir daha görülmemesi VE (varsa) suite'in yeşile dönmesi. Ajanın "düzelttim" demesi sayılmaz, ledger'daki sonuç sayılır (claimed_rc bir iddiadır kuralının devamı).
- **tahmini kurtarılan $:** kesilen zincir başına engellenen çağrı sayısı tahmini (sabit katsayı değil; kesilmeden bitmiş geçmiş zincirlerin ölçülen uzunluk dağılımının medyanı, ledger'dan) × oturumun gerçek ortalama çağrı maliyeti (ajanın kendi yerel oturum kayıtlarından okunur, Claude Code'da ~/.claude/projects/ altındaki JSONL; ağa hiçbir şey gitmez) − rabadon'un o oturumda enjekte ettiği tokenların maliyeti − (varsa) repair kolunun harcadığı tokenlar.

Fiyat kaynağı: ccusage'ın kullandığı LiteLLM fiyat tablosu, çevrimdışı önbellekli; cache-read ve cache-write ayrı sınıf olarak fiyatlanır (uzun oturumda hacmin çoğu cache-read; bunu input'a katan sayaç yanlış sayar). Abonelik kullanıcısında satır "API liste fiyatıyla tahmini" der (Yasa 7).

Fail-honest kuralları:
- oturum JSONL'i bulunamıyorsa ya da model fiyatı çözülemiyorsa dolar kısmı basılmaz, sadece hata sayısı basılır.
- net negatifse negatif basılır ("tahmini -0.40 $": rabadon o oturumda kazandırmadı, dürüstçe söylenir).
- zincir dağılımı için yeterli geçmiş yoksa dolar yerine "ölçüm birikiyor" basılır; uydurma katsayı kullanılmaz.
- oturumda hiç zincir kesilmediyse satır "rabadon: bu oturumda müdahale yok" der; sıfır dolar "kurtarıldı" diye basılmaz.
- JSONL'de rabadon'un kendi enjeksiyon tokenları ayırt edilemiyorsa gider hanesi üst sınırdan yazılır (400 karakter × enjeksiyon sayısı); lehimize yuvarlama yok.

rabadon usage haftalık toplamı gösterir; rabadon usage --explain her sayıyı zincir zincir, çağrı çağrı türetir; rabadon usage --json aynı veriyi makine okunur verir (M2'deki paylaşım kartı buradan üretilir, elle değil). README'ye sayaç cümlesi bu turun kabulü yeşilken girer.

Durma: sayaç hesabı oturum kapanışında çalışır, hot-path'e eklenmez. stdout satırı yalnız kapanışta ve tek satırdır. Yeni CLI verb'ü açılmaz; sayaç usage'ın içidir.

Kabul (reports/R6/accept.sh):
- kapanış satırı "tahmini" (EN'de "estimated") kelimesini içeriyor
- sentetik oturumda elle hesaplanan sayıyla bire bir aynı sayı basılıyor
- usage --explain aynı sayıyı adım adım türetiyor, ara toplamlar ledger satırlarına referans veriyor
- JSONL-yok fixture'ında dolar basılmıyor, hata sayısı basılıyor
- negatif senaryo fixture'ında negatif basılıyor
- sıfır-müdahale fixture'ında "kurtarıldı" kelimesi geçmiyor
- docs/COUNTER.md formülü kodla aynı (formül testten okunur, elle senkron değil)

## R7 — hız ve iki kollu kanıt

**Hız.** Kapı süresinin büyük kısmı süreç başlatma — ve bu artık **ölçüldü**: 4.2 ms'lik bir çağrının ~2.3 ms'si fork/exec/dyld (R1.3 profili, `reports/R1.3/PROFIL.md`). Yani daemon'ın kazanacağı şey tahmin değil, bilinen bir sayı; gate'in kendi işi ~1.9 ms ve optimize edilecek yer orası. Kalıcı daemon (rabadon-gated, unix socket) + ince istemci ile yargılama süresine iner; daemon yoksa istemci bugünkü yola düşer: fail-open değil, fail-same.

**Kanıt.** İki kollu koşu: aynı görev seti, A kolu ajan yalnız, B kolu ajan + birikme motoru. Harness sıfırdan yazılmaz. **Kullanılan harness'ın tam repo adı ve commit'i reports/R7/ altına yazılır — zorunlu.** Terminal-Bench adı tek başına bir şeye işaret etmiyor: `laude-institute/terminal-bench` v1, `harbor-framework/terminal-bench-2` v2, gerçek harness artık `harbor-framework/harbor`, ve `alibaba/terminal-bench-pro` üçüncü taraf. Hangisi olduğu yazılmadan beş sayının hiçbiri karşılaştırılabilir değildir. (SWE-smith ya da Terminal-Bench/Harbor yeniden kullanılır; Cursor'ın 25.06 yazısındaki .git temizleme ve egress kapatma hazırlığı uygulanır — Cursor'ın kendisi bunu "best-effort" diye niteliyor, biz de öyle yazarız; yoksa ajan cevabı git geçmişinden bulup her iki kolu da şişirir). Beş sayı: gerçek fix oranı (held-out testle, ajanın kendi testiyle değil), harcanan token, insan müdahalesi, yanlış pozitif oranı, ve sayaç doğrulaması — B kolunda sayacın "tahmini kurtarılan" toplamı iki kol arasındaki gerçek token farkıyla karşılaştırılır, sapma yüzdesi raporlanır. Ham JSONL reports/R7/ altına, özet değil.

Kabul (reports/R7/accept.sh):
- daemon açıkken kapı medyanı < 1 ms, gate_bench ile ölçülü
- daemon kapalıyken davranış bugünküyle bayt bayt aynı
- iki kolun ham verisi mevcut ve bench/reproduce.sh ile yeniden üretilebilir
- reports/R7/ altında harness'ın tam repo adı ve commit hash'i yazılı; test bunun varlığını kontrol eder

## R8 — yayın

npm paketi ilk kez gerçekten çıkar. Bilinen üç kırık bu turda kapanır, yenisi aranmaz:
1. darwin-arm64 ölümü: heldout/harness_lock pytest guard'ları gerçek macOS runner'da doğrulanır; runner'a pytest kurmak da meşru çözümdür, hangisi seçildiyse workflow'a yazılır.
2. release.yml'in 17 binary / package.json'ların 18 dosya uyuşmazlığı kapanır: rabadon-run her platform paketine girer.
3. Yayın yeşil main'den, temiz tag'le yapılır; kırmızı tabandan publish yasak.

Plugin paketi: repo köküne .claude-plugin/plugin.json + hooks/hooks.json girer; hook'lar npm'deki aynı binary'yi çağırır, ikinci kod yolu yoktur. Kurulum iki cümle olur: `npm i -g rabadon` ya da `/plugin marketplace add <org>/rabadon && /plugin install rabadon@rabadon`. Plugin README'si açıkça yazar: hot-path'te ağ yok, model yok, izin dosyasına yazmıyor — PromptArmor saldırı sınıfına karşı savunma cümlesi dürüst olarak söylenebildiği için söylenir.

**Canonical dizin `anthropics/claude-plugins-official`'dır — PR oraya gider.** Aynı plugin isimlerini taşıyan üç repo var ve yanlışına gitmek dağıtımı boşa harcar: `anthropics/claude-code/plugins/` bir *demo* marketplace, `anthropics/claude-plugins-community` üçüncü bir dizin. Otomatik kayıtlı ve Anthropic yönetimli olan yalnız `claude-plugins-official`.

Free/paid ayrımı bu turda sadece bayraktır: RABADON_TIER=free sinyalleri ve sayacı çalıştırır ama enjeksiyonu ve repair kolunu kapatır; free'de kapanış satırı "düzeltme kapalıydı, tahmini X $ yandı" der. Lisans/ödeme altyapısı bu koşunun dışıdır, bayrak yeterlidir.

Kabul (reports/R8/accept.sh):
- npm view rabadon version yayınlanmış sürümü döndürüyor
- dört platform paketinin dosya listesi ile workflow'un kopyaladığı binary listesi bire bir aynı (test iki listeyi karşılaştırır)
- `claude --plugin-dir .` ile plugin yükleniyor, hooks.json'daki komutlar npm binary'siyle aynı yolu çağırıyor (diff sıfır)
- README kurulum bölümü yayınlanan komutu gösteriyor, "not on npm yet" notu düşmüş
- free bayrağında enjeksiyon ve repair kapalı, sayaç açık; iki tier'da kapanış satırı doğru metni basıyor

---

# PAZARLAMA TURLARI (M0..M4)

Kural: M turu, bağlı olduğu R turunun kabulü yeşil olmadan kapanmaz. Ölçülmemiş şey satılmaz (Yasa 7). Operatörün "build in public" hasadı (stitchu/gymgyme/ir-globe için kurulu akış) burada aynen kullanılır; yeni kanal icat edilmez, mevcut akışa rabadon eklenir.

## M0 — isim, cümle, yer (R0 ile birlikte)

- docs/POSITIONING.md'den landing tek sayfa: cümle (§1c), üç rakip cümlesi, kapanış satırının görseli (şimdilik "ölçüm birikiyor" haliyle, uydurma sayıyla değil). Domain karar: rabadon.dev (müsaitlik kontrol edilir, yoksa getrabadon.dev).
- GitHub repo açıklaması ve topics: coding-agent, claude-code, cursor, reward-hacking, reliability. claudemarketplaces.com GitHub'ı otomatik taradığı için topics keşfin kendisidir.
- Kanal listesi sabitlenir ve yalnız bunlar kullanılır: GitHub README, X, LinkedIn/Substack (mevcut hasat akışı), Show HN (bir kez, M4'te), r/ClaudeAI + r/cursor (launch haftası), Anthropic Discord'un plugin kanalı.
- Hedef kitle tek: Claude Code/Cursor'da günde 2+ saat agent koşturan, "bugün kaç para yaktım" sorusunu zaten ccusage ile soran geliştirici. Takım/kurumsal hedef M4 sonrasına; kişisel sat, takım gelir.

Kabul: landing yayında, üstünde ledger'dan gelmeyen tek sayı yok.

## M1 — makbuzlar (R2 ve R4 ile birlikte)

R2'nin sessiz modu gerçek oturumlarda veri toplarken her tur kapanışında reports/R*/tohum.md'ye düşen 3-5 satır (olay + sayı + ledger referansı) haftalık tek yazıya işlenir: "bu hafta ajan şunu 4 kez yapmaya çalıştı, 2'sinde testi yeşile boyamak istedi." Yorum yok, sayı var. Bu yazı serisi Show HN'in ham maddesi olur.

İçerik formatı: kısa (≤ 300 kelime), bir ledger satırı ekran görüntüsü, bir cümle "ne görüldü". Reels için: terminalde kırmızı suite + test dosyasına yazma denemesi + stderr "suite kırmızı; kapıyı değil kodu düzelt" — 15 saniye.

Kabul: en az 4 haftalık makbuz yazısı yayında, her birinde en az bir ledger referansı.

## M2 — sayaç görseli (R6 ile birlikte)

Kapanış satırı ürünün tek reklamıdır. `rabadon usage --json` çıktısından otomatik üretilen haftalık kart (text, PNG değil; terminal ekran görüntüsü olarak paylaşılır): "bu hafta: N zincir, M anında düzeltme, tahmini X $". Kart kullanıcıya aittir, paylaşması için tek komut yoktur; paylaşılabilir olması için dürüst olması yeter.

Operatörün kendi oturumları ilk kaynak: stitchu/gymgyme/ir-globe koşularının gerçek sayaç çıktıları, negatifler dahil, yayınlanır. İlk negatif sayaç yazısı ("rabadon bu hafta bana 0.40 $ kaybettirdi, işte neden") özellikle yazılır; piyasada böyle yazı yok.

Kabul: en az 3 gerçek oturumun sayaç satırı yayında; biri negatif ya da "müdahale yok".

## M3 — kanıt yazısı (R7 ile birlikte)

İki kollu koşunun raporu tek yazı: beş sayı, ham JSONL linki, bench/reproduce.sh komutu. Başlık iddiasız: "We measured whether rabadon pays for itself." Sonuç olumsuzsa yazı yine çıkar ve yanlışlanma koşulu 1 uygulanır; olumluysa sayaç cümlesi README'ye bu yazıyla birlikte girer.

Karşılaştırma tablosu: rabadon vs "ccusage yalnız" vs "guardrail yalnız" — her sütunda ne ölçer, ne engeller, hot-path'te ağ var mı, model var mı. Rakip sütunlarındaki sayılar rakibin kendi sayfasından, linkli, ve docs/POSITIONING.md'de doğrulanmış işaretli.

Kabul: yazı yayında, reproduce.sh üçüncü bir makinede aynı sayıyı veriyor.

## M4 — yayın haftası (R8 ile birlikte)

Sıra, aynı hafta:
1. npm + plugin marketplace yayını (R8 kabulü yeşil).
2. anthropics/claude-plugins-official'a PR (kabul garantisi yok; PR'ın kendisi görünürlük).
3. Show HN: başlık "Show HN: rabadon – catches your coding agent repeating itself and painting tests green, tells you what it cost". İlk yorum M3 yazısının beş sayısı. Negatif sonuçlar saklanmaz; HN'de saklanan sonuç bulunur.
4. r/ClaudeAI, r/cursor, Anthropic Discord: aynı gün, aynı beş sayı.
5. Mevcut hasat akışı: LinkedIn/Substack uzun yazı + reels (M1 formatı).

Fiyat hipotezi: **AÇIK — M3 sonrası yeniden yazılır.**

Eski hipotez ($12/ay kişisel Pro) tek bir dayanağa oturuyordu: Lineman'ın "$49 koltuk" fiyatının çok altında kalmak. O koltuk yok (§1b). Takım geneli $14.99'un karşısında $12/kişi, iki kişilik bir takımda bile bizi pahalı yapıyor — yani hipotezin gerekçesi çürüdü, sayısı değil. Sayıyı gerekçesiz taşımak Yasa 7'nin ihlali olur.

Yeniden yazımın ön koşulu M3'tür: iki kollu koşu, rabadon'un bir oturumda gerçekte kaç dolar kurtardığını ölçmeden fiyatın dayanacağı tek dürüst zemin yok. M3 bittiğinde bu blok şunlarla yeniden yazılır: ölçülen kurtarma başına değer, free→Pro'nun neye karşı satıldığı, ve rakip fiyatının kendi yayınladığı hâli.

Bu koşuda sabit kalan tek şey ayrımın kendisi (bayrak, R8):
- Free: sinyaller + sayaç, düzeltme kapalı. "Tahmini X $ yandı" satırı conversion'ın kendisidir.
- Pro: enjeksiyon + repair açık. **Fiyat: açık.**
- Team: M4 sonrası, plugin marketplace'in team dağıtımı üstüne; fiyat ilk 20 Pro kullanıcının söylediğiyle belirlenir.

M4, fiyatı açık bırakarak da koşabilir: ölçülecek üç oranın ikisi (landing → install, install → 7 gün sonra hâlâ kurulu) fiyattan bağımsızdır. Üçüncüsü (free → Pro) fiyat yazılana kadar ölçülemez ve bu, M4 raporunda eksik değil, bilinen bir boşluk olarak yazılır.

Ölçülecek: landing → npm install oranı, install → 7 gün sonra hâlâ kurulu oranı, free kapanış satırını gören → Pro'ya geçen oranı. Üçü de ilk ay raporda.

Kabul: Show HN yayında; ilk 30 gün üç oran ölçülmüş ve reports/M4/'e yazılmış.

---

## Roller (Tur arası kapı bölümünün yerine geçer)

Üç oturum, üç yetki, hiçbiri diğerinin dosyasına yazamaz:

| rol | ne zaman koşar | ne görür | ne yazar |
|---|---|---|---|
| yapan | tur boyunca | her şey | kod, test, rapor, SORU.md |
| yargıç | tur kapanışında | diff + rapor + kabul + bütçe; tarihçe değil | reports/R<n>/kapi.md |
| danışman | SORU.md yazıldığı anda | plan + SORU + profil/ölçüm + ilgili kod; tur anlatısı değil | reports/R<n>/KARAR.md |

### Ölçemeyen bir bütçe kapısı, olmayan bir kapıdan kötüdür

23.08'de kanıtlandı: R1.3'ün kabul betiği, **hiç değişmemiş tek bir ikili dosyada** beş koşuda 602, 118, 213, −59, 228 µs verdi — tavan ~212. Aynı kod hem geçti hem kaldı. Uzunluk testi aynı şekilde %0.4 ile %11.7 arasında salındı, tavan %10.

Bu bir tur sorunu değil, **alet sorunu**. Süreç başlatma 4.2 ms'lik çağrının ~2.3 ms'si; 200 µs'lik bir bütçeyi o gürültünün içinden ölçmeye çalışmak, terazi yerine zar atmaktır. Ve zar atan bir kapı, yokluğundan kötüdür: gerçek bir regresyonu geçirir, temiz bir turu keser, ve iki kararına da kimse güvenmez.

**Kural: bir bütçe maddesi, ölçtüğü büyüklüğü çözebildiğini KANITLAMADAN kullanılmaz.** Kanıt yöntemi ekilmiş regresyondur — ölçüme bilerek bilinen bir maliyet (ör. 150 µs) eklenir ve alet onu tekrarlanabilir şekilde yakalıyor mu diye bakılır. Yakalayamıyorsa o madde yeşil dönse bile hiçbir şey söylemiyordur.

**Aleti değiştirmek gevşetme değildir; iddianın KONUSUNU küçültmek gevşetmedir.** "Kayıt tavanın altında maliyetli" cümlesi aynı kalır, ölçen şey değişir. Bu ayrımı yargıç denetler (KAPI-PROMPT 4. soru).

### Sayı yazan doküman, kod büyüdükçe yalana döner

23.08'de yakalandı: `make test` R3'ten **önce** kırmızıydı ve kimse fark etmemişti. Sebep `site_claims_test.sh` — README "~17k satır" diyordu, `native/` 20.231'e çıkmıştı, test bandı 18k–22k. Yani kırmızıyı yapan yeni kod değil, **eski bir cümlenin bayatlaması**ydı; her tur `native/`'e satır eklediği için bu bir zaman meselesiydi.

İki sonuç:

1. **Bir turun "make test yeşildi" raporu, o turun kendi ölçümüyle sınırlıdır.** Tur başında koşulmayan bir suite, tur sonunda kırmızıysa suçlu tur olmayabilir. Bundan sonra her tur **başlangıç ölçümünü de** kaydeder (`reports/R<n>/baseline` ya da CLAIM.md'de tek satır), yoksa "ben mi kırdım" sorusu cevaplanamaz.
2. **Sayı taşıyan her public cümle bir bakım borcudur.** README'deki satır sayısı, BENCHMARK'taki tablolar, landing'deki her rakam — kod büyüdükçe kayarlar. Yasa 7 bunların ledger'dan türemesini istiyor; türeyemeyen sayı (ör. "kaç satır C++") ya bir testle bağlanır ya da cümleden çıkarılır. Bant genişletmek çözüm değil, borcu ertelemektir.

**Ölçüm yöntemi sayının yanına yazılır.** Aynı `make test` çıktısı, hangi özet-satırı biçimlerinin sayıldığına göre 1876, 2036 ya da 2451 verebiliyor — üçü de "doğru". Bir turun sayısı ancak **aynı yöntemle** alınmış bir sayıyla karşılaştırılabilir. Bu koşunun yöntemi:

    grep -oE '[0-9]+ (passed|ok), *[0-9]+ failed' LOG | grep -oE '^[0-9]+' | paste -sd+ - | bc

### Faz dağıtımı — yapan tek context'te koşmaz

Bir tur tek bir oturumun context'ine sığmaz. Sığdırmaya çalışmak turu yavaşlatır ve kaliteyi düşürür: ham dosya içeriği, uzun loglar ve test çıktıları context'i şişirir, şişen context'te karar kalitesi düşer. Yapan oturum turu parçalara böler ve her parçayı **kendi ajanına** verir:

| parça | ajan ne yapar | ne yapmaz |
|---|---|---|
| kabul betiği | turun sınavını yazar, kırmızı olduğunu doğrular | ürün kodu yazmaz |
| uygulama | tek hedef, kabul betiği elinde, yeşile çevirir | kabul betiğini düzenlemez |
| ölçüm / profil | sayı üretir, neyi izole edemediğini söyler | yorum yazmaz |
| araştırma | birincil kaynak + URL, doğrulanmayanı işaretler | sayı uydurmaz |

Yapan oturumun context'inde yalnız şunlar durur: planın ilgili bölümü, ajanların dönen **özetleri**, ve kararlar. Ham çıktı yapanın context'ine girmez.

Kural: bir ajanın dönüş raporu **40 satırı geçmez** ve ölçüm içerir. Ajan "yaptım" diyemez; ne koştuğunu ve ne çıktığını yazar. Paralel çalışabilecek parçalar aynı anda salınır.

### Danışman

Yapan oturum SORU.md yazınca DURMAZ; danışmanı çağırır ve KARAR.md gelene kadar o soruya bağlı olmayan işi yapar (test fixture, doküman, sonraki turun bütçesi).

    claude -p "$(cat docs/DANISMAN-PROMPT.md)" < <(cat KOSU-RABADON.md reports/R<n>/SORU.md reports/R<n>/PROFIL.md; git show HEAD:<ilgili dosyalar>)

Danışmanın görevi A/B/C'den seçmek DEĞİL. Üç adım, sırayla, yazılı:

1. Hangi değişmez ihlal ediliyor? (ör. "her olayda tüm tarihçeye dokunuluyor") Yapanın sunduğu seçeneklerin hepsi aynı değişmezi ihlal ediyorsa hepsi reddedilir.
2. Değişmezi koruyan tasarım ne? Seçenek D yazılır, A/B/C'ye bakılmaksızın.
3. Karar + o kararın kabul ölçüsü + bütçe satırı. "Dene bak" yok; ölçülebilir beklenti yazılır ("parse O(1) olmalı; delta ≤ %5").

Danışman KARAR.md'ye yalnız şunları yazar: değişmez, tasarım, karar, kabul ölçüsü, ve OPERATÖR mü DEĞİL mi etiketi.

### Operatöre giden sorular — kapalı liste, danışman karar verir

Yalnız bunlar operatöre gider, gerisi danışmanda biter:

- **para:** fiyat, tier sınırı, ödeme
- **ürün konumu:** cümle, kategori, hedef kitle değişikliği
- **dış yayın:** npm publish, Show HN, herhangi bir public metin
- **sahiplik:** operatörün kendi verisi/dizini arasında seçim (`docs/kanit` gibi)
- **geri alınamaz:** repo dışına etki, kullanıcı ağacına yazım, plan dosyasındaki Yasa değişikliği

Danışman bir soruyu OPERATÖR etiketlerse yapan oturum o soruda durur, başka işte devam eder. Operatör günde bir kez KARAR.md'leri okur; geriye dönük veto hakkı var, veto geldiğinde o karardan sonraki commit'ler geri alınır. Okumazsa kararlar geçerli sayılır.

### Aynı sorun sayacı (ara tur kuralının yerine)

Bütçe maddesi aynı turda iki kez AŞTI → danışman optimizasyon değil **tasarım değişikliği** yazmak ZORUNDA (madde 2). Aynı madde üçüncü kez AŞTI → OPERATÖR, ve PROFIL.md şart. Ara tur adedine değil, **aynı ölçümün kaç kez tutmadığına** bakılır.

### Yargıç değişmedi

Beş soru, GEÇTİ/AŞTI/BLOK, tek dosya. KAPI-PROMPT 4. soruya eklendi: "zaman damgası, geçici yol ve sandbox adı maskeleme gevşetme değildir."

## Yanlışlanma koşulları (bugün yazıldı, sonuç görülmeden)

1. R7 biter ve B kolu A koluna göre ne gerçek fix oranında ne net token'da gerçek iyileşme göstermezse, enjeksiyon tezi yanlıştır; birikme motoru sessiz moda döner, ürün konumu yeniden düşünülür. M3 yazısı yine çıkar.
2. Sayacın tahmini, iki kollu koşudaki gerçek token farkından %50'den fazla saparsa, dolar satırı yayından çekilir; kapanış satırında yalnız hata sayısı kalır, formül düzeltilip yeniden ölçülene kadar geri gelmez. Landing'deki dolar cümlesi de aynı gün iner.
3. M4'ten 30 gün sonra free→Pro geçiş sıfırsa fiyat hipotezi yanlıştır; sayaç satırının satmadığı kabul edilir. (Bu koşul, fiyat M3 sonrası yazılana kadar ÖLÇÜLEMEZ — açık fiyatla free→Pro diye bir geçiş yoktur. M4 raporu bunu eksik değil, bilinen boşluk diye yazar; koşulun saati fiyat yazıldığı gün başlar.) Koşul tetiklenirse ürünün "takım görünürlüğü" konumuna çekilip çekilmeyeceği ayrı kararla masaya gelir. Sayı şişirerek çözülmez.

## Bu koşuda yapılmayacaklar

- kademe 2 / AST / tree-sitter (R7 sonrası, ölçümsüz değil)
- hot-path'te embedding, model çağrısı, LLM yargıç. Not: literatür (EvilGenie, TRACE) reward hacking tespitinde LLM yargıcı güçlü bir dedektör sayıyor; v1'de deterministik alt küme yeter, yargıç R7 ölçümünden sonra ayrı kararla masaya gelir — yargıcın kendisi yanlış pozitif kaynağıdır ve DoS yüzeyidir (guardrail-DoS literatürü).
- yeni CLI verb'ü (yüzey beştir, geri şişirilmez)
- OTLP, dashboard, UI genişletmesi
- README'de, landing'de ya da kapanış satırında ölçülmemiş / ledger'dan türetilmeyen tek bir sayı
- sessiz otomatik yazma: hiçbir mod kullanıcı ağacını kendiliğinden değiştirmez
- rakip ölçümü: rakibin sayısını biz ölçmeyiz, kendi yayınladığını linkleriz
- takım/kurumsal satış M4'ten önce
- ücretli reklam (claudemarketplaces.com dahil) M4 ölçümü görülmeden

## Neden bu sıra

R0 önce, çünkü iki plan dosyası olan repoda ajan hangisine uyacağını bilemez; tek kaynak kalır. R1 olmadan R2 doğrulanamaz: kayıt yoksa sinyal test edilemez. R2 olmadan R4 yapılamaz: yanlış pozitif ölçülmeden enforce etmek Yasa 1 ihlalidir. R3, R4'ten önce gelir çünkü tam eşitlikle söylenecek söz zaten bugün bloklanıyor; yeni bir şey söylemek için semantik lazım. R5, R2'nin sinyaline bağımlıdır. R6, R1+R4'ün ledger'ı olmadan basacak dürüst sayı bulamaz. R7 sona doğrudur: hızlandırma doğru şey kanıtlanmadan yapılan optimizasyondur ve sayaç iki kollu koşuyla doğrulanmadan dünyaya dolar söyleyemez. R8 en sondadır: yayın, ürün ürün olmadan yapılan gürültüdür; ama bu kez yayının kendi üç kırığı da bilinen iştir ve turun içindedir.

M turları R'lerin gölgesidir: M0 sadece cümle ve yer (sayı yok), M1 ham makbuz (sayı var, iddia yok), M2 sayaç (iddia var, ölçülü), M3 kanıt (karşılaştırma var, yeniden üretilebilir), M4 yayın. Sıra tersine dönerse — önce Show HN, sonra ölçüm — piyasadaki "%40 daha az token" yazılarından biri daha oluruz ve ürün o kalabalığın içinde kaybolur. Dürüst sayaç tek farkımız; farkı korumanın yolu sırayı korumaktır.

## Tur kapanış notu (pazarlama hasadı)

Her tur kapanışında reports/R*/tohum.md dosyasına 3-5 satır düşer: o turda ledger'a giren en çarpıcı olay + sayısı (ör. "kırmızı suite'te test dosyası yazımı 2 kez bloklandı, ikisi de gerçek oturumda"). Yazı yazılmaz, yorum yapılmaz; sadece olay + sayı + ledger referansı. İşleme chat'te yapılır; M1 bu dosyaları tüketir.
