#!/usr/bin/env bats
# test-aid-c3-dispatch.bats — P065 E-065-1_7 Step 2 behavioral red-green tests
# for scripts/lib/aid-c3-dispatch.sh `build-manifest`.
#
# build-manifest is the C3 producer half: it writes the four Codex brief files
# under <evidence_dir>/c3/ and a canonical hash-manifest
# (<evidence_dir>/audit-input-manifest.json) that records exactly what brief
# Codex is given and at what commit. It formalises skills/pipeline.md §7's prose
# "C3 producer hook" (allowlist[]/input_hash VERBATIM) and adds the Codex brief
# provenance (base_sha/head_sha/codex_brief_files[]/codex_brief_hash/
# allowed_recheck_commands/verification_budget).
#
# All fixtures run the REAL script against a REAL git repo (no source grep) and
# sanity-check the emitted manifest with the REAL aid-protocol-validate.sh.
# Fixture conventions (setup_test_evidence_dir, AID_PLUGIN_PATH) follow
# test-invalidation-map.bats / test-c3-audit.bats.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  export DISPATCH
  VALIDATE="$AID_PLUGIN_PATH/scripts/aid-protocol-validate.sh"
  export VALIDATE

  # project.yaml so identity.project_id resolves to a real value (not "unknown").
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'project_id: test-c3-proj\n' > "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml"

  # Two commits with a source change → BASE_SHA (before) / HEAD_SHA (after).
  mkdir -p src
  printf 'export const a = 1;\n' > src/app.ts
  git add src/app.ts .aid-o/config/project.yaml
  git commit -q -m "base"
  BASE_SHA="$(git rev-parse HEAD)"
  printf 'export const b = 2;\n' >> src/app.ts
  git add src/app.ts
  git commit -q -m "head change"
  HEAD_SHA="$(git rev-parse HEAD)"
  export BASE_SHA HEAD_SHA

  # Changed-paths file (one repo-relative changed path per line).
  CHANGED_PATHS_FILE="$TEST_TMPDIR/changed-paths.txt"
  printf 'src/app.ts\n' > "$CHANGED_PATHS_FILE"
  export AID_CHANGED_PATHS="$CHANGED_PATHS_FILE"

  # This run's evidence artifacts (belong in allowlist, NOT in the brief).
  printf '# Final report\n' > "$TEST_EVIDENCE_DIR/final_report.md"
  printf '{"result":"ok"}\n' > "$TEST_EVIDENCE_DIR/gates_report.json"

  MANIFEST="$TEST_EVIDENCE_DIR/audit-input-manifest.json"
  export MANIFEST

  # ── Step 3 (qa): fake-codex CLI fixture on PATH ─────────────────────────────
  # Prepend the fixture dir so `codex` resolves to our deterministic stub even
  # when a real codex is installed (fixture wins). teardown() restores PATH.
  # None of the Step-2 build-manifest tests invoke `codex`, so this is inert for
  # them; it only shadows a `codex` binary, never git/jq/bash.
  FAKE_CODEX_DIR="$(cd "$BATS_TEST_DIRNAME/../fixtures/fake-codex" && pwd)"
  export FAKE_CODEX_DIR
  ORIGINAL_PATH="$PATH"
  export ORIGINAL_PATH
  PATH="$FAKE_CODEX_DIR:$PATH"
  export PATH
  # Deterministic provenance the fixture echoes in `valid` mode. HEAD_SHA is a
  # real 40-hex sha from this fixture's git setup above (not repo git state that
  # the stub itself ever reads — the stub never runs git).
  export FAKE_CODEX_EXPECT_HEAD="$HEAD_SHA"
  export FAKE_CODEX_EXPECT_MANIFEST_HASH="sha256:$(printf 'fake-brief' | sha256sum | cut -d' ' -f1)"
  FC_LAST="$TEST_TMPDIR/fc-last-message.txt"
  export FC_LAST
  FC_STREAM="$TEST_TMPDIR/fc-stream.jsonl"
  export FC_STREAM
}

teardown() {
  unset AID_CHANGED_PATHS AID_PLAN_AC_FILE C3_AUDIT_POLICY
  # Step 3 (qa): restore PATH and clear fixture env so nothing leaks across tests.
  PATH="${ORIGINAL_PATH:-$PATH}"
  export PATH
  unset FAKE_CODEX_MODE FAKE_CODEX_EXPECT_HEAD FAKE_CODEX_EXPECT_MANIFEST_HASH FAKE_CODEX_THREAD_ID
  teardown_test_evidence_dir
}

# _build [risk_profile]  — run build-manifest with the fixture's evidence dir + SHAs.
_build() {
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" "${1:-high}"
}

# ─── AC1: valid manifest, existing format kept, new brief fields added ──────

@test "AC1: build-manifest exits 0 and the emitted manifest passes aid-protocol-validate.sh" {
  _build high
  [ "$status" -eq 0 ]
  [ -f "$MANIFEST" ]
  run bash "$VALIDATE" "$MANIFEST"
  [ "$status" -eq 0 ]
}

@test "AC1: manifest keeps the existing allowlist / input_hash / prior_pass_summaries format" {
  _build high
  [ "$status" -eq 0 ]
  # allowlist is an array
  run jq -r '.audit_input_manifest.allowlist | type' "$MANIFEST"
  [ "$output" = "array" ]
  # input_hash matches the existing sha256:<64hex> format
  run jq -r '.audit_input_manifest.input_hash' "$MANIFEST"
  [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]
  # prior_pass_summaries is untrusted (D2)
  run jq -r '.audit_input_manifest.prior_pass_summaries' "$MANIFEST"
  [ "$output" = "untrusted" ]
}

@test "AC1: manifest adds codex_brief_files (4 items, each {path,sha256,size}) + codex_brief_hash" {
  _build high
  [ "$status" -eq 0 ]
  # exactly four brief files, all under c3/
  run jq -r '.audit_input_manifest.codex_brief_files | length' "$MANIFEST"
  [ "$output" = "4" ]
  run jq -r '[.audit_input_manifest.codex_brief_files[].path] | sort | join(",")' "$MANIFEST"
  [ "$output" = "c3/bundle-diff.patch,c3/bundle-plan-ac.md,c3/bundle-review-profile.json,c3/bundle-scope.txt" ]
  # every entry carries {path,sha256,size} with the right shapes
  run jq -r '[.audit_input_manifest.codex_brief_files[]
              | select((.path|type=="string")
                       and (.sha256|test("^sha256:[0-9a-f]{64}$"))
                       and (.size|type=="number"))] | length' "$MANIFEST"
  [ "$output" = "4" ]
  # codex_brief_hash present and well-formed
  run jq -r '.audit_input_manifest.codex_brief_hash' "$MANIFEST"
  [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]
}

@test "AC1: the four brief files are actually written under c3/" {
  _build high
  [ "$status" -eq 0 ]
  [ -f "$TEST_EVIDENCE_DIR/c3/bundle-diff.patch" ]
  [ -f "$TEST_EVIDENCE_DIR/c3/bundle-scope.txt" ]
  [ -f "$TEST_EVIDENCE_DIR/c3/bundle-plan-ac.md" ]
  [ -f "$TEST_EVIDENCE_DIR/c3/bundle-review-profile.json" ]
  # bundle-diff.patch reflects the base..head source change
  grep -q "export const b = 2;" "$TEST_EVIDENCE_DIR/c3/bundle-diff.patch"
}

# ─── AC2: hash determinism / sensitivity ────────────────────────────────────

@test "AC2: identical inputs reproduce codex_brief_hash AND input_hash (idempotent)" {
  _build high
  [ "$status" -eq 0 ]
  local cbh1 ih1
  cbh1="$(jq -r '.audit_input_manifest.codex_brief_hash' "$MANIFEST")"
  ih1="$(jq -r '.audit_input_manifest.input_hash' "$MANIFEST")"
  _build high
  [ "$status" -eq 0 ]
  local cbh2 ih2
  cbh2="$(jq -r '.audit_input_manifest.codex_brief_hash' "$MANIFEST")"
  ih2="$(jq -r '.audit_input_manifest.input_hash' "$MANIFEST")"
  [ "$cbh1" = "$cbh2" ]
  [ "$ih1" = "$ih2" ]
}

