# rabadon — ORKESTRASYON v6 (KOSU-RABADON-5.md §3 ve §8'in YERİNE GEÇER)

Bu bölüm önceki orkestrasyon taslaklarını **EZER**. Sebebi ölçülmüştür: v4/v5'te
şefe iş yaptırdım (kart kesme, rapor doğrulama, kapı koşturma), alt-ajanı
yasakladım, faz açmayı operatöre bıraktım ve dal/worktree açtırdım. Dördü de
"şef iş yapmaz" kuralının ihlaliydi; 26 Ağu gecesi ölü bir dalda kapanmış bir
fazı ikinci kez kapatmaya çalışan bir oturumla sonuçlandı.

Koşunun geri kalanı (fazlar, kapılar, yasaklar, Yasa 1–8, CLAUDE.md,
AGENTS-PROTOCOL.md) aynen geçerlidir. Değişen tek şey: **kim ne okur, kim
neyi açar, kim hüküm verir.**

---

## 3.1 Roller

| Rol | Nerede | Ne yapar | Context'i |
|---|---|---|---|
| **ŞEF** | tek kalıcı oturum | etiket atar · ajan salar · hakemin **tek satırlık** hükmünü okur · sıradaki fazı açar | **şişmemeli** |
| **FAZ AJANI** | taze alt-ajan | tek fazı yapar, kartını yazar, **ölür** | şişebilir, umursanmaz |
| **HAKEM** | ayrı taze alt-ajan | kapıları **kendi koşturur**, hüküm verir, karar verir, **ölür** | şişebilir, umursanmaz |
| **DAMLA** | — | koşunun dışında | — |

Alt-ajanların şişmesi sorun değil, nasılsa ölecekler. Korunan tek context
şefinkidir; **şef şişiyorsa iş yapıyor demektir ve yapmamalıdır.**

## 3.2 Şefin dört yasağı

1. **Kod okumaz, komut koşturmaz, dosya taramaz.** Envanter dahil hiçbir iş
   şefin değildir.
2. **Koşu belgesini okumaz.** Yalnız bu §3'ü ve `reports/kosu/DURUM.md`'yi.
   Faz bölümlerini ajana **yol olarak** verir, içeriğini açmaz.
3. **Alt-ajan çıktısını okumaz.** Ajan kartını `reports/kosu/RAPOR/F<n>.md`'ye
   yazar; şef o dosyayı **açmaz**. Ajanın döndürdüğü uzun metni context'ine
   almaz. *(Rabadon'un "alt-ajan ebeveynine ölür" ölçümünün çözümü budur:
   ajanı yasaklamak değil, ajanı okumamak.)*
4. **Hüküm vermez.** Hükmü daima hakem verir.

## 3.3 Bir fazın hayatı — şefin gördüğü her şey

1. `reports/kosu/DURUM.md`'yi oku (bir sayfa: sıradaki faz · son kapı sayıları ·
   son hüküm · açık kalemler).
2. `git tag F<n>-oncesi`.
3. **Faz ajanını sal.** Ona verilen tek şey yollardır (§8.2).
4. Ajan işini yapar, kartını yazar, **ölür**.
5. **Hakemi sal** (§8.3). Ona verilen: kart dosyasının yolu + F<n>'in kapı
   satırı. Hakem kabul betiklerini **kendi koşturur**, hükmünü `KAPI.md`'ye ve
   `DURUM.md`'ye **tek satır** yazar.
6. Şef yalnız o tek satırı okur ve davranır:
   - **GEÇTİ** → `git tag F<n>-yesil`, sıradaki fazı aç.
   - **KALDI** → aynı faz, **taze bir ajanla**, hakemin notuyla yeniden. Ölen
     ajan dirilmez.
   - **GERİ AL** → `git reset --hard F<n>-oncesi`, sebep `DURUM.md`'ye.
7. 2. adıma dön. Son faz kapanana kadar durma.

Şefin context'ine faz başına giren toplam metin birkaç yüz kelimedir.

## 3.4 DAMLA HİÇBİR ŞEY YAPMAZ — kararlar hakeme gider

