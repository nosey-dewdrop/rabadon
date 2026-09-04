# DENEMELER — koşu döngüsünün kendi kabulü (B6 smoke)

Tek yazar: o turun yapan oturumu (B1.7). Yeni blok EN ALTA eklenir.

## deneme 1 — 2026-08-24 (tur 1, yapan)

**DENENEN.** B6.3 (OPERATÖR yolu) ve B6.5 (watchdog) sürücünün davranışıdır,
yapan oturumun değil — canlı döngünün içinden koşulamaz, çünkü yapan zaten
sürücünün çocuğudur. Bu yüzden `scripts/kos-smoke.sh` yazıldı: /tmp'de tek
kullanımlık git deposu + sahte `claude` ile **gerçek scripts/kos.sh** koşturulur.
Test edilen dosya değiştirilmez; yalnız belgelenmiş env knob'ı (STALL_TIMEOUT=60)
dışarıdan verilir, `sleep 300` operatör anketi KISALTILMAZ.

**SONUÇ.** İlk koşu B6.5'te düştü: 240 sn'de `1.out` hiç gelmedi, yani asılı
oturum HİÇ kesilmedi. `bash -x` izi kök sebebi verdi:

```
+ chg=./.kosu-nabiz.41364        <- watchdog'un KENDI nabiz markeri
+ '[' -n ./.kosu-nabiz.41364 ']' <- "aktivite var" -> stall=0, sonsuza kadar
```

Doğrudan ölçüm (`touch ./.mark; sleep 1; find . -type f -cnewer ./.mark`):
macOS/BSD find `-cnewer REF` **REFERANSIN KENDİSİNİ de eşleştirir**; GNU find
etmez. Marker prune edilmediği için `chg` her turda dolu, `stall` hiç artmıyor,
**STALL KILL hiç ateşlenmiyor.** B1.6'nın "son savunma"sı macOS'ta ölüydü.

İkinci kanıt: ilk koşu iptal edilince sahte asılı çocuk (pid 30471) **PPID=1
yetim** olarak hayatta kaldı — `set -m` yüzünden ayrı process grubunda, yani
onu yalnız `grup_oldur` öldürebilir. Watchdog ölüyken bir TTY-bekleyen araç
gece boyu yaşar; belgenin "yetim claude gece boyu para yakamaz" zırhı bu hata
yüzünden geçersizdi.

**ELENEN HİPOTEZ.**
- "Watchdog yalnız STALL_TIMEOUT ayarıysa çalışmaz" — ELENDİ, knob doğru
  geçiyordu (izde `[ 0 -ge 60 ]` görünüyor), sorun `chg`'nin hep dolu olması.
- "kos.sh doc'tan sapmış olabilir" — ELENDİ, `diff` doc ile birebir aynı.
- "İki-nabız fikri yanlış, dosya aktivitesi nabzı atılmalı" — ELENDİ:
  prune sonrası gerçek dosya aktivitesi HÂLÂ görünüyor (B6.0 ikinci assert),
  yani fikir sağlam, uygulaması taşınabilir değildi.

**KALAN HİPOTEZLER / açık uçlar.**
- `$i.out.raw` ve `.raw.err` marker'dan SONRA yaratıldığı için ilk çevrimde
  "aktivite" sayılıyor; stall bir çevrim (60 sn) geç başlıyor. Zararsız
  (öldürme yönünde değil yaşatma yönünde yanılıyor) ama ölçülmedi.
- B6.4 (tekrar freni / DENEMELER'den hipotez eleme) sahte `claude` ile
  dürüstçe test EDİLEMEZ — gerçek değerlendiren modeli gerekir. Döngünün
  kendi seyrinde kanıtlanmalı, burada DEĞİL.
- `DISABLE_AUTOUPDATER=1` bu turda eklendi ama **canlı sürücü onsuz başladı**;
  sürüm sabitliği ancak sürücü yeniden başlatılınca yürürlüğe girer.

**DÜZELTME.** `-name '.kosu-nabiz.*' -prune` nabız ifadesine eklendi; hem
`scripts/kos.sh`'e hem KOSU-RABADON-2.md §B2'ye (doc tek kaynak, diff birebir).
Regresyonu tutan 2 saniyelik test kos-smoke.sh'e B6.0 olarak kondu.

## deneme 2 — 2026-08-24 (tur 4, yapan)

**BAĞLAM.** Bu oturum, tur 3 kararını TALİMAT olarak aldı. Tur 3 kararı bir
`OPERATÖR:` sorusuydu. Yani yönlendirme hatası gerçekten oldu ve kanıtı bu
oturumun kendisidir (`reports/kosu/son.talimat` == `reports/kosu/3.karar`).

**CHALLENGE — "sürücü bozuk" teşhisi YANLIŞ. Bozuk olan belgedir.**

Tur 3 yapan oturumu "kos.sh kararın sadece ilk satırına bakıyor, herhangi bir
satırına bakmalı" dedi. Kanıt bunu çürütüyor:

    scripts/kos.sh:253  ilk="$(printf '%s\n' "$karar_ham" | sed ... | head -1)"
    scripts/kos.sh:255  OPERATÖR*|OPERATOR*)

