#!/usr/bin/env bats
# aid-tier: t2
# test-generation-labels.bats — P074 Step 18: honest failure labels.
#
# WHAT THIS PINS. Generation failures render as EXACTLY TWO AID-owned labels
# and nothing else is relabelled:
#
#   aid_generation_force_required:  the CP1 gate refused a condition a
#                                   deliberate, audited PM --force CAN cover;
#                                   the printed command carries THIS
#                                   invocation's --plan and --queue-mode,
#                                   shell-quoted, and is executable verbatim.
#   aid_cp1_blocked:                the refusal is one --force CANNOT cover;
#                                   the hard condition is named FIRST, and
#                                   --force is REFUSED IN THE SAME PLACE
#                                   rather than merely not advertised.
#
# THE HONESTY PROPERTIES, and why each is tested the hard way — asserted any
# more weakly than this, none of the four means anything:
#
#   1. LINE 1, not "somewhere". The label must be the FIRST line of stderr.
#      Asserted with `head -1`, never with a substring search over the whole
#      stream — the pipeline emits [INFO] chatter before the gate runs, so
#      "appears somewhere" would pass on a label buried under it.
#   2. THE COMMAND ACTUALLY RUNS. The printed force command is extracted from
#      the label line, its reason placeholder replaced, and EXECUTED — proving
#      it parses and reaches the outcome it promises, not merely that it looks
#      right.
#   3. A HOSTILE PATH. The fixture plan lives at a path with a space AND an
#      apostrophe, so naive quoting of the printed command fails loudly here.
#   4. HARD MEANS UNFORCEABLE. Every hard class is re-run WITH
#      `--force --reason '<20+ chars>'` and must fail in the same place with no
#      authority — otherwise `aid_cp1_blocked` would be decoration
#      (AID-v3-principles §1), a claim the next invocation disproves.
#
# WHY THE CLASSIFICATION IS NOT GUESSWORK (PM decision 3 dropped the host-error
# detector for exactly that reason). It is read off aid-cp1-gate.sh's own
# documented exit-code contract (0 pass/NA, 1 condition verdict, 2 usage,
# 3 I/O) plus its three literal pre-verdict plan-identity error strings. These
# tests drive a stub that emits that vocabulary; whether the REAL gate emits it
# is the real gate's own suite's business.
#
# FD-3 HYGIENE: bats reports results over fd 3; a child holding it open
# truncates the suite's TAP output. Every pipeline invocation runs with `3>&-`.
# A `run` whose command is MISSING exits 127 and bats writes a warning to fd 3
# — with fd 3 closed that destroys the whole file's output, so no `run` here is
# ever handed a path that might not exist.
# After any edit, verify the result count:
#   bats --tap test-generation-labels.bats | grep -cE '^(ok|not ok)'   # == 15

load test-helpers.bash
load generation-fixture.bash

setup() {
  gen_setup
  gen_shadow_farm
  _stub_cp1_configurable
  REASON="the PM accepts this bypass because the blocking condition is a known false positive"
  export REASON
}

teardown() { gen_teardown; }

# _stub_cp1_configurable — this suite's own CP1 gate stub: the test dictates
# its exit code and its output, so one stub stands in for every real gate
# outcome in the vocabulary this suite classifies.
_stub_cp1_configurable() {
  gen_stub aid-cp1-gate.sh <<'STUB'
#!/usr/bin/env bash
# AID_TEST_CP1_OUT is emitted verbatim (\n honoured) and AID_TEST_CP1_RC is the
# exit code.
[[ -n "${AID_TEST_CP1_OUT:-}" ]] && printf '%b\n' "$AID_TEST_CP1_OUT" >&2
exit "${AID_TEST_CP1_RC:-0}"
STUB
}

# _seed_plan <project> — a HOSTILE plan path: a space AND an apostrophe. Naive
# single-quote interpolation of the printed force command produces an
# unparseable line for exactly this path, which is why every fixture uses it.
_seed_plan() {
  local d="$1" p="$1/.aid-o/plans/P099 PM's multi phase.md"
  cp "$FIXTURES/multi-phase-plan-numeric.md" "$p"
  printf '%s\n' "$p"
}

# _run_pipeline <project> <plan> [extra args…] — stderr is captured to its OWN
# file so LINE ORDER can be asserted (bats' $output merges the two streams and
# loses it).
_run_pipeline() {
  local proj="$1" plan="$2"; shift 2
  ERRFILE="$TEST_TMPDIR/stderr.txt"
  export ERRFILE
  RC=0
  ( cd "$proj" && bash "$PIPELINE" --plan "$plan" --queue-mode chain "$@" ) \
    >"$TEST_TMPDIR/stdout.txt" 2>"$ERRFILE" 3>&- || RC=$?
  export RC
}

