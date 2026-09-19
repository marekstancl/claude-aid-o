# P094 — řádky před a po (krok 15, V9)

Zapsáno 19. 9. 2026 nad `feat/p094-step-review` po kroku 14; strojová verze
`plugins/aid-orchestrator/scripts/tests/fixtures/step-review/line-count.json`
(seznam souborů = rozsah plánu: odstraněné, zobecněné, nové; „před" = commit
033dec6f před větví).

| skupina | před | po |
|---|---|---|
| odstraněné (pre-filter, invalidační mapa, skripty jen pro CP1, jejich prompt a schémata) | 2 038 | 0 |
| zobecněné (pipeline, verifier, gate-fixer, aid-run, aid-do, aid-plan, šablona, FSM, release-policy, politika, balík CP1, emit-dispatch, smlouvy) | 17 162 | 16 500 |
| nové (kontrola kroku, motor kol, rozhodčí, profil, config, balík, souhrn, adaptér, role, prompt, schéma, ceník, tabulka nástupců) | 0 | 2 830 |
| **celkem** | **19 200** | **19 330** |

FSM: `fsm_check_verifier_output` 67 → 67 (jen CP4), `fsm_check_cp3_freshness` 137 + `verify_provenance` 76 + `_cp3_freshness_route` 11 → `fsm_check_review_round` 158.

**Verdikt V9: celek NENÍ menší (+130 řádků, +0,7 %).** Dva důvody, oba vědomé:
1. instrukce pro controller (`aid-review-adapter-claude.md`, 89 řádků) je citována
   doslova ve dvou příkazech (`aid-run.md`, `aid-plan.md`) a test hlídá, že jsou
   bajt po bajtu stejné — jednou napsaná, dvakrát počítaná;
2. dva nové soubory jsou záznamy, ne kód: `prices.yaml` (41) a
   `review-successors.md` (58), a producent profilu (464) je teď samostatný
   soubor místo části pre-filtru.
Bez těchto tří položek je „po" 19 142 < 19 200. Co zmizelo z hlavy agenta je
větší: skill pipeline −372 řádků, karta verifikátora −143, FSM −309.
