# Rozbor ostatních skillů marketingskills (P108 krok 8)

Podklad k diskusi s PM: co z repozitáře github.com/coreyhaines31/marketingskills (commit `dda3841`,
2. 10. 2026, MIT) ještě převzít. Převzato v P108: product-marketing, copywriting, copy-editing,
customer-research, cro. Zbývá 45 skillů. U každého: co dělá, přínos, kam by patřil a doporučení
**teď** (příští plán), **později** (až bude potřeba, typicky s jiným plánem) nebo **nikdy** (nehodí se,
nebo to už /aid-ui umí). Repozitář je psaný pro americké SaaS; „přínos" je míněn pro /aid-ui
a pro zákazníky, kterým web stavíme. Partnerské integrace (`tools/`, Converly, Ploy) se nepřebírají.

**Shrnutí doporučení:** teď 6 (site-architecture, marketing-psychology, offers, competitor-profiling,
image, signup); později 30 (z toho většina patří k marketingu jako službě, který zatím „připravujeme");
nikdy 9 (programmatic-seo, schema, aso, popups, ab-testing, attribution, revops, prospecting,
marketing-council). Nejvíc pro kvalitu webu přinese site-architecture (struktura
v kroku 2) a marketing-psychology s offers (přesvědčivost textů a nabídky).

## SEO a obsah

### seo-audit
Co dělá: audit SEO existujícího webu (technika, on-page, obsah, typické chyby podle druhu webu).
Přínos: u přestavby webu (P105) najde, co starý web dělá dobře a co rozbít nesmíme.
Kam by patřil: krok 0 přestavby, plán P105.
Doporučení: později — přestavby (P105); pro nový web máme vlastní kontrolu SEO (K2).

### ai-seo
Co dělá: optimalizace pro AI vyhledávače: technická dostupnost pro roboty, stavba odpovědí v textu (blok s přímou odpovědí), zmínky na cizích webech, sledování citací v AI odpovědích, připravenost pro AI agenty.
Přínos: technickou část už kontroluje náš řádek `ai_search` (K2: politika robotů, JSON-LD, text bez JavaScriptu, úryvky, llms.txt). Nepokryté zůstává psaní odpovědí (částečně řeší copywriting) a sledování citací po spuštění.
Kam by patřil: sledování citací do marketingu; stavba odpovědí do příručky textů, pokud kontrola textů ukáže mezeru.
Doporučení: později — marketing (sledování citací); technická část je pokrytá K2.

### site-architecture
Co dělá: hierarchie stránek, navigace, URL, vnitřní prolinkování, vizuální mapa webu.
Přínos: velký. Náš krok 2 dnes dělá seznam stránek a sekcí (a u aplikace role, toky, stavy) a drátěné modely; chybí v něm pravidla navigace (co do hlavičky a patičky, kolik položek), vzory URL podle typu stránky, plán vnitřních odkazů a ověření mapy webu před stavbou. Brána hlídá jen hloubku kliků (varování v SEO kontrole) a odkazy, které vedou nikam.
Kam by patřil: krok 2 (struktura), jako postup a kontrola struktury před schválením.
Doporučení: teď — doplní to, co krok 2 nemá, dřív než se píšou texty.

### programmatic-seo
Co dělá: stránky ve velkém ze šablon a dat (města, srovnání, adresáře).
Přínos: pro malé firmy spíš riziko (doorway stránky), náš standard je výslovně zakazuje.
Kam by patřil: nikam.
Doporučení: nikdy — v rozporu se standardem lokálního SEO (žádné kopie stránek pro města).

### schema
Co dělá: strukturovaná data (JSON-LD) a jejich ověření.
Přínos: malý, JSON-LD stavíme a kontrolujeme (K2, `ai_search`, `seo`).
Kam by patřil: krok 6.
Doporučení: nikdy — pokryto K2.

### content-strategy
Co dělá: plán obsahu (témata, pilíře, klíčová slova podle fáze nákupu, blog).
Přínos: střední, až když zákazník chce blog nebo pravidelný obsah.
Kam by patřil: marketingová část stránky pro zákazníka („připravujeme").
Doporučení: později — marketing.

### aso
Co dělá: optimalizace zápisu aplikace v App Store a Google Play.
Přínos: žádný pro web; možná pro PWA, která se do obchodů nedává.
Kam by patřil: nikam.
Doporučení: nikdy — /aid-ui nevydává aplikace do obchodů.

## Konverze

### signup
Co dělá: registrace a založení účtu s co nejmenším třením.
Přínos: velký u webových aplikací a PWA, kde registraci stavíme (toky a stavy úloh).
Kam by patřil: krok 2 (toky aplikace) a kontrola v kroku 7.
Doporučení: teď — doplní cro u aplikací, kde je registrace hlavní tok.

### onboarding
Co dělá: první spuštění, aktivace, prázdné stavy, kontrolní seznam pro nového uživatele.
Přínos: střední u aplikací; prázdné stavy už hlídá standard úloh a stavů.
Kam by patřil: krok 2 u aplikací.
Doporučení: později — s plánem pro texty obrazovek aplikací.

### popups
Co dělá: vyskakovací okna, bannery, odchod ze stránky.
Přínos: malý, malé firmy je většinou nechtějí; souvisí jen s lištou souhlasu s cookies.
Kam by patřil: nikam.
Doporučení: nikdy — náš standard bere vyskakovací okna jako tření, ne nástroj.

### paywalls
Co dělá: placené funkce a obrazovky upgradu v aplikaci.
Přínos: jen u aplikací s předplatným.
Kam by patřil: později u aplikací.
Doporučení: později — až bude první zákazník s placenou aplikací.

## Texty a kanály

### cold-email
Co dělá: studené B2B e-maily a navazující sekvence.
Přínos: pro zákazníka, ne pro web; patří do marketingu, který je „připravujeme".
Kam by patřil: marketing.
Doporučení: později — marketing.

### emails
Co dělá: automatické e-mailové sekvence (uvítání, péče, znovuoslovení).
Přínos: střední, až web sbírá kontakty nebo aplikace posílá e-maily.
Kam by patřil: marketing; u aplikací texty systémových e-mailů.
Doporučení: později — marketing a texty aplikací.

### social
Co dělá: obsah pro sociální sítě, kalendář, háčky, opakované použití obsahu.
Přínos: střední pro zákazníka, mimo web.
Kam by patřil: marketing; obrázek pro sdílení patří do plánu tiskovin.
Doporučení: později — marketing.

### video
Co dělá: výroba videa nástroji AI a programově.
Přínos: mimo web; může patřit k marketingu jako službě, který stránka pro zákazníka ohlašuje jako „připravujeme".
Kam by patřil: marketing.
Doporučení: později — marketing, jen pokud zákazník tento kanál používá.

### image
Co dělá: obrázky pro marketing, OG a sociální náhledy, optimalizace obrázků.
Přínos: střední; náhledový obrázek pro sdílení (og:image) dnes vzniká ručně a je v plánu tiskovin.
Kam by patřil: plán tiskovin a rozšířené sady značky.
Doporučení: teď — do plánu tiskovin (obrázek pro sdílení, profilové obrázky).

### sms
Co dělá: SMS, MMS a WhatsApp kampaně.
Přínos: mimo web; může patřit k marketingu jako službě, který stránka pro zákazníka ohlašuje jako „připravujeme".
Kam by patřil: marketing.
Doporučení: později — marketing, jen pokud zákazník tento kanál používá.

## Placená reklama a měření

### ads
Co dělá: kampaně v Google Ads, Meta, LinkedIn.
Přínos: pro zákazníka, mimo web; souvisí s cílovými stránkami.
Kam by patřil: marketing.
Doporučení: později — marketing.

### ad-creative
Co dělá: varianty reklamních textů a vizuálů.
Přínos: mimo web.
Kam by patřil: marketing.
Doporučení: později — marketing.

### ab-testing
Co dělá: návrh a vyhodnocení A/B testů.
Přínos: malý u malých webů (málo návštěv pro statisticky platný test).
Kam by patřil: nikam teď.
Doporučení: nikdy — malé weby nemají provoz na testy; vrátit se jen u velkého zákazníka.

### analytics
Co dělá: měřicí plán, události, GA4, Tag Manager; sám se ptá na požadavky na soukromí a souhlas.
Přínos: střední, až zákazník bude chtít měřit. Náš standard zakazuje cizí požadavky a cookies jen PŘED souhlasem; měření po souhlasu nebo bez cookies na vlastním serveru je s ním v souladu.
Kam by patřil: marketing, s rozhodnutím, zda /aid-ui podporuje měření až po souhlasu, nebo bez cookies.
Doporučení: později — marketing; podmínka: projde kontrolou `privacy_before_consent`.

### attribution
Co dělá: přisuzování konverzí kanálům, modely atribuce.
Přínos: mimo web malých firem.
Kam by patřil: nikam.
Doporučení: nikdy — příliš velký nástroj pro naše zákazníky.

## Růst a udržení

### referrals
Co dělá: doporučovací a affiliate programy.
Přínos: mimo web.
Kam by patřil: marketing.
Doporučení: později — marketing.

### free-tools
Co dělá: bezplatné nástroje jako marketing (kalkulačky, generátory).
Přínos: střední, kalkulačka ceny nebo úspory může být silný prvek webu.
Kam by patřil: krok 2 jako typ sekce, až o něj zákazník požádá.
Doporučení: později — na vyžádání zákazníka.

### churn-prevention
Co dělá: snížení odchodu zákazníků, zrušení předplatného, upomínky plateb.
Přínos: jen u aplikací s předplatným.
Kam by patřil: aplikace.
Doporučení: později — s placenou aplikací.

### community-marketing
Co dělá: budování komunit (Discord, Slack, fóra).
Přínos: mimo web; může patřit k marketingu jako službě, který stránka pro zákazníka ohlašuje jako „připravujeme".
Kam by patřil: marketing.
Doporučení: později — marketing, jen pokud zákazník tento kanál používá.

### lead-magnets
Co dělá: materiály ke stažení výměnou za e-mail.
Přínos: střední, až web sbírá kontakty.
Kam by patřil: marketing.
Doporučení: později — marketing.

### co-marketing
Co dělá: společné kampaně s partnery.
Přínos: mimo web; může patřit k marketingu jako službě, který stránka pro zákazníka ohlašuje jako „připravujeme".
Kam by patřil: marketing.
Doporučení: později — marketing, jen pokud zákazník tento kanál používá.

### influencer-marketing
Co dělá: spolupráce s influencery a ambasadory.
Přínos: mimo web; může patřit k marketingu jako službě, který stránka pro zákazníka ohlašuje jako „připravujeme".
Kam by patřil: marketing.
Doporučení: později — marketing, jen pokud zákazník tento kanál používá.

## Prodej a uvedení na trh

### revops
Co dělá: řízení obchodního procesu, skórování a směrování leadů, CRM.
Přínos: mimo web.
Kam by patřil: nikam.
Doporučení: nikdy — mimo rozsah /aid-ui.

### sales-enablement
Co dělá: prodejní prezentace, one-pagery, argumentace k námitkám.
Přínos: střední; one-pager a prezentace patří k dokumentům a tiskovinám.
Kam by patřil: plán tiskovin a dokumentů.
Doporučení: později — plán tiskovin.

### launch
Co dělá: plán uvedení produktu, Product Hunt, oznámení.
Přínos: malý; spuštění webu malé firmy je jednodušší.
Kam by patřil: marketing.
Doporučení: později — marketing (oznámení spuštění webu).

### pricing
Co dělá: cenotvorba, balíčky, ceníková stránka.
Přínos: střední; ceníková stránka je častá a cro ji pokrývá jen zčásti.
Kam by patřil: krok 3 u webu s ceníkem.
Doporučení: později — až pilot s ceníkem ukáže, že cro nestačí.

### competitors
Co dělá: srovnávací stránky „my vs. konkurence" a „alternativa k"; sám vyžaduje datované důkazy a odděluje fakta od výkladu.
Přínos: malý pro většinu malých firem; tam, kde zákazník srovnání chce, ho skill vede poctivě.
Kam by patřil: krok 3 jako typ stránky, tvrzení o konkurenci jen se zdrojem v registru faktů.
Doporučení: později — na vyžádání zákazníka, napojené na registr faktů.

### competitor-profiling
Co dělá: rozbor konkurence z jejích webů (pozice, sdělení, ceny).
Přínos: velký pro oddíl Konkurence a Čím se liší v dokumentu o produktu (krok Podklady).
Kam by patřil: krok 1p, jako zdroj s výslovným souhlasem PM (čte cizí weby).
Doporučení: teď — doplní nejslabší oddíly podkladů, které dnes PM vyplňuje sám.

### prospecting
Co dělá: hledání a kvalifikace potenciálních zákazníků.
Přínos: mimo web.
Kam by patřil: nikam.
Doporučení: nikdy — mimo rozsah.

### directory-submissions
Co dělá: zápisy do katalogů startupů, SaaS, AI nástrojů, recenzních portálů a místních katalogů, uvedení na launch platformách.
Přínos: malý pro běžné místní firmy (pro ně Firmy.cz a Google profil řeší SEO zadání); větší pro softwarové produkty.
Kam by patřil: marketing, jen u softwarového produktu.
Doporučení: později — jen pro softwarové produkty; u místní firmy stačí úkoly ze SEO zadání.

### public-relations
Co dělá: práce s médii, tiskové zprávy, mediakit.
Přínos: mimo web; tisková stránka webu je okrajová.
Kam by patřil: marketing.
Doporučení: později — marketing.

### events
Co dělá: akce, webináře, veletrhy.
Přínos: mimo web; může patřit k marketingu jako službě, který stránka pro zákazníka ohlašuje jako „připravujeme".
Kam by patřil: marketing.
Doporučení: později — marketing, jen pokud zákazník tento kanál používá.

## Strategie

### marketing-psychology
Co dělá: psychologie nákupu, mentální modely, přesvědčování, cenová psychologie.
Přínos: velký pro psaní textů a stavbu stránky (proč lidé nakupují, co je zastaví).
Kam by patřil: k copywritingu v krocích 1v, 3, 6 a jako čočka v kontrole textů.
Doporučení: teď — prohloubí přesvědčivost textů, hlavní slabinu pilotu.

### marketing-ideas
Co dělá: katalog marketingových nápadů pro SaaS.
Přínos: malý, obecný seznam.
Kam by patřil: marketing.
Doporučení: později — marketing, jen jako inspirace.

### marketing-plan
Co dělá: kompletní marketingový plán (13 oddílů, AARRR).
Přínos: střední, až budeme marketing nabízet jako službu.
Kam by patřil: marketing.
Doporučení: později — marketing.

### marketing-council
Co dělá: simulovaná rada slavných marketérů, každý posuzuje otázku jiným odborným pohledem.
Přínos: malý; naše personas v kontrole textů modelují reakci zákazníků, ne odborné pohledy, takže se nepřekrývají, ale simulované autority dávají slabě podložené rady.
Kam by patřil: nikam.
Doporučení: nikdy — rada smyšlených osobností není ověřitelná; odborné pohledy dává copy-editing a cro.

### marketing-loops
Co dělá: opakující se marketingové úlohy, které agent spouští pravidelně.
Přínos: střední pro budoucí marketing jako službu.
Kam by patřil: marketing.
Doporučení: později — marketing.

### offers
Co dělá: stavba nabídky (hodnota, výsledek, záruka, bonusy, důkazy, naléhavost a omezení, platební podmínky, pojmenování).
Přínos: velký; nabídka je to, co web prodává, a dnes ji nikdo neformuluje záměrně.
Kam by patřil: krok 1p (oddíl nabídky v podkladech) a krok 3.
Doporučení: teď — s pevnou hranicí: každá složka nabídky (záruka, bonus, výsledek, důkaz, naléhavost, cena a platby) jde na web jen jako fakt z registru se souhlasem zákazníka; skill smí navrhnout, nikdy tvrdit.

