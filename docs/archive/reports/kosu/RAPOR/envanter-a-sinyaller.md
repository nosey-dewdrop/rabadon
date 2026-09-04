# envanter-a-sinyaller — hangi sinyal tanımlı, hangisi gerçekten çağrılıyor

Repo: `/Users/damummyphus/damla_projects_2026/rabadon-kosu4` (dal: kosu4)
Yöntem: yalnız statik okuma + `grep -n` / `sed -n`. Derlenmiş bir gate binary'si
makinede YOK (aşağıda ÖLÇÜLEMEDİ bölümü), dolayısıyla runtime kanıtı değil,
kaynak-zinciri kanıtı verilmiştir.

---

## 0. Sinyal üreten TÜM kod noktaları (tam liste)

Komut:
```
grep -rn 'out.push_back({ "' /Users/damummyphus/damla_projects_2026/rabadon-kosu4/native/*.h /Users/damummyphus/damla_projects_2026/rabadon-kosu4/native/*.cpp
```
Çıktı (aynen):
```
native/semantic.h:360:  out.push_back({ "semantic_repeat", conf, seqs,
native/signals.h:128:      out.push_back({ "repeat", 0.6, seqs,
native/signals.h:149:        out.push_back({ "oscillation", 0.7, seqs, "one file rewritten back and forth" });
native/signals.h:162:      out.push_back({ "root_migration", 0.75, seqs,
native/signals.h:172:      out.push_back({ "scope_drift", 0.4, { last.seq },
native/signals.h:182:      out.push_back({ "green_redefined", 0.85, { last.seq },
native/signals.h:203:        out.push_back({ "green_redefined", 0.9, seqs,
native/signals.h:214:        out.push_back({ "green_redefined", 0.8, { m[i].seq, last.seq },
```

