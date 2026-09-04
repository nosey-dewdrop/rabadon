# F3d — HAKEM RAPORU (ayrıntı; şef okumaz)

Taban `F3d-oncesi` = `73bda28`. Bütün sayılar bu oturumda **benim** koşturduğum
komutlardan; kartın hiçbir sayısı kopyalanmadı.

---

## 0. KAPI SAYILARI — kendi koşumum

    make test ; echo "EXIT=$?"                       -> MAKE_TEST_EXIT=0
    grep -cE '^[[:space:]]*ok\b'   <çıktı>           -> 3838
    grep -oE 'PASS \([0-9]+ checks?\)' | ... | bc    -> 633
    npm test                                         -> pass 64 / fail 0
    TOPLAM                                           -> 4535 yeşil / 0 kırmızı

Taban 4529 → **+6**, kartın iddiasıyla birebir. Kaynağı da ayırdım (aşağıda §2).

    bash reports/R7/accept.sh -> 23 yeşil / 3 kırmızı, "R7 NOT ACCEPTED"
    kırmızı AD kümesi        -> {2b, 6e, 7b}  — BÜYÜMEDİ (§3.6 tuttu)
    2b satırı                -> "median is 1282.2 us with the daemon up, ceiling is 1000 us"

Süit sayımı (kendi regex'imle, taban = kartın `0-maketest-taban.out` dosyası —
**bu tek kalem kart kaynaklıdır**, kendi taban `make test`'imi koşturmadım):

    taban 72 süit -> HEAD 73 süit
    GREW  guard lint  20 -> 22
    NEW   silent skip  -  -> 4
    SHRANK / GONE: HİÇBİRİ

+2 ve +4 = **+6**. Süit özeti diff'inde küçülen ya da düşen süit yok.

F1e-C üçlüsü, nihai ikiliye karşı, kendi koşumum:
`docs_truth 42/0 EXIT=0` · `install_docs 38/0 EXIT=0` · `version 13/0 EXIT=0`.

Kâtip commit'i `4ee2894` (21:14:39) fazın **son commit'i değil** — sonrasında
`818f1e6` ve `50c579c` var. Ve `README.md` fazın diff'inde **gerçekten var**
(13 satır): kâtip şartı **üç fazdır ilk kez boşluğa düşmüyor**.

§3.12: tahmin commit'i `c4e7fdd` **20:51:49**, ilk kart commit'i `af0a3b5`
**20:57:20** — tahmin karttan 5,5 dakika ÖNCE ve fazın ilk commit'i. Tetik
çalmadı (300 dk tahmin, ~35 dk gerçekleşen commit aralığı).

---

## 1. CANLI (b) — GERÇEK, AMA **KENDİ ELİYLE KIŞKIRTILMIŞ**. n=1 lafzen doğru.

### 1.1 Kayıt canlı defterde duruyor ve UYDURMA DEĞİL

`~/.rabadon/spool/2026-08-29.jsonl` satır 2100 (`INJECT`) ve 2102
(`INJECT_ANSWER`). Bütün defterde `INJECT_ANSWER` sayısı: 29 günün toplamı
**1**, ve o bugün. `INJECT` toplamı 8 (22/23/24/25/26 Ağu'dan 7 + bugün 1).

**Sentetik/elle yazılmış olabilir mi — dört bağımsız kontrol, dördü de HAYIR:**

1. **Diff'te deftere yazan hiçbir şey yok.** `git diff F3d-oncesi..HEAD --stat`
   33 dosya: `Makefile`, `README.md`, 11 `*_test.sh`, 1 yeni `*_test.sh`, kart
   ve `kanit/f3d/*`. **Tek satır C++ yok**, `printf >> spool` yok, seed betiği
   yok, fikstür yok. `psig`/`INJECT_ANSWER` kodu `gate.cpp:3255` ve `:5167`'de
   ve **F3c'de yazılmıştı** — bu fazda gate.cpp'ye dokunulmadı.
2. **İkinci, bağımsız artefakt doğruluyor.** Halka dosyasını (`.rabadon/sessions/
   5fa2e187-…moves.bin`, `RBMV1`, 320 baytlık `Rec`) kendi parser'ımla açtım
   (`reports/kosu/kanit/f3d-hakem/ring.py`). Defterdeki üç alan da halkada
   birebir duruyor:

       hamle 756  sig=1a37b823ede897e7  err=c827cdae109a188c   <- INJECT'in psig'i
       hamle 757  sig=474caf5152ab8dd8  err=(yok)              <- INJECT'in mseq'i
       hamle 758  sig=69f067c23b54e9ca  err=(yok)              <- ANSWER'ın sig'i

   Defteri elle yazan biri, ayrıca ikili halka dosyasını da tutarlı biçimde
   yazmak zorundaydı. **`psig` GERÇEKTEN önceki kaydın imzasıdır** — kaynak
   (`gate.cpp:3379`) `injPendingPrevSig = ms.moves.back().sig` diyor, ve
   sinyal anında `moves.back()` = 756, sig = `1a37b823ede897e7`. Kendim
   hesapladım, tuttu. `same=false` da doğru: `69f0… ≠ 1a37…`.
3. **Zaman çizgisi tutarlı.** INJECT `ts=1788026979953` = **21:09:39**,
   ANSWER **21:09:49**; kart 1 commit'i `1e701ef` **21:10:21**. Yani kayıt
   commit'ten 42 saniye önce doğdu — sonradan eklenmiş olamaz.
4. **§F3:142 — fikstür imzası değil, ajan imzası.** `pipe` alanı
   `rabadon:session`, `sess` gerçek Claude Code oturum kimliği, taşıyıcı
   `call` bir `toolu_…` aracı çağrısı. `native/*_test.sh` fikstürlerinin
   yazdığı hiçbir şey bu alanları taşımaz.

### 1.2 AMA: SİNYAL AJANIN KENDİ ELİYLE ÜRETİLDİ (kart özetinde YOK)

Halkadan okudum, kartın özet cümlesinde geçmiyor:

    749  ls -la ~/…/_f3d_temizklon/native/rabadon-gate 2>&1; true     err=c827cdae109a188c
    755  command ls -la ~/…/_f3d_temizklon/native/rabadon-gate 2>&1   err=c827cdae109a188c
    756  env     ls -la ~/…/_f3d_temizklon/native/rabadon-gate 2>&1   err=c827cdae109a188c

**Aynı komut, üç farklı yazımla**, tier-0 imzası farklılaşsın ama `err_sig`
aynı kalsın diye — `root_migration`'ın "bir hata üç farklı hamleyi sağ atlattı"
şartını tam olarak üretmek için. `SIGNAL` satırı bunu kendisi söylüyor:
`"why":"one error survived 3 different moves","seqs":[749,755,756]`.
Ve `; true` ekleri tesadüf değil — §1.4'teki kör noktayı aşmak için.

Bunu **kart özeti gizledi ama kanıt dosyası gizlemedi**: `5-canli-b.out:42,52`
lafzen *"the phase agent was deliberately probing an unbuilt worktree three
ways"* diyor. CLAUDE.md 8 kanıt dosyasında karşılandı, kart 25 satırında
karşılanmadı. Ağırlaştırıcı değil, ama **hüküm bu ayrımı taşımak zorunda.**

### 1.3 same=false NE KANITLIYOR — hemen hemen hiçbir şey

Taşıyıcı hamle 757 ile hamle 752 **aynı imzayı taşıyor** (`474caf5152ab8dd8`,
aynı python3 defter-okuma betiği). Yani ajan enjeksiyon indiğinde zaten kendi
kanıt toplama işini yapıyordu; 758 de aynı işin ikinci adımıydı. `same=false`
burada **yapısal olarak garantiliydi**. Kart bunu kendi aleyhine yazdı
("enjeksiyon zaten uçmakta olan çağrıya bindi, nedensellik (c) ister, F4 kapalı
kalır") ve **doğrudur, lehine sayılır**.

Ölçtüğüm yapısal kusur, kartta yok: `INJECT_ANSWER.same` yalnız ajan bir
sonraki hamlede **birebir aynı komutu** tekrarlarsa `true` olabilir. Yani (b)
sayacı "ajan metni kullandı mı"yı değil "ajan bire bir tekrarı bıraktı mı"yı
ölçüyor — tek bitlik ve ucuza tatmin edilir bir ölçüt. §F3:142'nin lafzı bu,
ama lafzın kendisi zayıf.

### 1.4 DÖRT FAZLIK n=0'IN SEBEBİ — kartın üçüncü ölçümünü KENDİM ÜRETTİM

Kartın en ağır iddiası: **çıkışı sıfır olmayan bir Bash çağrısı için PostToolUse
olayı hiç gelmiyor.** Kendi elimle sınadım, iki komut, aynı oturum:

    toolu_01RCs43FXi5ZmtdXc9roaEVn   env ls -la /nonexistent-hakem-probe-ZZ1 2>&1   (exit 1)
        -> STEP_START     VAR
        -> STEP_OK        YOK

    toolu_01Xgcf9CMS3BvaDdKbojbzzp   … ; true                                       (exit 0)
        -> STEP_START     VAR
        -> STEP_OK        VAR

**DOĞRULANDI.** Ve `err_sig` yalnız PostToolUse dalında atanıyor (`moves.h`
`claimed_rc` / `err` alanları PostToolUse'da yazılıyor). Sonuç, ürünün kendi
kanıt yolunda **kör nokta**: rabadon'un var olma sebebi olan "aynı hata üçüncü
kez" sinyali, **düz başarısız bir komutu göremiyor**. Faz ajanının sinyali
ateşleyebilmesinin tek yolu her komuta `; true` eklemek olmuştu — yani n=1'i
üretmek için ürünün kör noktasını **elle telafi etti**.

Bu, dört fazlık n=0'ı diğer bütün açıklamalardan daha iyi açıklıyor ve
**sıradaki fazın bloklayan ilk kartıdır** (§3.7, dayanak: yukarıdaki iki
`call` kimliği).

Kartın diğer iki ölçümünü (iki sinyalin 29 günde hiç ateşlememesi; `err_sig`'in
bütün `tool_response` blob'unu hash'lemesi) **kaynaktan okudum, ayrı ayrı
YENİDEN ÖLÇMEDİM** — DOĞRULANMADI, ama kör nokta ölçümü zaten yeterli.

### 1.5 Yanlış pozitif

Kart kendi aleyhine "1 yanlış pozitif sayıldı" diyor (enjeksiyon metni
"no green move is on record this session" derken yanlıştı). Metnin kendisi
defterde duruyor ve gerçekten öyle diyor; **kabul**, sayılır.

**Bu oturumda BEN de 1 yanlış pozitif aldım:** `baseline-truncating-redirect`,
`printf … > $B/shim/python3` — hedef dosya **henüz var olmayan** bir dosyaydı
("the contents are gone before anything runs" — silinecek içerik yoktu) ve
ret metni "there is no command on the line to name" diyordu, oysa satırda
`printf` vardı. **F1b hakemi 2026-08-29'da aynı kuralın aynı şeklini saymıştı**
— yani bu sınıf iki hakem oturumunda üst üste ateşledi ve **sahibi hâlâ yok**.
Kural gevşetilmedi; yaklaşımı değiştirdim (`>` yerine `| tee`, §İKİ TUZAK/2).

---

## 2. SESSİZ SKIP — MUTASYONLAR BENİM ELİMDE, VE ÖLÇÜT DEĞİŞİKLİĞİ ONAYLANDI

### 2.1 Boş yeşil turu — kendim koşturdum

`F3d-oncesi` (`73bda28`) için `/tmp` DIŞINDA `--detach` worktree
(`~/damla_projects_2026/_hakem_f3d_base`), HEAD'in `silent_skip_test.sh`'ini
oraya kopyalayıp koşturdum:

    silent skip: 3 passed, 1 failed
    | sites=15 files=13 scanned=114

**Yeni kilit taban ağaçta KIRMIZI, HEAD'de yeşil.** Worktree
`git worktree remove --force` ile kaldırıldı (`rm -rf` KULLANILMADI, §İKİ TUZAK/2).

**Kartın sayısında küçük bir tutarsızlık var ve düzeltiyorum:** kart başlığı
"**14 site / 13 dosya**" diyor; düzeltilmiş ölçütle taban ağacın gerçek sayısı
**15 site / 13 dosya**'dır (kart kendi §14'ünde bu doğru sayıyı da yazmış).
14, düzeltme ÖNCESİ ölçütün saydığı sayıdır. İkisi de kartta var, gizleme yok.
Her hâlde **hakemin 9/8'inden büyük** — kartın asıl iddiası doğru: `grep 'echo
"  skip'` büyük harfli `SKIP` basan siteleri kaçırmış.

### 2.2 ⚠ ÖLÇÜT DEĞİŞİKLİĞİ (`eafa3e7`) — §3.8/1 İNCELENDİ, **ONAYLIYORUM**

Kart bir kabul ölçütünü kendi eliyle değiştirdi. Dördünü de kendim okudum:

- **Sertleşme mi gevşeme mi:** dar anlamda **gevşeme** — sayaç artık echo'nun
  kendi satırında olmak zorunda değil (pencere: 3 satır yukarı, 1 aşağı).
  AMA aynı commit bir **sertleşme** de getiriyor: pencerede başka bir şey
  BASAN satır (`ok() { PASS=$((PASS+1)); echo … }`) sayaç sayılmaz — bu
  olmadan pencere `ok()` yardımcısını yutup sessiz bir skip'i "sayılmış"
  ilan ediyordu, ve ajan bunu ölçmüş.
- **Eski/yeni yan yana mı:** EVET, dosyada yorum olarak lafzen
  (`was: same line only` commit mesajında, gerekçe + ölçüm kodda).
  Ölçülen etki: `harness_lock_test.sh` ve `heldout_test.sh` — ikisi de
  `skipped=$((skipped+1))` satırını echo'nun BİR ÜSTÜNE koyuyor, yani doğru
  davranıyor — haksız suçlu olmaktan çıktı.
- **Ayrı commit ve kodsuz mu:** EVET. `eafa3e7` yalnız `silent_skip_test.sh`
  + kanıt dosyası; onarım commit'i `fb7f2be` **6 dakika SONRA**. Sıra:
  ölçüt (`af0a3b5`, KIRMIZI) → ölçüt düzeltmesi (`eafa3e7`) → onarım
  (`fb7f2be`). CLAUDE.md 2 harfiyen sağlanmış.
- **BELİRLEYİCİ OLAN:** düzeltme hiçbir şeyi yeşile çevirmedi. `eafa3e7`'in
  kendi kanıt dosyası **`silent skip: 3 passed, 1 failed`** diyor. Yeşili
  getiren commit ölçüt commit'i değil, onarım commit'i.

**HÜKÜM: ONAYLANDI.** Gerekçe üç sayı: (i) dosya §3.8/1'in mühürlediği kümede
DEĞİL (`reports/*/accept.sh` ve `reports/R7/ON-KAYIT.md`; ikisinin de diff'i
0 satır); (ii) değiştirilen ölçüt **aynı fazda, aynı gün, aynı ajan tarafından
doğmuş** bir ölçüttür, devralınmış bir kapı değil; (iii) düzeltmeden sonra
süit KIRMIZI kaldı, yani gevşetme yeşil satın almadı. **Onaylayan benim, ajan
değil** — ve kural bundan sonra da geçerlidir: devralınmış bir kapıya (accept.sh,
ON-KAYIT, mühürlü eşik) aynı hareket yapılsaydı **REDDEDERDİM**.

### 2.3 MUTASYON KANITI — kendi elimde iki dal (kartınkini kopyalamadım)

**M1 — `node` gizlendi (`env PATH=/usr/bin:/bin:/usr/sbin:/sbin`):**

    HEAD: SKIP - the whole suite: 9 assertion(s) did NOT run — node is not installed…
          red base scope: 0 ok, 0 fail, 1 skipped (9 assertion(s) not run)
          red base scope: NOT JUDGED — every case needs node

Dal **adıyla ve sayısıyla** ilan ediyor. Kart doğru.

**M2 — bayat ağaç (`touch native/pathres.h`, `make all` KOŞTURMADAN):**
aynı ağaçta, aynı anda, taban dosyası ile HEAD dosyası yan yana:

    native/version_test.sh      TABAN: 11 passed, 0 failed   EXIT=0   ("skip - make -q arm…")
                                HEAD : 11 passed, 1 FAILED   EXIT=1
    native/guard_lint_test.sh   TABAN: 20 ok, 0 fail         EXIT=0   ("skip - make -q arm…")
                                HEAD : 20 ok, 1 FAILED       EXIT=1

Taban dosyalarını `git show F3d-oncesi:…` ile çıkarıp **proje dizini içinde**
koşturdum (ilk denememde `/tmp`'den koşturunca 0/11 çıktı — yol bağımlı;
o koşum atıldı). Bayat ağaç artık gerçekten **kırmızı düşüyor**.

`sandbox` ve `script_wrapper` dallarını **ben de dıştan zorlayamadım**
(çekirdek backend yok, pty yok) — kartın "DOĞRULANMADI" ilanı dürüst,
aynen devam ediyor.

### 2.4 `guard_lint_test.sh`'in ÖLÜ KOLU — DOĞRULANDI, ve gerçek bir kazanç

Kartın "sorulmamış bulgusu"nu kendim sınadım. `make all` (BUILD_EXIT=0), yani
**tam kurulu ağaçta**, taban dosyası hâlâ:

    guard lint: 20 ok, 0 fail
      skip - make -q arm: the tree is not built (run make first)

HEAD'de aynı ağaçta:

    guard lint: 22 ok, 0 fail, 0 skipped (0 assertion(s) not run)
      ok - make rebuilds 4 binaries when rules.h changes
      ok - the arm left the tree exactly as it found it (rules.h mtime restored)

**Yani bu kol yazıldığı günden beri hiç koşmamış** ve skip dalı bunu yutmuş.
+2 iddia sahte değil, hiç koşmamış iki iddianın ilk kez koşmasıdır. Bu, F3d'nin
en somut ürün kazancıdır.

---

## 3. `2b` — İKİ ÖLÇÜMÜ DE YENİDEN ÜRETTİM, VE KARTIN YORUMUNU DÜZELTİYORUM

Faz hızlandırmadı ve bunu iddia etmiyor: diff'te **tek satır C++ yok**
(§0'daki 33 dosya). Tavan oynatılmadı: `reports/R7/accept.sh` diff'te **HİÇ YOK**.

### 3.1 A/A (gerçek fark SIFIR), `7-2b-aa.sh` N=500 × 8, kendi koşumum

    ortalama fark   : +117,2 µs     (kart: +107,9)
    aralık          : -87,5 … +243,4  = 330,9 µs   (kart: 589,3)
    stdev           : 106,4 µs
    işaret          : 7 artı / 1 eksi              (kart: 6+/2-)
    tek koşu içi sürükleme: attributable armA 1472,5 -> 2357,0 µs, TEK YÖNLÜ

**Sonuç aynı, ve bir yerde kartın ötesine geçiyor:** aynı ikili kendine karşı
**7/1**'lik bir işaret ayrımı üretti. Bu, F3b hakeminin *"F3b'nin 8/8 işareti
ayrı ve geçerli bir kanıttır"* hükmünü **zayıflatır**: bu makinede sıfır gerçek
farkta 7/1 çıkabiliyor, yani 8/8 bile ancak sınırda anlamlıdır. Kayda geçti.

### 3.2 Eşli aç/kapa, `8-2b-taban.sh` N=400 × 6, kendi koşumum

    attributable, TAM YOL     : ortalama 1602,1 µs   (medyan 1583,2)
    attributable, YALNIZ ANAHTAR (RABADON_OFF=1): ortalama 676,4 µs (medyan 683,4)
    rabadon'un KENDİ İŞİ      : ortalama  925,7 µs   işaret 6+/0-
    taban payı / tavan        : %68
    bütün mantığa kalan       : 324 µs

Kart 595,2 / 1066,7 demişti; benim tabanım **daha kötü** (676,4), kalan pay
**daha dar** (324 µs). Yön ve büyüklük sınıfı aynı.

### 3.3 ⚠ KARTIN CÜMLESİNİ DÜZELTİYORUM — bu "ürünün kontrolü dışında" DEĞİL

Kart: *"1000 µs tavanın 595'i **süreç başlangıcı**… ürünün kontrolü dışında"*.
Betiği okudum: `attributable OFF = off − null`, ve `null` = **`/usr/bin/true`
doğurma maliyeti**. Yani işletim sisteminin herkesten aldığı süreç doğurma
maliyeti **zaten çıkarılmış**. Geriye kalan 676 µs, `rabadon-gate` ikilisinin
**kendi** yükleme maliyetidir: dyld, ikilinin boyutu, statik başlatıcılar,
bağlama seçimleri, anahtar okuma. **Bunların hepsi ürünün kendi kalemidir** —
`gate.cpp`'nin algoritmalarının içinde değil, ama ürünün içinde ve küçültülebilir
(statik bağlama, statik başlatıcıların azaltılması, ikili boyutu).

**Bu yüzden `2b`'nin 1000 µs tavanı ÖLÇMEK İSTEDİĞİ ŞEYİ ÖLÇÜYOR:** kullanıcı
her araç çağrısında bütün süreci ödüyor, yükleme dahil. Tavan doğru şeye
bakıyor; yanlış olan, bütçenin `gate.cpp`'nin algoritmalarında olduğu
varsayımıydı. **Tavan OYNAMAZ** (§3.8/4, §11) ve adının düzeltilmesine de
gerek yok — düzeltilmesi gereken **F3-S1'in hedefi**dir.

---

## 4. §3.8 DENETİMİ — TEMİZ

`git diff F3d-oncesi..HEAD --stat`, 33 dosya, 10783+/41−:

- **Silinen dosya:** YOK.
- **Silinen/skip'lenen/xfail'lenen/yoruma alınmış iddia:** YOK. `*.sh` diff'inde
  silinen 11 satırın hepsi eski sessiz-skip echo'ları ve sayaç ilklendirmeleri;
  hiçbiri bir iddia değil. `grep -cE '^\+.*(xfail|SKIP_ALL|exit 0 *# *skip)'` → **0**.
- `reports/R7/accept.sh` · `reports/R7/ON-KAYIT.md` · `docs/claims.tsv` ·
  `.rabadon/guard.json` → **diff'te HİÇ YOK**.
- **`CAP=200`:** `native/moves.h:62` yerinde, diff'te dokunulmamış.
- **Korpus / snapshot:** dokunulmamış.
- **Ölçüt commit'leri koddan ÖNCE ve AYRI:** EVET (§2.2 zaman çizgisi).
- **`docs/` kâtip şartı:** `README.md` 13 satır — **üç fazlık boşluk kapandı.**

**Kapı beni bir kez kesti, § adıyla:** `baseline-truncating-redirect`
(§1.5'te sayıldı, yanlış pozitif). `guard.json`'a DOKUNULMADI, `rabadon off`
KULLANILMADI, CHALLENGE-3 bileşik-komut deliği KULLANILMADI, `rm -rf`
KULLANILMADI (`git worktree remove --force`), kum havuzu `/tmp` DIŞINDA
açıldı ve **kaldırıldı**.

---

## 5. F4 — KAPALI

`KOSU-RABADON-5.md` §F3 satır 143 lafzen: *"Bu ölçüm yapılmadan F4 açılmaz."*
(c) negatif kontrolü **kartta koşulmadı ve BENDE de koşulmadı** (mühürlü görev
kümesi §3.8/2 + ağ + `claude -p` + saatler). Ayrıca F4'ün kendi eşik indirimi
(3→1) (b)'nin canlı yanlış-pozitif oranını gerektirir; o oran bugün **n=1**
üzerinden hesaplanamaz. **F4 KAPALI KALIR.**

**(c)'nin sahibi:** F3e DEĞİL. (c) iki kollu, mühürlü görev kümesi üzerinde
koşan bir ölçümdür ve `reports/R7/ab_run.jsonl`'in kümesine bağlıdır — bu
**F6'nın (Kanıt) aletidir**. Ama (c) olmadan F4 açılmaz, yani sıra
**F3e → (c) → F4** olamaz; doğru sıra **F3e → F6-aleti-ile-(c) → F4**'tür.
Dayanak: §F3'ün (c) tanımı ("aynı görev seti üzerinde iki kol") ile §F6'nın
aleti aynı şeydir; ayrı bir alet kurmak mühürlü kümeyi ikiye böler (§3.8/2 ihlali).

---

## 6. SORULMAMIŞ AMA ÖNEMLİ (§5.5 dökümü)

1. **Faz ajanı ile hakem AYNI oturum kimliğini paylaşıyor** (`5fa2e187-…`).
   Bu ölçümü kolaylaştırdı (halka hâlâ elimde) ama yapısal bir risktir:
   hakemin kendi hamleleri faz ajanının halkasına yazılıyor, ve hakem
   ölçtüğü defteri aynı anda büyütüyor. Bu koşuda zarar vermedi (`INJECT`/
   `INJECT_ANSWER` sayıları benim hamlelerimden bağımsız) ama ileride
   hakemin bir sinyali ateşlemesi kartın sayısını değiştirebilir.
2. **`~/.rabadon/sessions/` 16:15'ten beri hiç yazılmıyor.** Canlı oturum
   durumu **projenin kendi** `.rabadon/sessions/`'ına yazılıyor. İki ayrı
   kök var (`~/.rabadon/.rabadon/` diye üçüncü, tuhaf bir dizin de var).
   Hangisinin kanonik olduğu belgede yazılı değil; hakem raporlarının
   "canlı defter = `~/.rabadon/spool`" varsayımı **defter için** doğru,
   **halka için YANLIŞ**. Kimsenin kartı değil.
3. `docs_truth`, `install_docs`, `version` üçlüsü nihai ikiliye karşı yeşil,
   ama `install_docs` özet satırı süit adını basmıyor (`38 ok / 0 fail`) —
   §2.1'deki süit sayacım onu ada göre eşleştiremedi, elle doğruladım.
4. Kartın `docs/` güncellemesi `README.md`'dedir; `docs/` klasörünün kendisi
   bu fazda değişmedi. Kâtip şartının lafzı "README/docs" olduğu için
   sağlanmış sayıyorum, ama `docs/commands.md` bayat kalmış olabilir —
   **ÖLÇMEDİM.**

## 7. ÖLÇEMEDİKLERİM

- Kendi taban `make test`'imi koşturmadım; süit-küçülme karşılaştırmasının
  taban tarafı kartın `0-maketest-taban.out` dosyasıdır. (HEAD tarafı benim.)
- (c) negatif kontrolü — **ölçemedim**.
- `sandbox` ve `script_wrapper` skip dalları — **dıştan zorlayamadım**.
- Kartın "iki sinyal 29 gündür hiç ateşlemedi" ve "`err_sig` bütün blob'u
  hash'liyor" ölçümleri — kaynaktan okudum, **yeniden ölçmedim**, DOĞRULANMADI.
- Temiz konteynerde hiçbir şey koşmadım; yalnız macOS/arm64, tek makine,
  arka planda yük vardı (A/A'nın tek yönlü sürüklenmesi bunun kanıtı).
- `INJECT_ANSWER`'ın kayıt zincirini (`prev` sha) uçtan uca doğrulamadım;
  halka artefaktıyla çapraz doğrulama yaptım, o daha güçlüydü.
