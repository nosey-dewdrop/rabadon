# f2-0 · HÜKÜM — bu koşunun 16 STOP'unun her biri

Kapsam: `sid` ön eki `286fd71d`, kaynak `~/.rabadon/spool/2026-08-2[456].jsonl`.
Dondurma noktası: son kapsamlı `ts` = 1787731772907. Ölçüm anı: 2026-08-26T08:43:46Z.
Sayaç: `bash native/refusal_rate.sh 286fd71d` → `reports/kosu/RAPOR/f2-0-refusal-rate.out`.

**ÖNCE ÖLÇÜLEN KISIT.** Defterdeki `STOP.detail` alanı komut metnini **160 bayt**ta
kesiyor (ölçüm: 16 kaydın 9'u tam olarak 187 = 27 önek + 160 bayt). Bu yüzden dört
retin eşleşen metni kaydın dışında kalıyor ve **hükümsüz** kalıyorlar. Bunu sessiz
geçmiyorum: aşağıda adlarıyla duruyorlar.

| # | kural | `detail` ilk satırı (kesik) | hüküm |
|---|-------|------------------------------|-------|
| 1 | no-blind-inplace-source-rewrite | `... && bash -c '\n{\necho "=== f1d-C empty-green round (§8.2) ...` | **HÜKÜMSÜZ** — eşleşen metin 160 baytın ötesinde |
| 2 | no-exit-code-after-pipe | `make all 2>&1 \| tail -10; echo "MAKE_ALL_EXIT=$?"` | **DOĞRU RED** — `$?` tail'in durumu, kuralın tarif ettiği hata birebir görünür |
| 3 | no-exit-code-after-pipe | `bash native/version_test.sh 2>&1 \| grep -iE ... \| head -20; echo "EXIT=$?"` | **DOĞRU RED** — `$?` head'in durumu |
| 4 | no-blind-inplace-source-rewrite | `sed -i '' -e 's/PLACEHOLDER_EXIT/0/' -e 's/PLACEHOLDER_OK/3616/' ...` | **DOĞRU RED** — gerçek yerinde kaynak yazımı, kuralın tam konusu |
| 5 | no-exit-code-after-pipe | `rm -rf /tmp/hakem-pre && mkdir -p ... && git archive 1ea32c4 \| tar -x ...` | **HÜKÜMSÜZ** — görünen boruda `tail\|head\|grep\|sed\|awk` yok; eşleşme kesilen kuyrukta |
| 6 | no-exit-code-after-pipe | `docker info 2>&1 \| sed -n '1,60p'; echo "EXIT=$?"` (TAM, 119 bayt) | **DOĞRU RED** — `$?` sed'in durumu |
| 7 | no-gnu-timeout-on-macos | `timeout 180 docker pull debian:bookworm-slim > /tmp/pull.out 2>&1; echo "pull exit=$?"` (TAM) | **YANLIŞ RED** — aşağıda kanıt |
| 8 | no-exit-code-after-pipe | `cat >> .../reports/kosu/SAPMA-KARARLARI.md <<'MARKER' ...` | **YANLIŞ RED** — yasak şekil yazılan BELGENİN içinde; ölçülen olayın ta kendisi |
| 9 | no-blind-inplace-source-rewrite | `sed -i '' 's\|^DIGEST=$(docker image inspect ...` | **DOĞRU RED** — gerçek yerinde kaynak yazımı |
| 10 | red-suite-test-write | süit kırmızıyken `native/status_truth_test.sh` yazımı | **YANLIŞ RED** — operatör aynı gün `rabadon wrong` ile bildirdi (defterde) |
| 11 | red-suite-test-write | süit kırmızıyken `native/status_truth_test.sh` yazımı | **YANLIŞ RED** — aynı, defterde kayıtlı |
| 12 | red-suite-test-write | süit kırmızıyken `native/heredoc_prose_test.sh` yazımı | **YANLIŞ RED** — aynı, defterde kayıtlı |
| 13 | red-suite-test-write | süit kırmızıyken `native/heredoc_prose_test.sh` yazımı | **YANLIŞ RED** — aynı, defterde kayıtlı |
| 14 | no-exit-code-after-pipe | `set -u\nR=/Users/...\nP=$(mktemp -d); RD=$(mktemp -d) ...` | **HÜKÜMSÜZ** — eşleşen metin 160 baytın ötesinde |
| 15 | no-exit-code-after-pipe | `... && bash -c '\nset -u\nGATE=native/rabadon-gate\n...` | **HÜKÜMSÜZ** — eşleşen metin 160 baytın ötesinde |
| 16 | no-exit-code-after-pipe | `./native/rabadon-cli.sh wrong 2>&1 \| head -6; echo "exit=$?"` | **DOĞRU RED** — `$?` head'in durumu |

**Sayım:** DOĞRU RED 6 · YANLIŞ RED 6 · HÜKÜMSÜZ 4 · toplam 16.
Hükümsüz bırakılan ret sayısı SIFIR DEĞİL: 4 (#1, #5, #14, #15), sebebi yukarıdaki
160 baytlık kesme. Bunları "doğru red" saymak sayacı olduğundan iyi gösterirdi.

## Yeni koşulan `wrong` verbleri (gerçekten koştu, deftere yazdı)

7 numara için ölçülen kanıt: kuralın kendi `why` satırı "macOS has no `timeout`
binary; the command dies before the real work runs" diyor. Bu makinede
`command -v timeout` → `/opt/homebrew/bin/timeout`. Öncül bu kutuda YANLIŞ, ret
çalışan bir komutu durdurdu.

```
./native/rabadon-cli.sh wrong no-gnu-timeout-on-macos "STOP 7 ... command -v timeout answers /opt/homebrew/bin/timeout ..."   -> exit 0
./native/rabadon-cli.sh wrong no-exit-code-after-pipe  "STOP 8 ... the forbidden shape sat in the PROSE being written ..."     -> exit 0
```

10–13 için YENİ bir `wrong` KOŞULMADI, çünkü defterde zaten bu koşunun penceresinde
dört `red-suite-test-write` WRONG_REFUSAL satırı var (ts 1787719075970, 1787719555475,
1787719812903, 1787725691722) ve dördü dört STOP'a birebir denk düşüyor. Beşincisini
yazmak payı şişirmek olurdu.

## Ölçülen boşluk (kart S13/f — onarım kapsam dışı, ilan burada)

`WRONG_REFUSAL` satırında `sess` YOK, `sid` YOK, `call` YOK — yalnız `rule`, `why`,
`ts` ve `pipe:"damummyphus:cli"` var. `STOP` satırında üçü de VAR. Sonuç: pay ile
payda **yalnız kural adı** üzerinden birleşiyor; tek tek retle birleşmiyor ve pay bu
koşuya daraltılamıyor. `refusal_rate.sh` C bölümünde bunu her koşuda basıyor.
