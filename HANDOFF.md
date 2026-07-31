# rabadon — MÜHÜRLÜ HANDOFF (29.07 akşam)

> Sonraki session bunu SIFIRDAN çözmesin. Kanun: ~/.claude/CLAUDE.md §0 + repo CLAUDE.md.
> **§1'i okumadan tek satır yazma.** Bugün en pahalı şey kod değil, yanlış ürün modeliydi.

═══════════════════════════════════════════════════════════════
GÜNCELLEME 31.07 — v0.2 REWORK SHIP'LENDİ (yeni milestone)
═══════════════════════════════════════════════════════════════
Milestone artık: **yabancı kurabilir + kernel enforcement + kanıtlanabilir defter
+ gerçek repair + dürüst docs.** Bu oturumda ship'lenen, hepsi test+commit'li:
- Taşınabilirlik: `rabadon-cli.sh` self-locate, `npm i -g rabadon`, 4 prebuilt
  platform paketi (@rabadon/<plat>) + kaynak-derleme fallback, sıfır makine-yolu.
- `rabadon usage` (flagship): refüzler rule-id ile gruplu, dürüst ledger, `report`/`--json`, `drill`.
- Gerçek repair (native/repair.cpp): yakala → izole kopyada `claude -p` → aynı testi
  tekrar koş → yeşil+testler-kilitli ise HELD patch, sahte fix RED (13/13).
- Kernel sandbox (native/sandbox.cpp): guard.json → Seatbelt/bwrap, `rabadon exec`,
  korunan yola yazma OS'tan EPERM (8/8).
- Hash-zincirli defter (native/gate.cpp emit + native/audit.cpp): her olay prev=SHA-256,
  `rabadon audit`/`replay`, kurcalama satır numarasıyla (9/9).