_first_line() { head -1 "$ERRFILE"; }
_auth() { printf '%s\n' "$1/.aid-o/work/evidence/P099/generation/generation-authority.json"; }

# _printed_force_command — the command the label advertises, extracted from
# stderr line 1 exactly as printed.
_printed_force_command() {
  local line; line="$(_first_line)"
  printf '%s' "${line#*override deliberately with: }"
}

# ─── forceable: the label is line 1, and the command it prints WORKS ──────

@test "a forceable CP1 refusal puts aid_generation_force_required on stderr LINE 1" {
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  export AID_TEST_CP1_RC=1
  export AID_TEST_CP1_OUT='ERROR: High-risk plan requires CP1-deep evidence.\nMissing files in .aid-o/work/evidence/P099/cp1-deep/:\n  - cp1-lens-L1-behavior.md'
  _run_pipeline "$TEST_TMPDIR/p" "$plan"
  [ "$RC" -ne 0 ]

  # LINE 1 — not "somewhere in the output". The pipeline's own [INFO] chatter
  # is staged behind this line, never in front of it.
  local first; first="$(_first_line)"
  [[ "$first" == "aid_generation_force_required: "* ]]
  # The other label never fires for a forceable class.
  ! grep -q 'aid_cp1_blocked' "$ERRFILE"
  # Nothing was generated…
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]
  # …and the staged chatter was not swallowed to achieve line 1.
  grep -q '\[INFO\]' "$ERRFILE"
}

@test "the printed force command re-parses to the EXACT hostile plan path (space + apostrophe)" {
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  export AID_TEST_CP1_RC=1
  export AID_TEST_CP1_OUT='ERROR: High-risk plan requires CP1-deep evidence.'
  _run_pipeline "$TEST_TMPDIR/p" "$plan"
  [ "$RC" -ne 0 ]

  local cmd; cmd="$(_printed_force_command)"
  [[ "$cmd" == "aid-auto-pipeline.sh --plan "* ]]
  # Parse the printed argument vector with the shell itself and recover --plan.
  local recovered
  recovered="$(eval "set -- ${cmd#aid-auto-pipeline.sh }"
               while [[ $# -gt 0 ]]; do
                 if [[ "$1" == "--plan" ]]; then printf '%s' "$2"; break; fi
                 shift
               done)"
  [ "$recovered" = "$plan" ]
}

@test "EXECUTING the printed force command proceeds: it parses, and it seals a forced authority" {
  # The honesty property: the label does not merely LOOK like a command. It is
  # extracted, its reason placeholder replaced with a real reason, and RUN.
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  export AID_TEST_CP1_RC=1
  export AID_TEST_CP1_OUT='ERROR: High-risk plan requires CP1-deep evidence.'
  _run_pipeline "$TEST_TMPDIR/p" "$plan"
  [ "$RC" -ne 0 ]
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]

  local cmd; cmd="$(_printed_force_command)"
  # Swap the bare script name for this run's shadow copy, and the placeholder
  # reason for a real one. Everything else — including the quoting of the
  # hostile plan path — is used EXACTLY as printed.
  cmd="bash $(printf %q "$PIPELINE") ${cmd#aid-auto-pipeline.sh }"
  cmd="${cmd%--reason *}--reason $(printf %q "$REASON")"

  local rc2=0
  ( cd "$TEST_TMPDIR/p" && eval "$cmd" ) >/dev/null 2>"$TEST_TMPDIR/forced.txt" 3>&- || rc2=$?
  [ "$rc2" -eq 0 ]
  # It reached the outcome the label promised: a sealed, forced authority.
  local a; a="$(_auth "$TEST_TMPDIR/p")"
  [ -f "$a" ]
  [ "$(jq -r '.forced_override' "$a")" = "true" ]
  [ "$(jq -r '.force_reason' "$a")" = "$REASON" ]
  [ "$(jq -r '.plan_path' "$a")" = "$plan" ]
}

@test "the gate's own stderr follows the label verbatim — the label adds, never replaces" {
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  export AID_TEST_CP1_RC=1
  export AID_TEST_CP1_OUT='ERROR: CP1 revision-limit ledger blocks EPIC generation for plan P099.\naid-cp1-ledger.sh check-budget rc=1: attempts 5 >= max 5'
  _run_pipeline "$TEST_TMPDIR/p" "$plan"
  [ "$RC" -ne 0 ]

  [[ "$(_first_line)" == "aid_generation_force_required: "* ]]
  # Both of the gate's own lines survive, byte for byte, BELOW the label.
  grep -qF 'ERROR: CP1 revision-limit ledger blocks EPIC generation for plan P099.' "$ERRFILE"
  grep -qF 'aid-cp1-ledger.sh check-budget rc=1: attempts 5 >= max 5' "$ERRFILE"
  local gate_line
  gate_line="$(grep -nF 'ERROR: CP1 revision-limit ledger blocks' "$ERRFILE" | head -1 | cut -d: -f1)"
  [ "$gate_line" -gt 1 ]
}

# ─── hard: the label is enforced, not advertised ─────────────────────────

@test "a gate exit 2 (usage error) is aid_cp1_blocked on LINE 1 and offers no force command" {
  # rc 2 means the gate was mis-invoked and never evaluated a CP1 condition —
  # there is no verdict to waive, so --force covers nothing.
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  export AID_TEST_CP1_RC=2
  export AID_TEST_CP1_OUT='{"error": "Unknown argument: --nonsense", "code": 2}'
  _run_pipeline "$TEST_TMPDIR/p" "$plan"
  [ "$RC" -ne 0 ]

  [[ "$(_first_line)" == "aid_cp1_blocked: the CP1 gate exited 2 (usage error)"* ]]
  ! grep -q 'aid_generation_force_required' "$ERRFILE"
  ! grep -q -- '--force --reason' "$ERRFILE"
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]
}