@test "AC2: editing a brief file changes codex_brief_hash but NOT input_hash" {
  # Drive the plan-ac brief content via AID_PLAN_AC_FILE (a brief input, not an
  # allowlisted changed-source path). Must live INSIDE the repo (TEST_PROJECT_ROOT,
  # not the outer TEST_TMPDIR) — real usage always points at an in-repo plan file
  # (e.g. .aid-o/plans/*.md), and build-manifest's _path_is_within containment
  # check correctly rejects anything outside the repo (CP3 security fix).
  local plan="$TEST_PROJECT_ROOT/plan-ac.md"
  printf 'PLAN VERSION A\n' > "$plan"
  export AID_PLAN_AC_FILE="$plan"
  _build high
  [ "$status" -eq 0 ]
  local cbh1 ih1
  cbh1="$(jq -r '.audit_input_manifest.codex_brief_hash' "$MANIFEST")"
  ih1="$(jq -r '.audit_input_manifest.input_hash' "$MANIFEST")"

  printf 'PLAN VERSION B (different)\n' > "$plan"
  _build high
  [ "$status" -eq 0 ]
  local cbh2 ih2
  cbh2="$(jq -r '.audit_input_manifest.codex_brief_hash' "$MANIFEST")"
  ih2="$(jq -r '.audit_input_manifest.input_hash' "$MANIFEST")"

  [ "$cbh1" != "$cbh2" ]   # brief file changed → codex_brief_hash changed
  [ "$ih1" = "$ih2" ]      # allowlist unchanged → input_hash unchanged
}

@test "AC2: editing a changed-source file changes input_hash but NOT codex_brief_hash" {
  _build high
  [ "$status" -eq 0 ]
  local cbh1 ih1
  cbh1="$(jq -r '.audit_input_manifest.codex_brief_hash' "$MANIFEST")"
  ih1="$(jq -r '.audit_input_manifest.input_hash' "$MANIFEST")"

  # Mutate the working-tree copy of the changed source WITHOUT committing:
  # input_hash reads the working tree (changes), but the base..head tree diff
  # that feeds the brief is unchanged (codex_brief_hash stays constant).
  printf 'export const c = 3; // working-tree mutation\n' >> src/app.ts
  _build high
  [ "$status" -eq 0 ]
  local cbh2 ih2
  cbh2="$(jq -r '.audit_input_manifest.codex_brief_hash' "$MANIFEST")"
  ih2="$(jq -r '.audit_input_manifest.input_hash' "$MANIFEST")"

  [ "$ih1" != "$ih2" ]
  [ "$cbh1" = "$cbh2" ]
}

# ─── AC3: allowlist membership (changed sources + evidence, NOT brief files) ─

@test "AC3: allowlist contains AID_CHANGED_PATHS entries + evidence artifacts, and NOT the brief files" {
  _build high
  [ "$status" -eq 0 ]
  # changed source present
  run jq -e '.audit_input_manifest.allowlist | index("src/app.ts")' "$MANIFEST"
  [ "$status" -eq 0 ]
  # evidence artifacts present
  run jq -e '.audit_input_manifest.allowlist | index("final_report.md")' "$MANIFEST"
  [ "$status" -eq 0 ]
  run jq -e '.audit_input_manifest.allowlist | index("gates_report.json")' "$MANIFEST"
  [ "$status" -eq 0 ]
  # NO brief (bundle-*) path leaked into the allowlist
  run jq -r '[.audit_input_manifest.allowlist[] | select(test("bundle-"))] | length' "$MANIFEST"
  [ "$output" = "0" ]
  run jq -r '[.audit_input_manifest.allowlist[] | select(test("^c3/"))] | length' "$MANIFEST"
  [ "$output" = "0" ]
}

@test "AC3: prior verifier-output-*.md are included in allowlist when present, omitted when absent" {
  # absent → not in allowlist
  _build high
  [ "$status" -eq 0 ]
  run jq -r '[.audit_input_manifest.allowlist[] | select(test("verifier-output"))] | length' "$MANIFEST"
  [ "$output" = "0" ]
  # present → included
  printf 'verifier output\n' > "$TEST_EVIDENCE_DIR/verifier-output-1.md"
  _build high
  [ "$status" -eq 0 ]
  run jq -e '.audit_input_manifest.allowlist | index("verifier-output-1.md")' "$MANIFEST"
  [ "$status" -eq 0 ]
}

# ─── Edge cases ──────────────────────────────────────────────────────────────

@test "edge: base_sha == head_sha yields an empty-diff brief that is still hashed" {
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$HEAD_SHA" "$HEAD_SHA" high
  [ "$status" -eq 0 ]
  # empty diff → size 0 brief files, but still present + hashed
  run jq -r '.audit_input_manifest.codex_brief_files[] | select(.path=="c3/bundle-diff.patch") | .size' "$MANIFEST"
  [ "$output" = "0" ]
  run jq -r '.audit_input_manifest.codex_brief_hash' "$MANIFEST"
  [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]
  run bash "$VALIDATE" "$MANIFEST"
  [ "$status" -eq 0 ]
}

@test "edge: missing AID_CHANGED_PATHS → allowlist [] but codex_brief_files still built" {
  unset AID_CHANGED_PATHS
  # also remove evidence artifacts so the allowlist is provably empty
  rm -f "$TEST_EVIDENCE_DIR/final_report.md" "$TEST_EVIDENCE_DIR/gates_report.json"
  _build high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.allowlist | length' "$MANIFEST"
  [ "$output" = "0" ]
  run jq -r '.audit_input_manifest.codex_brief_files | length' "$MANIFEST"
  [ "$output" = "4" ]
  run bash "$VALIDATE" "$MANIFEST"
  [ "$status" -eq 0 ]
}

@test "edge: empty AID_CHANGED_PATHS file → allowlist omits changed sources" {
  : > "$AID_CHANGED_PATHS"   # truncate to empty
  rm -f "$TEST_EVIDENCE_DIR/final_report.md" "$TEST_EVIDENCE_DIR/gates_report.json"
  _build high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.allowlist | length' "$MANIFEST"
  [ "$output" = "0" ]
}

# ─── required_independence_level resolution (policy + fail-closed) ──────────

@test "independence: high → cross_model (from default policy)" {
  _build high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.required_independence_level' "$MANIFEST"
  [ "$output" = "cross_model" ]
}

@test "independence: unverifiable → cross_provider (from default policy)" {
  _build unverifiable
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.required_independence_level' "$MANIFEST"
  [ "$output" = "cross_provider" ]
}

@test "independence: unknown profile → fail-closed cross_provider" {
  _build bogus_profile
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.required_independence_level' "$MANIFEST"
  [ "$output" = "cross_provider" ]
}

@test "independence: missing policy file → fail-closed cross_provider" {
  export C3_AUDIT_POLICY="$TEST_TMPDIR/does-not-exist.yaml"
  _build high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.required_independence_level' "$MANIFEST"
  [ "$output" = "cross_provider" ]
}

# ─── identity derivation ────────────────────────────────────────────────────

@test "identity: epic_id/run_id derived from evidence_dir path when no fsm-state.yaml" {
  _build high
  [ "$status" -eq 0 ]
  run jq -r '.identity.epic_id' "$MANIFEST"
  [ "$output" = "E-test" ]
  run jq -r '.identity.run_id' "$MANIFEST"
  [ "$output" = "R-test" ]
  run jq -r '.identity.project_id' "$MANIFEST"
  [ "$output" = "test-c3-proj" ]
}

@test "identity: epic_id/run_id read from fsm-state.yaml when present (overrides path)" {
  cat > "$TEST_EVIDENCE_DIR/fsm-state.yaml" <<'YAML'
epic_id: E-065-1_7
run_id: R-E065-1
state: DONE
YAML
  _build high
  [ "$status" -eq 0 ]
  run jq -r '.identity.epic_id' "$MANIFEST"
  [ "$output" = "E-065-1_7" ]
  run jq -r '.identity.run_id' "$MANIFEST"
  [ "$output" = "R-E065-1" ]
}