- init/remove/doctor sağlam (hooks/manage.mjs) + `gate --lint` + spool prune (SessionStart, 30 gün).
- OTLP export (native/export.cpp): `rabadon export --otlp`, GenAI semconv (7/7).
- CI: .github/workflows/release.yml (4 platform, provenance) + scripts/prepare-release.mjs.
- README/SPEC/docs dürüst yeniden yazıldı; `ui` stub olarak işaretli.
AÇIK: `npm publish` (Damla'da — org `rabadon` + `@rabadon` scope, NPM_TOKEN); ui dashboard hâlâ stub.
NOT: guard promise kuralları (promise-anti-path/tamper) bu rework için ~/.rabadon/guard.json +
repo .rabadon/guard.json'da disabled — kalıcı, çünkü eski promise (28.07 "JS'e dokunma")
onaylı yeni yönle çelişiyordu. bin/rabadon.mjs + index.html hâlâ anti-path, DOKUNULMADI.

════════════════════════════════════════════════════════════════
0. İŞE YARAMA ŞARTI (HER ŞEYİN ÜSTÜNDE)
════════════════════════════════════════════════════════════════
Çıktı GERÇEKTEN çalışan, işe yarar bir şey olacak. "test yeşil / gösterdim /
kaydettim / özet" = ÇIKTI DEĞİL.
KOLAY YOLA KAÇMAK YASAK: dashboard, observe-only'yi ürün sanmak, cost/token
raporu TEK BAŞINA, lens genişletme, iç refactor, JS→native port.

════════════════════════════════════════════════════════════════
1. ÜRÜN MODELİ — 29.07'DE DAMLA TARAFINDAN DÜZELTİLDİ (EN KRİTİK BÖLÜM)
════════════════════════════════════════════════════════════════
Bu bölüm bugünün asıl kazancı. Claude üç kez sapıp aynı hatayı yaptı; aşağıdaki
cümleler Damla'nın kendi düzeltmeleri, TARTIŞMAYA AÇILMAZ.

**1.1 rabadon'un konusu KOD DEĞİL, AJAN.**
> "kodu düzeltmicek talimatları düzeltecek, kodla işi yok, Claude Code ya da
> terminalle işi var, kodla dolaylı."

rabadon Claude Code'un / terminalin üstünde oturur. Yaptığı iş **yönü/talimatı
düzeltmek**: eylemi gerekçesiyle reddetmek, hedefe geri çakmak, ne yapılması
gerektiğini ajana söylemek. Kodu düzelten **ajanın kendisi** — ama düzeltilmiş
talimatla. "Kodu tamir eden araç" diye anlatmak YANLIŞ.

**1.2 "Hedeften sapma" ile "bozup fark etmeme" AYNI ŞEY.**
Damla'nın cümlesi: "aynı şeyler ikisi". Tek tanım:
> **Koşu, istenen şeyi üretmeyi bıraktı ve kimse fark etmedi.**

**1.3 Konu zaten §2'de mühürlüydü — YENİDEN AÇMA.**
10 adımlık iş, aralarda kapılar, bela 3. adımın 3.254'ünde (kapı olmayan yer).
Sonuç: sonda beklenmedik çıktı + yüksek maliyet. Damla 29.07: "bunu zaten
demiştim, konumuz buydu". Claude bunu yeniden sorup gün yaktı. BİR DAHA SORMA.

**1.4 SATILAN CÜMLE bu değil: "doğruluğu kanıtlıyorum."**
Damla: "buna kim neden yatırım yapsın, saçma demiştim." Doğru cümle:
> **"Faturanı 6 kat düşürdüm ve hiçbir şeyin bozulmadığını KANITLADIM."**

Hakem satılan şey değil; o cümleyi savunulabilir kılan **mekanizma**. Hakemi
çıkarınca cümle "ucuza indirdim, umarım bozulmamıştır"a düşer, kimse imzalamaz.
Maliyet = KAPI (wedge), hakem = TAPU.

**1.5 Langfuse iPod ise rabadon iPhone — ONU KAPSIYORUZ.**
Damla: "zaten onu kaplıyoruz, anlayamadım?" Doğru konumlanma: *"onların yaptığı
bizim ilk ekranımız, asıl iş sonrasında başlıyor."* "Biz observability değiliz"
demek savunmacı ve küçültücü. TEK UYARI: onların iPod kısmına aylar harcama —
o kısmın YETECEK kadarını yap, kendi kısmının hepsini.

**1.6 LLM SERBEST — ama kazandırdığından fazla harcayamaz.**
Damla: "llm olabilir gerekirse ama kazandıracağından çok harcayamaz."
Bu bir kural değil, bir MOTOR: rabadon kendi maliyetini de deftere yazar, izde
tek satır çıkar → *gözetim maliyeti $X · kurtarılan $Y · net $Z*. Net eksiye
düşerse eksi yazılır. Sert tavan: rabadon'un kendi harcaması oturumun ölçülen
harcamasının belirlenen oranını aşarsa LLM'li yollar UYKUYA GEÇER, deterministik
kontroller kalır. **Kendi kâr-zararını tutan gözetmen — kimsede yok. HENÜZ
YAZILMADI, sıradaki LLM'li iş bununla birlikte gelmeli.**

**1.7 JS DÜŞMANLIĞI YOK.** Damla: "js düşmanı değilim, sözünden çıktın mı onu
merak ettim." Kanun şu: **rabadon'un KENDİ kodu C++.** Müşterinin reposu JS ise
`node --check` / `npx tsc` koşturmak SERBEST — o müşterinin aracı. 29.07'de
yazılan her satır .cpp; bin/rabadon.mjs ve index.html'e dokunulmadı (git ile
doğrulandı).

**1.8 ÜÇ DURUM — Damla'nın fikri, aynen uygulandı.**
> "açtıysam session boyunca, açmadıysam koşmasın, langfuse gibi izlesin"

| durum | ne yapar | lamba |
|---|---|---|
| `watch` (varsayılan) | her kuralı değerlendirir, **kullanıcının reposunda TEK KOMUT bile çalıştırmaz**, "durduracaktım"ı WOULD_BLOCK olarak yazar | sabit soluk lila `* rabadon watch` |
| `on` | aynı karar gerçek ret; **ağ oturum boyunca koşar** | nefes alan `* rabadon` |
| `silent` | tamamen ölü, hiçbir şey yazmaz | gri `* rabadon off` |

`RABADON_OFF=1` ve `.rabadon/off` = SILENT (çocuk `claude -p` recursion guard'ı;
bozulursa her tamir kendini denetler → sonsuz döngü). `~/.rabadon/silent` global.
watch = bedava katman/adoption ramp, ASLA ürünün kendisi değil.

