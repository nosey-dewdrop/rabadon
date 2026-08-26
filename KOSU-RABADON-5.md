# rabadon, koşu belgesi 5

2026-08-26. Koşu 4'ün yerine geçer. Koşu 2 ve 4 arşive iner, silinmez.
Bu belge kendi kendine yeter. Bir fazın şefi başka hiçbir şey okumadan ne yaptığını ve niye yaptığını buradan bilir.

---

## §1. PROJE NEDİR

**rabadon, kodlama ajanının hatasını daha büyümeden yakalar ve ajana kendi tamir ettirir.**

C++ ile yazılmış yerel bir ikili. Ajanın hook'larına takılır, her hamleyi görür, hamlenin sonucunu tutar. Ajan bir hataya takılmaya başladığında araya girer ve ajanın göremediği tarihçeyi onun bağlamına verir. Tamiri rabadon yapmaz, ajan yapar.

Hot-path'te model çağrısı yok, ağ yok, telemetri yok. Hedef gecikme bir milisaniyenin altı. Yani rabadon ekstra hiçbir şey koşturmaz, zaten yanacak olan turu keser.

**Ne değil:** gözcü değil, kapı değil, guardrail değil, izin sistemi değil, hafıza değil, geçmiş değil, ölçüm değil, rapor değil, dashboard değil. Bunların hepsi sonradan bakan ya da hayır diyen şeylerdir.

**Mekanizmanın özü:** rabadon akıllı olmaya çalışmaz. Ajan kodu nasıl yazacağını zaten biliyor, göremediği tek şey kendi tarihçesi. rabadon dışarıdan beyin sokmaz, ajanın kör noktasını onun yüzüne çarpar.

---

## §2. NE İÇİN

Ajan gece boyu çalışır. Üçüncü adımda küçük bir hata yapar. Dördüncüden onuncuya kadar o çürük zeminin üstünde koşar. Sabah kullanıcı kalkar ve repo bozuktur. Yanan token cabası.

Kullanıcının duyduğu vaat: **sen uyurken ajan bozmaz.**
Kullanıcının kendi cümlesi: *"Sabah kalktığımda ajanın gece ne bozduğunu temizlemiyorum artık."*

**İlk gün hissedeceği an:** ajan yanlış bir düzeltme üretir, hamle henüz çalışmamıştır, rabadon araya girer ve neyin yanlış olduğunu söyler, ajan doğrusunu yapar, kullanıcı hiçbir şey yapmaz. Ürünün tamamı bu tek anı üretmek için vardır.

Geliştirici canı yandığı an öder. O acıyı hissettirmezsen "zaten her şey yolunda" der ve aracı siler.

---

## §3. BAR

Çıta maintainer için çalışması değil. Çıta şu: bu şey milyonlarca geliştiriciye gider, her ajan kullanıcısının çantasında durur, ve **fren gibi** kullanılır. Ayda bir değil, her oturumda hissedilir.

İyi ürünün tanımı tek cümle: **kullanıcı kurar, ilk gün fark yaratır, silmez.**

İki düşman adıyla yazılı: **reward hacking** ve **compound error**.

Ölçek: bin ödeyen kullanıcı, ayda iki yüz dolar. Dünyada milyonlarca yazılımcı ajan kullanıyor, binde birinin ödemesi yetiyor. Sorun pazar büyüklüğü değil, ürünün gerçekten işe yarayıp yaramaması.

Küçük bir proje gibi konumlanmayacak.

---

## §4. İSTEKLERİM, tavizsiz

1. **Eşik birdir.** Üçüncü tekrarı beklemek vaadin ihlalidir; o noktada token yanmış, ağaç kirlenmiştir. Ajan aynı imzayı ya da aynı kök hatayı ikinci kez ürettiğinde girilir.
2. **Enjeksiyon ajana fiilen ulaşacak.** Ürünün ortadaki kolu bu ve bugüne kadar hiç sınanmadı.
3. **Yanlış pozitif ürünü öldürür.** Tavan yüzde beş. Üstündeki sinyal canlıya çıkmaz. Ve ağırlık farkı: kapının yanlış pozitifi kullanıcıyı kızdırır, enjeksiyonun yanlış pozitifi kodu bozar.
4. **Satır numarası enjekte edilmez, öneri verilmez.** Dosya bağlamı ve karşıtlık verilir: şu hamleden sonra yeşildi, bundan sonra kırmızı, fark bu.
5. **Ölçülmemiş şey satılmaz.** Kamuya giden her sayı ledger'dan türetilir. Net negatifse negatif basılır. "Bu oturumda kazandırmadı" satırı yayın değeri taşır.
6. **Faturada olmamış dünya hakkında sayı yok.** Karşı olgusal iddiaya kullanıcı bir süre inanır, sonra bırakır ve aracı siler.
7. **Kurulum iki cümleye iner.** Soru sorulmadan çalışır. Kafa karıştıran red bir churn olayıdır.
8. **Her reddin cevapladığı üç soru:** ne bloklandı, neden, insan sıradaki hangi komutu koşacak.
9. **Kesin seviyenin her kuralının çıkış yolu vardır.** Çıkış yolu olmayan blok üçüncü maddenin ihlalidir.
10. **Yüzey beştir, geri şişirilmez.**
11. **Ajan bağımsız kalır.** Bir ajanın yapamadığı şey gizlenmez, tabloya yazılır.
12. **Kanıt üç katmanlıdır: yazdı, okundu, zarar vermedi.** Bir şeyin ledger'a yazılmış olması onun işe yaradığını göstermez. Enjeksiyon için de, sayaç için de, her sinyal için de ölçüt ajanın davranışının değişmesidir.
13. **Yeni sinyal kullanıcıda gözlem modunda doğar.** Kullanıcı kendi verisinde görmeden hiçbir sinyal ona dokunmaz. Güven bir kez kırılırsa geri gelmez.
14. **Sorun sadece bahsettiğim yerde olmayabilir.** Son koşunun kusuru kapıda değil, hangi ikilinin bağlandığındaydı ve on beş tur boyunca hiçbir yeşil bunu göstermedi. İhtimali ele, kafana göre hareket etme.

