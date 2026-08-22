# R1.3 — DUR, ve profil çıktısı (tahmin yok)

Kabul: **11 yeşil, 1 kırmızı.** Kırmızı olan tek şey Goal 4, yani turun var oluş sebebi.

## Şartlar

1. **Hot-path'te SHA doğrulaması yok.** ✅ `prev` her satıra yazılmaya devam ediyor;
   doğrulama yalnız `RABADON_MOVES_STRICT=1` ve `audit`'te. Hot-path olay başına **tek**
   hash hesaplıyor (son satırınki, bir sonraki append'in zincirlenmesi için) — N değil.
   **3a ve 3c iddiaları değişmeden yeşil.**
2. **Eşik göreli:** kayıt-kapalı medyanının %5'i. ❌ Tutmadı.
3. **SHA'sız salt parse maliyeti ayrı raporlandı.** ✅ Aşağıda.
4. **1b:** `ts` maskelendi, iddia yeşil. Maskeleme gevşetme değil — iddia "yazılmış baytlar
   oynamadı" diyor, iki sandbox iki farklı milisaniyede kuruluyor, maskesiz karşılaştırma
   depolamayı değil saati test ediyordu. `seq`, `tool`, `sig`, `prev` hâlâ bayt bayt kıyaslanıyor.

## Goal 4 — ölçüm

| kol | koşular (ms) | medyan |
|---|---|---|
| kayıt kapalı | 4.300 / 4.103 / 4.211 | **4.211** |
| kayıt + sinyal açık | 5.822 / 5.951 / 5.943 | **5.943** |

**Delta 1733 µs. Eşik %5 = 211 µs.**

SHA'nın çıkarılması ölçülebilir kazanç verdi (R1.2'de 1949 µs → şimdi 1733 µs) ama
büyüklük sırası değişmedi.

## Goal 5 — profil: kalan maliyet nerede

400 olaylık bir oturumun sonunda günlük **400 satır / 67.090 bayt**. Aynı fixture, aynı olay:

| ne ölçüldü | ms/çağrı |
|---|---|
| uzun günlük, zincir kontrolü **KAPALI** (hot-path'in bugünkü hali) | **6.647** |
| uzun günlük, zincir kontrolü **AÇIK** (STRICT) | 7.144 |
| kayıt tamamen kapalı (referans) | ~4.2 |

**Hot-path'in artık ödemediği SHA: 497 µs.**
**Hot-path'in hâlâ ödediği: ~2.4 ms — ve bunun neredeyse tamamı parse.**

Yani sıralama şu: hash maliyeti gerçekti ve gitti; **asıl maliyet 67 KB'lık günlüğün her
tool olayında baştan okunup ayrıştırılması.** Üç ara tur boyunca üç ayrı yeri ucuzlattık
(tam-dosya yazımı → append; çift yazım → dirty-track; N hash → 1 hash) ve her seferinde
ölçüm aynı şeyi söyledi: **maliyet, her olayda tüm tarihçeye dokunmanın kendisinde.**

Ayrıca dikkat: 400 satırlık günlükte hot-path 6.647 ms, 200 civarındakinde 5.943 ms.
**Maliyet oturum uzadıkça büyüyor** — sıkıştırma yalnız oturum sonunda çalıştığı için
oturum içinde bunu düzelten hiçbir şey yok.

## Ne ölçülmedi

- Parse'ın içinde ne var: `read_file` (I/O) mı, `get_str`/`get_num`'un satır başına
  tekrar tekrar string araması mı? Ayrıştırmadım, tahmin de etmiyorum.
- Sıkıştırmayı oturum içinde tetiklemenin (ör. 300 satırı geçince) maliyeti.
- Daemon'ın (R7) bunu ne kadar çözdüğü.

## DUR

Şartın gereği: eşik tutmadı → DUR + profil, tahmin yok. Profil yukarıda. Bir sonraki
hamleyi seçmek operatörün.
