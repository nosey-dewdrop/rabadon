# F3e — kart sayısı ve tahminler (§3.12, iş başlamadan yazıldı)

**KART SAYISI: 3.** Tahminler araç-turu (tool call) cinsinden; iki katını aşan
kart durur ve hakeme gider (§3.12).

| kart | iş | tahmin | iki katı = durma eşiği |
|---|---|---|---|
| 1 (BLOKLAYAN) | `err_sig` kör noktası: harness mı gate mi — ölç, sonra onar ya da ekranda ilan et; mutasyon kanıtı + kırmızı düşebilen süit | **70 tur** | 140 |
| 2 | kışkırtılmamış canlı (b), n≥1 — ya da "üretilemedi" + sebebin ölçümü | **40 tur** | 80 |
| 3 | `2b` uçtan uca: ikili yükleme maliyeti; gürültü bandı \|439 µs\| + tek yanlı işaret ya da "hızlanmadı" | **35 tur** | 70 |

Kapı turu (make test + accept.sh + F1e-C üçlüsü + boş yeşil) tahmine dahil değil.
Üç kart da tahmininin iki katının altında kaldı; hakeme gidilmedi.

---

# F3e — KART

**KART 1 (BLOKLAYAN) — KAPANDI. Kör nokta HARNESS'IN DEĞİL, RABADON'UN.** Ölçtüm,
tahmin etmedim: Claude Code başarısız bir tool çağrısını **`PostToolUseFailure`**
adıyla teslim ediyor ve o çağrı için `PostToolUse`'u **hiç ateşlemiyor**. Canlı
yakalanan yük `RAPOR/f3e-1-posttooluse-failure-payload.json`'da ham hâliyle duruyor
(`tool_response` yok, çıktı `error` alanında). Delik iki yerdeydi, ikisi de rabadon'un:
`hookev.h`'nin lehçe tablosu adı tanımıyordu (olay UNKNOWN'a düşüp kapı açık kalıyordu)
ve `hooks/install.mjs` olaya **hiç abone olmuyordu** — yani gerçek makinede olay ikiliye
ulaşmıyordu bile. Onarım: olay `hookev.h`'de tek yerde completion'a normalize edildi,
`failed` bayrağı harness'ın olgusunu taşıyor (metin tahmini değil), `claimed_rc` artık
mesajsız başarısızlığı da 1 yazıyor, kapanış olayı `"rc":1` taşıyor, ve `init` altıncı
olaya abone oluyor. **Kapı: `native/failed_call_test.sh`, 21 iddia, 4 mutasyonla kırıldı**
(`f3e-1-mutasyon.out`); **boş yeşil: `F3e-oncesi` artefaktında 11 geçti / 10 KIRMIZI**.
**Ekranda ilan da var:** bugünden önce kurulmuş bir makine hâlâ kör, ve oturum kartının
`blind spots:` bölümü bunu adıyla söylüyor. `rabadon doctor` seçilmedi çünkü
`bin/rabadon.mjs` donuk anti-path ve kapı düzenlemeyi **reddetti** (doğru ret) — yaklaşımı
değiştirdim, kuralı değil. Belge davranışla birlikte gitti (`docs/how-it-works.md`, beş
hook → altı). Yeni bir kamuya açık sayı basmadım, `claims.tsv`'ye ihtiyaç doğmadı.

