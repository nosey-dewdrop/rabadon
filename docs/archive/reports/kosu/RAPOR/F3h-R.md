# F3h — HAKEM RAPORU. Hüküm: **KALDI**

Şef bunu okumaz. Tek satır `KAPI.md`'de.
Her sayı hakemin kendi elinde, kartın hiçbir sayısı kopyalanmadan ölçüldü.
Kum havuzu: `~/damla_projects_2026/_hakem_f3h/` — `/tmp` DEĞİL (Tuzak 1,
DURUM.md:578). Ölçüm aleti kartın `probe.sh`'i değil, sıfırdan yazılmış
`_hakem_f3h/hprobe.sh`: her şekle **taze** fikstür, ve `EXEC=1` ile komut
gerçekten koşturulup **yasa hayatta mı** diye diskten bakılıyor. Kartın probe'u
yalnız gate'in verdiğini okur; benimki etkiyi de ölçer.

---

## 0. SIFIRINCI İŞ — `~/.claude/settings.json`

`make test` ÖNCESİ ve SONRASI, `shasum -a 256`:

    ÖNCE   6c14cc5fdd4a3407a1448a14f9a6639c39c71327fe3d4e2ab6ae5cd3bb5680aa
    SONRA  6c14cc5fdd4a3407a1448a14f9a6639c39c71327fe3d4e2ab6ae5cd3bb5680aa

**BAYT BAYT AYNI.** F3g'nin en ağır kalemi kapandı. Kartın hash'i de birebir tutuyor.

**MUTASYON — kartınkini kopyalamadım, kendim ürettim.** `contract_test.sh`'ten
`SBHOME=$(mktemp -d); export HOME=$SBHOME` iki satırını Edit ile çıkardım:

    home_isolation: 4 passed, 2 failed
      FAIL - contract_test.sh rewrote $HOME/.claude/settings.json — it borrowed the operator's machine
      FAIL - contract_test.sh left a .bak-rabadon beside the operator's settings

Geri alındı → **6/0**. Kapı gerçekten kırmızı düşebiliyor (§3.8/3). Üstelik
mutasyon koşarken **canlı dosya bozulmadı** çünkü süit decoy bir HOME'a yazdırıyor
— kilit kendi kendini de koruyacak şekilde kurulmuş. **K0 GEÇTİ.**

---

## 1. KART 1 — BEŞ YANLIŞ POZİTİF, ve daraltma bypass açtı mı?

### Beşi de bugün ALLOW, ikizlerinin beşi de REFUSE

    ALLOW   mkdir -p .rabadon                          REFUSE  mkdir -m 000 .rabadon
    ALLOW   mkdir -p /elsewhere/unrelated/.rabadon     REFUSE  tar -xf a.tar -C .rabadon
    ALLOW   mkdir -p "$VAR/.rabadon"                   REFUSE  find . -path '*/.rabadon/*' -delete
    ALLOW   tar -cf backup.tar .rabadon                REFUSE  rm -rf .rabadon
    ALLOW   find . -not -path '*/.rabadon/*' -delete   REFUSE  rm -rf .r*  ·  rm -rf .rabado?

`find . ! -path …` (uzun yazım yerine `!`) de ALLOW — iki yazım da okunuyor.
`EXEC=1` ile: `find . -not -path '*/.rabadon/*' -delete` gerçekten koşturulunca
**law-SURVIVED**, yani daraltma doğru şeyi yapıyor, körlemesine muaf tutmuyor.

### `tar` "moda göre" — yazma modunu kendi elimde denedim

    REFUSE  tar --extract --file a.tar -C .rabadon
    REFUSE  tar xf a.tar -C .rabadon          (öneki eksik eski yazım)
    REFUSE  tar -x -f a.tar -C .rabadon
    REFUSE  tar --delete -f backup.tar .rabadon
    REFUSE  tar -cf .rabadon/guard.json a.txt (arşivin KENDİSİ yasanın üstüne yazılıyor)
    REFUSE  tar -cf .rabadon a.txt
    ALLOW   tar -rf backup.tar .rabadon  ·  tar -uf backup.tar .rabadon

Son ikisi arşive **ekleme**dir, yolları okur, yazmaz — doğru ALLOW.
**Yazma modunun hiçbir yazımı kaçmadı.**