Sürücü ilk satıra bakıyor ve bu DOĞRU davranıştır, çünkü
`docs/DEGERLENDIREN.md:40` aynen şunu garanti ediyor:

    Cevabın yalnız üç biçimden biridir; İLK SATIR biçimi belirler; başka
    hiçbir şey (selamlama, başlık, açıklama) yazmazsın

Sürücü belgeye birebir uyuyor. Kök sebep başka yerde: **aynı belge kendisiyle
çelişiyor.** `docs/DEGERLENDIREN.md:18` şunu emrediyor:

    TEKRAR KONTROLÜ (her kararda ilk iş): GUNLUK'a bak — ...

"her kararda ilk iş" ifadesi değerlendireni ilk satıra `TEKRAR KONTROLÜ:`
yazmaya itiyor; satır 40 ise ilk satırın biçim etiketi olmasını şart koşuyor.
İki talimat aynı satır için yarışıyor ve 18 kazanıyor. GUNLUK.tsv üç turun
üçünde de bunu gösteriyor — hiçbir kararın ilk satırı biçim etiketi değil:

    1  GUNLUK'a bakıyorum: ilk tur, tekrar yok. ...
    2  TEKRAR KONTROLÜ: GUNLUK'ta 1 tur, tekrar yok. ...
    3  TEKRAR KONTROLÜ: GUNLUK'ta 2 tur, tekrar yok. ...

Tur 1 ve 2 talimattı, `*)` dalına düşmeleri zararsızdı; hata ancak tur 3
operatör sorusu olunca görünür oldu. Yani bu bir tur-3 kazası değil, üç
turdur sessizce çalışan bir belge hatasıdır.

**ELENEN HİPOTEZ.**
- "kos.sh'in eşleşmesi bozuk / herhangi bir satıra bakmalı" — ELENDİ.
  Sürücü belgeye birebir uyuyor; `head -1` kasıtlıdır. Sürücüyü
  "herhangi bir satır"a çevirmek, gövdesinde `OPERATÖR:` kelimesi geçen her
  normal talimatı operatör durağına çevirir — bugünkünden beter.
- "Operatör sorusu OPERATOR.md'ye yazıldı, operatör görmedi" — ELENDİ.
  `reports/kosu/OPERATOR.md` hiç yaratılmadı; `case` eşleşmediği için o
  koda hiç girilmedi. Operatörün cevaplayabileceği bir kanal YOKTU.

**ÖNERİLEN DİFF (uygulanmadı — operatör kararı bekliyor).**
`docs/DEGERLENDIREN.md` satır 18 ve KOSU-RABADON-2.md §B3'teki birebir
kopyası (iki dosya `diff` ile aynı olmak zorunda, doğrulandı) şöyle olur:

    TEKRAR KONTROLÜ (her kararda ilk iş, ama İLK SATIRA DEĞİL — biçim
    etiketinden sonraki satıra yazılır): GUNLUK'a bak — ...

ve satır 40'a şu eklenir:

    İlk satır HER ZAMAN tam olarak şunlardan biridir: bir talimat cümlesi,
    "OPERATÖR:" veya "BİTTİ:". "TEKRAR KONTROLÜ:", selamlama, başlık ya da
    özet ilk satıra YAZILAMAZ — sürücü ilk satıra bakar, gerisini okumaz.

Bu, tur 3'ün operatöre sorduğu (b) seçeneğidir. Değerlendiren de (b)'yi
önermişti; bu oturum kanıtla aynı sonuca bağımsız vardı. Ama CLAUDE.md
"If PROJECT.md itself is wrong" kuralı gereği yapan oturum bunu SESSİZCE
UYGULAMAZ: diff burada duruyor, uygulaması operatör onayına bağlı.

**PROTOKOL İHLALİ (ikinci bulgu, sorulmamıştı).**
Tur 3 kararı harness seçimini (hangi org/repo, hangi commit) operatöre
sordu. Bu `docs/DEGERLENDIREN.md:16`'nın açık ihlali — "operatöre teknik
soru GİTMEZ" — ve KOSU-RABADON-2.md §A1 zaten harness seçimini operatör
sorusu değil, beklerken yapılacak ORTAK İŞ olarak sayıyor. Bu yüzden bu
oturum harness'ı bekletmeden seçti (aşağı bak). Operatöre kalan tek gerçek
soru R7a/R7b bölünmesidir.

**YAPILAN İŞ.** `reports/R7/HARNESS.md` yazıldı: SWE-bench/SWE-smith,
commit 057f0478b6918bfcd89a51ceeec7229c60bb1028 (tag v0.0.6), hash uzak
repodan `git ls-remote --tags` ile çözüldü. Gerekçe metrikten türetildi
(6a `heldout_pass`, 5b `instance_id` — SWE-bench sözlüğü).
Ölçüm: `./reports/R7/accept.sh` 4 yeşil / 22 kırmızı  ->  6 yeşil / 20 kırmızı.
4d bilerek kırmızı bırakıldı: o hazırlık henüz YAPILMADI, yazmak boş yeşil
olurdu (accept.sh başlığı: "NO ASSERTION MAY PASS VACUOUSLY").
