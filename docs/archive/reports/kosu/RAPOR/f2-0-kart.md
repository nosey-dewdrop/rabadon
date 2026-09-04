# f2-0-yanlis-pozitif — kart raporu

Dal `main`, faz başı `f03320f`. Yeni dal/worktree açılmadı, alt ajan salınmadı.

## Commit'ler

| commit | ne |
|--------|-----|
| `eeedfe4` | FİKSTÜR TEK BAŞINA: 5 yanlış-pozitif hücresi ALLOW beklentisiyle + 2 yeni pozitif (çıplak boru, `bash -c` gerçek boru hattı). Kod DEĞİŞMEDİ, süit FAILED düştü. |
| `2097d75` | S12 onarımı: `native/cmdtext.h` + `native/rules.h`. |
| (bu commit) | S13 sayacı `native/refusal_rate.sh`, hüküm ve kart raporu. |

Kabul ölçütü onu sağlayan kodla **aynı commit'te değil** (CLAUDE.md 2, F1e yöntemi).

## S12 — ne yapıldı

Kök sebep: `rules.h::whole_line` boru adlandıran kurala **ön-işlenmiş ama
tırnak-nötrleştirilmemiş** satırı veriyordu. Her segment yüzeyi (`cmdtext.h::scan`)
tırnak içi boşluğu `\x01` (DATA_WS) yapıyor; bütün-satır yüzeyi bunu yapmayan tek
yerdi. Yama değil, aynı cevabı ikinci kez türetmemek için `scan`'in tırnak yürüyüşü
`cmdtext.h::line_surface()` olarak ayrıldı ve satıra uygulandı.

Kuralı gevşetmeyen yarısı: tırnaklı bir dizge bir kabuğa verildiğinde **program**dır.
`Parsed::lines` artık bir vektör — `lines[0]` nötrleştirilmiş satır, sonraki her
girdi gerçekten koşan bir dizge (`bash -c` / `sh -c` / `eval` betiği, `$( )` ve
backtick gövdesi). `bash -c "<gerçek boru hattı>"` bu ikinci girdi üzerinden
reddediliyor.

**Kart (d) — CHALLENGE'a gerek kalmadı.** `bash -c "make test | grep -c ok ; echo
exit=$?"` hücresi fikstüre kondu, ölçüldü, **BLOCK**; beş ALLOW hücresi bozulmadan.
Bilinen boşluk ilan etmeye gerek yok, çünkü hücre yeşil değil — doğru cevabı verdi.

`.rabadon/guard.json`'a dokunulmadı (regex, eşik, `disabled[]` aynı).
Mevcut yedi pozitifin hiçbiri silinmedi/zayıflatılmadı; sayı 14 → **21**.

## S13 — ne yapıldı

`native/refusal_rate.sh <sid-öneki> [spool-dizini]`. bash + grep/sed/awk; python3,
jq, node, ağ yok. Kapsam argümanı **zorunlu**: aynı spool dosyasında `stitchu`,
`fixed`, `damummyphus:cli` satırları var, filtresiz sayı yanlış sayıdır.

İki payda tanımı da AYRI basılıyor (biri "doğru" ilan edilmiyor), ölçüm anı ve
dondurma `ts`'i çıktının başında, `WRONG_REFUSAL` birleştirme boşluğu C bölümünde,
elle sayılan eski rakamlar E bölümünde "farklı yöntem, kıyaslanmaz" etiketiyle.

## Ölçülen sayılar (komutlarıyla)

