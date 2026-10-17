---
sidebar_position: 17
title: Návrh a stavba frontendu (/aid-ui)
description: "Kdy je web nebo webová aplikace hotová, jakými fázemi k tomu /aid-ui vede, kdo v které rozhoduje a jak vznikají tři jedinečné směry."
status: published
owner: "Platform"
created: 2026-09-27
updated: 2026-09-30
---

# Návrh a stavba frontendu (/aid-ui)

Jednou větou: **front je hotový, až projde bránou kontrol, PM schválí každou
stránku a vše neprošlé má jmennou výjimku PM; cesta k tomu vede přes pravdu
o produktu, plán obsahu a tři skutečně odlišné směry, mezi kterými vybírá PM.**

Standard platí pro skill /aid-ui pluginu AID a pro každého, kdo staví web nebo
webovou aplikaci ekosystému jinak. Navazuje na
[Design systém aplikací](./design-system-standard) (šablona a brand balíček),
[Úlohy a stavy webové aplikace](./webapp-tasks-states-standard) (mapa úloh),
[Product vision](./product-vision) a [SEO a webovou viditelnost](./seo/).
Co tyto standardy říkají, se tady neopakuje.

## What — definice hotového frontu

Front je hotový, když platí všechno níže na celé **matici**: stránky ×
šířky 390 / 768 / 1440 px × prohlížeče Chromium a WebKit × role a stavy
(u aplikace). Sloupec „Kontrola" říká, kdo to ověřuje: **skript** (brána
/aid-ui, opakovatelně), **PM** (posouzení člověkem), **klient** (dodá nebo
potvrdí zadavatel).