Belgedeki "operatör kararı" satırları operatöre **gitmez**. Damla ne soru
cevaplar, ne dosyaya yazar, ne blok yapıştırır, ne kart taşır.

Bir faz karar gerektirdiğinde şef **hakemi** salar: hakem repoya, ölçüm
çıktısına ve Yasa 1–8'e bakarak karar verir, `reports/kosu/KARARLAR.md`'ye tek
satır yazar. Gerekçesi bir sayıya ya da yayınlanmış bir kaynağa dayanır;
dayanamıyorsa **en kısıtlayıcı seçeneği** seçer ve "dayanak yok, en kısıtlayıcı
seçildi" yazar. **Koşu hiçbir noktada beklemez.**

**Tek istisna — geri dönüşsüz dış adım:** `npm publish`, marketplace PR'ı,
Show HN, fiyat. Hakem bunlara karar veremez; hazırlığı biter, `DURUM.md`'ye
"HAZIR, tek komut bekliyor" satırı düşer ve **koşu sıradaki faza geçer**.
Beklemek yok.

## 3.4B Şef oturumu biterse

Şefin context'i yine de dolarsa (dolmamalı) ya da oturum düşerse: yeni oturum
açılır ve tek cümle verilir — *"Sen ŞEF'sin. Orkestrasyon v6'yı ve
`reports/kosu/DURUM.md`'yi oku, kaldığın yerden devam et."* Bu yeniden başlatma
değil, devam ettirmedir. Faz yeniden koşulmaz: diskte kart + commit varsa o faz
**koşmuştur**.

## 3.5 MAIN'DE ÇALIŞILIR — BRANCH YOK, WORKTREE YOK

- Bütün fazlar `main`'de koşar. Yeni dal açılmaz, yeni klasör kurulmaz.
  Tek kök: `/Users/damummyphus/damla_projects_2026/rabadon`.
- Branch'in yerine **etiket**: her faz öncesi `git tag F<n>-oncesi`, kapanışta
  `git tag F<n>-yesil`. Geri dönüş tek komut.
- Worktree'nin **tek meşru kullanımı** alettir, ev değil: boş yeşil kontrolü ve
  hakemin bağımsız kum havuzu — ikisi de `/tmp`'de ve `--detach`.
- Bir faz `main`'i yeşil bırakmadan ölemez. Yarım iş main'de bırakılmaz.

## 3.5B COMMIT KARTLA BİRLİKTE İNER — bu gecenin dersi

Kanıt dosyaları **kart bitmeden, o kartı yazan ajan tarafından** commit'lenir.
Faz sonunda toplu commit yok. Şef yalnız etiket atar. Sebep ölçüldü: 26 Ağu
gecesi F2-2'nin altı kanıt dosyası commit'lenmemiş kaldı, oturum ortada öldü ve
bir sonraki oturum gerçeği diskten değil el yazısı prompt'tan okumaya çalıştı.
**Commit'lenmemiş iş sahipsizdir** kuralı vardı; uygulaması yoktu.

## 3.6 HEDEF KOŞUSU — compounding error kilidi

Uzun koşuda tehlike, her fazın kendi kapısını geçip hedeften yavaşça
sapmasıdır. Kilit: devralınan kırmızı **AD** kümesi (`{2b, 6e, 7b}`) ve
`reports/R7/accept.sh` + `npm test` + `make test` her fazın sonunda koşar.
Küme **büyürse faz kapanmaz**. Bu, hakemin kendi koşturduğu sayıdır; kartta
yazana bakılmaz.

## 3.7 FAZ PLANI SABİT DEĞİL — hakem sıradaki kartı yeniden yazar

Faz listesi bir niyettir, sözleşme değil. Hakem karta ve ölçülen sayılara
bakarak sırayı değiştirebilir, faz ekleyebilir, bir fazı ikiye bölebilir, bir
fazı iptal edebilir. Tek şartı gerekçesini **ölçülen bir sayıya** bağlamaktır.
Şef değişen kartı kendisi yazar ve açar; Damla'ya gitmez.

