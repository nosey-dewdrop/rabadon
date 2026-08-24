# REGRESYON — tur 9 teşhisi (2026-08-24)

Operatör CEVAP 2 (`reports/kosu/8.operator.md`) gereği, profil işinden ÖNCE
yapılan tek teşhis adımı. Soru: tur 8'de bulunan 7 kırmızı gerçekten
"pre-existing" mi, yoksa bu koşu sırasında mı girdi?

**Cevap: ikisi de. 3'ü pre-existing, 4'ü BU KOŞUDA GİRMİŞ REGRESYON.**

## Yöntem

B1.8 gereği canlı worktree'ye dokunulmadı. `git clone . /tmp/rbisect` ile ayrı
bir klon açıldı, tüm checkout/build/test orada koşuldu. `kosu2` branch'inden
çıkılmadı, `reset --hard`/`branch -D`/`checkout main` kullanılmadı.

Bisect'e gerek kalmadı: uç noktalar tek başına ayrıştırdı. Koşunun başlangıç
commit'i `a59138b` (R6 ACCEPTED) referans alındı — C.0 ön kontrolünde
`make test` bu ağaçta rc=0 döndürmüştü (`reports/kosu/ONKONTROL.md`, kontrol 2).

Her ölçüm için: `git checkout -q <commit>` → `make all` (rc=0) →
`timeout 600 ./native/<suite>.sh </dev/null`.

## Bulgu 1 — `promises_test.sh`: 3 kırmızı, PRE-EXISTING (doğrulandı)

`a59138b`'de koşuldu. Çıktı bugünküyle **aynı**:

```
promises: 6 kept, 3 broken
  BROKEN - PROMISE 3 NOT KEPT: it caught the break, attempted no repair, and said nothing about repair at all
  BROKEN - PROMISE 4 NOT KEPT: 'only work in src' was said and a write to lib/ went through (exit 0)
  BROKEN - PROMISE 4 NOT KEPT: the stop does not quote what the user actually asked for
```

Koşu başlamadan önce de kırmızıydı. Tur 8'in "pre-existing" ifadesi bu üç
kalem için DOĞRU. R7 kabulünü bloklamaz; kendi turunda kapanır.

Neden C.0'da `make test` yine de rc=0 döndü: `make test` hedefinde
`promises_test.sh` (Makefile:923) `cli_test.sh`'ten (Makefile:106) çok sonra
gelir ve `make` ilk kırmızı suite'te durur — o gün cli_test yeşil olduğu için
akış oraya kadar gitmiş olsa bile, kırmızının `make test` rc'sine yansımadığı
bir sıra sorunu var. **Bu ayrı bir kusurdur ve aşağıda PARKED'e yazıldı.**

## Bulgu 2 — `cli_test.sh`: 4 kırmızı, REGRESYON (bu koşuda girdi)

