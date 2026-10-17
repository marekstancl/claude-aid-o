---
name: ui-design-local-motion
description: Vlastní vrstva pro pohyb značky (dílna P113, F2) - pohybový jazyk ze značky, animované logo v sadě značky, hero z loga jako možnost ve vzhledu, pravidla, která projdou branami studia, odborník a klient na místě „pohyb“.
---

# Pohyb značky (ověřeno na zkušebním podniku 14. 10. 2026)

**Nahrazuje:** v `steps/1i-identity.md` bod 5 animované logo (součást sady značky), v `steps/5-directions.md` hero z loga
jako jednu z možností vzhledu a v `steps/6-build.md` zapojení pohybu značky do stavby.
**Platí dál:** nástroje a brány těchto kroků (`aid-ui-tool.sh motion`, `aid-ui-motion.py`, `build-record`).

Rozhodnutí PM (14. 10.): animované logo je součást sady značky (krok loga); hero z loga je jedna z možností ve
třech návrzích vzhledu; logo a hero nesou pohyb značky, zbytek stránky smí nést pohyb vzoru (krok 3–5).

## Pohybový jazyk
- Odvoď ho z tezí a ze stavby loga (ne z cizího webu): u zkušebního podniku (projekční kancelář) „rýsování“ – tenká konstrukční linka vede tah,
  tvar se vyplní; pořadí jako na výkrese: nejdřív předmět, pak kóty; název se odkryje spolu s kótou.
- Vlastní detail z oboru (kóta, razítko…) se kreslí i animuje **podle konvencí oboru** (kóta odsazená od předmětu,
  pomocné čáry z předmětu, kótuje se až nakreslený předmět) – hodnotitelé to sami nepoznají, PM to na zkušebním podniku našel.
- Tempo: téměř rovnoměrný tah s krátkým dojezdem, fáze se překrývají, žádné pružení, blikání, otáčení, zvětšování.
- **Limity (doplněno F7, neověřeno; rozhodnutí PM v F6 „B zkrácený“):**
  - **na webu** (hlavička, hero, úvodní obrazovka): značka se dokreslí **≤ 1 s** (dílna 0,9 s), detail oboru (kóta)
    400–500 ms, **jméno a podtitul čitelné od prvního snímku** (nekreslí se, neodkrývají se), po 1 s nic neběží;
  - **samostatné video a prezentace** smí delší verzi 2–3 s (konec drží ≥ 0,9 s, logo čitelné nejpozději v polovině);
    na web se nevkládá;
  - studio dodává **obě verze** a v podkladech pro role uvádí délku každé; verze pro web nad limitem se rolím
    nepředkládá. Důkaz: F6 – pohyb 1,6 s se skrytým jménem dostal u odborníka 5/10; F7 – běh podle tohoto souboru
    bez limitu udělal 2,06–2,2 s se skrytým jménem a obě role ho pustily (měřítko limit neznalo).

## Technika (projde branami studia)
- Jen CSS animace masek nad hotovými tvary; po doběhnutí jediná schválená cesta (žádné švy masek);
  `prefers-reduced-motion` a bez JS = hned konečný stav. Konečná geometrie = schválené SVG (ověřit rozdílem ploch 0).
- Hero: h1, podnadpis a tlačítko hotové od prvního snímku; kreslí se jen značka (aria-hidden). Na telefonu značka
  v hero nesmí stát před nadpisem; **pod obsahem (pod tlačítkem) je dovolená** (doplněno F7, neověřeno – klient F7:
  bez ní je půl obrazovky prázdné).
- Písma z webu (woff2), ne z Google Fonts před souhlasem.
- **Jak dosáhnout „jediné schválené cesty“ po doběhnutí (doplněno F7, neověřeno):** jediná vrstva schválených cest,
  maska se na konci vypne (`mask: none`) a tahy masky **přesahují rovné konce tvaru** (dílna 14 j. na 256); neanimovat
  `opacity` konečné vrstvy (zůstane složená na GPU, jiné vyhlazení) ani `visibility` s krokem 1 ms (zaokrouhlení
  průběhu). Měřit **šev**: snímek těsně před a po vypnutí masky, rozdíl ploch = 0 (F7: 292 → 4 px až po přesahu).
- **Mezistavy:** každý tah kreslí jen svůj kus tvaru (rozšíření ořezu nesmí odkrýt později kreslené kusy).
- **Kontroly pro samostatnou stránku loga** (doplněno F7, neověřeno): `motion_settled`, `reduced_motion`,
  `content_without_js`, rozdíl konečného snímku proti SVG; `first_paint_visible` platí jen pro hero (logo stránka nemá h1).
- **Podklady pro role:** pás snímků přesně – pozastavit animace a nastavovat `currentTime` (nezávislé na výkonu stroje),
  video nahráváním Playwrightu: `aid-ui-tool.sh strip` a `aid-ui-tool.sh video`; animaci z dílů značky dělá
  `aid-ui-logo-motion.py` (webová verze ≤ 1 s a video 2–3 s); limity pro brány měří `aid-ui-tool.sh motion measure`.
- **Hero v kroku pohybu je jen ukázka pro posouzení pohybu** (text ze schváleného sdělení); návrh hero patří do vzhledu.
- Ověření v dílně: kontroly studia (motion_settled, content_without_js, first_paint_visible, reduced_motion) beze
  změny logiky; zkušební podnik prošel na 1440 i 390, Coufalův hero neprošel (nadpis jen v obrázku).

## Místo rozhodnutí „pohyb“
- Odborník a klient s měřítky `critic/web-local.{tech,owner}.pohyb.yaml` (+ gates). Podklady: pás snímků po 40 ms
  (logo) a 200 ms (hero, i telefon), snímky s omezeným pohybem a bez JS, konečné snímky, metriky (CLS, rozdíl
  geometrie proti logu), výsledky kontrol. Dílna: odborník 7,4 → 8,2, klient schválil. Kolo místa: `aid-ui-quality.py round --place pohyb`;
  projekt bez pohybu jen výjimkou PM (`aid-ui-state.sh place-record --place pohyb --without <odpověď>`).

## Cesta k 10 (zatím neudělané)
- klidná varianta pro omezený pohyb (ne jen konečný stav), 1s verze loga, vlastní pohyb na telefonu,
  čtvercové video pro sociální sítě.
