# SAPMA KARARLARI — koşu 5

Cevapçının §10 yetkisiyle aldığı faz değişiklikleri. Her kalem: hangi faz,
ne değişti, hangi ÖLÇÜM bunu gerektirdi. Ölçü sertleşir, gevşemez (§10a).
§1, §3, §4 dokunulmaz.

---

## 2026-08-26 · F0 kapanışı sonrası · F1'in bölünmesi ve sertleştirilmesi

Soru: F1 gece modunda (§13) nasıl koşulur, ya da koşulmaz mı?

### 1. Hangi değişmez risk altında?

İki tanesi, aynı anda:

- **§13 / gece modu.** F1'in yazılı KABUL'ünün ilk maddesi
  `npm view rabadon version` sayı döndürüyor. Bu madde ancak `npm publish`
  ile yeşile döner: para değil ama **geri alınamaz** (npm'de bir sürüm
  yayımlandıktan sonra unpublish penceresi dar, isim kalıcı olarak
  sahiplenilir) ve **sahiplik** kalemidir. §13 bunu açıkça uykuda
  koşmaz listesine yazar. Yani F1 yazıldığı haliyle **bu gece kapanamaz**.
- **§4.10 "Yüzey beştir, geri şişirilmez."** ÖLÇÜM: yüzey zaten beş
  (`./native/rabadon-cli.sh --help` → `init`, `on|off`, `usage`, `repair`,
  `doctor` + `version` + `dev`; `dev --help` → 30 verb; exit 0). Ama
  `native/cli_test.sh` (310 ok / 0 fail) yalnız **keşfedilebilirliği**
  denetliyor — "her verb iki ekrandan birinde listeli" — **tavanı
  denetlemiyor.** Ana ekrana altıncı satır eklense hiçbir test kırmızı
  düşmez. Yani §4.10 bugün kırmızı düşebilen bir denetime bağlı DEĞİL.
  Bu bir boş yeşildir (§8.2).