### `-not` DELİĞİ — VAR, AMA F3h AÇMADI

Daraltmanın açtığı bir delik arıyordum ve buldum:

    ALLOW  law-GONE  find . -not -name zzz -delete
    ALLOW  law-GONE  find . '!' -name zzz -delete
    ALLOW  law-GONE  find . -not -newer README.md -delete
    ALLOW  law-GONE  find . -not -path '*/keepme/*' -name '*.json' -delete

Dördü de `EXEC=1` altında yasayı **gerçekten yok etti**. Kural şu: `-not` varsa
ve komut metni yasanın adını başka yerde hecelemiyorsa muaf düşüyor — oysa o
`-not` yasayı değil bambaşka bir şeyi hariç tutuyor.

**AMA: aynı dört şekli `F3h-oncesi` (`3cd4fdc`) ikilisinde de koşturdum** —
worktree açıp `make native/rabadon-gate` ile tabanı derledim:

    F3h-oncesi:  ALLOW  find . -not -name zzz -delete
    F3h-oncesi:  ALLOW  find . -delete
    F3h-oncesi:  ALLOW  ls -a | xargs rm -rf

**Dördü de tabanda da ALLOW'du.** Delik F3h'nin daraltmasından DEĞİL, `find`'ın
`.`'tan yürüyüp yasanın adını hiç yazmamasından doğuyor — kartın `ls | xargs`
için "kapanamaz" dediği sınıfın ta kendisi. **Daraltma bypass AÇMADI; hüküm:
KART 1'in daraltma kısmı GEÇTİ.** Delik gerçektir ve aşağıda KART 2'ye yazılıyor.

