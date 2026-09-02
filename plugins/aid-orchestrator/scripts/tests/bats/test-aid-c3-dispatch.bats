#!/usr/bin/env bats
# aid-tier: t2
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
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  local plan="$TEST_PROJECT_ROOT/.aid-o/plans/plan-ac.md"
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

@test "8th DONE-review audit fix ('gate evidence integrity'): manifest binds evidence-class allowlist entries to a sealed {path,sha256,size} digest" {
  _build high
  [ "$status" -eq 0 ]

  # evidence_hashes[] must contain both evidence-class entries, matching
  # the ACTUAL bytes on disk at build-manifest time.
  local real_gates_sha; real_gates_sha="sha256:$(sha256sum "$TEST_EVIDENCE_DIR/gates_report.json" | awk '{print $1}')"
  local real_gates_size; real_gates_size="$(wc -c < "$TEST_EVIDENCE_DIR/gates_report.json" | tr -d '[:space:]')"
  run jq -r '.audit_input_manifest.evidence_hashes[] | select(.path=="gates_report.json") | .sha256' "$MANIFEST"
  [ "$output" = "$real_gates_sha" ]
  run jq -r '.audit_input_manifest.evidence_hashes[] | select(.path=="gates_report.json") | .size' "$MANIFEST"
  [ "$output" = "$real_gates_size" ]

  run jq -r '.audit_input_manifest.evidence_hashes[] | select(.path=="final_report.md") | .sha256' "$MANIFEST"
  [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]

  # Production source files (changed paths) are NOT in evidence_hashes —
  # they're independently git-verifiable, unlike runtime evidence.
  run jq -r '[.audit_input_manifest.evidence_hashes[] | select(.path=="src/app.ts")] | length' "$MANIFEST"
  [ "$output" = "0" ]

  # Full schema shape: every entry has path+sha256+size, sha256 well-formed.
  run jq -e '.audit_input_manifest.evidence_hashes | all(has("path") and has("sha256") and has("size"))' "$MANIFEST"
  [ "$status" -eq 0 ]
  run bash "$VALIDATE" "$MANIFEST"
  [ "$status" -eq 0 ]

  # A hash mismatch (post-seal tamper) is detectable: the manifest's stored
  # value must NOT change just because the file on disk changes afterward.
  printf 'TAMPERED AFTER SEAL\n' > "$TEST_EVIDENCE_DIR/gates_report.json"
  run jq -r '.audit_input_manifest.evidence_hashes[] | select(.path=="gates_report.json") | .sha256' "$MANIFEST"
  [ "$output" = "$real_gates_sha" ]
  [ "$output" != "sha256:$(sha256sum "$TEST_EVIDENCE_DIR/gates_report.json" | awk '{print $1}')" ]
}

