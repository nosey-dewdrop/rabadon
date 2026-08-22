GERCEK HATA MADENI
2026-08-01

31 gercek hata vakasi, 8 acik kaynak projeden, 545 taranmis commit icinden.


TABLO

repo                    vaka   taranan commit   medyan kaynak satir   medyan dusen test
expressjs/express          4               46                   6.5                 2.5
tj/commander.js            4               31                   6.5                 1.0
lodash/lodash              4              218                  10.5                 1.5
ajv-validator/ajv          3              110                   5.0                 2.0
pallets/click              4               48                   6.5                 2.5
pallets/jinja              4               35                   8.0                 1.0
pallets/markupsafe         4               30                   4.5                 1.0
yaml/pyyaml                4               27                   1.0                 1.5
TOPLAM                    31              545                   6.0                 1.0

En kucuk vaka 1 kaynak satiri, en buyuk 33. En az 1 test dusuyor, en cok 10.
31 vakanin 31'i deterministik: kirmizi kosu 3 kez tekrarlandi, her seferinde ayni testler dustu.


BU VAKALAR SENTETIK DEGIL

Burada hicbir hata benim ya da bir modelin uydurdugu hata degil.

Her vaka, projenin KENDI git tarihinden cikarildi. Hatayi yakalayan test, o hatayi duzelten
muhendis tarafindan, duzeltmeyle ayni commit'te yazildi. Yani:

  - hatayi kim buldu: projenin kendi kullanicisi / bakimcisi
  - hatayi kim duzeltti: projenin kendi muhendisi
  - hatayi yakalayan testi kim yazdi: ayni muhendis, ayni commit'te
  - ben ne yaptim: sadece duzeltmenin KAYNAK yarisini geri aldim, test yarisina dokunmadim

Sentetik hata (bir modele "bu koda bug ekle" dedirtmek) ile bunun farki su: sentetik hatada
hatanin da testin de yazari ayni sistemdir, yani olcum kendi kendini onaylar. Burada test,
hatayi geri alan kisiden bagimsiz olarak ve ondan ONCE yazilmistir. Test hatayi gormezden
gelemez, cunku o testin var olma sebebi zaten o hatadir.


YONTEM

Her vaka icin uc adim:

  1. YESIL. Duzeltme commit'ine gecilir, projenin kendi test suiti kosulur. Suit tamamen gecer.
     Kanit: evidence/<vaka>.green.txt

  2. GERI ALMA. Commit'in yalnizca kaynak yarisi geri alinir. Test dosyalari oldugu gibi kalir.
     Yama: patches/<vaka>.patch

  3. KIRMIZI. Ayni suit tekrar kosulur, duser. Bu 3 kez tekrarlanir, her seferinde ayni testler.
     Kanit: evidence/<vaka>.red.txt

Makine okunabilir ozet: cases.json


DIZIN

  cases.json      31 vakanin tamami: repo, duzeltme sha, commit basligi, kaynak dosyalar,
                  test dosyalari, kaynak satir sayisi, dusen test sayisi, dogrulama sonuclari
  patches/        vaka basina bir geri-alma yamasi, dosya adi vakanin anahtari
  evidence/       vaka basina ham yesil ve ham kirmizi cikti (62 dosya)
  ajv/ click/ commander/ express/ jinja/ lodash/ markupsafe/ pyyaml/
                  madenci kosunun biraktigi ham log/patch dosyalari, oldugu gibi


DOGRULAMA (bu raporu yazarken yeniden yapildi)

  1. 31 SHA'nin tamami klonda "git log -1 <sha>" ile arandi. Commit basliklari birebir karsilastirildi.
  2. 31 yamanin tamami "git show -R <sha> -- <kaynak dosyalar>" ile SIFIRDAN yeniden uretildi ve
     diskteki yama ile karsilastirildi. patches/ altindaki dosyalar bu yeniden uretilmis hallerdir.
  3. 31 yamanin tamami, duzeltme commit'indeki dosya icerigi uzerine "git apply --check -p1" ile
     sinandi. 31/31 temiz uygulaniyor. Tek bir "patch does not apply" yok.


