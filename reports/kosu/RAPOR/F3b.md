# F3b — kart

## TAHMİN (§3.12, iş başlamadan yazıldı, 2026-08-29)
**Kart sayısı: 4.** İki katı = 8; 8'i aşarsam durur, hakeme giderim.
1. **D7** (BLOKLAYAN) — `Makefile` önkoşulları include grafiğine hizalanır + kırmızı
   düşebilen yeni süit + mutasyon kanıtı. Tahmin: ~40 kural taranır, ≥1 gerçek
   eksik önkoşul bulunur, süit ≥8 iddia.
2. **F3-S1** — sevk edilen ikilinin uçtan uca atfedilebilir maliyeti 1681,3 µs'ten
   düşürülür. Tahmin: 1681 → 1200 µs bandı gerçekçi, tavan 1000 µs'e inmek
   ŞÜPHELİ; ne çıkarsa sayıyla yazılır, tavan oynatılmaz.
3. **F3 (b) katmanı** — merdiven (enjeksiyon→enjeksiyon→blok) + `rabadon mute`,
   ve "ajan okudu" için imza-değişimi kabulü. Tahmin: fikstür üstünde kanıt
   mümkün, CANLI ajan üstünde şüpheli.
4. **F3 (c) negatif kontrol** — `ab_run.sh` iki kollu koşu. Tahmin: **ŞÜPHELİ** —
   ağ + `claude -p` + saatlerce koşu gerektirir; koşamazsam "ölçemedim" yazılır.