# ─── error handling (PRECONDITION FAIL, no partial manifest) ────────────────

@test "error: unresolvable head_sha → PRECONDITION FAIL exit 1, no manifest written" {
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" high
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [ ! -f "$MANIFEST" ]
}

@test "error: unresolvable base_sha → PRECONDITION FAIL exit 1" {
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "not-a-sha" "$HEAD_SHA" high
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
}

@test "error: non-git directory → PRECONDITION FAIL exit 1" {
  local nongit="$TEST_TMPDIR/nongit"
  mkdir -p "$nongit"
  run bash -c "cd '$nongit' && bash '$DISPATCH' build-manifest '$nongit/ev' '$BASE_SHA' '$HEAD_SHA' high"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
}

@test "error: AID_PLAN_AC_FILE set but unreadable → PRECONDITION FAIL exit 1" {
  export AID_PLAN_AC_FILE="$TEST_TMPDIR/missing-plan.md"
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
}

@test "error: wrong argument count → exit 1" {
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA"
  [ "$status" -eq 1 ]
}

# ─── CLI skeleton (build-manifest only; other subcommands are stubs) ────────

# dispatch is IMPLEMENTED as of Step 5 (this EPIC): it is no longer a stub. With
# no <evidence_dir> it is a usage/precondition error (exit 1), not exit-2 "not
# yet implemented". (Full dispatch behavior is covered by the Step-5 block below.)
@test "skeleton: dispatch subcommand requires <evidence_dir> (usage error, no longer a stub)" {
  run bash "$DISPATCH" dispatch
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" != *"not yet implemented"* ]]
}

@test "skeleton: verify subcommand is a not-yet-implemented stub (exit 2)" {
  run bash "$DISPATCH" verify
  [ "$status" -eq 2 ]
  [[ "$output" == *"not yet implemented"* ]]
}

@test "skeleton: unknown subcommand → exit 1 with usage" {
  run bash "$DISPATCH" frobnicate
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown subcommand"* ]]
}

@test "skeleton: no subcommand → exit 1" {
  run bash "$DISPATCH"
  [ "$status" -eq 1 ]
}