---

## §5. KULLANICININ YOLU

Koşunun omurgası bu. Her faz bu yolun bir adımını gerçek yapar. Adımı gerçek yapmayan faz, faz değildir.

| adım | kullanıcı ne yaşıyor | bugün |
|---|---|---|
| 1. duyar | ajanının döngüye girdiğini bilen biri arar ve bulur | bulunamıyor |
| 2. kurar | iki komut, soru yok | kurulamıyor, npm 404 |
| 3. ilk ekran | kendi verisinden bir sayı görür, demo değil | yok |
| 4. çalışırken | rabadon araya girdiğinde iz görür | görünmez |
| 5. tıkandığında | ajan kurtarılır, kendisi hiçbir şey yapmaz | olmuyor |
| 6. kapanışta | iki cümlelik dürüst fatura | yok |
| 7. rahatsız olursa | tek sinyali kısar, komple silmez | tek seçenek silmek |
| 8. anlatır | ekran görüntüsü alınabilir bir çıktı | yok |

---

## §6. BUGÜN NEREDEYİZ

`main` geride, `kosu4` üstküme, arada 107 commit. **Birikme motoru yazılmış, bağlanmamış.** 26.08 ölçümü: `native/gate.cpp` 4733 satır, `signals.h` 224, `inject.h` 201, `counter.h` 339. Dört sinyal adıyla kodda: `repeat`, `oscillation`, `root_migration`, `green_redefined`. Enjeksiyon yolu tam: `hookSpecificOutput` ile `additionalContext` basılıyor, `INJECT`, `INJECT_CAPPED`, `INJECT_HELD` emit ediliyor, `RABADON_INJECT` kapatma anahtarı var. `counter.h` düzeltilmiş zinciri şöyle tanımlıyor: enjeksiyondan sonraki üç hamlede aynı hata imzası dönmedi ve süit koştuysa yeşildi.
Enjeksiyon hiç ulaşmadı: son iki kollu koşu legacy kapıya bağlıydı, ledger'da 51 satırın 51'i `STEP_START`, sıfır INJECT. Kabul 23 yeşil 3 kırmızı. Sayaç yok. Yüzey 25 verb. npm 404, sürüm 0.2.3. Disclosure 41 isim liste dışı. Onarım gerçek kırıkta 0 tutmuş. Eşik 3 ve yalnız Bash.

Elimizdeki tek gerçek ürün parçası: kapı çalışıyor ve otuz günde 61 gerçek yakalama yapmış.

**Araştırmadan gelen dört karar.** Teknik hendek dar: `opencode-anti-loop` ve StrongDM `attractor` çekirdek döngü tespitini zaten yapıyor, dağıtım hendeği daha geniş, yayın öne alınır. Yanlış pozitif tavanı yüzde beş, Tricorder eşiği bu. OpenHands önce Cursor sonra, çünkü Cursor'da enjeksiyonun ajana ulaşmadığına dair açık kayıtlar var. Platform riski canlı: Anthropic'te `/goal` ve `/loop` var, salınım tespiti henüz native değil ama olabilir, her faz bunu kontrol eder.

---

## §7. FAZLAR

