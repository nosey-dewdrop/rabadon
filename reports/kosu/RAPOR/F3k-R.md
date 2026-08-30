# F3k-R — hakem tutanağı (2026-08-30)

Hüküm tek satır hâlinde `reports/kosu/KAPI.md`'nin sonundadır: **`F3k: GEÇTİ`**.
Bu dosya ayrıntıdır, şef okumaz. Faz tabanı `F3k-oncesi` = `07d10e9`, HEAD = `074b72b`.

---

## 0. SAHİBİNİN MAKİNESİ — dört ölçüm, hepsi aynı

`~/.claude/settings.json` sha256, ölçüm sırasıyla:

| ne zaman | sha256 |
|---|---|
| oturum başı | `adcb41a93f858d6befca4086c42c50d271a8906513acd1fa29c68ffb6dee5681` |
| kendi self-heal probumdan sonra | aynı |
| mutasyondan (bozuk `refresh.mjs`) sonra | aynı |
| `make test`'ten sonra | aynı |

- `~/.rabadon/mode` = `watch` · `~/.rabadon/enabled` **YOK** (30 Ağu 03:22, sahibinin kalemi) — **dokunmadım**.
- `git worktree list` → **tek satır**. **Worktree AÇMADIM** (hasar 3'ün kök sebebi).
- `.rabadon/guard.json`'a dokunmadım · `rabadon off` kullanmadım · CHALLENGE-3 bileşik-komut deliğini kullanmadım.
- Kendi kum havuzumu `~/.rbjudge-work` altında kurdum ve **sildim**; `/Users/Shared` ve
  `/Library/Caches` altına koyduğum iki geçici kurulum probun kendi içinde `rm -rf` edildi.
  Artık klasör bırakmadım.
- Sahibinin ölü `/tmp/rabadon-501.sock`'una **dokunmadım**.

---

## 1. AÇIK SORU 1 — `/private/tmp` deliği: **AİLE olarak kapandı, kartın iddiasından daha geniş**

### (i) Kendi bulduğum, kartın listesinde OLMAYAN iki kalıcı-olmayan kök

Kartın üç kökünü (`/private/tmp`, `/private/var/tmp`, süidin `$HOME` altında kurduğu kök)
**kullanmadım**. Kendi taramam:

    find / -maxdepth 3 -type d -perm -1002
      /Library/Caches
      /private/tmp
      /Users/Shared
      /Users/Shared/Parallels
      /private/var/.Parallels_swap
      /private/var/tmp

Seçtiğim ikisi kartta hiç geçmiyor: **`/Users/Shared`** ve **`/Library/Caches`**.

Prob (kendi yazdığım, `native/selfheal_path_test.sh`'ten sayı kopyalamadan): her kök için
ürünün `native/rabadon-gate` + `native/rabadon-drift` + `hooks/{refresh,install}.mjs`
kopyasını o kökün altına kurdum; sahte bir `$HOME` yarattım ve içindeki
`.claude/settings.json`'a **var olmayan** bir gate kaydettim
(`/nonexistent/gone/rabadon-gate`) — böylece self-heal repoint'i **gerçekten denemek
zorunda**. Tek `SessionStart`, taze `RABADON_DIR` (6 saatlik damga ölçümü susturmasın).

| kök | ekrana basılan | kayıtlı komut sonrası |
|---|---|---|
| `/Users/Shared/rbjudge-shared/native/rabadon-gate` | `rabadon: … I will NOT repoint it to /Users/Shared/… — it is under /Users/Shared, a world-writable scratch directory that the system sweeps.` | `/nonexistent/gone/rabadon-gate` — **DEĞİŞMEDİ** |
| `/Library/Caches/rbjudge-libcache/native/rabadon-gate` | aynı biçim, `/Library/Caches` adıyla | `/nonexistent/gone/rabadon-gate` — **DEĞİŞMEDİ** |

Sahibinin `~/.claude/settings.json`'ı probun öncesinde ve sonrasında **bayt bayt aynı**.
Ret **sesli** (Promise 1) ve **hiçbir dosya yazılmadı**.

**Sonuç:** ölçüt dizge değil, dosya sisteminin kendi işareti. Kartın listesinde geçmeyen
iki kök de yakalandı → **şekil değil, aile.**

### (iii) Aşırı-uyum / yanlış negatif kontrolü — kalıcı kopya KABUL edilmeli

Aynı probun üçüncü kolu: kalıcı bir yola (`$HOME` altında, 1777 DEĞİL, gerçek `.git`
DİZİNİ ile) kurulmuş kopyadan aynı sahte HOME'a tetikledim.

    rabadon: this install was older than the binary — subscribed to PostToolUseFailure;
    repointed rabadon-gate from /nonexistent/gone/rabadon-gate
    to /Users/damummyphus/.rbjudge-work/durable/native/rabadon-gate in …/settings.json

**KABUL EDİLDİ**, ve repoint OLD→NEW adresiyle ilan edildi. Yani kapı "her şeyi reddet"
değil; §4.3'ün öldürücü yanlış pozitifi bu kolda **yok**.

### (ii) Mutasyon — korumayı boz, kırmızı gör, geri al

Bozduğum tek satır `hooks/refresh.mjs:127` (yapısal kol):

    -    if (st.isDirectory() && (st.mode & 0o1000) && (st.mode & 0o0002))
    +    if (false && st.isDirectory() && (st.mode & 0o1000) && (st.mode & 0o0002))

| adım | `native/selfheal_path_test.sh` |
|---|---|
| önce | **31 passed, 0 failed · EXIT=0** |
| mutasyon | **25 passed, 6 failed · EXIT=1** |
| geri al | **31 passed, 0 failed · EXIT=0**, `git diff hooks/refresh.mjs` **0 satır** |

Kartın 31/0 → 25/6 → 31/0 iddiası **birebir tuttu**. Kırmızı olabilen kapıdır.

### Ölçüt commit'i koddan önce ve ayrı

`2935489` (ölçüt) → `17e503c` (kod). Ölçüt commit'indeki `hooks/refresh.mjs`
`F3k-oncesi` ile aynı; süit orada kırmızı. **Boş yeşil tur değil.**

---

## 2. AÇIK SORU 2 — daemon: iki uyarı da DOĞRU, ve kartın kendi aleti kartın sonucunu daraltıyor

### (a) "Kartın dayandığı mekanizma artık yok" — **DOĞRULANDI, kaynaktan**

`native/gate.cpp:551-591`, `rb_day_str_at`: `gmtime_r` **çağrılmıyor**. Howard Hinnant
days-to-civil tamsayı takvimi (`z = epochDay + 719468; era = …`) + güne anahtarlı statik
önbellek. `:538`'deki "rabadon-gated forks a worker per request, so every request paid the
cold price again" cümlesi o önbelleğin **neden var olduğunu** anlatan geçmiş zamandır.
269-483 µs'lik soğuk timezone yükü sevk edilen koddan **zaten kalkmış**.
Gecikmenin sebebi timezone **DEĞİL** — kartın teşhisi doğru.
(`iso8601_now()` hâlâ `gmtime_r` çağırıyor ama o günlük dizge yolunda değil.)

### (b) Sıfır-fork aletiyle IPC'nin daha ucuz olması — **DOĞRULANDI** (`kanit/f3k/k2-floor.out`)

    mean A (shipped, judges in-process) = 3494.1 us
    mean FLOOR (0 forks, 0 judging)     = 1450.7 us
    FLOOR - A = -2043.4 us   sign: 0/3 pairs slower

Soket gidiş-dönüşü sorun değil; ceza **2 fork + işçinin yargıyı baştan yapması**.

### ⚠ KARTIN KENDİ ALETİ, KARTIN GENEL SONUCUNU **DESTEKLEMİYOR** — hakemin bulgusu

`k2-floor.out`'un okuma talimatı şöyle yazıyor:

    READ: FLOOR is the least any daemon design can cost… If FLOOR > A, no
    fork-count optimisation can win.

**Ama ölçülen FLOOR (1450,7) < A (3494,1).** Yani koşul **TUTMUYOR**: sevk edilen yolun
altında **2043 µs ölçülmüş boşluk var**. Bu alet daemon'un kazanamayacağını
kanıtlamıyor — tam tersine, yargıyı önbellekleyen ve fork etmeyen bir daemon'un
kazanabileceği bir alan olduğunu gösteriyor. Kart bunu genel sonuç olarak kullanmıyor,
kullanmadığı için de bir hata yapmış değil; ama `2b` kararının dayanağı budur (§3 aşağıda).

### ⚠ Türetilmiş cümle doğru etiketlenmiş mi? — **EVET**

"Bir fork kaldırılsa da ~1000-1900 µs yavaş kalır" ve "fork başına ~1300-1700 µs" cümleleri
`k2-hukum.out`'ta açıkça **"TÜRETİLMİŞ AYRIŞTIRMA (⚠ DOĞRULANMADI — gürültülü ortalamalar
üstünde aritmetik, doğrudan ölçüm değil)"** başlığı altında, ve `F3k.md`'nin
"ÖLÇEMEDİKLERİM / DOĞRULANMADI" bölümünün 1. kaleminde tekrar. **Etiketleme doğru,
CLAUDE.md 8 tutuyor.** Hükmüm o cümleye dayanmıyor.

---

## 3. `2b` ŞIKKI — **(B) SEÇİLDİ**

Tam gerekçe `KARARLAR.md` · 2026-08-30 · F3k. Özet:

- **(A) reddedildi, iki ölçülmüş sebeple.** (1) F3j'nin "sevk edilen yol 766,3 µs" sayısı
  **benim ölçümüm değil**; bugün kendi koşturduğum `accept.sh` daemon açıkken
  **1685,4 µs** okudu, sevk edilen kolu ben **hiç ölçmedim**. Mühürlü kabul dosyasını
  ölçmediğim bir sayı için yeniden yazmak CLAUDE.md 1'in ihlalidir.
  (2) `k2-floor.out` daemon hedefinin **ulaşılamaz değil, ulaşılmamış** olduğunu gösteriyor
  (§2). Ulaşılabilir ama ulaşılmamış bir hedefi ölçütün **konusunu değiştirerek** yeşile
  çevirmek, eşiğe dokunulmasa bile özde **§3.8/4 gevşetmesidir**.
- **(B) uygulandı.** `2b` bugünkü lafzıyla kalır, kırmızı kalır, **kalıcı §1 hedef ihlali**
  olarak yayımlanır. Tavan **1000 µs gevşetilmedi**. `reports/R7/accept.sh`'e
  **dokunmadım**, diff'te **yok**.
- `rabadon-gated` **sevk edilmiyor** (bugün doğruladım: `~/.claude/settings.json`'da
  `rabadon-gated` **0 kez**, koşan süreç yok) ve **sevk EDİLMEYECEK**; istek başına
  iki-fork modeli ölçülmüş açık kusurdur (+2645,3 / +3365,9 µs, 7 çiftin 7'si, bant |439|).

---

## 4. AÇIK SORU 3 — sayaç ve selefinin hatası

`DURUM.md`'nin üç komutu, tek log, tek koşu:

| ölçü | değer |
|---|---|
| `make test` exit | **0** |
| native GENİŞ `^[[:space:]]*ok\b` | **4096** |
| native `PASS (N checks)` toplamı | **633** |
| `npm test` | **64 pass / 0 fail** |
| **TOPLAM** | **4793 yeşil / 0 kırmızı** |
| taban (F3j) | 4783 → **+10** |
| sıfırdan büyük `N failed` | **0** (grep boş) |
| sessiz `skip` / `xfail` | **0** (bulunan `skip` satırları `silent skip` süidinin kendi iddiaları) |

**Selefinin 4034'ü:** aynı logda **DAR** `grep -c '^  ok'` bugün **4044**, GENİŞ **4096**,
fark **tam 52**. Kartın atfı (52 = `ok`'u sütun 0'dan basan iki süit, 38 + 14) bu farkla
birebir uyuyor; taban ile bugün arasındaki +10 her iki regexte de aynı (4034→4044,
4086→4096), yani ortam/sıra etkisi yok. **Kayıp iddia yok. Kart haklı, selefi emekli
regexi kullanmış.** Emekli sayı silinmiyor; `DURUM.md`'de gerekçesiyle duruyor.

**ÖLÇEMEDİM:** kartın "süit 121" sayısı. `DURUM.md`'nin üç komutunda süit sayan bir komut
yok; kendi kalıbım (`^ad: N passed, M failed`) **53** adlı süit buluyor, `ctest` özet
satırı bu logda yok. 121'i **doğrulamadım da yalanlamadım da**.

---

## 5. AÇIK SORU 4 — §3.8 / §3.12 denetimi

`git diff F3k-oncesi..HEAD`:

- **Silinen dosya: 0** (`--diff-filter=D` boş).
- **Ürün diff'i yalnız `hooks/refresh.mjs`** (+80/-16). Yeni süit `native/selfheal_path_test.sh`.
  Gerisi `reports/kosu/` altında kart + kanıt.
- Mühürlü set diff'te **YOK**: `reports/R7/accept.sh`, `reports/R7/ON-KAYIT.md`,
  `docs/claims.tsv`, `.rabadon/guard.json`. `bin/rabadon.mjs` (O3) da **YOK — donuk**.
- **Hiçbir süidin iddia sayısı düşmedi.** Taban logu (`kanit/f3k/baseline-make-test.out`)
  ile bugünkü logu ad ad `join`'ledim: **53 adlı süit her iki tarafta da var**,
  küçülen **0**, kaybolan **0**. Değişen tek süit `selfheal_path` (yeni, 31).
- **Ölçüt commit'i koddan ÖNCE ve AYRI:** `2935489` < `17e503c`. ✔
- **§3.12 tahmini kart kesilmeden önce commit'li:** `3ee5023` fazın **ilk** commit'i,
  3 kart / 240 dk. Gerçekleşen ~40 dk, iki katı (480) aşılmadı, hakeme durma gerekmedi. ✔
- **`bash reports/R7/accept.sh` → EXIT=1, 23 yeşil / 3 kırmızı, `{2b, 6e, 7b}`.**
  **BÜYÜMEDİ.** Kırmızıların bugünkü lafzı:
  - `2b the gate's median is 1685.4 us with the daemon up, ceiling is 1000 us`
  - `6e counter validation impossible: no 'estimated_saved' total on arm B…`
  - `7b falsification 2 is UNCHECKABLE — no deviation could be computed`
- **Kâtip commit'i:** fazın son commit'i `074b72b` **yalnız `reports/` altına yazıyor**
  (kart + 3 kanıt dosyası), ürün kodu ya da test kodu içermiyor. F1e-C üçlüsünün
  koştuğu nihai ikili ile sevk edilen ağaç arasında **kod farkı yok**; bu yüzden son
  commit'in kâtip commit'i olması ölçümü geçersizleştirmiyor. Yine de **not düşüyorum:**
  lafzen "kâtip commit'i sonuncu olmamalı" kuralı bu fazda **sağlanmamıştır**;
  zararsız olduğunu **ölçtüm** (diff yalnız `reports/`), o yüzden bloklamıyorum.

---

## 6. §4.3 — YANLIŞ POZİTİF ADAYI: **1**

Kapı bu oturumda beni **hiç kesmedi**; mod `watch` olduğu için bu, kapının enforce altında
çalıştığının kanıtı **DEĞİLDİR** ve öyle yazmıyorum.

Ama self-heal kolunda bir aday **var** ve kart onu görmemiş (çünkü kart yalnız gerçekten
süpürülen kökleri denemiş): `/Users/Shared` ve `/Library/Caches` 1777'dir ama
**sistem onları süpürmez** — `/Users/Shared` macOS'un standart çok-kullanıcılı kurulum
yeridir. Ürün ikisini de reddederken ekrana *"a world-writable scratch directory that the
system sweeps"* basıyor; **ret savunulabilir, gerekçe cümlesi yanlış.** Ayrıntı ve
devredilen kalem: `KARARLAR.md` · 2026-08-30 · F3k (ikinci satır).

---

## 7. KAPSAM DIŞI — dokunmadım

`(c)` negatif kontrolü (F6'nın aleti; **F4 (c) ölçülmeden açılmaz**) · yasa ailesinin 21
açık şekli (eşitlik kilidi 21=21) · fren (`~/.rabadon/mode`, `enabled`).

**Sıradaki faz `F3l`, ilk bloklayan kart `(c)` negatif kontrolü, F6'nın aletiyle.**
`(c)` dokuz fazdır erteleniyor; §0 anlamında oyalamadır ve F3l onu ölçmeden kapanmaz.