| Pravidlo | Co musí platit | Kontrola |
|---|---|---|
| **FB-1 Stránky odpovídají** | každá stránka vrací HTTP 200 | skript |
| **FB-2 Pokrytí glyfů** | každý znak stránky vykreslí zamýšlené písmo, včetně ě š č ř ž ý á í é ů ú; žádný záskok systémového písma | skript |
| **FB-3 Bez vodorovného přetečení** | na žádné šířce stránka neroluje do strany | skript |
| **FB-4 Ovladače na jeden řádek** | tlačítka a odkazy ve formě ovladače se nezalamují | skript |
| **FB-5 Žádné zástupné texty** | žádné lorem ipsum, „TODO", vymyšlený kontakt ani zástupný obrázek | skript |
| **FB-6 Fakta sedí** | údaje na stránce (ceny, kontakty, otevírací doba, čísla) odpovídají registru faktů | skript + klient |
| **FB-7 Logo a favicon z brand balíčku** | nic nakreslené narychlo mimo [brand balíček](./design-system-standard#brand-balíček-projektu) | skript |
| **FB-8 Žádné rozbité odkazy a zdroje** | odkazy, obrázky, písma a skripty se načtou | skript |
| **FB-9 Povinné soubory** | lokalizovaná stránka 404, sada favicon, og obrázek, atribut `lang` | skript |
| **FB-10 Přístupnost** | axe: nálezy závažnosti serious a critical = 0 | skript |
| **FB-11 Úlohy × stavy** | u aplikace projdou scénáře z [mapy úloh](./webapp-tasks-states-standard#what--co-musí-aplikace-mít) | skript |
| **FB-12 Obrázky** | formát WebP (nebo AVIF), jeden obrázek ≤ 200 kB | skript |
| **FB-13 Lighthouse mobil** | skóre se měří a hlásí; jen varování, neblokuje | skript |
| **FB-14 SEO** | kontrola `aid-ui-seo-check.py`; nález BLOCKER = neprošlo | skript |
| **FB-21 Nic se nepřekrývá** | žádné dva viditelné texty, ovladače ani obrázky se nepřekrývají | skript |
| **FB-22 Značka jednotně** | každý text má webové písmo, které web sám deklaruje; hlavička a patička jsou na všech stránkách stejné | skript |
| **FB-23 Váha stránky** | stránka přenese nejvýš 1 MB, v `<head>` žádný blokující skript, velké rastrové obrázky mají `srcset` | skript |
| **FB-24 Minimum pro firmu** | na každé stránce identifikace podnikatele (IČO), u formuláře odkaz na informace o zpracování osobních údajů | skript |
| **FB-15 Snímky celých stránek** | PM projde snímek každé stránky na každé šířce | PM |
| **FB-16 Schválení stránky** | PM schválí každou stránku zvlášť | PM |
| **FB-17 Výjimky** | co neprošlo nebo není pokryté, má jmennou výjimku PM s důvodem | PM |

Brána se po opravě spouští znovu celá, ne jen neprošlé řádky.

## Why — proč to platí

Dřívější /aid-ui končilo, když stránka „vypadala hotově" na jedné šířce
v jednom prohlížeči. Audit (září 2026) našel stránky s háčky vykreslenými
záložním písmem, zalomená tlačítka, vymyšlené údaje a logo mimo brand balíček,
tedy chyby, které skript najde za sekundy a člověk přehlédne. Zároveň
vzhled, který generuje model bez vedení, je průměr internetu: bez vlastní
reference a výběru ze skutečně odlišných směrů vypadá každý web stejně.

## How — fáze a kdo rozhoduje

Každá volba a schválení PM se děje na jedné **stránce studia** projektu:
karty s náhledem a tlačítky vybrat / schválit / vrátit s komentářem /
vygenerovat znovu. Agent nic nerozhoduje za PM a nic nevymýšlí.

| Fáze | Co vzniká | Rozhoduje |
|---|---|---|
| **0 Start** | varianta (FB-18) | PM |
| **1 Pravda o produktu** | fakta o produktu, volitelně vize a slogany, identita (logo, paleta), SEO brief | PM (fakta dodá PM nebo klient) |
| **2 Struktura** | stránky a sekce; u aplikace role, navigace, klíčové toky s mapou úloh | PM |
| **3 Plán obsahu** | viz FB-19 | PM, klient |
| **4 Reference** | agent najde asi šest referenčních webů | PM vybírá |
| **5 Tři směry** | viz FB-20 | PM vybírá |
| **6 Stavba** | celý front ve zvoleném směru | agent |
| **7 Ověření** | brána (FB-1 až FB-14), oprava, nový běh; revize stránek PM; projektový design standard | PM schvaluje |

**FB-18 Varianty.** Druh: web / webová aplikace / PWA. Značka: nová /
existující (bere se brand balíček) / žádná (vznikne ve fázi 1). Varianta určuje,
které řádky definice platí (FB-11 jen u aplikace; PWA navíc podle
[Oznámení v PWA](./pwa-notifications-standard)).

**FB-19 Plán obsahu.** Pro každou stránku a sekci: co je potřeba, kdo to dodá
(PM / klient / agent), do kdy a stav. Fakta žijí v **registru faktů**, ze
kterého čerpá stránka i kontrola FB-6. Nic se nevymýšlí a nepoužívají se
zástupné texty; co chybí, PM buď dodá, nebo vědomě odloží (sekce se pak
nestaví).

**FB-20 Tři směry.** Agent postaví tři směry jako skutečné stránky: první
obrazovka se skutečným obsahem, ne obrázek ani drátěný model. Každý nese
**prohlášení o jedinečnosti**: princip odvozený ze značky a vybraných
referencí, charakteristické komponenty a čím se liší od šablony. PM vybere,
nebo nechá směr vygenerovat znovu opatrněji / odvážněji s vlastním komentářem.
Jako heuristiku řemesla /aid-ui používá převzatá pravidla (skill frontend-design
od Anthropicu a craft floor z Impeccable, oba Apache 2.0, registrované
v pluginu); standardy mají přednost.

### Studio: průběh stavby

Stránka studia ukazuje celý běh jako šest kroků pod sebou (Druh webu, Zadání
a obsah, Vzory, Vzhled, Stavba, Kontrola). U každého kroku stojí jeho výsledek
jednou větou (u výběru z návrhů název vybraného návrhu) a kdo ho rozhodl:
PM, AI, nebo oba. Tlačítko Detail otevře rozhodnutí kroku v pořadí, jak
padla, s komentáři PM a s návrhy, ze kterých PM vybíral; čekající otázka stojí
přímo uvnitř svého kroku a odpovídá se na ni tam. Agent rozhoduje sám jen tam,
kde to postup kroku říká, nebo kde ho PM výslovně pověřil (fakt z podkladů,
doplnění pravidel podle standardu, výsledek stavby). Každé takové rozhodnutí
hned zapíše do záznamu rozhodnutí příkazem `aid-ui-state.sh decide` i s důvodem.
Co v záznamu není, pro PM neexistuje. Rozhodnutí doplněné do záznamu až po běhu
nese značku „doplněno zpětně".

![Studio po dokončeném běhu: šest kroků, u každého výsledek a kdo rozhodl](/img/aid-ui/studio-prubeh-stavby.png)

*Snímek: zkušební data (pilot Needless, 30. 9. 2026), ne skutečný klient.*

### Pohyb a měření (FB-25, FB-26, FB-27; 10.–12. 10. 2026)

- **FB-25 Úvodní overlay má jediný tvar:** prvek s atributem `data-aid-intro`, který do 10 s zmizí
  z dokumentu nebo dostane `display:none`. Brána (`motion_settled`) měří a fotí každou stránku až
  po doběhnutí konečných animací, 500 ms klidu a zmizení tohoto prvku, i po posunu; nekonečné
  animace nechává běžet. Zjasnění přes `opacity` je v pořádku; pohyb se kvůli bráně neosekává.
- **FB-26 Stavba nese pohyb vybraného vzoru** tak, jak ho zadavatel viděl u směrů
  (`.aid-ui/motion.json`): brána (`motion_fidelity`) úvodní stránku sama pozoruje (načtení, druhé
  načtení, posun, najetí, přechod stránky) a jmenuje pohyb, který neběžel. Bez vybraného vzoru N/A.
- **FB-27 Obsah je vidět bez skriptu, bez posunu a při omezeném pohybu.** Skryté výchozí stavy pohybu
  (opacity 0, posun, ořez) smí stránka nést jen pod `html.js` (třídu přidá řádek skriptu v `<head>`),
  odhalení prvků ve výřezu začne hned po načtení (ne až po kolečku) a při `prefers-reduced-motion`
  je vše čitelné hned. Brána: `content_without_js` (stránka s vypnutým skriptem ukazuje každý obsahový
  text, který ukazuje stránka se skriptem po doběhnutí pohybu a posunu) a `first_paint_visible` (hned
  po načtení, bez posunu, je čitelný h1 a první obsahový blok a nic čitelného není zesláblé; totéž pod
  omezeným pohybem). Zavedeno po retru klienta-agenta Coufal 11. 10. 2026 („prázdné stránky“).
- **FB-28 Formulář odesílá, nebo poctivě říká, co dělat.** Nikdy `mailto:` (otevře poštovní aplikaci
  návštěvníka, bez ní nefunguje). Odesílá se skriptem na koncový bod; během odesílání je tlačítko zamčené,
  stav je v živé oblasti (`role="status"`), chyba vždy nabídne klikací telefon nebo e-mail a úspěch se nikdy
  nepředstírá. Dokud koncový bod na hostingu neběží, je to kritický otevřený bod (publikace blokovaná).
  Brána: `form_states` (koncový bod podvrhne 404 a 200 a čte stavy). Zavedeno po retru klienta Coufal 11. 10. 2026.
- **FB-29 Co zákazník hledá, najde do dvou kroků.** Projekt má v `docs/content/tasks.yaml` úkoly
  zákazníka: konkrétní cena, otevírací doba, objednání formulářem. Každý hledaný text pochází z registru
  faktů (`docs/content/facts.yaml`), aby se úkol nedal usnadnit vymyšleným textem. Brána
  (`task_test`) jde z domovské stránky po odkazech nejvýš dva kroky, na počítači (1440 px) i na mobilu
  (390 px), a úkol, který nenajde, je selhání. Zavedeno se smyčkou kvality P113a 12. 10. 2026.
- **FB-30 Fotka, kterou klient teprve dodá, má místo v přesném tvaru.** Každá taková fotka je
  v `docs/content/photos.yaml` (stránka, místo, co na ní je, tvar `rect`/`round`, poměr stran, nejmenší
  rozměr v px). Na webu je rámeček `data-aid-photo="<id>"` v tomto poměru a tvaru s ikonou fotoaparátu:
  bez textu, `aria-hidden="true"`, nic v něm nejde zaměřit klávesnicí. Dodaná fotka se jen vloží
  (`<img>` přes celý rámeček, `object-fit: cover`, s popisem `alt`) a nic se neposune. Brána
  (`photo_slots`) vloží zkušební fotku jiného tvaru a měří, že rámeček ani stránka nezměnily velikost.
  Zadání fotek ukazuje stránka „co jste dostali“. Zavedeno P113a 12. 10. 2026 (rozhodnutí PM 1A).
- **FB-31 Text má odstup od dělicích čar.** Svislá dělicí čára mezi sloupci nebo bloky (jednostranný okraj
  bloku) má na obou stranách vnitřní odstup aspoň 16 px; text nikdy nezačíná ani nekončí těsně u čáry. Brána
  (`text_clearance`) měří každý řádek textu vedle čáry na všech stránkách a šířkách a pod 12 px hlásí selhání.
  Zavedeno 13. 10. 2026 po Coufalu (odpovědi nalepené na čáry prošly vším, chytil je až PM).
- **FB-32 Základy přístupnosti, které brána měří sama.** Stránka s navigací začíná odkazem „Přeskočit na
  obsah“ na existující cíl; nadpisy nepřeskakují úroveň (po h1 nikdy rovnou h3); obrys zaměření má proti tomu,
  co je za ovládacím prvkem, kontrast aspoň 3:1. Brána: `a11y_basics`. Zavedeno 13. 10. 2026 (kritik Coufal
  našel všechny tři ručně, brána je neměřila).
- **FB-33 Na telefonu jako na telefonu.** Styly pro najetí myší jen uvnitř `@media (hover: hover)`
  (na dotyku jinak „visí“ po klepnutí), přiblížení se nikdy nezakazuje (`user-scalable=no`, `maximum-scale=1`),
  písmo polí formuláře aspoň 16 px (jinak iOS stránku přiblíží). Brána: `mobile_native`. Zavedeno 13. 10. 2026
  s převzatou dovedností emil-skills/mobile-native (Coufal: 28 neohraničených hover pravidel).

## Exceptions — výjimky

- **Mimo rozsah:** nasazení, hosting a předání klientovi; redesign
  existujícího webu (samostatný pozdější plán).
- Neprošlé nebo nepokryté pravidlo definice smí zůstat jen s jmennou výjimkou
  PM (FB-17), zapsanou na stránce studia s důvodem.
- Interní nástroj bez veřejné tváře nemusí mít FB-9 og obrázek ani FB-14 SEO;
  výjimku zapíše PM stejně jako ostatní.

## Enforcement — jak se vynucuje

- /aid-ui nepustí front do stavu „hotovo", dokud brána neprojde nebo
  neprošlé řádky nemají výjimku, a dokud PM neschválí každou stránku.
- Kontroly FB-1 až FB-14 běží skriptem, ne úsudkem agenta; výsledek je vidět
  na stránce studia.
- Schválení PM (FB-16, FB-17) studio váže ke stránce, jejímu otisku a jedinému
  použití a před zápisem ho znovu ověří u běžícího studia. To zastaví agenta,
  který odpověď PM přeskočí nebo použije jinde, ne agenta, který soubory úmyslně
  padělá (klíč studia si agent přečíst může). Skutečnou kontrolou zůstává to,
  že PM hotový web projde stránku po stránce.
- Každé pravidlo má číslo, aby na něj mohla odkazovat mapa pokrytí standardů
  v pluginu AID; pravidlo, které /aid-ui nepoužívá, je tam viditelně označené
  „nepoužito, protože …".