TEKILLESTIRME

Kural: iki vaka ancak su dortu birden tutuyorsa ayni sayilir.
  ayni repo + ayni kaynak dosya + cakisan eski-satir araligi + ayni degisen satir kumesi

Sonuc: 23 tane "ayni repo, ayni dosya" cifti incelendi. Hicbirinde satir araliklari cakismadi.
ELENEN VAKA SAYISI: 0.

Ciftlerin tam listesi cases.json icinde nearCollisions altinda. En yakin olanlar, yine de ayri hatalar:
  - markupsafe striptags: "collapse spaces" (satir 158-165 + 192-200) ile "match newlines" (satir 13-21).
    Ayni fonksiyonun iki ayri hatasi: bosluk sikistirma sirasi ve regex'in DOTALL olmamasi.
  - lodash prototype pollution: zipObjectDeep (satir 3990) ile defaultsDeep (satir 6589+6597).
    Ayni sinif zafiyet, ayri fonksiyonlar, ayri yamalar.


DURUSTLUK NOTLARI (madenci kosunun ciktisinda bulup duzelttiklerim)

  1. pallets/jinja: madenci ajan iki vakanin TAM SHA'sini yanlis bildirdi. On-ek dogruydu, 40 karakterlik
     kuyruk uydurmaydi. Klonda dogrulanmadan once soyle patliyordu:
       fatal: bad object 7232b824623e9ce679a1ec3d70e2d13ea1a86dae
       fatal: bad object 56a724644b6b6a7b21f4e7f5a1d7b1b06d1e0b7c
     "git rev-parse --disambiguate" ile dogru SHA'lar bulundu:
       7232b8246200155226adb672db8b3ef305cf29da  (Fix pickle/copy support for the `missing` singleton, 2024-10-01)
       56a724644b1ad9cb03745c10cca732715cdc79e9  (fix f-string syntax error in code generation, 2023-05-26)
     Vakalar gercek, diff'ler ve kanit dosyalari zaten dogru commit'e aitti. Sadece bildirilen kimlik yanlisti.

  2. tj/commander.js: 4 vakanin yamasi kosuda ILERI yonde tutulmus ve "git apply -R" ile uygulanmisti.
     Yani dosya "duzeltme yamasi"ydi, ters uygulaniyordu. Islem ozdes, kirmizi kanit gecerli, ama dosya
     adiyla icerigi celisiyordu. patches/ altindaki 4 dosya geri-alma yonunde yeniden uretildi.

  3. pallets/click d340b0c1: commit basligindaki cift kelime ("Fix speculative speculative empty string
     check") benim yazim hatam degil, upstream commit basliginda gercekten oyle.


KANITIN GUCU HER VAKADA AYNI DEGIL (kucultmeden yaziyorum)

  - express: projenin TAM suiti ortamsal olarak kararsiz. HEAD'de 3 kez "npm test": 1260 gecti /
    1259 gecti + 1 dustu / 1260 gecti. Dusen test her kosuda baska bir test ve hatasi hep
    "Error: socket hang up". Bu yuzden express'te oracle, duzeltmenin KENDI test dosyasina daraltildi
    (npx mocha ... <test dosyasi>). Dosya bazli kosular kararli. Yine de bu, diger 7 repodan daha
    zayif bir garanti: tam suit degil, alt kume.
  - ajv 720a23fa (ReDoS): dusen 4 testin 3'u duvar saati esigi ("expected 212083 to be below 500").
    3 kosuda da genis farkla kirmizi ama mantik degil zamanlama sekilli. 4. hata (gecersiz regex
    SyntaxError) tamamen deterministik ve mantiksal.
  - pyyaml: 3 kirmizi kosunun her biri ayri ham dosya olarak saklanmamis, tek ozet metinde toplanmis
    ("DETERMINIST: 3/3 kosu exit=1", pyyaml/pyyaml-mining-evidence.txt). Diger repolarda 3 kosunun
    ucu de ayri ham dosya. Yani pyyaml'in determinizm iddiasi ozet metne dayaniyor, ayri ham
    kosu ciktilarina degil. DOGRULANMADI demiyorum, tanecigi daha kaba diyorum.
  - click: 3 kirmizi kosu ayri ham dosya degil, click/case_<sha>.json icinde 3 kayit olarak duruyor.
    Her kaydin kendi exit kodu ve dusen test kuyrugu var, ucu de ayni.
  - Tablodaki "taranan commit" sayilari madenci ajanlarin kendi bildirimidir. Taramalari yeniden
    kosmadim. SHA'lari, yamalari ve uygulanabilirligi yeniden kosarak dogruladim, tarama hacmini degil.


CIKARILAMAYANLAR

Hicbir repo tamamen bos donmedi. Asagidakiler, ya bir donemin ya da tek tek adaylarin
elenme sebepleri, ham hatalariyla.

1. tj/commander.js: node --test donemi (2026-01-12'den HEAD'e, 78 commit) tek bir gercek hata
   vermedi. O bant dependabot yukseltmeleri, dokuman ve esm gocunden ibaret. 4 vakanin dordu de
   jest doneminden geliyor.

2. tj/commander.js c635fad50 "Collect variadic with push, add tests (#2410)":
   lib/argument.js + lib/option.js + lib/command.js geri alindi, suit YESIL kaldi (1367 gecti).
   Commit'in kendi testleri eski concat davranisini yakalamiyor. Elendi.

3. pallets/click fc6c7c47ed "FuncParamType should use ValueError message in self.fail() (#3211)":
   kendi testi 3 kosuda da dusuyor ama suitte alakasiz bir kararsiz test var:
     FAILED tests/test_utils.py::test_echo_via_pager[test5-cat] - AssertionError
   Sadece run2'de cikti. Determinizm sarti bozuldugu icin elendi. (click bu kararsizligi sonradan
   7eb57cff7c / d15f3c23a1 ile kendisi duzeltti.)