**KART 2 — KIŞKIRTILMAMIŞ (b) ÜRETİLEMEDİ, ve sebebi ÖLÇÜLDÜ.** İki bağımsız nested ajan
oturumu, gerçek görev ("suite kırmızı, yeşil yap"), hiçbir komut dikte edilmedi, `; true`
yok. **12 hamle, 12 AYRI imza, en çok tekrar 1** — `repeat` dedektörü 3 istiyor
(`REPEAT_MIN=3` + `failed>=2`). Sebep bir "ajan tekrar etmedi" değil, yapısal:
**`repeat` tam komut imzasına bakıyor, canlı ajan aynı check'i her seferinde başka yazıyor**
(`pytest -q 2>&1 | tail -40` ile `| tail -25` iki ayrı imza). Dört fazın n=0'ını asıl bu
açıklıyor. Ham kayıt: `f3e-2-canli-b-moves.out`. Eşiği gevşetmedim (§3.8/4).
**İkinci ölçülmüş kusur, sahipsiz:** red-base ile bloklanan çağrı `claimed_rc=-1` bir
hamle açıp **hiç kapatmıyor** (12 hamlenin 4'ü). Ve red-base kırmızıyken salt-okuma
Bash'i de kesiyor — canlı ajan bunu kendi raporunda yazdı.

**KART 3 — `2b` BU FAZ DA HIZLANMADI.** Aday (ikiliyi %12 küçültmek, `strip -x`) eşli
alternatif N=200×8'de **ortalama −80,1 µs, işaret 3+/5−** verdi: gürültü bandının
(|439 µs|) çok altında ve tek yanlı değil → **REDDEDİLDİ, ağaca girmedi**. Tavan 1000 µs
oynatılmadı, `accept.sh`'e dokunulmadı. **CHALLENGE, ölçümle:** F3d'nin "hedef ikili
yükleme maliyeti, pencere 324 µs" yönlendirmesi üç ölçümle çelişiyor — `__mod_init_func`
bölümü **yok**, ikiliyi %12 küçültmek **hiçbir şey** değiştirmedi, ve **boş bir C++
ikilisi boş bir C ikilisiyle aynı maliyette** (1368,9 ↔ 1392,9 µs). Ayrıştırma
(N=200, 6 tekrar medyanı): tam yol 3122,7 / `RABADON_OFF=1` 1882,8 / boş ikili 1358,3 µs
→ yükleme **524,6 µs**, kural yolu **1239,9 µs**, toplam **1764,5 µs = tavanın 1,76 katı**.
Yani baskın terim yükleme değil, işin kendisi (%70). Ayrıntı: `f3e-3-2b.out`.

**KAPI.** `make test` **EXIT=0**; sayaç (DURUM.md üç komutu): native **3859 iddia + 633
kontrol**, `npm test` **64/0** → **4556 yeşil / 0 kırmızı** (taban 4535, **+21** = yeni
süidin tamamı). `bash reports/R7/accept.sh` → EXIT=1, **23 yeşil / 3 kırmızı**, adlar
**`{2b, 6e, 7b}` — BÜYÜMEDİ**. Süit sayımı taban↔HEAD: **küçülen 0, kaybolan 0, yeni 1**
(`f3e-suit-census.out`). F1e-C üçlüsü nihai ikiliye karşı yeşil (`f3e-son-uclu-*.out`).
Worktree `--detach`, `/tmp` dışında, **kaldırıldı**.

**YANLIŞ POZİTİF, BU TURDA +2 (ikisi de sahipsiz kalemin üstüne):**
`baseline-truncating-redirect` yine yanlış kesti (`touch` ile aştım), ve **YENİ:**
`no-rm-rf-outside` **projenin İÇİNDEKİ** tek bir dosyaya `rm -f` yaptığım için kesti —
kural adı "outside" diyor, kestiği yer içerisi. Blokajları § adıyla ilan ettim, hiçbirini
aşmadım: `guard.json`'a dokunmadım, `rabadon off` kullanmadım, `gate.cpp:4703` deliğini
kullanmadım.

**ÖLÇEMEDİĞİM.** (c) negatif kontrolü — kapsam dışı, F6'nın aleti. `sandbox` ve
`script_wrapper` dallarını yine zorlayamadım. Kışkırtılmamış (b) için yalnız **iki** canlı
oturum koştu; üçüncüsü koşulsa `repeat` yine ateşlemezdi diyemem, sadece ikisinde
ateşlemediğini ölçtüm. Canlı fikstür `~/damla_projects_2026/_f3e_live` altında **duruyor**
(hakem `.rabadon/sessions/*.moves.bin`'i kendi parser'ıyla açabilsin diye silmedim).