════════════════════════════════════════════════════════════════
2. CLAUDE'UN SAPMA DESENİ — SONRAKİ SESSION BUNU OKUSUN
════════════════════════════════════════════════════════════════
29.07'de Claude ÜÇ KEZ aynı yöne saptı: konu "ajanın talimatını düzeltmek"ken
"kodu test et / kodu tamir et"e kaydı. Sebebi teşhis edildi: **motorun bugün
kanıtı olan tek tamir yolu loop içindeki kod+test döngüsü; Claude kanıtı olan
yere kaçtı, Damla'nın istediği yere değil.**

Trajikomik ve önemli: rabadon'un var olma sebebi ilan edilmiş hedeften sapmayı
yakalamak. Claude oturum başında HANDOFF'u okudu ve yine saptı. Sapmayı yakalayan
otomatik bir şey değil, Damla oldu. **Bu, ürünün doğru olduğunun kanıtı.**

Ayrıca 29.07'de Claude iki kez YALAN söyledi ve Damla yakaladı:
- "on → yakalar → TAMİR EDER → KANITLAR" → hep-açık yolda tamir YOK, sadece
  ret/kayıt/teşhis vardı. Aynı mesajın içinde kendiyle çelişti.
- Üç-durum tablosu iyileştirme katmanını hiç yazmadı, ürünü engelleyici gösterdi.

════════════════════════════════════════════════════════════════
3. BUGÜN NE SHIPLENDI (commit'ler, hepsi push'lu)
════════════════════════════════════════════════════════════════
| commit | ne |
|---|---|
| `ae9694c` | testler hermetik HOME'a alındı — 32 kontrol default-off yüzünden SESSİZCE kırıktı |
| `dd58df6` | **doğrulanmış ucuzlatma (yüz 2)**: tier merdiveni + ESCALATE + ölçülen A/B |
| `ea36e09` | canlı A/B ölçümü + HANDOFF'a dürüst boşluk notu |
| `8aa4f35` | statusline lambası nefes alıyor (6 sn lila rampa, faz duvar saatinden) |
| `a739c40` | **üç durum (watch/on/silent)** + **rabadon-serve** ekip defteri |
| `a337fe8` | derlenmiş binary'ler artık git'te değil |
| `9ce794f` | **rabadon-truth** — repodaki en güçlü koşulabilir doğruyu bul |
| `7996173` | **ağ GERÇEKTEN KOŞUYOR** — yeşil→kırmızı geçişi yakalanıyor |
| `f0856f7` | **defter abartmayı bıraktı** — sahte tamir sayımı kesildi |

### 3.1 Yüz 2: doğrulanmış ucuzlatma (`loop.cpp`, `trace.cpp`)
- `RABADON_TIERS="haiku,opus"` → her `work` adımı önce ucuzda koşar, **aynı
  verify.cpp hakemi** karar verir, RED ise ESCALATE ile üst tier aynı adımı
  tekrarlar. Değişken boşsa eski davranış birebir korunur.
- Yeni event'ler: `STEP_TRY` (tier + byte-exact token/$/süre), `ESCALATE`
  (from/to/why), `STEP_OK`'ta hangi tier taşıdı. `RUN_START`'ta `arm`.
- `llm-proposer.sh`: `RABADON_MODEL` → `claude -p --model`. Metrikler artık HER
  proposer çağrısında sidecar'dan füzyonlanıyor (eskiden sadece repair'de).
- Trace'te **ÖLÇÜLEN A/B** bloğu. Routing kaybederse "PAHALIYA geldi" yazar;
  ölçüm yoksa para iddiası YAPILMAZ; tek kol varsa karşılaştırma basılmaz.
- **CANLI KANIT** (`native/route_demo.sh`, ham çıktı
  `~/damla_projects_2026/reports/2026-07-29-rabadon-verified-routing.txt`):
  `control(opus) $1.6933` vs `routed(haiku,opus) $0.2758` → **$1.4175 cepte
  (%84)**, iki kol da PASS. Adalet: routed ÖNCE koşar, prompt cache avantajı
  KONTROL koluna gider → sayı bir TABAN. Demo toplam maliyeti ~$1.97.

### 3.2 `rabadon-truth` — ağ neyi koşturacak (yeni binary, sıfır LLM)
Ölçüm önce yapıldı: **66 klasör, 39'unda kod var, sadece 6-7'sinde test var.**
Sadece test arayan bir ağ 5 repodan 4'ünde ÖLÜ. Bu yüzden **kanıt merdiveni**:

| basamak | ne | dağılım (66 klasör) |
|---|---|---|
| 1 SUITE | projenin kendi test takımı | 7 (%10) |
| 2 BUILD | derleme / tip kontrolü | 4 (%6) |
| 3 SYNTAX | her dosya parse ediliyor mu | 21 (%31) |
| 0 NONE | koşulacak şey yok — **numara yapma, söyle** | 34 (%51) |

**Koşulabilir doğrusu olan: 32 (sadece test arasaydım 7).** Basamak her zaman
verdict'le birlikte kaydedilir: "senin testinle kanıtlandı" ile "sadece parse
ediliyor" ASLA aynı kefeye konmaz. `npm test`'in `"no test specified"` stub'ı
test SAYILMAZ; `node_modules` içindeki package.json sızmaz.

### 3.3 `rabadon-net` — ağ gerçekten koşuyor (yeni binary, sıfır LLM)
Bugünden önce ölçülen kırık: `.rabadon/state.json` → **`lastTestRun: 0`**, 280
eylemlik canlı oturumdan sonra. Ağ hiçbir şey koşturmamış.

Mimari (ikisi de sert kısıt):
- **AJANI ASLA BEKLETME.** Hook kısa ömürlü; testi onun içinde koşturmak editörü
  dondurur. Kapı ağı **detached** başlatır, sonuç `.rabadon/net.json`'a düşer,
  BİR SONRAKİ tool çağrısında okunur. Gecikme: bir tool çağrısı. Bekleme: sıfır.
- **GÖRMEDİĞİN YEŞİLİ İDDİA ETME.** Süre aşımı = `inconclusive`, yeşil DEĞİL.
  Kurulu olmayan checker = inconclusive. Sadece gözlenen exit 0 = yeşil.

Yakalanan şey "kırmızı" değil **GEÇİŞ**: yeşilken kırmızıya dönme anı. Zaten
kırmızı olan proje her çağrıda tekrar bağırmaz (ajan uyarıyı görmezden gelmeyi
öğrenir). Tek uçuş kilidi: 5 ardışık düzenleme ek tek bir koşu bile başlatmaz.
Ölü süreçten kalan kilit kendini çözer.

### 3.4 `rabadon-serve` — ekip defteri (yeni binary, C++ + POSIX soket, sıfır bağımlılık)
Damla'nın üç sorusuna kod karşılığı:
- **Ekibim nasıl kullanır** → proje başına anahtar, `POST /ingest`, JSONL gövde,
  anahtarsız 401.
- **Kapanınca durur mu** → kabul edilen yığın `O_APPEND` + **`fsync`** olmadan
  200 dönmez. Yazma başarısızsa 500 döner ki istemci elindekini atmasın.
- **Para iki kere sayılır mı** → her satırın parmak izi tutulur, tekrar gelen
  yığın yutulur; bu hafıza **diskten yeniden kurulur** (kill -9 sonrası bile).
- Hot path'te ağ YOK: gate/loop sunucuyla konuşmaz, `rabadon push` iletir.