4. pallets/click, pytest 9.1.1 ile 2026-06 oncesi HER commit TOPLAMA asamasinda patliyor, cunku
   pyproject filterwarnings=["error"] diyor:
     E pytest.PytestRemovedIn10Warning: Passing a non-Collection iterable to parametrize is deprecated.
       Test: tests/test_basic.py::test_boolean_conversion, argvalues type: chain
     31000 deselected, 1 error in 2.72s
   pytest 8.3.5'e dusurulunce duzeldi. HEAD her iki surumde de yesil.

5. pallets/markupsafe b15d9d6c84 "avoid ambiguous regex in striptags":
   src/markupsafe/__init__.py geri alindi, suit YESIL kaldi:
     35 passed, 17 skipped   exit 0
   Gonderilen test, CPython 3.14'te eski birlesik regex'i yakalamiyor. Elendi.

6. pallets/markupsafe, 2019 oncesi py2 donemi (markupsafe/tests.py duzeni): Python 3.14'te import
   bile edilemiyor. Hic denenmedi.

7. pallets/jinja e45bc745a7 (overlay enable_async): kaynak geri alindi, suit YESIL kaldi (901 gecti).
   Commit'in kendi testi env_async.overlay() senaryosunu hic denemiyor. Elendi.

8. pallets/jinja 051df10c7b, d5f49f5cc1, 49d5f9788c, 77a212bf93, f15452f130 (2020-2021):
   YESIL taban bile tutmuyor, Python 3.14 ortam kaymasi. Ornek:
     7 failed, 813 passed
     tests/test_loader.py::test_package_zip_list - TypeError: This zip import does not have the
       required metadata to list templates.
     tests/test_debug.py::test_runtime_error, test_async_filters PytestUnraisable
   Hata degil, ortam kaymasi. Atildi.