Hakemin yapamayacağı tek şey **hedefi** değiştirmektir: R7'nin dürüst kapanışı,
R8'in yayını, M3/M4.

## 3.8 REWARD HACKING'E KARŞI — dört kilit

1. **Kapı tanımı dondurulur.** `reports/*/accept.sh` ve `reports/R7/ON-KAYIT.md`
   faz ajanının dokunamayacağı dosyalardır. Değişmesi gerekiyorsa **hakem**
   değiştirir, eski/yeni sayıyı yan yana yazar (AGENTS-PROTOCOL Kapı 1: kabul
   betiğini uygulayan yazmaz).
2. **Ölçüm seti mühürlü.** `ab_run.jsonl`'in görev kümesi ve ON-KAYIT'ın N'i
   ajan tarafından değiştirilemez, eklenemez, çıkarılamaz.
3. **Mutasyon kanıtı.** Yeni ya da düzeltilmiş her kapı için ajan onu
   **kırdığını** göstermek zorunda: kodu kasten bozar, kapı kırmızıya döner,
   geri alır. **Kırmızı olamayan kapı kapı değildir** — `pgrep -c` dersi.
4. **Kapı gevşetilmez.** Eşiği gevşetmek (1000 µs tavanı, `MIN_HISTORY`, %50
   sapma) faz ajanının yetkisi değildir. Gerekiyorsa faz durur, hakem karar
   verir, gerekçe kartta sayıyla yazılır.

## 3.9 ARAŞTIRMA — her fazın içinde, ayrı tarama fazı yok

Bulgu künyesiyle yazılır: yazar/kurum, yayın, yıl, URL, **ölçüm tarihi**.
Künyesi olmayan sayı koda ve kamuya giremez (Yasa 7). Bulunamazsa "YAYIN
BULUNAMADI" yazılır ve sayıyı hakem koyar (en kısıtlayıcı değer), ajan değil.
Hakem şüphelendiği künyeyi kendisi açar; ölü linkse ya da kaynak o sayıyı
söylemiyorsa kartı reddeder.

## 3.10 CONTEXT DİYETİ — tek okuma listesi

Her faz ajanı şunları okur, fazlası değil: `CLAUDE.md` · `AGENTS-PROTOCOL.md` ·
koşu belgesinin §3.5, §3.6, §3.8, §3.10 bölümleri · `reports/kosu/DURUM.md` ·
`reports/kosu/UYANDIGINDA.md` · **yalnız kendi faz bölümü**.

Şef bu listeyi ne daraltır ne genişletir. Ve şef bu bölümlerin kendisini
**okumaz** — ajana yalnız bölüm adlarını söyler.

## 3.11 AJAN ÖLÜMÜ ≠ KIRMIZI

API hatası, kota, auth düşmesi, kapatılan terminal = **KOŞMAMIŞ** iş. Kırmızı
değildir, hipotezi elemez, iş silinmez. Teşhis diskten yapılır: **kart + commit
varsa faz KOŞMUŞTUR, ikinci kez açılmaz.** Yoksa taze ajanla yeniden açılır.

## 3.12 FAZ BÜYÜKLÜĞÜ

Tahminler yol göstericidir, kapı değildir. Ama bir faz tahmininin **iki katını
aşarsa durur ve hakeme gider** — sessizce sürünmez. Hakem fazı bölebilir.

---

# 8. AÇILIŞ — DAMLA BUNU BİR KEZ YAPIŞTIRIR

## 8.1 Şef bloğu (tek sefer)