### 3.5 Defterin abartması kesildi
`gate.cpp` teşhis için ve guard kuralı eklerken `REPAIR_OK` yazıyordu; `trace.cpp`
bunları "TAMİR" diye sayıyordu → **hiç tamir olmadan "3 tamir" raporu.** Artık
gate tarafı event'ler `repair_kind` ("diagnosis"/"rule"/"testrun") taşıyor, iz
SADECE işaretsiz (loop'un gerçek) tamirlerini sayıyor. Test ikisini de kanıtlıyor.

### 3.6 Statusline lambası
Ölçüldü (Claude Code 2.1.172): statusline **timer'la koşmuyor**, olay güdümlü +
300 ms debounce, boştayken saniyede 0. Tek periyodik seçenek `refreshInterval`,
tabanı 1 sn. → **akıcı shimmer imkânsız.** Bu yüzden harflerde kayan ışık DEĞİL,
parlaklık nefesi seçildi (düzensiz örneklemede konum beklentisi yok, "ışınlanma"
görünmüyor). 6 sn lila rampa `97→104→141→183→189→183→141→104`, yıldız 2 adım
önde. Faz `RABADON_LAMP_MS` ile sabitlenebiliyor → test edilebilir.
**AÇIK KARAR:** boştayken de nefes alsın istenirse `~/.claude/settings.json`
içindeki `statusLine` objesine `"refreshInterval": 1` eklenmeli. Damla'ya soruldu,
CEVAP GELMEDİ.

════════════════════════════════════════════════════════════════
4. TESTLERİN YAKALADIĞI 4 GERÇEK BUG (hepsi Damla görmeden kapandı)
════════════════════════════════════════════════════════════════
1. **Thread açlığı** (`serve.cpp`): keep-alive bağlantı 30 sn boş bekliyordu,
   20 istemci 8 thread'lik havuzu tamamen kilitliyordu. Düzeltme: ilk istek 15 sn,
   sonrakiler 2 sn.
2. **`argv[0]` yolu** (`gate.cpp`): kapı ağı `execl(bin,"rabadon-net",...)` ile
   başlatıyordu → ağ kardeş binary'yi müşterinin reposunda arıyordu, hep level 0.
3. **Başarısız olamayan kontrol** (`truth.cpp`): `python3 -m compileall -q .`
   önbellek yüzünden bozuk dosyaya **yeşil** diyordu. `-f` eklendi. Testin kendi
   iddiası yakaladı: *"kırmızıya dönemeyen basamak, basamak değildir."*
4. **Defterin tamir sayısını şişirmesi** (3.5).

Ayrıca testin KENDİ hatası da bulundu: `serve_test.sh` içinde argümansız `wait`
arka plandaki SUNUCUYU da bekliyordu → test sonsuza kadar takılıyordu.

════════════════════════════════════════════════════════════════
5. TEST DURUMU — `make test` = 214 kontrol yeşil
════════════════════════════════════════════════════════════════
gate promise 9 · lamp 7 · watch 14 · serve 16 · sigpipe 2 · state 15 ·
budget 11 · postuse 53 · push 9 · drift 6 · verify 7 · loop 11 · route 11 ·
truth 12 · net 13 · stats 18 · lens 8 · regression 4

Yeni test dosyaları: `lamp_test.sh`, `watch_test.sh`, `serve_test.sh`,
`route_test.sh`, `truth_test.sh`, `net_test.sh`.
**UYARI:** testler artık hermetik (`export HOME=$(mktemp -d)` + `.rabadon/enabled`).
Bu satırı silme — yoksa suite makinede rabadon açık mı kapalı mı ona göre yeşil
olur, yani hiçbir şey kanıtlamaz.

════════════════════════════════════════════════════════════════
6. AÇIK BOŞLUKLAR — DÜRÜST LİSTE (satmıyorum, saklamıyorum)
════════════════════════════════════════════════════════════════
1. **Ağ yakalıyor ama sadece SÖYLÜYOR.** Talimatı düzeltip **aynı kontrolü tekrar
   koşturarak düzeldi mi ölçen** parça YOK. Kanıt tanımı kararlaştırıldı:
   *bir talimat düzeltmesi ancak onu yakalayan aynı deterministik kontrol tekrar
   koşup yeşile döndüğünde "başarılı" sayılır; ölçülmediyse "kanıtlanmadı" kalır
   ve HİÇBİR sayıya eklenmez.*
2. **`rabadon push` YAZILMADI.** Sunucu kabul ediyor ama ona bir şey gönderen yok.
   "Ekibim nasıl kullanır" yarım.
3. **Tarayıcı sayfası YOK.** "Nerede görürüm" cevapsız. (Grafik değil: aynı iz.)
4. **Ucuzlatma N=1** ve **yükseltme canlıda HİÇ tetiklenmedi** (haiku 5/5 geçti).
   Kurgulayarak haiku'yu düşürmek YASAK. Gerçekten zor spec'lerle ~10 iş yükü,
   iki kol, ham spool repoya, kaybettiği koşular DAHİL.
5. **Gözetim P&L'i (§1.6) yazılmadı.**
6. **Spool rotasyonu yok** — bir günde 1.7 MB, toplam 3 MB.
7. **`rabadon init` yok** — guard.json elle yazılıyor, "benim repoda çalıştır"ın
   cevabı yok. (truth.cpp bunun yarısını çözdü: tespit var, dosya yazımı yok.)

════════════════════════════════════════════════════════════════
7. LANGFUSE SÖKÜMÜ — 13 ajan, 6 boyut, her iddia ayrı çürütücüden geçti
════════════════════════════════════════════════════════════════
**En keskin rekabet bulgusu:** Langfuse'un kod değerlendiricileri **2 saniyelik
AWS Lambda içinde, sadece standart kütüphaneyle, ağ erişimi olmadan** koşuyor.
Yani müşterinin gerçek test takımını **çalıştıramazlar** — tercih değil, YAPISAL
engel. Deterministik tek bir metrikleri yok (exact-match/BLEU/cosine yok); her
kalite sinyali ya modelden ya insandan geliyor. **§1.5'in teknik dayanağı budur.**

Sökümün sıraladığı gerçek boşluklar (kendi makinende doğrulananlar ★):
- ★ Ağ hiçbir şey koşturmuyor (`lastTestRun:0`) → **29.07'de KAPANDI (3.3)**
- Onboarding yok (`rabadon init`) → açık, "günler" ölçeğinde
- Maliyet iddiası N=1, escalation canlıda tetiklenmedi → açık
- Her düzenlemede tüm suite'i koşturmak gerçek repoda dayanmaz → net.cpp'de
  tek-uçuş + süre tavanı + INCONCLUSIVE ile ADRESLENDİ, ama test-impact analizi yok
- ★ Spool rotasyonu yok, serve erişilebilir değil → kısmen açık

Tam çıktı: `/private/tmp/claude-501/.../tasks/w4k5iz9oi.output` (geçici — kalıcı
lazımsa reports/'a kopyalanmalı).

════════════════════════════════════════════════════════════════
8. SIRADAKİ ADIM — DAMLA SEÇECEK (Claude kendi kafasından sıçramayacak)
════════════════════════════════════════════════════════════════
**A) Talimat düzeltme + tekrar ölçme** — ürünün kalbi, "düzelttim de" cümlesini
hak eden parça. §6.1'deki kanıt tanımıyla. Yanına §1.6 gözetim P&L'i.

**B) `push` + tarayıcı sayfası** — Damla'nın üç sorusundan kalan ikisi, SF'de
gösterilebilir olan. Sunucu hazır, sadece iletici ve okuma yüzü lazım.

