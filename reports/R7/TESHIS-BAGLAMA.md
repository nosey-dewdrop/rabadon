# B KOLU BAĞLAMASI — native gate'e çevrildi, ve bağlama kabulü sertleştirildi

Tarih: 2026-08-24 (tur 17). **Hiçbir ajan koşulmadı, para harcanmadı.**
Kaynak: tur 16 teşhisi (`reports/R7/TESHIS-B-KOLU.md`) + operatör talimatı.

Bu dosya üç şey yapar: yapılan düzenlemeyi yazar, düzenlemenin **ölçülmüş**
etkisini yazar, ve düzenlemenin **kapatmadığı** kırmızıların sebebini yazar.

---

## 1. Yapılan (yalnız statik dosya düzenlemesi)

`reports/R7/ab_run.sh`:

| yer | önce | sonra |
|---|---|---|
| `GATE` | `$ROOT/hooks/gate.mjs` (legacy JS) | `$ROOT/native/rabadon-gate` |
| çalıştırma | `timeout 2 node $GATE` | `timeout N $GATE` (node yok) |
| olaylar | yalnız `PreToolUse` | `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `SessionEnd` |
| ikili yokluğu | sessiz | koşu **başlamıyor** (`make` de, sonra gel) |
| bağlama kabulü | `ledger_new_lines > 0` | native satır **ve** COUNTER **ve** ≥1 SIGNAL/INJECT |

Model `hooks/install.mjs:169-175`. Ondan iki bilinçli fark:

- **`SessionEnd` EKLENDİ.** install.mjs onu bağlamıyor, `Stop` yedeğine
  güveniyor. Burada COUNTER'ın ateşlenmesi turun kabul kalemi (6e/7b), o yüzden
  planın kendi hook'u da bağlanır. `gate.cpp:3992-3994` ikisini de kabul edip
  önce geleni yazıyor.
- **`rabadon-drift` BAĞLANMADI.** Bu kol birikim motorunu ölçüyor; drift ayrı
  bir ürün yüzeyi ve kola ait olmayan gürültü ekler.

**`PreToolUseResult` diye bir olay yok.** `gate.cpp:2733-2734` tam olarak altı
olay tanıyor ve tanımadığını sessizce düşürüyor. Bağlanan altı da odur.

**Timeout — B1.5'in literal `timeout 2`sinden bilerek sapıldı.** O rakam tek işi
hızlı bir verdict olan bir kapı için yazılmıştı. Native gate'in **kapanış** yolu
(COUNTER) bütün spool'u ve projedeki her ring'i yürüyor; ortak spool 220k+ satır.
2 saniyede öldürmek, kolun ölçmek için var olduğu olayı tam yazılırken keserdi —
tur 14'teki `>/dev/null` hatasının zamanlama kılığında tekrarı. Sıcak yol 10 s,
kapanış 60 s. B1.5'in koruduğu iki şey aynen duruyor: süre **sınırlı** (yetim
süreç yok, B1.9) ve exit **daima 0** (hook oturumu tutamaz).

---

## 2. Ölçüm — bağlama gerçekten ne üretiyor? (ajansız, sentetik oturum)

`native/rabadon-gate`'e altı olay elle beslendi (SessionStart →
UserPromptSubmit → 5×(PreToolUse+PostToolUse, `pytest -q` kırmızı) →
SessionEnd), izole `HOME` içinde. Ajan yok, model çağrısı yok, para yok.

**COUNTER ATEŞLENDİ.** Eski `PreToolUse`-tek bağlamada bu **yapısal olarak
imkânsızdı** (COUNTER yalnız `SessionEnd`/`Stop`'ta, `gate.cpp:4001`). Ledger:

    1 CONTRACT   1 COUNTER   2 RUN_START   5 STEP_OK   2 STEP_START   3 CHECK_FAIL   3 STOP

stdout'a düşen satır: `rabadon: bu oturumda müdahale yok.`

**`saved_usd` = `null`. Sıfır DEĞİL, gerçek değer de değil — `null`.** COUNTER
satırının tamamı:

    "chains_cut":0, "fixed":0, "injections":0, "saved_usd":null, "gross_usd":0,
    "reason":"no-chains", "median_uncut":null, "median_n":0, "avg_call_usd":null,
    "session_usd":0, "calls":0

`counter.h:63 MIN_HISTORY=3`: ölçülmüş üç zincirden azı varsa **hiçbir rakam
basılmaz**, `null` basılır. Bu bir hata değil, kapının kendi dürüstlük kuralı.

---

## 3. Kabul betiği — 23 yeşil, 3 kırmızı. **Kapanan kırmızı: 0.**

    bash reports/R7/accept.sh      # rc=1, "R7 acceptance: 23 green, 3 red"

Bu turda hiçbir kırmızı kapanmadı ve **kapanması da beklenmiyordu**: `accept.sh`
6e/7b'yi `reports/R7/ab_run.jsonl`'den okur, o dosya **önceki** (tur 16, geçersiz
ilan edilmiş) koşunun ürünüdür ve bu tur ajan koşmadı. Düzenleme **sonraki**
koşuyu değiştirir, bu turun sayısını değil. Turun çıktısı bir yeşil değil, bir
sebep listesidir:

### 6e ve 7b — sebep BAĞLAMA DEĞİL. İki ayrı duvar var.

**Duvar 1 — kablo hiç yok.** `accept.sh` GOAL 6e, B kolu satırlarında
`estimated_saved` alanını arıyor. `ab_run.sh` bu alanı **hiç yazmıyor**
(`grep -c estimated_saved reports/R7/ab_run.sh` → **0**). Yani native gate
mükemmel bağlansaydı ve COUNTER gerçek bir rakam üretseydi bile, o rakam
JSONL'e **taşınmıyor**. 6e kırmızı kalır, 7b (6e'nin sapmasını okur) onunla
birlikte kırmızı kalır.

**Duvar 2 — rakam üretilemiyor.** Yukarıdaki ölçüm: tek oturumluk bir görevde
`chains_cut=0`, `median_n=0`, `MIN_HISTORY=3`. Sayaç formülü
`saved_usd = median(uncut_chain_lengths) * chains_cut * avg_call_usd`
(`counter.h:19`); üç ölçülmüş zincir birikmeden `null` döner. Her görev tek
oturum olduğu sürece bu duvar durur — kablo çekilse bile `null` taşınır.

**Sonuç, tek cümle:** 6e/7b'yi kapatan şey doğru ikiliyi bağlamak değildir;
(a) COUNTER'ın `saved_usd`'sini ledger'dan okuyup JSONL'e `estimated_saved`
olarak yazan kablo, ve (b) sayacın rakam üretebileceği bir koşu şekli gerekir.
Reçete PARKED'e yazıldı.

### 2b — bu makinede ölçüm ALINMADI, alınamaz

Operatör emri gereği latans ölçümü **alınmadı**. `accept.sh` kendi ölçümünü
aldı (8148,9 µs) ve **o sayı delil değildir**: ölçüm anındaki makine durumu

    load average: 7,51  7,77  8,84      (yük ortalaması, 3 pencere)
    %99,2  Python (homebrew 3.14)
    %24,2  WindowServer
    %18,9  WebKit WebContent
     %8,1  claude

Yani tek çekirdeği doyuran bir Python süreci + grafik yığını koşarken alınmış
bir medyan. Tur 16'nın kaydı da aynı yöndeydi (1385,2 µs → 2443,8 µs, load 6,24).
**Yük altında alınan hiçbir latans sayısı bu tavana karşı okunmaz.** 2b'nin
kırmızısı bu turda "gate yavaş" demiyor, "ölçüm yapılmadı" diyor.

---

## 4. CHALLENGE — sertleştirilen kabul, koşuyu neredeyse koşulamaz yapıyor

Operatör "bağlama kabulü = en az bir SIGNAL veya INJECT satırı" dedi ve
**aynen uygulandı**. Ama uygulamadan önce taban oran ölçüldü, ve sayı ağır:

    ~/.rabadon/spool/*.jsonl, `sess` alanı olan oturumlar:
      toplam oturum          186
      >=1 SIGNAL veya INJECT   8   (%4,3)
      >=1 INJECT               3   (%1,6)
      >=1 COUNTER             52   (%28,0)

Yani gerçek dogfooding'de kapı, oturumların **%95,7'sinde hiç sinyal
üretmiyor** — çünkü o oturumlarda yakalanacak bir şey yok. Bu sart aynen
kalırsa iki sonuç doğar:

1. **B koşularının büyük çoğunluğu atılır**, N zaten 4'ken sıfıra yaklaşır ve
   her atılan koşu ÖDENMİŞ paradır.
2. Daha kötüsü: kalan küme **"rabadon'un konuştuğu oturumlar"a doğru yanlıdır**.
   B kolu yalnız kapının müdahale ettiği görevlerden oluşursa, B'nin A'dan iyi
   çıkması ölçümün kendi seçiminin sonucudur — turun cevaplamak istediği sorunun
   tam da yanıtını varsayar.

**Bu yüzden şart uygulandı ama YALNIZ BAŞINA bırakılmadı.** Bağlamanın gerçek
kanıtı, sinyalden bağımsız iki deterministik satıra bağlandı:

- **native yazar imzası** (`run:"ng-…"`): `gate.mjs` bunu yazamaz, yani "doğru
  ikili bağlı mı" sorusu satırdan cevaplanır — tur 16'nın kaçırdığı tam bu soru.
- **COUNTER**: yalnız `SessionEnd`/`Stop`'ta üretilir, yani olay kümesinin
  **son** halkasının da bağlı olduğunun kanıtı. Eski bağlamada imkânsızdı.

İkisi de her oturumda deterministik (§2'de ölçüldü), yani seçicilik üretmezler.
Ayrıca `ledger_signal_inject` alanı JSONL'e **yazılıyor**, ki raporlama bu
seçiciliği gizleyemesin.

**OPERATÖR KARARI GEREKİYOR, paralı koşudan ÖNCE:** SIGNAL/INJECT şartı
(a) aynen kalsın mı, (b) geçerlilik şartı olmaktan çıkıp yalnız kayıtlı bir alan
mı olsun, yoksa (c) "native + COUNTER" bağlama kanıtı yeterli sayılıp
SIGNAL/INJECT ayrı bir sonuç sütunu mu olsun? Yapan oturum bunu kendi başına
gevşetmez — kabul gevşetmek bu ürünün reddetmek için var olduğu hamledir.

---

## 5. Kanıt komutları

    bash -n reports/R7/ab_run.sh                     # sozdizimi
    bash reports/R7/accept.sh                        # 23 yesil, 3 kirmizi (rc=1)
    grep -c estimated_saved reports/R7/ab_run.sh     # 0  <-- 6e'nin kablosu yok
    grep -n 'MIN_HISTORY' native/counter.h           # 63: = 3
    grep -n 'SessionEnd\|"Stop"' native/gate.cpp     # 4008, 4015
    sed -n '2733,2734p' native/gate.cpp              # tanınan alti olay
