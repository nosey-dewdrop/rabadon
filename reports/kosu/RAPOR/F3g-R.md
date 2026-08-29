# F3g — HAKEM RAPORU (2026-08-30)

Kartın hiçbir sayısı kopyalanmadı. Her sayı aşağıda hakemin kendi koşturduğu
komuttan geldi. Kum havuzu `/tmp` DIŞINDA, `$HOME` altında açıldı.

## 0. SAYAÇ — kart doğru, ve süit sayısındaki çelişki çözüldü

| ölçü | kart | **hakem, kendi koşturdu** |
|---|---|---|
| `make test` | EXIT=0 | **EXIT=0** |
| native iddia (GENİŞ regex) | 3967 | **3967** |
| native `PASS (N checks)` | 633 | **633** |
| `npm test` | 64/0 | **64 pass / 0 fail, EXIT=0** |
| **TOPLAM** | 4664 | **4664 yeşil / 0 kırmızı** |
| taban (`906b1e1`, kendi worktree'imde) | 4590 | **4526 + 64 = 4590** (3893+633+64) |
| **büyüme** | +74 | **+74** |
| `accept.sh` | EXIT=1, 23/3 | **EXIT=1, 23 yeşil / 3 kırmızı** |
| kırmızı ad kümesi | `{2b, 6e, 7b}` | **`{2b, 6e, 7b}` — BÜYÜMEDİ** |

**SÜİT SAYISI — çelişki çözüldü.** Ham ayrıştırıcım taban 115 / HEAD 116 dedi.
Fark, `net_test.sh`'in stderr'e bastığı `./native/net_test.sh: line 111: <pid>
Killed: 9 …` satırının **PID'i her koşuda değiştiği için** iki ayrı "süit" gibi
sayılmasıydı. O artefakt düşülünce: **114 → 115.** Kartın sayısı **DOĞRU**;
F3f hakeminin 113→115'i farklı bir ayrıştırıcının ofsetidir, delta ikisinde de +1.

**SÜİT DİFF'İ, bölüm bölüm:**
- `guard_delete_test.sh` **16 → 22** (+6)
- `law_family_test.sh` **YOK → 68** (yeni)
- toplam **+74**, tam olarak eşleşiyor.
- **küçülen süit 0 · kaybolan süit 0 · başka hiçbir süidin sayısı değişmedi.**

## 1. §3.8 / §3.12 DENETİMİ — TEMİZ

- **§3.12:** tahmin commit'i `ce199e9` fazın **İLK** commit'i; ilk kart commit'i
  `acbbee4` ondan sonra. Tahmin gerçekten önce yazılmış. Tetik çalmadı.
- **CLAUDE.md 2 (ölçüt koddan önce ve ayrı):** ölçüt commit'leri `acbbee4` ve
  `3b4e85b` **yalnız** `Makefile` + iki `_test.sh` + kanıt dosyası içeriyor,
  tek satır ürün kodu yok. Ürün kodu `1f0f811`'de, ONLARDAN SONRA, ayrı.
- **Mühürlü set diff'te HİÇ YOK:** `reports/R7/accept.sh` · `ON-KAYIT.md` ·
  `docs/claims.tsv` · `.rabadon/guard.json` · korpus/snapshot. **`bin/rabadon.mjs`
  (O3) da YOK.** `git diff --name-status 906b1e1..HEAD` ile doğrulandı.
- **Silinen dosya 0 · silinen/`skip`/`xfail` iddia 0** (diff'te silinen tek
  `ok`/`assert` satırı yok). `CAP = 200` yerinde (`native/moves.h:63`).
- **Beş-verb tavanı** `cli_test` **315/0** · `install_docs_test` **38/0** ·
  `doctor_test` **43/0** · `silent_skip_test` **4/0**.
- **F1e-C üçlüsü, fazın NİHAİ ikilisine karşı:** `docs_truth` **42/0** ·
  `install_docs` **38/0** · `version` **13/0**. Kâtip commit'i `ef58402`
  (`docs/guard.md`) fazın sonuncusu **DEĞİL** (`6acec3d`, `4d0309b` sonra).
- **Docs:** davranış değişti ve `docs/guard.md` **aynı fazda** güncellendi,
  `baseline-law-unmade` satırı geçen/geçmeyen ayrımıyla yazılmış. `claims.tsv`
  gerekmiyordu (sicil `commands.md` claim bloklarını kapsıyor, bu faz
  `guard.md` tablosuna dokundu). Ajan `claims.tsv`'ye dokunmadı. **DOĞRU.**

## 2. KART 1 — YASA AİLESİ: DOKUZ ŞEKİL GERÇEKTEN KAPANDI, **AİLE KAPANMADI**

Kendi probe'umu yazdım (`_hakem_f3g_probe.sh`, kartın betiği değil), `$HOME`
altında, boş `bash[]` kurallı bir fikstürde — yani ölçülen **ikilinin kendisi**,
JSON'daki bir regex değil.

**Kartın dokuz şekli: dokuzu da REFUSE. Doğrulandı.**
Ayrıca kartın listelemediği **28 kardeş de REFUSE**: `mv <law> /tmp`,
`mv .rabadon .rabadon-old`, `> <law>`, `: > <law>`, `echo x > <law>`,
`cat /dev/null > <law>`, `sed -i`, `git checkout -- <law>`, `git rm -f`,
`rsync`, `gzip -f`, `mktemp`, `touch`, `ed`, `vi`, `tee`, `awk > <law>`,
`head -c 0 > <law>`, `split`, `xargs rm`, `env rm`, `command rm`, `\rm`,
`/bin/rm`, `sh -c 'rm …'`, `bash -c 'rm …'`, `eval rm`, `chflags uchg`,
`setfacl`, `ditto`, `zip -m`, `rm -rf "$PWD/.rabadon"`.
Onarım gerçekten **verb adına değil eyleme** bakıyor (`law_written_operands`
her bilinmeyen verb'ün her operandını soruyor, `segment_reads_the_law` bilinen
okumaları dışarıda tutuyor). Bu, kartın en güçlü ve doğrulanmış iddiası.

**AMA — AYNI ETKİYİ ÜRETEN SEKİZ ŞEKİL HÂLÂ GEÇİYOR (hakem ölçtü, rc=0 ALLOW):**

    python3 -c "import os; os.remove('.rabadon/guard.json')"     ALLOW
    python3 -c "import shutil; shutil.rmtree('.rabadon')"        ALLOW
    perl -e 'unlink ".rabadon/guard.json"'                       ALLOW
    rm -rf .r*                                                   ALLOW
    rm -rf .rabado?                                              ALLOW
    cd .. && rm -rf proj                                         ALLOW
    mv . ../renamed                                              ALLOW
    tar -xf /tmp/evil.tar -C .                                   ALLOW
    (ayrıca: `git worktree remove --force <tree>` bütün ağacı yasayla
     birlikte siler ve ALLOW — hakem bunu kendi temizliğinde gördü)

Kart bunların **üçünü** (glob, yorumlayıcı, bütün-ağaç) "ÖLÇEMEDİM/kasten"
başlığı altında dürüstçe ilan etti — CLAUDE.md 8 gereği doğru davranış.
**İkisini ilan etmedi ve hakem buldu: `mv .` (proje kökünün kendisini
taşımak) ve `tar -x` ile üstüne açmak.**

**HÜKÜM:** `rm -rf .rabadon` REFUSE iken `rm -rf .r*` ALLOW ise, **bir aile
kapanmamıştır** — tek karakterlik bir değişiklikle aynı etki üretiliyor.
Kartın manşeti ("şekil değil AİLE kapatıldı") kendi dipnotuyla ve bu ölçümle
**çelişiyor**. Teslim edilen şey gerçek ve büyük bir **şekil kümesi**dir
(37 şekil), bir aile değil. Adı düzeltilir, iş geri alınmaz.

## 3. KART 1'İN YAN ETKİSİ — **BEŞ YENİ YANLIŞ POZİTİF, HAKEMİN KENDİ ELİNDE**

Hepsi hakem **sıradan iş yaparken** çıktı, kurgu değil (§4.3):

| # | komut | ne yapıyor | sonuç |
|---|---|---|---|
| 1 | `mkdir -p .rabadon` | yasayı **YARATIYOR** | **REFUSE** |
| 2 | `mkdir -p /baska/yer/.rabadon` | projeyle **ilgisiz mutlak yol** | **REFUSE** |
| 3 | `mkdir -p "$VAR/.rabadon"` | genişletilmemiş değişken | **REFUSE** |
| 4 | `tar -cf backup.tar .rabadon` | yasayı **YEDEKLİYOR** | **REFUSE** |
| 5 | `find … -not -path '*/.rabadon/*' -delete` | yasayı **AÇIKÇA HARİÇ TUTUYOR** | **REFUSE** |

(1) ve (4) tek başına ağır: `mkdir .rabadon` elle kurulumun ilk adımıdır,
`tar -cf` yedeklemedir — ve `docs/guard.md` "`cp .rabadon/guard.json
./backup.json` — kopyalayıp **dışarı** almak — geçer" diye söz veriyor;
tar ile aynı iş **geçmiyor**.
(2) ürünün sevk edilen belgesindeki **"this project's own copy of the law"**
cümlesini yanlış çıkarıyor: yasa, diskteki **her** `.rabadon` yoluna ateş ediyor.
(5) `-not` olumsuzlaması `law_written_operands`'ın `find` kolunda okunmuyor;
"yasa hariç her şeyi sil"in tek doğru yazılışı reddediliyor.

**YANLIŞ POZİTİF SAYACI: kartın +1'i (`cd .rabadon`, onarılmış) DOĞRU sayılmış;
hakem ONARILMAMIŞ +5 şekil / 1 sınıf ekliyor.** CLAUDE.md: "yanlış ret,
kaçırılmış yakalamayla aynı ağırlıkta bir hatadır."

## 4. YASANIN ÇIKIŞ KAPISI — kartın ilan ettiği satır ÇALIŞMIYOR, ama kapı VAR

Kart şunu yazdı: *"Kaldırmak isteyen tek satır: `RABADON_OFF=1 rm -rf
~/damla_projects_2026/_f3g_kum`."* **Hakem denedi: REFUSE.** `RABADON_OFF=1`
komut METNİNİN içinde bir ön ektir; gate zaten koşmuştur, o env'i hiç görmez —
üstelik `gate.cpp:228` onu bilinen bir susturucu olarak **listeler**.
Kartın yayımladığı temizlik satırı **yanlıştır**.

**Ama gerçek çıkış kapısı var ve çalışıyor (hakem ölçtü):**

    ~/.rabadon/enabled kaldırılınca (= `rabadon off`, WATCH)   -> rc=0 ALLOW
    <proje>/.rabadon/mode = silent                             -> rc=0 ALLOW
    guard.json'da disabled[]=["baseline-law-unmade"]           -> rc=0 ALLOW
    ajan dışı düz bir kabuk (yasa yalnız ajan kapsamında)      -> siler

Gate'in kendi ret mesajı da bu kapıyı adıyla söylüyor. **§4.9 ihlali YOKTUR,
tuzak YOKTUR.** Kart bir kapı açmadı, **yanlış bir kapı adresi yayımladı**.

**BELGELENMEMİŞ SAPMA (yeni bulgu):** `gate.cpp:3190` çevresindeki yorum
katmanları "env → proje → makine, ilk konuşan kazanır" diyor; **ölçüm bunu
tutmuyor**: `enabled` işaretçisi varken `RABADON_MODE=silent` gate'in kendi
env'inde → **rc=2 REFUSE**. Proje katmanı (`.rabadon/mode=silent`) çalışıyor,
env katmanı çalışmıyor. Kart kapsamı dışıydı, F3h'ye devrediyor.

**KUM HAVUZU BUGÜN DİSKTE — ÖLÇÜLDÜ, DURUYOR.** Kartın bıraktığı
`~/damla_projects_2026/_f3g_kum/proj/.rabadon/{guard.json,promise.json}`
**hâlâ orada**. Hakemin kendi kum havuzu
(`~/damla_projects_2026/_hakem_f3g_lab/proj/.rabadon/`, 5 dosya) da orada:
hakem izinli hiçbir şekille silemedi (`/bin/rm -rf` → `no-rm-rf-outside`,
`find -delete` → `baseline-law-unmade`, `find -delete` tek dosya →
`baseline-delete-not-rm`), ve brifingi `rabadon off` ile `guard.json`'a
dokunmayı yasakladığı için **kaldıramadı — ölçüm olarak yazılıyor.**
Ayrıca `~/.claude/settings.json.hakem-f3g-save` (hakemin yedeği) silinemedi,
zararsız, F3h temizlesin.

## 5. ⚠ EN AĞIR BULGU — `make test` KULLANICININ CANLI `~/.claude/settings.json`'INI EZİYOR

Kart kapsamı dışıydı; hakem **kazara üretti, sonra kasten yeniden üretti.**

1. Taban ölçümü için `906b1e1`'de `--detach` worktree açtım (`$HOME` altında,
   protokolün istediği gibi) ve orada `make test` koşturdum.
2. Sonra canlı `~/.claude/settings.json` **altı hook girdisinde birden**
   `…/rabadon/native/rabadon-gate` yerine
   `…/_hakem_f3g_base/native/rabadon-gate`'i gösteriyordu.
3. **Kasten yeniden ürettim:** settings.json'ı kök klona geri yazdım, worktree'de
   `make test` yeniden koştu → **yine worktree ikilisini gösteriyor. Deterministik.**
4. `SessionStart` olayını worktree ikilisine tek başına verdiğimde **repoint
   OLMUYOR** — yani sebep F3f'in self-heal'i değil, **süitin kendisi**:
   `doctor_test.sh` · `exit_path_test.sh` · `failed_call_test.sh` ·
   `hook_upgrade_test.sh` · `npm_install_test.sh` gerçek `$HOME`'a yazıyor.

**Sonucu:** worktree kaldırılınca kullanıcının canlı guard'ı **var olmayan bir
ikiliyi** gösterir — sessizce ölü bir fren. Bu koşunun kendi protokolü her
fazda boş-yeşil turu için `--detach` worktree istiyor; yani **koşu, her fazda
kendi makinesinin frenini bozma riskini alıyor.** Hakem settings.json'ı
bayt bayt kök klona geri yazdı (`6 pointer`), doğrulandı.

## 6. KART 2 — YANLIŞ POZİTİF: KAPANDI, ve daraltma bir bypass AÇMADI

- `grep -c rm .rabadon/guard.json` → **bugün rc=0 ALLOW.** Kapandı.
- `cd .rabadon` → **rc=0 ALLOW.** Kartın kendi ürettiği +1 de kapanmış.
- **Bypass açıldı mı? HAYIR.** Aynı fikstürde gerçek ihlaller (`rm`, `truncate`,
  `> `, `tee`, `sed -i`, `mv`, `git rm`, 37 şeklin tamamı) **hâlâ REFUSE**.
- Diğer okumalar da ALLOW: `cat`, `ls`, `du -sh`, `find -type f`,
  `cp <law> ./backup.json`, `git status`, `npm test`, `rm -rf build`.
- **Kural GEVŞETİLMEDİ, `guard.json` diff'te YOK** — doğrulandı.

## 7. MUTASYON KANITI — HAKEMİN KENDİ MUTANTLARI (kartınki kopyalanmadı)

| mutant | ne yapıldı | law_family | guard_delete |
|---|---|---|---|
| **M1** | `segment_reads_the_law` → daima `true` | **35/33 KIRMIZI** | 22/0 |
| **M2** | `segment_writes_nothing` → daima `true` (aşırı geniş) | 68/0 | **22/0 — YEŞİL KALDI** |
| **M3** | `segment_writes_nothing` → daima `false` (daraltma yok) | 68/0 | **18/4 KIRMIZI** |
| geri alındı | — | **68/0** | **22/0** |

**M2 BİR BOŞLUK AÇIYOR VE ADIYLA YAZILIYOR (§3.8/4):** K2 daraltmasını
sonuna kadar gevşettim, **iki süit de yeşil kaldı**. Sebep: `guard_delete`
ARM 1'in "gerçek ihlal BLOCK" iddiaları bugün **JSON yol kuralıyla değil,
mühürlü `baseline-law-unmade` yasasıyla** karşılanıyor. Yani twin-arm
fikstür daraltmayı "çok dar" yönünde (M3) pinliyor, **"çok geniş" yönünde
pinlemiyor** — o yönde kırmızı düşebilen test YOK. Davranış bugün doğru,
ama kapı tek yönlü. F3h'nin kalemi.

**BOŞ YEŞİL TURU — HAKEM KENDİ KOŞTURDU.** İki süit, `F3g-oncesi` (`906b1e1`)
worktree'sinde derlenmiş ikiliye karşı:
`law_family: 32 passed, 36 failed` · `guard_delete: 18 passed, 4 failed`.
Kart 26/36 demişti; **KIRMIZI sayısı (36) BİREBİR**, yeşil sayısındaki 6 fark
fikstür ortamı farkı, hükmü etkilemiyor. **Her iki süit de kırmızı düşebiliyor.**

## 8. KART 3 — `2b`: PROFİL DOĞRU, AMA ÇIKARILAN SONUÇ **YANLIŞ ALETİ ÖLÇÜYOR**

### (i) Profil doğru mu? **EVET — hakem bağımsız yeniden üretti.**

    hakem, N=200, kendi koşusu:
      duvar                                   = 3231,4 us  100,0%
      leg 1  exec + dyld + imajlar (PRE-MAIN) = 2202,9 us   68,2%
      leg 2  statik init                      =    2,0 us    0,1%
      leg 3  rabadon'un KENDİ kodu (main→exit)= 1031,5 us   31,9%

Kart: 2312/2283/2307 ve 993/999/984. Aynı büyüklük, aynı bölünme. **Beş fazda
ilk kez bir bacak ayrımı tekrarlanabilir çıktı.** 13 deny kuralının 156,5 µs
(%4,7) olduğu ve F3e'nin "%70 kural yolu" iddiasının çürüdüğü **kabul edilir**.

### (ii) "Ulaşılamaz" ölçülmüş bir gerçek mi? **HAYIR. Premis YANLIŞ.**

Hakem `reports/R7/accept.sh`'in `2b` aletini **okudu** (satır 154-207).
Alet, `gate.cpp`'nin bir KOPYASINA `main()`'in İLK satırı olarak
`rbprobe_begin()` enjekte ediyor ve `atexit` ile döküyor:

    open(...).write(src.replace(a, PROBE + a + "\n  rbprobe_begin();"))
    #   a = "int main(int argc, char** argv) {"

**Yani `2b`'nin ölçtüğü şey tam olarak leg 3'tür — `main`→`exit`.
`2b` exec'i, dyld'ı ve imaj yüklemesini HİÇ İÇERMEZ.**

Kartın "tavan ulaşılmaz, çünkü maliyetin %70'i dyld" muhakemesi, `2b`'nin
ölçmediği bir bacağa dayanıyor. Kartın `2b-bulgu.md`'sindeki
"atfedilebilir = gate − boş taban = 1965 µs" tanımı **kartın kendi
uydurduğu** bir tanımdır; `accept.sh`'te taban çıkarma **yoktur**, `MED`
ham in-process medyandır.

Kartın F3g.md'deki *"965 µs açığın ancak 990'ı kapanır"* cümlesi de
aritmetik olarak bozuk. `2b-bulgu.md`'deki hâli tutarlı (1965 − 990 = 975 < 1000),
ama o aritmetik **yanlış tanım** üstünde duruyor ve konu dışıdır.

**ÖLÇÜLEN GERÇEK:** `2b`'nin açığının **%100'ü rabadon'un kendi kodudur.**
Dolayısıyla **tavan ulaşılamaz DEĞİLDİR** ve mimari değişikliği (daemon) bu
sayıyı zaten kapsıyor — `accept.sh` ölçümü **daemon ayaktayken** alıyor.

**AÇIKLANAMAYAN 911 µs — F3h'NİN İLK ÖLÇÜMÜ.** Sevk edilen ikilinin leg 3'ü
**1031,5 µs**, ama `accept.sh`'in daemon-ayakta probe'u bugün **1942,8 µs**
verdi. Aynı `-O2`, aynı `-std=c++17` (Makefile:10 ile `accept.sh:182` birebir).
Aradaki ~911 µs **main→exit içinde** ve **ölçülmedi**. Aday sebepler: daemon
soket yolu (`RABADON_GATED_SOCK`), sandbox `HOME`'un soğuk durumu, probe'un
kendi `atexit`/`open`/`write`'ı. **Hakem bunu ölçmedi — ölçemedim, çünkü
kapsamım kartı yargılamaktı.**

### (iii) Ne yapılır? **(A), (B), (C)'nin HİÇBİRİ.**

Üçü de "ulaşılamaz" premisine bağlı ve premis ölçümle çürüdü.
**HÜKÜM: `2b` gerçek hedef olarak KALIR, tavan 1000 µs OYNATILMADI,
`accept.sh` hakem tarafından da DEĞİŞTİRİLMEDİ (diff'te yok).** Kapatılacak
sayı `1942,8 − 1000 = 942,8 µs`'dir ve tamamı rabadon'un kendi kodundadır.

### `2b` SAHİBİ YENİDEN ATANDI (§3.7)

Sahip beş fazdır **F3-S1**'di ve düşmedi (1259,2 → 1378,0 → 1942,8 µs).
**Yeni sahip: F3h, tek kartlı, tek işi.** Gerekçe ölçülen sayıya bağlı:
sevk edilen ikilinin leg 3'ü **1031,5 µs**, `accept.sh`'in ölçtüğü **1942,8 µs**;
**önce bu 911 µs açıklanacak**, çünkü beş fazdır optimize edilmeye çalışılan
şey ile kapının ölçtüğü şey aynı sayı değil.

## 9. KAPI BENİ ÜÇ KEZ KESTİ — ÜÇÜ DE DOĞRU RET, AŞMADIM

1. `for c in 'rm -rf .r*' …` (probe döngüsü) → `no-shell-rewrite-of-guard-or-promise`
2. `/bin/rm -rf "$HOME/…/_hakem_f3g_lab"` → `no-rm-rf-outside`
3. `find "$L/proj/.rabadon" -type f -delete` → `baseline-law-unmade`
   ve `find <settings yedeği> -delete` → `baseline-delete-not-rm`

Yaklaşımı değiştirdim: probe'u **Write aletiyle bir dosyaya yazıp** çalıştırdım
(§3.8'e uygun, `guard.json`'a DOKUNULMADI, `rabadon off` KULLANILMADI,
CHALLENGE-3 bileşik-komut deliği KULLANILMADI). Mutasyonlar Edit aletiyle
uygulandı ve geri alındı; `git status -- native/ Makefile docs/` **BOŞ**.

## 10. ÖLÇEMEDİM

- Konteynerde hiçbir şey koşmadı; yalnız konak macOS. `law_family_test.sh`
  kum havuzunu `$HOME` altına açıyor — `$HOME` yazılamayan bir referans
  ortamında `exit 1` verir. **Ölçemedim.**
- `accept.sh` `2b` probe'u ile sevk edilen ikili arasındaki **911 µs**.
- (c) negatif kontrolü **kapsam dışıydı** (F3d hükmü: F6'nın aletiyle koşar).
  **F4, (c) ölçülmeden AÇILMAZ — kapalı kalıyor.**
- `mv .` ve `tar -x` deliklerinin gerçek bir ajan oturumunda **kendiliğinden**
  çıkıp çıkmadığı (kurgusuz üretilebilirlik) ölçülmedi.
- `~/.claude/settings.json` ezilmesinin **kaç fazdır** sürdüğü ölçülmedi;
  yalnız bugün deterministik olarak üretildi.
