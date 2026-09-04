# F3j — HAKEM RAPORU (ikinci hakem)

Şef bunu okumayacak. Hüküm `KAPI.md`'de tek satır, kalemler `KARARLAR.md`'de.

## 0. BU OTURUMUN DURUMU

**Selefim 103 araç çağrısı ölçüm yaptı ve hükmünü yazamadan oturum limitine
takıldı.** Ham çıktısı `750f6e7` ile diske indi (`reports/kosu/kanit/f3j-hakem/`).
Ben onları **tekrar üretmedim**; okudum, kaynak gösterdim, ve **açık kalan üç
soruyu ölçüp** hükmü yazdım. `make test`'i **bir kez** koşturdum.

**SELEFİMDEN ALDIĞIM KALEMLER (yeniden ölçmedim):**

| Kalem | Kaynak | Değer |
|---|---|---|
| `accept.sh` sonucu | `kanit/f3j-hakem/hakem-accept.out` | EXIT=1, **23 PASS / 3 FAIL**, ad kümesi **`{2b, 6e, 7b}` BÜYÜMEDİ** |
| `2b` daemon'lu medyan | aynı dosya | **2009,0 µs** |
| `blind spots:` eşitliği | `hakem-declared.txt` / `hakem-measured-blind.txt` | 21 = 21, **KÜMELER EŞİT** |
| korpus ölçümü | `hakem-korpus-olcum.out` | 21 `ALLOW+GONE`; kontrol kolu doğru |

**KENDİ ÖLÇTÜKLERİM:** `kanit/f3j-hakem2/` (üç dosya).

---

## 1. AÇIK SORU 1 — `2b`, VE SEKİZ FAZLIK TEŞHİS HATASI

### Çelişki neydi?

Kart "sevk edilen hiçbir şey daemon'u başlatmıyor, `wait` bacağı `2b`'nin
yolunda değil" diyordu. Ama ölçütün kendi çıktısı **"with the daemon up"**
diyordu. **Kart mı haklı, ölçüt mü?** Üçünü de kaynaktan okudum.

### (i) `accept.sh`'in `2b` kolu daemon'u KENDİSİ başlatıyor

`reports/R7/accept.sh:132`:

```sh
SOCK="$W/rabadon-gated.sock"          # $W = mktemp -d
env HOME="$DH" RABADON_DIR="$DH/.rabadon" RABADON_GATED_SOCK="$SOCK" "$GATED" &
```

Daemon ölçütün kum havuzunda **doğuyor ve ölüyor**. Prob (`$PGATE`) da
`gate.cpp`'nin `/tmp` altına yamalanmış bir **kopyası**. Yani `2b`'nin ölçtüğü
konfigürasyonun üç parçasının üçü de ölçüt tarafından kuruluyor.

### (ii) Sevk edilen kurulum daemon'u BAŞLATMIYOR

Ölçtüm, dördü de:

- `~/.claude/settings.json`: **5 olayda `native/rabadon-gate`** kayıtlı
  (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `SessionStart`,
  `UserPromptSubmit`, `Stop`). **`rabadon-gated` 0 olayda.**
- `~/Library/LaunchAgents/`'ta rabadon plist'i **yok**.
- `ps aux | grep rabadon-gated` → **koşan süreç yok**.
- Daemon'u başlatan tek şey `bin/rabadon.mjs`'teki `rabadon dev gated` — bir
  geliştirici verbi, ve `bin/rabadon.mjs` bu fazın diff'inde **hiç yok** (O3
  donuk, doğrulandı).

Gate'in daemon'a uzanan bacağı (`gate.cpp:3286` → `gated_client.h:69`
`resolve_sock`) varsayılan olarak `$XDG_RUNTIME_DIR`/`/tmp` + `rabadon-<uid>.sock`
arıyor ve **yalnız dosya varsa** bağlanıyor. Bu makinede o dosya **var**
(`/tmp/rabadon-501.sock`, 24 Ağu 15:29) ve **dinleyicisi yok**, yani her gate
çağrısı ölü bir `connect()` ödüyor — ama daemon **yok**.

### (iii) Sonuç: `2b` kullanıcının yaşamadığı yolu ölçüyor

**KART HAKLI, ÖLÇÜT DEĞİL.** Ölçütün etiketi ("with the daemon up") dürüst;
tarif ettiği kurulum **sevk edilmiyor**. Ve bunun bedeli şudur: **F3h (+530,4 µs)
ve F3i (+538,0 µs) hakemlerinin daemon ölçümleri de sevk edilmeyen bir yolu
ölçtü.** `2b`'nin gerçek açığı sekiz fazdır **hiç teşhis edilmemişti**.

