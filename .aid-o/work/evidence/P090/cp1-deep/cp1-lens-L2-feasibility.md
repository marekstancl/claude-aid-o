# CP1-deep L2 — feasibility lens (P090)

Plan: `.aid-o/plans/P090-fronta-ktera-nezastavi.md`
Lens: touched files, output contracts, parser/producer ordering, implementability
Reviewer: controller (single-provider)

stop_rule_blockers: []

findings:
  - id: L2-1
    severity: high
    title: Step 5 contradicts itself about what the dispatcher does at `stop_hook_active`
    evidence: |
      Architecture Context (corrected in round 4): "`aid-hook.sh:315-319` … nastaví `no_block=1`:
      pravidlo **se pořád provede a smí mluvit**, jen z něj nesmí vzejít odmítnutí."
      Edge Cases, three paragraphs later, still says: "`stop_hook_active: true` → dispatcher
      pravidlo stejně **nepustí**; sada to ověřuje".
      The dispatcher's actual behaviour is the first one: `no_block=1` suppresses a REFUSAL; every
      matching rule still runs.
    consequence: |
      An implementer reading the Edge Cases block writes a test asserting the handler did not run,
      which will fail against the real dispatcher — and AC15 (already corrected) asserts the
      opposite. One of the two has to go before anyone writes the suite.
    recommendation: delete the stale Edge Case sentence; AC15 already carries the right claim.
  - id: L2-2
    severity: medium
    title: the wave table promises six waves; the steps declare four of them as solo
    evidence: |
      `## Parallel plan` lists waves 1-6. But the steps declare:
        Step 1 `---`, Step 2 `vlna-2`, Step 3 `---`, Step 4 `---`, Step 5 `vlna-2`,
        Step 6 `---`, Step 7 `---`.
      So only steps 2 and 5 are actually in a wave; the rest are standalone. The table reads as a
      concurrency plan that the declarations do not implement.
      `aid-plan-parallel-check.sh` cannot catch this: it reads `**Parallel group:**` and proves
      disjointness within a group — the narrative table is not an input.
    consequence: |
      A reader (or a dispatcher acting on the table) would believe five steps can be scheduled in
      parallel bands that no step declares.
    recommendation: |
      Make the table state the truth — one wave of two (2 and 5) and the rest sequential — or
      declare the waves the table promises. The table is documentation; the declarations are the
      contract.
  - id: L2-3
    severity: medium
    title: three steps modify one new script and none of them says who creates which part
    evidence: |
      `aid-plan-continue.sh` is created in Step 3, extended in Step 4 (artifact producer/consumer)
      and again in Step 6 (`--spawn`). All three declare it, and all three are standalone, so the
      order is only implied by `Depends on:`.
    consequence: |
      Not a scheduling defect — the dependency chain is 3 → 4 → 6 and holds. But Step 6's
      no-overlap check needs fields that Step 4 defines, and a reviewer of Step 6 alone cannot
      see that the schema exists.
    recommendation: |
      One sentence in Step 6 naming the fields it reads and the step that defines them
      (`job_id`, `jobs_dir`, `spawned_count` — Step 4).
  - id: L2-4
    severity: low
    title: idempotence is claimed but its test is one of five in a shared suite
    evidence: |
      Step 3 promises "Skript je idempotentní: druhé spuštění nad týmž hotovým EPICem zrcadlení
      přeskočí" — and the fifth case of `test-plan-continue.bats` covers it. The mechanism by
      which it detects the repeat (the queue status already being `merged_to_plan`) is not stated.
    recommendation: name the signal it keys on, so the test asserts the mechanism, not the outcome.

confidence: high
