# R7 — CHALLENGE (tur 6, 2026-08-24)

CLAUDE.md: *"Never weaken, delete, rename, skip, or reinterpret an existing test
to make anything pass."* ve *"Never fix it silently."* Aşağıdaki üç kalem
`reports/R7/accept.sh`'a **DOKUNULMADAN** yazıldı. Önerilen diff'ler uygulanmadı;
çözüm insan onaylı bir commit'tir. Çürütülen adım KIRMIZI sayılır.

---

## CHALLENGE 1 — GOAL 2a hiçbir uygulamayla geçemez (uykusuz hazırlık döngüsü)

`reports/R7/accept.sh:113`

    for _ in $(seq 50); do [ -S "$SOCK" ] && DAEMON_UP=1 && break; done

Bu döngüde **`sleep` yok**. 50 kez `[ -S ... ]` bash builtin'i, yani toplam
bekleme süresi ~0.1 ms. Daemon'ın bağlanması için gereken süre ölçüldü:

    bind #1 took 22.5 ms
    bind #2 took 22.6 ms
    bind #3 took 21.8 ms

Aradaki oran ~220x. 22 ms'nin neredeyse tamamı fork+exec+dyld'dir — yani
**hiçbir daemon uygulaması bu döngüyü kazanamaz**, çünkü şart, exec'in kendisinden
kısa sürede bind etmeyi istiyor. 2a'nın kırmızılığı daemon hakkında bir olgu
değil, betik hakkında bir olgudur. Aynı desen `accept.sh:169`'da da var, yani
GOAL 2b/2c ölçümü de aynı yarışı kaybediyor.

**Önerilen diff (UYGULANMADI):** iki satırdaki döngüye gerçek bekleme konur —
`for _ in $(seq 100); do [ -S "$SOCK" ] && break; sleep 0.05; done` (5 sn tavan).
Şart gevşemez: soket yine ZORUNLUDUR, yalnız betik onun belirmesini beklemeye
başlar.

## CHALLENGE 2 — GOAL 3 karşılaştırması hiçbir uygulamayla geçemez (kum havuzu kimliği)

`accept.sh:240-256` iki kolu bayt bayt karşılaştırıyor, ama her kol `sb` ile
**AYRI bir `mktemp -d` kum havuzu** yaratıyor. Ledger satırları o kum havuzunun
kimliğini taşıyor: `run` (zaman+pid), `pipe` (proje dizininin adı), ret metnindeki
mutlak proje yolu ve bunların üstüne kurulu zincir hash'i. `sed` yalnız `ts` ve
ISO damgalarını normalize ediyor.

