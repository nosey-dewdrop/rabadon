# f1a-3-doctor — dört sessiz kurulum hatası

YAPILAN
1. `native/doctor_test.sh` +9-12. bölüm (eski case silinmedi/zayıflatılmadı): node<engines.node / ikili var ama executable değil / PATH'te çift-yabancı `rabadon` / önceki kurulumdan kalan global hook. Her sınıfın yanında POZİTİF KONTROL (hep uyaran doctor da kırmızı düşer); `three()` yardımcısı WARN bloğunda `why:`+`run:` yoksa kırmızı verir.
2. `hooks/manage.mjs` / `cmdDoctor`: (0) engines.node tabanı package.json'dan OKUNUR, sabit sayı yok; (1b) mevcut ama X_OK'suz ikililer → `chmod +x <yollar>`; (2) gate spawn `error` → OS çalıştırmayı reddetti (quarantine/arch); (4b) PATH taranır, realpath ile "bu kurulum mu" diye bakılır; (5) hook komutu ölü mü (yol yok) yoksa BAYAT mı (yol var, başka ağaç). Dördü de what + `why:` + `run:` basar.

ÖLÇÜLEN — komut: `./native/doctor_test.sh`
3. BAZ (dosyaya dokunmadan): `doctor: 24 passed, 0 failed`, exit 0.
4. KIRMIZI ÖNCE (testler yazıldı, manage.mjs'e dokunulmadı): `28 passed, 15 failed`, exit 1 → `f1a-3-kirmizi-once.out` (139 satır, dört sınıf da kırmızı).
5. SONRA: `43 passed, 0 failed`, exit 0 — ok sayısı 24 → 43, azalmadı.
6. `node hooks/manage.mjs doctor` gerçek makinede `all green.` exit 0; yeni satırlar: `ok node 26.5.0 (satisfies engines.node ">=18")` · `ok \`rabadon\` on PATH is this install (/opt/homebrew/bin/rabadon)` · `ok global hooks healthy (1 rabadon command(s), all from this install)`.

YAPILAMAYAN
7. quarantine (macOS xattr) dalı fixture'la KANITLANMADI — karantinalı ikili üretmek indirme ister; chmod -x dalı kanıtlı, ikisi aynı kodda. DOĞRULANMADI.
8. Gerçek eski node (v16) ile koşulmadı; taban `engines.node` alanı yükseltilerek üretildi, karşılaştırma kodu aynı.
9. `native/npm_install_test.sh` koşulmadı (kart listesi dışı, açmadım): grep'e göre yalnız "native core built" arıyor, exit kodu aramıyor. DOĞRULANMADI.

KART DIŞI (dokunulmadı)
10. `.github/workflows/ci.yml` çalışma ağacında zaten değişik (` M`) — benim işim değil.
11. Fixture'larda doctor artık 1 problem sayıyor (makinedeki gerçek `/opt/homebrew/bin/rabadon` sahte ağaca göre yabancı); mevcut testler göreli karşılaştırdığı için etkilenmedi (`half 2 > full 1`).
12. `version drift` uyarısı hâlâ tek satır (why:/run: yok) — §4.8'e göre eksik ama bu kartın dört sınıfı dışında, dokunmadım.