Her fazın altında **ADIM** (§5'in hangi adımını gerçek yapıyor), **UX** (kullanıcı ne görüyor, nasıl kaçıyor), **KABUL**.

### F0. Zemin
**Tek kök, tek dal.** 26.08 ölçümü: `rabadon` ayrı klon ve `main` dalında, `rabadon-kosu2`, `-kosu3`, `-kosu4` onun worktree'leri. Uzağa gitmemiş commit yok. `main`'de `kosu4`'te olmayan commit de yok, yani birleştirme düz ileri sarmadır: `git merge --ff-only kosu4`. Squash kararı, çakışma, merge mesajı yok.
Birleştirmeden sonra üç worktree `git worktree remove` ile kaldırılır. **Dallar silinmez**, geçmiş `main`'e girdi ve referanslar kalır. Bu koşunun tek kökü `rabadon`, tek dalı `main`.
Bu koşuda yeni worktree ya da yeni dal açılmaz. Paralel koşu yok, tek operatör var; worktree'yi doğuran ihtiyaç ortadan kalktı.
**Tek canlı koşu belgesi.** Kökte bugün dört koşu belgesi birden duruyor: `KOSU-RABADON.md`, `-2`, `-3`, `-4`. Hepsi canlı, hepsi farklı şey söylüyor, hiçbiri diğerini iptal etmiyor. Köke bakan bir ajan hangisinin geçerli olduğunu bilemez ve yanlış belgeye göre kart keser. Dördü de `docs/archive/` altına iner, her birinin başına tek satır iptal notu düşer, silinmez. Kökte tek koşu belgesi kalır: bu.
Ortam sertleştirme: önce git kilitleri kırılır sonra yarım rebase temizlenir, inode kontrolü eklenir, kodlama sabitlenir (`PYTHONIOENCODING=utf-8`, `PYTHONUTF8=1`), alt süreçler topluca gömülür, reddedilen push yutulmaz. **CLI sürümü sabitlenir** (`DISABLE_AUTOUPDATER=1`): gece boyu koşan bir sistemde bayrak ya da çıktı formatı ortada değişirse koşu durur, ve bu koşu 2'de bulunmuş bir derstir. macOS'ta `timeout` yoktur, shim gerekir. rabadon kendi koşusuna yalnız observe modda ve sarmalayıcıyla bağlanır.
**ADIM:** yok. Tek istisna, ve bu yüzden en kısa faz.

### F1. Kurulabilen ürün
Yüzey beşe iner: `init`, `on` ve `off`, `usage`, `doctor`, `repair`. Kalan yirmi verb silinmez, `dev` altına iner. Disclosure kapısının kırk bir ismi sınıflanır, kapı gevşetilerek değil kapatılarak geçilir. npm ve plugin paketi çıkar.
**Kurulum yüzeyleri netleşir.** `rabadon init` bugün Claude Code'a `.claude/settings.json`, Cursor'a `.cursor/hooks.json` yazıyor; geri kalan herkes için `docs/agent-contract.md`'deki süreç sözleşmesi var: stdin'e tek JSON, exit kodu hüküm, 2 ret, 0 devam, başka her kod rabadon'un arızası ve ajan devam eder. Bu doğru tasarım ve korunur.
**Ama Cursor bugün kağıt üstünde destekli.** Fren edit tarafında çalışmıyor ve enjeksiyonun ajana ulaştığı doğrulanmadı. Tabloda "destekleniyor" yazamayız; ne yapıp ne yapamadığı satır satır yazılır.
**HTTP yüzeyi yok ve bu bilinçli.** Sözleşme süreç çağrısı üstünden yürür, çünkü ağ açmak hot-path yeminini bozar. Sunucu tarafında koşan ajanlar için sürtünme yaratıyorsa çözüm ağ değil, yerel soket; karar F8'de verilir, F1'de değil.
**ADIM 2.** **UX:** iki komut. `rabadon init` sonrası ekranda ne yazdığı testli. Hiçbir soru sorulmuyor. `rabadon off` tek komut ve geri dönüşü var.
**Kurulum hatasız değil, hatası anlaşılır olacak.** İki komut yazmak UX değildir; UX, o iki komut patladığında ne olduğudur. Node sürüm uyumsuzluğu, ikili izin sorunu, PATH çakışması, eski kurulumun kalıntısı: dördü de sessizce patlayan yerlerdir. `rabadon doctor` bunları tek tek kontrol eder ve `init` onu kendi içinde koşturur, kullanıcı ayrıca çağırmaz.
**KABUL:** `npm view rabadon version` sayı döndürüyor. Taşınan yirmi verb `dev` altında çalışıyor, test sayısı düşmedi. **Kurulum matrisi koşuldu ve otomatik koşuyor:** en az iki işletim sistemi ve iki Node sürümü, her biri temiz makinede. Matris elle koşulmaz, CI'a bağlanır; elle koşulan bir matris ikinci faza kalmadan terk edilir ve o zaman kurulum sessizce bozulur. Dört bilinen hata sınıfının her biri kasıtlı üretildi ve `doctor` her birinde ne olduğunu ve sıradaki komutu söyledi. Kurulumdan çalışır guard'a kaç adımda varıldığı ölçülüp yazıldı.

### F1b. Kendi koşumuzda kanıt: dogfooding
Ürünün elindeki en güçlü kanıt kendi geçmişi ve kullanılmıyor. Koşu 2'nin yirmi iki turluk logları duruyor. Beş dedektör bu logların üstünde çevrimdışı koşturulur.
**ADIM 3 ve 8'i besler.** **UX:** landing'de ve README'de duran ilk gerçek sayı bu olur. Kendi ürünümüzü kendi verimizde ölçmediysek kimseden ölçmesini isteyemeyiz.
**KABUL:** koşu 2 loglarında sinyal başına yakalama sayısı ve elle etiketlenmiş doğruluk oranı yazılı. Yakalananların en az biri elle incelenip "burada gerçekten tur yanmış" diye doğrulanmış. Rakam ledger'dan türetilmiş, elle yazılmamış.
**Canlı dogfooding kademeli:** kapı koşunun kendi worktree'sinde observe modda ve sarmalayıcıyla kalır. Deny moduna geçiş F6 kabulünden sonra ve ayrı kararla.

### F2. İlk ekran: `rabadon scan`
Beş dedektör canlı hook'a dokunmadan, geçmiş oturum kayıtları üzerinde çevrimdışı koşar. Kayıtlar yereldedir, ağ isteği yoktur. Kullanıcı kendi son yedi gününü görür: kaç tekrar, kaç salınım, kaç kök taşıma, hangi oturumda.
Bu aynı zamanda dedektörlerin gerçek veriyle ilk sınavı, sentetik fixture'ın veremeyeceği şey.
**ADIM 3 ve 8.** **UX:** aha anı ilk gerçek hataya değil kuruluma bağlanıyor. Çıktı tek ekran, ekran görüntüsü alınabilir, ve kullanıcının kendi verisi olduğu için tartışılamaz.
**Ekran suçlama ekranı olmayacak.** Yalnız geçmişte ne kaybettiğini gösteren bir çıktı kullanıcıyı ürüne değil kendine kızdırır. Çıktı üç parçadır: ne oldu, hangi oturumda, **ve sıradaki tek komut.** Kapanış satırı geçmişe değil sonraki oturuma bakar: aç, ve bir dahakinde ne olduğunu gör.
**Karşı olgusal sayı yasağı burada da geçerli.** "rabadon açık olsaydı şu kadarı kesilirdi" yazılmaz. Ne olduğu yazılır, ne olabileceği yazılmaz.
**KABUL:** her sayının yanında onu üreten oturum yolu var. Tetiklenmeler elle etiketleniyor, yanlış pozitif oranı sinyal başına ayrı yazılıyor, yüzde beş üstündeki sinyal canlıya çıkmıyor.
**Ölçüm tek tip repoda yapılmaz.** Sentetik fixture gerçek dünya karmaşasını taklit edemez. Oran en az üç zeminde ayrı ayrı ölçülür: tek paketli küçük repo, monorepo, ve büyük bağımlılık ağacı olan bir proje. Zeminler arasında oran farkı varsa bu tabloya yazılır ve en kötü zemin ölçüt kabul edilir.
**Dağıtım kapısı:** burası yeşilse ürün dağıtılabilir. Cümle dürüst olur: rabadon henüz araya girmiyor, ajanının nerede tıkandığını gösteriyor.

### F3. Canlı müdahale: motoru bağla ve yut testinden geçir
Motor yazılmış, iş onu bağlamak ve ajanın yuttuğunu kanıtlamak. B kolu gerçek native ikiliye bağlanır. Sinyal PostToolUse'da doğar, bir sonraki PreToolUse'da `additionalContext` üstünden biner. Metinde dosya bağlamı, neyin kırıldığı, karşıtlık, kaçıncı deneme; satır numarası ve öneri yok, dört yüz karakter tavan.
**Merdiven: enjeksiyon önce, blok son çare.** Enjeksiyon havada kalırsa ürün çöptür, bu doğru. Cevap her sinyali bloklamak değil, merdiven kurmak. Birinci sapmada enjeksiyon. Aynı imza devam ediyorsa ikinci ve son enjeksiyon. Üçüncüde blok, ve blok sebebini söyler ve çıkış yolunu verir. Yani rabadon "bak burası bozuk" deyip geçmez, ısrar eder ve gerekirse durdurur; ama durdurmayı ilk hamlede değil, yumuşak yol iki kez denendikten sonra yapar.
**Enjeksiyon yutulmuyorsa kanal değişir, ısrar edilmez.** (b) katmanı iki koşuda üst üste kırmızı düşerse metnin biçimi ve kanalı yeniden tasarlanır: daha kısa metin, farklı yerleşim, ya da kesin ailede sebepli red. Aynı kanalı üçüncü kez denemek yasak.
**Yeni sinyallerin varsayılanı enjeksiyon ve iz, blok değil.** Geliştiricinin doğru yazdığı kodu kesen bir araç ilk beş dakikada silinir, ve asıl kaybedilen yanlış pozitif değil güvendir.
**Yeni sinyaller kullanıcıda gözlem modunda başlar.** Kurulumda hiçbiri canlı değildir. Kullanıcı `rabadon scan` ile o sinyalin kendi verisinde ne yakaladığını görür, sonra kendisi açar. Kendi verisinde doğrulamadığı bir sinyal ona hiç dokunmaz.
**ADIM 4, 5 ve 7.** **UX:** enjeksiyon ajana gider, **iz kullanıcıya**. İz olmadan ürün kullanıcı için görünmezdir. `rabadon mute <sinyal>` tek sinyali kısar, komple kapatmaya zorlamaz, ve kısma yerelde sayılır: sahadaki gerçek yanlış pozitif oranı buradan öğrenilir.
**KABUL, üç katman. İlki tek başına kanıt değildir.**
**a) rabadon yazdı mı.** Ledger'da SIGNAL, INJECT ve COUNTER üçü de var. `STEP_START` kanıt sayılmaz, iki kapıda da yazılıyor.
**b) ajan okudu mu.** INJECT satırı yalnız rabadon'un yazdığını gösterir, ajanın kullandığını göstermez. Enjeksiyondan sonraki ilk hamlenin imzası, enjeksiyon öncesi tekrarlanan imzadan farklı olmalı. Aynı imza devam ediyorsa metin ajana ulaşmamış ya da gürültü sanılmıştır ve faz kapanmaz. Ajanın metni okuduğunu iddia etmesi sayılmaz, sonraki hamlenin imzası sayılır.
**c) zarar verdi mi.** Negatif kontrol zorunlu: aynı görev seti üzerinde, sinyal ateşlemediği halde kasıtlı enjeksiyon yapılan bir kolda ajanın çözüm oranı düşüyor mu, hamle sayısı artıyor mu. Düşüyorsa enjeksiyon bağlam kirletiyordur ve metin kısalır ya da kanal değişir. Bu ölçüm yapılmadan F4 açılmaz.
İz fixture'da düşüyor. `mute` sonrası o sinyal ateşlemiyor, diğerleri ateşliyor.

