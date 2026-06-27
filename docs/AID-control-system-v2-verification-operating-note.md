# AID Control System v2 - verification operating note

Status: active working note
Created: 2026-06-26
Source case: E-050 delivery gate verification loop

## Why this note exists

E-050 ukazal, ze nestaci dodat kontrolni skript a nechat agenta napsat
"vse proslo". Overeni musi prokazat tri veci:

1. dodany mechanismus opravdu bezi proti aktualnimu HEAD,
2. evidence je ulozena v kanonicke AID ceste, ne jen v `/tmp`,
3. kontrola umi i selhat na spatnem vstupu, ne pouze vratit zeleny exit code.

Tento postup se ma pouzit i u dalsich planu v serii AID Control System v2.
Pri dalsim planu/EPICu ma reviewer uzivateli znovu nabidnout stejny
interaktivni use case: implementator doda evidence pack, nezavisly reviewer
ho overi primo v repu, vrati konkretni nalezy, implementator opravi, reviewer
opakuje kontrolu. Release az po PASS.

## Kdy kterou kontrolu delat

### 1. Po napsani planu, pred implementaci

Pouzit pro kazdy executable plan v Control System v2.

Cil: overit, ze plan neni jen textovy zamer, ale ma overitelny kontrakt.

Kontrola ma potvrdit:

- plan rika, jake artefakty vzniknou,
- kazde AC ma konkretni verification recipe,
- existuji pozitivni i negativni kontroly,
- je jasne, co je observe-only a co je blocking,
- je jasne, kde bude kanonicka evidence,
- plan nepredpoklada, ze soucasne CP/Auditor/Curator jsou spravne jen proto,
  ze existuji.

Vystup: plan PASS / REVISE pred `/aid-run`.

### 2. Po kazdem implementacnim EPICu pred DONE/review

Pouzit povinne pro kazdy EPIC, ktery meni kontrolni system, FSM, evidence,
validator, delivery gate, CP/Auditor/Curator, P048 visual guard nebo release
rozhodovani.

Cil: E-050 style evidence pack.

Implementator musi dodat:

- `git status` a HEAD,
- seznam commitu od base,
- kanonickou cestu k artefaktum v `.aid-o/work/evidence/...`,
- summary hlavniho artefaktu,
- validaci proti aktualnimu HEAD, napr. `--current-head "$(git rev-parse HEAD)"`,
- deterministicke testy,
- negativni kontroly pro nove/menene guardy,
- performance/cost, pokud kontrola spousti build/test/typecheck nebo LLM,
- explicitni vysvetleni, zda je vysledek observe-only nebo blocking.

Reviewer musi nezavisle spustit minimalne:

- `git status --short --branch`,
- `git rev-parse HEAD`,
- validaci kanonickeho artefaktu proti HEAD,
- relevantni fingerprint/schema kontrolu,
- alespon jednu negativni kontrolu pro novy guard,
- test nebo smoke, ktery dokazuje wiring v realnem toku.

Vystup: EPIC PASS / PASS WITH CONDITION / FAIL.

### 3. Po kazde opravne iteraci

Pouzit vzdy, kdyz reviewer najde HIGH/MEDIUM problem a implementator tvrdi,
ze je opraveno.

Cil: neoverovat jen posledni tvrzeni, ale znovu overit puvodni failure mode.

Reviewer musi zopakovat:

- puvodni failing prikaz nebo fixture,
- validaci aktualni evidence proti HEAD,
- kontrolu, ze worktree je cisty,
- kontrolu, ze nova evidence neni jen v `/tmp`.

Maximalne dve az tri iterace. Pokud se stejny typ problemu vraci, zastavit
release a vytvorit samostatny fix plan.

### 4. Pred release/merge

Pouzit vzdy.

Cil: posledni release gate nesmi byt zalozeny na zastarale nebo nekonzistentni
evidenci.

Minimalni release checklist:

- worktree clean,
- canonical evidence exists,
- artifact `revision.head_sha == git rev-parse HEAD`,
- `head_is_current` a `freshness` odpovidaji realite,
- schema/fingerprint/head validation exit 0,
- zadny HIGH/MEDIUM nalez bez explicitniho waiveru,
- observe-only fail je pojmenovan jako telemetry, ne jako ignorovana blokace.

### 5. Po merge do main

Pouzit pro zmeny, ktere meni sdilene kontrolni mechanismy.

Cil: overit, ze integrace neztratila wiring.

Minimalni kontrola:

- spustit levny smoke na main,
- overit, ze nove registry entries jsou stale viditelne pro guard,
- overit, ze verze evidence/protokolu odpovida aktualnimu kodu.

## E-050 learned checks

Tyto chyby se v E-050 realne objevily a maji byt hledane znovu:

- evidence v `/tmp` misto kanonicke `.aid-o/work/evidence/...`,
- artifact tvrdi `head_is_current: true`, ale `revision.head_sha` neni HEAD,
- validator spusten bez `--current-head`, takze nechytne stale evidence,
- guard ma zeleny exit code, ale neparsuje realny format dat,
- chybi negativni fixture dokazujici, ze guard umi selhat,
- worktree neni cisty po poslednim commitu,
- delivery gate `delivery_ready=false` neni vysvetleny jako observe-only,
- performance neni uvedena a dlouhy beh vypada jako zasek.

## Interactive use case to repeat

1. Implementator oznami DONE a doda evidence pack.
2. Reviewer nezavisle overi pack primo v repu.
3. Reviewer vrati konkretni nalezy vcetne prikazu, ktere selhaly.
4. Implementator opravi a doda novy pack.
5. Reviewer opakuje pouze relevantni kontroly plus freshness/head kontrolu.
6. Release se povoli az po explicitnim PASS.

Tento use case ma byt uzivateli nabidnut po kazdem dalsim planu v Control
System v2, kde se dodava dalsi cast kontrolniho retezce.

## Hlidaci pravidlo pro dalsi plan v serii

Pri dalsim planu Control System v2 se reviewer musi zeptat:

"Je to plan-time, EPIC-time, fix-loop, nebo release-time kontrola?"

Podle odpovedi se vybere sekce vyse. Pokud je zmena soucast kontrolniho
systemu, default je EPIC-time + release-time. Pokud plan teprve vznikl,
default je plan-time.

## Relation to automation

Toto je zatim rucni provozni pravidlo. Cilovy stav Control System v2 je, aby
ho pozdeji vynucoval system:

- implementator vygeneruje `verify-input-manifest`,
- nezavisly verifier bezi v cistem kontextu,
- vysledek se ulozi jako `independent-verification.json`,
- C4/release rozhodnuti nesmi projit bez aktualniho PASS nebo explicitniho
  waiveru.

Do te doby se tento dokument pouziva jako manualni checklist.
