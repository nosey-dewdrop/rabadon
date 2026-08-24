# R7 harness — seçim ve sabitleme

Durum: SEÇİLDİ ve SABİTLENDİ. Koşu YAPILMADI.
Tarih: 2026-08-24 (tur 4 yapan oturumu)

## Seçim

    repo   : SWE-bench/SWE-smith
    commit : 057f0478b6918bfcd89a51ceeec7229c60bb1028   (tag v0.0.6)

Bu iki satır `reports/R7/accept.sh` GOAL 4b ve 4c'nin istediği şeydir:
tam org/repo adı + 40-hex commit. "Terminal-Bench" tek başına dört ayrı
repoya işaret ettiği için kabul betiği çıplak ismi reddediyor.

## Nasıl doğrulandı (uydurulmadı)

Hash uzaktaki gerçek repodan çözüldü, elle yazılmadı:

    git ls-remote --tags https://github.com/SWE-bench/SWE-smith
    ...
    057f0478b6918bfcd89a51ceeec7229c60bb1028  refs/tags/v0.0.6

Hareketli `HEAD` değil, sabit bir sürüm etiketi seçildi — HEAD yarın
değişir ve beş sayı karşılaştırılamaz hale gelir.

## Neden SWE-smith, neden Terminal-Bench değil

Karar zevk değil, kabul betiğinin ölçtüğü metrikten çıkıyor. GOAL 6a ham
kayıtta her görev için `heldout_pass` alanı istiyor ve 5b görev anahtarı
olarak `instance_id`'yi kabul ediyor (accept.sh:309, :341). Bu SWE-bench
ailesinin sözlüğü: saklanan testle ölçülen kod-onarım başarısı. Terminal-Bench
terminal görevleri koşturur, saklı test/onarım oranı üretmez — seçilseydi
6a–6e ham veriden doldurulamazdı.

İkinci gerekçe: rabadon'un koruduğu şey depoda kod değiştiren ajandır;
iki kollu koşunun (A: ajan yalnız, B: ajan + rabadon) anlamlı olması için
görevlerin ajanın kendi testini optimize edebileceği cinsten olması gerekir.
6a bunu açıkça yasaklıyor ("the agent's own test does not count"), ki bu
ancak saklı testi olan bir harness'ta uygulanabilir.

## Bu dosyanın KAPSAMADIĞI şey

GOAL 4d (koşu öncesi hazırlığın kaydı) bilerek BOŞ bırakıldı ve KIRMIZI
kalıyor. O hazırlık henüz yapılmadı; yapılmadan buraya yazmak kabul
betiğini boş yere yeşile çevirmek olurdu — accept.sh'in başlığındaki
"NO ASSERTION MAY PASS VACUOUSLY" kuralının ihlali. 4d, iki kollu koşu
fiilen kurulduğunda, yapılan işin kaydı olarak eklenir.

Aynı şekilde GOAL 5 ve 6 (ham JSONL, beş sayı) bu dosyayla ilgisizdir ve
kırmızı kalır. Seçim yapıldı; koşu yapılmadı.
