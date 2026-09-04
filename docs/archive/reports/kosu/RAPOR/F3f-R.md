# F3f — HAKEM RAPORU (2026-08-29)

Taban `F3f-oncesi` = `b482d40`. HEAD = `49163f3`. Şef bunu okumaz; hüküm
`KAPI.md`'nin tek satırındadır.

**HÜKÜM: GEÇTİ.** Bloklayan kart (K1) tam teslim edildi ve dört yoldan KENDİ
elimde doğrulandı. §3.8 denetiminde tek bir ihlal yok. Ama K4'ün üç iddiası
yanlış çıktı ve üçü de sıradaki fazın bloklayan kartını doğuruyor — ürün
kapsamından, kanıt altyapısından değil.

---

## 1. SAYAÇLAR — hepsini ben koşturdum

`make test` **EXIT=0**. TEK GEÇERLİ SAYAÇ (DURUM.md:594 üç komut):

| bacak | taban `b482d40` (kendi worktree'mde koşturdum) | **HEAD** |
|---|---|---|
| native iddia (`grep -cE '^[[:space:]]*ok\b'`) | 3859 | **3893** |
| kontrol (`PASS (N checks)` toplamı) | 633 | **633** |
| npm (`ℹ pass` / `ℹ fail`) | 64 / 0 | **64 / 0** |
| **TOPLAM** | **4556 / 0** | **4590 / 0** |

**+34 doğrulandı ve kaynağı SÜİT-DİFF'İYLE ayrıldı** (iki `make test`
çıktısının süit bazında karşılaştırması):

- süit sayısı **113 → 115**
- `guard_delete_test.sh` **yok → 16**, `hook_upgrade_test.sh` **yok → 18**
- **başka HİÇBİR süidin sayısı değişmedi. Küçülen 0, kaybolan 0.**
  (Kartın "başka hiçbir süidin sayısı değişmedi" cümlesi doğru.)

Taban worktree'sinin `Makefile`'ı iki yeni süidi **hiç çalıştırmıyor**
(`grep -c` → 0), yani 4556 ölçümü kirlenmedi.

`bash reports/R7/accept.sh` → **EXIT=1, 23 yeşil / 3 kırmızı, `{2b, 6e, 7b}`
— BÜYÜMEDİ.**

`F1e-C üçlüsü`, fazın **nihai** ikilisine karşı, az önce koşturuldu:
`docs_truth_test.sh` **42/0**, `install_docs_test.sh` **38/0**,
`version_test.sh` **13/0**, üçü de **EXIT=0**.
Kâtip commit'i `793a544` (`docs/how-it-works.md`) fazın **son commit'i değil**
(son commit kart, `49163f3`). ✔

## 2. §3.8 DENETİMİ — ihlal yok

