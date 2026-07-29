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

════════════════════════════════════════════════════════════════
7. YENİ YÖN — İKİNCİ YÜZ: DOĞRULANMIŞ UCUZLATMA (Damla emri 29.07 gece)
════════════════════════════════════════════════════════════════
DAMLA İSTİYOR, tartışma kapandı: maliyeti gerçekten DÜŞÜREN motor yazılacak.
ŞEKİL (Damla onayladı): ayrı ürün/repo DEĞİL — rabadon'ın İKİNCİ YÜZÜ, aynı
verify.cpp hakem motoru. Tek platform iki surface:
  yüz 1 (var):  yakala → tamir et → KANITLA          (güvenilirlik)
  yüz 2 (yeni): ucuza düşür → KANITLA → yükselt      (maliyet)
FARK (Helicone/Portkey/OpenRouter/Martian bunu YAPAMAZ): onlar ucuza yönlendirip
UMUT eder, correctness oracle'ları yok. rabadon'da deterministik hakem var →
her ucuz cevabı contract'tan geçirir, geçmezse OTOMATİK pahalı modele yükseltir.
Kategori: "provably-safe cost reduction / VERIFIED ROUTING". Wrapper testi geçer:
LLM'i çıkar → ucuz-mu-pahalı-mı kararını veren deterministik hakem kalır.
İLK KANIT (aylar değil, GÜNLER — Step D disiplini): plan haiku'da koşar, hakem her
adımı doğrular, haiku'nun çuvalladığı adım opus'a yükselir, trace şunu gösterir:
"N adım ucuzda geçti+KANITLANDI, $X cebe, 1 doğrulanıp yükseltildi." Kanıt tutarsa
tam motora (cache/routing/sıkıştırma) yatırılır. loop.cpp zaten koştur→doğrula→
yükselt(repair) şekli; "yükselt = daha iyi model" birebir aynı iskelet.
İSİM: DÜŞTÜ. Ayrı ürün olmayınca ayrı marka gerekmiyor (Damla 29.07: "ayrı
yapmayalım demiştik"). Ayrı repo/binary YOK — aynı loop, aynı hakem, aynı trace.
LoL adı istenirse sadece trace'teki yükseltme satırının etiketi olur (kozmetik).

DURUM 29.07 — YÜZ 2 ÇALIŞIYOR VE ÖLÇÜLDÜ (commit dd58df6):
• loop.cpp: RABADON_TIERS="haiku,opus" → her work adımı önce ucuzda koşar, aynı
  verify.cpp hakemi karar verir, RED olursa ESCALATE ile üst tier aynı adımı
  tekrarlar. Repair = en üst tier'da (tamir zaten bir yükseltmedir). Değişken
  boşsa eski davranış birebir korunur. Yeni event'ler: STEP_TRY / ESCALATE +
  STEP_OK'ta hangi tier taşıdı. RUN_START'ta arm=routed|control.
• llm-proposer.sh: RABADON_MODEL → claude -p --model. Metrikler artık HER
  proposer çağrısında sidecar'dan füzyonlanıyor (sadece repair'de değil).
• trace.cpp: routed görünüm + ÖLÇÜLEN A/B bloğu. İki kol da spool'daysa fark
  basılır; routing kaybederse "PAHALIYA geldi" yazar; ölçüm yoksa (scripted
  proposer) para iddiası YAPILMAZ; tek kol varsa karşılaştırma basılmaz.
• Testler: loop_test 11/11 (yükseltme LLM'siz kanıtlı), route_test 9/9 (yeni,
  A/B aritmetiği + kayıp senaryosu + yarım-ölçüm koruması). make test tamamı yeşil.
• AYRICA (ae9694c): repo testlerinin 32'si default-off commit'inden beri sessizce
  kırıktı — gate uykudayken ölçüyorlardı. Testler hermetik HOME'a alındı.
• CANLI KANIT (native/route_demo.sh, ham çıktı: reports/2026-07-29-rabadon-
  verified-routing.txt): aynı plan iki kez koştu, $ değerleri modelin kendi
  total_cost_usd'sinden. control(opus) $1.6933 · routed(haiku,opus) $0.2758 →
  $1.4175 cepte (%84), iki kol da PASS. Adalet: routed ÖNCE koşar, prompt cache
  avantajı kontrol koluna gider (yani sayı bir TABAN).
AÇIK/DÜRÜST BOŞLUK: bu canlı koşuda haiku 5/5 geçti → YÜKSELTME CANLI TETİKLENMEDİ.
Yükseltme yolu deterministik (loop_test) ve kuru provada kanıtlı, canlı değil.
Kurgulayarak haiku'yu düşürmek YASAK; gerçekten zor bir spec ile ikinci koşu
(~$2) yapılacaksa Damla'ya maliyeti söylenip onay alınır. N=1: bu bir workload,
henüz benchmark değil — %84'ü genel iddia olarak satma.
AYRI TUTULACAK (bu işe karıştırma): "$X israf yakalandı" waste-detector
(runaway loop / gereksiz re-run) = SONRAKİ ayrı ürün, Damla öyle dedi.

REDDEDİLEN YÖNLER (dış LLM tavsiyesi, Damla ile konuşuldu — geri açma):
• "Teknikten anlamayan no-code wrapper kurucusuna sat" → o müşteride test/repo/
  otonom agent YOK, hakem koşacak bir şey bulamaz, moat görünmez. HAYIR.
• "Maliyeti yarıya indir" TEK BAŞINA pitch → metre gösterir, düşürmez; yapmadığını
  satmak olur (§1). Maliyet = KAPI (wedge), moat'ın SONUCU; tek başına ürün değil.
• Müşteri promptlarını/iş modelini gizlice madenlemek ("spyware boyutu"), rehin
  lock-in ($299 şoku), müşteri loglarıyla rakip rezil etme post-mortem'i →
  KVKK/GDPR + dava + güven imhası. AI-infra'da para birimi GÜVEN. HAYIR.
• Alınan doğru çekirdekler: güvenlik/bodyguard tonu (yapmadığını satmadan),
  cömert freemium (ihanetsiz), arms-dealer YC tezi (hakaretsiz).