### F4. Erken müdahale
E�ik üçten bire iner. Bash kilidi kalkar, Edit ve Write kapsama girer, çünkü compound error asıl orada birikir. Semantik imza kaskadı devreye girer.
**ADIM 5'i gerçek yapar.** **UX:** kullanıcı üçüncü turu beklemiyor, ilk sapmada kurtarılıyor.
**KABUL:** salınım ve kök taşıma fixture'ları ateşliyor, Edit tarafında birikme görülüyor. F2'nin saha oranları eşik değişiminden sonra yeniden ölçülüyor ve yüzde beş altında kalıyor. `MIN_HITS` yeşil için oynatılmadı.

### F5. Fatura
Oturum kapanışında iki cümle: kaç kez kesildi, kesildikten sonra hata bir daha çıktı mı. İkisi de ledger'dan, doğrulanabilir, bedava. Statusline'a tek satır düşer.
**ADIM 6.** **UX:** gizli kahramana kimse para vermez. Dolar satırı yalnız iki kollu ölçüm varsa ve kaynağını göstererek gelir; yoksa satır olay sayısı basar, dolar basmaz.
**KABUL:** fail-honest kurallarının hepsi fixture'la kanıtlanıyor. Fiyat çözülemeyince dolar basılmıyor, net negatifte negatif basılıyor, yeterli geçmiş yokken uydurma katsayı kullanılmıyor, hiç müdahale yokken "kurtarıldı" geçmiyor. Ajanın "düzelttim" demesi sayılmıyor, ledger'daki sonuç sayılıyor.

### F6. Kanıt
İki kollu koşu temiz koşulur: aynı görev seti, A kolu ajan yalnız, B kolu ajan artı motor. Ön-kayıt N=6 doldurulur ya da eksiğin sebebi ön-kayıta yazılır. Kabul betiği ön-kayıtın kendi N'ini okur, kol başına sabit iki değil. Harness'ın tam repo adı ve commit hash'i rapora yazılır.
**ADIM 6'nın dolar satırını doğurur.**
**KABUL:** yeni ham veri, yeni tarih, INJECT satırlı. Beş sayı raporlanır, ne çıkarsa yayınlanır. Fark gürültüde kalırsa yanlışlanma koşulu tetiklenir: motor sessiz moda döner, ürün konumu yeniden düşünülür, sayı yine yayınlanır.