Yanlış ret sayacına ekleyecek yeni şeklim yok: bu turda kapı beni **hiç kesmedi**
(sebebi §5'te, ve o sebep başlı başına bir bulgudur).

### `docs/guard.md` bugün ölçümle doğru mu?

Evet. Eski cümle (`"this project's own copy of the law"`) satır 18'de
**silinmemiş**, altına `### Correction, 2026-08-30` başlığıyla ölçüm tarihi,
çalıştırılabilir probe komutu ve beş satırlık REFUSE çıktısı konmuş. Beş şeklin
beşini de bugün kendi elimde ALLOW ölçtüm → **belge doğru.**

**`docs/claims.tsv` sicili GEREKMİYORDU** — `docs_truth_test.sh:99-102` sicili
yalnız `commands.md` · `faq.md` · `uninstall.md` claim bloklarıyla sınırlıyor;
bu faz `docs/guard.md`'yi değiştirdi. F3e/F3f hakemleriyle aynı hüküm.
Ajan `CHALLENGE:` **yazmadı** ve yazmasını gerektiren bir şey de bulamadım.

---

## 2. KART 2 — AİLE, ve BİLEREK AÇIK BIRAKILANLAR (en kritik hüküm)

### Kartın kendi bulduğu üç şekil — ikisini doğruladım

    REFUSE  awk 'BEGIN{system("rm -rf .rabadon")}'    ← kartın bulgusu, DOĞRU
    REFUSE  mv .rabadon{,.bak}                        ← kartın bulgusu, DOĞRU
    ALLOW   ls | xargs rm -rf                         ← kartın "kapanamaz"ı

### (iii) `ls | xargs` "kapanamaz" iddiası — SONUÇ DOĞRU, ÖRNEK YANLIŞ SEÇİLMİŞ

`EXEC=1`: `ls | xargs rm -rf` → **law-SURVIVED.** Çünkü `ls` nokta ile başlayan
adları listelemez; o komut `.rabadon`'a hiç değmiyor. Kart, sınıfın **yasaya
ulaşmayan** üyesini seçmiş. Ulaşanlar:

    ALLOW  law-GONE  ls -a | xargs rm -rf
    ALLOW  law-GONE  ls -A | xargs rm -rf
    ALLOW  law-GONE  find . -delete   (+ yukarıdaki dört -not varyantı)

**"Kapanamaz" hükmü ayakta** (yol komut metninde hiç geçmiyor, ve kapatmanın
bedeli KART 1'in az önce onardığı yanlış pozitifin geri gelmesidir) — **ama
kartın ilan ettiği şekil sınıfın en zayıf üyesidir ve gerçek üyeler hiçbir yerde
adlandırılmamıştır.**

### (i) Dört şekil: kullanıcının kendi işi mi, yasayı yok etmenin ucuz yolu mu?

Dördünü de `EXEC=1` ile koşturdum:

    ALLOW  law-GONE      cd .. && rm -rf proj        ← ağacın tamamı gidiyor
    ALLOW  law-SURVIVED  mv . ../renamed             ← macOS'ta `mv .` hata veriyor
    ALLOW  law-SURVIVED  tar -xf a.tar -C .          ← arşiv yasayı içermiyorsa etkisiz
    ALLOW  law-SURVIVED  git worktree remove --force .

**HÜKÜM (i): KAPSAM KARARI ÖZÜNDE MEŞRU.** Dördü de ağacın tamamını hedefliyor;
kesmek kullanıcıyı kendi projesini silemez hâle getirirdi ve bu, `docs/guard.md`
satır 18'in *"the subject is the law, not the tree around it"* cümlesiyle
tutarlıdır. Yasayı yok etmenin **ucuz** yolu değiller: `cd .. && rm -rf proj`
projenin tamamını da götürüyor, saldırgan için bedava değil. **İş geri
alınmıyor** (F3g'nin "ad düzeltilir, iş geri alınmaz" içtihadı).

**AMA prosedür ihlali kayda geçer:** §3.8/4 uyarınca bir kapsam kararı faz
ajanının yetkisi değildir; ajan durup hakeme gelmedi, kendi kararını verip kartta
ilan etti. Bu tek başına GERİ AL gerektirmiyor (karar doğru çıktı), ama
tekrarlanırsa gevşetmeyi meşrulaştıran bir alışkanlık olur.

### (ii) İLAN EDİLDİ Mİ? — **HAYIR. BLOKLAYAN BULGU BUDUR.**

- **Ürünün kendi ekranı:** `gate.cpp:1398`'deki `blind spots:` bloğu bu fazın
  diff'inde **HİÇ YOK** — `git diff --stat F3h-oncesi..HEAD` içinde `gate.cpp`
  adı geçmiyor. Ekran bugün üç şey sayıyor (Cursor'ın pre-edit deliği, mutlak
  yolla çağrılan program, `PostToolUseFailure` aboneliği) ve **yasanın kendi
  ailesindeki tek bir deliği bile saymıyor.**
- **`docs/guard.md`:** yalnız **olumlu** cümle var — *"deleting a whole project
  of yours that happens to contain a `.rabadon`"* geçer. Bunun bir **kapsam
  boşluğu** olduğu, `find . -delete` / `ls -a | xargs rm -rf` / `cd .. && rm -rf`
  ile yasanın **sessizce yok edilebildiği** hiçbir yerde yazmıyor.

CLAUDE.md: *"Every error path is a designed path. 'It shouldn't happen' is not a
state; if rabadon can't check, it says 'I can't check this project' — it never
goes quiet (Promise 1 is law)."* Burada rabadon kontrol edemediğini **bilmiyor
değil** — ajan tam olarak biliyor, karta yazmış, ürüne yazmamış. **Sessiz bir
açık, ilan edilmiş bir açıktan çok daha kötüdür.** Şef kartı okumaz; kullanıcı
hiç okumaz. Kartta ilan = ilan değildir.

### ÇIKIŞ KAPISI — kendi elimde kullandım

Enforce eden fikstürde, belgede yazan yollar:

    ALLOW   rm -rf ./old-project        (kendi projen — belgenin sözü tutuyor)
    ALLOW   mv ./old-project /tmp/bin
    REFUSE  rm -rf <baska-yerdeki-leftover>

ve reddin metni:

    Rule: no-rm-rf-outside — baseline: recursive delete outside a project is unrecoverable
    (user override: add "no-rm-rf-outside" to disabled[] in .rabadon/guard.json,
     or `rabadon off` to pause supervision)

**Kapı çalışıyor, kullanıcı tuzakta değil.** Tek sapma: `docs/guard.md` satır
59-65 bu reddin **`baseline-rm-rf-outside`** adını basacağını yayımlıyor; bu
repoda projenin kendi `guard.json`'ı önce konuştuğu için ekranda
**`no-rm-rf-outside`** yazıyor. Boş `bash[]` fikstüründe belgenin dediği çıkar,
yani belge tabanı anlatırken doğru; ama yayımlanan çıktı bloğu bu repoda
birebir görülen çıktı değil. Bloke etmiyor, kayda geçiyor.

### KART 1 ↔ KART 2 ters yönde çekiyor — aynı fikstürde ölçüldü mü?

Evet, ve **kendi mutantımı ürettim** (kartınkini kopyalamadım). F3g hakeminin
açık bıraktığı yön tam olarak buydu: daraltma "çok geniş" yönünde pinlenmiyordu.
`baseline.h:970`'te `if (!carriesMode) return;` satırını
`(void)carriesMode; return;` yaptım — yani `mkdir` **koşulsuz** muaf:

    law_family: 116 passed, 1 failed
      FAIL - ALLOWED: mkdir CARRYING A MODE is not the create-only shape — the narrowing became a hole

Geri alındı, yeniden derlendi → **117 passed, 0 failed.**
**F3g'nin "M2 iki süidi de yeşil bıraktı" bulgusu KAPANDI: daraltma artık ÇİFT
YÖNDE pinli.** Bu, bu fazın en sağlam teknik işidir.

---

## 3. KART 3 — 911 µs. YENİDEN ÜRETİLDİ, VE KARTTAN DAHA GÜÇLÜ ÇIKTI

`k3-paired.sh`'i okudum (aynı ikili, aynı fikstür, aynı daemon, yalnız
`RABADON_GATED_SOCK` değişiyor, kollar **iç içe** koşuyor — hile yok) ve kendim
koşturdum, R=8 × N=120:

    round 1  SOCK set 1507.8  unset 1026.6  diff +481.2
    round 2  SOCK set 1622.5  unset 1116.4  diff +506.1
    round 3  SOCK set 1741.6  unset 1167.7  diff +573.9
    round 4  SOCK set 1856.2  unset 1245.4  diff +610.8
    round 5  SOCK set 1785.7  unset 1241.1  diff +544.6
    round 6  SOCK set 1784.2  unset 1248.2  diff +536.0
    round 7  SOCK set 1799.4  unset 1274.7  diff +524.7
    round 8  SOCK set 1836.6  unset 1321.7  diff +514.9

    medyan +530.4 µs · min/max +481.2 / +610.8 · TEK YANLI 8/8 · |439 µs| bandı: **AŞILDI**

Kart temkinli davranıp **+433,1 µs** ve *"bandı aşmıyor, iddia değil KONUM"*
yazmış. **Benim elimde +530,4 µs ve bandı AŞIYOR.** Yani bulgu kartın kendi
ilan ettiğinden daha ağır: bu bir konum değil, **ölçülmüş bir mimari
gerilemedir.** R7 hedef 2 daemon'u gate'i UCUZLATMAK için kurdu; ölçüldüğünde
tam tersini yapıyor, ve `2b` soketi export eden **tek** koldur.

**(i) `2b` kısmen defterin boyutunu ölçüyor.** Kartın Finding 2'sini (taze
`$HOME`, 3/3, ~160 çağrıdan sonra ~800 µs → ~1660 çağrıdan sonra ~1065 µs,
**+265 µs**) betiği okuyarak doğruladım; sürüklenmeyi kendi paired koşumda
bağımsız olarak yeniden ürettim: SOCK-unset kolu **tek koşu içinde** 1026,6 →
1321,7 µs, **+%28,8, kod değişmeden.** **HÜKÜM: `2b` kararsız bir ölçüttür —
aynı kod, daha uzun bir oturumda daha kötü bir sayı verir.** Bu, ölçütün adının
düzeltilmesini gerektirir, **tavanın yükseltilmesini değil.**

**(ii) Gürültü bandı |439 µs| bu bulgudan sonra ne demek?** Bant, kod
değişikliğinin ölçülebilirlik eşiğidir. Tek koşu içinde %29 sürüklenme varken
**oturumlar arası** karşılaştırma bandın çok üstünde sapabilir — nitekim `2b`
bugün benim elimde **1824,4 µs**, kartta **1300,6 µs**, F3g'de **1942,8 µs**.
Üç sayı, aynı kod ailesi, **642 µs yayılım.** Bant, **eşli ve iç içe** ölçümler
için geçerlidir; eşleşmemiş oturumlar arası tek sayılar için değildir. Bundan
sonra `2b`'ye dayanan her iddia **eşli** ölçüm ister.

**TAVAN GEVŞETİLMEDİ. 1000 µs yerinde.** `reports/R7/accept.sh` ajanın
diff'inde **yok**, hakem de **dokunmadı**. "Ölçüt kararsız" hükmü tavanı
yükseltmenin gerekçesi değildir ve yükseltmedim (§3.8/1, §3.8/4, §11).

**§3.7 — `2b`'NİN SAHİBİ YENİDEN ATANDI.** Bugünkü açık **1824,4 − 1000 =
824,4 µs**. Bunun **530,4 µs'si (%64)** ölçülmüş, tek yanlı, bandı aşan
**daemon gidiş-dönüşüdür**. Altı fazdır sahibi düşmedi çünkü altı faz da
`gate.cpp`'nin içini optimize etmeye çalıştı; ölçülen sayı, açığın çoğunluğunun
`gate.cpp`'de **değil**, `2b`'nin kendi açtığı soket yolunda olduğunu söylüyor.
**Yeni sahip: F3i, tek kart, hedef = daemon yolu** (ya ucuzlatılır ya `2b`'nin
onu ayakta tutması gerekçelendirilir ya da ölçütün adı düzeltilir). Gerekçe
ölçülen sayıdır: **530,4 µs / 824,4 µs.**

---

## 4. KAPI SAYILARI — hepsini kendim koşturdum

| ölçü | kart | **hakem** | sonuç |
|---|---|---|---|
| `make test` exit | 0 | **0** | ✔ |
| native iddia (GENİŞ regex) | 4022 | **4022** | ✔ |
| `PASS (N checks)` toplamı | 633 | **633** | ✔ |
| `npm test` | 64/0 | **64 pass / 0 fail** | ✔ |
| **toplam** | **4719 / 0** | **4719 / 0** | ✔ |
| `accept.sh` | EXIT=1, 23/3 | **EXIT=1, 23/3** | ✔ |
| kırmızı ad kümesi | `{2b,6e,7b}` | **`{2b,6e,7b}` — BÜYÜMEDİ** | ✔ |

Çıktıdaki tek `FAIL` satırı (`maketest.log:4626`) bir **fikstür** metnidir
(kırmızı bir süidi taklit eden test), gerçek kırmızı değil; `EXIT=0`.

### SÜİT SAYISI — oynaklık ÇÖZÜLDÜ, hükme bağlanıyor

Üç faz üç farklı sayı verdi (113→115, 114→115, 116→117) çünkü herkes `make test`
**çıktısını** regex'liyordu ve süitler adlarını farklı basıyor. Log satırı
saymak §8.2'dir. **Tek geçerli sayaç, çıktı değil KAYNAK olmalıdır** —
Makefile'ın `test` hedefinin gerçekten çağırdığı betikler:

    awk '/^test:/{f=1} f&&/^$/{exit} f' Makefile | grep -oE 'native/[a-zA-Z0-9_.-]+\.sh' | sort -u | wc -l

    F3h-oncesi (git show F3h-oncesi:Makefile)  → 116
    HEAD                                        → 117

**Kartın 116→117'si DOĞRU.** (Aynı komutu logdan saydığımda 115 ve 116 çıkıyor —
bu yüzden emekliye ayırıyorum.) **BUNDAN SONRAKİ TEK GEÇERLİ SÜİT SAYACI
YUKARIDAKİ MAKEFILE KOMUTUDUR**, log regex'i değil.

