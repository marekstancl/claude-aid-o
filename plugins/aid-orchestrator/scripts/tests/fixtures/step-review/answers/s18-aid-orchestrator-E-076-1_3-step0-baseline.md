_generated_by: aid-orchestrator:verifier@s18-aid-orchestrator-E-076-1_3-step0
_generated_at: 2026-09-19T07:36:01Z
classification: FULL_REVIEW
verdict: fail
findings:
  - severity: high
    file: plugins/aid-orchestrator/defaults/enforcement-registry.yaml:1112
    description: >-
      The rewritten `gate_runtime_baseline_advisory` description asserts, in the
      present/past tense, that behaviour which does not exist at this commit is
      already shipped. It says the `run_mode` key is "read by aid-run-gates.sh"
      and that "P076 Step 3 added the recommendation's first behavioural
      consumer ... aid-run-gates.sh emits ONE `gate_run_mode_advice` timeline
      event per gate per run". At commit a9d2da432a9a968d9b5b6c7ac257affaa0b29dd8,
      `plugins/aid-orchestrator/scripts/aid-run-gates.sh` does not reference
      `run_mode` at all (the sole `run_mode` hit in that file is the pre-existing,
      unrelated `gate_baseline_recommend_run_mode` baseline-report function name),
      and `gate_run_mode_advice` does not appear anywhere in the shipped scripts —
      only in this description, in the two comment blocks added to
      `defaults/execution.yaml`/`.aid-o/config/execution.yaml`, and in the new
      bats file's assertions against the template's prose. This diff (per the new
      test file's own header, "Step 1 creates the LANDING FIELD only. The
      runner-side read/validation lives in Step 2") is Step 1 only: the config
      key and its documentation. Step 2 (runner reads/validates `run_mode`) and
      Step 3 (the `gate_run_mode_advice` advisory event) are not part of this
      diff and are not present in the repository at this commit. An
      enforcement-registry entry marked `status: active` / `surface: llm-facing`
      is meant to describe real, current behaviour; this one now claims a
      concrete emitted event and a runner integration that a human or agent
      reading the registry could reasonably rely on, and neither exists yet.
    recommendation: >-
      Rewrite the added sentences to describe Step 1's actual scope only, e.g.
      "P076 Step 1 gave the run-mode half of that recommendation a real landing
      field: `run_mode: foreground|background` is now an optional, currently
      inert per-gate key in execution.yaml (default foreground, documented in
      defaults/execution.yaml). A later step (P076 Step 2/3, not yet landed) is
      expected to make aid-run-gates.sh read/validate the key and emit an
      observe-only `gate_run_mode_advice` timeline event; until then the field
      only has meaning when a human edits `run_mode` by hand." Do not describe
      Step 2/3 behaviour as already implemented until the corresponding
      aid-run-gates.sh change actually ships and its own bats coverage (not just
      this field-contract suite) exists.

--- Verified against the stated Acceptance Criteria (all pass) ---
- All four bats cases in plugins/aid-orchestrator/scripts/tests/bats/test-run-mode-field.bats pass, including case 3 (the loud invalid-value failure): ran locally against a clean checkout of a9d2da432a9a968d9b5b6c7ac257affaa0b29dd8 — `1..4 / ok 1 / ok 2 / ok 3 / ok 4`.
- `yq '.gates.bats_all.run_mode' .aid-o/config/execution.yaml` prints `background` (verified for both bats_all and bats_boundary).
- `grep -c 'run_mode' plugins/aid-orchestrator/defaults/execution.yaml` shows 5 hits, all inside the new documentation block; `yq -r '[.gates[] | select(has("run_mode"))] | length'` on that template is `0` — no template gate sets it.
- plugins/aid-orchestrator/defaults/enforcement-registry.yaml:1112 — sentence rewritten to name the field (`run_mode: foreground|background`) and the advisory event (`gate_run_mode_advice`) instead of the old "a human ... edits execution.yaml's timeout_seconds/run_mode by hand" claim — text-level AC is met (see high-severity finding above for a factual-accuracy problem in the new text itself).
- step_forbidden_paths: empty; no forbidden-path violation possible.
- No other files were touched outside step_outputs.
