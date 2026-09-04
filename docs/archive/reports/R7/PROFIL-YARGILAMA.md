# PROFIL — yargılama kovasının içi (R7 tur 9, 2026-08-24)

Operatör CEVAP 1 (`reports/kosu/8.operator.md`): bu tur **sadece profil**. Kod
yazılmadı, optimizasyon denenmedi, hiçbir şart değiştirilmedi. `native/` altına
dokunulmadı — bütün problar `/tmp` altındaki KOPYALARA yamalandı.

Soru: tur 8'in tek parça ölçtüğü **1075 µs yargılama kovasının** içinde ne var?

## Tek cümlelik cevap

**Kural motoru — rabadon'un var olma sebebi — yargılama maliyetinin %4.4'ü.
Geri kalan %95 defter tutmadır, ve en büyük tek kalem (%28.5) bir saat dilimi
veritabanı yüklemesidir: her forklanan worker'ın yeniden ödediği, ikinci
çağrıda 1 µs'ye düşen tek seferlik ilklendirme.**

## Yöntem

Tur 8'in protokolü aynen: kaynak `/tmp`'ye kopyalandı, prob KOPYAYA yamalandı,
`native/` okundu ama yazılmadı. İki bağımsız prob, birbirini doğruluyor:

**Prob A — dışlamalı (exclusive) zaman yığını, 71 kova.** `gate.cpp`'de tanımlı
**her** fonksiyon (55 tanesi, elle seçilmeden, `patch_deep.py` ile otomatik) +
15 başlık yaprağı. Bir bölgeye girmek ebeveyninin sayacını DURDURUR, böylece
`judge_command`→`parse`→`rx_test` veya `note_mode`→`last_ledger_mode` gibi
iç içe çağrılar iki kez sayılmaz. Kovalar toplama **tanım gereği** eşitlenir;
bu eşitlik ölçümün kendi doğrulama testidir.

**Prob B — satır damgalı kontrol noktaları.** `main()` gövdesine (2142–4697)
531 kontrol noktası; yalnızca ÇALIŞAN noktalar kaydeder, yani dallanma kendi
kendini halleder. Ardışık iki nokta arasındaki en büyük boşluk, zamanın
harcandığı SATIRI verir.

