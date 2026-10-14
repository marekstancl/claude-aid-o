# P113a bod 8: méně kol, víc rozdílů

Zadání P113a (12. 10. 2026) bod 8: „Otázky po kole ukazují jen rozdíl proti minulé verzi; související rozhodnutí se
slučují do milníků; kritik dostává živý web.“ Kritik živý web už dostává (smyčka kvality). Zbývají první dvě části.

## Proč (data z Coufala, 11.–13. 10. 2026)

Klient-agent dostal ve studiu přes 85 otázek, 33 z nich vrátil. Nejvíc opakování:

| Druh otázky | Kolikrát |
|---|---|
| schválení stránky (`approve_page`) | 21 |
| výjimka brány (`exception`) | 9 |
| SEO zadání | 8 |
| fakta | 8 |
| plán obsahu | 7 |

- **Celý text znovu:** opakovaná otázka (po vrácení nebo po změně) ukazuje celý dokument znovu a klient hledá, co se
  změnilo. Při SEO zadání 13. 10. kvůli tomu přehlédl rozbitý řádek tabulky.
- **Každá stránka zvlášť:** po změně společného stylu přišlo 9 otázek (8 stránek a styl). Schválení stránek bylo
  21 otázek.

## Co se staví

### A. Rozdíl proti minulé verzi

- **Kdy se rozdíl ukáže:** otázka má `prior.question` a míří na tentýž soubor jako předchozí otázka, jen v jiné
  verzi (`target` = `<cesta>@<sha>` s jiným sha). Studio pak nahoře ukáže **jen změněné řádky** jako rozdíl
  s 2 řádky kontextu, nejvýš 60 řádků, a pod tím sbalené celé znění.
  - Bez změny ukáže „beze změny proti verzi, kterou jste viděli“.
  - Rozdíl delší než 60 řádků se zkrátí s počtem vynechaných řádků.
- **Snímky verzí:** server při načtení `payload.json` uloží obsah každého souborového cíle otázky do
  `.aid-ui/studio/snapshots/<sha>`, jen když se sha souboru shoduje s cílem a cesta je uvnitř projektu.
  Starší verzi tak má odkud vzít. Chybí-li snímek předchozí verze, ukáže celé znění s větou „předchozí verzi nemám,
  ukazuji celé znění“.
- **Schválení stránky** (`approve_page`, cíl `stránka@otisk`): rozdíl viditelného textu stránky proti verzi, kterou
  klient minule viděl. Snímek je text stránky z `site/` při otevření otázky.
- **Klient-agent** dostane rozdíl v promptu stejně jako PM, před celým zněním.

### B. Milníky: související rozhodnutí v jedné otázce

- **Otázka s položkami:** druhy `approve_page` a `exception` smí nést pole `items`:
  `[{id, title, target, preview?}]`, kde `target` je cíl té položky jako u samostatné otázky.
- **Odpověď:**
  - `approve` = vše schváleno,
  - `return` s `items: {<id>: "<komentář>"}` = vráceny jen jmenované položky, ostatní schválené.

  Studio zobrazí seznam s možností vrátit jednotlivou položku.
- **Zápis:** `aid-ui-state.sh record-answer` zapíše za každou položku samostatnou odpověď s id `<otázka>#<položka>`,
  druhem a cílem té položky a jejím rozhodnutím. Dnešní příkazy (`approve-page <stránka> --answer <otázka>#<položka>`,
  výjimky) tak fungují beze změny.
- **Postup (krok 6 a 7):** po přestavbě se schválení všech změněných stránek a společného stylu posílá jako jeden
  milník. Výjimky brány z jednoho okruhu jako druhý.

## Co se nemění

- Otázky bez `prior` a bez `items` vypadají jako dnes.
- Kontrola, že odpověď patří k aktuálnímu cíli (sha a otisk), zůstává u každé položky.

## Hotovo když

1. Opakovaná otázka na soubor ukáže rozdíl proti verzi z předchozí otázky (test: SEO zadání se změnou jednoho řádku
   → studio i prompt klienta obsahují jen ten řádek s kontextem a celé znění sbalené).
2. Bez snímku předchozí verze ukáže celé znění s vysvětlující větou (test).
3. Opakované schválení stránky ukáže rozdíl viditelného textu (test).
4. Otázka `approve_page` s 9 položkami: jedno `approve` dá 9 schválení přes `approve-page … --answer q#položka`.
   `return` jedné položky vrátí jen ji a ostatních 8 projde (test).