@test "8th DONE-review audit fix: the rendered C3 prompt exposes evidence_hashes as an authoritative binding" {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=valid run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  local prompt="$TEST_EVIDENCE_DIR/c3/codex-prompt.txt"
  [ -f "$prompt" ]
  run grep -c "AUTHORITATIVE evidence digests" "$prompt"
  [ "$output" -ge 1 ]
  run grep -c "gates_report.json=sha256:" "$prompt"
  [ "$output" -ge 1 ]
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

# verify is IMPLEMENTED as of Step 7 (this EPIC): it is no longer a stub. With no
# <evidence_dir> it is a fail-closed usage error (exit 2 — verify's whole contract
# is "exit 2 unless fully verified"), NOT the old exit-2 "not yet implemented"
# stub message. (Full verify behavior is covered by the Step-7 block below.)
@test "skeleton: verify subcommand requires <evidence_dir> (fail-closed, no longer a stub)" {
  run bash "$DISPATCH" verify
  [ "$status" -eq 2 ]
  [[ "$output" != *"not yet implemented"* ]]
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

@test "post-merge fix ('control_protocol envelope' finding, 10th DONE-review audit): c3-dispatch.json carries the full protocol-v2 envelope and passes aid-protocol-validate.sh" {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=valid run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ -f "$DJSON" ]

  # Envelope fields aid-evidence-verify.sh's V2_ARTIFACTS scan requires on
  # ANY schema_version:"aid-2.0" file, not just the ones with a dedicated
  # payload schema (this artifact was missing ALL of these before the fix,
  # not just control_protocol — the first-missing-field error only ever
  # named control_protocol because it's earliest in the required-fields loop).
  run jq -r '.control_protocol' "$DJSON"; [ "$output" = "aid-2.0" ]
  run jq -r '.identity.project_id' "$DJSON"; [ -n "$output" ] && [ "$output" != "null" ]
  run jq -r '.subject.subject_hash' "$DJSON"; [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]
  run jq -r '.revision.head_sha' "$DJSON"; [ "$output" = "$HEAD_SHA" ]
  run jq -r '.status' "$DJSON"; [ -n "$output" ] && [ "$output" != "null" ]
  run jq -r '.verdict.kind' "$DJSON"; [ -n "$output" ] && [ "$output" != "null" ]
  # provenance.dispatch_mode is the GENERAL protocol-v2 envelope concept
  # (how was this artifact's content produced — deterministic script here),
  # distinct from independence.*_level's C3-specific "cross_provider" — the
  # bug fixed here was conflating the two under the same field.
  run jq -r '.provenance.dispatch_mode' "$DJSON"; [ "$output" = "deterministic" ]
  run jq -r '.independence.achieved_independence_level' "$DJSON"; [ "$output" = "cross_provider" ]

  run bash "$VALIDATE" "$DJSON"
  [ "$status" -eq 0 ]
  run bash "$VALIDATE" "$DJSON" --check-fingerprint
  [ "$status" -eq 0 ]
  run bash "$VALIDATE" "$DJSON" --current-head "$HEAD_SHA"
  [ "$status" -eq 0 ]
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

# ═══════════════════════════════════════════════════════════════════════════
# Step 6 (backend) — Validation + deterministic normalization + fail-closed writer
#
# Additive only: never touches the Step-2/3/4/5 tests above. Exercises the
# TRUST-BOUNDARY functions in scripts/lib/aid-c3-dispatch.sh:
#   _validate_response  (the trusted jq gate — does NOT trust --output-schema)
#   _normalize          (deterministic fingerprint/occurrence_id computation)
#   _write_report       (the ONLY place status:pass|fail is written)
#   _write_unverifiable (fail-closed — every failure ⇒ status:unverifiable)
#   _process_response   (validate → normalize → write, wired into `dispatch`)
#
# Fixture modes (valid/invalid_json/hash_mismatch/head_mismatch/no_stream/
# timeout/rate_limited/missing_action_owner) drive the end-to-end paths; the
# _validate_response red-green battery and the review_unverifiable/invalid_output
# split are driven by SOURCING the bridge and calling the functions directly with
# crafted inputs (the source-guard makes `main` inert when sourced).
# ═══════════════════════════════════════════════════════════════════════════

# _vr <json-file> — source the bridge and run _validate_response on <json-file>.
# Sets $status: 0 = accepted, non-0 = rejected (fail-closed).
_vr() {
  run bash -c "source '$DISPATCH'; _validate_response '$1'"
}

# _base_valid_resp <out> — a schema-VALID C3 response (findings status, one high
# finding with a valid action_owner; blocking_findings consistent).
_base_valid_resp() {
  jq -nc --arg h "$_RH40" --arg bh "$_IMH" \
    '{reviewed_head:$h, codex_brief_hash:$bh, review_status:"findings",
      blocking_findings:true,
      findings:[{severity:"high",area:"scripts/x.sh:1",finding:"f",recommendation:"r",action_owner:"implementer"}]}' \
    > "$1"
}

# ─── AC1: valid high-severity finding → validator-passing audit-report.json ──

@test "step6/AC1: valid high finding normalizes to an audit-report.json that PASSES aid-protocol-validate.sh" {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=valid run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  local AR="$TEST_EVIDENCE_DIR/audit-report.json"
  [ -f "$AR" ]
  # the whole envelope passes the AUTHORITATIVE runtime validator
  run bash "$VALIDATE" "$AR"
  [ "$status" -eq 0 ]
  # blocking high finding ⇒ envelope status fail; artifact_type audit_report
  run jq -r '.status' "$AR"; [ "$output" = "fail" ]
  run jq -r '.artifact_type' "$AR"; [ "$output" = "audit_report" ]
  # the high finding carries a well-formed fingerprint, a non-empty c3-<epic>-<n>
  # occurrence_id, and a valid action_owner — all present
  run jq -e '[.findings[] | select(.severity=="high")
             | select((.fingerprint|test("^sha256:[0-9a-f]{64}$"))
                      and (.occurrence_id|test("^c3-E-test-[0-9]+$"))
                      and (.action_owner=="implementer"))] | length > 0' "$AR"
  [ "$status" -eq 0 ]
  # audit_report provenance is bridge-filled and binds to this run
  run jq -r '.audit_report.provider' "$AR";        [ "$output" = "codex" ]
  run jq -r '.audit_report.model' "$AR";           [ "$output" = "gpt-5.6-terra" ]
  run jq -r '.audit_report.reviewed_head' "$AR";   [ "$output" = "$HEAD_SHA" ]
  run jq -r '.audit_report.independence_level' "$AR"; [ "$output" = "cross_provider" ]
  run jq -r '.audit_report.input_manifest_hash' "$AR"
  [ "$output" = "$(jq -r '.audit_input_manifest.input_hash' "$MANIFEST")" ]
  run jq -r '.audit_report.codex_brief_hash' "$AR"
  [ "$output" = "$(jq -r '.audit_input_manifest.codex_brief_hash' "$MANIFEST")" ]
  # dual-emit markdown twin exists
  [ -f "$TEST_EVIDENCE_DIR/audit-report.md" ]
}

@test "step6/AC1: low/medium finding WITHOUT action_owner is carried absent (never defaulted) — B5 tuple parity" {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=valid run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  local AR="$TEST_EVIDENCE_DIR/audit-report.json"
  # the valid fixture's medium finding has NO action_owner — it must stay ABSENT
  run jq -e '[.findings[] | select(.severity=="medium") | select(has("action_owner")|not)] | length > 0' "$AR"
  [ "$status" -eq 0 ]
  # …and the report still validates (action_owner only required for crit/high)
  run bash "$VALIDATE" "$AR"
  [ "$status" -eq 0 ]
}

# ─── AC2: _validate_response rejects every safety-rule violation ─────────────

@test "step6/AC2: _validate_response ACCEPTS a schema-valid base response" {
  _base_valid_resp "$TEST_TMPDIR/r.json"
  _vr "$TEST_TMPDIR/r.json"
  [ "$status" -eq 0 ]
}

@test "step6/security: _validate_response REJECTS multi-document JSON (a malformed/malicious doc concatenated before a well-formed one)" {
  # CP2/CP3 finding (HIGH, fixed): `jq -e FILTER file` evaluates FILTER against
  # EVERY top-level JSON document in the file and -e's exit reflects only the
  # LAST one — a crafted 2-document file could validate solely against its
  # last (well-formed) document, silently ignoring an earlier malicious one.
  # Regression-lock the fix so a future refactor can't silently reintroduce it.
  _base_valid_resp "$TEST_TMPDIR/valid_tail.json"
  {
    printf '{"attacker":"controlled","not":"schema-shaped"}\n'
    cat "$TEST_TMPDIR/valid_tail.json"
  } > "$TEST_TMPDIR/multidoc.json"
  _vr "$TEST_TMPDIR/multidoc.json"
  [ "$status" -ne 0 ]
}

