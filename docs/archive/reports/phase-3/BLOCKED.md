# Faz 3 — BLOKE (kısmi): protokol kendi kendisiyle çelişiyor

Tarih: 2026-08-20. `bash reports/phase-3/accept.sh` → **exit 1**.
Beş kapsam maddesinin **dördü bitti ve kanıtlandı**, beşincisi yapılamıyor —
çünkü protokolün iki cümlesi aynı anda tutulamaz.

## CHALLENGE — AGENTS-PROTOCOL.md Faz 3, iki cümle, tek konu

Satır 150, **Kapsam**:

> `~/.rabadon/enabled` + `mode.last` tek dosyaya insin.

Satır 154, **Durma**:

> mevcut bir test kırılıyorsa dur — silme, zayıflatma.

`native/cli_test.sh:210`, mühürlü, bugün yeşil:

```sh
run toggle >/dev/null 2>&1
[ -f "$HOME_DIR/enabled" ] && pass "`rabadon toggle` still flips it ..." \
  || fail "`rabadon toggle` did not turn it on"
```

Bu test **`enabled` dosyasının var olduğunu** doğruluyor. Kapsam o dosyanın
kalkmasını emrediyor. Yani:

- Kapsam'a uyarsam → `cli_test.sh:210` kırılır → Durma "dur" der.
- Durma'ya uyarsam → `enabled` kalır → Kapsam yapılmamış olur.

Kanıt (çöküş uygulanmışken, geri alınmadan önce):

```
$ make test
  FAIL - `rabadon toggle` did not turn it on
cli: 295 passed, 1 failed
make: *** [test] Error 1
```

Bu bir uygulama hatası değil. Test, protokolün kaldırılmasını emrettiği
davranışı doğruluyor. Testi düzeltmek çözüm gibi görünüyor ve **tam olarak bu
ürünün reddetmek için var olduğu hamle**: kabul kriterini, onu sağlayan kodla
aynı diff'te değiştirmek (CLAUDE.md, madde 1 ve 2).

## Ne yapıldı

Çöküş **geri alındı**, kalan dört madde yerinde bırakıldı. Sebebi CLAUDE.md'nin
kendi kuralı: tartışmalı adımı durdur, ona bağlı olmayanlarla devam et. Böylece
zemin kırmızıya düşmedi.

```
$ make test
exit=0, 3331 ok, 0 fail
```

Yeni bir dosya yazıldı ama hiçbiri silinmedi: `<RABADON_DIR>/mode` artık
`rabadon on/off/silent` ile yazılıyor ve katmanlı okuyucu onu okuyor —
`enabled` ve `mode.last` da yerinde duruyor. Yani çöküşün **okuma tarafı**
çalışıyor, **silme tarafı** insan kararı bekliyor.

## Çözüm için gereken karar (senin, benim değil)

1. `cli_test.sh:210-213` kendi commit'inde, kendi gerekçesiyle güncellensin
   (assertion `enabled` yerine `mode` dosyasına baksın) — sonra çöküş tamamlanır. Ya da
2. Kapsam maddesi düşürülsün: iki dosya kalsın, `mode` yalnız katmanlı okuma için
   kullanılsın. Ya da
3. Faz 3 dört maddeyle kapatılsın, çöküş ayrı bir faza taşınsın.

Hangisi olursa olsun, AGENTS-PROTOCOL.md'ye giden diff **ayrı commit** olmalı —
bu dosyayı yazan ajan (ben) o diff'i yazamaz.

## İkinci ifşa: mühür bilerek kırıldı

`Makefile`'ın hash'i değişti. Sebep: protokolün Faz 3 **Kabul**'ü yeni bir test
istiyor ("bir dizin kırmızıyken komşu dizinde ateşlemediğini gösteren yeni
test"), ve yeni test `make test` recipe'sine girmeden koşmuyor.

```
önce : 6116a74bdd549ca8371cd7d44b0e70fe17c1ec1f0181056fdda7844be7645966  ./Makefile
sonra: f20438989575726476167e2bcc0dbcec2cb1f45725bb9ef91f8d0090a751d0e1  ./Makefile
diff : +	./native/scope_test.sh          (tek satır, ekleme)
```

Kendi commit'inde, kendi gerekçesiyle yapıldı (`f72d023`). Hiçbir şey
zayıflatılmadı, silinmedi; bir satır eklendi. Yine de mühür kırılmasıdır ve
saklanmıyor.

## Biten dört madde

| Madde | Durum | Kanıt |
|---|---|---|
| A. `netRed` kökle yazılsın | bitti | `net.json` artık `"root"` taşıyor |
| B. kök eşleşmezse ateşlemesin | bitti | `scope_test.sh` — 9/9 |
| C. üçüncü hal `could-not-run` | bitti | `net.cpp` level==0 yolu |
| E. mod katmanlı (env→proje→makine) | bitti | kapının 5.x maddeleri yeşil |
| F. tek dosyaya iniş | **BLOKE** | yukarıdaki çelişki |