Yük: 300 örnek × 3 tur (arm F) + 1 tur CPU yükü altında, arm F ile arm C
(tur 8'in 2 damgalı probu) **çağrı çağrı sıralı** (R1.3 GOAL 6 protokolü).

```sh
python3 /tmp/sprof/patch_deep.py && cd /tmp/sprof/deep && \
  c++ -std=c++17 -O2 -I . -o rabadon-gated-deep gated.cpp
for t in r1 r2 r3; do bash /tmp/sprof/run_deep.sh 300 $t; done
python3 /tmp/sprof/an_sub.py r1 r2 r3
```

### Ölçümün kendi kalite sayıları

| kontrol | sonuç |
|---|---|
| kovaların toplamı vs ölçülen toplam | **+0.2 µs fark (%0.0)** — ayrıştırma tam |
| prob maliyeti (arm F − arm C, sıralı) | **+20.1 µs (%1.7)** |
| daemon gerçekten servis etti mi | **900/900 satır** — bir satır ancak worker tarafından yazılabilir (aşağıya bak) |
| toplam medyan (sakin) | 1205.7 µs, %95 GA [1198.1, 1214.7], p10 1096.6 / p90 1641.4 |
| toplam medyan (yük altında) | 2733.1 µs, %95 GA [2686.9, 2770.1] |

Güven aralıkları 2000 örneklemli bootstrap, `random.seed(20260824)` sabit —
rapordaki hiçbir sayı yeniden üretilemez değil.

**Sessiz düşmeye karşı yerleşik kanıt:** prob değişkeni `gated_client.h:123`
gereği İSTEMCİNİN ortamıyla worker'a taşınır, dolayısıyla bir satırı ancak bir
worker yazabilir. Eğer istemci sessizce süreç-içi yola düşseydi satır EKSİK
olurdu — makul ama yanlış bir sayı değil. 900 çağrı, 900 satır.

## Ayrıştırma (sakin tur, 900 örnek)

| kova | medyan µs | %95 GA | çağrı | pay |
|---|---|---|---|---|
| `main_rest` (main'in kendi gövdesi) | 387.1 | [381.9, 392.3] | 1 | **32.1%** |
| `write_atomic` (durum dosyası yazımı) | 151.6 | [150.2, 152.7] | 1 | 12.6% |
| `chain_append` (zincirli defter) | 132.4 | [130.4, 134.2] | 1 | 11.0% |
| `resolve_real` (realpath) | 87.7 | [87.4, 88.0] | 8 | 7.3% |
| `read_file` | 62.6 | [62.1, 63.2] | 6 | 5.2% |
| `append_move` (hamle günlüğü) | 56.9 | [55.9, 58.2] | 1 | 4.7% |
| `acquire_lock` | 46.6 | [46.1, 47.2] | 1 | 3.9% |
| spool tarama (`scan_ledger_mode`+`read_tail`+`last_ledger_mode`) | 97.5 | — | — | 8.1% |
| `load_moves` | 31.6 | [31.1, 32.2] | 1 | 2.6% |
| `rx_test` (regex kur + ara) | 18.3 | [18.2, 18.4] | 1 | 1.5% |
| `judge_command` (kural yürüyüşü, iç içeler hariç) | 6.5 | [6.4, 6.5] | 1 | 0.5% |
| `cmdtext_parse` | 9.7 | [9.5, 10.0] | 1 | 0.8% |
| `hook_parse` | 5.0 | [5.0, 5.1] | 1 | 0.4% |

`main_rest`'in %32'si bir kalıntı değil: `gate.cpp`'nin **her** fonksiyonu
ayrı kovada olduğu için bu, doğrudan `main()` içine yazılmış düz kod demektir.
Prob B onu satırına kadar indirdi.

## Prob B — zaman hangi SATIRDA (pay olarak, iki farklı yükte)

| satır | ne yapıyor | pay (yük ~4) | pay (yük ~16) |
|---|---|---|---|
| `gate.cpp:2754` | `time()` + `gmtime_r()` + `strftime()` — gün dizgisi | **29.1%** | **28.5%** |
| `gate.cpp:4644` | `em.emit("STEP_START")` → zincirli defter yazımı | 15.2% | 15.3% |
| `gate.cpp:4695` | `stt.save()` → oturum durumu diske | 16.0% | 14.3% |
| `gate.cpp:2778` | `stt.load()` → oturum durumu diskten | 10.2% | 8.8% |
| `gate.cpp:2693` | `note_mode()` → spool'u tarayıp mod değişimi arar | 3.7% | 7.2% |
| `gate.cpp:2871` | `stt.append_move()` → hamle günlüğü | 5.2% | 5.8% |
| `gate.cpp:4201` | `judge_command()` — **asıl kural yargılaması** | 5.2% | 4.4% |
| `gate.cpp:2819` | `read_file(guard.json)` | 5.0% | 4.3% |

Mutlak süre bu iki koşu arasında ~3 kat değişti (1108 µs → 3058 µs); **paylar
değişmedi.** Bu, ayrıştırmanın makine durumuna değil koda ait olduğunun kanıtı.

## En büyük kalem KANITLANDI: bu bir saat dilimi ilklendirmesi

`gate.cpp:2754`'ün neden 300+ µs sürdüğü tahmin edilmedi, ayrı bir deneyle
ölçüldü (`/tmp/sprof/tz.c`). Forklanan bir çocukta aynı satır:

```
cold worker: 1st=483.0us 2nd=1.0us 3rd=0.0us
cold worker: 1st=320.0us 2nd=1.0us 3rd=0.0us
cold worker: 1st=299.0us 2nd=1.0us 3rd=0.0us
cold worker: 1st=269.0us 2nd=1.0us 3rd=0.0us
cold worker: 1st=280.0us 2nd=1.0us 3rd=0.0us
warm-parent worker: 1st=71.0us    (ebeveyn bir kez çağırdıktan SONRA fork)
warm-parent worker: 1st=81.0us
warm-parent worker: 1st=129.0us
warm-parent worker: 1st=164.0us
warm-parent worker: 1st=172.0us
```

İlk çağrı 269–483 µs, **ikinci çağrı 1.0 µs.** Bu tek seferlik bir süreç
ilklendirmesidir (saat dilimi/yerel ayar verisinin yüklenmesi). Daemon ebeveyni
bunu hiç çağırmadığı için forklanan HER worker bedeli baştan ödüyor. Ebeveyni
ısıtmak bedeli ~129 µs'ye indiriyor; **gün dizgisi bir gün boyunca zaten
aynı olduğundan** ebeveynde bir kez hesaplanıp taşınırsa bedel ~0'a iner.

## Karar kuralının uygulanması

Operatörün önceden bağladığı kural: alt kovalar toplamda **≥%55** kısılabilir
görünüyorsa (1075 → <500 µs) fırsat denenir ve **tavan KALIR**; hiçbir bileşim
%55'e ulaşmıyorsa "mimari olarak ulaşılamaz" kanıt olur ve (b) açılır.

Payları tur 8'in 1075 µs tabanına uygulayarak:

**Anlamı değişmeyen kalemler (saf israf):**
| kalem | pay | 1075 µs'de |
|---|---|---|
| gün dizgisi / saat dilimi ilklendirmesi | 28.5% | 306 µs |
| `note_mode` spool taraması (her olayda yeniden) | 7.2% | 77 µs |
| `resolve_real` — aynı süreçte 8 realpath | 7.3% | 78 µs |
| **toplam** | **43.0%** | **461 µs** |

Bu üçü tek başına 1075 → **614 µs**. **%55'e ULAŞMIYOR.**

**Eşiği aşmak için gereken dördüncü kalem:**
| kalem | pay | 1075 µs'de |
|---|---|---|
| `stt.load` + `stt.save` + `append_move` (oturum durumu gidiş-dönüşü) | 28.9% | 311 µs |

Dördü birlikte: 1075 → **303 µs**, yani **%72 kısım. Eşik AŞILIYOR.**

### Sonuç: (a) yolunun hükmü — TAVAN KALIR, (b) AÇILMAZ

Karar kuralı gereği, fırsat göründüğü için tavan kalır ve seçenek (b)
("1000 µs şartını kaldır") bu turda **açılmaz.** Tur 8'in "mimari olarak
ulaşılamaz" ekstrapolasyonu ölçümle **çürütüldü**: 1075 µs'nin %4.4'ü kural
motoru, %28.5'i bir kez yapılıp bir daha yapılmaması gereken ilklendirme.

### Ama bir sınır çizgisi, şimdiden yazılı

**%55 eşiği yalnızca oturum durumu gidiş-dönüşü dahil edilirse aşılıyor
(%43 vs %72).** O kalem saf israf DEĞİL: diske yazmayı bırakmak dayanıklılık
semantiğini değiştirir. Bu bir sonraki tur için bir uyarıdır, pazarlık değil:

- **Defter yazımı (%15.3) bir optimizasyon hedefi değildir.** Zincirli defter
  bu ürünün ürettiği kanıtın kendisidir. Bir gecikme sayısını tutturmak için
  kanıtı incelten bir değişiklik, rabadon'un var olma sebebi olan hastalığın
  ta kendisidir. Sayı için delil kısılmaz.
- Oturum durumu daemon belleğinde tutulacaksa, çökme davranışı ve fail-SAME
  sözü ölçülerek gösterilmelidir — "muhtemelen aynı" yeterli değildir.
- İlk denenecek kalem tartışmasız olan: gün dizgisi. Tek başına %28.5, hiçbir
  semantik bedeli yok, ve nedeni ayrı bir deneyle kanıtlandı.

## NOT VERIFIED / bu ölçümün sınırları

- **Makine sakin değildi.** "Sakin" turların yük ortalaması 3.93–5.21 idi
  (`out.r*/load.before`). Mutlak medyanım 1205.7 µs, tur 8'in 1075.1 µs'si ve
  onun 1061–1134 µs aralığının DIŞINDA. Fark prob maliyetiyle açıklanamaz
  (yalnız 20.1 µs). Bu yüzden bu raporun sonucu **paylardır**, mutlak sayılar
  değil; paylar 3 kat yük değişiminde sabit kaldığı için dayanıklıdır.
  Kamuya giden bir <1 ms iddiası bu koşudan türetilemez.
- Ölçüm tek bir senaryo içindir: `echo hello world`, **BOŞ guard.json**,
  taze HOME, tek dosyalık `.git`. Boş guard yüzünden deny-kural döngüsü hiç
  dönmüyor; `rx_test` yalnız 1 kez çağrılıyor (taban yasaları). **Kurallı bir
  projede regex payı bu tablodakinden yüksek olacaktır** ve o ölçülmedi.
- Yalnız bu macOS makinesinde ölçüldü. Saat dilimi ilklendirme maliyeti
  platforma bağlıdır; Linux'ta doğrulanmadı. Temiz container'da koşulmadı.
- `main_rest` içindeki 387 µs'nin 322 µs'si `gate.cpp:2754`'e bağlandı; kalan
  ~65 µs satır satır dağıtılmadı, dağınık kabul edildi.
- Prob B'nin 531 kontrol noktası ölçtüğü şeyi bir miktar şişirir; bu yüzden
  Prob B yalnız PAY ve SATIR için kullanıldı, mutlak süre için Prob A.
- İki prob iki farklı koşuda çalıştı; aynı çağrıda eşzamanlı değillerdi.
  Aralarındaki tutarlılık (main_rest %32.1 ≈ 2754 satırı %28.5 + dağınık)
  hesapla uyuşuyor ama tek bir ikili ölçümle mühürlenmedi.
- Hiçbir optimizasyon DENENMEDİ. Yukarıdaki "1075 → 303 µs" bir aritmetik
  projeksiyondur, ölçüm değildir. Kanıt, denendiğinde çıkacak sayıdır.

## Yeniden üretme

```sh
python3 /tmp/sprof/patch_deep.py                    # 71 kovalı dışlamalı prob
cd /tmp/sprof/deep && c++ -std=c++17 -O2 -I . -o rabadon-gated-deep gated.cpp
for t in r1 r2 r3; do bash /tmp/sprof/run_deep.sh 300 $t; done
python3 /tmp/sprof/an_sub.py r1 r2 r3               # tablo + GA + mutabakat
bash /tmp/sprof/run_ck.sh 300 ck2                   # satır damgalı prob B
cc -O2 -o /tmp/sprof/tz /tmp/sprof/tz.c && /tmp/sprof/tz   # saat dilimi kanıtı
```
