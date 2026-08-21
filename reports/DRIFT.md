# DRIFT — kayma sayacı (§6.4)

Her turun sonunda **bir satır**. Yorum bu başlığın altına değil, turun kendi
CLAIM.md'sine yazılır.

Üç kırmızı bayrak — herhangi biri görülürse koşu durur:
1. Üst üste iki turda "kapsam dışı" dolu → yön kaymış.
2. Bir turun kabulü kısmi kaldı ve sonraki tur yine de başladı → kapı delinmiş.
3. `make test` sayısı bir turda düştü → yeşil satın alınmış.

```
T1 | 2026-08-20 | kabul: 17 yeşil / 2 kırmızı (KISMİ) | kapsam dışı: yok (ama kapsam içi madde 3 YAPILMADI: GitHub description+topics) | varsayım değişti: §T1.4'ün "her satır aynı sayı" ile "sayı ledger'dan okunur" maddeleri çakışıyor — reports/T1/CHALLENGE.md
```

```
T1 | 2026-08-20 | VARSAYIM DEĞİŞTİ (insan onaylı): §T1.4 + Kabul maddesi 1 düzeltildi — "repair sayısı geçen her satır aynı değer" ifadesi, aynı maddenin "sayı ledger'dan okunur" cümlesiyle çakışıyordu; ledger dökümü projeye göre 0 ve 2 basıyor ve ikisi de doğru. Yeni ifade iddia/veri ayrımı yapıyor, per-project sayımları muaf tutuyor, ve karşılığında ledger bloğunun TOPLAM satırının 2 okuduğunu ayrıca zorunlu kılıyor. Gerekçe: reports/T1/discards.txt madde 8.
```

```
T1 | 2026-08-20 | kabul: 20 yeşil / 0 kırmızı (TAMAMLANDI) | kapsam dışı: yok | kapsam maddesi 3 (GitHub description+topics) kapandı
```

**Bayrak yok. T1 kapandı, T2 başlayabilir.**

Üç kırmızı bayrağın hiçbiri yanmadı: kapsam dışına çıkılmadı, tur kısmi
bırakılıp üstüne gidilmedi, `make test` sayısı düşmedi (hiçbir test dosyasına
dokunulmadı).

```
T2 | 2026-08-21 | VARSAYIM DEĞİŞTİ (insan onaylı, uygulamadan önce): protokol "25 CLI verb'ü / taşınan 20" diyordu, bu rakam ölçülmemiş, hafızadan yazılmıştı. Dispatcher'da 43 verb token var; taşınan gerçek sayı 29. Ayrıca 25'ten 5 TABLO SATIRI çıkarılarak bulunmuş bir off-by-one vardı. Gerekçe: reports/T2/discards.txt madde 1.
T2 | 2026-08-21 | kabul: 21 yeşil / 0 kırmızı (TAMAMLANDI) | kapsam dışı: yok | temiz zeminde sıfırdan derlenerek doğrulandı (21/0) | make test 2014 -> 2015 (düşmedi, arttı)
```

**Bayrak yok. T2 kapandı, T3 başlayabilir.**

T2'de iki test dosyası değiştirildi (`cli_test.sh`, `unknown_verb_probe.py`),
ikisi de koddan önce ve kendi commit'lerinde. İkisi de ana yardım ekranının her
verb'ü listelemesini şart koşuyordu, yani turun hamlesini yasaklıyordu.
Korudukları şey keşfedilebilirlikti, ekranın kendisi değil; ikisi de artık
`rabadon dev --help`'i de okuyor. Eşik düşürülmedi, bir iddia eklendi, test
sayısı arttı. Zayıflatma değil — ama bir turun test dosyasına dokunması her
zaman bakılacak bir yerdir, kayda geçiyor.

T2'nin NOT VERIFIED'ı: bağımsız hakem oturumu T2'ye bakmadı.

T1'den kayda geçen iki uyarı, hâlâ açık:
- T1'in son hali (20/0) bağımsız bir hakem oturumu tarafından denetlenmedi;
  testi yeniden yazan oturum kendi işini mutasyonla sınadı. Kendi kendini ölçmenin
  bir biçimi (§4).
- `accept.sh`'ın muafiyetinde bilinen ve kapatılmayan bir delik var: tam kurallı
  yazılmış uydurma bir ledger bloğu muaf olurdu. Gerekçesi ve tutamakları
  `reports/T1/CLAIM.md` içinde.

Hakem kaydı: T1'i ayrı bir oturum denetledi, Kapı 1'i temiz buldu, README ve
BENCHMARK'a yazılan her sayıyı ledger'a karşı doğruladı (uydurma sayı yok), ve
ilk CHALLENGE'ın üç maddesinden 1.5'ini reddetti. Reddedilenler metin
düzeltmesiyle kapatıldı, itiraz tek satıra indi.