### F7. Bulunabilirlik
"Üretimde kimse yok" cümlesi silinir. Rakipler adıyla ve **yaptıkları küçümsenmeden** yazılır. Apollo Watcher blocking monitörlerle tool call'ı gerçek zamanlı durduruyor ve bulduğunu ajana geri besleyip self-correction sağlıyor. StrongDM `attractor` tool turları arasında yönlendirme mesajı enjekte ediyor, `LOOP_DETECTION` ve `STEERING_INJECTED` olayları var. `opencode-anti-loop` semantik tekrarı yakalıyor, blokluyor, beş blokta override promptu enjekte ediyor.
**Döngü tespiti ve enjeksiyon bir ayrışma değildir.** Üç ayrı yerde yapılıyor. Bunu fark diye yazan landing ilk yorumda çürütülür.
Ayrışma üç kalemdir ve üçü de savunulabilir: **maliyet**, rakipler izlemek için ikinci bir model koşturuyor, biz hiçbir şey koşturmuyoruz. **Güvenlik**, kod dışarı gitmiyor, yeni saldırı yüzeyi açılmıyor. **Dürüst sayaç**, türetemediğimiz sayıyı basmıyoruz, net negatifse negatif basıyoruz, ajanın beyanını kanıt saymıyoruz. Kopyalanması en zor olan üçüncüsüdür.
Hız tek başına satış argümanı değildir: kullanıcı bir milisaniye ile iki yüz milisaniye farkını hissetmez, faturayı hisseder.
Karşılaştırma tablosu landing'de açıkta durur ve rakibin sayısı yalnız kendi yayınından alınır.
Paket açıklaması ve keywords aranan kelimeleri taşır; kimse "reliability layer" diye aramıyor. **Landing var, sırası da doğru** (26.08 ölçümü): `index.html` ilk ekranda ne yaptığını söylüyor, hemen altında beş komutluk kurulum var, ölçüm sayfaları menüde arkada. Yirmi dokuz dosya ve sayı üreten bir boru hattı çalışıyor.
**Sorun sıra değil, sattığı ürün.** Başlık bugün *guardrails and a verifiable record for coding agents* diyor. §1 "guardrail değil" diyor ve o kelimenin düşmesi bir önceki protokolde karara bağlanmıştı, hâlâ birinci satırda duruyor. Sayfa yıkıcı komutu reddetmeyi ve makbuz yazmayı anlatıyor; compound error, "sen uyurken ajan bozmaz" ve enjeksiyon geçmiyor. Yani landing eski ürünü satıyor.
**Üç uyumsuzluk aynı gün kapanır:** kurulum satırı `git clone && make` diyor, F1 sonrası npm olacak. Sayfadaki beş komut (`watch`, `on`, `usage`, `repair`, `audit`) F1'in beşiyle (`init`, `on`, `off`, `usage`, `doctor`, `repair`) çelişiyor. Ve kesinlik sayısı üç farklı zeminde üç farklı değer veriyor (34 vakada yüzde 100, tüm defterde yüzde 26,3, test laboratuvarları çıkarılınca yüzde 93,8); dürüst ama sayfada hangi zeminin ne olduğu ve bunun yanlış pozitif tavanıyla aynı şey olmadığı yazmıyor.
**Korunacak olan:** sayfadaki "ilk gün işini bloklayan aracı ikinci gün silersin" cümlesi ve watch modunun varsayılan olması. Bu ürünün zaten bildiği doğru refleks, bozulmayacak.
Ölçüm sayfaları kalır, arkada durur. Bayat cümle ya güncellenir ya gerekçesiyle arşive taşınır, sessiz silme yok. `docs/SAVUNMA.md` yazılır.
**ADIM 1.** **UX:** ajanının döngüye girdiğini bilen biri arar ve bulur.
**KABUL:** ölçülmemiş hiçbir sayı sayfada yok. Duran her sayının yanında onu basan aletin adı ve ölçüm tarihi var, ve o aletin gerçekten o sayıyı bastığı doğrulanmış.

### F8. Çok ajan
OpenHands önce, Codex sonra. Cursor `additional_context` enjeksiyonu doğrulanana kadar beklemede, sebebi `docs/agent-contract.md`'de yazılı.
**ADIM 2'yi genişletir.** **UX:** kendi ajanında çalışıyor, tek editöre kilitli değil.
**KABUL:** OpenHands'te enjeksiyon ledger'da görünüyor. Desteklenmeyen ajanın yapamadığı şey tabloda.
**Sıra uyarısı:** F3 ve F4 yeşil olmadan açılmaz. Çalışmayan bir ürünü üç yere kopyalamak yayılma değildir.

### F9. Kapanış
§5'in sekiz adımı tek tek işaretlenir: gerçek mi, hangi kanıtla. §4'ün on dört isteği tek tek işaretlenir: kapandı mı, açıksa sebebi ve kuyruk satırı. Sekiz adım gerçekse ürün ayaktadır ve koşu bitmiştir. Kullanım, tutunma, fiyat ve takım katmanı sonraki koşunun konusudur.

---

## §8. ŞART: güvenilirlik

Hedef değil, şart. Faz değil, her fazın kapısında koşan kısıt. Biri kırmızıysa faz kapanmaz.

