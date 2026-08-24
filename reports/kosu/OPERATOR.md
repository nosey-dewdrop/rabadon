
OPERATÖR: R7'de iki karar bekliyor; ikisi de ON-KAYIT'a dokunan semantik değişiklik.

**Durum.** 23 yeşil / 3 kırmızı. Kalan kırmızılar:

1. **6e/7b — `estimated_saved`:** accept.sh 6e bunu **token** cinsinden bir int bekliyor; rabadon `saved_usd` (dolar, bazen null) üretiyor ve B kolu COUNTER olayı kaçış yolunu kapattı (`calls:0`, `tok_in/cw/cr/out:0` — dolara bile çevrilemiyor). Tek çıkış: (b) 6e'yi `total_cost_usd` ile dolar-dolar yapmak — accept.sh + ON-KAYIT değişikliği. Yoksa (c) ikisini kırmızı bırakmak ve R7'yi 23/25 ile kapatmak.

2. **astroid N=6:** `bench/pre-verify.sh`'a "bozuk dalda zaten düşen P2P testleri taban kümeden çıkarılır" kuralı eklenmesi gerekiyor — bu ON-KAYIT'ın dondurduğu puanlama semantiğine dokunuyor, insan onayı ister. Olmadan N=4 kalıyor.

**Önerim:** (b)'yi uygula — 6e'yi `total_cost_usd`'ye çevir, ON-KAYIT + accept.sh güncellenir, R7 25/25 kapanır. Token tezini değil birimi düzeltiyoruz; anlam değişmiyor, ölçüt ölçülebilir hale geliyor. astroid kuralını da onaylarsan N=6'ya çıkılır ama önce b kararı.

CEVAP satırları + ONAY yaz; seçtiğin yönde döngü devam eder.
