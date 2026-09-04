# F3g kart 3 — `2b`: ÖNCE PROFİL. Sonuç: suçlanacak bacak, suçlanması planlanan bacak değil.

Üç faz üst üste bir bacak suçladı ve üçü de çürütüldü (F3d "süreç başlatma %60",
F3e "%70 kural yolu", F3f'in ölçümü gürültü). Bu yüzden bu kartta önce profil
çıkarıldı, sonra hiçbir şey suçlanmadı.

## Profil — tek koşunun İÇİNDE bölünmüş, iki popülasyonun farkı değil

Alet: `reports/kosu/kanit/f3g/2b-profil.sh` — `gate.cpp`'nin kendi
`RABADON_PROFILE=1` üçlü ayrımını (ctor / main / exit) kullanır, N=200 gerçek
PreToolUse olayı, ALLOW yolu, olay başına bir süreç (hook'un yaptığı gibi),
her bacak MEDYAN. Üç bağımsız koşu (`2b-profil.out`):

| bacak | koşu 1 | koşu 2 | koşu 3 | yayılım |
|---|---|---|---|---|
| duvar (harness) | 3301,7 | 3288,6 | 3306,1 | 17,5 µs |
| **1 · exec + dyld + imajlar (main ÖNCESİ)** | **2312,8** | **2282,9** | **2307,4** | **29,9 µs** |
| 2 · statik init | 2,0 | 2,0 | 2,0 | 0 |
| **3 · rabadon'un KENDİ kodu (main→exit)** | **993,5** | **999,0** | **983,5** | **15,5 µs** |
| leg 1 payı | %70,0 | %69,4 | %69,8 | — |

Yayılım (30 ve 16 µs) gürültü bandının (|439 µs|) çok altında, çünkü ayrım
koşunun içinde eşli alınıyor. **Bu, beş fazda ilk defa bacakları ölçülmüş bir
ayrım.**

## Kural yolu ne kadar? ÖLÇÜLDÜ: 156,5 µs.

Aynı ikili, aynı olay, tek fark `guard.json`'daki `bash` kuralları:

    leg 3, 13 deny kuralıyla  = 1016,0 µs   (n=200)
    leg 3,  0 deny kuralıyla  =  859,5 µs   (n=200)
    ---------------------------------------------
    13 kuralın tamamı         =   156,5 µs  = duvarın %4,7'si

**F3e'nin "%70 kural yolu" iddiası bir sayıyla çürüdü.** Kural motorunu tamamen
silmek duvarı %4,7 düşürürdü.

## Yükleme tabanı — 818 KB'lık imajın bedeli

Aynı harness, aynı makine, N=200 medyan:

    /usr/bin/true                  = 1335,7 µs   (harness + kernel exec tabanı)
    boş c++ ikilisi (16 KB)        = 1391,1 µs   (+55 µs = C++ çalışma zamanı)
    boş c++ + <regex> dokunulmuş   = 1513,6 µs
    native/rabadon-gate (818 KB)   = 3301   µs

## KARARIN ARİTMETİĞİ — tavan bu koldan kapanmıyor

`2b`'nin tanımı: **atfedilebilir = gate − boş taban.** Bugün ≈ 3301 − 1336 =
**1965 µs**, tavan **1000 µs**. Kapatılması gereken: **965 µs**.

- Kural motorunun TAMAMI 156,5 µs. Sıfırlansa kalan 1808 µs.
- rabadon'un KENDİ kodunun tamamı (leg 3) 990 µs. **Sıfırlansa bile** kalan
  ≈ 975 µs — yani ürünün her satırı silinse tavan ancak kıl payı tutuyor.
- Geriye kalan ≈ 920 µs, bu ikilinin **dyld tarafından yüklenmesidir**
  (818 KB imaj, boş bir C++ ikilisinin 55 µs'si ile aynı iş).

**Bu yüzden bu faz `2b`'yi hızlandırmadı ve hızlandırmayı denemedi.** Kural
yoluna, sinyallere ya da defter yazımına yapılacak hiçbir değişiklik 965 µs
bulamaz; sayının bulunacağı yer ya **imaj yükleme maliyeti** (bağlama/boyut) ya
da **çağrı başına süreç başlatmamak** (accept.sh'in kendi "with the daemon up"
ifadesinin işaret ettiği yol). İkisi de bu kartın kapsamı değil ve tahminle
girilmez — bu belge onların önündeki ilk ölçüm.

## Bugünkü sayı, iddiasız

`bash reports/R7/accept.sh` bu fazda iki kez koştu: **1331,3 µs** ve
**1297,5 µs**. Devralınan sayı 1378,0 µs. Üçü de |439 µs| bandının içinde,
**tek yanlı değil**, tekrar sayısı 2. **İDDİA YOK: bu faz `2b`'yi
hızlandırmadı.** Tavan oynatılmadı, `accept.sh` diff'te yok.
