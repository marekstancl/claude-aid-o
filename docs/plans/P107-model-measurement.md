# P107 — Sonnet on the code-writing cards: the Opus baseline and the return rule

**Decided:** PM 2026-09-30 (1A): implementer `sonnet`/`high`, implementer-light `sonnet`/`medium`,
gate-fixer `sonnet`/`medium`; every reviewer, verifier and scanner stays on Opus. UI DESIGN
(`/aid-ui`, the brainstorm) is never Sonnet: it runs in the session on Fable. UI IMPLEMENTATION by
plan steps (role `frontend`) runs on Sonnet "but it must work" — hence this record.

## Baseline on Opus 5.5 (before 2.112.0)

CP2 round-1 blocker+major findings per step, by the step's role, from
`.aid-o/work/evidence/E-102-*/*/cp2/step-*/round-1/merged.json` and `E-103-*` (plans P102 and
P103, plugin 2.108.0–2.111.0), the role read from the run's `plan.json`. Computed 2026-09-30:

| Role | Steps | Blocker+major | Per step |
|---|---|---|---|
| backend | 7 | 1 | 0.14 |
| docs-writer | 5 | 1 | 0.20 |
| frontend | 3 | 3 | 1.00 |
| qa | 2 | 2 | 1.00 |
| release | 1 | 0 | 0.00 |
| **all** | **18** | **7** | **0.39** |

Per-step rows: E-102-1_3 0/0/0 (backend, docs-writer, backend); E-102-2_3 0/0/1/0/0
(docs-writer, frontend, docs-writer, backend, backend); E-102-3_3 1/0 (qa, release);
E-103-1_3 0/0/3/1 (docs-writer, backend, frontend, backend); E-103-2_3 0/0 (docs-writer,
frontend); E-103-3_3 1/0 (qa, backend).

## The return rule (PM decides over the numbers)

After the first two plans with `frontend` steps built on Sonnet: if CP2 round-1 blocker+major
per frontend step exceeds the Opus baseline (1.00) by more than half (> 1.50), the PM decides
whether `frontend` returns to Opus — `**Model:** opus` on its role card in
`skills/role-cards.md`, or `step.model: opus` per plan. The same table is computed for the
other roles and shown next to this one; the decision is the PM's, not a threshold in code.

Command to recompute — run in the project whose plans are measured, naming the EPIC ids of the
plans to compare (for the Sonnet side: the first two plans with frontend steps after 2.112.0;
for the baseline: the P102/P103 EPICs above). The role is read from the `plan.json` that sits
beside each run's evidence, never from another EPIC's plan:

```bash
# usage: measure E-108-1_2 E-108-2_2 …   (EPIC ids under .aid-o/work/evidence)
for e in "$@"; do
  for r in .aid-o/work/evidence/$e/*/cp2/step-*/round-1/merged.json; do [ -f "$r" ] || continue
    run="${r%/cp2/*}"; pj="$run/plan.json"; [ -f "$pj" ] || pj="$(ls "$run"/../*/plan.json 2>/dev/null | head -1)"
    idx=$(echo "$r" | sed -E 's#.*/step-([0-9]+)/.*#\1#'); role=$(jq -r ".steps[$idx].role" "$pj")
    echo "$e step-$idx $role $(jq '[.findings[]|select(.severity=="blocker" or .severity=="major")]|length' "$r")"
  done
done | awk '{c[$3]++; s[$3]+=$4} END{for(r in c) printf "%s %d steps %d b/m %.2f\n", r, c[r], s[r], s[r]/c[r]}'
```
