# rabadon — MÜHÜRLÜ HANDOFF (29.07 geç)

> Sonraki session bunu SIFIRDAN çözmesin. Kanun: ~/.claude/CLAUDE.md §0 + repo CLAUDE.md.

════════════════════════════════════════════════════════════════
0. İŞE YARAMA ŞARTI (HER ŞEYİN ÜSTÜNDE)
════════════════════════════════════════════════════════════════
Çıktı GERÇEKTEN çalışan, işe yarar bir şey olacak. "test yeşil / gösterdim /
kaydettim / özet" = ÇIKTI DEĞİL. Ölçü: Damla'nın parmakla gösterebileceği tek
cümle — "rabadon, agent'ımın DERİN ve ufak bir bozulmasını, ben fark etmeden,
olduğu AN yakaladı, tamir etti, ve bana Langfuse gibi detaylı raporladı; 10.
adım rezil olmadı, param+zamanım cepte."
KOLAY YOLA KAÇMAK YASAK: dashboard, observe-only, cost/token raporu TEK BAŞINA,
lens genişletme, iç refactor, JS→native port. Ürün TEK şey:
YAKALA + TAMİR ET + TAMİRİ KANITLA + Langfuse-grade RAPORLA.

════════════════════════════════════════════════════════════════
1. İLK 10 DAKİKA (yap, atlama)
════════════════════════════════════════════════════════════════
Üç proof'u KOŞ, gözünle gör (hepsi izole spool, Damla'nın ledger'ını kirletmez):
  • ./native/repair_proof.sh        — scripted moat (honest REPAIR_OK / cheat REPAIR_FAIL)
  • ./native/repair_proof_llm.sh    — GERÇEK claude -p toy bug'ı kapatır (REPAIR_OK, ~21s)
  • ./native/regression_net_demo.sh — STEP C: gerçek modül + derin off-by-one, ağ
      check 5/6'da yakalar, canlı claude -p tamir eder, sahte fix forbidden-sha ile red
OKU: native/loop.cpp (runner+repair) · native/verify.cpp (hakem: testsuite/
differential/forbidden/cmd/fileExists/fileContains) · native/gate.cpp (hep-açık
yüzey + default-off + --statusline/--on/--off/--toggle) · native/drift.cpp ·
native/usage.h (byte-exact token/$ metre) · native/llm-proposer.sh (bounded claude -p).

