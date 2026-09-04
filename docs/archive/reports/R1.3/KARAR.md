# R1.3 — KARAR

*İlk danışman kararı. Operatör tarafından verildi; danışman rolü bu karardan sonra
`docs/DANISMAN-PROMPT.md` ile ayrı oturumda koşar.*

## Değişmez

**Hot-path maliyeti oturum uzunluğuna bağlı olamaz.**

Ölçüm bunu üç kez söyledi: 200 satırlık günlükte 5.943 ms, 400 satırlıkta 6.647 ms.
Aynı komut, aynı fixture, tek fark tarihçenin uzunluğu. Bir gate'in bedeli, ajanın o
oturumda kaç hamle yaptığına bağlıysa, ürün uzun oturumda — yani en çok işe yaradığı
yerde — en pahalı hale gelir.

## Sunulan seçenekler ve neden reddedildi

Yapan oturum A/B/C sundu. **Üçü de reddedildi**, çünkü üçü de aynı değişmezi ihlal ediyor:

- **A (zincir doğrulamasını çıkar):** uygulandı, gerçek 497 µs kazandırdı, ve delta hâlâ
  1733 µs. Parse'a dokunmuyor; maliyet oturum uzunluğuna bağlı kalıyor.
- **B (yalnız kuyruğu oku):** maliyeti sabitlemiyor, sadece sabiti küçültüyor — ve
  `scope_drift` ile `root_migration`'ın gördüğü veriyi daraltarak R2'nin ölçtüğü şeyi
  değiştiriyor. Ölçümü korumak için ölçüleni bozmak.
- **C (R7'ye bırak):** ölçülmemiş bir varsayıma dört tur yaslanmak. Daemon süreç
  başlatmayı çözer; her olayda 67 KB ayrıştırmayı çözeceğini kimse ölçmedi.

## Tasarım D — sabit genişlikli ikili halka

- **Kayıt dosyası ikili ve sabit genişlikli:** 200 kayıt × ~320 B. Tek `read` (ya da
  `mmap`), **parse yok**. Bir kaydı okumak indeks aritmetiğidir, metin taraması değil.
- **Başlıkta artımlı özetler**, her append'de güncellenir, hiçbir zaman yeniden hesaplanmaz:
  - `touchedDirs` tablosu (scope_drift bunu okur, tüm tarihçeyi değil)
  - `err_sig` sayaç tablosu (root_migration bunu okur)
  - son-20-`sig` halkası (repeat bunu okur)
- **`prev` hash kayıtta durur**, `audit` gezer. Hot-path olay başına **tek** hash.
- **Atomiklik başlık `count` ile:** kayıt önce yazılır, sonra `count` artırılır. Yarım
  yazılmış kayıt `count`'un dışında kalır, yani hiç var olmamıştır.
- **JSONL yalnız `audit --export`.** İnsan ve test okuması dışa aktarma yoluyla; hot-path
  hiç JSON üretmez.
- **Sıkıştırma satırı silinir.** Halka sabit boyutlu; sıkıştırılacak bir şey yok.
  `docs/butce.md`'nin sıkıştırma bölümü kaldırılır.

## Karar

D uygulanır. A/B/C uygulanmaz.

## Kabul ölçüsü

1. **50 olayda ve 400 olayda aynı medyan** (fark ölçüm gürültüsü içinde). Değişmezin
   testi budur: maliyet oturum uzunluğuna bağlı değilse iki sayı aynı çıkar.
2. **delta ≤ %5** (kayıt+sinyal açık − kayıt kapalı, kayıt-kapalı medyanının %5'i).
3. **`native/moves_test.sh` 21/0**, iddiaları değişmeden, **export üstünden okuyarak**.
4. **3a ve 3c yeşil** — eksik kayıt yakalanır, `rabadon audit` yeşil kalır.

Tutarsa onay beklenmez, R3'e geçilir.

## Etiket: DEĞİL

Teknik tasarım kararı. Kapalı listenin hiçbir maddesine girmiyor.