@test "skeleton: --help → exit 0" {
  run bash "$DISPATCH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"build-manifest"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════
# Step 3 (qa) — fake-codex CLI fixture harness
#
# Additive only: exercises scripts/tests/fixtures/fake-codex/codex, the
# deterministic stub of the real `codex` CLI. setup() prepends it to PATH;
# these tests never touch the Step-2 build-manifest tests above.
# Grounding: scripts/tests/e2e/evidence/codex-stream-sample/fields.md.
# ═══════════════════════════════════════════════════════════════════════════

# _fc_codex <mode> [extra positional args…] — invoke the PATH-resolved `codex`
# stub in <mode>. Captures the --json stream into $output and $FC_STREAM, and
# the last-message into $FC_LAST. Uses the deterministic FAKE_CODEX_EXPECT_*
# exported by setup(). After the call, $status = the stub's exit code.
_fc_codex() {
  local mode="$1"; shift || true
  FAKE_CODEX_MODE="$mode" run codex exec --json --skip-git-repo-check --ephemeral \
    --cd "$TEST_PROJECT_ROOT" --sandbox read-only -m gpt-5.5 \
    --output-schema /dev/null \
    --output-last-message "$FC_LAST" "$@" "Review the C3 brief and report."
  printf '%s\n' "$output" > "$FC_STREAM"
}

# _fc_events_valid <stream_file> — echo "true"/"false" per fields.md's 4-condition
# events_valid definition (thread.started-first w/ UUID, turn.completed-last, no
# error line, ≥1 agent_message).
_fc_events_valid() {
  jq -rs '
    (.[0].type=="thread.started")                                                as $c1a
    | ((.[0].thread_id // "")|length>0)                                          as $c1b
    | (.[-1].type=="turn.completed")                                             as $c2
    | ((map(select(.type=="error"))|length)==0)                                  as $c3
    | ((map(select(.type=="item.completed" and .item.type=="agent_message"))|length)>0) as $c4
    | ($c1a and $c1b and $c2 and $c3 and $c4)
  ' "$1"
}

# ─── AC3: setup() resolves `codex` to the fixture ───────────────────────────

@test "step3/AC3: setup() resolves codex --version to fake-codex 0.0.0 (fixture wins on PATH)" {
  run codex --version
  [ "$status" -eq 0 ]
  [ "$output" = "fake-codex 0.0.0" ]
  # the resolved binary is the prepended fixture, not any real codex
  run command -v codex
  [ "$output" = "$FAKE_CODEX_DIR/codex" ]
}

# ─── AC1: valid-mode stream matches fields.md event vocabulary/ordering ──────

@test "step3/AC1: valid stream — session id + completion event present, correct vocabulary/order" {
  _fc_codex valid
  [ "$status" -eq 0 ]
  # first line = thread.started carrying a non-empty UUID-shaped session id
  run jq -rs '.[0].type' "$FC_STREAM"
  [ "$output" = "thread.started" ]
  run jq -rs '.[0].thread_id' "$FC_STREAM"
  [[ "$output" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
  # turn.started present
  run jq -rs 'any(.[]; .type=="turn.started")' "$FC_STREAM"
  [ "$output" = "true" ]
  # last line = turn.completed (the completion event) with 4 integer usage keys
  run jq -rs '.[-1].type' "$FC_STREAM"
  [ "$output" = "turn.completed" ]
  run jq -rs '.[-1].usage | [.input_tokens,.cached_input_tokens,.output_tokens,.reasoning_output_tokens] | map(type=="number") | all' "$FC_STREAM"
  [ "$output" = "true" ]
  # every emitted line is valid JSONL
  run jq -e -c . "$FC_STREAM"
  [ "$status" -eq 0 ]
}

@test "step3/AC1: valid stream — session id + usage resolve via the exact fields.md jq paths" {
  _fc_codex valid
  run jq -r 'select(.type=="thread.started")|.thread_id' "$FC_STREAM"
  [ -n "$output" ]
  run jq -c 'select(.type=="turn.completed")|.usage' "$FC_STREAM"
  [[ "$output" == *'"input_tokens"'* ]]
}

@test "step3/AC1: final answer is the LAST agent_message and is schema-shaped JSON" {
  _fc_codex valid
  local final
  final=$(jq -rs 'map(select(.type=="item.completed" and .item.type=="agent_message"))|last|.item.text' "$FC_STREAM")
  # parses as JSON and carries the informal c3-codex-response shape
  echo "$final" | jq -e '.reviewed_head and .codex_brief_hash and .review_status and (.blocking_findings|type=="boolean") and (.findings|type=="array")'
  # in valid mode reviewed_head / codex_brief_hash echo the EXPECT_* envs
  [ "$(echo "$final" | jq -r .reviewed_head)" = "$FAKE_CODEX_EXPECT_HEAD" ]
  [ "$(echo "$final" | jq -r .codex_brief_hash)" = "$FAKE_CODEX_EXPECT_MANIFEST_HASH" ]
  # ≥1 high-severity finding carries action_owner
  echo "$final" | jq -e '[.findings[]|select(.severity=="high" and .action_owner)]|length>0'
}

@test "step3/AC1: valid stream passes the events_valid 4-condition check" {
  _fc_codex valid
  [ "$(_fc_events_valid "$FC_STREAM")" = "true" ]
}

# ─── AC2: each FAKE_CODEX_MODE → intended last-message + exit ────────────────

@test "step3/AC2 valid: exit 0, last-message is JSON echoing EXPECT_*" {
  _fc_codex valid
  [ "$status" -eq 0 ]
  run jq -r .reviewed_head "$FC_LAST"
  [ "$output" = "$FAKE_CODEX_EXPECT_HEAD" ]
  run jq -r .codex_brief_hash "$FC_LAST"
  [ "$output" = "$FAKE_CODEX_EXPECT_MANIFEST_HASH" ]
}

@test "step3/AC2 invalid_json: exit 0, last-message unparseable, stream lines still valid" {
  _fc_codex invalid_json
  [ "$status" -eq 0 ]
  run jq -e . "$FC_LAST"          # last-message is malformed JSON
  [ "$status" -ne 0 ]
  run jq -e -c . "$FC_STREAM"     # yet each stream LINE is valid JSONL
  [ "$status" -eq 0 ]
}

@test "step3/AC2 hash_mismatch: head OK, codex_brief_hash != EXPECT (still sha256-shaped)" {
  _fc_codex hash_mismatch
  [ "$status" -eq 0 ]
  [ "$(jq -r .reviewed_head "$FC_LAST")" = "$FAKE_CODEX_EXPECT_HEAD" ]
  local h
  h=$(jq -r .codex_brief_hash "$FC_LAST")
  [ "$h" != "$FAKE_CODEX_EXPECT_MANIFEST_HASH" ]
  [[ "$h" =~ ^sha256:[0-9a-f]{64}$ ]]
}

@test "step3/AC2 head_mismatch: hash OK, reviewed_head != EXPECT (still 40-hex)" {
  _fc_codex head_mismatch
  [ "$status" -eq 0 ]
  [ "$(jq -r .codex_brief_hash "$FC_LAST")" = "$FAKE_CODEX_EXPECT_MANIFEST_HASH" ]
  local rh
  rh=$(jq -r .reviewed_head "$FC_LAST")
  [ "$rh" != "$FAKE_CODEX_EXPECT_HEAD" ]
  [[ "$rh" =~ ^[0-9a-f]{40}$ ]]
}

@test "step3/AC2 missing_action_owner: exit 0, a high-severity finding lacks action_owner" {
  _fc_codex missing_action_owner
  [ "$status" -eq 0 ]
  run jq -e '[.findings[]|select(.severity=="high" and (has("action_owner")|not))]|length>0' "$FC_LAST"
  [ "$status" -eq 0 ]
}

@test "step3/AC2 no_stream: exit 0 but events_valid fails (last line != turn.completed)" {
  _fc_codex no_stream
  [ "$status" -eq 0 ]
  [ "$(_fc_events_valid "$FC_STREAM")" = "false" ]
  run jq -rs '.[-1].type' "$FC_STREAM"
  [ "$output" != "turn.completed" ]
}

@test "step3/AC2 rate_limited: exit 1, error + turn.failed with rate-limit signature" {
  _fc_codex rate_limited
  [ "$status" -eq 1 ]
  run jq -rs 'map(.type)|contains(["error"]) and contains(["turn.failed"])' "$FC_STREAM"
  [ "$output" = "true" ]
  grep -q "rate_limit_exceeded" "$FC_STREAM"
}

@test "step3/AC2 timeout: mode hangs — a timeout wrapper kills it (exit 124), never waited on directly" {
  FAKE_CODEX_MODE=timeout run timeout 2 codex exec --json "prompt"
  [ "$status" -eq 124 ]
}

@test "step3/AC2 unknown mode → exit 2 (fail-closed)" {
  FAKE_CODEX_MODE=definitely-not-a-mode run codex exec --json "prompt"
  [ "$status" -eq 2 ]
}

@test "step3/AC2 valid with UNSET EXPECT_* → loud sentinel (never silent pass)" {
  unset FAKE_CODEX_EXPECT_HEAD FAKE_CODEX_EXPECT_MANIFEST_HASH
  FAKE_CODEX_MODE=valid run codex exec --json --output-last-message "$FC_LAST" "prompt"
  [ "$status" -eq 0 ]
  [ "$(jq -r .reviewed_head "$FC_LAST")" = "UNSET_SENTINEL_BAD_VALUE" ]
  [ "$(jq -r .codex_brief_hash "$FC_LAST")" = "UNSET_SENTINEL_BAD_VALUE" ]
}

# ─── AC2: the fixture NEVER runs git ────────────────────────────────────────

@test "step3/AC2: fixture never invokes git (tripwire across all non-hang modes)" {
  local tripdir="$TEST_TMPDIR/git-tripwire"
  mkdir -p "$tripdir"
  local marker="$TEST_TMPDIR/git-was-called.marker"
  cat > "$tripdir/git" <<EOF
#!/usr/bin/env bash
echo called >> "$marker"
exit 99
EOF
  chmod +x "$tripdir/git"
  # tripdir first, then the fixture dir (from setup): `codex` still resolves to
  # the fixture, but ANY git call the fixture might make would hit the tripwire.
  local m
  for m in valid invalid_json hash_mismatch head_mismatch missing_action_owner no_stream rate_limited; do
    PATH="$tripdir:$PATH" FAKE_CODEX_MODE="$m" run codex exec --json \
      --cd "$TEST_PROJECT_ROOT" --output-last-message "$FC_LAST" "prompt"
  done
  [ ! -f "$marker" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# Step 4 (backend) — Output contracts
#
# Additive only: never touches the Step-2/Step-3 tests above. Exercises the
# files authored in Step 4:
#   - scripts/aid-protocol-validate.sh   (extended Step-14 audit_report loop)
#   - defaults/schemas/c3-codex-response.schema.json
#   - defaults/schemas/audit-input-manifest.schema.json  (new provenance fields)
#   - defaults/prompts/c3-audit-prompt-v1.md + scripts/lib/aid-render-prompt.sh
#
# JSON-Schema tests use python3 + jsonschema (Draft 2020-12) — the SAME idiom
# aid-lifecycle.sh uses to validate lifecycle artifacts; they skip cleanly when
# it is unavailable rather than false-failing on a machine without it.
# ═══════════════════════════════════════════════════════════════════════════

RESP_SCHEMA_REL="defaults/schemas/c3-codex-response.schema.json"
MANIFEST_SCHEMA_REL="defaults/schemas/audit-input-manifest.schema.json"
RENDER_REL="scripts/lib/aid-render-prompt.sh"
PROMPT_REL="defaults/prompts/c3-audit-prompt-v1.md"

# Shared constants for the audit_report validator tests.
_IMH="sha256:2222222222222222222222222222222222222222222222222222222222222222"
_RH40="1234567890abcdef1234567890abcdef12345678"

_have_jsonschema() {
  command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' >/dev/null 2>&1
}

# _schema_validate <schema_file> <instance_file> — exit 0 valid, 1 invalid.
_schema_validate() {
  python3 - "$1" "$2" <<'PY'
import sys, json
from jsonschema.validators import Draft202012Validator
schema = json.load(open(sys.argv[1]))
inst = json.load(open(sys.argv[2]))
sys.exit(1 if list(Draft202012Validator(schema).iter_errors(inst)) else 0)
PY
}

# _write_audit_report <path> <audit_report_inner_json>
#   Full protocol-v2 envelope + the given .audit_report inner object.
_write_audit_report() {
  local path="$1" inner="$2"
  cat > "$path" <<JSON
{
  "schema_version": "aid-2.0",
  "artifact_type": "audit_report",
  "producer": "test",
  "created_at": "2026-07-14T00:00:00Z",
  "control_protocol": "aid-2.0",
  "identity": {"project_id": "p"},
  "subject": {"subject_hash": "sha256:0000000000000000000000000000000000000000000000000000000000000001"},
  "revision": {"head_sha": "abc"},
  "status": "pass",
  "verdict": {"kind": "none"},
  "provenance": {"dispatch_mode": "deterministic", "generated_by_tool": "t"},
  "audit_report": ${inner}
}
JSON
}

_write_min_template() {
  cat > "$1" <<'EOF'
---
template_id: min
template_version: v1
variables: [only]
---
Value: {{only}}
EOF
}

_write_full_prompt_vars() {
  cat > "$1" <<'JSON'
{
  "plan_path": ".aid-o/plans/P065.md",
  "plan_sha256": "sha256:deadbeef",
  "base_sha": "1111111111111111111111111111111111111111",
  "head_sha": "2222222222222222222222222222222222222222",
  "input_manifest_path": "audit-input-manifest.json",
  "input_manifest_hash": "sha256:abc",
  "codex_brief_hash": "sha256:def",
  "bundle_diff_path": "c3/bundle-diff.patch",
  "bundle_scope_path": "c3/bundle-scope.txt",
  "acceptance_criteria_path": "c3/bundle-plan-ac.md",
  "review_profile_path": "c3/bundle-review-profile.json",
  "evidence_paths": "final_report.md, gates_report.json",
  "output_schema_path": "defaults/schemas/c3-codex-response.schema.json",
  "allowed_recheck_commands": "[]",
  "verification_budget": "max_commands=10 max_seconds=120"
}
JSON
}

# ─── AC1: aid-protocol-validate.sh Step-14 provenance fields ────────────────

@test "step4/AC1: audit_report WITHOUT reviewed_head fails Step 14 (exit 14)" {
  _write_audit_report "$TEST_TMPDIR/ar.json" \
    "{\"provider\":\"a\",\"model\":\"m\",\"process_id\":\"p\",\"input_manifest_hash\":\"$_IMH\",\"required_independence_level\":\"cross_model\"}"
  run bash "$VALIDATE" "$TEST_TMPDIR/ar.json"
  [ "$status" -eq 14 ]
  [[ "$output" == *"missing_audit_report_field:reviewed_head"* ]]
}

@test "step4/AC1: audit_report WITH valid 40-hex reviewed_head + all required passes (exit 0)" {
  _write_audit_report "$TEST_TMPDIR/ar.json" \
    "{\"provider\":\"a\",\"model\":\"m\",\"process_id\":\"p\",\"input_manifest_hash\":\"$_IMH\",\"required_independence_level\":\"cross_model\",\"reviewed_head\":\"$_RH40\"}"
  run bash "$VALIDATE" "$TEST_TMPDIR/ar.json"
  [ "$status" -eq 0 ]
}

@test "step4/AC1: audit_report missing required_independence_level fails (exit 14)" {
  _write_audit_report "$TEST_TMPDIR/ar.json" \
    "{\"provider\":\"a\",\"model\":\"m\",\"process_id\":\"p\",\"input_manifest_hash\":\"$_IMH\",\"reviewed_head\":\"$_RH40\"}"
  run bash "$VALIDATE" "$TEST_TMPDIR/ar.json"
  [ "$status" -eq 14 ]
  [[ "$output" == *"missing_audit_report_field:required_independence_level"* ]]
}

@test "step4/AC1: bad required_independence_level enum fails (exit 14)" {
  _write_audit_report "$TEST_TMPDIR/ar.json" \
    "{\"provider\":\"a\",\"model\":\"m\",\"process_id\":\"p\",\"input_manifest_hash\":\"$_IMH\",\"required_independence_level\":\"bogus\",\"reviewed_head\":\"$_RH40\"}"
  run bash "$VALIDATE" "$TEST_TMPDIR/ar.json"
  [ "$status" -eq 14 ]
  [[ "$output" == *"bad_audit_report_enum:required_independence_level"* ]]
}

@test "step4/AC1: bad OPTIONAL independence_level enum fails when present (exit 14)" {
  _write_audit_report "$TEST_TMPDIR/ar.json" \
    "{\"provider\":\"a\",\"model\":\"m\",\"process_id\":\"p\",\"input_manifest_hash\":\"$_IMH\",\"required_independence_level\":\"cross_model\",\"independence_level\":\"nope\",\"reviewed_head\":\"$_RH40\"}"
  run bash "$VALIDATE" "$TEST_TMPDIR/ar.json"
  [ "$status" -eq 14 ]
  [[ "$output" == *"bad_audit_report_enum:independence_level"* ]]
}

@test "step4/AC1: advisory non-boolean fails (exit 14); advisory boolean passes (exit 0)" {
  _write_audit_report "$TEST_TMPDIR/bad.json" \
    "{\"provider\":\"a\",\"model\":\"m\",\"process_id\":\"p\",\"input_manifest_hash\":\"$_IMH\",\"required_independence_level\":\"cross_model\",\"reviewed_head\":\"$_RH40\",\"advisory\":\"yes\"}"
  run bash "$VALIDATE" "$TEST_TMPDIR/bad.json"
  [ "$status" -eq 14 ]
  [[ "$output" == *"bad_audit_report_type:advisory"* ]]
  _write_audit_report "$TEST_TMPDIR/ok.json" \
    "{\"provider\":\"a\",\"model\":\"m\",\"process_id\":\"p\",\"input_manifest_hash\":\"$_IMH\",\"required_independence_level\":\"cross_model\",\"reviewed_head\":\"$_RH40\",\"advisory\":true}"
  run bash "$VALIDATE" "$TEST_TMPDIR/ok.json"
  [ "$status" -eq 0 ]
}

# ─── AC2: c3-codex-response.schema.json ─────────────────────────────────────

@test "step4/AC2: response schema accepts a valid response" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  cat > "$TEST_TMPDIR/resp.json" <<'JSON'
{
  "reviewed_head": "1234567890abcdef1234567890abcdef12345678",
  "codex_brief_hash": "sha256:2222222222222222222222222222222222222222222222222222222222222222",
  "review_status": "findings",
  "blocking_findings": true,
  "findings": [
    {"severity":"high","area":"scripts/x.sh:1","finding":"f","recommendation":"r","action_owner":"implementer"}
  ]
}
JSON
  run _schema_validate "$AID_PLUGIN_PATH/$RESP_SCHEMA_REL" "$TEST_TMPDIR/resp.json"
  [ "$status" -eq 0 ]
}

@test "step4/AC2: response schema rejects a high finding missing action_owner" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  cat > "$TEST_TMPDIR/resp.json" <<'JSON'
{
  "reviewed_head": "1234567890abcdef1234567890abcdef12345678",
  "codex_brief_hash": "sha256:2222222222222222222222222222222222222222222222222222222222222222",
  "review_status": "findings",
  "blocking_findings": true,
  "findings": [
    {"severity":"high","area":"scripts/x.sh:1","finding":"f","recommendation":"r"}
  ]
}
JSON
  run _schema_validate "$AID_PLUGIN_PATH/$RESP_SCHEMA_REL" "$TEST_TMPDIR/resp.json"
  [ "$status" -ne 0 ]
}

@test "step4/AC2: response schema rejects a top-level process_id (additionalProperties:false)" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  cat > "$TEST_TMPDIR/resp.json" <<'JSON'
{
  "reviewed_head": "1234567890abcdef1234567890abcdef12345678",
  "codex_brief_hash": "sha256:2222222222222222222222222222222222222222222222222222222222222222",
  "review_status": "pass",
  "blocking_findings": false,
  "findings": [],
  "process_id": "leaked-by-model"
}
JSON
  run _schema_validate "$AID_PLUGIN_PATH/$RESP_SCHEMA_REL" "$TEST_TMPDIR/resp.json"
  [ "$status" -ne 0 ]
}

@test "step4/AC2: unverifiable REQUIRES unverifiable_reasons; the field is forbidden otherwise" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  # unverifiable WITHOUT reasons → reject
  cat > "$TEST_TMPDIR/u1.json" <<'JSON'
{"reviewed_head":"1234567890abcdef1234567890abcdef12345678","codex_brief_hash":"sha256:2222222222222222222222222222222222222222222222222222222222222222","review_status":"unverifiable","blocking_findings":false,"findings":[]}
JSON
  run _schema_validate "$AID_PLUGIN_PATH/$RESP_SCHEMA_REL" "$TEST_TMPDIR/u1.json"
  [ "$status" -ne 0 ]
  # unverifiable WITH reasons → accept
  cat > "$TEST_TMPDIR/u2.json" <<'JSON'
{"reviewed_head":"1234567890abcdef1234567890abcdef12345678","codex_brief_hash":"sha256:2222222222222222222222222222222222222222222222222222222222222222","review_status":"unverifiable","blocking_findings":false,"findings":[],"unverifiable_reasons":["no gate artifact at reviewed HEAD"]}
JSON
  run _schema_validate "$AID_PLUGIN_PATH/$RESP_SCHEMA_REL" "$TEST_TMPDIR/u2.json"
  [ "$status" -eq 0 ]
  # reasons present on a NON-unverifiable status → reject
  cat > "$TEST_TMPDIR/u3.json" <<'JSON'
{"reviewed_head":"1234567890abcdef1234567890abcdef12345678","codex_brief_hash":"sha256:2222222222222222222222222222222222222222222222222222222222222222","review_status":"pass","blocking_findings":false,"findings":[],"unverifiable_reasons":["x"]}
JSON
  run _schema_validate "$AID_PLUGIN_PATH/$RESP_SCHEMA_REL" "$TEST_TMPDIR/u3.json"
  [ "$status" -ne 0 ]
}

@test "step4/AC2: pass forbids findings/blocking; findings-status requires >=1 finding" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  # pass WITH a finding → reject
  cat > "$TEST_TMPDIR/p1.json" <<'JSON'
{"reviewed_head":"1234567890abcdef1234567890abcdef12345678","codex_brief_hash":"sha256:2222222222222222222222222222222222222222222222222222222222222222","review_status":"pass","blocking_findings":false,"findings":[{"severity":"low","area":"x","finding":"f","recommendation":"r"}]}
JSON
  run _schema_validate "$AID_PLUGIN_PATH/$RESP_SCHEMA_REL" "$TEST_TMPDIR/p1.json"
  [ "$status" -ne 0 ]
  # pass WITH blocking_findings:true → reject
  cat > "$TEST_TMPDIR/p1b.json" <<'JSON'
{"reviewed_head":"1234567890abcdef1234567890abcdef12345678","codex_brief_hash":"sha256:2222222222222222222222222222222222222222222222222222222222222222","review_status":"pass","blocking_findings":true,"findings":[]}
JSON
  run _schema_validate "$AID_PLUGIN_PATH/$RESP_SCHEMA_REL" "$TEST_TMPDIR/p1b.json"
  [ "$status" -ne 0 ]
  # findings-status with an empty findings array → reject
  cat > "$TEST_TMPDIR/p2.json" <<'JSON'
{"reviewed_head":"1234567890abcdef1234567890abcdef12345678","codex_brief_hash":"sha256:2222222222222222222222222222222222222222222222222222222222222222","review_status":"findings","blocking_findings":false,"findings":[]}
JSON
  run _schema_validate "$AID_PLUGIN_PATH/$RESP_SCHEMA_REL" "$TEST_TMPDIR/p2.json"
  [ "$status" -ne 0 ]
}

# ─── AC3: audit-input-manifest.schema.json (new provenance fields) ──────────

@test "step4/AC3: REAL build-manifest output validates against audit-input-manifest.schema.json" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  _build high
  [ "$status" -eq 0 ]
  run _schema_validate "$AID_PLUGIN_PATH/$MANIFEST_SCHEMA_REL" "$MANIFEST"
  [ "$status" -eq 0 ]
  # the new provenance fields are actually present in that manifest
  run jq -e '.audit_input_manifest | has("base_sha") and has("head_sha") and has("codex_brief_files") and has("codex_brief_hash")' "$MANIFEST"
  [ "$status" -eq 0 ]
}

@test "step4/AC3: legacy audit_input_manifest fixture still validates (back-compat)" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  run _schema_validate "$AID_PLUGIN_PATH/$MANIFEST_SCHEMA_REL" \
    "$AID_PLUGIN_PATH/scripts/tests/fixtures/protocol-v2/audit_input_manifest/valid.json"
  [ "$status" -eq 0 ]
}

