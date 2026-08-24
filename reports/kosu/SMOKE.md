# B6 — döngünün kendi kabulü (smoke), tur 1, 2026-08-24

Kabul betiği: `scripts/kos-smoke.sh` · ham çıktı: `reports/kosu/SMOKE.out`
Yeniden koşmak için: `scripts/kos-smoke.sh /tmp/kosu-smoke-run` (≈17 dk)

## Neden ayrı bir harness?

B6.3 (OPERATÖR yolu) ve B6.5 (watchdog) **sürücünün** davranışıdır, yapan
oturumun değil. Canlı döngünün içinden koşulamaz: yapan oturum zaten sürücünün
çocuğudur, kendi ebeveyninin watchdog'unu tetikleyemez. Bu yüzden harness
/tmp'de tek kullanımlık bir git deposu (+ bare remote) kurar, PATH'e sahte bir
`claude` koyar ve **gerçek `scripts/kos.sh`'i** koşturur.

Test edilen dosya DEĞİŞTİRİLMEZ — `kos.sh` birebir kopyalanır. Dışarıdan yalnız
belgelenmiş env knob'ları verilir (`STALL_TIMEOUT=60`). Operatör anketinin
`sleep 300`'ü **kısaltılmamıştır**: "döngü bekliyor" iddiası ancak gerçek bir
tam anket çevrimi boyunca beklediği görülürse kanıttır.

## Bulunan kritik hata — watchdog macOS'ta ÖLÜYDÜ

İlk koşu B6.5'te düştü: asılı oturum 240 saniyede hiç kesilmedi. `bash -x` izi:

```
+ chg=./.kosu-nabiz.41364          <- watchdog'un KENDİ nabız markeri
+ '[' -n ./.kosu-nabiz.41364 ']'   <- "aktivite var" -> stall=0, sonsuza kadar
```

Doğrudan ölçüm:

```
$ touch ./.mark; sleep 1; find . -type f -cnewer ./.mark -print
./.mark
```

macOS/BSD `find`'da `-cnewer REF` **referansın kendisini de eşleştirir**;
GNU find etmez. Marker prune edilmediği için `chg` her turda doluydu, `stall`
hiç artmadı, **STALL KILL hiç ateşlenmedi**. B1.6'nın "son savunma"sı bu
makinede yoktu — ve Linux'ta çalıştığı için sessiz kalırdı.

İkinci kanıt: ilk koşu iptal edilince sahte asılı çocuk **PPID=1 yetim** olarak
hayatta kaldı (`set -m` yüzünden ayrı process grubunda; onu yalnız `grup_oldur`
öldürebilir). Yani belgenin "yetim claude gece boyu para yakamaz" zırhı bu hata
yüzünden geçersizdi.

**Düzeltme:** nabız ifadesine `-name '.kosu-nabiz.*' -prune` eklendi; hem
`scripts/kos.sh`'e hem KOSU-RABADON-2.md §B2 kod bloğuna (doc tek kaynaktır;
yalnız scripti düzeltmek sonraki oturum B2'yi birebir yazınca hatayı geri
getirirdi). `diff` ile doc == script doğrulandı. Regresyonu tutan 2 saniyelik
test harness'a **B6.0** olarak kondu.

## İkinci bulgu — sürüm sabitleme yoktu, iddia edilmişti

`reports/kosu/ONKONTROL.md` satır 14: "kos.sh `export DISABLE_AUTOUPDATER=1`
ile başlıyor." **Yanlıştı** — `grep DISABLE_AUTOUPDATER scripts/kos.sh` boş
dönüyordu, doc'ta da yoktu, sürücünün ortamında da yoktu (`env | grep -c` → 0).
C.0'ın "koşu boyunca auto-update kapalı" şartı fiilen uygulanmamıştı.
Export hem script'e hem doc §B2'ye eklendi.

## Sonuç tablosu