5. Cíl položky, který neodpovídá aktuálnímu buildu, se odmítne stejně jako u samostatné otázky (test).
6. Studio zobrazí seznam položek a umí vrátit jednu. Klient-agent umí odpovědět s `items` (test).
7. Krok 6 a 7 posílají schválení stránek a výjimky jako milník. Dokumentace (SKILL.md, kroky, CHANGELOG) to popisuje.

## Mimo rozsah

- Slučování jiných druhů otázek: fakta, plán obsahu a SEO zůstávají samostatné, ale dostanou rozdíl.
- Úspora se změří až na dalším webu (Coufal je odložený).

## Revize zadání (Codex, 14. 10. 2026) – co přebírám

1. Odkaz na předchozí otázku je **nové pole `previous`** (id starší otázky), ne `prior` (to dál nese předchozí volbu
   u směru). Server ověří: otázka `previous` existuje, je starší, stejného druhu a míří na stejnou cestu.
2. **Žádná odvozená id odpovědí.** Odpověď milníku zůstává jedna (id otázky) s mapou položek. Spotřeba položky:
   `approve-page <stránka> --answer <otázka> --item <id>`. `take_answer` ověří položku v odpovědi a do `consumed`
   zapíše `<otázka>#<položka>` jako text, takže jedna položka jde spotřebovat jen jednou.
3. `record-answer` zapisuje milník **jedním zápisem pod zámkem stavu**, tak jako dnes jednu odpověď.
4. Odpověď milníku nese **`items_sha256`** nad kanonickými `{id, kind, target}` položek. Ověřuje se při záznamu
   a při spotřebě. Změněný seznam = neplatná odpověď.
5. **Cesty a snímky:**
   - cíl je soubor uvnitř projektu po `realpath`, žádný symlink ani `..`,
   - obsah se čte jednou a hashuje přečtené bajty,
   - snímek se zapisuje přes dočasný soubor a přejmenování a nikdy nepřepisuje existující.
6. Formát cíle zůstává `<cesta>@<sha256>` (64 hex, sha256 obsahu souboru), dělí se podle posledního `@`.
   Strukturovaný cíl *nepřebírám*: byla by to změna všech dnešních druhů otázek.
7. Snímek verze vzniká **při prvním vydání otázky** ve `/state`. „Verze, kterou klient viděl“ = cíl otázky
   `previous`, na kterou odpověděl.
8. Rozdíl stránky = rozdíl **bloků subjektu kontroly textů** (`aid-ui-verify.sh --copy-subject`: text bloků, title,
   description) proti snímku z doby otázky `previous`. Společný styl je vlastní položka bez textového rozdílu,
   s větou „změnil se vzhled, viz náhled“ a odkazem na náhled.
9. **`return` milníku:**
   - `items` musí být přesná neprázdná podmnožina známých unikátních id, každé s neprázdným komentářem,
   - server zapíše úplnou mapu: vrácené položky + `approved` pro všechny ostatní, výslovně,
   - neznámé, duplicitní nebo prázdné → 422.
10. **Měřitelnost:**
    - přestavba se změnou N stránek a stylu = 1 otázka schválení místo N+1 (test),
    - opakovaná souborová otázka dá klientovi v promptu **jen rozdíl + sha celého znění**; celé znění jen bez snímku
      (test délky promptu),
    - slučování dalších druhů (fakta, plán obsahu, SEO) jde do backlogu jako IMP-698 pro P113.

## Revize implementace (Codex, 14. 10. 2026)

Přijato a opraveno:
- rozdíl po položkách milníku,
- celé znění, když chybí snímek,
- `previous` musí být zodpovězená,
- snímek stránky jen pro otisk zaznamenaného buildu,
- duplicitní klíče v odpovědi dávají 422 (u všech těl požadavků),
- dočasný soubor snímku je jedinečný pro každý zápis,
- sha celého znění je v promptu klienta,
- žádný symlink na cestě a čtení s `O_NOFOLLOW`,
- věta u společného stylu.

Bod „N stránek = 1 otázka“ je místo testu na počet **vynucený kódem**: studio odmítne víc než jednu otevřenou
samostatnou otázku `approve_page`.

*Nepřebráno:* výtah textu stránky ze subjektu kontroly textů (`--copy-subject`). Studio ho neumí spustit (jde
o prohlížečový běh brány), proto má vlastní výtah textu „čtenář v1“ (title, description, text bloků bez skriptů
a stylů). Rozdíl slouží člověku k orientaci, ne kontrole textů.

Krok 6 se nemění: schvalování stránek je v kroku 7 (bod 5), proto „kroky 6 a 7“ v Hotovo 7 = kroky 1s a 7.