### TEŞHİS — bugün, zorunlu aletle

**Ölçüm 1 — sevk edilen yolun kendi medyanı (boş makine).** `accept.sh`'in
şart koştuğu R1.3 süreç-içi probunun aynısı, aynı olay, aynı 60 ısınma + 300
örnek. Tek fark: **daemon yok**, `RABADON_GATED_SOCK` boş.

```
SHIPPED-PATH (no daemon) n=300 median=766.3 us  p90=861.0  min=664.5  max=2436.1
```

**766,3 µs < 1000 µs.** Kullanıcının gerçekte koştuğu yol **tavanın altında**,
üstelik bu ölçüm makinenin bugünkü bozuk hâlini (ölü `connect()`) **ödeyerek**
alındı.

**Ölçüm 2 — eşli, ABBA, tek oturumda.** Çünkü yukarıdaki 766,3 ile selefimin
2009,0'ı **iki ayrı oturumdan** ve benden önceki üç hakemin tam olarak bu yüzden
azarlandığını biliyorum. Daemon'u kum havuzunda başlattım, `D,N,N,D` sırasıyla
üç tekrar, kol başına 400 örnek:

```
rep1: daemon UP 1661.3 | daemon DOWN 1023.1 | daemon costs +638.2
rep2: daemon UP 1924.5 | daemon DOWN 1142.3 | daemon costs +782.1
rep3: daemon UP 1977.2 | daemon DOWN 1282.7 | daemon costs +694.6
mean = +705.0 us, 3 plus / 0 minus
```

**Daemon +705,0 µs, işaret 3/3.** Hızlanma değil; `2b`'nin başarısızlığındaki
**en büyük tek terim**, ve **sevk edilmeyen bir bileşen**.

**Mekanizma, ağacın kendi cümlesiyle** (`gate.cpp:538`):
> "rabadon-gated forks a worker per request, so every request paid the cold
> price again"

`gated.cpp:269` ve `:294` — istek başına **iki `fork()`**, ve her taze işçi
`gmtime_r`'ın soğuk timezone yüklemesini (269–483 µs) yeniden ödüyor.

### HÜKÜM (§3.7)

Tavan **gevşetilmedi**; `accept.sh` diff'te **yok**, ona **dokunmadım**.
`2b`'yi **kalıcı §1 hedef ihlali ilan ETMİYORUM** — çünkü ölçtüm, hedef
**tutuyor**, yalnız yanlış kolda aranıyordu. **Ölçülmüş bacak F3k'ye atanıyor:
`rabadon-gated`'in istek başına `fork()` modeli.** İki çıkıştan biri seçilecek:

1. fork-per-request kaldırılır, daemon **sevk edilir** — o zaman `2b`'nin
   ölçtüğü yol gerçek yol olur ve 705 µs'lik terim ortadan kalkar; ya da
2. R7'nin "daemon açıkken" şartının **sevk edilmeyen bir kola bağlı olduğu**
   ölçüyle yazılır ve `2b` KAPI dışına alınır, yerine sevk edilen yolun medyanı
   (bugün 766,3 µs) konur.

Hangisi olduğunu seçmek F3k'nindir. **Dokuzuncu faza aynı belirsizlikle
devretmek §0 anlamında oyalamadır; bu rapor o belirsizliği bitiriyor.**

---

## 2. AÇIK SORU 2 — KART 1, SELF-HEAL (B2)

Sahibine verilen **en uzun** hasar. Üç senaryo + bir mutasyon, hepsi sahte
HOME'a karşı. `~/.claude/settings.json` sha256'sı **hepsinin öncesinde ve
sonrasında `adcb41a9…`**.

**ÖNCE BİR İTİRAF: ilk fikstürlerim BOŞTU ve bunu kendim yakaladım.**
`refresh.mjs` gövdesi `import.meta.url == file://$argv[1]` şartına bağlı;
macOS'ta `/tmp` bir sembolik bağ olduğu için şart yanlış oluyor ve **gövde hiç
koşmuyor**. İlk iki senaryom bu yüzden "koruma tuttu" gibi göründü. `/private/tmp`
altından yeniden koştum. Kart bunu yan bulgu olarak yazmış; ben **bağımsız
olarak aynı tuzağa düştüm**, yani bu onun ikinci ölçümüdür.