1. Fazın kabul betiği yeşil.
2. **Boş yeşil kontrolü.** Fazın eklediği denetim, faz öncesi artefakt üstünde kırmızı düşüyor mu. Düşmüyorsa hiçbir şey ölçmüyordur.
3. Kırmızı **ad** kümesi büyümedi. Sayı değil ad.
4. Eşik, tolerans, ön-kayıt ya da fixture değiştiyse eski değer, yeni değer ve ölçülmüş gerekçe commit mesajında.
5. Ölçüm sevk edilen yoldan alındı: süreç içi mi, gerçek native ikili mi.
6. **UX kapısı.** Fazın ADIM satırı gerçek oldu mu: kaç adımda varılıyor, ekranda ne yazıyor, kullanıcı nasıl kaçıyor. Üçü yazılı değilse kapanmaz.
7. Hakem hükmü GEÇTİ.
8. Kâtibin commit'i var.
9. **SAPMA satırı:** bu faz kullanıcının yolunda hangi adımı gerçek yaptı, hangi sayı gösteriyor, saptık mı.

---

## §9. ROLLER

**ŞEF**, faz başına bir, sonra ölür. Kart keser, işçi salar, kapıyı koşturur, tutanağı ve SAPMA satırını yazar, devir sayılarını bırakır. **Kaynak koda dokunamaz.** Hiçbir şef iki faz yaşamaz.

**İŞÇİ**, faz başına iki ile altı, ayrı süreç. Tek iş, tek kart, seksen satır tavan. Kartın saydığı dosyalar dışında bir şey okumaz, kartın çıktı satırı dışında bir şeye yazmaz. Alt ajan salamaz. Raporu on iki satırda komutla kırpılır.

**HAKEM**, kapı başına bir, temiz oturum. Kartları ve tutanağı okumaz; ne hedeflendiğini değil ne olduğunu okur. Sayıyı kendisi yeniden koşturur. Hüküm tek satır: GEÇTİ ya da KALDI. KALDI derse pazarlık yok.

**KÂTİP**, faz kapanışı başına bir. Yalnız `docs/`, `README.md`, `site/` yazar. Kâtibin commit'i olmayan faz kapanmamıştır.

**TARAFSIZ CEVAPÇI**, çağrı başına bir, temiz oturum.

**Roller işin büyüklüğüyle orantılıdır.** Tek kartlık bir fazda beş rol açmak disiplin değil yavaşlatmadır. Kural şu: **hakem her fazda ayrıdır ve bu asla esnemez**, çünkü işi yapanın kendi işini onaylaması bu projenin can damarı. Şef ve işçi tek kartlık fazlarda aynı oturum olabilir. Kâtip küçük fazlarda ayrı oturum açmaz, şefin son işi olarak koşar. Cevapçı yalnız tetikleyicisi doğduğunda açılır, önlem olarak açılmaz.

---

## §10. TARAFSIZ CEVAPÇI

Soruyu alan oturum cevap **vermez**, taze cevapçı açar, cevabını değiştirmeden uygular. Tetikleyiciler: operatör bir şey sorarsa, "faz kapandı" hükmü gerekirse, "ajan mı öldü faz mı kırmızı" teşhisi gerekirse, iki oturum aynı büyüklük için farklı sayı basarsa (cevapçı iki komutu da yeniden koşturur).

Cevapçının işi A ya da B'yi seçmek değil. Üç adım: hangi değişmez ihlal ediliyor, onu koruyan tasarım nedir, kabul ölçüsü ne. "Dene bak" yok.

**Operatöre giden beş kalem:** para, ürün konumu, dış yayın, sahiplik, geri alınamaz iş. Listede olmayan soru operatöre geldiyse iş boşuna durdurulmuştur; listedeki soru cevapçıda bittiyse yetki aşılmıştır. İkisi de ihlaldir.

**Kuyruk bekletmez.** Her kararın varsayılanı yazılıdır, cevap gelmezse varsayılan yürür ve tutanağa yazılır.

### Cevapçı sonraki fazı değiştirebilir

Fazlar bu belgede yazılı ama **taş değil**. Her faz kapanışında, hakem hükmü düştükten sonra, cevapçı öndeki fazın çıktısına bakar ve sonraki fazın tanımını değiştirebilir. Yetkisi üç şeyle sınırlı:

a) **Kabul ölçüsünü sertleştirebilir.** Gevşetemez. Bir faz beklenmedik bir yoldan geçtiyse ölçü yetersizdir.
b) **Sıra değiştirebilir.** Bir fazın önkoşulu tutmadıysa sonraki faz beklemeye alınır, arkasındaki öne çekilir. Gerekçe yazılır.
c) **Faz ekleyebilir.** Öndeki fazın çıktısı belgede olmayan bir işi zorunlu kıldıysa yeni faz doğar.

Yapamayacağı tek şey: **§1'in hedefini, §3'ün barını ve §4'ün isteklerini değiştirmek.** Onlar operatörün, cevapçının değil.

Değişiklik `reports/kosu/SAPMA-KARARLARI.md`'ye yazılır: hangi faz, ne değişti, hangi çıktı bunu gerektirdi. Amaç hatadan öğrenmek; ölçüyü gevşetmek ödül hacklemektir ve (a) maddesi tam olarak bunu yasaklar.

---

## §11. FRENLER VE YASAKLAR

Aynı ölçüm iki kez tutmadıysa cevapçı optimizasyon değil tasarım değişikliği yazar, üçüncüde operatöre gider. Kesilen işçi kırmızı sayılmaz, hipotezi elenmiş saymaz. Yeni kart denenmemiş bir hipotezi hedefler. Kırmızı zeminin üstüne bir adım daha atılmaz.
İşçi tavanı altmış dakika, faz başına en fazla altı işçi. Şefe dönen tek şey hüküm satırı. Context'i şişiren ajan sayısı değil, ajandan geri okunan metnin boyudur. Ajan sık commit eder, commit'lenmemiş iş sahipsizdir. Aynı dosyaya dokunacak işçiler paralel salınmaz.

