# Zadání směru vzhledu (šablona; vrstva vzhled-postup.md, bod 4) - společné pro tři směry

Postavíš JEDEN směr vzhledu webu <podnik z registru faktů> jako skutečné stránky kostry: úvod, hlavní služba,
portfolio nebo seznam a kontakt, ve složce svého směru (`.aid-ui/directions/<směr>/`). Stránky na sebe odkazují
(ostatní položky menu mohou vést na `#`), fungují na 1440 i 390 px a jsou samostatné (žádný cizí server).

Povinné vstupy (nic si nevymýšlej):
- tokeny `../tokens.css` (barvy, písma, mřížka, mezery, rohy) - barvy a písma JEN z tokenů, písma lokálně;
- texty `../copy.md` - doslova; bloky „ČEKÁ“ ukaž jako označené místo „čeká na klienta“ (`--wait`, přerušovaný
  rámeček), ne jako hotový text a ne jako vymyšlenou hodnotu;
- logo ze sady značky (v hlavičce, výška 40-48 px, nikdy nedeformovat), obrázky klienta ve WebP se srcset; jen tyto
  obrázky, žádné fotobanky ani generované obrázky;
- teze podniku ze schváleného sdělení a princip směru (jedna věta) odvozený z tezí a značky.

Řemeslo (povinně): mřížka 12 sloupců z tokenů; **vyvážené, proporční kompozice** - prvky opticky na středu,
rovnoměrná vizuální váha, hrany textů a obrázků lícují s mřížkou, přirozené poměry obrázků (object-fit bez
deformace); typografie: hierarchie z tokenů, řádek do 66 znaků, nezlomitelné mezery po k s v z o u a i; kontrast
podle tokenů (akcent pro text jen `--accent-text`); viditelný fokus; odkaz „Přeskočit na obsah“; dotykové plochy
≥ 44 px; `prefers-reduced-motion`; pohyb jen jemný (najetí, zaměření), animace loga jen podle `pohyb-znacky.md`;
bez vyjetí na každé sekci. Vyhni se rubrice obecnosti: SaaS karty se stínem a gradientem, ALL-CAPS nadpisky nad
každým nadpisem, řetězce A · B · C, šipky na tlačítkách, krémová + patkové + terakota, Inter všude, 01/02/03 kde
nejde o posloupnost.

Zkontroluj nástroji studia (`aid-ui-tool.sh shot --name <n>`): 1440 a 390 px, žádný vodorovný posun, žádné chyby
v konzoli; snímky první obrazovky a celé stránky ulož vedle složky směru. Nakonec zapiš `karta.md`: princip (1 věta),
čím se liší od šablony (1 věta), které teze nese, riziko. Naslepo: neutrální `<title>` a jména souborů, ze kterých
nejde poznat směr; tento soubor a klíč směrů role nečtou.
