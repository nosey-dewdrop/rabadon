rabadon prove — ILK GERCEK VERDICTLER
2026-08-16

Iki gercek, upstream'e merge edilmis commit. Ikisi de bu makinede yeniden
klonlandi ve `rabadon prove` bagimsiz olarak yargiladi. Hicbiri rabadon'un
kendi onceki kanitina dayanmiyor.

SORU
  Bir degisikligin KAYNAK yarisi geri alinip her test oldugu yerde birakilinca,
  projenin kendi kontrolu kirmiziya donuyor mu? Donmuyorsa o degisiklik hicbir
  sey kanitlamamistir, kendi testleri ne derse desin.

IDDIA EDILMEYEN
  PROVEN "dogru" demek degildir. Suite yanlis davranisi kodluyorsa, onu
  saglayan bir degisiklik yine PROVEN cikar. Olculen sey, yesilin SEBEBININ
  bu degisiklik olup olmadigi.


01 — pallets/markupsafe e49d257126  "match newlines when stripping tags"
     komut: rabadon prove --dir <klon> --patch <git show e49d2571>
            --cmd "PYTHONPATH=src python3 -m pytest tests -q"
     post GREEN / counter RED / pre GREEN
     verdict: PROVEN_WITH_TEST_EDIT      exit 0

     Gercek bir duzeltme. Kaynak geri alininca suite kirmiziya donuyor, yani
     yesili bu degisiklik uretiyor. "WITH_TEST_EDIT" cunku commit yeni bir test
     dosyasi eklemedi, var olani duzenledi — ayirt edici testin bir kismini ayni
     degisiklik yazdi, ve bu ayri bir iddia oldugu icin ayri bir kelimeyle
     soyleniyor.


02 — tj/commander.js c635fad50  "Collect variadic with push, add tests (#2410)"
     komut: rabadon prove --dir <klon> --patch <git show c635fad50>
            --cmd "npx jest --silent"
     post GREEN / counter GREEN / pre GREEN
     verdict: TEST_PASSES_BOTH_WAYS      exit 1

     BU RAPORUN ASIL BULGUSU. Baslikta "add tests" yaziyor. PR uc kaynak
     dosyasi (lib/argument.js, lib/command.js, lib/option.js) ve iki test
     dosyasi tasiyor. Uc kaynak dosyasi da geri alindi, jest suite'inin tamami
     yesil kaldi. PR'in kendi ekledigi testler PR'i test etmiyor.

     Bu, insan review'unun goremedigi sekil: ozenli gorunen, test tasiyan,
     yesil bir yama. Merge edildi.

     BAGIMSIZ TEYIT: ayni sonuc bir hafta once baska bir kosuda da olculmustu —
     reports/2026-08-01-real-defect-mine/README.txt:140-142, "lib/argument.js +
     lib/option.js + lib/command.js geri alindi, suit YESIL kaldi (1367 gecti)".
     Iki ayri yol, ayni cevap.


03 — ayni markupsafe vakasi, KIRIK ORTAMLA
     ilk kosuda PYTHONPATH verilmemisti; pytest exit 4 (ortam hatasi, test
     toplanamiyor) dondu ve UC AGACIN UCU DE kirmizi cikti.
     verdict: NO_COUNTERFACTUAL      exit 2
     "the check is RED with the change applied, so there is no green for the
      change to explain."

     Burada onemli olan sey, dogru cevabin cikmasi degil, YANLIS cevabin
     cikmamasi. Kirik bir ortam counter agacini da kirmizi yapar; naif bir
     uygulama bunu "counter kirmizi = PROVEN" diye okurdu. Kontrol agaci (post)
     once soruldugu icin oyle olmadi.


ACIK KALAN
  - Bu iki vaka bir dagilim degil. Kanit orani, gercek merge edilmis PR'larin
    yuzde kacinda kesin bir verdict cikabildigi, henuz olculmedi.
  - Ikisi de kucuk, tek dilli, temiz repolar. Monorepo, uzun suite, kararsiz
    test hicbiri denenmedi.
  - `prove` su an makbuz yazmiyor, deftere baglanmiyor, held-out probe
    kosturmuyor. Sadece cekirdek.