@test "step6/AC2: rejects ANY extra top-level key (process_id / provider / model / input_manifest_hash)" {
  local k
  for k in process_id provider model input_manifest_hash; do
    _base_valid_resp "$TEST_TMPDIR/r.json"
    jq --arg k "$k" '. + {($k): "leaked"}' "$TEST_TMPDIR/r.json" > "$TEST_TMPDIR/r2.json"
    _vr "$TEST_TMPDIR/r2.json"
    [ "$status" -ne 0 ]
  done
}

@test "step6/AC2: rejects a missing REQUIRED top-level key" {
  _base_valid_resp "$TEST_TMPDIR/r.json"
  jq 'del(.blocking_findings)' "$TEST_TMPDIR/r.json" > "$TEST_TMPDIR/r2.json"
  _vr "$TEST_TMPDIR/r2.json"
  [ "$status" -ne 0 ]
}

@test "step6/AC2: rejects a bad review_status enum" {
  _base_valid_resp "$TEST_TMPDIR/r.json"
  jq '.review_status="bogus"' "$TEST_TMPDIR/r.json" > "$TEST_TMPDIR/r2.json"
  _vr "$TEST_TMPDIR/r2.json"
  [ "$status" -ne 0 ]
}

@test "step6/AC2: unverifiable REQUIRES non-empty unverifiable_reasons; forbidden otherwise" {
  # unverifiable WITHOUT reasons → reject
  jq -nc --arg h "$_RH40" --arg bh "$_IMH" \
    '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"unverifiable",blocking_findings:false,findings:[]}' \
    > "$TEST_TMPDIR/u1.json"
  _vr "$TEST_TMPDIR/u1.json"; [ "$status" -ne 0 ]
  # unverifiable WITH empty reasons → reject
  jq -nc --arg h "$_RH40" --arg bh "$_IMH" \
    '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"unverifiable",blocking_findings:false,findings:[],unverifiable_reasons:[]}' \
    > "$TEST_TMPDIR/u1b.json"
  _vr "$TEST_TMPDIR/u1b.json"; [ "$status" -ne 0 ]
  # unverifiable WITH reasons → accept
  jq -nc --arg h "$_RH40" --arg bh "$_IMH" \
    '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"unverifiable",blocking_findings:false,findings:[],unverifiable_reasons:["no gate artifact"]}' \
    > "$TEST_TMPDIR/u2.json"
  _vr "$TEST_TMPDIR/u2.json"; [ "$status" -eq 0 ]
  # reasons on a NON-unverifiable status → reject
  _base_valid_resp "$TEST_TMPDIR/r.json"
  jq '. + {unverifiable_reasons:["x"]}' "$TEST_TMPDIR/r.json" > "$TEST_TMPDIR/u3.json"
  _vr "$TEST_TMPDIR/u3.json"; [ "$status" -ne 0 ]
}

@test "step6/AC2: rejects a bad severity enum" {
  _base_valid_resp "$TEST_TMPDIR/r.json"
  jq '.findings[0].severity="catastrophic"' "$TEST_TMPDIR/r.json" > "$TEST_TMPDIR/r2.json"
  _vr "$TEST_TMPDIR/r2.json"
  [ "$status" -ne 0 ]
}

@test "step6/AC2: rejects a bad action_owner enum at ANY severity (high AND medium)" {
  # high with a bad owner → reject
  _base_valid_resp "$TEST_TMPDIR/r.json"
  jq '.findings[0].action_owner="nobody"' "$TEST_TMPDIR/r.json" > "$TEST_TMPDIR/r2.json"
  _vr "$TEST_TMPDIR/r2.json"; [ "$status" -ne 0 ]
  # medium with a bad owner (owner present at a non-blocking severity) → reject
  jq -nc --arg h "$_RH40" --arg bh "$_IMH" \
    '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"findings",blocking_findings:false,
      findings:[{severity:"medium",area:"a",finding:"f",recommendation:"r",action_owner:"nobody"}]}' \
    > "$TEST_TMPDIR/m.json"
  _vr "$TEST_TMPDIR/m.json"; [ "$status" -ne 0 ]
}

@test "step6/AC2: rejects a high finding with NO action_owner (required for crit/high)" {
  jq -nc --arg h "$_RH40" --arg bh "$_IMH" \
    '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"findings",blocking_findings:true,
      findings:[{severity:"high",area:"a",finding:"f",recommendation:"r"}]}' \
    > "$TEST_TMPDIR/r.json"
  _vr "$TEST_TMPDIR/r.json"
  [ "$status" -ne 0 ]
}

@test "step6/AC2: rejects a malformed reviewed_head and a malformed codex_brief_hash" {
  _base_valid_resp "$TEST_TMPDIR/r.json"
  jq '.reviewed_head="XYZ-not-40-hex"' "$TEST_TMPDIR/r.json" > "$TEST_TMPDIR/h.json"
  _vr "$TEST_TMPDIR/h.json"; [ "$status" -ne 0 ]
  _base_valid_resp "$TEST_TMPDIR/r.json"
  jq '.codex_brief_hash="md5:whatever"' "$TEST_TMPDIR/r.json" > "$TEST_TMPDIR/b.json"
  _vr "$TEST_TMPDIR/b.json"; [ "$status" -ne 0 ]
}

