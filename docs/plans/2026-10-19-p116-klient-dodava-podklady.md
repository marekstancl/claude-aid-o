# Zadání: klient-agent dodává podklady, které kritik vrátil „dodá klient“ (P116, PM 19. 10. 2026, 1A + 2A)

## Proč
Smyčka kvality /aid-ui (aid-ui-quality.py) označí nález role s owner=client jako `blocked "client supplies it"` a
readiness položky role (seznam „co musí dodat klient“) jen sbírá; nikdo je nedodá, ukážou se až ve verdiktu místa.
Studio už má nezávislého klienta-agenta (aid-ui-client.py answer: hraje vlastníka, odpovídá jen z podkladů projektu,
Opus, záskok Codex). PM chce autonomní běh: podklady dodá klient-agent, „musí kritikovi vyhovět na základě něčeho“,
PM na konci jen vidí, co bylo rozhodnuto bez něj. Druhé rozhodnutí (2A): model obrazovek a úloh aplikace smí
schválit klient-agent stejně jako ostatní místa studia (dnes jen PM - app_tasks_need_owner).

## Co se mění
1. `aid-ui-client.py supply <project> --place <p>`: položky = nálezy posledního kola místa s owner=client
   + readiness položky posledního kola (obě role), bez těch, které už mají záznam. Jedno volání role klienta
   (stejná role a paměť jako answer, role=True) s položkami. Odpověď na každou položku:
   - `supplied`: odpověď + `source` „soubor:řádek“ v projektu (soubor existuje, řádek v jeho rozsahu) - fakt z podkladů;
   - `decided`: odpověď + `reason` (≥ 10 znaků) - volba vlastníka bez faktu v podkladech (jméno obrazovky, výchozí
     hodnota nastavení); nikdy ne fakt (číslo, postup, smlouva), který v podkladech není;
   - `missing`: co chybí a kdo to musí dodat - zůstává otevřené pro PM.
   Neúplná nebo neplatná odpověď = jedno opakování s důvodem, pak záskok (jako answer). Zápis
   `.aid-ui/client/supplied.json` {items: {<klíč>: {place, round, kind finding|readiness, id, text, status, answer,
   source|reason|missing, provider, at}}}; klíč nálezu = jeho id, readiness = "ready:" + sha256(text)[:12].
2. Smyčka (`aid-ui-quality.py status/round`): nová decision `supply`, když poslední kolo má klientskou položku bez
   záznamu (před fix/round; po triage a conflict). `round` ji odmítne. Nález owner=client se záznamem supplied/decided
   a stále `blocked "client supplies it"` je pro smyčku nález bez stavu (decision triage): agent ho přijme a opraví
   podle odpovědi. `missing` zůstává blocked. Launch smyčka beze změny (readiness tam je nasazení).
3. Role vidí, co klient dodal: `supplied.json` jde do podkladů místa (podklady/klient-dodal.json) u všech míst.
4. `aid-ui-client.py decided <project>`: lidský seznam toho, co rozhodl klient-agent bez PM - odpovědi studia
   s by: client (feedback.jsonl) a záznamy supplied/decided se zdrojem nebo důvodem; zvlášť `missing` = co
   zbývá na PM. Exit 0.
5. 2A: `app_tasks_need_owner` přijme schválení modelu od pm i od klienta (by: client); baseline a odebrání dnešní
   úlohy (app_owner_only) zůstávají jen PM (data existující aplikace, mimo rozhodnutí).
6. Podklady klienta (client-template.md): u aplikace i zadání a plány v docs/ (docs/plans/) a model docs/design/screens.json.
7. Dokumentace ve stejném kroku: hlavička aid-ui-client.py a aid-ui-quality.py, SKILL.md (smyčka), aplikace-postup.md,
   commands/aid-ui.md, Docusaurus /aid/commands/aid-ui, CHANGELOG při vydání.

## Hotovo když
- A1 supply zapíše supplied/decided/missing; supplied s neexistujícím souborem nebo řádkem mimo rozsah je odmítnut
  (test se stubem modelu); položky se záznamem se znovu neposílají.
- A2 status: klientská položka bez záznamu → decision supply a round odmítne; po supply nález supplied → triage;
  missing → zůstává blocked a smyčka pokračuje.
- A3 bundle místa obsahuje klient-dodal.json, když existuje.
- A4 decided vypíše rozhodnuté i chybějící položky lidsky.
- A5 schválení modelu aplikace klientem se zapíše; baseline klientem dál odmítnuto.
- A6 stávající sady quality, client, critic, state, app zelené; dokumentace odpovídá kódu.