**Yasak:** kapıyı gevşeterek geçmek, kırmızıyı sonraki faza taşımak, boş yeşil, hedef yerine vekil denetlemek, testi yeşil için değiştirmek, kabul ölçütünü onu sağlayan kodla aynı commit'e koymak, kirli ölçüme etiket yapıştırmak, ön-kayıtı sonradan değiştirmek, `MIN_HISTORY` ya da `MIN_HITS`'i yeşil için oynatmak, faturada olmamış dünya hakkında sayı, hot-path'te model çağrısı ağ telemetri, ledger'dan türetilmeyen sayıyı kamuya yazmak, satır numarası enjekte etmek, ajana ne yapması gerektiğini söylemek, şefin kod yazması, işçinin alt ajan salması, operatöre teknik soru göndermek, negatif sonucu olumluya çevirmek, yeni CLI verb'ü, sessiz otomatik yazma, sahte demo, boş kovanla launch.

---

## §12. KARARLAR VE VARSAYILANLARI

| karar | varsayılan | ne zaman |
|---|---|---|
| dal düzeni | main'e ileri sarma, worktree'ler kaldırılır, yeni dal açılmaz | F0 |
| disclosure kapısı | yayın kapısı olarak kalır, kırk bir isim sınıflanır | F1 |
| npm publish ve tag | F1 kabulü yeşilken çıkar | F1 |
| ilk dağıtım | F2 yeşilse dağıtılır, dürüst cümleyle | F2 |
| kamuya duyuru | F5 ve F7 kapandıktan sonra, bir kez | F7 |
| fiyat ve tier | ertelenir, kapsam yalnız free bayrağı | F9 sonrası |

Hiçbiri koşuyu bloke etmez.

---

## §13. GECE MODU: operatör uyurken

Operatör ajan doğurup öldürmez. Faz içinde işçileri şef salar ve öldürür. Fazlar arasında **şef ölmeden önce sonraki fazın şefini kendisi başlatır**: ayrı süreç, taze context, kendi manifestosu. Devir dosyadan olur (`DURUM.md`, `ENVANTER.md`, `KAPI.md`), konuşmadan değil.

### Uykuda koşabilen ve koşamayan

**Uykuda koşabilir:** F0, F1b, F2, F3, F4, F5, F9. Bunlar yereldir, geri alınabilir, ve para yakmaz.

**Uykuda koşmaz, operatörü bekler:** para harcayan ve geri alınamaz olan her şey. F1'in npm yayını, F6'nın iki kollu koşusu (sekiz oturum), F7'nin kamuya duyurusu, F8'in dış entegrasyon kararı. Bunlar `reports/kosu/UYANDIGINDA.md`'ye yazılır ve koşu orada durur.

### Durma koşulları, hepsi zorunlu

Gece koşusu şu durumlarda **devam etmez, durur ve dosyaya yazar**:

1. Hakem KALDI dedi. Tekrar denemez.
2. Aynı kırmızı iki kez üst üste. Üçüncüyü denemez.
3. Bir faz kendi kabul ölçüsünü değiştirmek zorunda kaldı.
4. Kırmızı ad kümesi büyüdü.
5. Ortam kartı kırmızı düştü: disk, inode, kilit, credential.
6. Toplam duvar saati tavanı aşıldı.
7. Toplam harcama tavanı aşıldı.
8. `git push` reddedildi.

Durmak başarısızlık değildir. **Sessizce devam etmek başarısızlıktır.**

### Sabah tek dosya

Operatör uyandığında log okumaz. `reports/kosu/UYANDIGINDA.md` okur ve içinde şunlar vardır: hangi fazlar kapandı ve hangi ADIM gerçek oldu, nerede durdu ve neden, bekleyen karar satırları varsayılanlarıyla, ve gecenin SAPMA satırları alt alta.

On satırı geçmez. Geçiyorsa gece iyi geçmemiştir.

### Kısıt

Koşu `main` dalında ve tek kökte yürür (F0 birleştirmesinden sonra). Push serbest, çünkü geri alınabilir; yayın ve duyuru serbest değil. Geçmişe `reset --hard`, dal silme ve zorla push her koşulda yasak.

---

## §14. YÜRÜTME: tek mesaj, sonra operatör yok

Operatör tek bir mesaj atar ve çekilir. O mesajı alan oturum **ORKESTRATÖRDÜR.**

**Orkestratör ince kalır.** Kod yazmaz, kart doldurmaz, faz içeriği okumaz, rapor okumaz, log okumaz. Yaptığı tek şey: fazın şefini doğurmak, ondan tek satır hüküm almak, hakemi doğurmak, ondan tek satır hüküm almak, cevapçıyı doğurmak, ondan sonraki fazın talimatını almak, ve sonraki şefi doğurmak. Context'i bu yüzden şişmez: içine giren şey satırlardır, dosyalar değil.

**Ajanlar doğar ve ölür.** Her faz kendi şefiyle, her şef kendi işçileriyle, her kapı kendi hakemiyle. İşi biten kapanır. Hiçbiri ikinci bir faz görmez.

**Soru ve çıktı tarafsız ajana gider.** Bir şef takıldığında, bir çıktı tartışmalı olduğunda, bir faz kapandığında: orkestratör operatöre sormaz, cevapçıyı doğurur ve onun dediğiyle devam eder. Cevapçı sonraki fazı §10'a göre değiştirebilir.

**Operatöre yalnız iki şey ulaşır:** para ya da geri alınamaz iş kararı (§13), ve sabah `UYANDIGINDA.md`.

### Tek mesaj