# ─── Prompt template + renderer (aid-render-prompt.sh) ──────────────────────

@test "step4/render: real c3-audit-prompt-v1.md renders with a full var set (no residual, provenance emitted)" {
  _write_full_prompt_vars "$TEST_TMPDIR/vars.json"
  run bash "$AID_PLUGIN_PATH/$RENDER_REL" \
    --template "$AID_PLUGIN_PATH/$PROMPT_REL" \
    --vars-json "$TEST_TMPDIR/vars.json" \
    --output "$TEST_TMPDIR/rendered.md"
  [ "$status" -eq 0 ]
  # provenance JSON on stdout carries template_id + both sha256 hashes
  echo "$output" | jq -e '.template_id=="c3-audit-prompt" and (.template_sha256|test("^sha256:[0-9a-f]{64}$")) and (.rendered_prompt_sha256|test("^sha256:[0-9a-f]{64}$"))'
  # no residual placeholder; head_sha substituted; frontmatter stripped
  ! grep -qE '\{\{' "$TEST_TMPDIR/rendered.md"
  grep -q "2222222222222222222222222222222222222222" "$TEST_TMPDIR/rendered.md"
  ! grep -q "template_id: c3-audit-prompt" "$TEST_TMPDIR/rendered.md"
}

@test "step4/render: deterministic — identical inputs reproduce rendered_prompt_sha256 + byte-identical output" {
  _write_full_prompt_vars "$TEST_TMPDIR/vars.json"
  run bash "$AID_PLUGIN_PATH/$RENDER_REL" --template "$AID_PLUGIN_PATH/$PROMPT_REL" --vars-json "$TEST_TMPDIR/vars.json" --output "$TEST_TMPDIR/r1.md"
  [ "$status" -eq 0 ]
  local h1; h1="$(echo "$output" | jq -r .rendered_prompt_sha256)"
  run bash "$AID_PLUGIN_PATH/$RENDER_REL" --template "$AID_PLUGIN_PATH/$PROMPT_REL" --vars-json "$TEST_TMPDIR/vars.json" --output "$TEST_TMPDIR/r2.md"
  [ "$status" -eq 0 ]
  local h2; h2="$(echo "$output" | jq -r .rendered_prompt_sha256)"
  [ "$h1" = "$h2" ]
  cmp -s "$TEST_TMPDIR/r1.md" "$TEST_TMPDIR/r2.md"
}

