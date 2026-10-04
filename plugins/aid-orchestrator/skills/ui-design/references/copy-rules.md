# Pravidla textů webu (/aid-ui)

Vlastní text AID, jazykově neutrální. Platí pro vizi, slogany, plán obsahu a texty stránek
(kroky 1v, 3, 6) a pro nezávislou kontrolu textů (krok 7). Metodu psaní dávají převzaté skilly
v `adopted/marketingskills/` (copywriting, cro, copy-editing, product-marketing,
customer-research); tenhle soubor říká, jak je /aid-ui čte. Jazykovou stránku řeší
`copy-<jazyk>.md` (`copy-cs.md`, `copy-sk.md`, `copy-en.md`) podle `lang` stránky.

## Fakta a hypotézy

- Tvrzení na webu (číslo, cena, roky, počet zákazníků, jméno, reference, kontakt, záruka,
  termín, výsledek) jen z `docs/content/facts.yaml`, se zdrojem. Co v registru není, na web
  nejde (SKILL.md MUST 5); chybí-li, otázka `facts` ve studiu.
- `docs/content/product-context.md` rozlišuje stav oddílu: vyplněno, hypotéza, chybí, rozpor,
  zastaralé. Hypotéza smí řídit tón a výběr argumentů (komu psát, čím začít), nikdy se
  neobjeví jako tvrzení. Fakt se z ní stane jen odpovědí PM a zápisem do registru se zdrojem.
- Návrh nabídky, záruky, bonusu nebo naléhavosti (převzaté skilly je umí navrhnout) je jen
  návrh pro PM; na web jde až jako fakt z registru.

## Pořadí při rozporu

Když si zdroje odporují, platí v tomto pořadí:

1. poslední výslovná odpověď PM ve studiu,
2. `docs/content/facts.yaml`,
3. schválený `docs/content/product-context.md`,
4. `docs/product-vision.md`,
5. `PRODUCT.md`,
6. tyto mosty (`copy-rules.md`, `copy-<jazyk>.md`),
7. převzatý skill,
8. ostatní zdroje (starý web, rozhovory).

Dva doložené údaje, které si odporují (různá cena v zadání a na starém webu), se nerozhodují
samy: jedna otázka `facts` s oběma hodnotami a jejich zdroji.

## Jak číst převzaté

- Soubor kontextu, který převzaté skilly hledají (`.agents/product-marketing.md`), je u nás
  `docs/content/product-context.md`.
- Kde převzatý skill říká „zeptej se uživatele", /aid-ui se ptá otázkou ve studiu (`facts`,
  `sources`, `product_context`), nikdy v chatu.
- Odkazy v převzatých souborech na soubory, které ve snímku nejsou (např.
  `cro/references/experiments.md`), se nesledují.
- Převzaté skilly píšou pro americké SaaS. Co se na malou českou nebo slovenskou firmu
  nehodí (free trial, MRR, „book a demo"), se nepoužije; jazyková příručka říká, co místo toho.

## Co blokuje v revizi

Nezávislá kontrola textů (krok 7) dává nálezům závažnost `blokujici`, `vazny`, `drobny`.
Blokující je:

- tvrzení bez faktu v registru (číslo, jméno, reference, záruka, výsledek);
- text, který si odporuje s jiným místem webu nebo s registrem;
- stránka bez jasné odpovědi na otázku „co mi to přinese" (průchod so_what); neplatí pro právní
  stránku (`legal: true`), kde je cílem srozumitelnost, ne přesvědčení;
- výzva k akci, která nevede nikam nebo slibuje něco, co web nedělá;
- fráze ze seznamu „nikdy" jazykové příručky v nadpisu nebo prvním odstavci;
- text v jiném jazyce, než má stránka.

Vážný nález (obecnost, slabý důkaz, opakovaná fráze) se opraví, stránku sám nezastaví;
drobný je doporučení.

## Kotvy skóre person

Revize hodnotí každou stránku pohledem pěti person (konverzní copywriter, UX písař, cílový
zákazník, skeptický zákazník, strážce značky) od 1 do 10. Skóre pod 5 je blokující; cílový
a skeptický zákazník pod 7 je blokující taky (text, který zákazníka nepřesvědčí, neprojde; neplatí pro
právní stránku). Chybějící nebo nečíselné skóre je blokující.

- **1** - text škodí: zákazník odejde nebo nevěří.
- **5** - srozumitelné, ale zaměnitelné s konkurencí; nic nepřesvědčí.
- **7** - konkrétní a věrohodné, s jedním slabým místem.
- **8** - zákazník pozná sebe, svůj problém a další krok; žádná prázdná fráze.
- **10** - nic by se nedalo vypustit ani zpřesnit.

Skóre se zapisuje a ukazuje; o průchodu stránky rozhodují blokující pravidla, ne průměr.
O tom, jestli text zní jako firma, rozhoduje PM (otázka `copy_verdict`).

## Právní stránky

Krok 2 označí v `structure.pages[]` stránku `legal: true`, když nic neprodává a jen plní
povinnost: ochrana osobních údajů, obchodní podmínky, cookies, reklamační řád, impresum.
Na právní stránce konverzní body cro (hodnotová nabídka, výzva k akci, důvěra, námitky,
tření) smí dostat stav `netyka_se` s důvodem; průchody copy-editing platí i na ní
(srozumitelnost, tón, konkrétnost).