Yani 6 farklı SİNYAL ADI var, 8 üretim noktasında (green_redefined'ın 3 kolu var):

| # | sinyal adı | tanım dosyası:satır | conf |
|---|---|---|---|
| 1 | `repeat` | native/signals.h:128 | 0.6 |
| 2 | `oscillation` | native/signals.h:149 | 0.7 |
| 3 | `root_migration` | native/signals.h:162 | 0.75 |
| 4 | `scope_drift` | native/signals.h:172 | 0.4 |
| 5 | `green_redefined` (a: kırmızıyken test edit) | native/signals.h:182 | 0.85 |
| 5 | `green_redefined` (b: red→green, sadece test tarafı) | native/signals.h:203 | 0.9 |
| 5 | `green_redefined` (c: assertion sayısı düştü) | native/signals.h:214 | 0.8 |
| 6 | `semantic_repeat` (tier 1) | native/semantic.h:360 | 0.5*mean |

`core/` altında hiçbir sinyal adı YOK. Komut:
```
grep -rn "repeat\|oscillation\|root_migration\|green_redefined\|scope_drift\|semantic_repeat\|SIGNAL" core/*.mjs | grep -v test
```
Çıktı: BOŞ (0 satır). → Sinyal mantığı tamamen native/ tarafında, JS core'da yok.

---

## 1. Çağrı zinciri — giriş noktasından detektöre

Tek giriş: `int main(int argc, char** argv)` — komut:
```
grep -n "int main" native/gate.cpp   ->  native/gate.cpp:2178
```

Zincir (her adım grep -n / sed -n ile doğrulandı):

```
native/gate.cpp:2178   int main(argc, argv)
  |
  v
native/gate.cpp:2642   const string hook = E.hook;                 # hook adı olay girdisinden
  |
  v
native/gate.cpp:2658-2661
      const char* offEnv = getenv("RABADON_OFF");
      if ((offEnv && string(offEnv)=="1") || file_exists(cwd+"/.rabadon/off")
          || file_exists(rhome+"/silent")) return 0;               # KAPI 0: SILENT
  |
  v
native/gate.cpp:2733-2734
      if (hook != "PreToolUse" && hook != "PostToolUse" && ... ) return 0;
  |
  v
native/gate.cpp:2876-2877                                          # KAPI 1: kayıt bloğu
      if (rbmoves::enabled() && (hook=="PreToolUse" || hook=="PostToolUse") &&
          (toolName=="Bash" || toolName=="Edit" || toolName=="Write" || toolName=="MultiEdit"))
  |
  +-- 2905  rbmoves::push(...)            # move kaydı
  +-- 2919-2934 (hook=="PostToolUse")  open_move->err_sig = rbmoves::err_sig(...)
  |
  v
native/gate.cpp:3161   if (rbsig::enabled()) {                      # KAPI 2: RABADON_SIGNALS
native/gate.cpp:3162     for (const auto& h : rbsig::detect(ms.moves)) {   # <== TIER 0 DETEKTÖR
native/gate.cpp:3166       em.emit("SIGNAL", ...)                     # ledger'a yazılır
native/gate.cpp:3171       queue_injection(h.name, h.why, h.seqs.size());
native/gate.cpp:3172       maybe_repair(h.name);
  |
  v
native/gate.cpp:3187   if (rbsig::enabled() && rbsem::enabled()) {  # KAPI 3: RABADON_SIGNALS + RABADON_SEM
native/gate.cpp:3188     rbsem::Loader fps(stt.fps_path());
native/gate.cpp:3189     for (const auto& h : rbsem::detect(ms.moves, fps)) {  # <== TIER 1 DETEKTÖR
native/gate.cpp:3196       em.emit("SIGNAL", ... "\"tier\":1" ...)
native/gate.cpp:3202       queue_injection(h.name, h.why, h.seqs.size());
```

Komut (tüm detect/build çağrı yerleri, repo geneli):
```
grep -rn "rbsig::detect\|rbsem::detect\|rbinject::build\|queue_injection\|maybe_repair" native/ core/
```
Çıktı: `rbsig::detect` yalnız gate.cpp:3162'de; `rbsem::detect` yalnız gate.cpp:3189'da;
`rbinject::build` yalnız gate.cpp:3018'de. Kaynak dosyalarda başka çağıran YOK
(diğer eşleşmeler yorum satırı ve signals_test.sh:456).

`rbsig::detect` tek bir fonksiyon (`native/signals.h:95`) ve altı sinyalin
5'inin kolu bu tek fonksiyonun gövdesinde inline. Yani ayrı bir "tespit fonksiyonu"
başına çağrı zinciri yok; kural blokları detect() içinde sırayla çalışır:
```
grep -n "inline vector<Hit> detect" native/signals.h  -> 95
```
Blok başlangıçları: `signals.h:102` (repeat), `:137` (oscillation), `:156`
(root_migration), `:167` (scope_drift), `:178` / `:188` / `:210` (green_redefined a/b/c).

**SONUÇ: 6 sinyalin 6'sı da GERÇEKTEN ÇAĞRILIYOR.** "Tanımlı ama çağrılmıyor"
kategorisinde sinyal YOK. Ama hepsinin ledger'dan öteye geçme yolu farklı — §3, §4.

---

## 2. Her sinyal için koşullar (bayrak / eşik / tool filtresi)

### Tüm sinyaller için ortak (zorunlu) kapılar
| kapı | konum | koşul |
|---|---|---|
| SILENT | gate.cpp:2658-2661 | `RABADON_OFF=1` VEYA `<cwd>/.rabadon/off` VEYA `~/.rabadon/silent` → `return 0`, hiçbir sinyal çalışmaz |
| hook filtresi | gate.cpp:2876 | sadece `PreToolUse` / `PostToolUse` |
| **tool filtresi** | gate.cpp:2877 | sadece `Bash`, `Edit`, `Write`, `MultiEdit`. Read/Grep/Glob/Task/MCP tool'ları hiç kayıt bile olmuyor |
| moves anahtarı | gate.cpp:2876 `rbmoves::enabled()` — tanım moves.h:86 | `RABADON_MOVES=0` → kapalı |
| signals anahtarı | gate.cpp:3161 `rbsig::enabled()` — tanım signals.h:63-66 | `RABADON_SIGNALS=0` → kapalı |

`rbsig::enabled()` gövdesi (signals.h:63):
```
const char* v = getenv("RABADON_SIGNALS");
return !(v && v[0]=='0' && v[1]=='\0');
```
→ varsayılan AÇIK, sadece tam "0" kapatır.

### Sinyal başına eşikler (signals.h:57-61, isimli sabitler)
```
grep -n "static const int" native/signals.h
57:static const int REPEAT_MIN = 3;
58:static const int REPEAT_WINDOW = 20;
59:static const int OSC_CYCLES = 3;
60:static const int ROOT_MIN_PATHS = 3;
61:static const int DRIFT_DIRS = 5;
```

| sinyal | ek koşul | satır |
|---|---|---|
| `repeat` | son 20 move içinde aynı `sig` >= 3 kez **VE** bunların >= 2'si `claimed_rc==1` (hata). Sadece sayı yetmiyor. | signals.h:105, 127 |
| `oscillation` | son move bir EDIT (`Edit/Write/MultiEdit`, signals.h:68-70) **ve** `path` boş değil; aynı path'te tam 6 (=`OSC_CYCLES*2`) edit; A-B-A-B-A-B sıkı dönüşüm | signals.h:137,139,141,145 |
| `root_migration` | `last.err_sig` boş değil (yani pratikte **PostToolUse**, çünkü err_sig orada set ediliyor — gate.cpp:2920) **ve** aynı err_sig'i taşıyan farklı `sig` sayısı >= 3 | signals.h:156,161 |
| `scope_drift` | son move EDIT **ve** oturumda edit edilen ayrı dizin sayısı >= 5 | signals.h:167,171 |
| `green_redefined` (a) | son move EDIT **ve** `decides_green(path)` (classify → TEST/HARNESS, signals.h:81-85) **ve** en son bilinen `suite == 0` | signals.h:178,180,181 |
| `green_redefined` (b) | `last.suite == 1`, geriye doğru bir `suite==0` bulunuyor, arada test/harness edit VAR ama SOURCE edit YOK | signals.h:188,191,201 |
| `green_redefined` (c) | son move EDIT + decides_green + `asserts >= 0`, aynı dosyanın bir önceki edit'inden assertion sayısı DÜŞMÜŞ | signals.h:210,213 |
| `semantic_repeat` | ek anahtar `rbsem::enabled()` = `RABADON_SEM != "0"` (semantic.h:112-115); `MIN_HITS=3`, `WINDOW=20`, Jaccard `THRESHOLD=0.80` (semantic.h:92-96); son move EDIT olmalı (semantic.h:318); **kaskad**: pencerede tier-0 hash eşleşmesi varsa `return out` — tier 1 hiç konuşmaz (semantic.h:328-329); fingerprint dosyada yoksa `return out` (semantic.h:331-332) | semantic.h |

`semantic_repeat` için fingerprint yazımı da koşullu:
```
gate.cpp:2912   if (!isBash && rbsem::enabled())
gate.cpp:2915     rbsem::store(stt.fps_path(), open_move->seq, rbsem::fingerprint(txt));
```
→ Bash move'ları için fingerprint hiç yazılmaz, dolayısıyla semantic_repeat yalnız dosya edit'lerinde mümkün.

---

## 3. INJECT yolu — gate'ten gerçekten çağrılıyor mu?

**EVET, çağrılıyor. İki parçalı: kuyruğa alma (PostToolUse dahil her tool olayında) + teslim (yalnız PreToolUse).**

### 3a. Kuyruğa alma
```
gate.cpp:2957   auto queue_injection = [&](name, why, nseqs) {
gate.cpp:2970     if (!rbinject::enabled() || !rbinject::speaks(name, why)) return;
gate.cpp:2985     if (seen && *seen >= rbinject::CAP_PER_SIGNAL) { emit("INJECT_CAPPED"); mark_mute(); return; }
gate.cpp:2994     if (!ms.injPending.empty()) { emit("INJECT_HELD"); ...; return; }
gate.cpp:3002     rbinject::Ctx c; ...
gate.cpp:3018     ms.injPending = rbinject::build(c);
gate.cpp:3019     ms.injPendingSignal = name;
gate.cpp:3020     injQueuedThisEvent = true;
```
Çağıranlar: `gate.cpp:3171` (tier 0) ve `gate.cpp:3202` (tier 1).

### 3b. Konuşma izni — `rbinject::speaks` (inject.h:81-87), TAM METİN
```
inline bool speaks(const string& name, const string& why) {
  if (name == "oscillation" || name == "root_migration" ||
      name == "semantic_repeat") return true;
  if (name == "green_redefined")
    return why.find("only the test side") != string::npos;
  return false;
}
```
Buradan çıkan kesin sonuç:
- `oscillation`, `root_migration`, `semantic_repeat` → INJECT eder.
- `green_redefined` → yalnız (b) kolu (`signals.h:203` "red turned green and only the test side changed") INJECT eder. (a) ve (c) kolları `return false` ile düşer.
- `repeat` → **ASLA inject etmez** (fonksiyonun son `return false`'una düşer). Sadece SIGNAL satırı olur. Gerekçe inject.h:69-75'te yazılı.
- `scope_drift` → **ASLA inject etmez**, aynı şekilde.

### 3c. Teslim — hookSpecificOutput / additionalContext
```
gate.cpp:4697   if (hook == "PreToolUse" && rbinject::enabled() && !ss.injPending.empty() &&
gate.cpp:4698       !injQueuedThisEvent) {
gate.cpp:4704-4706   (cap sayacı DELIVERY'de artırılıyor, detection'da değil)
gate.cpp:4707   printf("{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"%s\"}}\n", ...);
gate.cpp:4709   fflush(stdout);
gate.cpp:4724   em.emit("INJECT", "\"signal\":... ,\"chars\":..., \"mseq\":..., \"err\":..., \"text\":...");
```
Ulaşılabilirlik kanıtı: 4200 ile 4697 arasında düz bir `return 0;` YOK. Komut:
```
grep -n "^\s*return 0;\|^\s*exit(" native/gate.cpp | awk -F: '$1>3300 && $1<4700'
```
Çıktı: `3517 3540 3674 3691 3865 3976 4011 4094` (hepsi PostToolUse/UserPromptSubmit/SessionStart/SessionEnd/Stop dallarının içi) ve `4130 4143 4181` (yalnız `block()` lambda'sı ile budget-halt, yani refuse yolları). → PreToolUse akışı bloklanmadıysa 4697'ye VARIR.

`rbinject::enabled()` (inject.h:58-61): `RABADON_INJECT=0` → tüm inject yolu kapalı, hem kuyruk hem teslim.
`CAP_PER_SIGNAL = 2` (inject.h:56): aynı sinyal adı oturumda en fazla 2 kez inject edilir.
`MAX_CHARS = 400` (inject.h:50): `build()` sonunda `clip_chars(scrub(s), MAX_CHARS)` (inject.h:198).

### 3d. Gecikme kuralı (bir olay geç)
`injQueuedThisEvent` (gate.cpp:2875 tanım, 3020 set, 4698 kontrol) → aynı olayda kuyruğa alınan diagnoz o olayda TESLİM EDİLMEZ. Bir sonraki PreToolUse'a kalır.

---

## 4. Sinyalin bloklamaya dönüştüğü tek yer (inject dışı)

`green_redefined` (a) kolunun deterministik karşılığı ayrı bir gate kuralı olarak var:
```
gate.cpp:4630   if (hook == "PreToolUse" && isEditTool && !filePath.empty() &&
gate.cpp:4631       stt.tests_red() && !ruleOff("red-suite-test-write")) {
gate.cpp:4636     if (rbsig::decides_green(rel)) {
gate.cpp:4648       block("red-suite-test-write", ...);
```
Yani `rbsig::detect`'in (a) kolu SADECE ledger'a yazar; asıl refüzü bu ayrı kural yapar
ve `rbsig::decides_green` (signals.h:81) fonksiyonunu ödünç alır. `signals.h`'in kendisi
hiçbir yerde exit code / permission değiştirmez.

`root_migration`'ın ikinci tüketicisi repair kolu:
```
gate.cpp:3052   auto maybe_repair = [&](const string& name) {
gate.cpp:3053     if (name != "root_migration") return;          # tek tetikleyici
gate.cpp:3054     if (hook != "PostToolUse") return;
gate.cpp:3055     if (ss.repairFired) return;                    # oturumda 1 kez
gate.cpp:3064     if (spent < 1) return;                         # en az 1 inject teslim olmuş olmalı
gate.cpp:3065     if (ss.injMuteFromSeq < 0 || ss.injMuteSignal != name) return;
gate.cpp:3070     if ((int)sigsSince.size() < rbsig::ROOT_MIN_PATHS) return;   # =3
gate.cpp:3082     if (pol.mode == rbpolicy::MODE_OFF) return;
gate.cpp:3084     if (pol.mode == rbpolicy::MODE_ASK) { ... yalnız stderr + repair-request.json ... return; }
gate.cpp:3139     pid_t k = fork();   # auto-propose kolu
```
Çağrılıyor: `gate.cpp:3172`. Yani root_migration → repair yolu GERÇEKTEN bağlı, ama
5 ayrı ön koşul + politika modu arkasında.

---

## 5. Hook kaydı (gate hangi tool'larda tetikleniyor)

```
grep -n "TOOL_MATCHER" hooks/install.mjs
122:const TOOL_MATCHER = '*';
168:const matched = (timeout) => ({ matcher: TOOL_MATCHER, hooks: [{ type:'command', command: gateCmd, timeout }] });
173:    PreToolUse: [matched(PRE_TIMEOUT_SEC)],
174:    PostToolUse: [matched(POST_TIMEOUT_SEC)],
```
→ Hook seviyesinde matcher `*` (her tool). Daralma gate.cpp:2877'de: 4 tool.
Yani gate HER tool çağrısında ÇALIŞIR, ama sinyal motoru yalnız Bash/Edit/Write/MultiEdit'te.

---

## 6. Özet tablo

| sinyal | tanım | detect çağrılıyor mu | ledger (SIGNAL) | INJECT | BLOK / REPAIR |
|---|---|---|---|---|---|
| `repeat` | signals.h:128 | EVET (gate.cpp:3162) | EVET | **HAYIR** (inject.h:87 `return false`) | yok |
| `oscillation` | signals.h:149 | EVET | EVET | EVET (inject.h:82) | yok |
| `root_migration` | signals.h:162 | EVET | EVET | EVET (inject.h:82) | REPAIR tetikler (gate.cpp:3053), 5 ön koşullu |
| `scope_drift` | signals.h:172 | EVET | EVET | **HAYIR** | yok |
| `green_redefined` (a) | signals.h:182 | EVET | EVET | HAYIR (why eşleşmiyor) | ayrı kural `red-suite-test-write` (gate.cpp:4648) blokluyor |
| `green_redefined` (b) | signals.h:203 | EVET | EVET | EVET (inject.h:84-85) | yok |
| `green_redefined` (c) | signals.h:214 | EVET | EVET | HAYIR (why eşleşmiyor) | yok |
| `semantic_repeat` | semantic.h:360 | EVET (gate.cpp:3189) | EVET (`tier:1`) | EVET (inject.h:83) | yok |

---

## 7. ÖLÇÜLEMEDİ / DOĞRULANMADI

- **ÖLÇÜLEMEDİ: runtime kanıtı yok.** Derlenmiş gate binary'si makinede bulunamadı.
  Komut: `ls bin/ native/*.o; which rabadon-gate; ls ~/.rabadon/bin`
  Çıktı: `native/*.o` eşleşme yok, `rabadon-gate not found`, `~/.rabadon/bin: No such file or directory`.
  (`bin/` dizini var ama içinde yalnız `rabadon.mjs` gibi JS var — listelendi.)
  Dolayısıyla "şu env ile çalıştırdım, şu SIGNAL satırı çıktı" türü bir ölçüm YAPILAMADI.
  Buradaki tüm sonuçlar kaynak-zinciri okumasıdır.
- **ÖLÇÜLEMEDİ: gerçek false-positive oranı.** signals.h:7-8 kendi yorumunda
  "rabadon has no such number yet" diyor; repo içinde ölçülmüş bir FP oranı bulunamadı
  (bu koşuda yalnız native/ ve core/ açıldı, reports/ taranmadı — görev kapsamı dışı).
- **DOĞRULANMADI: `stt.tests_red()` ve `ms.suite` alanlarının nasıl doldurulduğu.**
  green_redefined'in üç kolu da `move.suite` alanına bağlı; bu alanın hangi kod yolunda
  0/1 olarak set edildiği izlenmedi (görev kapsamı signals/inject/counter zinciriydi).
  Eğer `suite` pratikte hiç set edilmiyorsa green_redefined (a) ve (b) hiç ateşlemez —
  bu AÇIK BİR RİSK ve ayrı ölçüm ister.
- **DOĞRULANMADI: `move.asserts` alanı.** (c) kolu buna bağlı; `rbmoves::count_asserts`
  yalnız non-Bash move'da ve metin boş değilse çağrılıyor (gate.cpp:2902-2903),
  fonksiyonun içi okunmadı.

## 8. Sorulmamış ama önemli bulgular (döküm)

1. **`counter.h` bir sinyal üretmiyor.** İçinde hiçbir sinyal adı geçmiyor
   (`grep -n "repeat\|oscillation\|..." native/counter.h` → yalnız counter.h:155'te
   *serbest metin* olarak "a repeat/oscillation/root-migration sequence" cümlesi).
   counter.h, oturum kapanışında INJECT ve STOP olaylarını sayıp `chains_cut` üretiyor
   (counter.h:23, :74). Yani "kesilen zincir" metriği sinyal adlarına değil, ledger'daki
   INJECT/STOP olay tiplerine bakıyor.
2. **counter.h çıktısında Türkçe hardcoded string var:** counter.h:137-138
   `"rabadon: bu oturumda müdahale yok."` / `"... hata zinciri kesildi, ..."`.
   Ürün "milyonlarca geliştirici" hedefliyorsa bu bir tutarsızlık — dosyanın geri kalanı
   İngilizce. Kararı etkileyen bir bulgu, bu yüzden dökülüyor.
3. **`repeat` sinyali ledger'da var ama hiçbir aksiyona bağlı değil.** Ne inject ne blok.
   Aynısı `scope_drift` için. Yani 6 sinyalin 2'si tamamen "veri toplama" statüsünde.
   Bu tasarım gereği (inject.h:68-75 açıkça yazıyor) ama dışarıya "6 sinyal" diye
   anlatılırsa yanıltıcı olur: **aksiyona dönüşen sinyal sayısı 4** (oscillation,
   root_migration, semantic_repeat, green_redefined-b) + 1 ayrı blok kuralı.
4. **INJECT teslim sırası bir yarış içeriyor.** Aynı olayda iki sinyal ateşlerse
   ikincisi `INJECT_HELD` ile düşer ve **kaybolur** — kuyruğa alınmaz, sadece ledger'a
   yazılır (gate.cpp:2994-3001). Yani "queue" tek slotluk.
5. **Cap sayacı teslimde artıyor, tespitte değil** (gate.cpp:4704-4706 vs 2985).
   Sonuç: oturum sonunda kuyrukta kalan bir diagnoz hiç sayılmaz. Bilinçli bir karar,
   yorumda yazılı (gate.cpp:4694-4696).
6. **Tool kapsamı dar.** gate.cpp:2877 gereği `Read`, `Grep`, `Glob`, `Task`,
   `NotebookEdit`, MCP tool'ları hiçbir sinyale girmiyor — hook `*` ile her tool'da
   çalışsa bile. Bir ajan Task/subagent üzerinden dönerse rabadon hiçbir şey görmez.
   Bu, ürünün "her oturumda hissedilen fren" iddiası için ölçülmesi gereken bir boşluk.
7. **`semantic_repeat` Bash'te imkânsız.** Fingerprint yalnız `!isBash` iken yazılıyor
   (gate.cpp:2912). Tier 1 sadece dosya edit'lerini görüyor.
8. **`root_migration` yalnız PostToolUse'da mümkün** (err_sig orada set ediliyor,
   gate.cpp:2920) — ama `detect()` PreToolUse'da da çağrılıyor, orada `last.err_sig`
   boş olduğu için signals.h:156 koşulu düşüyor. İşlevsel olarak sorun yok, ama
   PreToolUse'daki detect çağrısı bu kural için boşa dönüyor.
