# R2 — tur arası kapı

Kabul: `reports/R2/accept.sh` → **19 yeşil, 0 kırmızı**. `make test` → exit 0, **2036 geçti, 0 kaldı**.
Kapının beş sorusu, sırayla.

---

## 1. Hot-path bedeli — **KÖTÜ. DUR.**

Ölçüm: tek partide dönüşümlü (kapalı, açık, kapalı, açık, kapalı, açık), her koşuda
ring 210 olayla 200'e doldurulup sonra 200 çağrı ölçüldü. Aynı makine, aynı fixture.

| kol | koşular (ms) | medyan |
|---|---|---|
| `RABADON_MOVES=0` | 4.433 / 4.949 / 4.636 | **4.636** |
| kayıt + sinyal açık | 5.775 / 6.244 / 6.207 | **6.207** |

**Fark: 1571 µs. Kapının eşiği 300 µs.**

### R1.1 yapıldı ve bedeli düşürmedi

Operatörün istediği ara tur uygulandı: `save()` dirty-tracked oldu — oturum dosyası
serialize edilip bu sürecin en son yazdığı baytlarla karşılaştırılıyor, bayt oynamadıysa
syscall atlanıyor.

Aynı yöntemle önce/sonra, **aynı partide**:

| binary | koşular (ms) | medyan |
|---|---|---|
| R1.1 öncesi (248e241) | 5.679 / 5.674 / 5.643 | **5.674** |
| R1.1 sonrası | 5.784 / 5.994 / 5.732 | **5.784** |

**Kazanç yok; gürültü içinde ~110 µs kötü.**

### Nedeni — ve neden R1.2'ye gitmiyorum

R1.1 yanlış şeyi hedefledi, ve hedefi ben seçtim. Varsayım "olay başına iki yazım var"dı.
Ölçülen yolda (Bash PreToolUse, izin) **zaten tek yazım vardı**: kaydedici `save()` çağırıyor,
o yol başka `save()` çağırmadan dönüyor. Dirty-tracking o yolda hiçbir yazımı engellemiyor,
üstüne 60 KB'lık bir string karşılaştırması ekliyor — ölçülen ~110 µs bu.

Asıl bedel çift yazımda değil, **tek yazımın kendisinde**: 200 hamlelik oturum dosyası
(50'sinde ham metin, ~60 KB) her tool olayında serialize edilip `write_atomic` ile diske
yazılıyor. O yazım kaldırılmadan bu sayı 300 µs'nin altına inmez, ve kaldırmanın üç yolu var,
üçü de **bu koşunun "yapılmayacaklar" listesine ya da başka bir turun kapsamına giriyor**:

1. **Kaydı diske değil daemon'a yazmak.** Süreç başlatma + tam dosya yazımı yerine kalıcı
   süreçte bellekte tutmak. Bu R7'nin kendisi (`rabadon-gated`, unix socket, hedef < 1 ms).
2. **Append-only hamle günlüğü**, oturum dosyasının içinde JSON dizisi yerine. Olay başına
   tek satır eklenir, tam dosya yeniden yazılmaz. Bu R1'in depolama sözleşmesini değiştirir —
   `moves_test.sh`'ın sabitlediği şeyi — yani R1'i yeniden açmak demek.
3. **Kaydı hot-path'ten çıkarıp ayrık çocuğa vermek.** Ama o zaman red yolunda kayıt
   kaybolabilir, ki R1'in tam kaçındığı şey oydu.

Kapının kuralı: "R<n>.2'ye gidiyorsa DUR; iki ara tur = tasarım hatası, operatöre gider."
Buradaki tam olarak o: bedel bir ayar hatası değil, **depolama biçiminin kendisi**. İkinci bir
ara tur tahmin ederek yeni bir tasarım seçmek olurdu. `reports/R2/SORU.md`'de üç yol,
maliyetleri ve benim önerim yazılı.

**Karar: DUR.** Push edildi, soru yazıldı, bekliyorum.

---

## 2. Plandan sapma — temiz (üç sapma, üçü de gerekçeli ve kanıtlı)

- **`export CXX` yapılmadı** (R0). PROJECT.md S0.2 iki *alternatif* çare sunuyor; birincisi
  on scriptte zaten yapılmış, export ikincisini uygulayıp birincisini bozardı. Kanıt ve
  gerekçe: `reports/R0/CLAIM.md` çağrı 1. Yerine Makefile varsayılanı `c++` yapıldı.
- **`docs/quickstart.md:148` değiştirilmedi** (R0). Plan onu bayat sanıyordu; `rabadon usage`
  gerçekten 7 gün varsayıyor (`native/stats.cpp:472`) ve blok "EXAMPLE OUTPUT" etiketli.
  Kanıt: `reports/R0/CLAIM.md` çağrı 2, ve `reports/R0/accept.sh` 2b bunu kayma karşısında
  koruyan teste çevirdi.
- **`native/postuse_test.sh` düzenlendi** (R1). Legacy node motoruna karşı differential ve
  `moves` node'un hiç üretemeyeceği bir alan. Hariç tutma kendi commit'inde, koddan önce,
  gerekçesi dosyada; kayıt `moves_test.sh`'ta tam olarak iddia ediliyor. İddia taşındı,
  düşürülmedi.

Gerekçesiz sapma yok.

## 3. Çökmüş iddia — temiz (hepsi aynı commit'te düzeltildi)

R0'da 11 iddia birincil kaynakta çöktü, 2'si çürütüldü. KOSU-RABADON.md'de düzeltildi ya da
`docs/POSITIONING.md`'de **UNVERIFIED** işaretlendi; M4 fiyat hipotezi **AÇIK**'a çevrildi.
Yayınlanmış hiçbir metne bırakılmadı — README, package.json ve landing bu sayıların hiçbirini
taşımıyor. R1 ve R2'de yeni çöken iddia yok.

## 4. Test dürüstlüğü — temiz, ama iki kez sınandım ve ikisini de yazıyorum

- **`moves_test.sh` üç iddiayı boşta geçiriyordu** (boş kayıtta kendiliğinden doğru) ve
  fixture watch modda olduğu için "aynı çıkış kodu" iki izin yolunu kıyaslıyordu. Test
  sıkılaştırıldı, ürün değil.
- **Bir iddiam üründe yanlıştı:** `4 passed in 0.12s` yeşil bekliyordum; sınıflandırıcı yeşil
  için kanıt istiyor. **Sınıflandırıcıyı gevşetmedim** — bir saat önce yazdığım testi tatmin
  etmek için check zayıflatmak tam olarak 5. sinyalin adı. Fixture sınıflandırıcının diline
  çevrildi ve gerekçe dosyaya yazıldı.
- **R2'de bir kural fixture yüzünden sıkılaştı, gevşemedi:** `lint, build, lint, build` `repeat`
  ateşledi. Eşiği yükseltip geçmedim; kurala "ilerlemiyor olma kanıtı" şartı eklendi
  (eşleşen hamlelerin en az ikisi hata taşımalı). Kural daha az ateşliyor, daha çok değil.

## 5. Operatör kararı — var, ve **bloklıyor**

`reports/R2/SORU.md`: hamle kaydının depolama biçimi (soru 1, R3'ü bloklar) ve `docs/kanit/`
(soru 2, bloklamaz).

---

**Karar tablosu sonucu: madde 1 kötü, R1.1 düzeltmedi, ikinci ara tur tasarım kararı
gerektiriyor → DUR.**
