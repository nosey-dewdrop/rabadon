# F3e — HAKEM RAPORU (2026-08-29)

Taban `F3e-oncesi` = `81d2433`. HEAD = `2c49345`. Kum havuzları `/tmp` DIŞINDA
açıldı (`_hakem_f3e_base`, `_hakem_f3e_mut`, `_hakem_f3e_screen`,
`_hakem_f3e_bench`) ve **dördü de kaldırıldı** (`git worktree list` tek satır).

## 1. KAPI — kartın hiçbir sayısı kopyalanmadı, üçü de kendim koşturuldu

| ölçü | taban (`81d2433`, hakem koşturdu) | **HEAD (hakem koşturdu)** | kartta |
|---|---|---|---|
| `make test` | EXIT=0 | **EXIT=0** | EXIT=0 |
| native iddia (GENİŞ regex) | 3838 | **3859** | 3859 |
| native `PASS (N checks)` | 633 | **633** | 633 |
| `npm test` | 64/0 | **64 / 0**, EXIT=0 | 64/0 |
| **TOPLAM** | **4535** | **4556 yeşil / 0 kırmızı** | 4556 |

**+21, ve 21'in tamamı yeni süit.** `make test` çıktısındaki tek `FAIL` satırı
(satır 4451) bir fikstürün beklenen metnidir, düşen bir iddia değildir.

`bash reports/R7/accept.sh` → **EXIT=1, 23 yeşil / 3 kırmızı**, adlar
**`{2b, 6e, 7b}` — BÜYÜMEDİ**. `2b` satırı: medyan **1252,1 µs**, tavan
**1000 µs**, tavan oynatılmadı.

**SÜİT SAYIMI, kendi sayacımla (iki `make test` çıktısını kendim ayrıştırdım):**
`base suites=111 → head suites=112`, **küçülen 0 · kaybolan 0 · büyüyen 0 ·
yeni 1** (`failed_call_test.sh`, 21). Toplam 4471 → 4492. Kartın
`f3e-suit-census.out`'u ile **birebir**.