@test "HARD IS UNFORCEABLE: --force on a gate exit 2 fails in the same place and seals NO authority" {
  # AID-v3-principles §1. If --force sailed past a condition the label calls
  # uncoverable, the label would be decoration — a claim the very next
  # invocation disproves.
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  export AID_TEST_CP1_RC=2
  export AID_TEST_CP1_OUT='{"error": "Unknown argument: --nonsense", "code": 2}'
  _run_pipeline "$TEST_TMPDIR/p" "$plan" --force --reason "$REASON"
  [ "$RC" -ne 0 ]

  [[ "$(_first_line)" == "aid_cp1_blocked: the CP1 gate exited 2 (usage error)"* ]]
  grep -qF -- '--force DOES NOT APPLY to this condition class' "$ERRFILE"
  # No authority, no waiver, no EPIC — the force bought exactly nothing.
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]
  run bash -c "ls '$TEST_TMPDIR/p/.aid-o/work/evidence/P099/generation'/waiver-generation-*.json 2>/dev/null | wc -l"
  [ "$output" = "0" ]
  run bash -c "ls '$TEST_TMPDIR/p/.aid-o/tasks'/E-099-*.md 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "HARD IS UNFORCEABLE: --force on a gate exit 3 (I/O) fails in the same place and seals NO authority" {
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  export AID_TEST_CP1_RC=3
  export AID_TEST_CP1_OUT='{"error": "Plan file not found: /nowhere/plan.md", "code": 3}'

  # Without --force…
  _run_pipeline "$TEST_TMPDIR/p" "$plan"
  [ "$RC" -ne 0 ]
  [[ "$(_first_line)" == "aid_cp1_blocked: the CP1 gate exited 3 (I/O error)"* ]]
  # …and WITH it, identically.
  _run_pipeline "$TEST_TMPDIR/p" "$plan" --force --reason "$REASON"
  [ "$RC" -ne 0 ]
  [[ "$(_first_line)" == "aid_cp1_blocked: the CP1 gate exited 3 (I/O error)"* ]]
  grep -qF -- '--force DOES NOT APPLY to this condition class' "$ERRFILE"
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]
}

@test "HARD IS UNFORCEABLE: --force on a broken plan identity (exit 1) fails in the same place" {
  # An rc-1 failure the gate raises BEFORE it determines risk. Forcing past it
  # would seal an authority whose plan identity is the broken thing.
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  export AID_TEST_CP1_RC=1
  export AID_TEST_CP1_OUT="{\"error\": \"Plan id 'P099/../etc' contains invalid characters (path traversal guard)\", \"code\": 1}"

  _run_pipeline "$TEST_TMPDIR/p" "$plan"
  [ "$RC" -ne 0 ]
  [[ "$(_first_line)" == "aid_cp1_blocked: "* ]]
  ! grep -q 'aid_generation_force_required' "$ERRFILE"

  _run_pipeline "$TEST_TMPDIR/p" "$plan" --force --reason "$REASON"
  [ "$RC" -ne 0 ]
  local first; first="$(_first_line)"
  [[ "$first" == "aid_cp1_blocked: "* ]]
  [[ "$first" == *"path traversal guard"* ]]
  grep -qF -- '--force DOES NOT APPLY to this condition class' "$ERRFILE"
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]
  # Nothing to audit, because no bypass happened.
  [ ! -f "$TEST_TMPDIR/p/.aid-o/work/audit-log.jsonl" ]
}