| Senaryo | Kurulum | Sonuç |
|---|---|---|
| **A2** | kayıtlı ikili **canlı** (kanonik), koşan kopya kanonik değil | komut **bayt bayt taşındı**, kendi yolu yazılmadı, abonelik **ilan edildi** — ✅ |
| **C** | kayıtlı ikili **ölü**, koşan kopya **worktree** (`.git` DOSYA) | **sesli ret**, `rabadon init` tavsiyesi, settings **değişmedi** — ✅ |
| **B** | kayıtlı ikili **ölü**, koşan kopya `/private/tmp` altında | **REDDETMEDİ, REPOINT ETTİ** — ❌ |

**A2 ve C, kartın omurgasını doğruluyor: zararın gerçek şekli (worktree)
bloklanıyor, ve her repoint eski+yeni adresle ilan ediliyor** (`refresh.mjs:216`,
`added.length`'ten bağımsız — eski sessiz repoint gitmiş).

**B DELİKTİR, kök sebebi okudum** (`refresh.mjs:92`):

```js
const tmp = real(os.tmpdir());     // bu makinede /var/folders/5b/.../T
```

Yani tmp kolu **yalnız `$TMPDIR`'i** kapsıyor. `/tmp` ve `/private/tmp` —
klasik scratch klasörleri, ve macOS'un gerçekten süpürdükleri — **kapsam dışı**.
Kartın "worktree/tmp yolunu sesli reddeder" cümlesi **ölçüden geniş**.

**İKİNCİ, GİZİL:** `notDurable(p)` aday yolu `p` alıyor ama worktree kolunu
`PKG_DIR`'e karşı sınıyor (`path.join(PKG_DIR, '.git')`) — **parametresini yok
sayıyor**. Bugün çakışıyorlar (GATE_BIN kardeş dosya), kusur canlı değil,
**gizil olarak kayda geçti**.

**MUTASYON:** `notDurable`'ı koşulsuz `null` yaptım →
`selfheal_path_test.sh` **21/0 → 18 passed / 3 failed, EXIT=1**; geri aldım →
**21/0**, `git diff hooks/refresh.mjs` boş. **Kırılabilen kapı = kapı.**

**Kararım: K1 KAPANDI, ilanı DARALTILDI.** Çürütmüyorum — zararın şekli
gerçekten bloklanıyor ve bunu kendi elimde gördüm.

---

## 3. AÇIK SORU 3 — KART 2, B3 ÜÇLÜ KAPISI

`native/rabadon-net`'i 17 baytlık `#!/bin/sh\nexit 0` ile değiştirdim:

```
FAIL - verify: 1 shipped artifact(s) are stub-sized
FAIL - verify: 1 shipped artifact(s) are not what they claim to be
FAIL - verify: a shipped artifact changed during the run — mode/size/hash moved
     < bin rabadon-net 755 155096 f1b3f7b0…
     > bin rabadon-net 755     17 306c6ca7…
machine_intact [verify]: 6 passed, 3 failed     EXIT=1
```

**Üç bacak da AYRI AYRI ateşledi:** 1024 baytlık boyut tabanı, Mach-O sihirli
sayısı, kayıtlı sha256. Geri aldım → sha256 **`f1b3f7b0…`, taban ile birebir**.
Kapı ayrıca aynı turda sahibinin `settings.json`'ının ve freninin
(`mode=watch`, `enabled` YOK) **oynamadığını kendi ağzıyla** doğruladı.

### Kapı doğru yerde mi? — brief'in sorusu, dürüst cevap

`make test`'in **ilk** (`Makefile:122`, `record`) ve **son** (`Makefile:1127`,
`verify`) satırı. Verify manifest'i **tüketiyor**: `record`'suz ikinci bir
verify kırmızı ("no baseline … this gate measured NOTHING") — bu tasarım
**doğru**, kapı boşa düşemiyor.

Ama kapının cevapladığı soru **"bu koşu sahibinin makinesine ne yaptı"**dır.
B1 (giden izin biti) ve B3 (stub) **ikisi de bir koşunun verdiği zarardı**, yani
kapı **doğru yerde**. Cevaplamadığı soru **"sahibinin makinesi ŞU AN sağlam
mı"**dır: `make test` koşulmadıkça elle kopyalama, çöken bir derleme ya da
düşen bir editör kaynaklı hasar **görünmez**.
`machine_intact_test.sh:88`'deki `point_in_time()` kolu tabana ihtiyaç
duymadan bunu **bugün** cevaplardı — **çağıranı yok**. Kart açmıyorum,
**boşluk olarak kayda geçiyor**.