**F1e-C üçlüsü, fazın NİHAİ ikilisine karşı:** `version_test` **13/0**,
`install_docs_test` **38/0**, `docs_truth_test` **42/0**, üçü de EXIT=0.
Ek olarak kurulum yüzeyi: `cli_test` **315/0** (beş-verb tavanı duruyor, F1d ile
aynı sayı), `doctor_test` **43/0** (F1d ile aynı — **yeni ürün verb'ü doğmadı**).

**Kâtip commit'i:** F3e'de kâtip commit'i YOK; son commit kart dosyasıdır
(`2c49345`), §8.2'nin istediği sıra. Belge davranışla **aynı commit'te** gitti
(`3bcf51e`: `docs/how-it-works.md` + `hookev.h` + `install.mjs` + `gate.cpp`) —
CLAUDE.md "docs move with behavior" karşılandı.

## 2. §3.8 DENETİMİ — TEMİZ

- **Silinen dosya: 0.** `git diff --name-status` içinde tek `D` yok.
- **Silinen / `skip` / `xfail` / yoruma alınmış iddia: 0.** `*.sh` diff'inde
  `-` ile başlayan tek bir `pass|ok|assert` satırı yok. Diff'te geçen iki
  "skip" kelimesi **"NOT a skip"** diyen yorumlardır.
- **Hiçbir süidin iddia sayısı düşmedi** (yukarıdaki census, `GREW: []`,
  `SHRUNK: none`).
- **Mühürlü set diff'te HİÇ YOK:** `reports/R7/accept.sh` · `ON-KAYIT.md` ·
  `docs/claims.tsv` · `.rabadon/guard.json` · `ab_run.jsonl` · korpus/snapshot ·
  `site/published-projects.txt`.
- **`CAP = 200` oynatılmadı** — `native/moves.h` diff'i **0 satır**.
- **`bin/rabadon.mjs` (O3 donuk anti-path) diff'te YOK** — dokunulmadı. Kart
  `doctor` ekranını denedi, kapı reddetti, ajan yaklaşımı değiştirdi. Doğru ret.
- **`docs/claims.tsv` gerekmiyordu, ve bu bir kanaat değil:** sicil yalnız
  `docs/commands.md` · `docs/faq.md` · `docs/uninstall.md` içindeki
  `rabadon:claims-begin` bloklarını kapsar (`docs/claims.tsv` başlığı,
  `native/docs_truth_test.sh:69,101`). Bu faz `docs/how-it-works.md`'yi
  değiştirdi — kapsam dışı — ve `docs_truth_test` iki yönlü denetimi **42/0**
  ile yeşil. Ajan `claims.tsv`'ye dokunmadı, `CHALLENGE:` de yazmadı.
- **§3.12:** tahmin commit'i `ed57569` **21:52:56**, ilk kart commit'i
  `e8fdffc` **21:58:58** — tahmin **gerçekten önce**, tetik çalmadı.

### §3.8 denetiminin TEK BULGUSU — CLAUDE.md 2'nin LAFZI (bloke etmiyor)

`3bcf51e` ve `0c29fe5`, `native/failed_call_test.sh`'i **kodla aynı commit'te**
değiştirdi. İkisini de satır satır okudum, **ikisi de ölçütü GÜÇLENDİRİYOR:**
- `3bcf51e`: CLAIM 7 `grep 'PostToolUseFailure' hooks/install.mjs`'ten
  **kurucuyu gerçekten koşturup yazdığı `settings.json`'ı okumaya** çevrildi
  (grep, aboneliği silseniz bile açıklama yorumuna takılıp yeşil kalıyordu —
  ajan bunu kendi mutasyon turunda yakalamış ve yazmış), ve CLAIM 9 (+2 iddia)
  eklendi.
- `0c29fe5`: `doctor` ölçütü (2 iddia) **oturum kartı** ölçütüne (3 iddia)
  taşındı, çünkü `doctor` yolu kapı tarafından reddedildi.

Zayıflatma yok, gevşetme yok, mühürlü dosya yok, ve süit **bu fazda doğdu** —
devralınan bir ölçüt değil. **KIRMIZI SAYMIYORUM.** Ama lafız ihlali kayda
geçer ve sıradaki faz için kural: **yeni bir süit bile olsa, ölçütün SURFACE'i
değişiyorsa o değişiklik kendi commit'inde ve gerekçesiyle gider.**

## 3. KART 1 — DOĞRU, ve dört ayrı yoldan KENDİM DOĞRULADIM

**(i) Ham yük CANLI, elle yazılmamış.** `f3e-1-posttooluse-failure-payload.json`
içindeki `tool_use_id` = `toolu_01VmCfk7dFyabrQ4BBzDt93T`. O id'yi harness'ın
kendi transcript'inde buldum
(`~/.claude/projects/-Users-…-rabadon/180040c2-….jsonl`, **2 kayıt**): `tool_use`
bloğundaki komut (`env ls -la /nonexistent-f3e-probe-CC3 2>&1`) ve
`tool_result`'taki metin (`Exit code 1\nls: /nonexistent-f3e-probe-CC3: No such
file or directory`) yükteki alanlarla **harfiyen aynı**. Uydurulamaz.

**(ii) Olay adı gerçek, ve bunu ürünün dışından da gördüm.** Canlı
`~/.claude/settings.json`'da bir `PostToolUseFailure` bloğu **zaten var** —
ama içinde **yalnız orkestra'nın `tick.py`'si**, rabadon-gate **yok**. Yani
harness olayı teslim ediyor, rabadon abone değil. Kartın teşhisi bire bir.

**(iii) ONARIM ÇALIŞIYOR — kendi elimde ürettim, ve tabanla yan yana koydum.**
Aynı `PreToolUse` + `PostToolUseFailure` çiftini iki ikiliye de verdim
(sandbox HOME, `pytest -q`, `Exit code 1\nE   AssertionError: hakem probe`):

| | **taban (`F3e-oncesi`)** | **HEAD** |
|---|---|---|
| defter | `STEP_START` — **kapanış YOK** | `STEP_START` + `STEP_OK … "rc":1` |
| `claimed_rc` (halkadan, kendi parser'ımla) | **−1** | **1** |
| `err_sig` | **boş** | **d58714fac4f6feb4** |

`sig` iki tarafta da `65b7c80d07c759bc` — aynı komut, aynı imza; fark yalnız
onarımın getirdiği alanlar.

**(iv) CANLI MAKİNE HÂLÂ KÖR — ve bunu bugün kendi hamlemle ölçtüm.** Bu
oturumda çıkışı 1 olan bir Bash koşturdum
(`toolu_01M14K72DJ4FP4trdsMuLknQ`, `ls -la /nonexistent-HAKEM-F3E-PROBE-ZZZ1`).
`~/.rabadon/spool/2026-08-29.jsonl`'de o çağrı için **`STEP_START` var, `STEP_OK`
YOK** — F3d hakeminin `toolu_01RCs43FXi5ZmtdXc9roaEVn` kanıtıyla **aynı**.
Hemen sonraki başarılı çağrının ikisi de var. Sebep: kurulum bayat. Kart bunu
zaten "bugünden önce kurulmuş bir makine hâlâ kör" diye ilan etmiş; ben
doğruladım, ve `rabadon init`'i **koşturmadım** (ölçüm ortamını değiştirmek
hakemin işi değil) — sıradaki fazın ilk bloklayan kartı budur.

**(v) EKRANDAKİ İLAN — sevk edilen ikiliyi koşturup KENDİ GÖZÜMLE gördüm.**
Bayat kurulum (`SessionStart`, sahte HOME, beş olaya abone):

```
  blind spots:
               - an agent that calls a program by absolute path (/usr/bin/git) walks past me
               - no .rabadon/guard.json here, so no command is denied — I only watch
               - this install does not subscribe to PostToolUseFailure, so a command that EXITS NON-ZERO is invisible to me here
                 (no error signature, so no repeat is ever detected) — fix: `rabadon init`
```

Aynı dizine `PostToolUseFailure` aboneliğini ekledim → satır **düştü**. İki yön
de doğru; kurt masalı okumuyor.

**(vi) MUTASYON — kartınkini kopyalamadım, kendim ürettim** (HEAD worktree'sinde,
`Edit` ile; `perl -0pi` denemem kapı tarafından **doğru** kesildi):

| mutasyon | süit |
|---|---|
| yok (kontrol) | **21 passed / 0 failed**, EXIT=0 |
| `hookev.h detect()`'ten `PostToolUseFailure` adı çıkarıldı | **14 / 7 KIRMIZI** |
| `install.mjs`'ten abonelik satırı silindi (**açıklayıcı yorum bırakıldı**) | **20 / 1 KIRMIZI** |

İkincisi önemli: yorum dosyada "PostToolUseFailure" yazmaya devam ediyordu ve
süit yine kırmızı düştü — çünkü ölçüt artık dosyayı grep'lemiyor, **kurucuyu
koşturuyor**. Kırılabilen kapı.

**(vii) BOŞ YEŞİL — `F3e-oncesi`'nde kendim koşturdum:** yeni süiti taban
worktree'sine kopyaladım, taban ikilisiyle: **10 passed / 11 FAILED, EXIT=1**.
Kart 11/10 demişti; **±1 fark**, toplam 21 iddia aynı. Kaynağını ayırmadım
(`ölçemedim` — ama yön ve büyüklük aynı, ve süit taban ağaçta düşüyor, tek
mesele bu).

**HÜKÜM: KART 1 KAPANDI.** Dört fazlık n=0'ın sebebi bulundu, adı kondu,
onarıldı, kırmızı düşebilen 21 iddialık bir kapıya bağlandı ve sevk edilen
ekranda ilan edildi. Bu fazın en ağır iddiası ve **doğru**.

## 4. KART 3 — CHALLENGE HÜKME BAĞLANDI: **F3d HAKEMİ YANILDI, ama F3e'nin YERİNE KOYDUĞU SAYI DA TUTMUYOR**

CLAUDE.md "If PROJECT.md itself is wrong": **kanıt belgeyi geçer.** Üç ölçümü de
kendim yeniden ürettim (N=200, 5 tekrar, aynı koşum, medyan):

| bacak | benim ölçümüm (2026-08-29, hakem) |
|---|---|
| `/usr/bin/true` | 1401,2 µs |
| boş C ikilisi (16,8 KB) | 1334,9 µs |
| boş C++ ikilisi (**aynı 16,8 KB, libc++ + libSystem**) | 1404,5 µs |
| `rabadon-gate`, `RABADON_OFF=1` | 2250,1 µs |
| `rabadon-gate`, tam yol | 3134,2 µs |

- **(c) DOĞRULANDI:** boş C++ ↔ boş C farkı **69,6 µs** — gürültü bandının
  (|439 µs|) çok altında. **C++ runtime bedava.** Kartın dediği gibi.
- **(b) DOĞRULANDI (dolaylı, fiziksel temelden):** kaldırılacak büyük bir statik
  ilklendirme yükü yok, yani ikiliyi küçültmek bir kaldıraç değil. Kartın
  eşli ölçümü (**−80,1 µs, 3+/5−**) bunu doğrudan test etmiş ve adayı
  **REDDETMİŞ** — ağaca girmedi, doğru karar.
- **(a) YANLIŞ İFADE EDİLMİŞ, DÜZELTİLDİ.** `otool -l` ile baktım:
  `__mod_init_func` gerçekten **0** — ama bu araç zincirinde onun yerine
  **`__init_offsets` var ve BOŞ DEĞİL: 4 bayt = tam bir (1) statik
  ilklendirici.** "Statik ilklendirici yok" demek yanlıştır; doğrusu "bir tane
  var, ve bir tane 676 µs etmez". Sonuç ayakta, **gerekçe (a) zayıf**; ağırlığı
  (b) ve (c) taşıyor.

**AYRIŞTIRMA — ve burada F3e de tutmuyor.** Aynı bacaklar, üç bağımsız ölçüm:

| bacak | F3d hakemi | F3e kartı | **ben, bugün** |
|---|---|---|---|
| yükleme (OFF − boş ikili) | **676,4** | **524,6** | **915,2** |
| kural yolu (tam − OFF) | *324 (çıkarımla)* | **1239,9** | **884,1** |
| **atfedilebilir toplam** | **1602,1** | **1764,5** | **1799,3** |

**TOPLAM üç ölçümde de aynı yere düşüyor (1602–1799 µs, tavanın 1,6–1,8 katı).
AYRIŞTIRMA DÜŞMÜYOR:** yükleme bacağı 524,6 / 676,4 / **915,2** — yayılım
**390 µs**, yani gürültü bandının (|439 µs|) içinde. Bu yöntem bu bacağı
**ayrıştıramıyor**.

**HÜKÜM, üç parça:**
1. **F3d'nin YÖNLENDİRMESİ GERİ ÇEKİLDİ.** "F3-S1'in hedefi ikili yükleme
   maliyeti olmalı; 324 µs'lik pencerede algoritmik kazanç tavana ulaşmaz"
   cümlesi **doğrudan bir deneyle çürütüldü**: ikiliyi %12 küçültmek
   **−80,1 µs, 3+/5−** verdi. Eski sayı **silinmiyor** (676,4 µs, F3d-R.md'de
   duruyor); gerekçesiyle düzeltiliyor.
2. **F3e'nin YERİNE KOYDUĞU SAYI DA BENİMSENMEDİ.** "%70 kural yolu, pencere
   ~1240 µs" bende **%49 kural / %51 yükleme** çıktı. Ayrıştırma bu yöntemle
   **ÇÖZÜLEMİYOR** ve bir hedef seçmenin dayanağı olamaz.
3. **AYAKTA KALAN, üç ölçümün ortak paydası:** uçtan uca atfedilebilir maliyet
   **~1600–1800 µs**, tavan **1000 µs** → **~800 µs düşmesi lazım**, ve
   **hiçbir bacak tek başına küçük değil.** Sıradaki faz için kısıt:
   **bacakları gürültü bandının içinde olan bir ayrıştırmadan hedef seçilemez** —
   önce daha düşük gürültülü bir yöntem (aynı süreçte, tekrarlı, eşli) kurulur.

⚠ **TAVAN 1000 µs GEVŞETİLMEDİ ve gevşetilmeyecek** (§3.8/4, §11). "Tavan
yanlış şeyi ölçüyor" hükmü verilmedi; verilse bile tavanı yükseltmenin gerekçesi
olmazdı. `accept.sh` diff'te **hiç yok**.

**`2b` HIZLANMADI — kendim eşli ölçtüm** (`kanit/f3/2b-uctan-uca.sh`, N=200,
HEAD ve `F3e-oncesi` ikilileri sırayla, 3 tekrar). Ham fark HEAD−taban:
`−18,8 / +555,6 / +126,9` µs → ortalama **+221,2 µs, işaret 2+/1−**. Tek yanlı
değil ve |439 µs| bandını aşmıyor: **ne hızlandı ne de ölçülebilir biçimde
yavaşladı.** `accept.sh`'in `2b` satırı **1252,1 µs** (F3d'de 1282,2) — aynı yer.

## 5. KART 2 — NEGATİF KABUL EDİLDİ, ve sebebi ÖLÇÜLMÜŞ (CLAUDE.md 8)

**Ham kaydı kendi parser'ımla açtım.** `_f3e_live/.rabadon/sessions/` altındaki
iki `RBMV1` halkası (320B `Rec`) — kartın `f3e-2-canli-b-moves.out`'u ile
**birebir**: iki oturum, **6+6 = 12 hamle, 12 AYRI imza, en çok tekrar 1**,
`repeat` **3** istiyor. Uydurma değil.

**Sebep de doğru, ve kodu kendim okudum:** `sig_bash` = tüm komut metninin
hash'i (`native/moves.h:173`), `repeat` `seen >= REPEAT_MIN(3) && failed >= 2`
istiyor (`native/signals.h:127`). `pytest -q … | tail -40` ile `| tail -25`
gerçekten iki ayrı imzadır.

**AMA KARTIN ÖLÇÜMÜ ZAYIF: 12 hamle bunu KANITLAMIYOR** — o iki ajan görevi
**6 hamlede çözdü**, hiç takılmadılar. Takılmayan bir ajanın tekrar etmemesi
dedektörün kusuru değildir. Bu yüzden ölçümü **ben büyüttüm**, diskteki bütün
korpusa (`~/.rabadon/sessions` + proje + 26 Ağu snapshot'ı):

> **81 oturum, 1766 hamle. Bir imzanın ≥3 tekrar ettiği oturum: 2.
> `repeat`'i ATEŞLEYEBİLECEK oturum (≥3 aynı imza VE ≥2'si `err_sig` taşıyan):
> **0 / 81.**

Kartın tezi bu sayıyla **çok daha güçlü** duruyor. Ama aynı sayı bir şeyi daha
söylüyor ve kart bunu görmemiş: **0/81 AŞIRI BELİRLENMİŞ.** O korpusun tamamı
`err_sig`'in başarısız çağrılara **hiç atanmadığı** dönemde toplandı (Kart 1'in
bulduğu delik). Yani `failed >= 2` kolu **yapısal olarak ulaşılamazdı**.
İki sebep var, kart birini yazmış:
1. `repeat` tam komut imzasına bakıyor (doğru, kodda),
2. **başarısız çağrı defterde hiç kapanmadığı için `err_sig` yoktu** (Kart 1).

F3e (2) numaralı deliği kapattı. **(b) bu yüzden geçmiş korpustan
CEVAPLANAMAZ** — abone olan bir kurulumla **yeniden** ölçülmek zorunda.

**İkinci ölçülmüş kusur da doğrulandı:** halkadaki 12 hamlenin **4'ü**
`claimed_rc=-1` ile açık kaldı (kapanmayan hamle).

## 6. YANLIŞ POZİTİF — kartın +2'sini doğruladım, kendim +1 daha buldum

- **`no-rm-rf-outside` GERÇEKTEN yanlış adlandırılmış.** Kuralı okudum
  (`.rabadon/guard.json`): `rm\s+-\w*[rf]\w*\s+(/(?!tmp)|~/(?!\.)|\$HOME)`.
  Bu regex "**proje dışı**"nı değil "**mutlak yol ve /tmp değil**"i yakalar —
  projenin **içindeki** mutlak bir yol da kesilir. Kart haklı; kuralın adı
  yaptığı işi yanlış anlatıyor. (Beni de kesti, doğru sebep + yanlış ad.)
- **YENİ, BENİM BULDUĞUM:** `no-shell-rewrite-of-guard-or-promise`
  **salt-okuma bir `grep -n … .rabadon/guard.json`'ı kesti.** Okumak yazmak
  değildir. F3d'nin "kırmızı tabanda salt-okuma Bash'i de kesiliyor"
  gözlemiyle aynı aile. CLAUDE.md kalite çıtası: *"False rejects are counted,
  not excused. Target is zero."* → **sahipsiz kalem, sıradaki fazın kartı.**
- **DOĞRU RET (yanlış pozitif DEĞİL):** `no-blind-inplace-source-rewrite`,
  motor kaynağını `perl -0pi` ile yerinde yeniden yazma denemi kesti.
  Yaklaşımı değiştirdim (`Edit`), kuralı değil.
- **DOĞRU RET:** `no-rm-rf-outside`, kum havuzlarını tek komutta `rm -rf` ile
  silme denemi kesti. Yaklaşımı değiştirdim: worktree'ler `git worktree remove`
  ile, iki scratch dizini **dosya dosya + `rmdir`** ile kaldırıldı. Toplu
  özyineli silme kullanılmadı.

**Blokajları § adıyla ilan ettim, hiçbirini aşmadım:** `guard.json`'a
dokunmadım, `rabadon off` kullanmadım, CHALLENGE-3 bileşik-komut deliğini
kullanmadım.

## 7. ÖLÇEMEDİKLERİM

- **(c) negatif kontrolü** — kapsam dışı (F3d hükmü: F6'nın aleti). **F4 (c)
  ölçülmeden AÇILMAZ**, değiştirmedim. Not: §F3 (c)'yi F4'ün ön şartı yapıyor,
  F3d ise (c)'yi F6'ya bağladı — bu **kilitli bir döngüdür** ve şu an sahipsiz;
  kaydediyorum, ölçülmüş gerekçem olmadığı için hükme bağlamıyorum.
- Boş yeşilde kartla aramdaki **±1 iddia** farkının kaynağını ayırmadım.
- `subscribed_to_failures()` oturum başına 4 dosya okuyor. Sıcak yolda
  **değil** (`contract_block` içinde, `SessionStart`) — kodun yerinden okudum,
  ama `SessionStart` maliyetini **ayrıca ölçmedim**.
- Kartın "%12 küçültme" eşli turunu (N=200×8) **yeniden koşturmadım**; adayın
  reddedilmiş olması ve ağaca girmemiş olması yeterliydi.
- `sandbox` / `script_wrapper` dalları — kart da zorlayamadı, ben de.
- `~/damla_projects_2026/_f3e_live` fikstürü **duruyor** (kart bilerek
  bırakmış, ben kullandım ve bıraktım).