@test "some forceable conditions plus one hard one: aid_cp1_blocked wins, names the hard one first, stays unforceable" {
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  export AID_TEST_CP1_RC=1
  export AID_TEST_CP1_OUT='ERROR: High-risk plan requires CP1-deep evidence.\nERROR: CP1 revision-limit ledger blocks EPIC generation for plan P099.\nPlan file missing closing '"'"'---'"'"' for frontmatter block.'
  _run_pipeline "$TEST_TMPDIR/p" "$plan"
  [ "$RC" -ne 0 ]

  ! grep -q 'aid_generation_force_required' "$ERRFILE"
  local first; first="$(_first_line)"
  [[ "$first" == "aid_cp1_blocked: "* ]]
  [[ "$first" == *"missing closing '---' for frontmatter"* ]]
  [[ "$first" != *"CP1-deep evidence"* ]]
  # And it stays hard under --force: the mixed case does not become forceable
  # just because some of its conditions were.
  _run_pipeline "$TEST_TMPDIR/p" "$plan" --force --reason "$REASON"
  [ "$RC" -ne 0 ]
  [[ "$(_first_line)" == "aid_cp1_blocked: "* ]]
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]
}

@test "gate stderr that already starts with a label is passed through, never double-labelled" {
  # The wrapper double-invocation case: a labelled refusal must not come back
  # wearing two labels, which would read as two different refusals for one.
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  export AID_TEST_CP1_RC=1
  export AID_TEST_CP1_OUT='aid_cp1_blocked: an inner invocation already decided this\nsupporting detail from the inner run'
  _run_pipeline "$TEST_TMPDIR/p" "$plan"
  [ "$RC" -ne 0 ]

  [ "$(grep -c 'aid_cp1_blocked' "$ERRFILE")" = "1" ]
  ! grep -q 'aid_generation_force_required' "$ERRFILE"
  grep -qF 'supporting detail from the inner run' "$ERRFILE"
}

# ─── foreign failures: verbatim, and the note only when it is true ────────

@test "a subprocess crash AFTER the gate passed prints verbatim plus the not-an-AID-gate note" {
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  export AID_TEST_CP1_RC=0
  export AID_TEST_CP1_OUT='CP1-gate: plan P099 is low-risk — CP1-deep not required. Proceeding.'
  gen_stub aid-epic-to-json.sh <<'STUB'
#!/usr/bin/env bash
echo "jq: error (at <stdin>:0): Cannot index number with string \"steps\"" >&2
exit 5
STUB
  _run_pipeline "$TEST_TMPDIR/p" "$plan"
  [ "$RC" -ne 0 ]

  # The foreign error survives byte for byte — nothing was relabelled.
  grep -qF 'jq: error (at <stdin>:0): Cannot index number with string "steps"' "$ERRFILE"
  # Neither AID label is attached to something that is not an AID gate.
  ! grep -q 'aid_cp1_blocked' "$ERRFILE"
  ! grep -q 'aid_generation_force_required' "$ERRFILE"
  # And the one true thing AID can add is added.
  grep -qF "note: AID's own checks passed — this failure is not an AID gate" "$ERRFILE"
  # The authority really had been sealed with a pass before the crash.
  [ "$(jq -r '.cp1.verdict' "$(_auth "$TEST_TMPDIR/p")")" = "pass" ]
}