════════════════════════════════════════════════════════════════
2. VİZYON (Damla'nın sözü — sapma yok)
════════════════════════════════════════════════════════════════
10 adımlık iş, aralarda kapılar. Bela büyük kapıda değil: 3. adımın 3.24'ünde —
KAPI OLMAYAN ufacık derin bir yer. rabadon o hatayı DOĞDUĞU AN yakalar, katlanmadan
tamir eder. Çözüm = HEP-AÇIK AĞ (her tool sonrası projenin VAR OLAN doğrularını koş)
+ DRIFT. "Her yere kapı koy" ÇÖZÜM DEĞİL. Dürüst sınır: hiçbir doğruyu kırmayan
tamamen sessiz hata deterministik yakalanamaz — ABARTMA.
KONUMLANMA: rabadon = Langfuse'un ÜSTKÜMESİ ("otonom agent koşuları için Sentry").
gör (SIFIR enstrümantasyon, transcript zaten diskte) + DURDUR + DÜZELT + "düzelttim
de". Moat = yolun içindeki DETERMİNİSTİK HAKEM (projenin GERÇEK testini koşar) —
LLM'i çıkar, hakem+gate+repair+ledger kalır.

════════════════════════════════════════════════════════════════
3. NE KANITLANDI (28-29.07 — tekrar keşfetme)
════════════════════════════════════════════════════════════════
• LENS + usage.h byte-exact metre bitti (tek başına cost tablosu = yanlış kapsam;
  metre fused raporun içinde yaşamalı).
• TAMİR DÖNGÜSÜ KAPANDI (repair_proof.sh, commit c5cfaec): honest→REPAIR_OK,
  cheat→forbidden-sha REPAIR_FAIL. Deterministik, LLM'siz.
• ADIM B (822e769): scripted proposer yerine GERÇEK claude -p — toy bug'ı kapattı,
  hakem gerçek testle kabul, REPAIR_OK. llm-proposer.sh = bounded (RABADON_OFF=1
  recursion guard, wall-clock cap).
• ADIM B2 (e22fdd1): proposer model biter bitmez sonlanıyor (stream-json terminal
  "result" event) — 181s→21s. Süre/maliyet profili artık dürüst (Step D için şart).
• ADIM C (64a10da): gerçek çok-fonksiyonlu modül (statslib) + moving_average'da
  KAPI-KONMAMIŞ off-by-one. Ağ = projenin KENDİ suite'i, check 5/6'da yakaladı
  (mean/variance/median yeşil). Canlı claude -p off-by-one'ı düzeltti (REPAIR_OK);
  sahte fix (testi neuter) forbidden-sha ile REDDEDİLDİ, fail-closed (maskelenmedi).
• DEFAULT-OFF + LAMBA (7ca5f10, 811c0dd, 6615797): rabadon artık DEFAULT KAPALI.
  Global hook'lar duruyor ama ~/.rabadon/enabled yoksa gate dormant. Toggle native:
  `rabadon` (veya prompt'ta `!rabadon`) = çevir; `rabadon status/on/off/stats`.
  /opt/homebrew/bin/rabadon symlink native wrapper'a (rabadon-cli.sh) taşındı,
  watch/do/fleet hâlâ mjs'e delege. Status line native --statusline: AÇIK=lila
  `* rabadon`, KAPALI=gri `* rabadon off` — lamba artık gerçek state'i gösterir.

════════════════════════════════════════════════════════════════
4. ADIM D BİTTİ (29.07) — Langfuse-grade RAPOR renderer CANLI
════════════════════════════════════════════════════════════════
• `native/trace.cpp` → `rabadon-trace` (C++, zero-dep). İzole spool jsonl'i
  (RUN_START/STEP_START/CHECK_FAIL/REPAIR_START/REPAIR_OK|FAIL/STOP/STEP_OK/
  RUN_DONE) → iç içe trace. Run başına blok, N adım, yakalanan adım altında
  catch→repair→proof (veya cheat→forbidden-sha→REPAIR_FAIL→STOP) alt-satırları,
  footer (YAKALANAN/TAMİR/REDDEDİLEN + "kurtarılan" değer satırı). Renk tty'de,
  --no-color dosyaya. LLM ÇAĞIRMAZ — saf sunum, moat testi geçer.
• token/$ FÜZYONU byte-exact: llm-proposer.sh, claude -p'nin stream-json terminal
  {"type":"result"} event'ini ($.total_cost_usd, usage.*_tokens, duration_ms,
  modelUsage-key=model) sidecar'a yazar → loop.cpp REPAIR_OK/FAIL event'ine gömer.
  Spool artık kendi kendine yeten deterministik ledger; renderer transcript
  avlamaz. Uydurma sayı YOK (metrik yoksa "—"). cheat scripted → metriksiz (doğru).
• GERÇEK KANIT: `native/trace_demo.sh` (5 adımlık pipeline, bug adım 3'te gömülü,
  adım 4 tamire bağımlı). honest: canlı claude -p off-by-one'ı tamir → adım 4–5
  temiz tabanda → PASS (opus-4-8, ~216k tok, ~$0.36). cheat: forbidden-sha reddi →
  STOP adım 3 → adım 4–5 HİÇ koşmadı. İkisi de trace'te render. `rabadon trace`
  artık CLI komutu (rabadon-cli.sh). regression_net_demo.sh de trace ile biter.

SIRADAKİ AÇIK UÇLAR (Damla onayıyla):
  (a) serbest SESSION spool'u (~/.rabadon/spool ng-* runs) için tool-call zaman
      çizgisi görünümü — şu an loop-run vokabülerine göre çiziliyor; session
      runs render olur ama hepsi "pass" görünür (catch/fix yok). Ayrı görünüm mü?
  (b) trace'i landing/demo'ya koy (GTM: Damla haftaya yatırım arıyor, §6). PNG/asciinema.
  (c) çok-tamir (attempt>1) ve çok-adım-yakalama görünümü (şu an 1 repair/step demo).
Her adım max 90dk/3 repair → DUR, çıktıyı Damla'ya göster, ONAY bekle. Commit+push.

════════════════════════════════════════════════════════════════
5. KURALLAR / TUZAKLAR
════════════════════════════════════════════════════════════════
• DEFAULT = PROPOSE-and-hold, silent-apply DEĞİL (GTM riski #1). Hakem gerçek testi
  geçirdiyse uygula; şüpheliyse öner+beklet. Hassasiyet = public benchmark.
• claude -p BOUNDED: child'da RABADON_OFF=1 (recursion), wall-clock cap, spool İZOLE
  (RABADON_DIR=temp). Askıda/gece-boyu koşma YOK. NOT: --allowedTools child'ı GERÇEKTEN
  kısıtlamıyor (B2'de Bash kullandı) — sahte fix'i durduran hakem, tool kısıtı değil.
• bin/rabadon.mjs anti-path — DOKUNMA (sadece rabadon-cli.sh üzerinden delege).
  index.html DAMLA ONAYLI — DOKUNMA. lens/usage.h metre işine GERİ DÖNME.
• promise areas = ^native/ ^Makefile$ ^SPEC.md$ ^README.md$. native/'te kal.
• rabadon şu an DEFAULT KAPALI; geliştirirken açmak istersen `rabadon on`.
• Bitince commit+push (lowercase İng, co-author ASLA).

════════════════════════════════════════════════════════════════
6. GTM (Damla haftaya yatırım arıyor)
════════════════════════════════════════════════════════════════
FİYAT = "doğrulanmış tamir" başına (hakem geçişi = kandırılamaz birim). Konumlanma =
"agent koşuları için Sentry", asla observability. Rakip: Sentry Seer (deterministik
hakem yok). HEDEF SORUSU (session başında cevapla): rabadon neden var? → gözetimsiz
otonom agent koşarken KAPI-KONMAMIŞ derin hatayı katlanmadan YAKALAYIP TAMİR eden ve
tamiri deterministik KANITLAYAN + Langfuse-grade RAPORLAYAN sistem.
