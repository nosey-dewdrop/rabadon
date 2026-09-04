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

## 4d — koşu öncesi hazırlığın kaydı (tur 14'te YAPILDI, sonra yazıldı)

Bu bölüm tur 4–13 boyunca bilerek BOŞ ve KIRMIZI bırakıldı: hazırlık
yapılmadan yazmak accept.sh'in "NO ASSERTION MAY PASS VACUOUSLY" kuralını
ihlal ederdi. Aşağıdaki üç madde artık `reports/R7/ab_run.sh` içinde
UYGULANMIŞ koddur, niyet değil.

**1. `git` geçmişi temizlenir — formalite değil, geçerlilik şartı.**
Ajanın göreceği ağaç, ayna klonundan kopyalanır ve `.git` dizini tamamen
SİLİNİR (`ab_run.sh`, `hazirla_gorev`). Sebep ÖLÇÜLDÜ: `origin/main` hem
**çözümü** (düzeltilmiş kaynak) hem **saklı F2P testlerini** taşıyor, yani
tek bir `git diff origin/main` görevi çözerdi. Bu, iki kolu birden şişirir
ve bir hata gibi değil, "iki güzel sayı" gibi görünür. Puanlayıcı `main`'i
AYRI bir klonda (`/tmp/rbrun/scorer/<iid>`) tutar; ajanın ağacıyla teması
yoktur.

**2. Held-out testler yapısaldır.** SWE-smith instance dalında F2P test
dosyaları zaten silinmiş durumdadır (ölçüldü: autograd dalında
`tests/test_linalg.py` YOK). Puanlayıcı bu dosyaları koşudan SONRA
`git checkout origin/main -- <yol>` ile geri koyar ve F2P + P2P koşar.
`heldout_pass = (tüm F2P geçti) VE (P2P bozulmadı)`.

**3. Ağ (network/egress) kapatma — BEST-EFFORT olarak etiketlenir.**
Görev checkout'undan giden git/pip erişimi koşu sırasında gerekmez (bağımlılıklar
ajan başlamadan önce kurulur). Ancak **tam egress kapatma MÜMKÜN DEĞİLDİR**:
`claude -p` model API'sine çıkmak zorundadır, dolayısıyla ağ arayüzü açıktır ve
ajan teorik olarak dışarıdan bilgi çekebilir. Bu madde bu yüzden
**best-effort** diye işaretlenir ve öyle raporlanır — kapatıldı diye değil.
Kapatılan somut şey `.git`'tir (madde 1), ki asıl sızıntı kanalı oydu.

## Bu dosyanın KAPSAMADIĞI şey

GOAL 5 ve 6 (ham JSONL, beş sayı) bu dosyayla ilgisizdir; onların kanıtı
`reports/R7/ab_run.jsonl` ham kaydıdır.