@test "an AID-owned gate failure after the CP1 pass does NOT get the not-an-AID-gate note" {
  # The D5 contract-validation gate is AID's own. Appending "this failure is
  # not an AID gate" to a gate that names itself in its own message would be a
  # flat contradiction.
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  export AID_TEST_CP1_RC=0
  # `gates/` is itself a SYMLINK in the shadow farm (it is an entry under
  # scripts/). Writing "through" it would edit the real repository, so it is
  # replaced with a real directory of symlinks before anything is stubbed.
  rm -f "$SHADOW/scripts/gates"
  mkdir -p "$SHADOW/scripts/gates"
  local g
  for g in "$REPO_PLUGIN/scripts/gates"/*; do ln -s "$g" "$SHADOW/scripts/gates/$(basename "$g")"; done
  rm -f "$SHADOW/scripts/gates/aid-contract-validate.sh"
  cat > "$SHADOW/scripts/gates/aid-contract-validate.sh" <<'STUB'
#!/usr/bin/env bash
echo '{"status":"fail","findings":["broadcast allowed_paths"]}'
exit 1
STUB
  chmod +x "$SHADOW/scripts/gates/aid-contract-validate.sh"

  _run_pipeline "$TEST_TMPDIR/p" "$plan"
  [ "$RC" -ne 0 ]
  grep -qF 'Contract validation failed for phase' "$ERRFILE"
  ! grep -qF "note: AID's own checks passed" "$ERRFILE"
}

@test "a failure BEFORE the gate passes prints verbatim with NO note" {
  # AID runs no FATAL subprocess before the CP1 call (the one it does run,
  # aid-plan-fsm.sh plan-start, is deliberately non-fatal), so the pre-gate
  # failure exercised here is AID's own transaction-identity abort — which is
  # the point: the note must not fire when AID's checks had not passed yet.
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  local gen="$TEST_TMPDIR/p/.aid-o/work/evidence/P099/generation"
  mkdir -p "$gen"
  jq -n '{schema:"aid-generation-transaction/v1", plan_id:"P099",
          plan_path:"x", plan_sha256:"deadbeef", target_branch:"main",
          target_head:"deadbeef", mode:"chain", phase_derivation_version:1,
          total_phases:3, authority_sha256:null, phases:{},
          created_at:"2026-08-06T00:00:00Z", updated_at:"2026-08-06T00:00:00Z"}' \
    > "$gen/transaction.json"

  export AID_TEST_CP1_RC=0
  _run_pipeline "$TEST_TMPDIR/p" "$plan"
  [ "$RC" -ne 0 ]

  grep -qF 'generation transaction identity mismatch' "$ERRFILE"
  ! grep -qF "note: AID's own checks passed" "$ERRFILE"
  ! grep -q 'aid_cp1_blocked' "$ERRFILE"
  ! grep -q 'aid_generation_force_required' "$ERRFILE"
  # Staged chatter from before the abort is flushed, not lost.
  grep -q '\[INFO\]' "$ERRFILE"
}

# ─── the instruction sweep (no kočkopes) ─────────────────────────────────

@test "SWEEP: no live instruction surface still teaches the per-phase gate call site" {
  # Every phrase below described the OLD model, where aid-plan-to-epic.sh ran
  # the CP1 gate itself on every phase. Under the transaction model the
  # pipeline runs it once per plan; a standalone aid-plan-to-epic.sh is the
  # only remaining per-invocation caller, and every surface must say so.
  cd "$REPO_PLUGIN"
  run bash -c "grep -rn 'Called as subprocess by' skills/ commands/ | wc -l"
  [ "$output" = "0" ]
  run bash -c "grep -rn '(called by aid-plan-to-epic.sh)' skills/ commands/ | wc -l"
  [ "$output" = "0" ]
  run bash -c "grep -rn '(called by .aid-plan-to-epic.sh.) is' skills/ commands/ | wc -l"
  [ "$output" = "0" ]
  # The surfaces that DO describe the call site name both halves of it.
  grep -q 'once per TRANSACTION' skills/review-checkpoint-contracts.md
  grep -q 'standalone' skills/review-checkpoint-contracts.md
  grep -q 'once per generation transaction' commands/aid-plan.md
  grep -q 'standalone' commands/aid-plan.md
}

@test "SWEEP: the gate call-site sentence states the transaction model in its own words" {
  # The plan's acceptance grep: `grep -rn 'per phase' review-checkpoint-contracts.md`
  # must land on the call-site sentence, and that sentence must say what the
  # model IS, not only what it is not.
  cd "$REPO_PLUGIN"
  local hit; hit="$(grep -n 'per phase' skills/review-checkpoint-contracts.md | head -1)"
  [ -n "$hit" ]
  [[ "$hit" == *"once per TRANSACTION, never once per phase"* ]]
  grep -q 'generation-authority.json' skills/review-checkpoint-contracts.md
  # …and pipeline.md / planner.md / aid-run.md carry the same chain.
  grep -q 'THE ONE CP1 call' skills/pipeline.md
  grep -q 'Generation for a plan is ONE transaction' skills/planner.md
  grep -q 'CP1 gate (once per plan)' commands/aid-run.md
}
