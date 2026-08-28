#!/usr/bin/env bats
# aid-tier: t0
# test-dispatch-contract.bats — what an agent is handed and what it must hand
# back (P087 Step 1).
#
# Pure functions over a fixture plan.json and a temp tree. Nothing here
# dispatches an agent: what is proved is that a return is judged against the
# PACKET and the DISK — a stale version is refused, a promised artifact has to
# exist, and a file changed outside the allowed paths is named.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-dispatch-contract.sh"
  TEST_DIR="$(mktemp -d)"; cd "$TEST_DIR"
  cat > plan.json <<'JSON'
{"steps":[
  {"id":"step_1_backend","role":"backend","objective":"build the thing",
   "outputs":["Create: `src/thing.sh` — the thing","Modify: `README.md` — mention it","Test: `tests/test-thing.bats` (tier: t0) — cases"],
   "allowed_paths":["src/thing.sh","README.md","tests/test-thing.bats"],
   "acceptance_criteria":["AC1 — it exists"]},
  {"id":"step_2_docs","role":"docs-writer","objective":"think about it","outputs":["a decision"],"allowed_paths":[]}
],
 "dependencies":[{"before":"step_1_backend","after":"step_2_docs","reason":"x"}]}
JSON
  source "$LIB"
  aid_dispatch_contract_build plan.json 0 contract.json
  VERSION="$(jq -r .version contract.json)"
  mkdir -p src tests .aid-o; : > src/thing.sh; : > tests/test-thing.bats; : > README.md
}
teardown() { cd /; rm -rf "$TEST_DIR"; }

# _return <json-fragment> — a full return with the right version unless overridden
_return() {
  jq -n --arg v "$VERSION" "{contract_version: \$v, changed_files: [\"src/thing.sh\",\"tests/test-thing.bats\"], gates: [{name: \"lint\", result: \"pass\"}], step_status: \"done\"} + ($1)" > .aid-o/return.json
}

@test "contract: the packet carries version, artifacts, allowed paths, dependencies and its own evidence dir" {
  run jq -c '[(.version|length), .expected_artifacts, (.allowed_paths|length), .evidence_dir, .depends_on]' contract.json
  [ "$output" = '[12,["src/thing.sh","tests/test-thing.bats"],3,"steps/step_1_backend",[]]' ]
}

@test "contract: a step with no declared paths owes no contract (exit 3)" {
  run aid_dispatch_contract_build plan.json 1 c2.json
  [ "$status" -eq 3 ]
  [[ "$output" == *"no contract is owed"* ]]
}

@test "contract: a complete return against the right version is accepted" {
  _return '{}'
  run aid_dispatch_contract_validate contract.json .aid-o/return.json "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq -r .verdict <<< "$output")" = "accept" ]
}

@test "contract: AC1 — a return without the version is refused, and a stale version is refused naming both" {
  _return '{contract_version: null}'
  run aid_dispatch_contract_validate contract.json .aid-o/return.json "$TEST_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not confirm a contract version"* ]]
  _return '{contract_version: "deadbeef0000"}'
  run aid_dispatch_contract_validate contract.json .aid-o/return.json "$TEST_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"deadbeef0000"* && "$output" == *"$VERSION"* ]]
}

@test "contract: AC2 — a promised artifact missing on disk is refused with the list, whatever the return claims" {
  rm tests/test-thing.bats
  _return '{}'
  run aid_dispatch_contract_validate contract.json .aid-o/return.json "$TEST_DIR"
  [ "$status" -eq 1 ]
  [ "$(jq -c .missing_artifacts <<< "$output")" = '["tests/test-thing.bats"]' ]
}

@test "contract: AC3 — a file changed outside the allowed paths is named and the return refused" {
  _return '{changed_files: ["src/thing.sh","lib/other.sh"]}'
  run aid_dispatch_contract_validate contract.json .aid-o/return.json "$TEST_DIR"
  [ "$status" -eq 1 ]
  [ "$(jq -c .out_of_scope <<< "$output")" = '["lib/other.sh"]' ]
}