| Madde | Durum | Kanıt |
|---|---|---|
| B6.0 nabız taşınabilirliği (yeni) | YEŞİL | marker kendini eşleştirmiyor; gerçek dosya aktivitesi hâlâ görünüyor |
| B6.1 kos.sh + DEGERLENDIREN.md commit'li, C.0 yeşil | YEŞİL | `d1a2c57`, `30d5cbb`, `14ce7be`; ONKONTROL.md (satır 14 bu turda düzeltildi) |
| B6.2 tam çevrim (raw→out→karar→GUNLUK→son.talimat, commit+push) | YEŞİL | 7/7 assert; sahte çevrim, deterministik |
| B6.3 OPERATÖR yolu (soru düştü, ONAY'sız CEVAP kımıldatmadı, ONAY kımıldattı) | YEŞİL | 7/7 assert; mühürsüz CEVAP 330 sn boyunca döngüyü ilerletmedi; tur 3'ün yapanı CEVAP talimatını argv'de aldı |
| B6.4 tekrar freni / DENEMELER'den hipotez eleme | **KOŞULMADI** | sahte `claude` ile dürüstçe test edilemez, gerçek değerlendiren modeli gerekir |
| B6.5 watchdog (STALL KILL + yetim bırakmama) | YEŞİL | 3/3 assert; hata bulundu, düzeltildi, tekrar koşuldu |

**Toplam: 19 assert, 19 PASS, 0 FAIL** (rc=0). Ham: `reports/kosu/SMOKE.out`.

## NOT VERIFIED / döküm

- **B6.4 koşulmadı.** Tekrar freni ve DENEMELER'den hipotez eleme, gerçek
  değerlendiren modelinin kararlarını gerektirir; sahte bir `claude` ile
  "kanıtlamak" tam olarak rabadon'un reddettiği şey olurdu. Döngünün kendi
  seyrinde, üç aynı-kırmızı tur birikince kanıtlanmalı. **B6 bu maddeden
  dolayı KAPANMADI.**
- **Canlı döngünün B6.2'si bu oturumdan doğrulanamaz.** Bu oturum tur 1'in
  yapanıdır; `.karar` / GUNLUK satırı / `son.talimat` ben bittikten SONRA
  yazılır. Tur 2'nin yapanı `reports/kosu/1.karar`, `GUNLUK.tsv` ve
  `son.talimat`ın varlığını doğrulamalı.
- **Canlı sürücü İKİ düzeltmenin de öncesinde başladı.** Şu an dönen
  `scripts/kos.sh` process'i hem ölü watchdog'a hem eksik sürüm sabitlemeye
  sahiptir. Düzeltmeler ancak sürücü **yeniden başlatılınca** yürürlüğe girer
  (`tmux kill-session -t rabadon` + yeniden `tmux new -d -s rabadon
  scripts/kos.sh`). Bu bir karar gerektirir; yapan oturum sürücüsünü kendi
  kendine öldürmez.
- İlk üç koşuda çıkan 3 FAIL'in üçü de **harness'ın kendi assert hataları**ydı
  (geniş `pgrep -f`; bare depoda `git log` HEAD=refs/heads/main'e bakıyor;
  `son.talimat` kontrolü tur 3'ün üzerine yazmasından sonraya kalıyordu).
  Üçü de düzeltildi ve temiz bir koşu yapıldı — prose ile açıklanıp geçilmedi.
- `$i.out.raw` ve `.raw.err` marker'dan sonra yaratıldığı için ilk çevrimde
  "aktivite" sayılıyor; stall bir çevrim (60 sn) geç başlıyor. Öldürme yönünde
  değil yaşatma yönünde yanılıyor, zararsız — ama **ölçülmedi**.
- `df -Pi` macOS'ta yanlış sütunu okuyor (ONKONTROL.md'de zaten dökülmüş);
  inode koruması bu makinede pasif, yanlış alarm üretmiyor.
- **Rabadon kapısı BAĞLANMADI** (B1.5: smoke + 5 temiz tur sonrası). Bu oturum
  hiçbir hook/settings dosyasına dokunmadı.
- **R7 durumu (A4'ün sıradaki işi, taranmış ama başlanmamış):**
  `reports/R7/accept.sh` var (23.5 KB, 8 GOAL: daemon+soket, medyan < 1 ms
  in-process, daemon-down byte-identical fail-SAME, harness repo+40-hex commit,
  iki kollu ham JSONL + reproduce.sh, beş sayı, çürütme koşulları, regresyon).
  `reports/R7/` altında **başka hiçbir dosya yok** — DENEMELER.md de yok, ham
  veri de yok. Daemon YOK: `native/gate.cpp` AF_UNIX **istemci** tarafını ve
  `RABADON_GATED_SOCK` fallback'ini içeriyor, `core/bus.mjs` ayrı bir watch
  soketi işletiyor; `rabadon-gated` diye bir binary/daemon kaynağı yok.
  A1'in soket-yolu kuralı (kısa+mutlak, repo dışı) `RABADON_GATED_SOCK`
  varsayılanına karşı ayrıca denetlenmeli — **DOĞRULANMADI**.