@test "step6/AC2: a medium finding WITH a valid action_owner AND one WITHOUT are BOTH accepted" {
  # medium WITH a valid owner
  jq -nc --arg h "$_RH40" --arg bh "$_IMH" \
    '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"findings",blocking_findings:false,
      findings:[{severity:"medium",area:"a",finding:"f",recommendation:"r",action_owner:"reviewer"}]}' \
    > "$TEST_TMPDIR/mw.json"
  _vr "$TEST_TMPDIR/mw.json"; [ "$status" -eq 0 ]
  # medium WITHOUT an owner
  jq -nc --arg h "$_RH40" --arg bh "$_IMH" \
    '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"findings",blocking_findings:false,
      findings:[{severity:"medium",area:"a",finding:"f",recommendation:"r"}]}' \
    > "$TEST_TMPDIR/mo.json"
  _vr "$TEST_TMPDIR/mo.json"; [ "$status" -eq 0 ]
}

@test "step6/AC2: fail-closed on a non-object / unparseable last-message" {
  printf '[1,2,3]\n' > "$TEST_TMPDIR/arr.json"
  _vr "$TEST_TMPDIR/arr.json"; [ "$status" -ne 0 ]
  printf 'not json at all {\n' > "$TEST_TMPDIR/bad.json"
  _vr "$TEST_TMPDIR/bad.json"; [ "$status" -ne 0 ]
}

# ─── AC3: review_status ↔ findings binding (red-green) ───────────────────────

@test "step6/AC3: pass WITH non-empty findings → reject" {
  jq -nc --arg h "$_RH40" --arg bh "$_IMH" \
    '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"pass",blocking_findings:false,
      findings:[{severity:"low",area:"a",finding:"f",recommendation:"r"}]}' \
    > "$TEST_TMPDIR/p.json"
  _vr "$TEST_TMPDIR/p.json"; [ "$status" -ne 0 ]
}

@test "step6/AC3: findings-status WITH empty findings → reject" {
  jq -nc --arg h "$_RH40" --arg bh "$_IMH" \
    '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"findings",blocking_findings:false,findings:[]}' \
    > "$TEST_TMPDIR/f.json"
  _vr "$TEST_TMPDIR/f.json"; [ "$status" -ne 0 ]
}

@test "step6/AC3: blocking_findings NOT matching (∃ crit/high) → reject (both directions)" {
  # claims blocking:true but only a low finding exists → reject
  jq -nc --arg h "$_RH40" --arg bh "$_IMH" \
    '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"findings",blocking_findings:true,
      findings:[{severity:"low",area:"a",finding:"f",recommendation:"r"}]}' \
    > "$TEST_TMPDIR/b1.json"
  _vr "$TEST_TMPDIR/b1.json"; [ "$status" -ne 0 ]
  # claims blocking:false but a high finding exists → reject
  jq -nc --arg h "$_RH40" --arg bh "$_IMH" \
    '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"findings",blocking_findings:false,
      findings:[{severity:"high",area:"a",finding:"f",recommendation:"r",action_owner:"implementer"}]}' \
    > "$TEST_TMPDIR/b2.json"
  _vr "$TEST_TMPDIR/b2.json"; [ "$status" -ne 0 ]
}

@test "step6/AC3: a consistent pass (empty findings, blocking:false) → accept" {
  jq -nc --arg h "$_RH40" --arg bh "$_IMH" \
    '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"pass",blocking_findings:false,findings:[]}' \
    > "$TEST_TMPDIR/ok.json"
  _vr "$TEST_TMPDIR/ok.json"; [ "$status" -eq 0 ]
}

# ─── AC4: honest review_unverifiable vs BROKEN invalid_output (red-green) ────

@test "step6/AC4: schema-valid review_status:unverifiable → report unverifiable/review_unverifiable (NOT invalid_output)" {
  _seed_manifest high
  local bh; bh="$(jq -r '.audit_input_manifest.codex_brief_hash' "$MANIFEST")"
  mkdir -p "$TEST_EVIDENCE_DIR/c3"
  jq -nc --arg h "$HEAD_SHA" --arg bh "$bh" \
    '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"unverifiable",blocking_findings:false,
      findings:[],unverifiable_reasons:["no gate artifact at reviewed HEAD"]}' \
    > "$TEST_EVIDENCE_DIR/c3/codex-last-message.json"
  run bash -c "source '$DISPATCH'; _process_response '$TEST_EVIDENCE_DIR' '$MANIFEST' 0 true dispatched cross_provider 'sess-abcd' '$HEAD_SHA' || true"
  local AR="$TEST_EVIDENCE_DIR/audit-report.json"
  [ -f "$AR" ]
  run jq -r '.status' "$AR";                           [ "$output" = "unverifiable" ]
  run jq -r '.audit_report.outcome' "$AR";             [ "$output" = "review_unverifiable" ]
  run jq -r '.audit_report.unverifiable_reasons[0]' "$AR"; [ "$output" = "no gate artifact at reviewed HEAD" ]
  run jq -r '.audit_report.blocking_findings' "$AR";   [ "$output" = "false" ]
}

@test "step6/AC4: a BROKEN (schema-invalid) output → report unverifiable/invalid_output (red-green twin)" {
  _seed_manifest high
  local bh; bh="$(jq -r '.audit_input_manifest.codex_brief_hash' "$MANIFEST")"
  mkdir -p "$TEST_EVIDENCE_DIR/c3"
  # schema-invalid: bad review_status enum (a genuinely broken output)
  jq -nc --arg h "$HEAD_SHA" --arg bh "$bh" \
    '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"bogus",blocking_findings:false,findings:[]}' \
    > "$TEST_EVIDENCE_DIR/c3/codex-last-message.json"
  run bash -c "source '$DISPATCH'; _process_response '$TEST_EVIDENCE_DIR' '$MANIFEST' 0 true dispatched cross_provider 'sess-abcd' '$HEAD_SHA' || true"
  local AR="$TEST_EVIDENCE_DIR/audit-report.json"
  run jq -r '.status' "$AR";               [ "$output" = "unverifiable" ]
  run jq -r '.audit_report.outcome' "$AR"; [ "$output" = "invalid_output" ]
}

# ─── AC5: every failure mode → unverifiable with the matching outcome ────────

