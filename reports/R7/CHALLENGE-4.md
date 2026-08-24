# CHALLENGE-4 — `accept.sh` 6e/7b bir DOLAR değerini bir TOKEN farkıyla karşılaştırıyor

durum: **AÇIK**, insan onayı bekliyor
açan: tur 19 yapan oturumu, 2026-08-24
dokunulan mühür: **hiçbiri** — bu bir öneri, `accept.sh` DEĞİŞTİRİLMEDİ

## Neden şimdi çıktı

Tur 18 CEVAP 2, `ab_run.sh`'ın `estimated_saved` alanını hiç yazmadığını tespit
edip kabloyu çektirdi. Kablo çekilince 6e'nin **erişilebilir** hâli ilk kez
görülebildi. Alan hiç yazılmadığı sürece 6e her zaman "field yok" diye kırmızıydı
ve aşağıdaki kusur **ölü koddu**; artık ölü değil.

## Kusur

`reports/R7/accept.sh:478-484`:

    e = float(est)                      # arm B'nin estimated_saved TOPLAMI
    real = float(tok_A) - float(tok_B)  # iki kolun TOKEN farki
    DEV  = abs(e-real)/abs(real)*100

`est`'in kaynağı sayacın `saved_usd` alanıdır (`native/counter.h:299`,
`o += ",\"saved_usd\":"`). Bu bir **ABD doları** değeridir.
`tok_A - tok_B` ise bir **token** farkıdır. İkisi aynı birimde değil.

### Ölçüldü (sentetik JSONL, `accept.sh`'ın KENDİ okuyucusuyla)

    est (saved_usd, DOLAR)      : 0.0417
    real (tok_A - tok_B, TOKEN) : -90.0
    accept.sh:6e sapma          : 100.0%

Sapma, dolar değeri ne olursa olsun ~%100 çıkar; çünkü token farkının yanında
tipik bir dolar sayısı daima ~0'dır:

    saved_usd=0.0001  -> sapma 100.0%
    saved_usd=0.05    -> sapma 100.1%
    saved_usd=1.0     -> sapma 101.1%
    saved_usd=5.0     -> sapma 105.6%

## Neden bu bir kabul kapısı sorunu, kozmetik değil

**6e'de eşik YOK.** `accept.sh:481` yalnız `DEV = NODIFF` (iki kol aynı tokeni
harcadı) durumunda kırmızı verir; başka HER sapma değerinde **yeşil** basar:

    pass "6e counter validation: estimate ... deviation 100.0%"

Yani 6e, "sayaç doğrulandı" diyen bir satırı **%100 sapmayla** basar. Sapmanın
kendisi sayacın doğrulanMAdığını söylerken kapı yeşil olur. Bir kapının
ölçtüğünü iddia ettiği şeyi ölçmemesi, bu projenin tam olarak engellemek için
var olduğu şeydir (CLAUDE.md, "iki düşman": ödül hacklemesi).

**7b'de eşik VAR** (`accept.sh:511`, %50) ve ~%100 sapma 7b'yi kırmızı yapar:

    fail "7b falsification 2 TRIGGERED: counter deviates 100.0% ... (limit 50%)"

7b'nin kırmızı olması güvenli yön — dolar satırının yayınlanmasını bloke eder.
Ama gerekçe YANLIŞ atfedilir: rapor "sayaç gerçek token farkından %100 sapıyor"
der; oysa sapan sayaç değil, **karşılaştırmanın birimidir.** Yanlış teşhis,
sayacın formülünü boşuna yeniden yazdırır — bileşik hatanın ta kendisi.

## Şu an bir sayı yayınlanma riski YOK

`counter.h:63 MIN_HISTORY = 3` ve iki kollu koşuda her görev tek oturum
olduğundan `median_n:0` → `has_saved` false → `saved_usd` **null** →
`estimated_saved` **null** → 6e "field yok" diye kırmızı kalır.
Bu, tur 18 CEVAP 2'nin **beklenen** sonucudur. Kusur bugün tetiklenmiyor;
`MIN_HISTORY` düşürülür ya da çok-oturumlu koşuya geçilirse tetiklenir.

## Önerilen diff (UYGULANMADI — mühür + insan onayı)

İki yoldan biri seçilmeli; ikisi de `accept.sh`'a dokunur:

**(a) Sayacı token cinsinden okut.** `estimated_saved`, `saved_usd` yerine
sayacın token tahmininden türetilsin. **Engel:** sayaç böyle bir alan
üretmiyor; `event_body` içinde token alanları var (`tok_in`, `tok_out`, …) ama
"kesilen zincirlerin kurtardığı token" diye bir alan YOK. Bu, ürün tarafında
yeni iş demektir.

**(b) Karşılaştırmayı dolara çevir.** `real`, token farkı yerine
**maliyet farkı** olsun: JSONL'de zaten `total_cost_usd` var (`ab_run.sh`,
her iki kol için yazılıyor). O zaman:

    real = cost_A - cost_B        # DOLAR
    DEV  = abs(saved_usd - real)/abs(real)*100

Bu, iki tarafı da dolara getirir ve **yeni ürün işi gerektirmez.**
Ayrıca 6e'ye 7b'yle aynı eşiğin (%50) konması önerilir; eşiksiz bir
"doğrulama" kapısı doğrulama değildir.

**Bu oturumun önerisi: (b) + 6e'ye eşik.**

## Karar kimin

`accept.sh` mühürlüdür (`KOSU-RABADON-2.md §A1`: "accept.sh olduğu gibi
kalır"). Kabul ölçütü değişikliği **kendi commit'inde, kod olmadan, gerekçesiyle**
yapılır (CLAUDE.md, ihlal edilemez kural 2) ve **insan onayı** gerekir.
Bu tur hiçbir şey değiştirmedi; challenge açıldı, adım kırmızı sayılıyor.
