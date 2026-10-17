---
name: ui-design-local-logo
description: Vlastní vrstva kroku 1i (logo) z dílny P113 - rešerše a teze, šíře skic, síto odborníka, hloubkové kolo, oživení zavedené značky, klient a odborník na místě rozhodnutí. Čte se spolu s 1i-identity.md; převzatý logo-design zůstává beze změny.
---

# Logo: vlastní postup (dílna P113, ověřeno na zkušebním podniku 14. 10. 2026)

**Proč:** naslepo proti dnešnímu postupu (zkušební podnik, 9 směrů, hodnotili PM, odborník, klient) dal tento postup 2 ze 3 směrů,
které PM označil za nejlepší; dnešní postup dal 1 z 5 a jeho 3 směry PM odmítl. Dnešní postup nechává směry vybírat
agenta, který je vytvořil (fáze 4b „kurátorství“) – tak prošlo fádní první kolo Coufala.

**Nahrazuje:** `steps/1i-identity.md` fáze 2–4b (koncepty, generování, kurátorství); doplňuje místo rozhodnutí „logo“.
**Platí dál:** z `steps/1i-identity.md` rozcestník (situace, sloty), vstupy, brány balíčku a nástroje balíčku (body 5–8).

## 1. Rešerše a teze (před jakýmkoli obrázkem)

- Z podkladů vypiš, co je na podniku **vlastní** (jeho slova, produkt, místo, historie), ne co platí pro obor.
- Police konkurence z regionu (3–5 log, `refs/competitors/`) a klišé oboru, které na ní vidíš.
- **Teze** přebírá ze schváleného dokumentu o podniku (krok 1p, `sdeleni-postup.md`, oddíl Teze; rozhodnutí PM 2a). Jen když
  tam chybí (logo bez webu), napiš 4–6 vět, každá jedna zajímavá myšlenka z faktu podniku (Bob Gill: „jedna zajímavá věta“).
- Police konkurence pro logo i průzkum konkurence v 1p jsou jeden průzkum – nedělat dvakrát.
- U zavedeného loga **audit** (logo-design `redesign.md`) ve tvaru, který čtou role: poznávané prvky, **proč** je
  lidé poznávají (kde a jak dlouho se používají), výhradnost proti polici, slabiny, co podnik nechce, důvod k novému začátku.
- Směry = kombinace tezí. U zavedeného loga: 3 oživení + 2 nové (rozcestník situace redesign).

## 2. Šíře: skici přes obrazový model (levně)

- 5–6 skic na směr, `quality low`, jedna barva, bez textu, popis konstrukce jako zadání art directora.
  Dílna: 30 skic ≈ 0,5 USD, ~7 min při 2 souběžných požadavcích.
- Arch skic se štítky (`skici/arch.png`).
- (doplněno F7, neověřeno) Parametry: `aid-ui-logo-gen.py` s `mode: mark`, `quality low`, bez `two_step` (zákaz `mark`
  a požadavek `full`/`high` v 1i fázi 4 tu neplatí); u oživení dnešní logo jako reference. Sloty směrů (3 oživení +
  2 nové) zapsat do `route.json` ručně, dokud `aid-ui-logo-route.py` sloty oživení neumí; běhy s jinými referencemi
  zvlášť a `gen.json` po každém běhu zkopírovat (druhý běh ho přepíše). Strop `AID_UI_IMAGE_BUDGET_USD=1.0`
  a `--max-cost` (F7: 29 skic, 0,71 USD). Odmítnutí bezpečnostním filtrem modelu se neobchází.

## 3. Síto odborníka nad skicami

- Nezávislá instance v roli **odborník** (`critic/web-local.tech.logo.yaml`) dostane arch, zadání, audit, polici.
  Vybere 1–2 skici na směr k dotažení s „proč“ a „co opravit“, vyřadí falešná čtení (dílna: všechny skici
  jednoho směru se četly jako cizí iniciály – směr vypadl celý), klišé sdílená s konkurencí, skvrny v 16 px.
- Směr, ze kterého nic neprošlo, se klientovi neukazuje. Neobchází se.
- (doplněno F7, neověřeno) Na sítu platí z měřítka jen myšlenka, odlišnost, falešná čtení, klišé proti polici
  a čitelnost tvaru v 16 px; typografie, přesné proporce a kontexty až na kartách.
- (doplněno F7, neověřeno) Když se rada síta bije s polici (F7: kóta přes celou střechu → obrys domu jako
  u konkurenta), má přednost police; studio odchylku zapíše na kartu s důvodem a odborník ji posoudí.

## 4. Čistá kresba v kódu