9. ajv-validator/ajv 69568d08 "fix: #2482 Infinity and NaN serialise to null":
   lib/ geri alininca specialNumbers secenegi tip tanimindan kalkiyor, spec derlenmiyor, suit hic kosmuyor:
     spec/jtd-schema.spec.ts(151,32): error TS2353: Object literal may only specify known properties,
     and 'specialNumbers' does not exist in type 'JTDOptions'.
   Testle yakalanan bir hata degil, derleme hatasi. Elendi.

10. ajv-validator/ajv a4892653 ve 2023-06 oncesi tum bant: kurulu typescript 5.3.3 ile YESIL taban zaten kirmizi:
      spec/types/async-validate.spec.ts(113,11): error TS18046: 'data' is of type 'unknown'.
    Her commit icin donemine ait TS kurmak gerekirdi. Yapilmadi.

11. lodash/lodash: "npm test" hic kullanilamadi. pretest=npm run build, build eski devDeps istiyor
    (uglify-js 2.7.5, webpack 1.x) ve node 26'da kurulmuyor. Onun yerine paketin kendi test:main
    scripti dogrudan kosuldu: node test/test.js (QUnit). Ayni sebeple test/test-fp.js iceren tum
    adaylar atlandi, cunku fp suiti "npm run build:fp" gerektiriyor.

12. lodash/lodash, incelenip kosulmamis 4 umutlu aday: 879aaa9313 (_.template imports key dogrulama),
    fe8d32eda (baseUnset proto pollution), 90e6199a16 (_.merge Object.prototype), 79b9d20a91
    (merge fonksiyon ozelligi). Ilk ikisi dist/ de degistirdigi icin "sadece kaynak" yarisi gurultulu.

13. expressjs/express, kosulmadan elenen 2 aday: 246f6f5a "Remove utils-merge dependency",
    c70197ad "use node:buffer instead of safe-buffer". Bagimlilik takasi, davranis hatasi degil.

14. expressjs/express test/app.router.js tek basina kosarken "--require should" gerekiyor. Dosya
    .should kullaniyor ama hic require etmiyor, tam suitte baska bir dosya yukluyor. Bayrak olmadan
    degismemis duzeltme commit'inde bile:
      35 failing ... TypeError: Cannot read properties of undefined (reading 'equal')

15. yaml/pyyaml harness tuzagi: 2019-2021 commitlerinde pytest yok, ozel kosucu var
    (setup.py test -> tests/lib{,3}/test_all.py). Ciplak "python tests/lib/test_all.py" HATA VARKEN
    BILE exit=0 donuyor, cunku test_all.py'de sys.exit yok. Bu yuzden setup.py'nin yaptigi
    "if not test_all.main([]): raise" mantigini birebir cagiran sarmalayici kullanildi. Bu tuzaga
    dusulseydi 4 vakanin 3'u sessizce "yesil" gorunecekti.

16. ajv kurulum sarti (bunlar olmadan hicbir ajv vakasi uretilemiyordu):
    git submodule update --init + npm run json-tests; npm link yerine node_modules/ajv -> ..
    sembolik bagi; NODE_OPTIONS=--no-experimental-strip-types (yoksa node 26 native TS stripping
    ts-node'un onune geciyor: "SyntaxError: TypeScript import equals declaration is not supported in
    strip-only mode"); node_modules/re2/re2.d.ts icine RegExpIndicesArray tanimi (yoksa
    "node_modules/re2/re2.d.ts(11,15): error TS2304: Cannot find name 'RegExpIndicesArray'").
    Yama yesil ve kirmizi kosulara ayni sekilde uygulandi.


DISARI HICBIR SEY GITMEDI. push yok, fork yok, issue yok, publish yok. rabadon reposuna yazilmadi.
Tum klonlar /tmp altinda kendi mktemp dizinlerinde, gercek $HOME ve ~/.rabadon kirletilmedi.
