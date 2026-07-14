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
  # allowlisted changed-source path).
  local plan="$TEST_TMPDIR/plan-ac.md"
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

@test "skeleton: dispatch subcommand is a not-yet-implemented stub (exit 2)" {
  run bash "$DISPATCH" dispatch
  [ "$status" -eq 2 ]
  [[ "$output" == *"not yet implemented"* ]]
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