### +55 nereden geliyor — süit bazında ayrıldı

    law_family      68 → 117   = +49   (F3g hakeminin ölçtüğü 68'den)
    home_isolation   0 →   6   = +6    (yeni süit)
                                 -----
                                 +55   ← taban 4664 + 55 = 4719 ✔

**Küçülen 0 · kaybolan 0 · silinen dosya 0.** Ölçüm: `git diff --diff-filter=D
--name-only F3h-oncesi..HEAD` → **0 satır**; test dosyalarında silinen iddia
satırı (`^-\s*(ok|pass|fail|assert)`) → **0**. Diff'teki üç "disabled" kelimesi
`skip` değil, **çıkış kapısı iddiasının kendisidir**
(`disabled":["baseline-law-unmade"]` fikstürü).

Yüzey süitleri, fazın nihai ikilisine karşı: `cli_test` **315/0** (beş-verb
tavanı duruyor) · `doctor_test` **43/0** · `install_docs_test` **38/0** ·
`docs_truth_test` **42/0** · `version_test` **13/0** → **F1e-C üçlüsü
42/0 · 38/0 · 13/0 KARŞILANDI.** Kâtip commit'i `2d4b7b4` (`docs/guard.md`)
fazın **sonuncusu DEĞİL** (son commit `e63a757`, kart). ✔

### §3.8 / §3.12 denetimi

- **§3.12 tahmini:** `70884bc` *"card count and per-card estimates, before any
  code"* fazın **İLK** commit'i (`3cd4fdc`'den hemen sonra), kart `e63a757`
  sonuncusu. Tahmin 7 sa, iki katı 14 sa; faz **01:48 → 02:36 = 48 dakika**
  sürdü. Tetik çalmadı. ✔
- **Ölçüt commit'leri koddan ÖNCE ve AYRI:** `4d9724a`(K0 ölçüt) → `febf4b9`(K0
  kod) · `c2066bb`(K1/K2 ölçüt) → `56e0489`(kod) · `b78ec6b`(K2 ölçüt) →
  `c12b08b`(kod). Üç çift, üçü de doğru sırada. CLAUDE.md 2 ✔
