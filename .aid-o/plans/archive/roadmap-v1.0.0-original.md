> **ARCHIVED 2026-08-10.** This is the original road map to v1.0.0 (P001–P006
> era). Every plan it schedules is long done or long superseded; the project is
> at v2.82.0 with P081 in planning. Kept as the earliest record of intent — the
> live delivery order is
> `docs/plans/2026-07-23-POST-P064-TO-E10-EXECUTION-CHECKLIST.md`.

Road map to version 1.0.0


Plány — souhrn
#	Plán	Soubor	Stav
1	Core Structure Refactoring	P002-core-structure-refactoring.md	Nový
2	Onboarding & Setup v2	P006-onboarding-setup-v2.md	Nový
3	Brainstorming Enhancement	P004-brainstorming-enhancement.md	Nový
4	FIRST AID Auto Mode	P003-first-aid-auto-mode.md	Nový
5	Release Protocol	P001-release-protocol-open.md	Aktualizován
Pořadí spouštění

FÁZE 1 (musí být první):
  ► P002  Core Structure Refactoring
    - plan_ref injection (nejvyšší priorita!)
    - SESSION→RUN, nové ID, evidence flatten, cost removal
    - Blokuje vše ostatní

FÁZE 2 (paralelně po Fázi 1):
  ► P004  Brainstorming Enhancement       ─┐
    - Hlubší analýza + 3 options pattern   │ paralelně
                                            │
  ► P001  Release Protocol                ─┘
    - Git tags, GitHub Releases, auto-mode integrace

FÁZE 3 (po Fázi 1, paralelně s Fází 2):
  ► P006  Onboarding & Setup v2           ─┐
    - GitHub detekce, docs, skill konflikty │ paralelně
                                            │
  ► P003  FIRST AID Auto Mode             ─┘
    - Autonomní orchestrace, permissions

FÁZE 4 (odloženo):
  ○ P005  GUI Dashboard — až bude struktura stabilní
  ○ Deep Testing (9b) — gate pro v1.0.0, po všem ostatním
  ○ Fast Mode (6) — musí uzrát






1) Detekce - čili init / setup 
- zda máme git / nebo i github v daném projektu
- existující dokumentace 
    - zda ji chce, zda to bude GH public repo --> pak asi github pages?
    - pokud nebude free tak co? Docusaurus? jiné? mít na to připraveny instrukce (skill?)
- detekce existujícísch skill které můžou být v konfliktu s našimi a deaktivace (viz bod3)
- jednodušší, více user fiednly inicializace nové verze
- doporučení na verzi Claude Code

2) Dokumentace projketu --> závicí na 1
- potřebujeme aby dokumentace a její aktualizace byly prioritou ve všech agentech/ skillech a intrukcích, kde to dává smysl, ať už pro read / nebo write /nebo audit!!
-> musíme vytvořit dokumentaci pro AID -> protože ji nemáme!!

3) Aid-Brainstorm
- potřeba prověřit zda jsme schopni zakázat Claude Default skills v tomto repo, často se stává že se pustí Claude Brainstorming skill namísto našeho
- vylepšení Aid-Brainstrom:
    - respektujeme co máme (to je dobrý základ!!!!), jen potřebuju upravit chování a to tak, PM zadá nějaký vstupní zadání, Ai zanalyzuje zadání a dá 3 možnosti které připadají v úvadu a taky jednu kterou doporučuje a proč. Mělo by dojít k většmu zamyšlení AI, aby návrh opravdu dával smysl a současně musí respektovat další pokyny v našem AI skillu (např WF, examples atd.)
    - stejné chování, pak bude v rámci každého kroku brainstormingu, AI napíše 3 možnosti, jakým směrem se můžeme ubírat a doporučená kterou možnost by volil a proč.

4) Refaktoring PLAN / EPIC / SESSION
- v teoretické rovině úvaha, potřebujeme to takto, dává to vůbec názvově smysl, v návaznost na best praktice a používané terminologie?
- používají agenti z každého souboru všechny informace, mají tyto soubory každý unikátní obsah?
- aktuálně používám UID, chtěl bych asi nahradit autoincrementem, kde PLAN/EPIC/SESSION ponesou stejné číslo
- odebrat info o ceně - stále tam je, prostě úplně dát pryč.
- v evidence máme spoustu složek, které se nevyužívají, k čemu jsou, proč se nevužívají? (gates, discovered issue, parallel groups, analyssi, prompts), sessions --> tuto nechápu, proč tam jsou jen 2? protože process nefunguje jak má?

5) Automatic Mode / WF refactoring
- aktuálně když spustím plan epic, tak po jeho dokončení musím zase znovu, spousta klikání,
- co když si naplánuju několik epiků i z různých plánů, a chci, aby je prostě orchestrárot udělal.
- tedy PM dává approve na začátku, o vše ostatní se starají agenti, který dělají kontroly za něj.
- reporting budeme mít k dispozici, protože budeme dělat GUI
- problém: potřebujueme dát ai skoro plnou kontrolu, jak na to? aktuálně hromada ptaní na přístupy spuštění kodu apod? SU permission with restrictions to system foleders for e.g.? + rozšížení reccomended viz json v aktuálním projektu

6) Fast mode / Quick Fixes
- nějaký mod, který umožní více manuální práce, tedy více adoptace skilů z původního cicera, případě claude, jejich přepis, pro naše potřeby, protože v některých případech není třeba absolvovat strikte všechny gates atd. 

7) Release protokol a verzování - viz 05aa
- toto musíme probrat, potřebuju rychlost navyšování snížit dle mě, to bychom za chvíli byly na V10,... i když dle mě nemáme ani v1

8) GUI - viz 4d9d
- musíme ještě dořešit, jak bude vzhled vypadat. 

9) Ideas under plans

9) Deep testing a Audit vech WF, na větším projektu, ale řízeně tak aby se opravu otestovalo co nejvíce zásadní funkcionality.