@test "step6/AC5: invalid_json → unverifiable/invalid_output (never pass/fail)" {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=invalid_json run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  local AR="$TEST_EVIDENCE_DIR/audit-report.json"
  run jq -r '.status' "$AR";               [ "$output" = "unverifiable" ]
  run jq -r '.audit_report.outcome' "$AR"; [ "$output" = "invalid_output" ]
}

@test "step6/AC5: hash_mismatch → unverifiable/hash_mismatch (Codex echoed the wrong brief)" {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=hash_mismatch run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  local AR="$TEST_EVIDENCE_DIR/audit-report.json"
  run jq -r '.status' "$AR";               [ "$output" = "unverifiable" ]
  run jq -r '.audit_report.outcome' "$AR"; [ "$output" = "hash_mismatch" ]
}

@test "step6/AC5: head_mismatch → unverifiable/head_mismatch (Codex reviewed the wrong commit)" {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=head_mismatch run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  local AR="$TEST_EVIDENCE_DIR/audit-report.json"
  run jq -r '.status' "$AR";               [ "$output" = "unverifiable" ]
  run jq -r '.audit_report.outcome' "$AR"; [ "$output" = "head_mismatch" ]
}

@test "step6/AC5: no_stream → unverifiable/invalid_output (events_valid false)" {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=no_stream run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  local AR="$TEST_EVIDENCE_DIR/audit-report.json"
  run jq -r '.status' "$AR";               [ "$output" = "unverifiable" ]
  run jq -r '.audit_report.outcome' "$AR"; [ "$output" = "invalid_output" ]
}

@test "step6/AC5: timeout → unverifiable/timeout" {
  _seed_manifest high
  _dispatch_seams
  AID_C3_TIMEOUT_SECONDS=1 FAKE_CODEX_MODE=timeout run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  local AR="$TEST_EVIDENCE_DIR/audit-report.json"
  run jq -r '.status' "$AR";               [ "$output" = "unverifiable" ]
  run jq -r '.audit_report.outcome' "$AR"; [ "$output" = "timeout" ]
}

@test "step6/AC5: rate_limited → unverifiable/rate_limited" {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=rate_limited run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  local AR="$TEST_EVIDENCE_DIR/audit-report.json"
  run jq -r '.status' "$AR";               [ "$output" = "unverifiable" ]
  run jq -r '.audit_report.outcome' "$AR"; [ "$output" = "rate_limited" ]
}

@test "step6/AC5: missing_action_owner (schema-invalid) → unverifiable/invalid_output (response-reject)" {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=missing_action_owner run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  local AR="$TEST_EVIDENCE_DIR/audit-report.json"
  run jq -r '.status' "$AR";               [ "$output" = "unverifiable" ]
  run jq -r '.audit_report.outcome' "$AR"; [ "$output" = "invalid_output" ]
}

@test "step6/AC5: NO failure mode ever produces status pass/fail" {
  _seed_manifest high
  _dispatch_seams
  local m AR="$TEST_EVIDENCE_DIR/audit-report.json"
  for m in invalid_json hash_mismatch head_mismatch no_stream missing_action_owner rate_limited; do
    rm -f "$AR"
    FAKE_CODEX_MODE="$m" run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
    run jq -r '.status' "$AR"
    [ "$output" = "unverifiable" ]
  done
  rm -f "$AR"
  AID_C3_TIMEOUT_SECONDS=1 FAKE_CODEX_MODE=timeout run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  run jq -r '.status' "$AR"; [ "$output" = "unverifiable" ]
}

# ─── AC6: normalized fingerprints/occurrence_ids are reproducible ───────────