@test "contract: more artifacts than promised is recorded, not refused" {
  _return '{changed_files: ["src/thing.sh","tests/test-thing.bats","README.md"]}'
  run aid_dispatch_contract_validate contract.json .aid-o/return.json "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq -c .extra_artifacts <<< "$output")" = '["README.md"]' ]
}

@test "contract: evidence written into another step's directory is refused" {
  _return '{changed_files: [".aid-o/work/evidence/E/R/steps/step_9_qa/output.md"]}'
  run aid_dispatch_contract_validate contract.json .aid-o/return.json "$TEST_DIR"
  [ "$status" -eq 1 ]
  [ "$(jq -c .foreign_evidence <<< "$output")" = '[".aid-o/work/evidence/E/R/steps/step_9_qa/output.md"]' ]
  _return '{changed_files: [".aid-o/work/evidence/E/R/steps/step_1_backend/output.md"]}'
  run aid_dispatch_contract_validate contract.json .aid-o/return.json "$TEST_DIR"
  [ "$status" -eq 0 ]
  # a directory that merely STARTS with the step id is another step's
  _return '{changed_files: [".aid-o/work/evidence/E/R/steps/step_1_backend_extra/output.md"]}'
  run aid_dispatch_contract_validate contract.json .aid-o/return.json "$TEST_DIR"
  [ "$status" -eq 1 ]
  [ "$(jq -c .foreign_evidence <<< "$output")" = '[".aid-o/work/evidence/E/R/steps/step_1_backend_extra/output.md"]' ]
}

@test "contract: the return is read from the last aid-return block of the agent's output, and a missing block is not a return" {
  printf 'Done.\n```aid-return\n{"contract_version":"old"}\n```\nmore\n```aid-return\n{"contract_version":"%s","changed_files":[],"gates":[],"step_status":"done"}\n```\n' "$VERSION" > output.md
  run aid_dispatch_contract_extract output.md
  [ "$status" -eq 0 ]
  [ "$(jq -r .contract_version <<< "$output")" = "$VERSION" ]
  printf 'no block here\n' > output.md
  run aid_dispatch_contract_extract output.md
  [ "$status" -eq 1 ]
}

@test "contract: the prompt block carries the packet verbatim and asks for the version back" {
  run aid_dispatch_contract_prompt contract.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"version\": \"$VERSION\""* ]]
  [[ "$output" == *'```aid-return'* ]]
  [[ "$output" == *"\"contract_version\": \"$VERSION\""* ]]
}

@test "contract: a status or gate result outside the declared vocabulary is refused" {
  _return '{step_status: "banana"}'
  run aid_dispatch_contract_validate contract.json .aid-o/return.json "$TEST_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"done|blocked"* ]]
  _return '{gates: [{name: "lint", result: "green"}]}'
  run aid_dispatch_contract_validate contract.json .aid-o/return.json "$TEST_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pass|fail|skipped"* ]]
}

@test "contract: in a git tree, a file changed on disk but left out of the return is refused — the disk is the fact" {
  git init -q -b main . 2>/dev/null || git init -q .
  git config user.email t@t; git config user.name T
  git add -A; git commit -q -m seed
  printf 'edited\n' > README.md
  _return '{}'
  run aid_dispatch_contract_validate contract.json .aid-o/return.json "$TEST_DIR"
  [ "$status" -eq 1 ]
  [ "$(jq -c .undeclared_changes <<< "$output")" = '["README.md"]' ]
  # declared, it is an in-scope extra and the return is accepted
  _return '{changed_files: ["src/thing.sh","tests/test-thing.bats","README.md"]}'
  run aid_dispatch_contract_validate contract.json .aid-o/return.json "$TEST_DIR"
  [ "$status" -eq 0 ]
}

