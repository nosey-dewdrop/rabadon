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