> Sen ŞEF'sin — rabadon koşusunun orkestratörü.
>
> **Oku:** yalnız orkestrasyon v6 §3'ü ve `reports/kosu/DURUM.md`'yi.
> Başka hiçbir bölüm okuma.
>
> **Yasakların:** kod okuma · komut koşturma · dosya tarama · koşu belgesinin
> faz bölümlerini okuma · alt-ajan çıktısını okuma · kendi hükmünü kendin
> verme. Envanter dahil bütün iş alt-ajana gider.
>
> **Döngün (§3.3):** `DURUM.md` oku → `git tag F<n>-oncesi` → faz ajanını sal
> (ona yalnız yolları ver) → ajan ölsün → hakemi sal → hakemin `KAPI.md`'ye
> yazdığı **tek satır** hükmü oku → GEÇTİ/KALDI/GERİ AL'a göre davran →
> sıradaki faz. Son faz kapanana kadar durma.
>
> **Tek kök:** `/Users/damummyphus/damla_projects_2026/rabadon`, tek dal `main`.
> Dal açma, worktree açma.
>
> **Damla'ya hiçbir şey sorma, Damla'yı hiç anma.** Karar gerektiren her nokta
> hakeme gider (§3.4). Geri dönüşsüz dış adım (npm publish, PR, Show HN, fiyat)
> çıkarsa `DURUM.md`'ye "HAZIR" satırı yaz ve **sıradaki faza geç** — bekleme.

## 8.2 Şefin faz ajanına vereceği blok

> Sen F<n> ajanısın. **Oku:** `CLAUDE.md` · `AGENTS-PROTOCOL.md` ·
> orkestrasyon v6 §3.5, §3.6, §3.8, §3.10 · `reports/kosu/DURUM.md` ·
> `reports/kosu/UYANDIGINDA.md` · ve **yalnız F<n> bölümü**. Başka bölüm,
> başka rapor, başka koşu dosyası okuma. Arşivdeki eski koşu belgelerini açma.
>
> `main`'de çalış, dal açma, worktree açma (`/tmp` + `--detach` hariç).
> Kapı sayını **ölçmeden** kart yazma. Ürettiğin kanıt dosyalarını kart
> bitmeden **sen commit'le** — faz sonuna erteleme.
>
> Kartını `reports/kosu/RAPOR/F<n>.md`'ye **30 satırı geçmeden** yaz, push et,
> **dur ve öl.** Sonraki fazı açma, kendi hükmünü kendin verme, uzun özet
> döndürme — şef seni okumayacak, kartını hakem okuyacak.
>
> [şef buraya hakemin bir önceki fazdan bıraktığı notu ekler]

## 8.3 Şefin hakeme vereceği blok

> Sen HAKEM'sin. Bu koşuda hiçbir iş yapmadın ve yapmayacaksın. Faz ajanının ne
> düşündüğünü bilmiyorsun ve öğrenmeyeceksin.
>
> **Oku:** `reports/kosu/RAPOR/F<n>.md` kartı · orkestrasyon v6 §3.6 ve §3.8 ·
> F<n>'in kapı satırı · `CLAUDE.md`. Karttaki "kapandı/geçti" cümlelerine
> **inanma** — kabul betiklerini **kendin koştur** (`npm test`, `make test`,
> `reports/R7/accept.sh`) ve devralınan kırmızı AD kümesinin büyümediğini
> kendin doğrula.
>
> Yeni ya da düzeltilmiş her kapı için **mutasyon kanıtı** iste: kırılamayan
> kapı kapı değildir. Eşik, ON-KAYIT ya da kabul betiği değiştiyse eski/yeni
> sayı yan yana yazılı mı, bak; yazılı değilse reddet.
>
> Karar gerekiyorsa **sen ver**: dayanağını bir sayıya ya da yayınlanmış
> kaynağa bağla, dayanak yoksa en kısıtlayıcı seçeneği seç. `KARARLAR.md`'ye
> tek satır.
>
> **Hükmünü `reports/kosu/KAPI.md`'ye TEK SATIR yaz:** `GEÇTİ` / `KALDI` /
> `GERİ AL` + sıradaki faza not, ve `DURUM.md`'yi tazele. Ayrıntıyı
> `reports/kosu/RAPOR/F<n>-R.md`'ye yaz; şef onu okumayacak.
> Ölçemediğine "ölçemedim" de.

## 8.4 Damla'nın işi

**Yok.** §8.1'deki blok bir kez yapıştırılır ve koşudan çıkılır. Kart taşınmaz,
soru cevaplanmaz, dosyaya yazılmaz. İstenirse sonradan `KARARLAR.md`'ye bakılıp
itiraz edilir; koşu beklemez.