@test "contract: the commit refuses a return it would not accept" {
  git init -q -b main . 2>/dev/null || git init -q .
  git config user.email t@t; git config user.name T
  git add -A; git commit -q -m seed
  printf 'x\n' > src/thing.sh
  _return '{contract_version: "stale0000000"}'
  run aid_dispatch_contract_commit "$TEST_DIR" contract.json .aid-o/return.json "step 1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not accepted"* && "$output" == *"stale0000000"* ]]
  [ "$(git rev-list --count HEAD)" -eq 1 ]
}

@test "contract: a declared deletion is committed, not reported as nothing to commit" {
  git init -q -b main . 2>/dev/null || git init -q .
  git config user.email t@t; git config user.name T
  git add -A; git commit -q -m seed
  rm README.md
  _return '{changed_files: ["README.md"]}'
  run aid_dispatch_contract_commit "$TEST_DIR" contract.json .aid-o/return.json "step 1: drop readme"
  [ "$status" -eq 0 ]
  [ "$output" != "nothing to commit" ]
  [ "$(git show --name-only --format= HEAD)" = "README.md" ]
}

@test "contract: with an evidence root the packet carries the step's absolute evidence directory" {
  aid_dispatch_contract_build plan.json 0 c-abs.json "$TEST_DIR/.aid-o/work/evidence/E/R"
  [ "$(jq -r .evidence_dir c-abs.json)" = "$TEST_DIR/.aid-o/work/evidence/E/R/steps/step_1_backend" ]
}

# --- IMP-521: an expected artifact in ANOTHER repository -----------------
# WAN reported this as blocking on 2026-08-27: a step declaring one absolute and
# one relative artifact could not be accepted by ANY root, because the absolute
# path was glued behind the tree root (`<root>//opt/eco/docs/...`).

@test "IMP-521: an absolute expected artifact is checked where it is, not behind the root" {
  local other="$TEST_DIR/other-repo"
  mkdir -p "$other" "$TEST_DIR/docs"
  echo "in another repo" > "$other/mcp.md"
  echo "in this repo"    > "$TEST_DIR/docs/map-request.md"

  cat > "$TEST_DIR/c.json" <<JSON
{"step_id":"step_11","allowed_paths":["$other/mcp.md","docs/*"],
 "expected_artifacts":["$other/mcp.md","docs/map-request.md"],"version":"v1"}
JSON
  cat > "$TEST_DIR/r.json" <<JSON
{"step_id":"step_11","step_status":"done","version":"v1","contract_version":"v1",
 "changed_files":["$other/mcp.md","docs/map-request.md"],"gates":[],"summary":"s"}
JSON

  source "$LIB"
  run aid_dispatch_contract_validate "$TEST_DIR/c.json" "$TEST_DIR/r.json" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.verdict' <<< "$output")" = "accept" ]
  [ "$(jq -r '.missing_artifacts | length' <<< "$output")" -eq 0 ]
}

@test "IMP-521: an absolute artifact that really is absent is still reported missing" {
  mkdir -p "$TEST_DIR/docs"
  cat > "$TEST_DIR/c2.json" <<JSON
{"step_id":"step_11","allowed_paths":["/nonexistent/gone.md"],
 "expected_artifacts":["/nonexistent/gone.md"],"version":"v1"}
JSON
  cat > "$TEST_DIR/r2.json" <<JSON
{"step_id":"step_11","step_status":"done","version":"v1","contract_version":"v1",
 "changed_files":["/nonexistent/gone.md"],"gates":[],"summary":"s"}
JSON
  source "$LIB"
  run aid_dispatch_contract_validate "$TEST_DIR/c2.json" "$TEST_DIR/r2.json" "$TEST_DIR"
  [ "$(jq -r '.verdict' <<< "$output")" = "reject" ]
  [[ "$output" == *"/nonexistent/gone.md"* ]]
}
