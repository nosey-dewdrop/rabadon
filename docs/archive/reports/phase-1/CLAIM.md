# Faz 1 — REPAIR sonuç ölçümü

Durum: **GEÇTİ.** `bash reports/phase-1/accept.sh` → exit 0.
Kabul testini başka bir ajan yazdı, ben dokunmadım (`git log --oneline --
reports/phase-1/accept.sh` → tek commit, uygulamadan önce).

## Bulunan şey

22 günlük defterde **435 REPAIR_START** var. Bunların **168**'i bir sonuçla
kapanmış. **267**'si hiçbir şeyle kapanmamış — ve "kapanmamış" burada zayıf bir
ifade: o 267 girişten sonra, kendi run'ları içinde, **hiçbir olay yok.** Terminal
olay yok, `STEP_OK` yok, `RUN_DONE` yok. Defter ortasında susuyor.

Yani `rabadon stats`'ın "tamir denemesi" diye saydığı şeylerin **%61'inin nasıl
bittiğini kimse söyleyemiyordu.** Kendi sonucunu ölçemeyen bir tamir döngüsü,
sonucu ölçtüğünü iddia eden bir ürünün içinde duruyordu.

## Kök sebep (yama değil, kök)

`native/gate.cpp:2353` teşhis için `REPAIR_START` yazıyor. Kapanış yolları:

| Yol | Eskiden | Şimdi |
|---|---|---|
| teşhis alınamadı | `REPAIR_FAIL` ✓ | ✓ + `outcome`/`class` |
| teşhis geldi, kural önerilmedi | **hiçbir şey** | `REPAIR_OK` + `outcome:held` |
| kural önerildi, regex derlenmedi | **hiçbir şey** | aynı kapanış |
| kural önerildi, kendi örneğini yakalayamadı | `REPAIR_FAIL` ✓ | ✓ + alanlar |
| kural zaten kurulu | **hiçbir şey** | aynı kapanış |
| kural kuruldu | `REPAIR_OK` ✓ | ✓ + alanlar |

267'nin ezici çoğunluğu ikinci satır: teşhis başarıyla geldi, yeni kural
önerecek bir şey yoktu, blok bitti, kimse bir şey yazmadı.

Düzeltme `repairClosed` bayrağı: blok hangi yoldan çıkarsa çıksın, çıkmadan önce
nasıl bittiğini yazar. Sonucu olay adından ÇIKARSAMAK yerine açıkça yazmak
kasıtlı — çıkarsama, deliği 22 gün görünmez tutan şeyin ta kendisiydi.

## Değişen dosyalar

- `native/gate.cpp` — `repairClosed`, kapanmayan üç yol kapatıldı, 6 emisyona `outcome`/`class`
- `native/repair.cpp` — 8 emisyona `outcome`/`class` (test-tamper, harness-tamper, timeout, FLAKY sınıfları artık olayın kendisinde)
- `native/loop.cpp` — 1 emisyona `outcome`/`class`
- `scripts/repair_census.py` — geriye dönük tarayıcı (yeni)
- `reports/phase-1/classified.tsv` — 435 satır, her biri kanıt satırını gösteriyor
- `reports/phase-1/distribution.tsv` — 8 anahtarlı dağılım

## Kanıt komutları

```sh
make test                                    # exit 0, 3336 ok, 0 fail
python3 scripts/repair_census.py             # 435 / 168 / 267
bash reports/phase-1/accept.sh               # exit 0
bash scripts/seal.sh 1 after && diff reports/phase-1/locks.txt.{before,after}   # fark yok
```

Dağılım (kabul testi bunu rapordan okumaz, kendisi yeniden hesaplar):

```
held             113
REPAIR_FAIL       51
FLAKY              0
test-tamper        2
harness-tamper     2
proposer-empty     0
timeout            0
unclassified     267
```

İleri kapanış kanıtı: mührün ötesinde 2 canlı `REPAIR_START`, ikisi de açık
`outcome` ile kapandı (`not-held`/`REPAIR_FAIL` ve `held`). `/tmp/pg-live`
üzerinde gerçek push-gate yolu koşturularak üretildi, gerçek deftere yazıldı.

## DOĞRULANMADI

- **267 kurtarılabilir mi, bilmiyorum.** Defterde o girişlere bağlanabilecek
  başka kanıt bulamadım. "Bulamadım" ile "yok" aynı şey değil; ikincisini
  iddia etmiyorum. Sınıflandırılmamış olarak sayıldılar, uydurulmadılar.
- `diagnosis unavailable` sınıfının `REPAIR_FAIL` olması bir yargı kararı
  (kabul testini yazan ajanın kararı). `proposer-empty` de savunulabilirdi.
- `REPAIR_FLAKY` olayı kodda var (`repair.cpp:1000`) ama defterde **hiç** yok.
  Yani FLAKY=0 "hiç olmadı" değil, "hiç kaydedilmedi" de olabilir.
- İleri kanıt push-gate yolundan üretildi. `repair.cpp`'nin session-repair yolu
  ve `gate.cpp`'nin diagnosis yolu **canlı olarak koşturulmadı** — ikisi de API
  anahtarı istiyor. Kod yolları `make test` içinde kapsanıyor, gerçek defterde
  değil.
- `rabadon audit` hâlâ exit 2 (13 dosya zincir öncesi). Faz 1'in işi değildi,
  düzeltilmedi, gizlenmedi.