---

## 4. KISA DENETİM (§3.8 / §3.12)

| Kontrol | Sonuç |
|---|---|
| `--diff-filter=D` silinen dosya | **0** |
| Yeni `skip` / `xfail` / yoruma alınmış iddia | **0** (diff'teki tek `skip` dizesi "NO SILENT SKIP" yorumu) |
| `reports/R7/accept.sh` diff'te | **YOK** ✅ |
| `reports/R7/ON-KAYIT.md` diff'te | **YOK** ✅ |
| `docs/claims.tsv` diff'te | **YOK** ✅ |
| `.rabadon/guard.json` diff'te | **YOK** ✅ |
| `bin/rabadon.mjs` (O3) | **YOK — donuk** ✅ |
| Ölçüt commit'i koddan önce ve ayrı | K1 `335fafa`→`07f3f21` ✅ · K3 `aea30a7`→`6196f8f` ✅ |
| Kâtip commit'i fazın sonuncusu değil | `6196f8f` (`docs/guard.md`), sonuncu değil ✅ |
| §3.12 tahmin, kart kesilmeden önce commit'li | `a2c251f` **05:06:01**, ilk iş commit'i `335fafa` **05:11:51** ✅ |

**İKİ NOT, KART LEHİNE DEĞİL AMA İHLAL DE DEĞİL:**

1. **K2 ve K4'ün ayrı ölçüt commit'i yok** (`07a2623`, `2def239` tek commit).
   Baktım: K2'nin diff'i yalnız `Makefile` + yeni `machine_intact_test.sh`, yani
   **ürün kodu içermiyor** — "ölçüt koddan önce" şartı **boşa düşerek**
   sağlanıyor. K4 salt ölçüm. Kural ihlali değil, ama iki fazdır tekrarlanan
   bir gevşeklik olarak yazıyorum.
2. **`law_blind_test.sh`'ten 4 iddia satırı silindi.** Baktım: silinenler
   `N>=5` ve `NC>=2` **kapsama** (containment) kontrolleridir ve yerlerine
   **eşitlik** kilidi geldi — selefim `comm` ile 21=21 doğruladı. Silinen
   satırlardan biri zaten **yanlış** bir sayı söylüyordu ("measured 7"). Bu bir
   **sertleşme**, §3.8 anlamında zayıflatma değil.

### SAYAÇ — ve dürüst bir uyuşmazlık

`make test` **EXIT=0**, hiçbir süitte tek bir `failed` yok, hiçbir yerde `skip` yok.

- Süit sayısı **kaynaktan** (F3h'nin emrettiği tek geçerli sayaç):
  `F3j-oncesi` **119** → HEAD **121**, ve fark **tam olarak iki yeni süit**
  (`machine_intact_test.sh`, `selfheal_path_test.sh`). **Kart doğru.**
- Kartın **+41 ayrıştırması** kendi koşumda **birebir** çıktı:
  `selfheal_path` **21** · `machine_intact` **6 + 9 = 15** · `law_blind` **15**
  (10'dan +5) → **21 + 15 + 5 = 41.** ✅
- **AMA mutlak native sayacı tutmadı:** bende `grep -c '^  ok'` = **4034**,
  kartta **4086** (fark **52**), ve bu F3i tabanı 4045'in bile **11 altında**.
  `PASS (N checks)` = **633**, kartla aynı.

**BU 52'Yİ ATFEDEMEDİM — "ÖLÇEMEDİM" DİYORUM.** İki gözlem bırakıyorum:
(a) `make test` koşarken `reports/` altına üç kanıt dosyası yazdım ve
`KARARLAR.md`'ye ekledim; ağacı tarayan süitlerin sayısını oynatmış **olabilir**,
izole etmedim. (b) Süitlerin bir kısmı gerçek `PATH`'i tarıyor
(`unknown wrappers: 63`, `wrappers: 64`) ve benim kabuğumun `PATH`'i 17 girdi —
**mutlak sayaç kabuğa bağlı olabilir**, yani hakem oturumları arasında
karşılaştırılabilir olmayabilir. Bu, sayacın kendisi hakkında bir bulgudur ve
F3k'nin bakması gereken bir şeydir.

**Hükmü mutlak sayaca DAYANDIRMIYORUM.** §3.8'in sorduğu şey "test silindi mi,
zayıflatıldı mı, atlandı mı"dır ve bunun üçüne de kendi ölçümümle **HAYIR**
diyorum: silinen dosya 0, yeni skip 0, süit 119→121, ve +41'in üç bileşeni de
kendi koşumda birebir.

---

## 5. SAHİBİNİN MAKİNESİ — KOŞU SONRASI

| Özne | Hâl |
|---|---|
| `~/.claude/settings.json` | **`adcb41a9…`** — oturumun başında, her mutasyonun çevresinde ve sonunda **aynı** |
| 21 artefakt (20 ikili + `bin/rabadon.mjs`) | **21'inin 21'i bayt bayt AYNI** (`diff` boş), **21'i de `-rwxr-xr-x`** |
| Fren | `mode=watch`, `enabled` **YOK** — sahibinin bıraktığı hâl |
| Worktree | **AÇMADIM.** `git worktree list` tek satır. C senaryosunda `.git`'i **dosya olan bir kopya** kullandım, gerçek worktree yok, ve iş biter bitmez sildim |
| Proje ağacı | yalnız benim rapor dosyalarım (`git status --porcelain`) |
| `/tmp/rabadon-501.sock` | **DOKUNMADIM** — sahibinin dosyası |
| `.rabadon/guard.json` | **DOKUNMADIM** · `rabadon off` **KULLANMADIM** · CHALLENGE-3 deliği **KULLANMADIM** |

**§4.3 — YANLIŞ POZİTİF ADAYI: 0.** Kapı bu oturumda beni **hiç kesmedi**.
Kaydedilen bir şey yok, dolayısıyla aday da yok.

---

## 6. ÖLÇEMEDİKLERİM (§5.5)

1. **`2b`'nin mutlak sayısının yükten arınmış hâli.** 766,3 µs **boş makinede**
   alındı; yük altında aynı kol 1023–1283 µs okuyor. Eşli +705 µs sağlamdır
   (3/3, ABBA), ama tek başına "766,3" **boş-makine varsayımı taşır**.
2. **Ölü `/tmp/rabadon-501.sock`'un µs maliyeti.** Denedim, **sıra artefaktı
   çıktı** (kollar arası tek yönlü sürüklenme, A hep B'den önce koştu; sonuç
   "ölü soketi silmek yavaşlatıyor" gibi absürt bir −104,1 µs). ABBA
   tasarlamadım, **ÖLÇEMEDİM**. Kart da ölçememişti; ikimiz de aynı yerde durduk.
3. **Mutlak native sayacındaki 52'lik fark** (yukarıda, §4).
4. **Konteyner/`refenv`** bu oturumda koşulmadı; `machine_intact` ve
   `selfheal_path` yalnız macOS'ta ölçüldü — **taşınabilirlikleri DOĞRULANMADI**.
5. **B1'in faili** (izin bitini kim düşürdü) — K2 kapısı olayı yakalar, faili
   değil. Selefimin de ölçemediği kalem.
6. **(c) negatif kontrolü** — kapsam dışı, F6'nın aleti. **F4 (c) ölçülmeden
   AÇILMAZ.** Açık şekilleri kapatmadım (istenen doğru sayımdı, ve o sayım tuttu).

## 7. SORULMADI AMA ÖNEMLİ

- **`gated_client.h:63-75` bir tasarım kararını doğru yapmış** ve bu, F3k'nin
  1. seçeneğini kolaylaştırır: varsayılan soket **yalnız zaten varsa** deneniyor,
  yani daemon'suz makine bir `connect()` timeout'u değil **tek bir `stat()`**
  ödüyor. Bu makinede yine de `connect()` ödeniyor çünkü **ölü soket dosyası
  duruyor** — kod doğru, ortam kirli.
- **`refresh()` her zaman `os.homedir()`'ı hedefliyor** (`refresh.mjs:234`),
  yani proje dizini ne olursa olsun **global `~/.claude/settings.json`'a
  dokunma yetkisi var**. B2'nin yarıçapı buradan geliyor. Bugün korumalar
  tutuyor (A2/C), ama yetkinin kendisi geniş ve bu kayda değer.
- **`~/.rabadon/rabadon.sock` (14 Ağu) ile `/tmp/rabadon-501.sock` (24 Ağu)
  AYRI iki dosya.** Gate'in daemon bacağı **yalnız ikincisine** bakıyor
  (`default_sock_path()`). Birincisinin ne olduğunu **çözmedim**, dokunmadım.