- Vybrané skici se **překreslí geometricky** (shapely: tahy `buffer` s rovnými konci a ostrými rohy, booleovské
  operace; oblouky jako `A`, ne mnohoúhelník), ne vektorizací rastru. Model je skicář, kód je ruka.
- Název skutečným písmem (Google Fonts, OFL, latin-ext, ověřené na všech znacích názvu) převedeným na křivky.
- Tři řezy značky: **velký**, **střední** (32–48 px, detaily zesílené, koncovky zjednodušené) a **malý** (16 px,
  bez jemných detailů). ViewBox vždy čtvercový (vyžaduje ho `aid-ui-ico.py --check-svg`).

## 5. Karty a místo rozhodnutí

- Každý směr jako karta stejného formátu (`aid-ui-tool.sh logo-sheet --cards <spec>`): logo s názvem, značka zvětšená, 48/32/16 px
  (i zvětšené ×4), černobíle, inverzně, záložka, ikona telefonu, avatar, vizitka, cedule na stavbě, polep auta,
  tmavá hlavička. Role vidí jen karty, zadání, audit a polici – nikdy úvahy ani bodování studia.
- **Odborník** ohodnotí každou kartu (kotvy 4/6/8/10, důkaz, co chybí, `zavedeny_motiv`, `rezim`). Brány
  (`*.gates.yaml`) zná jen kód. Co neprojde, se opraví podle „co chybí“ nebo vyřadí.
- **Klient** (majitel, s pamětí výtek `podklady/historie.json`) z toho, co prošlo, vybere jeden směr, nebo vrátí
  s konkrétním důvodem. V ručním režimu vybírá PM a volba klienta se zaznamená vedle kvůli kalibraci.
  (doplněno F7, neověřeno) Liší-li se volba PM a klienta (F7: PM A, klient B), klient v hloubkovém kole hodnotí
  vybraný směr a jeho výtky k ostatním směrům platí jen tam, kde se týkají všech karet; klientova brána „můj podnik“
  pak padá z principu (F7: 6 < 8) – zaznamenat jako rozpor volby, ne jako vadu směru. Paměť klienta je jedna
  přes všechna místa i odpovědi ve studiu (`scripts/lib/aid_ui_memory.py`); rozhodnutí PM v ní stojí zvlášť.
- (doplněno F7, neověřeno) Karta nese i kontexty, které zadání jmenuje navíc (razítko výkresu, oděv, fólie):
  `logo-sheet --cards` je bere ze zadání značky.
- Malý řez (16 px) smí zkrátit nebo vypustit detail (svah, kótu), poměr hlavních tvarů zavedeného motivu drží.

## 6. Hloubkové kolo (vybraný směr)

- Odborník dá 3–5 **měřitelných** úprav (co, kde, o kolik); když je nedá jako seznam, studio ho sestaví z nálezů
  (`upravy-<směr>-kolo1.md`) a odborník v dalším kole potvrdí, že odpovídá (doplněno F7, neověřeno). Studio je zapracuje a pošle **tutéž** instanci
  odborníka (s pamětí) znovu; ten u každé minulé úpravy napíše stav. Klient (s pamětí) schválí nebo vrátí.
- Dílna: odborník 5,3 → 6,8 → 8,4 za dvě kola; klient schválil. Poslední výtky: koncovky detailů se v 32–48 px
  slévají (střední řez), pata písmen, odstín barvy proti zavedené.

## 7. Oživení zavedeného loga (pravidla, která role znají)

- Zavedený motiv (poznávaný a výhradný podle auditu) je hodnota podniku, ne oborové klišé – i když motiv kreslí
  i konkurent. Odlišnost se posuzuje podle provedení a **vlastního detailu** navázaného na fakt podniku.
- Čisté překreslení bez vlastního detailu („kosmetika“) se klientovi neukazuje (brána any_of: myšlenka nebo
  odlišnost ≥ 7).
- Směr, který zavedený motiv bez doloženého důvodu zahodí, klient nevybere.
- Zdroje: Romaniuk 2018 (Building Distinctive Brand Assets), Walsh, Winterich, Mittal 2010 (JPBM 19(2)),
  Airey 2014 kap. 5, Müller, Kocher, Crettaz 2013 (JBR 66(1)).

## 8. Náklady

- Obrázky jen ve fázi 2 (skici, `low`). Čistá kresba a karty bez obrazového modelu.
- Dílna celkem: skici ≈ 0,5 USD, odborník a klient ≈ 8 volání modelu. Dnešní postup: 1,88 USD a zastavil se
  o rozpočet projektu 2 USD před posledním směrem.