- **Mühürlü set diff'te HİÇ YOK:** `reports/R7/accept.sh` · `ON-KAYIT.md` ·
  `docs/claims.tsv` · `.rabadon/guard.json` · korpus/snapshot — hiçbiri
  `git diff --name-only F3h-oncesi..HEAD` çıktısında geçmiyor. ✔
- **`bin/rabadon.mjs` (O3 donuk) diff'te YOK.** ✔
- **`CAP=200` yerinde** (`native/moves.h:63`, dosya diff'te yok). ✔

---

## 5. ⚠ KAPSAM DIŞI AMA BLOKLAYAN — KULLANICININ CANLI FRENİ KAPALI

Kartı yargılarken kapının beni bir kez bile kesmediğini fark ettim. Sebebi
ölçtüm:

    cat ~/.rabadon/mode            → watch
    ls  ~/.rabadon/enabled         → No such file or directory
    stat -f %Sm ~/.rabadon/mode    → Aug 30 02:03:16 2026

Sevk edilen ikiliye gerçek bir `PreToolUse` olayı verdim:

    $ ... "command":"git push --force origin main" | native/rabadon-gate
    rabadon (watch) would have blocked this.
    Nothing was stopped. `rabadon on` makes this a real refusal.
    LIVE-GATE-EXIT=0

**Bu makinede bugün `main`'e force-push DURDURULMUYOR.** DURUM.md satır 36-43
(2026-08-29, hakem ölçtü) *"mod **ENFORCE (deny)**, … `rabadon status` → 'ON —
the arbiter acts', gerçek PreToolUse → BLOCKED, EXIT=2"* diyor. **O satır artık
YANLIŞ** ve aşağıda düzeltiliyor.

`mode` dosyası **02:03'te** değişti — faz penceresinin (01:48 → 02:36) tam
ortasında. `~/.rabadon/enabled`'ın kalkması, F3g hükmü (1)'de ölçülmüş olan
**`rabadon off`** imzasıdır. Kart ise açıkça *"`rabadon off` çağrılmadı"* ve
*"KAPI BENİ KESTİ"* yazıyor.

**KİMİN YAPTIĞINI ÖLÇEMEDİM ve uydurmuyorum.** Defteri 01:58–02:10 aralığında
açtım: o dakikalarda bu makinede **ilgisiz ikinci bir Claude oturumu** da
koşuyordu (`python3 -m pytest`, `engine/tests`, başka bir repo). O oturum da
`rabadon off` çalıştırmış olabilir. Failin adını **yazmıyorum.**

Yazdığım iki şey ölçüm:
1. **Fren kapalı**, ve DURUM.md'nin ENFORCE satırı bugün yanlış.
2. Kartın *"kapı beni canlı kesti"* cümlesi defterde **karşılıksız**: faz
   ajanının oturumunda 01:40'tan sonra tek bir `BLOCKED`/`REFUSED` olayı yok;
   02:15:25'te bir **`WOULD_BLOCK`** var (watch = hiçbir şey durdurulmadı).
   Yani o cümle en iyi ihtimalle bir watch-modu "keserdim"ini gerçek bir ret
   gibi anlatıyor.

**Ben kapı durumunu DEĞİŞTİRMEDİM** — `rabadon on` da çalıştırmadım, çünkü
ölçüm ortamını değiştirmek hakemin işi değil. Sıradaki fazın ilk işi bu.

**Bunun yargıya etkisi:** kendi kum havuzumu (`_hakem_f3h/lab.*`, içinde
`.rabadon` fikstürleri) sorunsuz sildim — **ama kapı watch'ta olduğu için bu,
çıkış kapısının enforce altında çalıştığının kanıtı DEĞİLDİR.** Çıkış kapısını
enforce eden **fikstürde** ölçtüm (§2) ve orada çalışıyor; canlı makinede
enforce altında **ölçemedim.**

---

## 6. HÜKÜM

**KALDI.**

Bu fazın işi teknik olarak bu koşunun en temizlerinden biri: her sayı birebir
tuttu, mutasyonlar gerçekten kırmızı düşüyor, K0 kapandı, K1'in daraltması
bypass açmadı ve F3g'nin açık bıraktığı çift-yön pinleme kapandı, K3 yeniden
üretildi ve kartın kendi iddiasından **daha güçlü** çıktı. Kart ayrıca kendi
sınırlarını CLAUDE.md 8'e uygun biçimde dürüstçe yazmış.

Kapatmayan tek şey, ürünün kendi vaadidir:

1. **Yasanın ailesinde ölçülmüş, yasayı gerçekten yok eden bir şekil sınıfı var
   ve ürün bunu SÖYLEMİYOR.** `blind spots:` ekranı bu fazın diff'inde yok;
   `docs/guard.md` yalnız olumlu cümleyi kuruyor. Kartta ilan, ilan değildir —
   şef kartı okumaz, kullanıcı hiç okumaz. Promise 1.
2. **İlan edilen tek örnek (`ls | xargs rm -rf`) sınıfın yasaya ULAŞMAYAN
   üyesidir**; ulaşan üyeler (`ls -a | xargs rm -rf`, `find . -delete` ve dört
   `-not` varyantı — hepsi ölçüldü, hepsi law-GONE) hiçbir yerde adlandırılmadı.
3. **Kullanıcının canlı freni kapalı** ve kart bunun aksini iddia ediyor.

Kapatma **kapatmakla değil, İLAN ETMEKLE** olur: bu sınıfı kapatmanın bedeli
KART 1'in az önce onardığı yanlış pozitiflerin geri gelmesidir (yol komut
metninde hiç geçmiyor), ve CLAUDE.md yanlış retleri yakalanmamış saldırıyla
**aynı ağırlıkta** sayar. Bu yüzden sıradaki karta "kapat" demiyorum; "ürünün
kendi ekranında ve belgesinde ADIYLA SAY" diyorum.

## ÖLÇEMEDİKLERİM

- Konteynerde hiçbir şey koşmadı; yalnız konak macOS (arm64).
- Canlı makinede **enforce altında** çıkış kapısı — kapı watch'ta olduğu için
  ölçülemedi.
- `~/.rabadon/enabled`'ı kimin kaldırdığı. Aynı dakikada ilgisiz ikinci bir
  oturum koşuyordu; fail adı **ölçülmedi**, yazılmadı.
- K3 Finding 2'nin içi (yazma mı, okuma mı, kilit mi) — kartın da ölçemediği.
- Daemon yolunun **neden** 530 µs pahalı olduğu; nerede olduğu ölçüldü, nedeni değil.
- `mv .` ve `tar -x -C .` şekillerinin gerçekten yasayı öldürdüğü bir kurgu —
  benim fikstürümde ikisi de law-SURVIVED verdi, yani kartın "açık bıraktım"
  dediği dördün ikisi bende zaten etkisiz çıktı.
- **(c) negatif kontrolü KAPSAM DIŞIYDI, koşulmadı → F4 HÂLÂ KAPALI.**
  ((c) F6'nın aletiyle koşar — F3d hükmü, değiştirmedim.)