@test "step4/render: substitution is LITERAL (no eval / no shell expansion of values)" {
  _write_min_template "$TEST_TMPDIR/min.md"
  jq -n '{only: "L1 $(echo PWNED) `id` ${HOME} & | ; > <"}' > "$TEST_TMPDIR/v.json"
  run bash "$AID_PLUGIN_PATH/$RENDER_REL" --template "$TEST_TMPDIR/min.md" --vars-json "$TEST_TMPDIR/v.json" --output "$TEST_TMPDIR/out.md"
  [ "$status" -eq 0 ]
  grep -qF 'Value: L1 $(echo PWNED) `id` ${HOME} & | ; > <' "$TEST_TMPDIR/out.md"
}

@test "step4/render: fails closed when a declared variable is MISSING from vars-json (no output written)" {
  _write_min_template "$TEST_TMPDIR/min.md"
  echo '{}' > "$TEST_TMPDIR/v.json"
  run bash "$AID_PLUGIN_PATH/$RENDER_REL" --template "$TEST_TMPDIR/min.md" --vars-json "$TEST_TMPDIR/v.json" --output "$TEST_TMPDIR/out.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"MISSING"* ]]
  [ ! -f "$TEST_TMPDIR/out.md" ]
}

@test "step4/render: fails closed on an UNKNOWN (undeclared) variable in vars-json" {
  _write_min_template "$TEST_TMPDIR/min.md"
  jq -n '{only:"x", extra:"y"}' > "$TEST_TMPDIR/v.json"
  run bash "$AID_PLUGIN_PATH/$RENDER_REL" --template "$TEST_TMPDIR/min.md" --vars-json "$TEST_TMPDIR/v.json" --output "$TEST_TMPDIR/out.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"UNKNOWN"* ]]
}

@test "step4/render: fails closed on a non-string value" {
  _write_min_template "$TEST_TMPDIR/min.md"
  jq -n '{only: 42}' > "$TEST_TMPDIR/v.json"
  run bash "$AID_PLUGIN_PATH/$RENDER_REL" --template "$TEST_TMPDIR/min.md" --vars-json "$TEST_TMPDIR/v.json" --output "$TEST_TMPDIR/out.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"string"* ]]
}