| commit | sonuç |
|---|---|
| `a59138b` (koşu başlangıcı) | `cli: 297 passed, 0 failed` — **YEŞİL** |
| `d4e7a90` (da9e5b2'nin ebeveyni) | `cli: 297 passed, 0 failed` — **YEŞİL** |
| `da9e5b2` | `cli: 297 passed, 4 failed` — **KIRMIZI** |
| `6096646` (bugünkü HEAD) | `cli: 297 passed, 4 failed` — **KIRMIZI** |

Suçlu commit: **`da9e5b2` — "R7 GOAL 1: rabadon-gated daemon + thin client,
fail-SAME; two fail-opens found and closed"** (tur 6).

`da9e5b2`'deki 4 FAIL satırı bugünkü HEAD'in 4 FAIL satırıyla **birebir aynı**:

```
FAIL - rabadon-gated ships in every platform package and NO case arm resolves it — nobody who installed from npm can run it
FAIL - `rabadon-gated --help` HUNG for 10s instead of printing help
FAIL - `rabadon-gated -h` HUNG for 10s instead of printing help
FAIL - `rabadon-gated --rabadon-no-such-flag` HUNG for 10s on an undefined flag
```

`rabadon-gated`'ın doğum commit'i de aynı commit:
`git log --diff-filter=A -- 'native/*gated*'` → `da9e5b2`.
`git log -S'rabadon-gated' -- Makefile` → `da9e5b2`.

Yani: R7 GOAL 1 yeni bir binary'i pakete soktu, ama cli_test'in **her binary
için zaten var olan** iki sözleşmesini karşılamadı — (1) platform paketinde bir
case arm ile çözümlenmek, (2) `--help`/`-h`/tanımsız bayrakta yardım basıp
çıkmak. `rabadon-gated` bunun yerine 10 saniye asılıyor (muhtemelen doğrudan
socket accept döngüsüne giriyor, argv'yi hiç incelemeden).

Geçen sayı 297'de sabit kaldı: mevcut hiçbir test bozulmadı, 4 YENİ sözleşme
kalemi doğdu ve doğduğu anda kırmızı düştü.

## Hüküm

**Bu 4 kalem R7 kabulünden ÖNCE kapanmalıdır.** Operatörün cümlesi geçerli:
altındaki suite kırmızıyken 14 yeşil bir `accept.sh` "ilerleme" sayılmaz.
Dahası bu, R7'nin kendi teslimatının (daemon) kusuru — dışarıdan gelen bir borç
değil. `--help` asılması ayrıca R8 yayınını da bloklar: npm'den kuran kimse
binary'i çözümleyemiyor.

Kapsam disiplini: bu tur operatör tarafından **SADECE PROFİL** olarak
sınırlandı (CEVAP 1). Bu yüzden burada teşhis yazıldı, **düzeltme yazılmadı.**
Düzeltme bir sonraki turun ilk işidir.

## PARKED (bu turda düzeltilmedi, karar bekliyor)

- `make test` ilk kırmızı suite'te duruyor; `promises_test.sh` sıranın çok
  sonunda. Sonuç: suite'in tamamı hiçbir zaman uçtan uca görülmüyor ve
  `make test` rc'si "her şey yeşil" anlamına gelmiyor. C.0 ön kontrolünün
  rc=0'ı bu yüzden 3 kırmızıyı gizledi. Kapı aracı için bu kabul edilemez
  bir kör nokta — ama `make test` semantiğini değiştirmek bir kabul kriteri
  değişikliğidir, kendi commit'ini ve kendi gerekçesini ister.

## Yeniden koşturma komutları

```sh
git clone . /tmp/rbisect && cd /tmp/rbisect
for C in a59138b d4e7a90 da9e5b2 6096646; do
  git checkout -q "$C" && make all >/dev/null 2>&1
  printf '%s -> ' "$C"
  timeout 600 ./native/cli_test.sh </dev/null 2>&1 | grep -E 'passed, .* failed'
done
git checkout -q a59138b && make all >/dev/null 2>&1
timeout 600 ./native/promises_test.sh </dev/null 2>&1 | tail -3
```

## NOT VERIFIED

- Aradaki commit'ler tek tek koşulmadı (`ba231d6`, `5cfc7ad`, `9dd95a3`,
  `6481549`, `26ea409`, `45192f9`, `7d344ee`, `548f170`). Uç noktalar
  ayrıştırmaya yettiği için gerek görülmedi; ama bu commit'lerden birinin
  cli_test'e BAŞKA bir kırmızı ekleyip sonra kaldırmış olma ihtimali
  ölçülmedi. Sayım 297/4 olarak sabit olduğu için bu düşük ihtimal, kanıt değil.
- `make test`'in bugünkü HEAD'de uçtan uca rc'si ölçülmedi — cli_test'te
  duracağı bilindiği için ayrıca koşturulmadı.
- Kırmızıların temiz bir container'da (yalnız git + shell) aynı çıktıyı
  vereceği doğrulanmadı. Tüm ölçümler bu macOS makinesinde yapıldı.
- `rabadon-gated`'ın 10 sn asılmasının kök sebebi (argv'yi hiç okumadan
  accept döngüsüne girmesi) **okunmadı, tahmin edildi.** Kaynak incelemesi
  düzeltme turuna ait.