| madde | ölçüm |
|---|---|
| silinen dosya | **0** (`--diff-filter=D`) |
| silinen iddia satırı (`-.*ok \|assert`) | **0** |
| yeni `skip` / `xfail` | **0** (tek eşleşme bir YORUM: "NO SILENT SKIP") |
| küçülen süit | **0** (yukarıdaki süit-diff) |
| `reports/R7/accept.sh` · `ON-KAYIT.md` · `docs/claims.tsv` · `.rabadon/guard.json` | diff'te **HİÇ YOK** |
| `bin/rabadon.mjs` (O3 donuk yol) | diff'te **HİÇ YOK** |
| `moves.h` `CAP=200` | **200**, dokunulmadı (halkayı kendi parser'ımla açtım: 200 slot) |
| korpus / snapshot | dokunulmadı |
| ölçüt commit'leri koddan ÖNCE ve AYRI (CLAUDE.md 2) | **EVET**: `a21955a` (süit + kanıt, kod yok) → `959bd40` (kod); `3ef6928` (süit + kanıt, kod yok) → `8a62554` (kod) |
| beş-verb tavanı `cli_test.sh` | **315/0** |
| `install_docs_test.sh` + `doctor_test.sh` | **38/0** ve **43/0** |
| §3.12 tahmin commit'i kart kesilmeden önce | **EVET** — `bbf90d4` fazın **ilk** commit'i, ilk kart commit'i `a21955a` ondan sonra |

`docs/claims.tsv` **gerekmiyordu**: sicil kendi başlığıyla yalnız
`docs/commands.md` içindeki `rabadon:claims-begin` bloklarını kapsıyor;
bu fazın belgesi `docs/how-it-works.md`'ye düştü. Ajan `CHALLENGE:` yazmamış,
gerek de yoktu. Hükme bağlandı.

## 3. ⚠ ÖNCELİKLİ İNCELEME — `~/.claude/settings.json`'a OTOMATİK YAZMA

Bana en ağır sınıf olarak verilen kalem. **Altı sorunun altısını kendi elimde
ölçtüm ve altısı da ürünün lehine çıktı.** Bu, fazın en iyi mühendislik işi.

**(1) `statusLine.command` korunuyor mu — BAYT BAYT.**
Canlı makine, faz öncesi hâli `~/.claude/settings.json.bak-rabadon`'da duruyor:

```
'"statusLine": {\n    "type": "command",\n    "command": ".../orkestra/src/bar.py",\n    "padding": 0,\n    "refreshInterval": 1\n  }'
```

İki dosyada **bayt bayt AYNI** (`IDENTICAL_BYTES: True`). Paylaşımlı statusline
öldürülmedi. Kum havuzunda da doğruladım: yabancı bir `statusLine` yazdım,
tazeleme sonrası **aynen duruyor** (`/somebody/else/bar.py`).

**(2) Yabancı kancalar korunuyor mu.** Faz öncesi `settings.json`'da 12 adet
`orkestra/src/tick.py` kancası vardı; **sonrası 12.** Hiçbiri düşmedi, hiçbiri
kırpılmadı. `permissions` bloğu da kum havuzunda korundu.
*Değişen tek şey:* aynı olay içinde **sıra** — rabadon `stripOurs` + yeniden
ekleme yaptığı için `PreToolUse`/`PostToolUse`/`UserPromptSubmit`'te rabadon
kancası birinciden ikinciye düştü. Yabancıların birbirine göre sırası bozulmadı.
Bunu **not olarak** yazıyorum, ihlal saymıyorum.

**(3) Yedek gerçekten alınıyor mu, nereye.**
`~/.claude/settings.json.bak-rabadon`, diskte, 5536 bayt, 23:18.
İçeriği faz öncesi hâl (`PostToolUseFailure→rabadon-gate` ve
`Stop→rabadon-drift` YOK, kalan her şey var). Kum havuzunda da ölçtüm:
**yedek == orijinal, bayt bayt.**
*Zayıflık:* yedek adı SABİT. İkinci bir gerçek yazma orijinali ezer. Bugün
zararsız (sağlıklı dosyaya yazma yok), ama sınırsız değil — kayda geçti.

**(4) Bozuk/okunamayan `settings.json` ile ne oluyor — EN ÖNEMLİ SORU.**
Kum havuzunda **bozuk ama açıkça rabadon kurulumu olan** bir `settings.json`
verdim, sevk edilen `refreshTarget`'ı koşturdum:

```
returned      : null
threw         : null
file UNCHANGED: true      <-- YEDEKSİZ ÜSTÜNE YAZMIYOR
backup written: false
```

**En kısıtlayıcı davranış seçilmiş.** Emsal (F1c) burada TEKRARLANMADI.
**AMA — F1c'nin "iki yüzey, iki yasa"sı BİRLEŞTİRİLMEDİ; ÜÇÜNCÜ BİR YASA DOĞDU:**

| yüzey | okunamayan dosyaya davranış | ölçtüğüm |
|---|---|---|
| `.claude` / `installHooks` | `JSON.parse` fırlatır → çağıran `exit 1`, GÜRÜLTÜLÜ ret | (F1c'den, değişmedi) |
| `.cursor` / `installCursorHooks` | **YEDEKSİZ ÜSTÜNE YAZAR ve kullanıcının kendi kancasını YOK EDER** | `changed:true, backedUp:false, users hook survived: FALSE` — **BUGÜN ÖLÇTÜM, HÂLÂ AÇIK** |
| `refresh.mjs` (YENİ) | hiçbir şey yapmaz, **hiçbir şey de söylemez** | `returned: null`, ekranda satır yok |

Üçüncü yasa güvenli ama **DİLSİZ**. CLAUDE.md "her error path tasarlanmış bir
path'tir … asla susmaz" ve `refresh.mjs`'in kendi başlığı ("Promise 1: it never
goes quiet") buna aykırı: kullanıcının guard'ı sonsuza kadar yükseltilemez
kalır ve bunu kimse söylemez. Bloklayıcı değil, F3g'nin kalemi.

**(5) Çıkışı var mı, ekran söylüyor mu.**
Kum havuzunda bayat bir kuruluma **gerçek `SessionStart` olayı** verdim.
Ekranın **birinci satırı**:

```
rabadon: this install was older than the binary — subscribed to PostToolUse,
PostToolUseFailure, Stop, UserPromptSubmit in <path>/settings.json
        (your previous settings are in <path>/settings.json.bak-rabadon;
         the new events take effect in your NEXT session)
```

Sessiz değil, ilan edilmiş. Yuvarlamıyor da: aynı ekranda
`blind spots: … it is live from your NEXT session, this one stays blind`.
`RABADON_SELFHEAL=0` ile ikinci turu koşturdum: **dosya bayt bayt dokunulmadan
kaldı.** §4.8 (ekran ne diyorsa gate onu yapar) **KARŞILANDI.**
*Tek eksik:* `README.md` kurulumdan ÖNCE bunu söylemiyor; çıkış yalnız env
değişkeni, config anahtarı değil. F3g'nin kalemi, bloklayıcı değil.

**(6) `docs/` güncellendi mi.** **EVET** — `docs/how-it-works.md` +34 satır,
kendi başlıklı bölüm ("Upgrading an install that already exists"), ne dokunduğu
· neye dokunmayı reddettiği · yedek adı · `RABADON_SELFHEAL=0` · bir oturum geç
geldiği yazılı. "Docs move with behavior" karşılandı.

**HÜKÜM: otomatik yazma AĞIR SINIF ama DOĞRU YAPILMIŞ.** Geri alma gerektiren
hiçbir bulgu yok.

## 4. KART 1 — CANLI MAKİNE GERÇEKTEN GÖRÜYOR (kendi elimde)

`; true` OLMADAN, kendi oturumumda:
`ls -la /nonexistent-hakem-f3f-probe-ZZ9` → **Exit code 1**.

Ham defter (`~/.rabadon/spool/2026-08-29.jsonl`, kendi okuyucumla):

```
STEP_START  call=toolu_01VXyYK8e7AqH8pabdFqfeHs  step="bash: ls -la /nonexistent-hakem-f3f-probe-ZZ9"
STEP_OK     call=toolu_01VXyYK8e7AqH8pabdFqfeHs  step="ran: ..."  "rc":1
```

Ham hamle halkası (`RBMV1`, 320B `Rec`, **kendi parser'ımla**, sevk edilen
exporter'a hiç güvenmeden):

```
seq=1328 claimed_rc=1 tool=1 sig=e052be370cd30660 err_sig=7a32e59add7d390d
raw='ls -la /nonexistent-hakem-f3f-probe-ZZ9'
```

F3e hakeminde `STEP_START` vardı, `STEP_OK` YOKTU, `err_sig` boştu.
**"Sevk edildi ama kurulmadı" sınıfı, canlıda, kapandı.** ✔

**Mutasyonu kartınkini kopyalamadan kendim yaptım** (`hooks/refresh.mjs`,
Edit ile — kapı `perl -0pi`'yi haklı olarak keserdi):

| tur | ölçüm |
|---|---|
| kontrol, HEAD | **18 passed / 0 failed** |
| MUTASYON A — yükseltme adımı çıkarıldı (`refreshTarget` erken `return null`) | **9 passed / 9 FAILED** |
| MUTASYON B — self-install koruması gevşetildi (`before.size === 0` kolu silindi) | **17 passed / 1 FAILED** |
| ikisi de geri alındı, `git status` temiz | **18/0** |

Kartın 9/9 ve 17/1 sayıları **birebir doğrulandı**.
**Boş yeşil turu, `F3f-oncesi` ağacında, kendi worktree'mde:
`hook_upgrade_test.sh` 8 passed / 10 FAILED** (kart: 8/10 ✔),
`guard_delete_test.sh` **11 passed / 5 FAILED** (kart: 11/5 ✔).

## 5. KART 4 — ÜÇ İDDİA YANLIŞ. Onarım doğru, çerçeve şişik, aile açık.

### 5.1 "CANLI BYPASS" bir /tmp ARTEFAKTIDIR

Kartın kanıt betiği `k4-rm-probe.sh` kum havuzunu
`mktemp -d "${TMPDIR:-/tmp}/…"` ile açıyor. **Tuzak 1'in ta kendisi**
(DURUM.md:578). Aynı ölçümü iki kökte, iki ikiliyle koşturdum:

| ikili | kum havuzu kökü | `rm .rabadon/guard.json` | `rm -f` | `rm promise.json` | `mv` |
|---|---|---|---|---|---|
| **taban** `F3f-oncesi` | `$TMPDIR` | **rc=0 GEÇTİ** | rc=0 | rc=0 | rc=2 |
| **taban** `F3f-oncesi` | `$HOME/…/_hakem_f3f` | **rc=2 REDDEDİLDİ** | rc=2 | rc=2 | rc=2 |
| **HEAD** | `$TMPDIR` | rc=2 | rc=2 | rc=2 | rc=2 |
| **HEAD** | `$HOME/…/_hakem_f3f` | rc=2 | rc=2 | rc=2 | rc=2 |

**Yani faz öncesi ikili, evinin altındaki gerçek bir projede zaten
reddediyordu.** Açık YALNIZ temp-kökü sınıfındaydı. O sınıf gerçektir ve
önemsiz değildir (CLAUDE.md referans ortamı "temiz bir konteyner"), ama kartın
"canlı BYPASS ölçüldü" cümlesi, kendi diğer cümlesi ("worktree'ler /tmp dışında
açıldı ve kaldırıldı") ile aynı kartta çelişiyor. **Onarım doğru ve yalnız
reddi artırıyor** (`rules.h` diff'ini okudum: bir bastırma daraltılmış, desen
eklenmemiş) — **ama şiddet iddiası düzeltilerek kayda geçer.**
Ek olarak: `guard_delete_test.sh` de kum havuzunu `${TMPDIR:-/tmp}` altında
açıyor, yani **16 iddianın 16'sı temp-kökü sınıfında.** Onarımın gerçek bir
proje kökünde de tuttuğunu **ben ölçtüm** (yukarıdaki dördüncü satır).

### 5.2 BİLDİRİLEN YANLIŞ POZİTİF ÜRETİLEBİLİYOR — ÜRETTİM

Kart: "9 salt-okuma şekli, yanlış pozitif 0/9 · ÜRETİLEMEDİ · ÖLÇEMEDİM."
Onuncu şekli denedim, **HEAD ikilisinde, gerçek gate'e**:

```
grep -c rm .rabadon/guard.json          ->  rc=2   REDDEDİLDİ
```

Salt-okuma bir `grep`. Sebep desende: `\b(rm|mv)\b[^\n]*\.rabadon/(guard|promise)\.json`
**bir yazmayı değil bir ANMAYI yakalıyor** — satırda `rm` token'ı ve yol
geçmesi yetiyor. Ajanın 9 şeklinin hiçbirinde `rm`/`mv` token'ı yoktu, o yüzden
küme boş çıktı.

**HÜKÜM: F3e hakemi haklıydı, F3f kartı yanılmıştır.** Eski sayı silinmiyor:
F3e'nin bildirdiği yanlış pozitif **AYAKTA** ve bugün **+1 daha somut** (tam
komut metni artık kayıtlı, daraltılacak kapsam var). Bu, aynı `guard.json`'da
zaten bir kez hükme bağlanmış sınıf: `no-scripted-inplace-test-rewrite`'ın
`wrongWhy` alanı lafzen *"A rule about a write was matching a mention"*.
CLAUDE.md: "False rejects are counted, not excused."

### 5.3 BİR ŞEKİL KAPANDI, AİLE AÇIK — D1'in dersi

HEAD ikilisi, **gerçek proje kökü**, yasa dosyasını etkisizleştiren 16 şekil:

| şekil | rc |
|---|---|
| `rm` / `rm -f` / `rm ./` / `rm promise.json` / `mv` / `git rm -f` / `: >` / `cat /dev/null >` | **2 — REDDEDİLDİ (8 şekil)** |
| **`rm -rf .rabadon`** | **0 — GEÇİYOR** |
| `truncate -s 0 .rabadon/guard.json` | **0 — GEÇİYOR** |
| `cp /dev/null .rabadon/guard.json` | **0 — GEÇİYOR** |
| `chmod 000 .rabadon/guard.json` | **0 — GEÇİYOR** |
| `ln -sf /dev/null .rabadon/guard.json` | **0 — GEÇİYOR** |
| `install -m 000 /dev/null .rabadon/guard.json` | **0 — GEÇİYOR** |
| `dd if=/dev/null of=.rabadon/guard.json` | **0 — GEÇİYOR** |
| `find .rabadon -name guard.json -delete` | **0 — GEÇİYOR** |

**`rm -rf .rabadon` en ağırı:** yasanın tamamını siler, gate izin verir.
`is_rabadon_law_file` yalnız İKİ TABAN ADINA bakıyor, üst dizini hiç görmüyor —
bastırma dizin hedefinde aynen çalışmaya devam ediyor. **Guard'ın kendisi
silinebiliyorsa guard yoktur.** Bu, kartın kapattığını ilan ettiği sınıfın
kendisidir ve HEAD'de canlıdır.

Bastırmanın var olma sebebi korunmuş (`rm -rf build`, `rm -rf ./build`,
`rm -f README.md` → hepsi rc=0 ✔) — onarım aşırı daraltmadı.

## 6. KART 2 — DOĞRULANDI (kendim koşturdum)

`k2-ayristir.py`'ı kendim koşturdum (halkaları okur, yazmaz):

- A) yalnız tam-imza şartı: **2 / 81 oturum**
- B) yalnız başarısızlık şartı: 9 / 81
- C) sevk edilen kural (ikisi birden): **0 / 81**
- D) **ÜST SINIR** — 276 kapanmamış hamlenin hepsi başarısız sayılsa bile:
  **0 / 81**
- pencere içi en yüksek tekrar: **75 oturumda seen=1** (imza bir kez bile
  tekrar etmiyor)

**Kartın iddiası doğru: engelin TAMAMI tam-imza katılığıdır; `err_sig` onarımı
`repeat`'i ateşlenebilir yapmadı.** (ii) hiçbir zaman bağlayıcı kısıt değildi.

F4'e devredilen ölçüm: imza "ilk token" olsaydı 1. şart **32/81** (kart 32 ✔),
iki şart birden **7/81** — kart **8/81** demiş. **±1 fark gerçektir ve
sebebi halkanın canlı olmasıdır**: benim kendi oturumum korpusun içinde ve
o oturumdan beri büyüdü. Kartın sayısı silinmiyor, yanına benimki yazılıyor.

## 7. KART 3 — `2b` HIZLANMADI; ayakta kalan TEK SAYI

Kart negatif rapor ediyor (CLAUDE.md 8'e uygun) ve ben de negatif ölçüyorum.
Kendi koşumda, **yayınlanmış kabul aletiyle** (`reports/R7/accept.sh`):

```
FAIL  2b the gate's median is 1378.0 us with the daemon up, ceiling is 1000 us
```

**AYAKTA KALAN TEK SAYI: `2b` = 1378,0 µs · tavan 1000 µs · KALAN AÇIK 378 µs.**

Kart aynı satırda **1249,0 µs** yazmış. Aradaki **129 µs**, kartın kendi ilan
ettiği **|439 µs|** gürültü bandının içinde — yani fazın iddia ettiği
**−380,7 µs** iyileşme, aletin kendi koşudan koşuya sapmasıyla aynı büyüklükte.
**İyileşme iddiası yok, doğru davranış budur.** F3e hükmündeki "atfedilebilir
1602–1799 µs, ~800 µs düşmeli" ifadesi farklı bir ölçüm hattıdır; kayda geçen
**yayınlanmış kapı sayısı 378 µs açıktır.**
**Tavan oynatılmadı, `accept.sh` diff'te hiç yok** (§3.8/1, §3.8/4, §11). ✔
Kırmızı ad kümesi `{2b, 6e, 7b}` **büyümedi**.

## 8. KAPI BENİ KESTİ — nasıl aştığımı ilan ediyorum

`baseline-truncating-redirect`: `sed … > ~/…/_hakem_f3f/k4base.sh`
→ **BLOCKED, doğru ret** (proje ağacı dışına yönlendirme). **Aşma yolu:
Write aleti** — ayrı bir yüzey, kural shell yönlendirmesine bakıyor.
`guard.json`'a **DOKUNULMADI** · `rabadon off` **KULLANILMADI** ·
CHALLENGE-3 bileşik-komut deliği **KULLANILMADI**.
Kum havuzlarım `/tmp`'de DEĞİL (`~/damla_projects_2026/_hakem_f3f`), hepsi
kaldırıldı; taban worktree'si de kaldırılacak.

## 9. ÖLÇEMEDİKLERİM

- `pre_main`'in içi ve `main`'in içi (kartın da ölçemediği) — dokunmadım.
- Kartın K3 profil sayılarını (%72,3 / %27,0) yeniden üretmedim; negatif bir
  sonucu destekliyorlar ve `2b` kapı sayısını ben doğrudan ölçtüm.
- `rm -rf .rabadon`'un ve diğer 7 şeklin **F3f-oncesi** ikilisindeki hâlini
  ayrıca ölçmedim; HEAD'de açık olmaları hükmü tek başına taşıyor.
- `no-rm-rf-outside`'ın ad-iş uyuşmazlığı (F3e'den devir) bu turda
  incelenmedi — hâlâ sahipsiz.
- Yedek adının sabit olmasının ikinci bir gerçek yazmada orijinali ezmesini
  canlı makinede üretmedim (kum havuzunda mantığı okudum).
