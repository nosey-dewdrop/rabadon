# TEŞHİS — B kolu rabadon'la KONUŞMUYOR

Tarih: 2026-08-24 (tur 16). **Hiçbir ajan koşulmadı, para harcanmadı.**
Konu: `reports/R7/DENEMELER.md` PARKED maddesi — "ölçülen B kolu, ajana hiç
konuşmayan bir rabadon olabilir. ÖLÇÜLMEDİ."

**ÖLÇÜLDÜ. Şüphe DOĞRU, ve yazıldığından daha ağır.** İki bağımsız sebep var
ve her biri tek başına yeterli.

---

## 0. Ölçüm — geçerli B koşularının ledger'ı

Ortak spool'da A/B pipe etiketli her satır, **yazan ikiliye göre** ayrıldı.
İki yazar, satırdan ayırt edilebiliyor:

| yazar | `run` biçimi | ek alanlar |
|---|---|---|
| `native/rabadon-gate` | `ng-<ms>-<pid>` (gate.cpp:2738) | `sess`, `call` |
| `hooks/gate.mjs` | `mt7b…` (base36) | `sess` YOK, `call` YOK |

Sonuç (tüm A/B pipe'ları, `~/.rabadon/spool/*.jsonl`):

    native          CONTRACT     5
    native          COUNTER      4
    native          INJECT       1
    native          RUN_DONE     4
    native          RUN_START   10
    native          SIGNAL       1
    native          STEP_OK     74
    native          STEP_START  77
    node-gate.mjs   STEP_START  51      <-- BAŞKA HİÇBİR ŞEY YOK

**`hooks/gate.mjs` 51 satır yazdı ve 51'i de `STEP_START`.** Sıfır SIGNAL,
sıfır INJECT, sıfır COUNTER, sıfır RUN_DONE, sıfır STEP_OK.

Pipe pipe, zaman damgasıyla:

    autograd__B    native  14:08–14:10  {CONTRACT,RUN_START,STEP_START,STEP_OK,SIGNAL:1,INJECT:1,COUNTER,RUN_DONE}
    autograd__B    node    14:17–14:26  {STEP_START: 31}
    oauthlib__B    native  14:12–14:14  {CONTRACT,RUN_START,STEP_START,STEP_OK,COUNTER,RUN_DONE}
    oauthlib__B    node    14:27–14:28  {STEP_START: 6}
    pydicom__B     node    14:30–14:31  {STEP_START: 5}
    feedparser__B  node    15:00–15:01  {STEP_START: 9}

**Tek INJECT'in kimliği.** Veri kümesindeki tek SIGNAL ve tek INJECT,
autograd__B'de 14:08–14:10 penceresinde, `run:"ng-…"` + `sess` + `call` alanlı
satırlar — yani **native gate**'in, **tur 14'ün GEÇERSİZ ilan edilmiş**
penceresinde yazdığı satırlar. O pencerede operatörün global
`~/.claude/settings.json`'ı `…/rabadon/native/rabadon-gate`'i beş olaya birden
bağlıydı (aşağıda). Tur 15 `--setting-sources local` ekleyip o sızıntıyı
kapattı — ve INJECT üreten TEK yolu da onunla birlikte kapattı.

Yani: **INJECT hiçbir zaman geçerli bir B koşusunda gerçekleşmedi.** Bir kez
görüldü, o da harness'in kendi kurallarıyla çöpe attığı bir koşuda.

---

## 1. SEBEP A — B kolu YANLIŞ İKİLİYİ bağlıyor (asıl sebep)

`ab_run.sh:25` → `GATE="$ROOT/hooks/gate.mjs"`, ve `bagla_hook` (ab_run.sh:249)
şunu yazıyor:

    "command": "sh -c 'timeout 2 node .../hooks/gate.mjs 2>/dev/null; exit 0'"

Birikim motoru **`hooks/gate.mjs` içinde YOKTUR**. Kaynak taraması:

| şey | native/gate.cpp | hooks/gate.mjs |
|---|---|---|
| `SIGNAL` emit (tier 0 `rbsig::detect`) | 3166 | **yok** |
| `SIGNAL` emit (tier 1 `rbsem::detect`) | 3196 | **yok** |
| `queue_injection(...)` | 3175, 3216 | **yok** |
| `INJECT` emit | 4724 | **yok** |
| `additionalContext` / `hookSpecificOutput` | 4707 | **0 eşleşme** |
| `COUNTER` emit | 4001 | **yok** |

`hooks/gate.mjs`'nin ürettiği olayların TAMAMI: CHECK_FAIL, STOP, REPAIR_*,
STEP_START, STEP_OK, LLM_CALL, RUN_START, RUN_DONE. Enjeksiyon kanalı yok.

**Bu bir yapılandırma hatası değil, ikili seçimi hatası.** `hooks/install.mjs:111`
dosyanın kendi yorumu şunu diyor:

    // legacy JS gate path — still recognized (and replaced) when found in settings
    export const GATE_PATH = path.join(HERE, 'gate.mjs');

Yani `gate.mjs` **ESKİ (legacy) kapı**dır; gerçek kurulum onu bulduğunda
SİLİP native ile DEĞİŞTİRİR (`RABADON_CMD_RE`, install.mjs:117, `stripOurs`).
Gerçek `rabadon init`'in kurduğu şey `GATE_BIN = native/rabadon-gate`'tir.

**Doğrudan ölçüm (temiz kum havuzu, ajan yok):** `hooks/gate.mjs`'ye dört olay
tek tek verildi, stdout okundu.

    PreToolUse     rc=0  stdout_bytes=0
    PostToolUse    rc=0  stdout_bytes=0
    Stop           rc=0  stdout_bytes=0
    SessionEnd     rc=0  stdout_bytes=0
    spool: {STEP_START:1, STEP_OK:1, RUN_DONE:1}      COUNTER yok, INJECT yok

**Dört olayın hiçbirinde tek bayt stdout yok.** Claude Code hook'u ajanla
STDOUT üzerinden konuşur. `gate.mjs` hiçbir olayda konuşmuyor — hiç
konuşamıyor, çünkü kaynağında o cümleyi yazan satır yok.

**ELENEN ALTERNATİF HİPOTEZ — `timeout 2` kapıyı öldürüyor mu? HAYIR.**
5 ölçüm, aynı kum havuzunda: `real 0,34 / 0,14 / 0,14 / 0,14 / 0,14` sn,
hepsi `rc=0`, hepsi ledger'a yazdı. 140 ms, 2 s tavanının çok altında.
Zaman aşımı bu olayın sebebi değil.

---

## 2. SEBEP B — YALNIZ `PreToolUse` kayıtlı (ikinci, bağımsız sebep)

`bagla_hook` sadece `PreToolUse` yazıyor. Native gate bağlansaydı bile bu
konfigürasyonla dört olay yine gelmezdi, çünkü hepsi başka olaylara asılı:

- **SIGNAL** — `rbsig::detect(ms.moves)` bir hareket TAMAMLANDIĞINDA konuşur;
  hareketi kapatan dal `gate.cpp:2889`, `if (hook == "PostToolUse" …)`.
  PostToolUse yoksa hiçbir hareket kapanmaz, hiçbir sinyal doğmaz.
- **INJECT** — `gate.cpp:4697`, şartı `!ss.injPending.empty()`. `injPending`
  yalnız `queue_injection` ile dolar, o da yalnız yukarıdaki SIGNAL'lerden
  çağrılır. Sinyal yoksa kuyruk boş, teslimat satırı hiç çalışmaz.
  **Zincir: PostToolUse → SIGNAL → queue_injection → (sonraki) PreToolUse →
  INJECT. Zincirin ilk halkası kayıtlı değil.**
- **COUNTER** — `gate.cpp:4001`, `SessionEnd`/`Stop` kapanışında (4015).
- **RUN_DONE** — `gate.cpp:4093`, `Stop` dalında.

`gate.mjs` de aynı topolojiyi taşıyor: STEP_OK PostToolUse dalında (353+),
RUN_DONE Stop dalında (613).

**Gerçek ürünün kurduğu şeyle karşılaştırma** (`hooks/install.mjs:169-175`):

| | gerçek `rabadon init` | R7 B kolu |
|---|---|---|
| ikili | `native/rabadon-gate` | `hooks/gate.mjs` (legacy) |
| SessionStart | ✅ | ❌ |
| UserPromptSubmit | ✅ | ❌ |
| PreToolUse | ✅ (timeout 960 sn) | ✅ (timeout 2 sn) |
| PostToolUse | ✅ (timeout 120 sn) | ❌ |
| Stop | ✅ (+ rabadon-drift) | ❌ |

B kolu, ürünün beş olaylı kurulumunun **bir olayını, yanlış ikiliyle** kurdu.

---

## 3. NEDEN GÖRÜLMEDİ — tur 14'ün düzeltmesi teşhisi de sildi

Tur 14'te A kolu kirliydi: operatörün global settings'i native gate'i her
`claude` oturumuna bağlıyordu (ölçüldü: A kollarında 36 ve 40 ledger satırı).
O global bağlama, B kolunda da **native gate'i yan yolla çalıştırıyordu** —
autograd__B'nin SIGNAL+INJECT'i buradan geldi.

Tur 15 `--setting-sources local` ekledi. Bu **doğru** düzeltmeydi (kontrol
kolunun saflığı buna bağlı). Ama aynı hamle, B kolunda enjeksiyonu üreten tek
kaynağı da kesti — ve geriye harness'in kendi bağladığı `gate.mjs` kaldı,
o da hiçbir zaman konuşmuyordu. Sonuç: iki kol arasındaki tek fark
"ledger'a STEP_START yazan sessiz bir gözlemci" oldu.

---

## 4. SONUÇ — bu hangi sayıyı geçersiz kılıyor

- **GOAL 7a (falsification 1) OKUNAMAZ.** "Arm B ne düzeltme oranını ne net
  token'ı iyileştirdi" cümlesi enjeksiyon tezi hakkında bir hüküm DEĞİLDİR;
  enjeksiyon kolun içinde hiç olmadı. 2-2 bölünme, "kaydeden ama müdahale
  etmeyen" bir kapının beklenen sonucudur.
- **GOAL 6b/6c/6e (token, müdahale, sayaç doğrulaması) OKUNAMAZ.** Token farkı
  bir birikim motorunun etkisini değil, PreToolUse başına ~140 ms'lik bir
  node sürecinin gürültüsünü ölçüyor.
- **GOAL 6d (false positive) YAPISAL SIFIR.** `ledger_would_refuse` dört B
  satırının dördünde de 0; `gate.mjs` `wouldRefuse` alanını hiç yazmıyor.
  Yeşil, ama boş bir yeşil — ayrım gücü sıfır.
- **GOAL 5b (iki kol da ham kayıtta var) GERÇEK.** Kayıt var; kaydın B'si
  rabadon'un tamamı değil, sekizde biri.
- `ab_run.sh`'in kendi "BAĞLAMA KABULÜ" (`ledyeni > 0`) bu hatayı **yakalamadı**,
  çünkü kabul "ledger'a yeni satır düştü mü" diye soruyor. STEP_START bu şartı
  karşılıyor. Kabul, kapının ajanla KONUŞTUĞUNU sormuyor.

## 4b. KABUL BETİĞİNİN KIRMIZILARIYLA EŞLEME

`bash reports/R7/accept.sh` (tur 16, bu turda koşuldu): **23 yeşil, 3 kırmızı.**

| kırmızı | teşhis açıklıyor mu? |
|---|---|
| **6e** — `estimated_saved` yok, sayaç doğrulanamıyor | **EVET, iki kat.** (i) Alanı besleyecek olay COUNTER'dır; `gate.mjs` COUNTER'ı hiç yazmıyor ve native'in COUNTER'ı `SessionEnd`/`Stop`'ta (gate.cpp:4001,4015) — ikisi de B kolunda kayıtlı değil. (ii) COUNTER **gelse bile** `saved_usd = median(uncut) * chains_cut * avg_call_usd − …` ve `chains_cut` yalnız INJECT/STOP olaylarından sayılıyor (gate.cpp:2027, counter.h:23). B'de sıfır INJECT var → `chains_cut = 0` → tasarruf yapısal olarak 0. |
| **7b** — çürütme 2 kontrol edilemiyor | **EVET**, doğrudan 6e'ye asılı. |
| **2b** — kapı medyanı 2443,8 µs, tavan 1000 µs | **HAYIR.** Bu R7'nin hız yarısı, B koluyla ilgisi yok. Ayrı bir açık cephe. |

**2b HAKKINDA DÜRÜST NOT — sayı GERİLEDİ ve karşılaştırılabilir değil.**
Önceki `accept.out` 1385,2 µs yazıyordu; bu tur 2443,8 µs. Makine ölçüm
sırasında YÜKLÜYDÜ: `load average 6,24`, Chrome GPU helper %522 CPU, başka bir
projenin `surface-pattern` süreci %91,7. İki sayı aynı koşulda alınmadı, aralarındaki
fark bir regresyon delili DEĞİLDİR. Kırmızı olduğu her iki okumada da doğru
(ikisi de 1000 µs üstünde), ama **2b bu makinede güvenilir ölçülemiyor** —
yük temizlenmeden alınacak her sayı gürültüdür. Aynı şey 2c'nin 5,78 % → 7,22 %
hareketi için de geçerli (yeşil, ama gürültülü).

**YEŞİL AMA GEÇERSİZ — 7a.** Bu tur 7a YEŞİL geçti ("arm B improves on net
tokens": A 35 620 / B 33 221). **Bu yeşil delil değildir.** Bölüm 4'e göre B
kolunda enjeksiyon hiç olmadı; token farkı bir birikim motorunun etkisi değil.
Düzeltme oranı zaten aynı (%75 / %75) ve görev bazında yön 2-2 bölünmüş.
Kabul betiği 7a'yı yeşile çeviren şartı ("fix rate VEYA token iyileşti")
sağlıyor, ama sağladığı şey tezle ilgili bir hüküm değil. **7a bir yeşil olarak
raporlanmamalıdır.**

**TUR 14 GÜNLÜĞÜNE DÜZELTME.** `PROJECT.md`'nin tur 14 kaydı 2. maddede "Arm B
was muted… fixed" diyor. Ölçüm bunu daraltıyor: `>/dev/null` kaldırılınca
ledger yazımı düzeldi, ama **enjeksiyon kanalı düzelmedi** — `gate.mjs` dört
olayın hiçbirinde tek bayt stdout üretmiyor (bölüm 1). Susturma kaldırıldı,
konuşacak bir şey yoktu.

## 5. NE DEĞİŞMELİ (öneri, bu turda UYGULANMADI)

1. `ab_run.sh:25` → `GATE` native `rabadon-gate` olmalı; `gate.mjs` legacy'dir.
2. `bagla_hook` gerçek kurulumun beş olayını yazmalı (install.mjs:169-175),
   tercihen `hooks/install.mjs`'i çağırarak — kendi elle yazılmış kopyası
   ürünle sessizce ayrışıyor, bu turun kanıtı tam olarak bu.
3. B kolunun bağlama kabulü sertleşmeli: `ledger_new_lines > 0` yetmez. Şart
   ya ledger'da en az bir SIGNAL/INJECT/COUNTER olması, ya da B transcript'inde
   enjeksiyon metninin görünmesi olmalı. Bugünkü kabul boş bir kapıyı geçirir.
4. Bu üçü yapılmadan iki kollu koşu **tekrar koşulmamalı** — para harcanır,
   ölçülen şey yine rabadon olmaz.

## 6. DOĞRULANMAYAN / GÖREMEDİĞİM

- Native gate B koluna doğru bağlanınca INJECT'in GERÇEKTEN gelip gelmediği
  **doğrulanmadı**. Tek delil, tur 14'ün geçersiz autograd__B koşusundaki
  1 SIGNAL + 1 INJECT'tir — 4 instance'ta 1 kez. Yani doğru bağlamayla bile
  enjeksiyon oranı DÜŞÜK olabilir; bu ayrı bir risk, bu teşhis onu kapatmıyor.
- Enjeksiyon metninin ajanın transcript'ine gerçekten girip girmediği
  (`raw.stream.jsonl`'de arandı mı) bu turda **kontrol edilmedi**.
- `orkestra/src/tick.py` de aynı beş olaya global olarak bağlı; tur 14 ölçümlerine
  etkisi **incelenmedi**.
- Ölçümler tek makinede (darwin 24.2.0, arm64) alındı; temiz konteynerde
  **doğrulanmadı**.