Kanıt — **daemon hiç devrede değilken**, `accept.sh`'ın `run3` fonksiyonu birebir
kopyalanıp AYNI bayrakla iki kez koşuldu (yani A ile A'):

    *** TWO IDENTICAL INVOCATIONS DIFFER — the comparator cannot pass ***
    < ...,"run":"ng-68635241-66648","pipe":"p.OngqAO:session",...
    > ...,"run":"ng-68635276-66662","pipe":"p.e7cQI7:session",...

Aynı ikili, aynı ortam, daemon yok — yine de ayrışıyor. Yani 3a/3b/3c
**fail-SAME'i ölçmüyor**, kum havuzu adlarının farklı olduğunu ölçüyor ve her
zaman kırmızı. Betiğin kendi başlığı bunu yasaklıyor: *"a comparison that cannot
fail is not evidence"* — burada tersi olmuş, başarısız OLMAKTAN başka şansı olmayan
bir karşılaştırma var.

**Önerilen diff (UYGULANMADI):** `run3`'ün `sed` zincirine kimlik alanları eklenir —
`s/"run":"[^"]*"/"run":R/g; s/"pipe":"[^"]*"/"pipe":P/g`, kum havuzu yolları
`s#'"$W"'/[hp]\.[A-Za-z0-9]*#SANDBOX#g`, ve zincir hash satırı `s/^[0-9a-f]{64} /HASH /`.
ANLAMLI olan hiçbir şey normalize EDİLMEZ: çıkış kodu, `ev` türü, `mode`, `rule`,
ret metninin kendisi, satır sayısı ve sırası aynen karşılaştırılmaya devam eder.

## CHALLENGE 3 — R7'nin hız şartı ile aletinin ölçtüğü şey çelişiyor (mimari)

Bu, betik hatası değil, **planın kendisine** dair bir bulgu; `KOSU-RABADON-2.md §A1`
ve `KOSU-RABADON.md §R7`'yi ilgilendirir.

R7 iki şeyi aynı anda söylüyor:
1. daemon kapı medyanını < 1 ms'ye indirsin — gerekçe: çağrının ~2.3 ms'si
   fork/exec/dyld'dir (`reports/R1.3/PROFIL.md`), daemon onu siler;
2. ölçüm **süreç içi** probla yapılır, **uçtan uca cetvel YASAK**
   (`accept.sh` başlığı, `KOSU-RABADON-2.md:50-53`).

İkisi birlikte tutarsız. Prob `t0`'ı **istemcinin** `main()`'inin başına koyuyor.
Ama fork/exec/dyld `main()`'den ÖNCE olur — yani **daemon'ın sildiği maliyet
zaten ölçümün dışında.** Buna karşılık daemon'ın eklediği maliyet (bağlan, gönder,
iki fork, worker'ın TAM yargılaması, cevabı bekle) ölçümün tam içinde, çünkü
istemci verdict'i beklemek ZORUNDA — çıkış kodu yargının kendisidir.

Ölçüldü (accept.sh'ın kendi prob yaması, 300 örnek, `native/` değiştirilmedi):

| kol | süreç içi medyan |
|---|---|
| daemon AÇIK | **1597.3 µs** |
| daemon YOK | **1139.6 µs** |
| tavan | 1000 µs |

Daemon sayıyı **457 µs kötüleştiriyor**. Bu bir uygulama kusuru değil, bu aletle
bu mimarinin tanımı: istemci beklemek zorundaysa, işi başka bir sürece taşımak
süreç-içi süreyi düşüremez, yalnız IPC ekler.

Sonuç: **GOAL 2b bu şekilde tanımlı kaldıkça hiçbir daemon tarafından
geçilemez.** <1000 µs yalnız yargılamanın KENDİSİ ucuzlarsa gelir (PROFIL.md
adresi veriyor: `save#2` ~165 µs, `last_ledger_mode` hâlâ O(dosya)) — ki bu
daemon işi değil, gate işi.

**Seçenekler (karar OPERATÖR'ün / değerlendirenin, bu oturum SEÇMEDİ):**
- **(a)** Hız şartı yeniden yazılır: daemon'ın iddiası uçtan uca duvar saatidir
  ve ince bir istemci gerektirir (gate.cpp'yi linklemeyen küçük binary). Bu,
  "uçtan uca YASAK" kuralıyla çelişir, yani o kural da revize edilmelidir.
- **(b)** <1 ms hedefi daemon'dan KOPARILIR ve gate'in kendi maliyetine bağlanır
  (PROFIL.md'nin adres verdiği iki kalem). Daemon o zaman R7'nin parçası olarak
  kalır mı, ayrı bir tura mı gider — açık.
- **(c)** Daemon R7'den tamamen düşer; kanıt kolu (GOAL 4–7) R7 olur.
  Operatör CEVAP 3 bölmeyi reddetti, o yüzden bu seçenek o kararı yeniden açar.

Bu oturum hiçbirini seçmedi ve `accept.sh`'a dokunmadı: çürütülen adım kırmızı
kalır, karar belgeye insan onaylı diff'le girer.

---

## Bu turda DOĞRULANMADI

- 1597 µs'nin bileşenleri (istemci-öncesi iş / IPC / worker yargılaması)
  ayrıştırılmadı; sıcak fork'un yargılamayı ucuzlatıp ucuzlatmadığı bilinmiyor.
- Daemon'ın uçtan uca kazancı hiç ölçülmedi (R7 yasağı).
- Ölçüm tek makinede (macOS, darwin-arm64) yapıldı. Taşınabilirliği
  DOĞRULANMADI; `SCM_RIGHTS`, `SA_RESTART` ve `umask`+`bind` davranışı Linux'ta
  denenmedi.
- Daemon eşzamanlı istemcilerle test EDİLMEDİ (tek istemcili ölçüm).
- Daemon'ın uzun ömürlü çalışırken bellek/fd sızdırıp sızdırmadığı ölçülmedi.