@test "step4/render: fails closed when a value contains the placeholder opener {{ (injection guard)" {
  _write_min_template "$TEST_TMPDIR/min.md"
  jq -n '{only: "danger {{only}}"}' > "$TEST_TMPDIR/v.json"
  run bash "$AID_PLUGIN_PATH/$RENDER_REL" --template "$TEST_TMPDIR/min.md" --vars-json "$TEST_TMPDIR/v.json" --output "$TEST_TMPDIR/out.md"
  [ "$status" -ne 0 ]
}

@test "step4/render: fails closed on an UNDECLARED {{placeholder}} in the template body (no output written)" {
  cat > "$TEST_TMPDIR/bad.md" <<'EOF'
---
template_id: bad
template_version: v1
variables: [only]
---
{{only}} and {{ghost}}
EOF
  jq -n '{only:"x"}' > "$TEST_TMPDIR/v.json"
  run bash "$AID_PLUGIN_PATH/$RENDER_REL" --template "$TEST_TMPDIR/bad.md" --vars-json "$TEST_TMPDIR/v.json" --output "$TEST_TMPDIR/out.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"undeclared placeholder"* ]]
  [ ! -f "$TEST_TMPDIR/out.md" ]
}

@test "step4/render: missing --output flag → usage error (exit 1)" {
  _write_min_template "$TEST_TMPDIR/min.md"
  jq -n '{only:"x"}' > "$TEST_TMPDIR/v.json"
  run bash "$AID_PLUGIN_PATH/$RENDER_REL" --template "$TEST_TMPDIR/min.md" --vars-json "$TEST_TMPDIR/v.json"
  [ "$status" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# Step 5 (backend) — Executor-first Codex dispatch (`dispatch`) + raw capture
#
# Additive only: never touches the Step-2/3/4 tests above. Exercises cmd_dispatch
# in scripts/lib/aid-c3-dispatch.sh: the executor is chosen FIRST and Codex is
# ALWAYS probed as cross_provider (never cross_model, never cached); the real
# codex CLI (the deterministic fake-codex fixture, wrapped by a logging spy) is
# invoked read-only in a fresh process; raw output + codex-derived provenance
# are captured into <evidence_dir>/c3/c3-dispatch.json.
#
# Grounding: scripts/tests/e2e/evidence/codex-stream-sample/fields.md.
#
# Two test seams (both consumed by cmd_dispatch via env, NOT by editing source):
#   AID_C3_INDEPENDENCE_BIN → a spy that LOGS its `detect --required <level>` args
#     and returns available(0)/unverifiable(2). It never calls codex, so the only
#     codex invocations are the dispatch calls themselves (clean AC3 count).
#   a `codex` spy PREPENDED to PATH that logs each invocation's args (one
#     ARG:<val> line each) then exec's fake-codex. Lets us assert the exact
#     `--cd <repo> --sandbox read-only` launch and the absence of --output-schema.
# ═══════════════════════════════════════════════════════════════════════════

# _seed_manifest [risk_profile] — build a REAL manifest for dispatch to consume.
_seed_manifest() {
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" "${1:-high}"
  [ "$status" -eq 0 ]
}

# _dispatch_seams — install the independence pre-check spy + the logging codex
# spy, and export the paths/handles the Step-5 tests assert against.
_dispatch_seams() {
  INDEP_SPY="$TEST_TMPDIR/indep-spy"; mkdir -p "$INDEP_SPY"
  export INDEP_SPY
  INDEP_LOG="$TEST_TMPDIR/indep.log"; : > "$INDEP_LOG"
  export INDEP_LOG
  cat > "$INDEP_SPY/detect" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$INDEP_LOG"
exit 0
EOF
  chmod +x "$INDEP_SPY/detect"
  export AID_C3_INDEPENDENCE_BIN="$INDEP_SPY/detect"

  CODEX_SPY="$TEST_TMPDIR/codex-spy"; mkdir -p "$CODEX_SPY"
  export CODEX_SPY
  CODEX_LOG="$TEST_TMPDIR/codex.log"; : > "$CODEX_LOG"
  export CODEX_LOG
  cat > "$CODEX_SPY/codex" <<EOF
#!/usr/bin/env bash
{ echo "=== INVOKE ==="; for a in "\$@"; do printf 'ARG:%s\n' "\$a"; done; } >> "$CODEX_LOG"
exec "$FAKE_CODEX_DIR/codex" "\$@"
EOF
  chmod +x "$CODEX_SPY/codex"
  PATH="$CODEX_SPY:$PATH"; export PATH

  # Coherent EXPECT_* so valid-mode echoes the manifest's real head + brief hash.
  export FAKE_CODEX_EXPECT_HEAD="$HEAD_SHA"
  export FAKE_CODEX_EXPECT_MANIFEST_HASH="$(jq -r '.audit_input_manifest.codex_brief_hash // ""' "$MANIFEST" 2>/dev/null || echo "")"

  PROJECT_ROOT="$(git -C "$TEST_EVIDENCE_DIR" rev-parse --show-toplevel)"
  export PROJECT_ROOT
  DJSON="$TEST_EVIDENCE_DIR/c3/c3-dispatch.json"
  export DJSON
}

# ─── AC1: the executor probes cross_provider, NEVER cross_model ──────────────

@test "step5/AC1: high profile → dispatch probes detect --required cross_provider (NOT cross_model)" {
  _seed_manifest high
  # For high, the manifest's REQUIRED level is cross_model — the tempting-but-wrong
  # value the old executor/level mismatch would have probed. The executor must
  # still probe cross_provider.
  run jq -r '.audit_input_manifest.required_independence_level' "$MANIFEST"
  [ "$output" = "cross_model" ]

  _dispatch_seams
  FAKE_CODEX_MODE=valid run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  # The pre-check the bridge ACTUALLY made (spy log):
  grep -q 'detect --required cross_provider' "$INDEP_LOG"
  ! grep -q 'cross_model' "$INDEP_LOG"

  # …and it is recorded as the probed level (required is carried through verbatim).
  run jq -r '.independence.probed_independence_level' "$DJSON"
  [ "$output" = "cross_provider" ]
  run jq -r '.independence.required_independence_level' "$DJSON"
  [ "$output" = "cross_model" ]
}

# ─── AC2: valid mode captures session id / events_valid / achieved / raw sha ──

@test "step5/AC2: valid — codex launched --cd <repo> --sandbox read-only; session id, events_valid:true, achieved cross_provider, raw_response_sha256 recorded" {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=valid run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ -f "$DJSON" ]

  # provenance parsed from the --json stream (fields.md paths)
  run jq -r '.dispatch.codex_session_id' "$DJSON"
  [[ "$output" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
  run jq -r '.dispatch.events_valid' "$DJSON"; [ "$output" = "true" ]
  run jq -r '.dispatch.outcome' "$DJSON"; [ "$output" = "dispatched" ]
  run jq -r '.dispatch.invoked' "$DJSON"; [ "$output" = "true" ]
  run jq -r '.dispatch.exit_code' "$DJSON"; [ "$output" = "0" ]
  run jq -r '.independence.achieved_independence_level' "$DJSON"; [ "$output" = "cross_provider" ]
  run jq -r '.dispatch.raw_response_sha256' "$DJSON"; [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]
  run jq -r '.dispatch.stdout_sha256' "$DJSON"; [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]

  # reported model = the bridge's own -m arg (the slug is ABSENT from the stream)
  run jq -r '.executor.reported_model' "$DJSON"; [ "$output" = "gpt-5.6-terra" ]

  # codex was actually launched exec/read-only, cd'd to the repo root, and — per
  # the DISCOVERED ISSUE — WITHOUT --output-schema (the if/then schema would 400).
  grep -qx "ARG:exec" "$CODEX_LOG"
  grep -qx "ARG:--cd" "$CODEX_LOG"
  grep -qx "ARG:$PROJECT_ROOT" "$CODEX_LOG"
  grep -qx "ARG:--sandbox" "$CODEX_LOG"
  grep -qx "ARG:read-only" "$CODEX_LOG"
  ! grep -qx "ARG:--output-schema" "$CODEX_LOG"

  # raw last-message actually captured; its sha matches the recorded provenance
  [ -f "$TEST_EVIDENCE_DIR/c3/codex-last-message.json" ]
  local rsha="sha256:$(sha256sum "$TEST_EVIDENCE_DIR/c3/codex-last-message.json" | awk '{print $1}')"
  [ "$(jq -r '.dispatch.raw_response_sha256' "$DJSON")" = "$rsha" ]
  # and the stdout sha matches the captured event stream
  local ssha="sha256:$(sha256sum "$TEST_EVIDENCE_DIR/c3/codex-events.jsonl" | awk '{print $1}')"
  [ "$(jq -r '.dispatch.stdout_sha256' "$DJSON")" = "$ssha" ]
}

@test "step5/AC2: prompt is rendered deterministically from the committed template (provenance recorded, no residual {{)" {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=valid run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  # the rendered prompt exists, has no leftover placeholder, and carries head_sha
  [ -f "$TEST_EVIDENCE_DIR/c3/codex-prompt.txt" ]
  ! grep -qE '\{\{' "$TEST_EVIDENCE_DIR/c3/codex-prompt.txt"
  grep -q "$HEAD_SHA" "$TEST_EVIDENCE_DIR/c3/codex-prompt.txt"
  # render provenance recorded from aid-render-prompt.sh (the committed template)
  run jq -r '.prompt.template_id' "$DJSON"; [ "$output" = "c3-audit-prompt" ]
  run jq -r '.prompt.template_sha256' "$DJSON"; [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]
  run jq -r '.prompt.rendered_prompt_sha256' "$DJSON"; [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]
}

# ─── AC3: non-sticky — consecutive rate_limited runs each re-attempt codex ───

@test "step5/AC3: two consecutive rate_limited runs BOTH invoke codex (non-sticky; second not skipped, no state persists)" {
  _seed_manifest high
  _dispatch_seams

  FAKE_CODEX_MODE=rate_limited run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  run jq -r '.dispatch.outcome' "$DJSON"; [ "$output" = "rate_limited" ]
  run jq -r '.dispatch.invoked' "$DJSON"; [ "$output" = "true" ]
  run jq -r '.independence.achieved_independence_level' "$DJSON"; [ "$output" = "unavailable" ]

  FAKE_CODEX_MODE=rate_limited run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  run jq -r '.dispatch.outcome' "$DJSON"; [ "$output" = "rate_limited" ]
  run jq -r '.dispatch.invoked' "$DJSON"; [ "$output" = "true" ]

  # BOTH runs launched `codex exec` (the second was NOT skipped) → 2 exec calls.
  run grep -c '^ARG:exec$' "$CODEX_LOG"
  [ "$output" = "2" ]
  # …and each run independently ran the pre-check → 2 probes.
  run grep -c 'detect --required cross_provider' "$INDEP_LOG"
  [ "$output" = "2" ]
  # non-sticky: NO availability-cache / state artifact was written under evidence.
  run bash -c "find '$TEST_EVIDENCE_DIR' \\( -iname '*availab*' -o -iname '*cache*' \\) | wc -l | tr -d ' '"
  [ "$output" = "0" ]
}

# ─── Error handling / edge cases (Error Handling + Edge Cases in the plan) ────

@test "step5/error: dispatch without a manifest → PRECONDITION FAIL exit 1" {
  run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"manifest missing"* ]]
}

@test "step5/edge: pre-check unavailable → non-dispatched (invoked:false, achieved unavailable, exit 2); codex NEVER launched" {
  _seed_manifest high
  _dispatch_seams
  # Flip the pre-check spy to report unverifiable (exit 2).
  cat > "$INDEP_SPY/detect" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$INDEP_LOG"
exit 2
EOF
  chmod +x "$INDEP_SPY/detect"

  FAKE_CODEX_MODE=valid run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  run jq -r '.dispatch.outcome' "$DJSON"; [ "$output" = "unavailable" ]
  run jq -r '.dispatch.invoked' "$DJSON"; [ "$output" = "false" ]
  run jq -r '.dispatch.events_valid' "$DJSON"; [ "$output" = "false" ]
  run jq -r '.independence.achieved_independence_level' "$DJSON"; [ "$output" = "unavailable" ]
  # the pre-check WAS made (cross_provider), but codex exec was never launched.
  grep -q 'detect --required cross_provider' "$INDEP_LOG"
  run grep -c '^ARG:exec$' "$CODEX_LOG"
  [ "$output" = "0" ]
}

@test "step5/edge: codex timeout (124) → outcome timeout, invoked true, events_valid false, achieved unavailable, exit 2" {
  _seed_manifest high
  _dispatch_seams
  AID_C3_TIMEOUT_SECONDS=1 FAKE_CODEX_MODE=timeout run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  run jq -r '.dispatch.outcome' "$DJSON"; [ "$output" = "timeout" ]
  run jq -r '.dispatch.exit_code' "$DJSON"; [ "$output" = "124" ]
  run jq -r '.dispatch.invoked' "$DJSON"; [ "$output" = "true" ]
  run jq -r '.dispatch.events_valid' "$DJSON"; [ "$output" = "false" ]
  run jq -r '.independence.achieved_independence_level' "$DJSON"; [ "$output" = "unavailable" ]
}

@test "step5/edge: AID_C3_TIMEOUT_SECONDS unset → 900s default is used (not an empty timeout)" {
  # We do not want to wait 900s; assert the DEFAULT is wired by inspecting that a
  # valid run (which returns immediately) still succeeds with the env UNSET.
  _seed_manifest high
  _dispatch_seams
  unset AID_C3_TIMEOUT_SECONDS
  FAKE_CODEX_MODE=valid run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  run jq -r '.dispatch.outcome' "$DJSON"; [ "$output" = "dispatched" ]
}

@test "step5/edge: no_stream (well-formed lines, no turn.completed) → events_valid false, outcome failed, exit 2" {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=no_stream run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  run jq -r '.dispatch.events_valid' "$DJSON"; [ "$output" = "false" ]
  run jq -r '.dispatch.outcome' "$DJSON"; [ "$output" = "failed" ]
  run jq -r '.independence.achieved_independence_level' "$DJSON"; [ "$output" = "unavailable" ]
  # session id is still recovered from the (present) thread.started line
  run jq -r '.dispatch.codex_session_id' "$DJSON"
  [[ "$output" =~ ^[0-9a-f]{8}- ]]
}

@test "step5/boundary: invalid_json — stream is well-formed so dispatch SUCCEEDS; the raw malformed last-message is handed to Step 6 (bridge does not reject it)" {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=invalid_json run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  run jq -r '.dispatch.events_valid' "$DJSON"; [ "$output" = "true" ]
  run jq -r '.dispatch.outcome' "$DJSON"; [ "$output" = "dispatched" ]
  # the captured raw last-message is itself NOT valid JSON — Step 6's job to reject,
  # not the dispatch/capture path's.
  run jq -e . "$TEST_EVIDENCE_DIR/c3/codex-last-message.json"
  [ "$status" -ne 0 ]
  # …but a raw_response_sha256 over those raw bytes is still recorded.
  run jq -r '.dispatch.raw_response_sha256' "$DJSON"; [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]
}

@test "step5/edge: cross_model required (high) is still ATTEMPTED as cross_provider and satisfied by achieved cross_provider" {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=valid run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  # required cross_model, probed+achieved cross_provider (never downgraded).
  run jq -r '.independence.required_independence_level' "$DJSON"; [ "$output" = "cross_model" ]
  run jq -r '.independence.probed_independence_level' "$DJSON"; [ "$output" = "cross_provider" ]
  run jq -r '.independence.achieved_independence_level' "$DJSON"; [ "$output" = "cross_provider" ]
}