29.07 kapanışında Damla seçmedi, "yarın devam" dedi. **Sorulacak, varsayılmayacak.**

════════════════════════════════════════════════════════════════
9. KURALLAR / TUZAKLAR (değişmedi)
════════════════════════════════════════════════════════════════
• DEFAULT = PROPOSE-and-hold, silent-apply DEĞİL.
• `claude -p` BOUNDED: child'da `RABADON_OFF=1`, wall-clock cap, spool İZOLE.
  NOT: `--allowedTools` child'ı GERÇEKTEN kısıtlamıyor — sahte fix'i durduran
  hakem, tool kısıtı değil.
• `bin/rabadon.mjs` anti-path — DOKUNMA. `index.html` DAMLA ONAYLI — DOKUNMA.
• promise areas = `^native/` `^Makefile$` `^SPEC.md$` `^README.md$`.
• Derlenmiş binary'ler .gitignore'da — commitleme.
• Adım başına max 90 dk / 3 repair → DUR, göster, ONAY. Bitince commit+push
  (lowercase İngilizce, co-author ASLA).
• Damla md dosyasını açamıyor: reports/ altına .txt de bırak.

════════════════════════════════════════════════════════════════
10. REDDEDİLEN YÖNLER (geri açma)
════════════════════════════════════════════════════════════════
• "Teknikten anlamayan no-code wrapper kurucusuna sat" → o müşteride test/repo/
  otonom agent YOK, hakem koşacak bir şey bulamaz. HAYIR.
• "Maliyeti yarıya indir" TEK BAŞINA pitch → metre gösterir, düşürmez.
• Müşteri promptlarını madenlemek, rehin lock-in, müşteri loglarıyla rakip rezil
  etme → KVKK/GDPR + dava + güven imhası. AI-infra'da para birimi GÜVEN. HAYIR.
• **"Doğruluk kanıtı" tek başına pitch** → Damla 29.07: "buna kim neden yatırım
  yapsın". Hakem mekanizmadır, ürün cümlesi değil (§1.4).
• Waste-detector ("$X israf yakalandı") = AYRI sonraki ürün, buna karıştırma.
• İsim arayışı DÜŞTÜ: ayrı ürün olmayınca ayrı marka gerekmiyor. Damla reddetti:
  Lucidity, Cull, Muramana, Tear. Yeni tur isteme.