@test "step6/AC6: re-running dispatch on the same raw response yields identical fingerprints/occurrence_ids" {
  _seed_manifest high
  _dispatch_seams
  local AR="$TEST_EVIDENCE_DIR/audit-report.json"
  FAKE_CODEX_MODE=valid run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  local fps1 occ1
  fps1="$(jq -c '[.findings[].fingerprint]' "$AR")"
  occ1="$(jq -c '[.findings[].occurrence_id]' "$AR")"
  FAKE_CODEX_MODE=valid run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  local fps2 occ2
  fps2="$(jq -c '[.findings[].fingerprint]' "$AR")"
  occ2="$(jq -c '[.findings[].occurrence_id]' "$AR")"
  [ "$fps1" = "$fps2" ]
  [ "$occ1" = "$occ2" ]
  # the finding-0 fingerprint equals the deterministic helper's own output
  local pid sev area finding rec occ fp_expected fp_actual
  pid="$(jq -r '.identity.project_id' "$MANIFEST")"
  sev="$(jq -r '.findings[0].severity' "$AR")"
  area="$(jq -r '.findings[0].area' "$AR")"
  finding="$(jq -r '.findings[0].finding' "$AR")"
  rec="$(jq -r '.findings[0].recommendation' "$AR")"
  occ="$(jq -r '.findings[0].occurrence_id' "$AR")"
  fp_expected="$(bash "$AID_PLUGIN_PATH/scripts/lib/aid-finding-fingerprint.sh" fingerprint_audit_report "$pid" audit_report "$occ" "$sev" "$area" "$finding" "$rec")"
  fp_actual="$(jq -r '.findings[0].fingerprint' "$AR")"
  [ "$fp_expected" = "$fp_actual" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# Step 7 (backend) — `verify`: provenance chain + report↔raw faithful-transform
#
# Additive only: never touches the Step-2/3/4/5/6 tests above (except the verify
# skeleton test, which was updated from stub→real, mirroring how Step 5 updated
# the dispatch skeleton test). Exercises cmd_verify in aid-c3-dispatch.sh: it
# re-checks the codex provenance chain (invoked/exit/outcome/events_valid/session/
# achieved cross_provider, stdout/raw sha pinning, template freshness, the legacy
# input_manifest_hash + recomputed codex_brief_hash chains) AND proves
# audit-report.json is a faithful, deterministic transform of Codex's RAW
# response (re-validate + reviewed_head/codex_brief_hash/blocking equality +
# order-insensitive tuple-set + index-bound fingerprint/occurrence_id recompute).
#
# Every scenario drives a GENUINE end-to-end valid dispatch with the fake-codex
# fixture (_drive_valid_dispatch), then verify's its own output — small, targeted
# tamper tests each isolate ONE broken invariant → exit 2 (fail-closed).
# _seed_manifest / _dispatch_seams are the Step-5 helpers defined above.
# ═══════════════════════════════════════════════════════════════════════════

# _drive_valid_dispatch — seed a manifest + spies and run a GENUINE valid dispatch
# end to end, leaving a real evidence dir (c3-dispatch.json + audit-report.json +
# codex-last-message.json + codex-events.jsonl + audit-input-manifest.json) that
# `verify` should accept unchanged.
_drive_valid_dispatch() {
  _seed_manifest high
  _dispatch_seams
  FAKE_CODEX_MODE=valid run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ -f "$TEST_EVIDENCE_DIR/audit-report.json" ]
}

# _jq_edit <file> <filter> — jq-rewrite <file> in place (stays valid JSON).
_jq_edit() {
  local file="$1" filter="$2"
  jq "$filter" "$file" > "$file.t" && mv "$file.t" "$file"
}

# ─── AC1: genuine verify passes; each targeted tamper → exit 2 ───────────────

@test "step7/AC1: verify (live) exits 0 on a genuine dispatched run" {
  _drive_valid_dispatch
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verified — codex session"* ]]
  [[ "$output" == *"$HEAD_SHA"* ]]
}

@test "step7/AC1: tampered RAW response (edited reviewed_head) → exit 2 (raw sha mismatch)" {
  _drive_valid_dispatch
  _jq_edit "$TEST_EVIDENCE_DIR/c3/codex-last-message.json" '.reviewed_head="0000000000000000000000000000000000000000"'
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC1: tampered EVENT stream (appended line) → exit 2 (stdout sha mismatch)" {
  _drive_valid_dispatch
  printf '{"type":"injected-noise"}\n' >> "$TEST_EVIDENCE_DIR/c3/codex-events.jsonl"
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC1: normalized reviewed_head tampered in the report → exit 2" {
  _drive_valid_dispatch
  _jq_edit "$TEST_EVIDENCE_DIR/audit-report.json" '.audit_report.reviewed_head="0000000000000000000000000000000000000000"'
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC1: normalized input_manifest_hash tampered → exit 2 (legacy chain broken)" {
  _drive_valid_dispatch
  _jq_edit "$TEST_EVIDENCE_DIR/audit-report.json" \
    '.audit_report.input_manifest_hash="sha256:1111111111111111111111111111111111111111111111111111111111111111"'
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC1: normalized codex_brief_hash tampered → exit 2" {
  _drive_valid_dispatch
  _jq_edit "$TEST_EVIDENCE_DIR/audit-report.json" \
    '.audit_report.codex_brief_hash="sha256:2222222222222222222222222222222222222222222222222222222222222222"'
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC1: blocking_findings flipped in the report → exit 2" {
  _drive_valid_dispatch
  _jq_edit "$TEST_EVIDENCE_DIR/audit-report.json" '.audit_report.blocking_findings=false'
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC1: a finding's text tampered in the report → exit 2 (tuple-set divergence)" {
  _drive_valid_dispatch
  _jq_edit "$TEST_EVIDENCE_DIR/audit-report.json" '.findings[0].finding="a totally different, fabricated finding"'
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC1: a finding fingerprint tampered → exit 2 (index-bound recompute)" {
  _drive_valid_dispatch
  # tuple-set excludes fingerprint, so only the index-bound recompute catches this.
  _jq_edit "$TEST_EVIDENCE_DIR/audit-report.json" \
    '.findings[0].fingerprint="sha256:3333333333333333333333333333333333333333333333333333333333333333"'
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC1: a finding occurrence_id tampered → exit 2" {
  _drive_valid_dispatch
  _jq_edit "$TEST_EVIDENCE_DIR/audit-report.json" '.findings[0].occurrence_id="c3-forged-999"'
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC1: process_id tampered → exit 2 (does not bind to the dispatch session)" {
  _drive_valid_dispatch
  _jq_edit "$TEST_EVIDENCE_DIR/audit-report.json" '.audit_report.process_id="not-the-real-session"'
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC1: rendered prompt edited → exit 2 (prompt freshness)" {
  _drive_valid_dispatch
  printf 'trailing tamper\n' >> "$TEST_EVIDENCE_DIR/c3/codex-prompt.txt"
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC1: a pruned brief file → exit 2 (codex_brief recompute fails)" {
  _drive_valid_dispatch
  rm -f "$TEST_EVIDENCE_DIR/c3/bundle-diff.patch"
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC1: an altered brief file → exit 2 (codex_brief sha diverges)" {
  _drive_valid_dispatch
  printf 'sneaky extra byte\n' >> "$TEST_EVIDENCE_DIR/c3/bundle-scope.txt"
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC1: dispatch.invoked flipped to false → exit 2 (provenance says codex did not run)" {
  _drive_valid_dispatch
  _jq_edit "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json" '.dispatch.invoked=false'
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC1: achieved_independence_level downgraded → exit 2" {
  _drive_valid_dispatch
  _jq_edit "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json" '.independence.achieved_independence_level="cross_model"'
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

# ─── AC2: --reference freshness vs live HEAD ────────────────────────────────

@test "step7/AC2: --reference verifies against manifest.head_sha even after HEAD moves; live fails" {
  _drive_valid_dispatch
  # A later commit moves HEAD WITHOUT touching the evidence brief files.
  git -C "$TEST_PROJECT_ROOT" commit -q --allow-empty -m "later commit moves HEAD"
  local NEW_HEAD; NEW_HEAD="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  [ "$NEW_HEAD" != "$HEAD_SHA" ]
  # live mode now sees a stale reviewed_head (audit reviewed the OLD head) → exit 2
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  # --reference checks freshness against the captured manifest.head_sha → exit 0
  run bash "$DISPATCH" verify --reference "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verified — codex session"* ]]
  [[ "$output" == *"$HEAD_SHA"* ]]
}