Temiz bir Claude Code oturumuna yapıştırılır. Bir kez.

    KOSU-RABADON-5.md repo kökünde. Oku.

    Sen ORKESTRATÖRSÜN. §14'e göre çalış: ince kal, kod yazma, faz
    içeriği ve log okuma. Ajan doğur, tek satır hüküm al, sonrakini
    doğur. Faz şefi, hakem, kâtip ve tarafsız cevapçı ayrı ajanlardır
    ve işi biten ölür. Şablonlar §15'te.

    F0'dan başla ve F9'a kadar sırayla yürüt. Her fazın kapısını §8'e
    göre koştur. Kapı kapanınca cevapçıya sor; sonraki fazı §10'a göre
    değiştirebilir.

    F0'ın ilk kartı ENVANTERDİR: belgeye güvenme, ölç. Hangi sinyal
    kodda var ve çağrılıyor, hangi ajan yüzeyi gerçekten bağlı (kanıt
    ledger satırı olacak), site/index.html hangi ürünü satıyor. Sonuç
    reports/kosu/ENVANTER.md'ye. Sonraki fazlar belgeye değil buna bakar.

    GECE MODU AÇIK (§13). Bana soru sorma, cevapçıya sor. Durma
    koşullarından biri olursa devam etme, dur ve
    reports/kosu/UYANDIGINDA.md'ye yaz. Para harcayan ve geri alınamaz
    işleri uykuda yapma: npm yayını, iki kollu koşu, kamuya duyuru.

    Hedef ürün. Güvenilirlik §8'dedir ve şarttır, hedef değildir.

---

## §15. ŞABLONLAR

Bunlar operatörün yapıştıracağı şeyler değil, **orkestratörün ajan doğururken kullanacağı metinlerdir.**

### 15.1 Faz şefi

    Sen F<n> fazının ŞEFİsin.
    Oku: KOSU-RABADON-5.md §1-§6, §7'deki KENDİ fazının tanımı, §8, §9,
    §11, ve reports/kosu/DURUM.md + ENVANTER.md.
    Başka fazların tanımlarını okuma. Başka belge açma. KOD YAZMA.
    Kart kes (§15.2), işçi sal, işi biteni kapat, kabul betiğini koştur,
    tutanağı yaz, SAPMA satırını yaz, devir üç sayıyı DURUM.md'ye bırak,
    commit + push et.
    Orkestratöre TEK SATIR döndür: F<n>: <bitti|durdu>, <tek cümle>.
    Rapor, tablo, log döndürme.

### 15.2 İşçi kartı

    KART: <ad>
    İŞ: <tek cümle, tek iş>
    OKUYACAKLARIN: <dosya yolları, isim isim. Liste dışı dosya açma.>
    ÇIKTI: <yazacağın yollar. Liste dışına yazma.>
    KABUL: <hangi komut ne basmalı>
    RAPOR: reports/kosu/RAPOR/<ad>.md , yapılan (yol + hash), ölçülen
    (sayı + onu basan komut), yapılamayan (sebep), kart dışı fark
    edilen (dokunma, yaz).
    "Baktım", "doğru görünüyor", "çalışıyor" yasak. Alt ajan salma.
    Sık commit et.

### 15.3 Hakem

    Sen HAKEMSİN. F<n>'in kapı hükmünü vereceksin.
    OKU: fazın çıktı dosyaları, dokunduğu kabul betiğinin kaynağı, iki
    kabul logu (faz öncesi ve sonrası), CLAUDE.md, §8.
    OKUMA: kartlar, şefin tutanağı, fazın niyeti. Ne HEDEFLENDİĞİNİ
    değil ne OLDUĞUNU okursun. Kod yazmazsın, test düzeltmezsin.
    Rapordaki sayıyı kopyalamazsın, KENDİN yeniden koşturursun.
    Sorular: (1) çıktı iddia ettiği şeyi yapıyor mu, yoksa betiği geçmek
    için mi şekillendirilmiş. (2) Fazın eklediği denetim faz ÖNCESİ
    artefakt üstünde KIRMIZI düşüyor mu. (3) Kırmızı AD kümesi büyüdü
    mü. (4) Eşik, tolerans, ön-kayıt ya da fixture değişti mi, gerekçesi
    commit mesajında mı. (5) Ölçüm sevk edilen yoldan mı alındı, gerçek
    native ikili mi. (6) Fazın ADIM satırı gerçek oldu mu.
    reports/kosu/KAPI.md'ye TEK SATIR: GEÇTİ ya da KALDI, tek cümle gerekçe, baktığın dosyalar. Emin değilsen GEÇTİ yazmazsın.

### 15.4 Tarafsız cevapçı

    Sen TARAFSIZ CEVAPÇISIN. Oku: §1, §4, §8, §10.
    İşin A ya da B'yi seçmek DEĞİL. Üç adım: hangi değişmez ihlal
    ediliyor, onu koruyan tasarım nedir (gerekirse seçenek D'yi sen
    yaz), karar ve kabul ölçüsü ve bütçe satırı.
    "Dene bak" yasak. Emin olmadığın teknik iddiayı yazmak yasak;
    bilgin yetmiyorsa cevabın o bilgiyi ÜRETTİRMEKTİR.
    İki ajan aynı büyüklük için farklı sayı bastıysa iki komutu da
    KENDİN koşturup hangisinin geçerli olduğunu söylersin.
    Faz geçişinde sorulduysan: sonraki fazın kabul ölçüsünü
    SERTLEŞTİREBİLİRSİN, sırayı değiştirebilirsin, faz ekleyebilirsin.
    Gevşetemezsin. §1, §3, §4'e dokunamazsın. Değişikliği
    reports/kosu/SAPMA-KARARLARI.md'ye yaz.
    Cevabın kısadır. Operatöre bir şey sormazsın.

### 15.5 Kâtip

    Sen KÂTİPSİN. F<n> kapanışı.
    Oku: fazın tutanağı, fazın git diff'i, docs/ ağacı, README.md, site/.
    Yaz: SADECE docs/, README.md, site/, reports/INDEX.md.
    Koda, native/'e, core/'a, kabul betiklerine DOKUNMA.
    Anayasan: ledger'dan ya da bir testten türetilmeyen sayı yayında
    bulunmaz. Duran iddia yazılmaz; sayıyı basan aletin ADI ve ölçüm
    TARİHİ yazılır. Bayat cümle ya güncellenir ya gerekçesiyle
    docs/archive/'a taşınır, sessiz silme yok.
