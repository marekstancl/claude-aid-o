# P093 — počet řádků oblasti kontroly plánu, před a po

Před: `main` na commitu 3353a9db (před větví P093). Po: větev `feat/p093-plan-review`
před vydáním 2.98.0. Metoda: `git show 3353a9db:<soubor> | wc -l` pro „před",
`wc -l <soubor>` pro „po".

## Kód a data kontroly plánu

| Před | Řádků | Po | Řádků |
|---|---|---|---|
| `scripts/aid-cp1-gate.sh` | 719 | `scripts/aid-cp1-gate.sh` | 217 |
| `scripts/lib/aid-plan-band.sh` | 245 | — | 0 |
| `defaults/policies/risk-paths.yaml` | 91 | — | 0 |
| `defaults/policies/review-checkpoints.yaml` | 101 | `defaults/policies/review-checkpoints.yaml` | 61 |
| `scripts/lib/aid-cp1-ledger.sh` | 848 | — | 0 |
| `scripts/aid-c0-contract.sh` | 855 | — | 0 |
| `scripts/lib/aid-c0-plan-review.sh` | 1 871 | — | 0 |
| `defaults/prompts/c0-plan-review-prompt-v1.md` | 80 | `defaults/prompts/plan-review-prompt-v1.md` | 60 |
| `defaults/policies/c0-contract.yaml` | 5 | — | 0 |
| `defaults/schemas/c0-plan-review.schema.json` + `plan-review.schema.json` | 169 | `defaults/schemas/plan-review-finding.schema.json` | 46 |
| `skills/review-checkpoint-contracts.md` | 492 | `skills/review-checkpoint-contracts.md` | 208 |
| `scripts/tests/check-classification-reference.sh` | 125 | — | 0 |
| — | | `skills/plan-review-roles.md` | 212 |
| — | | `scripts/aid-plan-review-round.sh` | 465 |
| — | | `scripts/aid-plan-review-adjudicate.sh` | 166 |
| — | | `scripts/lib/aid-plan-review-config.sh` | 130 |
| — | | `scripts/lib/aid-plan-review-packet.sh` | 176 |
| — | | `scripts/lib/aid-plan-review-summary.sh` | 52 |
| — | | `scripts/lib/aid-plan-review-adapter-claude.md` | 54 |
| **Celkem** | **5 601** | | **1 847** |

## Instrukce pro agenta (celé soubory)

| Soubor | Před | Po |
|---|---|---|
| `commands/aid-plan.md` | 1 052 | 740 |
| `skills/plan-writing.md` | 1 487 | 1 426 |

## Testy

Smazané sady starého řetězce (ledger, C0 smyčka a graf, C0 smlouva, grounding,
stará brána, pásma): 5 130 řádků. Nové sady kontroly plánu (schéma, konfigurace,
kolo, rozhodčí, souhrn, brána, akceptace): 902 řádků.

## Celý plugin

`git diff --shortstat 3353a9db -- plugins/aid-orchestrator` bez fixture
akceptačního běhu: 131 souborů, +3 383 / −12 956 řádků.