# ─── AC3: B5 action_owner parity + added/removed findings ───────────────────

@test "step7/AC3: a low/medium finding WITHOUT action_owner verifies (raw+report both omit it)" {
  _drive_valid_dispatch
  local AR="$TEST_EVIDENCE_DIR/audit-report.json"
  # the valid fixture's medium finding carries NO action_owner in the report…
  run jq -e '[.findings[]|select(.severity=="medium" and (has("action_owner")|not))]|length>0' "$AR"
  [ "$status" -eq 0 ]
  # …nor in the raw response — and verify accepts the identical-absence tuple.
  run jq -e '[.findings[]|select(.severity=="medium" and (has("action_owner")|not))]|length>0' \
    "$TEST_EVIDENCE_DIR/c3/codex-last-message.json"
  [ "$status" -eq 0 ]
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
}

@test "step7/AC3: adding action_owner to the report's medium finding (absent in raw) → exit 2" {
  _drive_valid_dispatch
  _jq_edit "$TEST_EVIDENCE_DIR/audit-report.json" \
    '(.findings[]|select(.severity=="medium")) |= (. + {action_owner:"reviewer"})'
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC3: removing a finding from the normalized report (no matching raw) → exit 2" {
  _drive_valid_dispatch
  _jq_edit "$TEST_EVIDENCE_DIR/audit-report.json" 'del(.findings[1])'
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC3: adding a fabricated finding to the report (no matching raw) → exit 2" {
  _drive_valid_dispatch
  _jq_edit "$TEST_EVIDENCE_DIR/audit-report.json" \
    '.findings += [{fingerprint:"sha256:4444444444444444444444444444444444444444444444444444444444444444",occurrence_id:"c3-E-test-9",severity:"low",area:"forged",finding:"forged",recommendation:"forged"}]'
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

# ─── AC4: absent c3-dispatch.json / manifest → exit 2 even if report claims pass ─

@test "step7/AC4: c3-dispatch.json absent → exit 2 even if the report claims status:pass" {
  _drive_valid_dispatch
  # force the report to claim a clean pass, then remove the dispatch provenance
  _jq_edit "$TEST_EVIDENCE_DIR/audit-report.json" '.status="pass"'
  rm -f "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json"
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  [[ "$output" == *"required artifact missing"* ]]
}

@test "step7/AC4: audit-input-manifest.json absent → exit 2" {
  _drive_valid_dispatch
  rm -f "$TEST_EVIDENCE_DIR/audit-input-manifest.json"
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "step7/AC4: codex-last-message.json absent → exit 2" {
  _drive_valid_dispatch
  rm -f "$TEST_EVIDENCE_DIR/c3/codex-last-message.json"
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

# ─── edge: raw response that fails the trusted re-validation gate ────────────

@test "step7/edge: a raw response that fails _validate_response (re-validated, not trusted) → exit 2" {
  # Craft a self-consistent evidence dir whose RAW response is schema-INVALID
  # (bad severity enum). stdout/raw sha are recomputed to pass step 3, so the
  # rejection is step 4's own re-validation, not an incidental hash mismatch.
  _drive_valid_dispatch
  local LM="$TEST_EVIDENCE_DIR/c3/codex-last-message.json"
  _jq_edit "$LM" '.findings[0].severity="catastrophic"'
  # re-point the recorded raw_response_sha256 at the mutated file (step 3 passes)…
  local newsha="sha256:$(sha256sum "$LM" | awk '{print $1}')"
  _jq_edit "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json" ".dispatch.raw_response_sha256=\"$newsha\""
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

# ─── usage: unknown flag ────────────────────────────────────────────────────

@test "step7/usage: unknown flag → exit 2 (fail-closed)" {
  run bash "$DISPATCH" verify --bogus "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

# ─── IMP-464 (D2): plan-diff.json as a profile-aware C3 evidence input ───────
#
# _write_rp <lenses_json_array> — review-profile.json arming (or not) the AC
# lens. _write_pd <base> <head> <verdict> — a plan-diff.json bound to a range.

_write_rp() {
  jq -n --argjson lenses "$1" '{review_profile: {required_lenses: $lenses}}' \
    > "$TEST_EVIDENCE_DIR/review-profile.json"
}

_write_pd() {
  local base="$1" head="$2" verdict="$3"
  jq -n --arg b "$base" --arg h "$head" --arg v "$verdict" \
    '{base_commit:$b, head_commit:$h, overall_verdict:$v, results:[], summary:{present_count:0,absent_count:0}}' \
    > "$TEST_EVIDENCE_DIR/plan-diff.json"
}

@test "IMP-464: a present plan-diff.json is added to allowlist, evidence_hashes and plan_diff_status" {
  # A required AC lens ALSO requires the pre-existing IMP-269 AC-bundle gate
  # to see ac_source=="plan" (AID_PLAN_AC_FILE set+readable) — both gates
  # share the same required_lenses[] input, and this test isolates plan-diff
  # specifically by satisfying the other one.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  local plan="$TEST_PROJECT_ROOT/.aid-o/plans/plan-ac.md"
  printf 'PLAN\n' > "$plan"
  export AID_PLAN_AC_FILE="$plan"
  _write_rp '["ac_to_test_identity"]'
  _write_pd "$BASE_SHA" "$HEAD_SHA" "pass"
  _build high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.allowlist[] | select(. == "plan-diff.json")' "$MANIFEST"
  [ "$output" = "plan-diff.json" ]
  run jq -r '[.audit_input_manifest.evidence_hashes[] | select(.path=="plan-diff.json")] | length' "$MANIFEST"
  [ "$output" = "1" ]
  run jq -r '.audit_input_manifest.plan_diff_status' "$MANIFEST"
  [ "$output" = "present" ]
}

@test "IMP-464: required AC lens + MISSING plan-diff.json refuses before dispatch" {
  _write_rp '["ac_to_test_identity"]'
  _build high
  [ "$status" -ne 0 ]
  [[ "$output" == *"AC lens required"* ]]
  [ ! -s "$MANIFEST" ]
}

@test "IMP-464: required AC lens + MALFORMED plan-diff.json refuses before dispatch" {
  _write_rp '["requirement_test_drift"]'
  printf 'not json at all\n' > "$TEST_EVIDENCE_DIR/plan-diff.json"
  _build high
  [ "$status" -ne 0 ]
  [[ "$output" == *"AC lens required"* ]]
}

@test "IMP-464: required AC lens + WRONG BASE plan-diff.json refuses before dispatch" {
  _write_rp '["ac_to_test_identity"]'
  _write_pd "0000000000000000000000000000000000000000" "$HEAD_SHA" "pass"
  _build high
  [ "$status" -ne 0 ]
  [[ "$output" == *"AC lens required"* ]]
}

@test "IMP-464: required AC lens + WRONG HEAD plan-diff.json refuses before dispatch" {
  _write_rp '["ac_to_test_identity"]'
  _write_pd "$BASE_SHA" "0000000000000000000000000000000000000000" "pass"
  _build high
  [ "$status" -ne 0 ]
  [[ "$output" == *"AC lens required"* ]]
}

@test "IMP-464: required AC lens + a 'skipped' plan-diff.json (bound, but no verdict) refuses before dispatch" {
  _write_rp '["ac_to_test_identity"]'
  _write_pd "$BASE_SHA" "$HEAD_SHA" "skipped"
  _build high
  [ "$status" -ne 0 ]
  [[ "$output" == *"AC lens required"* ]]
}

@test "IMP-464: NO required AC lens + missing plan-diff.json is an explicit classification, never a pass" {
  _write_rp '[]'
  _build high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.plan_diff_status' "$MANIFEST"
  [ "$output" = "not_required_absent" ]
  run jq -r '[.audit_input_manifest.allowlist[] | select(. == "plan-diff.json")] | length' "$MANIFEST"
  [ "$output" = "0" ]
}

@test "IMP-464: NO required AC lens + a 'skipped' plan-diff.json is classified, not silently upgraded" {
  _write_rp '[]'
  _write_pd "$BASE_SHA" "$HEAD_SHA" "skipped"
  _build high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.plan_diff_status' "$MANIFEST"
  [ "$output" = "not_required_skipped" ]
}

@test "IMP-464: review-profile.json present but UNPARSEABLE fails closed regardless of plan-diff.json" {
  printf 'not json\n' > "$TEST_EVIDENCE_DIR/review-profile.json"
  _write_pd "$BASE_SHA" "$HEAD_SHA" "pass"
  _build high
  [ "$status" -ne 0 ]
}

@test "IMP-464: a post-seal tamper of plan-diff.json is detectable — the sealed hash does not follow the file" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  local plan="$TEST_PROJECT_ROOT/.aid-o/plans/plan-ac.md"
  printf 'PLAN\n' > "$plan"
  export AID_PLAN_AC_FILE="$plan"
  _write_rp '["ac_to_test_identity"]'
  _write_pd "$BASE_SHA" "$HEAD_SHA" "fail"
  _build high
  [ "$status" -eq 0 ]
  local real_pd_sha
  real_pd_sha="$(jq -r '.audit_input_manifest.evidence_hashes[] | select(.path=="plan-diff.json") | .sha256' "$MANIFEST")"
  printf 'TAMPERED AFTER SEAL\n' > "$TEST_EVIDENCE_DIR/plan-diff.json"
  run jq -r '.audit_input_manifest.evidence_hashes[] | select(.path=="plan-diff.json") | .sha256' "$MANIFEST"
  [ "$output" = "$real_pd_sha" ]
  [ "$output" != "sha256:$(sha256sum "$TEST_EVIDENCE_DIR/plan-diff.json" | awk '{print $1}')" ]
}

# --- the head under audit is the candidate, not the directory's HEAD -------
# ACTA, 2026-08-31: Codex returned the CORRECT reviewed_head with two blocking
# findings; the third condition of the old head check asked
# `git -C "$evidence_dir" rev-parse HEAD`, which answers with the PRIMARY
# checkout's head because that is where evidence lives — never the candidate
# branch under audit. The report was written as unverifiable/head_mismatch with
# findings: [], the exact opposite of the audit.

@test "head check: only the sealed candidate head decides — the evidence dir's own HEAD does not" {
  # The guard lives in _process_response step 4. Assert on the SOURCE that the
  # cwd-derived head is gone from that comparison: a behavioural fixture would
  # need a worktree whose HEAD differs from the candidate, which this suite's
  # fake-codex harness cannot build.
  local lib="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  local block
  # Comments are stripped: the block explains the old condition by name, and a
  # test that cannot tell an explanation from an instruction would forbid
  # writing down why the code is the way it is.
  block="$(sed -n '/Step 4: provenance-binding hash checks/,/Step 5a/p' "$lib" | grep -v '^[[:space:]]*#')"
  [[ "$block" == *'"$raw_head" != "$head_sha"'* ]]
  [[ "$block" != *'rev-parse HEAD'* ]]
}