Üçüncü, daha sessiz olan: **disclosure kapısı bugün CI'ı kırmızı tutuyor
ve kimse bunu ölçmemişti.** `gh run view 32922500561` (F0 kapanış
commit'i, 26.08 02:22): `ubuntu-latest` YEŞİL 5m56s, `macos-15` YEŞİL
6m18s, `disclosure ubuntu-latest` ve `disclosure macos-15` **KIRMIZI**.
`make disclosure` yerelde de kırmızı: **53 isim bulundu, 12 izinli,
41 liste dışı.** Liste dışı 41 ismin tamamı operatörün kendi
projelerinin adı (`youkiddingme`, `icerik`, `seviyorsevmiyor`,
`ir-globe`, `parmakestra`, `damla_portfolio`, `psikoloji-kitabi`, …).
**Hangi ismin kamuya çıkacağı cevapçının kararı değildir** (§10,
operatöre giden beş kalem: sahiplik + dış yayın).

### 2. Onu koruyan tasarım — SEÇENEK D

F1 ikiye bölünür. Kabul maddesi **gevşetilmez, taşınır** (§10b, sıra
değişikliği). Ve bölünmeden doğan boşluk daha SERT bir ölçüyle kapatılır.

**F1a — kurulabilir ürün, yayımlanmamış.** Uykuda koşar. Yerel, geri
alınabilir, para yakmaz.

**F1n — yayın.** `npm publish` + `v0.2.3` etiketi + `@rabadon` scope +
`NPM_TOKEN`. Uykuda KOŞMAZ. F1'in yazılı KABUL maddesi
`npm view rabadon version` sayı döndürüyor **aynen buraya taşınır**,
tek kelimesi değişmeden. F1n'in önkoşulu F1a'nın kapanmasıdır.

**SERTLEŞTİRME (§10a).** `npm view rabadon version` sayı döndürmesi zayıf
bir ölçüdür: bozuk bir paket de sayı döndürür. F1a bunun yerine, ondan
daha zor olanı kanıtlar — **yayımlanacak yol, yayımlanmadan önce temiz
makinede kurulup çalışır.** `native/npm_install_test.sh` tarball'ları
paketleyip temiz bir prefix'e kuruyor ve `make test` içinde koşuyor;
F1a bunu CI matrisinin **her hücresinde** koşturur. F1n yayımladıktan
sonra `npm view` maddesi ayrıca aranır. İki ölçü birbirinin yerine
geçmez, üst üste biner.

### 3. KARAR

**SIRADAKİ FAZ: F1a.** Bu gece koşar.

**F1a KABUL (hepsi zorunlu, hepsi yerel/geri alınabilir):**

1. **Yüzey tavanı kırmızı düşebilir hale gelir.** `--help` ana ekranında
   listelenen ürün verb'ü sayısı **beş** (+`version`, +`dev`); altıncısı
   eklenince test KIRMIZI düşer. Boş yeşil kontrolü (§8.2): denetim
   yazıldıktan sonra ana ekrana kasten altıncı satır eklenir, testin
   kırmızı düştüğü loglanır, satır geri alınır. Bugünkü 30 `dev` verb'ü
   ve `cli_test.sh`'in 310 ok'u düşmez.
2. **Disclosure kapısı KAPATILARAK geçilir, gevşetilerek değil.**
   `make disclosure` exit 0. Yol: **varsayılan saklamaktır** — liste
   dışı 41 isim artefaktlarda `(withheld)` olarak yeniden üretilir
   (mekanizma zaten var: `site/redact.py`, `site/field_stats.py`,
   `(withheld)` allowlist'te izinli). **`site/published-projects.txt`'e
   operatör kararı olmadan tek isim eklenmez.** Boş yeşil kontrolü:
   saklama geri alınınca kapı yeniden kırmızı düşer.
3. **`rabadon doctor` dört hata sınıfını adıyla yakalar.** Node sürüm
   uyumsuzluğu, ikili izin sorunu, PATH çakışması, eski kurulum
   kalıntısı. Dördü de fixture'da **kasten üretilir**; doctor her birinde
   (a) ne olduğunu, (b) neden, (c) insanın koşacağı **tek komutu** basar
   (§4.8). Sınıf ele alınmamışsa test kırmızıdır. Bugünkü doctor bu
   dördünü kontrol etmiyor (ölçüm: `rabadon doctor` → 6 satır: ikili
   sayısı, sürüm, sandbox, claude CLI, hook, ledger).
4. **Kurulum matrisi CI'da, dört hücre.** `ci.yml` bugün 2 işletim
   sistemi × **1 Node sürümü** (`node-version: '22'`). İkinci sürüm
   eklenir ve **`20` seçilir**, çünkü `release.yml` yayını Node 20 ile
   yapıyor (`release.yml:102,142`) — yani yayımlanan yol test edilen
   yol olur. Dört hücrenin dördünde `make all && make test && npm test`
   yeşil, `npm_install_test.sh` dördünde de koşmuş.
5. **CI main'de tamamen yeşil.** Kanıt rapordan kopyalanmaz:
   `gh run view <id>` çıktısı tutanağa yapıştırılır. Bugünkü hali
   kırmızıdır ve kırmızı zeminin üstüne adım atılmaz (§11).
6. **Kurulumdan çalışır guard'a kaç adım.** Sayı ölçülür ve yazılır.
   İki komut iddiası ölçülmeden yazılmaz.
7. **Ajan yüzeyi tablosu ölçüme dayanır.** Cursor için "destekleniyor"
   yazılmaz; ENVANTER (b) ölçümü **0 ledger satırı** diyor, tabloya
   satır satır ne yapıp ne yapamadığı ve bu sıfır yazılır (§4.11).

**F1a'nın KAPSAM DIŞI bıraktığı (F1n'e taşındı):** `npm publish`,
`v0.2.3` etiketi, `@rabadon` org'u, `NPM_TOKEN`, `npm view rabadon
version`, plugin paketinin yayını, sitedeki kurulum satırının
`npm i -g`'ye çevrilmesi (kâtip bunu F1n kapandıktan sonra yazar; bugün
yazarsa site çalışmayan bir kurulum satırı satar).

**BÜTÇE (§11):** F1a en fazla **5 işçi**, işçi başına 60 dakika tavanı,
paralel salınan işçiler aynı dosyaya dokunmaz — kart 2 (`site/`) ile
kart 4 (`.github/workflows/`) paralel, kart 1 (`native/cli_test.sh`) ile
kart 3 (`native/doctor*`) paralel, kart 5/6/7 tutanak işidir ve şefe
aittir. Para: sıfır. GitHub Actions dört hücre × ~6 dk, public repo,
ücretsiz.

**DURMA:** kart 2 ya da 4 iki kez üst üste aynı kırmızıyı verirse §13/2
uyarınca üçüncü denenmez, `UYANDIGINDA.md`'ye yazılır.

---

## 2026-08-26 · F1b ve F2'nin sırası değişti

**F2 öne alınır, F1b arkaya. Yeni sıra: F1a → F2 → F1b → F1n → F3.**

**Bunu gerektiren ölçüm.** §7/F1b "koşu 2'nin yirmi iki turluk logları
duruyor, beş dedektör bu logların üstünde çevrimdışı koşturulur" diyor
ve kabulü "rakam **ledger'dan** türetilmiş, elle yazılmamış" diyor.
Bu ikisi bugün birbirini tutmuyor:

- `reports/kosu/*.out` **22 dosya vardır** ama ledger değildir. İçerikleri
  ajanın düzyazı transkripti ve `[tool: Bash]` işaretleridir: yol yok,
  hata imzası yok, çıkış kodu yok, süit durumu yok. Dedektörlerin
  okuduğu alanlar (`native/signals.h`: `err_sig`, `sig`, `suite`, `seq`)
  bu dosyalarda **hiç yok**. Yani F1b yazıldığı gibi koşturulamaz;
  koşturulursa üretilen sayı elle uydurulmuş olur — kabulünün yasakladığı
  şeyin ta kendisi.
- Gerçek ledger `~/.rabadon/spool/` altındadır ve zengindir:
  **246.775 satır, 32 gün dosyası, 104 oturum, 2244 SIGNAL, 368 COUNTER,
  6 INJECT, 1 INJECT_HELD, 751 WOULD_BLOCK.** Ama içinde koşu 2'ye ait
  olan (`rabadon-kosu2:session`) **yalnız 20 SIGNAL satırı** var
  (18 `green_redefined`, 2 `scope_drift`) ve **0 INJECT**.
  Korpusun ağırlığı komşu projede: `stitchu:session` 2080 SIGNAL.

Yani F1b'nin varsaydığı "kendi koşumuz en güçlü kanıtımız" cümlesi
ölçümle çürüktür: kendi koşumuz 20 satır, komşu proje 2080. F2 (`rabadon
scan`) tam olarak bu korpusu okuyan alettir. **F1b'nin sayısı F2'nin
aletinden çıkmalıdır**, ayrı bir tek kullanımlık betikten değil — o
zaman "ledger'dan türetilmiş" iddiası aletin kendisiyle kanıtlanır.

### F2'ye SERTLEŞTİRME (§10a)

Korpusun sinyal dağılımı ölçüldü (`~/.rabadon/spool/*.jsonl`, tüm 32 gün):

| sinyal | korpustaki satır |
|---|---|
| `scope_drift` | 1905 |
| `green_redefined` | 333 |
| `root_migration` | 4 |
| `semantic_repeat` | 2 |
| `repeat` | **0** |
| `oscillation` | **0** |

F2 metni kullanıcıya "kaç tekrar, kaç salınım, kaç kök taşıma" göstermeyi
vaat ediyor. Ölçüm diyor ki 246 bin satırlık gerçek veride **tekrar ve
salınım bir kez bile ateşlememiş**, ve ateşleyenlerin %92'si
`scope_drift` — ki o enjekte etmiyor, yalnız ledger'a yazıyor
(ENVANTER (a)). Buradan iki sert madde doğar:

**F2-S1.** Sıfır ateşleyen sinyal ekranda **boş bir satır olarak
geçiştirilemez**. `n=0` olan her sinyal için çıktı "ÖLÇÜLMEDİ, bu
korpusta hiç ateşlemedi" der ve o sinyal **canlıya çıkmaz**. §4.3'ün
yüzde beş tavanı `n=0`'da hesaplanamaz; hesaplanamayan oran yeşil
sayılmaz. Sessizce sıfır basıp geçmek boş yeşildir (§8.2).

**F2-S2.** F2'nin kabul betiği, ekranda duran **her sayının yanında onu
üreten oturum yolunu** zaten istiyor; buna ek olarak **sinyal başına
`n` ve etiketlenen örnek sayısı** da yazılır. `n < 10` olan sinyal için
oran yazılmaz, ham sayı yazılır — 4 örnekten yüzde çıkarmak
"ölçülmemiş şey satılmaz"ın (§4.5) ihlalidir.

**F2-S3 (önkoşul).** F2'nin okuyacağı korpus, disclosure kapısının
saydığı 41 özel proje adını taşıyan korpusun aynısıdır. Bu yüzden
**F2, F1a'nın disclosure kartı kapanmadan açılmaz**: aksi halde ilk
ekran operatörün özel repo adlarını basar.

### F1b'ye SERTLEŞTİRME

**F1b-S1.** F1b'nin sayısı `rabadon scan` çıktısından türetilir, ayrı
betikten değil; tutanakta komut satırı ve çıktı yolu durur.
**F1b-S2.** F1b "kendi koşumuz" iddiasını yalnız `rabadon-kosu*:session`
kapsamı için kurar ve **n=20**'yi gizlemez. Korpusun geri kalanı
kullanılacaksa hangi projeden geldiği ve kaç satır olduğu yazılır;
"kendi verimiz" diye komşu projenin verisini göstermek §4.5 ihlalidir.

---

## 2026-08-26 · F1a hakem hükmü sonrası · F1a'nın kırmızısı + F2'nin yeniden tanımı

Sorulan iki şey: (1) hakemin adıyla bıraktığı "kurulum iki cümleye iner
gerçek olmadı" kırmızısı §11 ile §8.6 arasındaki gerilimde nasıl çözülür,
(2) korpusta `repeat`=0 / `oscillation`=0 bulgusu F2'nin tanımını
değiştirmeli mi. İkisi de bu oturumda YENİDEN ÖLÇÜLDÜ; aşağıdaki her sayının
yanında onu basan komut var.

---

### A. KIRMIZI KARARI — seçenek (c), ve gerekçesi ölçüm

#### A.1 Gerilim gerçek mi? Evet, ve iki ayrı şeyi tek ada sıkıştırıyor

§8.6 "üçü YAZILI değilse kapanmaz" der; üçü yazılıdır, o yüzden hakem GEÇTİ
demekte haklıdır. §11 "kırmızıyı sonraki faza taşımak" yasağı ise yazılı
olmayı değil, DÜZELTİLMİŞ olmayı ister. İkisi çelişmiyor: §8.6 bir
BELGELEME kapısı, §11 bir ZEMİN kapısıdır. Hakemin bıraktığı kırmızı, tek
bir kusur değil, **birbirinden bağımsız iki kusurdur** ve tek ad altında
tutuldukları için çözümsüz görünüyorlar. Ölçüm ikisini ayırıyor.

**KIRMIZI-A · `rabadon on` hiçbir kurulum yolunda yok.** Bu oturumda
yeniden koşturuldu:

```sh
grep -n "rabadon on" README.md
```
→ tek eşleşme **satır 132**, kurulumla ilgisiz bir paragrafın içinde.
README'nin kurulum bloğu (`README.md:22-40`) şu yedi satırı sayıyor:
`git clone && cd`, `npm install && npm link`, `cd your-project`,
`rabadon init`, `rabadon drill`, `claude`, `rabadon usage` — ve içinde
`rabadon on` **yok**. `site/index.html:83` `rabadon on`'u yalnız komut
listesinde anıyor, kurulum satırında değil. `docs/quickstart.md:120`
içinde var ama kurulum bloğunun sonrasında.

Sonucu §7/F1a kart 5'te ölçülmüştü ve doğrudur: `init` sonrası mod
WATCH'tır, aynı hook olayı `exit 0` + `Nothing was stopped` verir; `on`
sonrası `exit 2` + `rabadon BLOCKED this action`. Yani **belgeyi harfiyen
izleyen kullanıcı hiçbir şeyi reddetmeyen bir guard kuruyor.** Bu §3'ün
tek cümlelik iyi-ürün tanımının ("kullanıcı kurar, ilk gün fark yaratır")
ve §4.8'in ihlalidir. **Yereldir, geri alınabilir, para yakmaz, bu gece
kapanır.**

**KIRMIZI-B · "iki cümle" sayısı.** Ölçülen 5 birleşik satır / 7 ayrık
komut. KIRMIZI-A kapandıktan sonra dürüst asgari **3 satır**:
`git clone … && cd rabadon && npm install && npm link` · `cd proj &&
rabadon init` · `rabadon on`. Kalan 3 → 2 farkının tek sebebi ölçülebilir:
**paket yayımlanmamış.** Yayımlandığında yol `npm i -g rabadon` ·
`cd proj && rabadon init && rabadon on` = **2 satır**. Yayın O1'dir,
operatör kararıdır (§13, geri alınamaz + sahiplik).

Üçüncü satırın `init`'e katlanması **yasaktır**: §7/F7 "watch modunun
varsayılan olması… bozulmayacak" diyor ve bu operatörün korunacak dediği
refleks. Yani KIRMIZI-B'nin kalan kısmı bir ihmal değil, **O1'in kendisi**.

#### A.2 Hangi değişmez ihlal ediliyor

- **§11 · "kırmızıyı sonraki faza taşımak yasak"** — KIRMIZI-A bu gece
  kapanabiliyorken F2'ye devredilirse ihlal edilir. Seçenek (a) tek başına
  bu yüzden **reddedildi**.
- **§3 / §4.8** — KIRMIZI-A açık kaldığı her saat, belgeyi izleyen her
  kullanıcıda ürün fren değil süs.
- **§10a · ölçü gevşetilemez** — KIRMIZI-B'yi "aslında 3, yani yeşil"
  diye yeniden adlandırmak ödül hacklemedir. Yapılmadı: sayı 5 olarak
  ölçülü kalıyor, 3 hedef olarak yazılıyor, 2 **F1n'in kabul maddesi**
  oluyor ve ölçümle sınanıyor.

#### A.3 KARAR: yeni bir mini-faz, **F1c**, F2'den ÖNCE (§10c + §10b)

Kart değil faz, çünkü kapanışı bağımsız bir hakem hükmü ister (§9 "hakem
her fazda ayrıdır ve bu asla esnemez") ve içinde **kırmızı düşebilen bir
test** var — kâtip commit'i tek başına kapatmaz. F1a'da kâtip commit'i
olmaması (§8.8 zayıf, hakemin kendi notu) da burada kapanır.

**F1c KABUL (hepsi zorunlu, hepsi yerel/geri alınabilir):**

1. **`rabadon on` belgelenmiş her kurulum yolunda, kurulum bloğunun
   İÇİNDE.** `README.md`, `site/index.html`, `docs/quickstart.md`. Kâtip
   işi (§15.5): yalnız `docs/`, `README.md`, `site/`.
2. **Kırmızı düşebilen kilit.** Yeni bir test, belgelenmiş kurulum
   bloklarını okur ve `rabadon on` (ya da `on`'u içeren bir satır) yoksa
   **BLOCKED** basar. Boş yeşil kontrolü (§8.2): satır belgeden çıkarılır,
   test kırmızı düşer, log'lanır, geri konur. Bu madde 1'in tek gerçek
   kanıtıdır — belgeye bir cümle eklemek kanıt değildir, kilitlemek
   kanıttır.
3. **`rabadon init` ekranı modu SÖYLER.** Bugün söylemiyor (ölçüm:
   `f1a-5` §2 verbatim ekran; `rabadon on|off` satırı var, "şu an
   WATCH'tasın" yok). Ekran §4.8'in üç sorusunu kurulum sonu için
   cevaplar: **şu an ne olduğu (WATCH, hiçbir şey durdurulmaz), neden
   (varsayılan watch'tır ve öyle kalması senin kararın), sıradaki tek
   komut (`rabadon on`)**. Verbatim ekran tutanağa girer.
4. **Adım sayısı YENİDEN ölçülür ve yazılır.** Aynı kum-havuzu yöntemi
   (`mktemp -d`, sahte `HOME`, `npm_config_prefix`). Beklenen 3; ne
   çıkarsa o yazılır (§4.5, CLAUDE.md kural 8). **5 sayısı silinmez**,
   tutanakta "önce 5, sonra N" olarak yan yana durur.
5. **`rabadon remove` Cursor hook'unu söker.** `removeCursorHooks` yok
   (ölçüm: `grep -rn "removeCursorHooks" hooks/` → boş; `remove` sonrası
   `.cursor/hooks.json` beş olayla TAM duruyor). §4.9 "kesin seviyenin
   her kuralının çıkış yolu vardır" ihlali ve Cursor kullanıcısının çıkış
   yolu **hiç yok**. Test: `init` → `remove` → `.cursor/hooks.json`
   içinde rabadon kalmadı.
6. **Kırmızı ad kümesi büyümedi** (`{2b, 6e, 7b}`), `make test` ok sayısı
   düşmedi (F1a sonrası taban: 3448).

**F1c'nin KAPSAM DIŞI bıraktığı:** npm yayını ve "2 satır" iddiası
(F1n'e), `init`'in kesik hata mesajı `no manifes`, `npm link`'in 4 satır
`allow-scripts` uyarısı, `.gitignore` kalıntısı, `pages-build-deployment`
kırmızısı. Beşi de ölçülü ve yazılı, kart açılmadı.

**BÜTÇE:** 2 işçi (kart 1+2+3 kâtip/kilit, kart 5 Cursor sökme), işçi
başına 60 dk, paralel salınırlarsa aynı dosyaya dokunmazlar
(`README/site/docs` vs `hooks/manage.mjs`). Para: sıfır.

#### A.4 F1n'e giden SERTLEŞTİRME (§10a) — devir değil, kabul maddesi

F1n'in kabulüne şu madde eklenir, mevcut `npm view rabadon version`
maddesinin ÜSTÜNE (yerine değil):

> **F1n-S1.** Yayından sonra kurulum adım sayısı temiz bir kum havuzunda
> YENİDEN ölçülür. Kabul: `npm i -g rabadon` ile başlayan yol, çalışır
> bir guard'a (bir hook olayının `exit 2` döndüğü ana) **en fazla 2
> birleşik satırda** ve **sıfır soruda** varır. Sayı 2'nin üstündeyse
> F1n kapanmaz. Ölçüm komutu ve verbatim çıktı tutanağa girer.

Bu, kırmızıyı taşımak değildir: taşınabilir kısım (KIRMIZI-A) bu gece
kapanıyor, kalan kısmın tek sebebi F1n'in kendisi ve o artık F1n'in
kendi ölçüsüyle sınanıyor.

---

### B. F2 — ÜÇ ÖLÇÜM, ÜÇ DEĞİŞİKLİK

Cevapçının önceki kararındaki bulgu (`repeat` 0 / `oscillation` 0) bu
oturumda yeniden koşturuldu ve **doğrulandı**, ama ölçüm bunun ötesine
gitti ve F2'nin temelinde daha büyük iki şey buldu.

#### B.1 Sıfırın sebebi: (i) mi (ii) mi? — ÖLÇÜLDÜ, cevap (ii)

**Ayıran komut, ikiye bölünmüş olarak:**

**(i) dedektör bağlı mı / ateşliyor mu — GERÇEK ikili üstünden:**
```sh
./native/signals_test.sh          # GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
```
→ **39 passed, 0 failed.** İçinde birebir şunlar var:
`ok - three failing runs of one command are a repeat` ve
`ok - an A-B-A-B-A-B edit loop on one file is oscillation`.
Yani **dedektör bağlı ve gerçek `rabadon-gate` ikilisi üstünden
ateşliyor.** (i) ELENDİ.

**(ii) korpus bu sinyali içeriyor mu — dedektörü gerçek korpusa
yeniden koşturarak:** Korpus replay edilebilir tek yerde durur,
`~/.rabadon/sessions/*.moves.bin`, ve `rabadon audit --export` ile
okunur (aynı kapı `native/moves_test.sh:133`'ün kullandığı kapıdır).
`signals.h`'nin `repeat` ve `oscillation` mantığı eşikleriyle birlikte
bu kayıtların üstünde yeniden koşturuldu:

| koşum | sonuç |
|---|---|
| `repeat`, sevk edilen eşik (`REPEAT_MIN=3`, `failed>=2`, pencere 20) | **0** |
| `repeat`, `REPEAT_MIN=2` | **0** |
| `repeat`, `REPEAT_MIN=1` (§4.1'in "eşik birdir"i) | **0** |
| `repeat`, `MIN=3` ama `failed>=1` | **0** |
| `oscillation`, sevk edilen `OSC_CYCLES=3` (6 dönüşümlü edit) | **0** |
| `oscillation`, `OSC_CYCLES=2` (4 dönüşümlü edit) | **0** |

**Sebep de ölçüldü, tahmin değil:** 527 hamlenin **497'si Bash, 23'ü
Edit, 7'si Write**; yalnız **20'si** hata taşıyor (`claimed_rc==1`,
%3,8); yalnız **30'unda** yol dolu; ve **hiçbir tek yola 6'dan fazla
edit gitmemiş** — tek-yol edit histogramı `{1 edit: 8 yol, 2: 4, 3: 3,
5: 1}`, oscillation en gevşek halinde bile 4 istiyor ve A-B-A-B deseni
arıyor. `suite` alanı 527 kaydın **1'inde** dolu.

**HÜKÜM: (ii).** Dedektör çalışıyor; korpusta materyal yok. Ve bu bir
eşik meselesi de değil — eşik bire indirilse bile sıfır. §4.1'in eşik-bir
talebi (F4) bu korpusta **hiçbir yeni yakalama üretmeyecek**, ve bu F4
için şimdiden ölçülmüş bir gerçektir.

#### B.2 Daha büyük bulgu: F2'nin korpusu 246.775 satır DEĞİL, 527 kayıt

Bu, sorulmamıştı ama F2'nin temelini doğrudan yıkıyor.

```sh
grep -aho '"ev":"[A-Z_]*"' ~/.rabadon/spool/*.jsonl | sort | uniq -c | sort -rn
```
→ 247.715 satırın **152.349'u `STEP_START`**, 78.579'u `STEP_OK`.
`SIGNAL` 2289, `INJECT` 6, `COUNTER` 368.

Ve spool'da **hamle kaydı yoktur**: dedektörlerin okuduğu alanlar
(`sig`, `err_sig`, `suite`, `claimed_rc`, `asserts` — `native/moves.h`
`struct Rec`) spool'a hiç yazılmaz. Spool yalnız **o gün ateşlemiş olan
SIGNAL satırlarını** taşır. Yani `rabadon scan` spool'u okursa
dedektörleri **yeniden koşturamaz**, sadece geçmişte basılmış sonucu
okur.

Yeniden koşturulabilir korpus şudur ve ölçüldü:
```sh
for f in ~/.rabadon/sessions/*.moves.bin; do \
  echo $(( ($(stat -f%z "$f")-4096)/320 )); done | paste -sd+ - | bc
```
→ **527 kayıt / 34 oturum / 652 KB.**

İkisi de eriyor, ve süresi ölçülü:
- Ring **oturum başına 200 kayıtla sınırlı** (`moves.h: CAP = 200`); bir
  oturum (`286fd71d`) **zaten 200'de** — daha eskisini sessizce üzerine
  yazmış.
- Oturum `.json` dosyaları **24 saatte** siliniyor
  (`gate.cpp:1107 SESSION_TTL_MS = 24h`); diskte 34 `.moves.bin` var ama
  yalnız **6** `.json`.
- Spool 30 günde budanıyor.

Ve zaman aralığı: `SIGNAL` olayları **yalnız 5 gün dosyasında** var
(2026-08-22 … 08-26); kalan **27 gün dosyasında 0**. `.moves.bin`
dosyalarının hepsi 22-26 Ağustos tarihli.

**Sonuç: §7/F2'nin "kullanıcı kendi son yedi gününü görür" cümlesi bu
makinede karşılığı olmayan bir vaattir.** Yedi gün yok; 4-5 gün ve 527
hamle var.

#### B.3 Ölçülen üçüncü şey: `rabadon scan` altıncı verb olur — §4.10 ihlali

```sh
./native/rabadon-cli.sh scan
```
→ `rabadon: unknown command "scan"`. Verb yok, yazılacak.

Ama `native/cli_test.sh` F1a'da tam olarak bunu kırmızıya düşürecek hale
getirildi: ana ekranda ürün verb'ü sayısı beşten farklıysa **BLOCKED**
basıyor ve ad kümesini `{init, on|off, usage, repair, doctor}` olarak
sabitliyor (`cli_test.sh:265-302`). Hakem bunu kendi eliyle sınadı:
altıncı verb → 315/0'dan **312/3**'e. Ayrıca §11 açıkça **"yeni CLI
verb'ü"**'nü yasaklar ve §4.10 "yüzey beştir, geri şişirilmez" der.

`scan`'i eklemek için `cli_test.sh`'in `PRODUCT` listesini düzenlemek
gerekir — yani **mühür kümesindeki bir testi geçmek için değiştirmek**.
Bu, bu projenin var olma sebebinin tam tersidir. §7'deki verb ADI,
§4.10'un altındadır ve §4'e dokunamam.

#### B.4 Dördüncü şey, F2'nin aleti kırık: export geçerli JSON basmıyor

```sh
./native/rabadon-audit --export ~/.rabadon/sessions/286fd71d-*.moves.bin \
  | python3 -c 'import sys,json;[json.loads(l) for l in sys.stdin if l.strip()]'
```
→ `json.decoder.JSONDecodeError: Unterminated string`. Tüm korpusta
**608 satırın 280'i (%46) geçersiz JSON.**

Sebep `native/audit.cpp:181-186`: `path` ve `raw` alanları **hiç
kaçışlanmadan** `printf("%s")` ile basılıyor. İçinde `"`, `\` ya da
satır sonu taşıyan her hamle çıktıyı bozuyor (bozan gerçek kayıt:
`"raw":"cd … && python3 - <<'EOF'` + satır sonu). Bu, F2'nin okuyacağı
**tek kapı**dır ve `moves_test.sh` bozuk satırları `except: continue`
ile sessizce atladığı için hiçbir test kırmızı düşmüyor. Boş yeşil
(§8.2).

---

### B.5 KARAR: F2 tanımı DEĞİŞİR (§10a sertleştirme + §10b sıra)

**SIRA: F1c → F2 → F1b → F1n → F3.** (F1c yeni, gerisi değişmedi.)

**F2'nin adı ve yüzeyi değişir: `rabadon scan` YOK. F2'nin ilk ekranı
mevcut beş verb'ün içinden çıkar — `rabadon usage`'a bir BAYRAK olarak
(`--signals`).** Bayrak verb değildir, ana yardım ekranına satır
eklemez, `cli_test.sh` tavanını kırmızıya düşürmez. Bu bir gevşetme
değil, §4.10'un dayattığı daha dar bir kapsamdır: ürün yüzeyi büyümeden
aynı ekran teslim edilecek.

**F2 KABUL — eskisi aynen durur (her sayının yanında oturum yolu, elle
etiketleme, sinyal başına yanlış pozitif oranı, %5 üstü canlıya
çıkmaz, üç zeminde ölçüm, en kötü zemin ölçüt), üstüne şunlar biner:**

**F2-S1 (önceki karardan, aynen durur ve sertleşir).** `n=0` olan sinyal
"ÖLÇÜLMEDİ" basar ve canlıya çıkmaz. **EK:** sıfırın SEBEBİ de basılır
ve ölçülür — kaç aday hamle bakıldı, hangi eşik tutmadı. "0" tek başına
bir sayı değil, bir sessizliktir; sebebi olmadan ekrana konması §4.5
ihlalidir.

**F2-S2 (önceki karardan, aynen durur).** Sinyal başına `n` ve
etiketlenen örnek sayısı yazılır; `n < 10` ise oran değil ham sayı.

**F2-S3 (önceki karardan, aynen durur).** F1a'nın disclosure kartı
kapanmadan açılmaz — kapandı, bu önkoşul artık YEŞİL.

**F2-S4 · YENİ — okuduğu korpusu ekranda ilan eder.** Çıktının ilk
satırı, okunan korpusu ölçüyle basar: **kaç hamle kaydı, kaç oturum,
hangi tarih aralığı, hangi dosyalardan.** "Son yedi gün" ifadesi ancak
yedi günlük kayıt gerçekten okunduysa basılır; okunmadıysa gerçek
aralık basılır. Bugünkü ölçüm 527 kayıt / 34 oturum / 22-26 Ağustos
diyor ve bu, hiçbir yerde 7 gün olarak yazılamaz (§4.5, §4.6).

**F2-S5 · YENİ — export kapısı önce onarılır, testiyle.** `path` ve
`raw` JSON-kaçışlanır (`native/audit.cpp`). Kabul: ham korpusun
**608/608** satırı `json.loads` ile ayrışır (bugün 328/608). Boş yeşil
kontrolü: kaçışlama geri alınınca test kırmızı düşer. Ve `moves_test.sh`
içindeki sessiz `except: continue` yutucusu **sayar ve raporlar** —
bugün yuttuğu 280 satır hiçbir yerde görünmüyordu.

**F2-S6 · YENİ — dağıtım kapısı bu korpusla açılamaz.** §7/F2 "burası
yeşilse ürün dağıtılabilir" diyor. Ölçüm sonrası bu **koşullu** hale
gelir: ekran, dört sinyalden ikisi (`repeat`, `oscillation`) için
"ÖLÇÜLMEDİ" basacaksa ve okunan korpus 7 günden kısaysa, dağıtım
cümlesi bunu **saklamaz**. Dağıtılabilirlik hükmü F2 hakemine aittir ve
hakem bu iki satırı ekranda GÖRMEDEN GEÇTİ diyemez. Negatifi olumluya
çevirmek yasaktır (§11).

**F2-S7 · YENİ — kanıt üç katmanlıdır, ekran ikinci katmanı iddia
etmez.** §4.12. F2 yalnız "(a) yazdı" katmanını gösterir. Ekranda
"yakaladı / kurtardı / kazandırdı" gibi ikinci-üçüncü katman fiili
kullanılamaz; kullanılırsa faz kapanmaz.

**F2 BÜTÇE (§11):** en fazla **6 işçi**, işçi başına 60 dk. Paralel
salınanlar aynı dosyaya dokunmaz: `native/audit.cpp` (S5) ile
`native/usage.h` + `rabadon-cli.sh` (ekran) ayrı; etiketleme kartı
salt-okunur. Para: sıfır, ağ yok, model çağrısı yok.

**F2 DURMA (§13/2):** okuma kartı (S5) iki kez üst üste aynı kırmızıyı
verirse üçüncü denenmez, `UYANDIGINDA.md`'ye yazılır. Ve F2 hakemi
KALDI derse F1b açılmaz — F1b'nin sayısı F2'nin aletinden çıkıyor
(F1b-S1).

**ACELE, ölçülü:** korpus eriyor. Oturum `.json`'ları 24 saatte,
spool 30 günde, ring 200 kayıtta. `.moves.bin` süpürülmüyor ama ring
üzerine yazıyor ve bir oturum zaten dolmuş. **F2 geciktikçe elimizdeki
527 kayıt küçülüyor, büyümüyor.**

---

## Kart dışı, ölçülmüş, dokunulmadı (sonraki fazların işine yarar)

- **`suite` alanı pratikte ölü.** 527 hamle kaydının **1'inde** `suite`
  != -1. `green_redefined` ve `counter.h`'nin "süit koştuysa yeşildi"
  zinciri bu alana dayanıyor. F3/F5 buna bakmalı. DOĞRULANMADI: alanın
  neden dolmadığı (hook mu gelmiyor, `testout.h` mi tanımıyor) — kart
  açılmadı, ölçülmedi.
- **`INJECT` 6 satırın 6'sı da `root_migration`**, ve ikisi
  `pipe:"stitchu:session"` / `"video-essay:session"` — yani enjeksiyon
  gerçek oturumlarda ateşlemiş. F3'ün "hiç ulaşmadı" cümlesi
  ENVANTER'de kollu koşu için doğru, ama korpusta 6 gerçek INJECT var
  ve F3 bunlara bakmadan başlamamalı. `INJECT_CAPPED` 0, `INJECT_HELD` 1.
- **`usage` ekranı proje adlarını ham basıyor** (`damummyphus`,
  `stitchu`, …). Yerelde doğru; ama F2'nin ekranı ekran görüntüsü
  alınabilir olacak (§7/F2 "ADIM 8") ve o an disclosure kuralı
  ekran çıktısı için de gerekir. Bugün `site/` için var, CLI çıktısı
  için YOK. Kart açılmadı.
- **`WRONG_REFUSAL` korpusta 6 kez var.** §4.3'ün yanlış pozitif tavanı
  için elimizdeki tek gerçek saha kalemi bu olabilir. Kart açılmadı,
  içerikleri okunmadı.
- **`TEST_EVIDENCE_MISSING` 936 kez.** Korpusun en kalabalık dördüncü
  olayı ve hiçbir fazın tanımında geçmiyor.
- **ÖLÇEMEDİĞİM:** temiz Linux konteynerde hiçbir şey koşturmadım;
  Cursor uygulamasını başlatmadım; `npm i -g rabadon` (yayımlanmamış);
  `rabadon dev replay`'i hiç koşturmadım (F2'nin işine yarayabilir,
  `dev --help` "re-run a recorded session against the current rules"
  diyor — DOĞRULANMADI); F1c'nin tahmin ettiğim "3 satır"ı ölçmedim,
  ölçüm F1c'nin kabul maddesidir.

- **CI temiz makine kanıtı zaten var ve kimse kullanmamış.** `ubuntu-latest`
  ve `macos-15` iş kolları F0 kapanış commit'inde yeşil. ENVANTER (e)
  "temiz makinede koşum ÖLÇÜLEMEDİ" diyor — aslında ölçülmüş, GitHub'da
  duruyor. R7 kabulünün `2b` kırmızısı (bu makinede 1299,4 µs, tavan
  1000 µs) temiz bir referans ortam istiyordu; o ortam bugün CI'da var.
  Bu bir karar değil, sonraki şefin bakması gereken bir imkândır.
- `pages build and deployment` iş akışı da kırmızı (32922500146). Yayın
  yolu `vercel`, `pages` değil; ölü bir yayın yolu her push'ta kırmızı
  basıyor. Kart açılmadı.
- `rabadon doctor` bugün yerelde `all green` basıyor (6 kontrol, exit 0).
  Yeşil olması dört hata sınıfının ele alındığı anlamına GELMİYOR;
  kontroller farklı şeylere bakıyor.
- Korpusun tamamı UTF-8 olarak sorunsuz ayrıştı (`unparsable 0`), ama
  ENVANTER'in `grep -a` uyarısı geçerli: `grep -c` bazı gün dosyalarında
  sessizce boş dönüyor.
- `~/.rabadon/spool/` 71,2 MB ve **30 günlük saklama** ile budanıyor
  (`rabadon doctor`). Yani F2'nin korpusu her gün eriyor. Kart açılmadı,
  ama F2 geciktikçe kanıt küçülüyor.

---

## 2026-08-26 · F1c hakem hükümleri sonrası · hakemlerin açık bıraktığı beş bulgu

İki bağımsız hakem F1c'ye GEÇTİ dedi ve sayıları birbirini tuttu. Kapıyı
kapatmayan ama açık bıraktıkları BEŞ bulgu (B1–B5) bu oturumda **tek tek
yeniden koşturuldu**. Aşağıdaki her sayının yanında onu basan komut var ve
hiçbiri rapordan kopyalanmadı. Üçü ölçümde raporlanandan **daha kötü** çıktı.

---

### B1 · "AÇTIM" DİYEN VE AÇMAYAN YÜZEY — ertelenemez, F2'den ÖNCE kapanır

#### B1.1 Hakemin bulduğu, doğrulandı

Kum havuzu (`mktemp -d`, sahte `HOME`/`RABADON_DIR`, `git init`, `node
hooks/manage.mjs init --no-llm`), aynı PreToolUse olayı (`git push --force
origin main`) gerçek `native/rabadon-gate` ikilisine verildi:

| yol | ekranda ne yazdı | gate ne yaptı |
|---|---|---|
| yalnız `init` | — | **EXIT=0** · "rabadon (watch) would have blocked this." |
| `node bin/rabadon.mjs on` | `rabadon: ON — the session is supervised again.` | **EXIT=0** · hâlâ watch |
| `native/rabadon-cli.sh on` | `rabadon: ON — the arbiter acts…` | **EXIT=2** · "rabadon BLOCKED this action." |

Doğrulandı: `bin/rabadon.mjs` yalnız `.rabadon/off` dosyasını siliyor
(`bin/rabadon.mjs:522-534`), `$RABADON_DIR/mode`'a dokunmuyor. Ve doğrulandı
ki bu dosya sevk edilen yol DEĞİL: `package.json` `bin` = `native/rabadon-cli.sh`,
dispatcher'ın `on|off|status` kolu (`rabadon-cli.sh` case satırı 118) doğrudan
`rabadon-gate --on`'a gidiyor, `bin/rabadon.mjs`'e yalnız `ui|watch` ve
`guard|fleet|spin|pack` kolları düşüyor. Yani **`on` hiçbir sevk edilen
yoldan o dosyaya varmıyor.**

#### B1.2 ÖLÇÜM HAKEMİN BULDUĞUNDAN DAHA KÖTÜ ÇIKTI — yalan SEVK EDİLEN yüzeyde

Aynı kum havuzunda devam edildi. `.rabadon/off` dosyası ortamda dururken
(oraya `bin/rabadon.mjs off` koydu, ama dosyayı elle yaratmak da aynı şey):

    $ native/rabadon-cli.sh on            # SEVK EDİLEN yüzey, package.json bin
    rabadon: ON — the arbiter acts: refuses, repairs, proves
    $ printf '<PreToolUse: git push --force origin main>' | native/rabadon-gate
    EXIT=0    (çıktı: 0 BAYT — hiç konuşmadı)

    $ native/rabadon-cli.sh status
    rabadon: ON — the arbiter acts: refuses, repairs, proves
      read from: …/.rabadon/mode (present)

Ve **aynı ikili, aynı an, aynı proje**, ikinci bir ağızdan:

    $ printf '{"workspace":{"current_dir":"$P"}}' | native/rabadon-gate --statusline
    proj  * rabadon off

`rabadon status` "ON — the arbiter acts" diyor; kullanıcının prompt satırında
duran `--statusline` **"rabadon off"** diyor. İkisi de `native/rabadon-gate`.
Gate zaten biliyor: `gate.cpp:2429` `hardOff`'u `RABADON_OFF` + `.rabadon/off`
+ `~/.rabadon/silent` ile hesaplıyor — ama **yalnız statusline için**.
`--status` ve `--on` bu üç girdiyi hiç okumuyor (`gate.cpp:2658-2660` sessiz
yolda okuyor, ekrana basmıyor).

Ayrıca ölçüldü: `native/rabadon-cli.sh off` `.rabadon/off`'u **kaldırmıyor**;
`docs/`, `README.md`, `site/` içinde `.rabadon/off` dosyası **hiç geçmiyor**
(`docs/commands.md:550` yalnız `RABADON_OFF` ortam değişkenini anlatıyor).
Yani belgesiz bir susturucu var, onu kaldırmanın belgelenmiş yolu yok, ve
durumu soran komut onun varlığını görmüyor.

#### B1.3 Hangi değişmez ihlal ediliyor

- **§1 · "fren".** Frenin pedalı "bastım" diyor, disk boş. Bu bir kusur değil,
  ürünün tanımının tersi.
- **§4.8.** Ekran üç sorunun üçünü de cevaplamıyor: ne olduğu YANLIŞ yazılı,
  neden yok, sıradaki komut yok.
- **§4.12 · "yazdı ≠ işe yaradı".** `on` yazdı; işe yaramadı.
- **CLAUDE.md Promise 1** — "if rabadon can't check, it says so; it never goes
  quiet." Burada tam olarak sessizce gidiyor ve ON diyor.
- **§8.2 · boş yeşil.** Bunu kırmızıya düşürebilen tek bir test YOK. Kırmızı ad
  kümesinde görünmemesinin sebebi düzelmiş olması değil, **hiç ölçülmemiş
  olması**.

#### B1.4 KARAR — yeni mini-faz **F1d**, F2'den ÖNCE (§10c + §10b)

**Ertelenemez.** Gerekçe ölçüm: yalan sevk edilen yüzeydedir, bir üçüncü şahıs
yüzeyde değil. §11 "kırmızıyı sonraki faza taşımak" yasağı burada bağlayıcı:
bu gece kapanabilir (yerel, geri alınabilir, para yakmaz). Ve F2'nin ürünü tam
olarak **kullanıcının kendi verisi hakkında doğru söyleyen bir ekran**;
durumunu yanlış söyleyen bir alet dürüstlük ekranı satamaz.

Kart değil FAZ, çünkü kapanışı bağımsız bir hakem hükmü ister (§9) ve içinde
kırmızı düşebilen yeni bir test var.

**F1d KABUL (hepsi zorunlu, hepsi yerel/geri alınabilir):**

1. **Durum ekranı, gate'in HESAPLADIĞI durumu basar.** `rabadon status`,
   `rabadon on` ve `rabadon off` çıktısı, gate'in kapıda okuduğu HER girdiden
   türetilir: `$RABADON_DIR/mode`, `~/.rabadon/silent`, `RABADON_OFF`,
   projedeki `.rabadon/off`. Susturuculardan biri yürürlükteyse ekran onu
   **adıyla** söyler, **nereden okuduğunu** söyler ve **onu kaldıran tek
   komutu** verir (§4.8). `.rabadon/off` dururken "ON — the arbiter acts"
   tek başına basılamaz.
2. **Kırmızı düşebilen kilit — iddia ile fiil karşılaştırılır, vekil değil.**
   Yeni test, her durum için (a) CLI'ın İDDİA ettiği durumu, (b) aynı anda
   gerçek `native/rabadon-gate` ikilisine verilen aynı PreToolUse olayının
   ÇIKIŞ KODUNU alır ve **ikisi çelişirse BLOCKED basar.** Matris:
   `mode ∈ {watch, enforce}` × `.rabadon/off ∈ {var, yok}` ×
   `RABADON_OFF ∈ {1, unset}` × `~/.rabadon/silent ∈ {var, yok}`.
   "ON" iddiası + `EXIT=0` **kırmızıdır**.
   Boş yeşil kontrolü (§8.2): test F1d ÖNCESİ koda karşı koşulur ve KIRMIZI
   düşer — bugünkü ölçüm bunu şimdiden garanti ediyor (yukarıdaki tablo).
   Ayrı ağaçta koşulur (`git worktree add --detach`), çalışma ağacına
   dokunulmaz.
3. **`--statusline` ile `status` bir daha ayrışamaz.** Aynı test ikisini de
   çağırır ve aynı ana dair aynı hükmü vermelerini şart koşar. Bugün
   ayrışıyorlar (B1.2, verbatim).
4. **`bin/rabadon.mjs` EDİTLENMEZ.** Ölçüldü: bu dosya bu reponun KENDİ
   guard'ında korumalı bir anti-path'tir — `.rabadon/guard.json`
   `protectedPaths` içinde `anti-path-frozen` ve `anti-path-frozen-abs`,
   ayrıca `bash` kuralı `no-shell-write-to-frozen-file`; gerekçe olarak
   "CLAUDE.md / HANDOFF §9" yazılı. Onu düzeltmek için dondurmayı çözmek
   **operatörün kararıdır** (§10: sahiplik), cevapçının değil →
   `UYANDIGINDA.md`, **VARSAYILAN: donmuş kalır.**
   Delik onu editlemeden kapanır: madde 1 yetkili yüzeyi doğru yapar, ve
   ek olarak **kırmızı düşebilen bir kilit, sevk edilen hiçbir giriş
   noktasının `on|off`'u `bin/rabadon.mjs`'e yönlendirmediğini** sabitler
   (bugün böyle: `package.json` bin, dispatcher kolları, `npm run watch`
   yalnız `watch` çağırıyor). Bu kilit yarın birinin o dosyayı geri
   bağlamasını kırmızıya düşürür.
5. **`.rabadon/off` belgelenir.** §4.9 "her kuralın çıkış yolu vardır" ancak
   çıkış yolu BİLİNİYORSA gerçektir. Kâtip işi (§15.5, yalnız `docs/`):
   dosya adı, ne yaptığı (gate tamamen susar), nasıl kaldırılacağı.
   Bugün hiçbir belgede geçmiyor — ölçüldü.
6. **B2 aynı fazda kapanır** (aşağıda, ayrı bulgu).
7. **Kırmızı ad kümesi büyümedi** (`{2b, 6e, 7b}`), `make test` exit 0 ve
   sayaç düşmedi — **B5'te ilan edilen tek geçerli sayaçla ölçülür.**

**F1d BÜTÇE (§11):** en fazla **3 işçi**, işçi başına 60 dk. Paralel salınanlar
aynı dosyaya dokunmaz: kart A/B `native/gate.cpp` + yeni test, kart C
`docs/` + `native/install_docs_test.sh`. Para: **sıfır**, ağ yok, model
çağrısı yok.
**F1d DURMA (§13/2):** kart A iki kez üst üste aynı kırmızıyı verirse üçüncü
denenmez, `UYANDIGINDA.md`'ye yazılır.

---

### B2 · `docs/quickstart.md` §1'in ÖLÜ kurulum yolu — F1n değil, F1d; kilit GENİŞLER

**Doğrulandı, kendi koşumumla:** `npm view rabadon version` → **E404**
(`404 Not Found - GET https://registry.npmjs.org/rabadon`). Ve
`docs/quickstart.md` `## 1. Install` bloğu verbatim `npm i -g rabadon`
diyor, altında `npm i -g rabadon --allow-scripts=rabadon` alternatifi ve
`rabadon doctor` doğrulaması var. F1c'nin kilidi (`native/install_docs_test.sh`)
`rabadon init` çapalı §2 bloğuna baktığı için bu bloğu **hiç görmüyor**.

**Hangi değişmez:** §4.7 ("kurulum iki cümleye iner, soru sorulmadan çalışır")
ve §3 ("kullanıcı kurar"). Belgelenmiş iki kurulum yolundan biri ilk komutta
patlıyor. §5'in ADIM 2'si F1c'de "GERÇEK" ilan edildi — o hüküm README yolu
için doğru, quickstart yolu için **yanlış**, ve ikisi aynı ürünü anlatıyor.

**KARAR: satır F1n'e AİT DEĞİL, kilit GENİŞLER ve iş F1d'de biter.** F1n'e
bırakmak, ölü kurulum yolunu yayın gününe kadar canlı tutmak demektir; §11
"kırmızıyı sonraki faza taşımak" yasağı. Gevşetme değil, kapsam genişletmesi:

**F1d-B2 KABUL:**

1. **Tek kanonik kurulum yolu.** `docs/quickstart.md` §1, README'nin
   kaynaktan kurma yoluyla aynı şeyi söyler. Kâtip işi (yalnız `docs/`,
   `README.md`, `site/`).
2. **Kilit genişler, ÇEVRİMDIŞI kalır.** `native/install_docs_test.sh`
   artık **belgedeki her kurulum bloğunu** bulur (yalnız `rabadon init`
   çapalı olanı değil) ve şu değişmezi tutar: *belgelenmiş hiçbir kurulum
   bloğu, repoda `package.json`'daki sürümün `v<sürüm>` etiketi YOKKEN
   `npm i -g rabadon` taşıyamaz.* Etiket çevrimdışı ve doğrulanabilir
   (`git tag --list`), ağ isteği YOK — test temiz bir konteynerde de koşar
   (CLAUDE.md: yalnız git ve shell).
   Bu kilit F1n gününde kendiliğinden serbest bırakır: yayın `v0.2.3`
   etiketini attığı an satır yasal olur.
3. **Boş yeşil kontrolü (§8.2):** `npm i -g rabadon` satırı geri konur, test
   KIRMIZI düşer, loglanır, geri alınır.
4. F1n'in kendi maddesi **DEĞİŞMEDEN durur**: yayından sonra
   `npm view rabadon version` sayı döndürür (+ F1n-S1, 2 satır ölçümü).

---

### B3 · HOT-PATH `2b` — sahipsiz kalmaz: ÖLÇÜM+YASAK F2'ye, ONARIM F3'e

**Kendi koşumum:** `bash reports/R7/accept.sh` → exit **1**, **23 yeşil /
3 kırmızı**, adlar **`{2b, 6e, 7b}`**. Verbatim:

    in-process median with the daemon up: 1184.7 us over 300 samples
    ceiling = 1000 us (KOSU-RABADON R7); instrument = R1.3 in-process probe
    FAIL  2b the gate's median is 1184.7 us with the daemon up, ceiling is 1000 us
          50-event session: 1194.8 us   400-event session: 1270.3 us   divergence 6.32%

Ölçülen seri (aynı komut, aynı tavan, farklı oturumlar):
**1299,4 → 1244,2 → 1261,0 → 1310,8 → 1248,8 → 1229,9 → 1184,7 µs.**
Tavan 1000 µs, hiç oynatılmadı. **Hedef ihlali kalıcı, gürültü değil:
yedi ölçümün yedisi de tavanın üstünde.**

**Hangi değişmez:** §1'in son cümlesi — *"Hedef gecikme bir milisaniyenin
altı."* §1'e dokunamam (§10). Ve hiçbir faz bu satırı sahiplenmiyor: F2
çevrimdışı okuma, F3 enjeksiyonu bağlıyor, R7 kabulü ise faz değil devralınan
bir betik. Sahipsiz hedef, ölçülmemiş iddiaya dönüşür (§4.5).

**Neden F2'nin işi değil ama F2'yi bağlar:** §7/F2 açıkça **dağıtım kapısıdır**
("burası yeşilse ürün dağıtılabilir"). Yani F2 yeşilse ürün, §1'in manşet
gecikme vaadi ölçülmüş biçimde **%18,5 ihlal edilmişken** dağıtılır. Bu, §4.5
ve §11'in "ledger'dan türetilmeyen sayıyı kamuya yazmak" yasağının kardeşidir.

**KARAR — üçe bölünür, hiçbiri gevşetme değil:**

**F2-S9 (YENİ, F2 kabul maddesi) · sıfır maliyet, üç parça:**
  a) **F2 hot-path'e hiçbir şey EKLEMEZ.** `2b` F2 öncesi ve sonrası aynı
     komutla ölçülür ve **yükselmez**. (F2 zaten `usage --signals` bayrağı,
     çevrimdışı; bu madde onu kanıta bağlar.)
  b) **F2'nin ekranı ve dağıtım cümlesi "bir milisaniyenin altı" / "sub-ms" /
     "instant" DEMEZ**, `2b` kırmızı olduğu sürece. Derse faz kapanmaz.
     Negatifi olumluya çevirmek yasak (§11). Gerçek sayı yazılacaksa
     ölçülmüş medyan ve tavan yan yana yazılır.
  c) **Referans ortamda BİR KEZ ölçülür.** Bugüne kadar `2b`'nin her ölçümü
     bu makinede alındı; temiz referans ortam **zaten var ve bedava**:
     CI'ın `ubuntu-latest` + `macos-15` hücreleri (public repo, F1a'da
     4 hücre yeşil koştu). `2b`'nin medyanı orada da ölçülür ve tutanağa
     yazılır. Ne çıkarsa yazılır (CLAUDE.md kural 8). Bu bir ONARIM değil,
     **1184,7 µs'in makineye mi ürüne mi ait olduğunu öğrenmektir** — ve
     onarımı planlayacak faz bu sayı olmadan plan yapamaz.

**F3-S1 (YENİ, F3 kabul maddesi) · onarımın sahibi:**
  `2b` F3'ün kabulüne girer. F3 motoru canlı hook'a bağlayan fazdır, yani
  hot-path bütçesinin sahibi odur. Kabul: **F3 kapanışında `2b`'nin medyanı
  F3 ÖNCESİNDEN YÜKSEK OLAMAZ**, ve F3 `2b`'yi 1000 µs'in altına indirmediyse
  bunu tutanağında **ölçüyle ve adıyla** yazar; §1'in vaadi ile ölçülen
  gerçek arasındaki fark hiçbir yüzeyde gizlenmez. `2b`'nin tavanı
  (1000 µs) hiçbir fazda oynatılamaz — §11.

**Bu bir devir değil:** taşınabilir kısım (ölçüm + yasak) F2'de kapanıyor,
kalan kısım (onarım) onu yapabilecek tek fazın kendi ölçüsüne bağlanıyor.

---

### B4 · KORPUS KAYBI — raporlanandan ÜÇ KAT büyük, ve büyümeye devam ediyor

**Kendi saydım.** `native/moves.h`: `HDR_BYTES=4096`, `REC_BYTES=320`,
`CAP=200`, `Hdr{ char magic[8]; long long count; long long nextSeq; }` —
yani `count` = şimdiye kadar YAZILAN, diskteki kayıt = `(boyut-4096)/320`.
Betik başlıktan `count`'u okuyup diskteki kayıtla karşılaştırıyor:

| korpus | oturum | başlık `count` toplamı | diskte duran kayıt | **KAYIP** |
|---|---|---|---|---|
| **canlı** `~/.rabadon/sessions` | 34 | **933** | **527** | **406 (%43,5)** |
| **dondurulmuş yedek** `~/.rabadon-korpus-snapshot-20260826/sessions` | 34 | **654** | **527** | **127 (%19,4)** |

Dolu ring **tek**: `286fd71d-…moves.bin`, diskte 200/200.
Yedek anında `count=327`, **şimdi `count=606`** — yani **F1c ve bu oturum
boyunca 279 hamle daha üzerine yazıldı.** Tutanağın "139 hamle kaybolmuştu"
sayısı yedek anı için doğruydu; **bugün canlı korpustaki kayıp 406.**
Ve dolu ring, bu koşuyu koşan oturumun kendisidir.

**Hangi değişmez:** §4.5 ("ölçülmemiş şey satılmaz") ve §4.6. F2 kullanıcıya
"kendi son yedi günün" diye bir korpus ilan edecek; o korpusun **%43,5'i yok**
ve hangi hamlelerin gittiği bilinmiyor. Kaybı ilan etmeyen bir ekran, kısmi
bir veriyi tam veri gibi satar.

**KARAR — F2-S4 SERTLEŞİR + F2-S8 YENİ:**

**F2-S4 (sertleşti).** Çıktının ilk satırı okunan korpusu ölçüyle ilan eder:
kaç hamle kaydı, kaç oturum, hangi tarih aralığı, hangi dosyalardan — **ve
bunlara EK olarak KAYIP**: `başlık count toplamı − diskteki kayıt`, ve dolu
ring'i olan her oturum için ayrı satır. "N hamle okundu" cümlesi, N'in
yazılanın tamamı olmadığı durumda **tek başına basılamaz**. "Son yedi gün"
ifadesi ancak yedi günlük kayıt gerçekten okunduysa basılır; bugün ölçüm
**22–26 Ağustos, 4-5 gün** diyor.

**F2-S8 (YENİ).** **F2 kabul sayısını CANLI korpustan almaz.** Ölçüm
`~/.rabadon-korpus-snapshot-20260826/` (salt-okunur, `dr-xr-xr-x`) üstünde
koşar ve hangisini okuduğu tutanakta yazılıdır. Sebep ölçülü: canlı ring
her koşuda dönüyor (yedekten bu yana 279 hamle), yani canlı korpustan alınan
bir sayı **yarın yeniden üretilemez** — yeniden koşturulamayan sayı hakemin
sınayamayacağı sayıdır (§9: "sayıyı kendisi yeniden koşturur") ve §4.5
ihlalidir. Ürünün canlı yolda çalıştığı ayrıca gösterilecekse, o **ikinci**
bir koşumdur ve sayısı kabul sayısı değildir.

---

### B5 · TEST SAYACI — iki sayaç DEĞİL, ÜÇ lehçe; ikisi de eksik sayıyor

§10 gereği iki komutu da KENDİM koşturdum. Sonuç, hakemin teşhisinden farklı
ve daha kötü.

**Koşturduklarım** (`make test` exit **0**, `npm test` exit **0**):

| sayaç | komut | bugün |
|---|---|---|
| DAR | `grep -c '^  ok'` | **3490** |
| GENİŞ | `grep -cE '^[[:space:]]*ok\b'` | **3504** |
| yalnız özet basan süitler | `grep -oE 'PASS \([0-9]+ checks?\)'` toplamı | **612** |
| sayı basmayan süitler | çıplak `PASS` satırı | **3** (sayı yok) |
| node | `npm test` → `ℹ pass` / `ℹ fail` | **64 / 0** |

**Bulgu 1 — hakemin "make'in kendi süit özetleri" teşhisi YANLIŞ.**
F0/F1a'nın 3438/3462'si süit özetlerinden değil, `grep -cE "^\s*ok\b"`
regexinden geldi (`envanter-d-test-npm.md:78` komutu adıyla yazıyor).
Süit özetlerinin toplamı bugün **2603**, hiçbir yayımlanmış sayıyla eşleşmiyor.

**Bulgu 2 — iki regex GERÇEKTEN farklı ve fark tam 14.** DAR sayaç,
çıktının 3951-3965 satırlarındaki bir süitin **14 gerçek iddiasını sessizce
düşürüyor**, çünkü o süit `ok`'u sütun 0'dan basıyor (`ok    fixture: exit 0,
clean stderr` …). Bir süiti sessizce düşürebilen sayaç, ölçtüğünü sandığı
şeyi ölçmeyen sayaçtır — §8.2'nin ta kendisi. **DAR SAYAÇ EMEKLİ EDİLDİ.**

**Bulgu 3 — DURUM.md'deki gerçek hata, hakemin sandığı yerde değil.**
Fark 14, F1a hakeminin 3448'i ile f1a-tutanak'ın 3462'si arasındaki farkın
da aynısı. Yani DURUM.md'nin **F1a satırı GENİŞ sayaçla (3462+64=3526)**,
**F1c satırı DAR sayaçla (3490+64=3554)** yazılmış. İki farklı birim yan
yana konunca büyüme **+28** gibi okunuyor; **tek sayaçla gerçek büyüme
her iki sayaçta da +42'dir** (3462→3504 ve 3448→3490). Düzeltildi.

**Bulgu 4 — her iki yayımlanmış sayı da EKSİK.** `PASS (N checks)` basan
**9 süidin 612 kontrolü** iki regexin de tamamen dışında; ayrıca 3 süit hiç
sayı basmıyor. Bugüne kadar yayımlanan 3438/3448/3462/3490 sayılarının
hepsi en az 612 eksiktir.

#### KARAR — TEK GEÇERLİ SAYAÇ (ve bu birim bir daha değişmez)

Sayaç bir üçlüdür, üçü birden yazılır, hepsi tek komuttan:

    make test ; echo "EXIT=$?"                                    # 0 OLMALI
    grep -cE '^[[:space:]]*ok\b'        <make test çıktısı>       # native iddia
    grep -oE 'PASS \([0-9]+ checks?\)'  <…> | grep -oE '[0-9]+' | paste -sd+ - | bc
    npm test                                                      # 'ℹ pass' / 'ℹ fail'

**BUGÜNKÜ TABAN (2026-08-26, F1c sonrası, bu oturumda ölçüldü):**

> **native 3504 iddia + 612 kontrol = 4116 · node 64 · TOPLAM 4180 yeşil /
> 0 kırmızı**, `make test` exit 0, `npm test` exit 0.
> Sayı basmayan native süit: **3** (adı yok, sayısı yok — bilinen boşluk).

Sonraki her faz bu üç sayıyı bu komutlarla basar. **Eski sayılar silinmez**
(3502 / 3526 / 3554), ama artık "emekli DAR/GENİŞ sayaçla, `PASS (N checks)`
hariç" etiketiyle dururlar ve yeni sayılarla **kıyaslanmazlar**. Sayacı
değiştirmek yeşil için sayı oynatmak değildir — burada değişen ölçüm YÖNTEMİ,
ölçüt değil; ve yön SERTLEŞMEDİR: yeni sayaç eskisinin görmediği 612 kontrolü
ve düşürdüğü 14 iddiayı görür.

---

## SIRA (bu kararla güncellendi)

**F1c → F1d → F2 → F1b → F1n → F3 → F4 → F5 → F6 → F7 → F8 → F9.**

`F1d` yeni ve F2'nin önündedir; gerekçesi B1 ve B2 (§11 kırmızıyı taşıma
yasağı, ikisi de bu gece kapanabilir, ikisi de para yakmaz).

---

## F2'NİN NİHAİ KAPSAM SINIRI — F2 şefine verilecek metin

**Önkoşul:** F1d hakem hükmü GEÇTİ. KALDI ise F2 AÇILMAZ (§11).

**Yüzey:** `rabadon usage --signals` **BAYRAĞI**. Yeni verb YASAK (§4.10,
§11). `rabadon scan` YOKTUR ve yazılmaz. `native/cli_test.sh`'in beş-verb
tavanı kırmızı düşemez; `PRODUCT` listesi DEĞİŞTİRİLEMEZ.

**Kabul, tam liste — hiçbiri gevşetilemez:**
- Yazılı kabul aynen durur: her sayının yanında onu üreten oturum yolu; elle
  etiketleme; sinyal başına yanlış pozitif oranı; %5 üstü canlıya çıkmaz;
  üç zeminde ölçüm; en kötü zemin ölçüt (§7/F2).
- **S1** `n=0` sinyal "ÖLÇÜLMEDİ" basar, sıfırın SEBEBİ ölçülür, canlıya çıkmaz.
- **S2** sinyal başına `n` + etiketlenen örnek; `n<10` ise oran değil ham sayı.
- **S3** disclosure önkoşulu — YEŞİL (`make disclosure` exit 0).
- **S4 (SERTLEŞTİ, B4)** okunan korpus ekranda ilan edilir + **KAYIP** ilan
  edilir (`count` toplamı − diskteki kayıt, dolu ring başına satır).
- **S5** export kapısı önce onarılır: `native/audit.cpp` `path`/`raw`
  JSON-kaçışlanır, ham korpusun **608/608** satırı `json.loads` ile ayrışır,
  `moves_test.sh`'in sessiz `except: continue` yutucusu **sayar ve raporlar**.
- **S6** dağıtım cümlesi "ÖLÇÜLMEDİ" satırlarını ve kısa korpusu saklamaz;
  hakem bu satırları EKRANDA görmeden GEÇTİ diyemez.
- **S7** kanıt üç katmanlı; ekran "yakaladı / kurtardı / kazandırdı" demez.
- **S8 (YENİ, B4)** kabul sayısı **dondurulmuş yedekten** alınır
  (`~/.rabadon-korpus-snapshot-20260826/`), canlı ring'den değil; hangisi
  okundu tutanakta yazılı.
- **S9 (YENİ, B3)** F2 hot-path'e hiçbir şey eklemez ve `2b` yükselmez;
  ekran/dağıtım cümlesi `2b` kırmızıyken "sub-ms" demez; `2b` bir kez
  CI referans ortamında ölçülüp tutanağa yazılır.

**Kapsam DIŞI (açılmaz):** yeni verb, npm yayını, `2b`'nin ONARIMI (F3-S1),
`suite` alanının neden ölü olduğu, `WRONG_REFUSAL`/`TEST_EVIDENCE_MISSING`
kartları, `installCursorHooks` yedeksiz üstüne yazma kartı, `pages` iş akışı,
site ürün anlatısı (F7).

**BÜTÇE (§11):** en fazla **6 işçi**, işçi başına **60 dk**. Paralel salınanlar
aynı dosyaya dokunmaz: `native/audit.cpp` (S5) ile `native/usage.h` +
`rabadon-cli.sh` (ekran) ayrı; etiketleme kartı salt-okunur.
**Para: sıfır. Ağ yok. Model çağrısı yok.**
**DURMA (§13/2):** S5 iki kez üst üste aynı kırmızıyı verirse üçüncü
denenmez; F2 hakemi KALDI derse F1b açılmaz (F1b-S1).

---

## BU OTURUMDA GÖRÜLEN, SORULMAMIŞ, DOKUNULMAMIŞ (§5.5 dökümü)

- **`native/rabadon-cli.sh off` `.rabadon/off`'u kaldırmıyor.** İki ayrı
  "kapalı" kavramı var (mod=watch ve proje susturucusu) ve tek komut adıyla
  yönetiliyorlar. F1d madde 1 bunu görünür yapar ama iki kavramı
  BİRLEŞTİRMEZ — birleştirme kararı verilmedi, kart açılmadı.
- **`rabadon remove` çıktısı hâlâ "npm rm -g rabadon" diyor**, kaynaktan
  kurulmuş ağaçta hiçbir şey yapmayan bir komut. F1n/F1d-B2 ile aynı aile,
  kart açılmadı.
- **`make test` çıktısında 3 süit hiç sayı basmıyor** (çıplak `PASS`).
  Hangi süitler olduğu ölçülmedi; sayaç bu boşluğu adıyla taşıyor.
- **Süit özetlerinin toplamı 2603**, iddia satırı sayısı 3504. Aradaki fark
  süitlerin kendi özetlerinin de eksik olduğunu gösteriyor; sebebi
  ölçülmedi, kart açılmadı.
- **DOĞRULANMADI:** temiz konteynerde/temiz klonda hiçbir şey koşturmadım;
  gerçek Cursor uygulamasını başlatmadım; `npm i -g rabadon` yolunu
  ölçmedim (yayımlanmamış); `2b`'yi CI'da koşturmadım (F2-S9c'nin işi);
  `.rabadon/off` yolunu Cursor tarafında sınamadım; F1d'nin tahmin ettiğim
  kırmızısını yalnız elle gösterdim, test olarak yazmadım (o F1d'nin
  kabul maddesidir).