| sayı | komut |
|------|-------|
| `PASS (21 checks)`, EXIT=0 | `./native/heredoc_prose_test.sh` |
| 5/5 BLOCK (onarım ÖNCESİ), süit FAILED | aynı komut, `f2-0-bosyesil.out` |
| BUILD=0 | `make all` |
| make test EXIT=0 | `make test` |
| `ok` satırı **3745** (taban 3738, +7) | `grep -cE '^[[:space:]]*ok\b' f2-0-maketest.out` |
| PASS toplamı **633** (taban 626, +7) | `grep -oE 'PASS \([0-9]+ checks?\)' ... \| paste -sd+ - \| bc` |
| npm 64 pass / 0 fail | `npm test` |
| R7 23 yeşil / 3 kırmızı, adlar 2b, 6e, 7b | `bash reports/R7/accept.sh` |
| sıcak yol 228.7µs → 231.8µs medyan (+1.4%) | `./native/gate_bench.sh`, iki ikili aynı dakikada, `f2-0-bench.out` |
| STOP+BLOCKED **16**, WOULD_BLOCK **24**, toplam **40** | `bash native/refusal_rate.sh 286fd71d` |
| DOĞRU RED 6 / YANLIŞ RED 6 / HÜKÜMSÜZ 4 | `f2-0-hukum.md` |

## OLUMSUZ SONUÇLAR — olduğu gibi

- **Payda büyüdü, kartta yazandan da fazla.** Kart WOULD_BLOCK için 23 diyordu,
  ben 08:42'de **24** ölçtüm. STOP kartta 16, bende de 16. Defter canlı; betik
  ölçüm anını ve dondurma `ts`'ini basıyor, yoksa iki sayı asla uyuşmaz.
- **Yayımlanan "15" yalnız STOP'tu ve o tanımla bugün 16.** S13/a'nın istediği
  tanım (STOP+WOULD_BLOCK) **40** veriyor. İkisi de basılıyor.
- **Dört ret hükümsüz kaldı** (#1, #5, #14, #15). Sebep ölçüldü: defterin
  `STOP.detail` alanı komutu **160 baytta kesiyor**, eşleşen metin kaydın dışında.
  Bunları "doğru red" saymak yanlış-pozitif oranını olduğundan iyi gösterirdi.
- **R7 2b sayısı bu turda 2537.6µs okundu** (taban okuması 1218.5µs). Bu benim
  değişikliğim DEĞİL: aynı dakikada iki ikiliyle alınan bench farkı +3.1µs.
  2b zaten kırmızıydı ve kırmızı kaldı; makine yükü altındaki bir süreç-seviyesi
  ölçüm olduğu için sayısı oynuyor. Yine de sayı burada duruyor.
- **Pay ile payda tek tek retle birleşmiyor** (S13/f). Onarım kapsam dışı, ilan
  `f2-0-hukum.md` ve betiğin C bölümünde.

## DOĞRULANMADI

- Temiz konteynerde/temiz klonda hiçbir şey koşulmadı; hepsi bu makinede.
- `line_surface()` yalnız `heredoc_prose_test.sh`'in fikstür kuralları ve
  `make test`'in tamamıyla ölçüldü; kullanıcıların kendi guard.json regexleri
  (tırnak karakterine bakan bir desen) için ayrı bir ölçüm yapılmadı.
- 10–13'ün "operatör zaten `wrong` koştu" hükmü `ts` yakınlığına ve sayı
  eşleşmesine dayanıyor; `WRONG_REFUSAL` satırında `call` olmadığı için birebir
  bağ KURULAMAZ (boşluğun kendisi).

## KART DIŞI FARK EDİLENLER (dokunulmadı)

1. `no-gnu-timeout-on-macos` kuralının gerekçesi bu makinede **yanlış**:
   `/opt/homebrew/bin/timeout` var. Kural düzeltilmedi (kapsam dışı, `guard.json`
   yasak); yalnız `rabadon wrong` ile deftere yazıldı.
2. `STOP.detail` 160 baytta kesiyor. Bir retin neden verildiği sonradan
   denetlenemiyor — bu, yanlış-pozitif sayımının üst sınırı.
3. `~/.rabadon/wrong-<kural>` işaret dosyaları defterden bağımsız duruyor
   (`wrong-red-base`, `wrong-no-exit-code-after-pipe`); ikinci bir gerçek kaynağı.
4. `reports/kosu/RAPOR/f2-0-taban-accept.out` ve `f2-0-taban-test.out` faz başında
   takipsizdi (şefin taban ölçümü); bu kartla commit edildiler, silinmediler.
