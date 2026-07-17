#!/usr/bin/env bats
# test-c3-audit-prompt.bats — P065 E-065-4_7 Step 11 (docs-writer)
#
# Tests the C3 PROMPT PROTOCOL + RENDERER CONTRACT — the shipped, versioned
# prompt template `defaults/prompts/c3-audit-prompt-v1.md` rendered by
# `scripts/lib/aid-render-prompt.sh`, and the integration seam where the
# rendered prompt is handed to the (fake) Codex CLI by the real dispatch
# function `_run_codex_isolated`. Also exercises the trusted response gate
# `_validate_response` (built in an earlier EPIC) at its output-contract edges.
#
# This step does NOT author the template or the renderer — both already exist
# and are treated here as the source of truth. The tests run the REAL scripts
# against REAL committed fixtures (no source grep):
#   - defaults/prompts/c3-audit-prompt-v1.md   (the committed prompt template)
#   - scripts/lib/aid-render-prompt.sh         (the deterministic renderer)
#   - scripts/lib/aid-c3-dispatch.sh           (_run_codex_isolated + _validate_response)
#   - scripts/tests/fixtures/fake-codex/codex  (the deterministic Codex stub)
#   - scripts/tests/fixtures/c3-prompt/vars.json + codex-prompt.golden.txt
#
# Fixture conventions (setup_test_evidence_dir, AID_PLUGIN_PATH, fake-codex on
# PATH) mirror test-aid-c3-dispatch.bats.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH

  RENDER="$AID_PLUGIN_PATH/scripts/lib/aid-render-prompt.sh"
  PROMPT_TEMPLATE="$AID_PLUGIN_PATH/defaults/prompts/c3-audit-prompt-v1.md"
  DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  export RENDER PROMPT_TEMPLATE DISPATCH

  # Committed golden-render fixtures (the vars.json that produced the golden and
  # the golden itself — a re-render MUST reproduce the golden byte-for-byte).
  FIX_DIR="$AID_PLUGIN_PATH/scripts/tests/fixtures/c3-prompt"
  GOLDEN_VARS="$FIX_DIR/vars.json"
  GOLDEN_TXT="$FIX_DIR/codex-prompt.golden.txt"
  export FIX_DIR GOLDEN_VARS GOLDEN_TXT

  # v2 template fixtures (IMP-245 corrective fix) — same variable set as v1, a
  # new golden render of c3-audit-prompt-v2.md. v1's own fixtures above are left
  # completely untouched (v1 is a frozen historical artifact).
  PROMPT_TEMPLATE_V2="$AID_PLUGIN_PATH/defaults/prompts/c3-audit-prompt-v2.md"
  FIX_DIR_V2="$AID_PLUGIN_PATH/scripts/tests/fixtures/c3-prompt-v2"
  GOLDEN_VARS_V2="$FIX_DIR_V2/vars.json"
  GOLDEN_TXT_V2="$FIX_DIR_V2/codex-prompt-v2.golden.txt"
  export PROMPT_TEMPLATE_V2 FIX_DIR_V2 GOLDEN_VARS_V2 GOLDEN_TXT_V2

  # fake-codex CLI fixture (deterministic Codex stub) — used by the integration
  # test only; harmless elsewhere.
  FAKE_CODEX_DIR="$(cd "$BATS_TEST_DIRNAME/../fixtures/fake-codex" && pwd)"
  export FAKE_CODEX_DIR
  ORIGINAL_PATH="$PATH"
  export ORIGINAL_PATH

  # A well-formed base response for the _validate_response edge tests.
  RH40="1234567890abcdef1234567890abcdef12345678"
  BRIEF_HASH="sha256:$(printf 'brief' | sha256sum | cut -d' ' -f1)"
  export RH40 BRIEF_HASH
}

teardown() {
  PATH="${ORIGINAL_PATH:-$PATH}"
  export PATH
  unset FAKE_CODEX_MODE FAKE_CODEX_EXPECT_HEAD FAKE_CODEX_EXPECT_MANIFEST_HASH FAKE_CODEX_THREAD_ID
  teardown_test_evidence_dir
}

# _min_template <file> — a trivial single-variable template.
_min_template() {
  cat > "$1" <<'EOF'
---
template_id: min
template_version: v1
variables: [only]
---
Value: {{only}}
EOF
}

# ─── T1: golden render reproduces the committed golden byte-for-byte ─────────

@test "prompt/golden: rendering c3-audit-prompt-v1.md with the committed vars reproduces codex-prompt.golden.txt byte-for-byte" {
  [ -f "$GOLDEN_VARS" ]
  [ -f "$GOLDEN_TXT" ]
  run bash "$RENDER" --template "$PROMPT_TEMPLATE" --vars-json "$GOLDEN_VARS" --output "$TEST_TMPDIR/rendered.txt"
  [ "$status" -eq 0 ]
  # byte-exact match against the committed golden (regressions in the template
  # OR the renderer break this).
  cmp -s "$TEST_TMPDIR/rendered.txt" "$GOLDEN_TXT"
}

# ─── T2: key-set mismatch (missing OR unknown) → renderer exits non-zero ─────

@test "prompt/render: a MISSING declared variable makes aid-render-prompt.sh exit non-zero (no output)" {
  # Drop one required key from the committed vars set.
  jq 'del(.head_sha)' "$GOLDEN_VARS" > "$TEST_TMPDIR/vars-missing.json"
  run bash "$RENDER" --template "$PROMPT_TEMPLATE" --vars-json "$TEST_TMPDIR/vars-missing.json" --output "$TEST_TMPDIR/out.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"MISSING"* ]]
  [ ! -f "$TEST_TMPDIR/out.txt" ]
}

@test "prompt/render: an UNKNOWN (undeclared) variable makes aid-render-prompt.sh exit non-zero" {
  jq '. + {surprise_key: "x"}' "$GOLDEN_VARS" > "$TEST_TMPDIR/vars-unknown.json"
  run bash "$RENDER" --template "$PROMPT_TEMPLATE" --vars-json "$TEST_TMPDIR/vars-unknown.json" --output "$TEST_TMPDIR/out.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [ ! -f "$TEST_TMPDIR/out.txt" ]
}

# ─── T3: values with spaces/newlines/quotes render byte-for-byte (literal) ───

@test "prompt/render: a value containing spaces, newlines and quotes renders byte-for-byte (no eval/sed corruption)" {
  _min_template "$TEST_TMPDIR/min.md"
  # A value that would break any eval/sed-based interpolation.
  local val
  val=$'line1 "double" \'single\' $(echo PWNED) `id` ${HOME} & | ; > <  spaces\tTAB\nline2 end'
  jq -n --arg v "$val" '{only: $v}' > "$TEST_TMPDIR/v.json"
  run bash "$RENDER" --template "$TEST_TMPDIR/min.md" --vars-json "$TEST_TMPDIR/v.json" --output "$TEST_TMPDIR/out.txt"
  [ "$status" -eq 0 ]
  # The template body is exactly `Value: {{only}}\n`; expected = literal value spliced in.
  printf 'Value: %s\n' "$val" > "$TEST_TMPDIR/expected.txt"
  cmp -s "$TEST_TMPDIR/out.txt" "$TEST_TMPDIR/expected.txt"
}

# ─── T4: undeclared body {{placeholder}} → renderer fails ───────────────────

@test "prompt/render: a body {{placeholder}} not declared in frontmatter makes the renderer fail (no output)" {
  cat > "$TEST_TMPDIR/bad.md" <<'EOF'
---
template_id: bad
template_version: v1
variables: [only]
---
{{only}} plus {{ghost}}
EOF
  jq -n '{only: "x"}' > "$TEST_TMPDIR/v.json"
  run bash "$RENDER" --template "$TEST_TMPDIR/bad.md" --vars-json "$TEST_TMPDIR/v.json" --output "$TEST_TMPDIR/out.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"undeclared placeholder"* ]]
  [ ! -f "$TEST_TMPDIR/out.txt" ]
}

# ─── T5: rendered output has NO literal `{{` left ───────────────────────────

@test "prompt/render: the rendered c3 prompt contains no leftover {{ placeholder anywhere" {
  run bash "$RENDER" --template "$PROMPT_TEMPLATE" --vars-json "$GOLDEN_VARS" --output "$TEST_TMPDIR/rendered.txt"
  [ "$status" -eq 0 ]
  ! grep -qF '{{' "$TEST_TMPDIR/rendered.txt"
}

# ─── T6: the fake-Codex fixture receives EXACTLY the rendered prompt ─────────
# Integration seam: the real dispatch fn `_run_codex_isolated` reads the rendered
# prompt file and passes it as codex's final positional. We prepend a `codex`
# spy that records that positional then delegates to fake-codex — proving the
# rendered prompt reaches the executor intact (not just that rendering works).

@test "prompt/integration: _run_codex_isolated hands the fake-Codex fixture exactly the rendered codex-prompt.txt" {
  # Render the real prompt to codex-prompt.txt.
  local prompt_file="$TEST_TMPDIR/codex-prompt.txt"
  run bash "$RENDER" --template "$PROMPT_TEMPLATE" --vars-json "$GOLDEN_VARS" --output "$prompt_file"
  [ "$status" -eq 0 ]

  # A `codex` spy that captures its LAST positional (the prompt) then execs the
  # real fake-codex fixture with the identical argv.
  local spy_dir="$TEST_TMPDIR/spy"
  mkdir -p "$spy_dir"
  local capture="$TEST_TMPDIR/prompt-capture.txt"
  cat > "$spy_dir/codex" <<EOF
#!/usr/bin/env bash
printf '%s' "\${!#}" > "$capture"
exec "$FAKE_CODEX_DIR/codex" "\$@"
EOF
  chmod +x "$spy_dir/codex"

  # Drive the REAL bridge function through the spy (valid fake-codex mode).
  export FAKE_CODEX_MODE=valid
  export FAKE_CODEX_EXPECT_HEAD="$RH40"
  export FAKE_CODEX_EXPECT_MANIFEST_HASH="$BRIEF_HASH"
  PATH="$spy_dir:$PATH" run bash -c "
    source '$DISPATCH'
    _run_codex_isolated '$TEST_PROJECT_ROOT' '$prompt_file' \
      '$TEST_TMPDIR/events.jsonl' '$TEST_TMPDIR/stderr.txt' '$TEST_TMPDIR/last.txt'
  "
  [ "$status" -eq 0 ]
  [ -f "$capture" ]
  # The prompt the fixture received == the rendered prompt file content.
  # (Both sides pass through the bridge's `\$(cat)` normalization identically.)
  [ "$(cat "$capture")" = "$(cat "$prompt_file")" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# _validate_response — trusted output-contract gate (built in an earlier EPIC;
# tested here, not built). Green control + the two required red edges.
# ═══════════════════════════════════════════════════════════════════════════

# _vr <json-file> — source the bridge and run _validate_response on <json-file>.
_vr() {
  run bash -c "source '$DISPATCH'; _validate_response '$1'"
}

@test "prompt/validate (green control): a well-formed pass response PASSES _validate_response" {
  jq -n --arg rh "$RH40" --arg bh "$BRIEF_HASH" \
    '{reviewed_head:$rh, codex_brief_hash:$bh, review_status:"pass", blocking_findings:false, findings:[]}' \
    > "$TEST_TMPDIR/ok.json"
  _vr "$TEST_TMPDIR/ok.json"
  [ "$status" -eq 0 ]
}

@test "prompt/validate: a response with an OUT-OF-SCHEMA top-level key does NOT pass _validate_response" {
  # Same well-formed pass body, plus a forbidden extra top-level key.
  jq -n --arg rh "$RH40" --arg bh "$BRIEF_HASH" \
    '{reviewed_head:$rh, codex_brief_hash:$bh, review_status:"pass", blocking_findings:false, findings:[], provider:"openai"}' \
    > "$TEST_TMPDIR/extra.json"
  _vr "$TEST_TMPDIR/extra.json"
  [ "$status" -ne 0 ]
}

@test "prompt/validate: review_status=unverifiable with NO unverifiable_reasons is rejected by _validate_response" {
  jq -n --arg rh "$RH40" --arg bh "$BRIEF_HASH" \
    '{reviewed_head:$rh, codex_brief_hash:$bh, review_status:"unverifiable", blocking_findings:false, findings:[]}' \
    > "$TEST_TMPDIR/unv.json"
  _vr "$TEST_TMPDIR/unv.json"
  [ "$status" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# v2 template (IMP-245 corrective fix) — c3-audit-prompt-v2.md. v1's tests above
# are untouched: v1 is a frozen historical artifact whose bytes already bind to
# every previously-issued report's `template_sha256`. v2 is the ACTIVE template
# `aid-c3-dispatch.sh` now points at (PROMPT_TEMPLATE). These tests mirror T1/
# T2/T5/T6 above against v2's fixtures, plus a regression proof (V7) that the
# always-allowed-reads vs allowed_recheck_commands contradiction is fixed.
# ═══════════════════════════════════════════════════════════════════════════

# ─── V1: golden render reproduces the committed v2 golden byte-for-byte ──────

@test "prompt/golden v2: rendering c3-audit-prompt-v2.md with the committed vars reproduces codex-prompt-v2.golden.txt byte-for-byte" {
  [ -f "$GOLDEN_VARS_V2" ]
  [ -f "$GOLDEN_TXT_V2" ]
  run bash "$RENDER" --template "$PROMPT_TEMPLATE_V2" --vars-json "$GOLDEN_VARS_V2" --output "$TEST_TMPDIR/rendered-v2.txt"
  [ "$status" -eq 0 ]
  cmp -s "$TEST_TMPDIR/rendered-v2.txt" "$GOLDEN_TXT_V2"
}

# ─── V2: key-set mismatch (missing OR unknown) → renderer exits non-zero ─────

@test "prompt/render v2: a MISSING declared variable makes aid-render-prompt.sh exit non-zero (no output)" {
  jq 'del(.head_sha)' "$GOLDEN_VARS_V2" > "$TEST_TMPDIR/vars-missing-v2.json"
  run bash "$RENDER" --template "$PROMPT_TEMPLATE_V2" --vars-json "$TEST_TMPDIR/vars-missing-v2.json" --output "$TEST_TMPDIR/out-v2.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"MISSING"* ]]
  [ ! -f "$TEST_TMPDIR/out-v2.txt" ]
}

@test "prompt/render v2: an UNKNOWN (undeclared) variable makes aid-render-prompt.sh exit non-zero" {
  jq '. + {surprise_key: "x"}' "$GOLDEN_VARS_V2" > "$TEST_TMPDIR/vars-unknown-v2.json"
  run bash "$RENDER" --template "$PROMPT_TEMPLATE_V2" --vars-json "$TEST_TMPDIR/vars-unknown-v2.json" --output "$TEST_TMPDIR/out-v2.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [ ! -f "$TEST_TMPDIR/out-v2.txt" ]
}

# ─── V5: rendered v2 output has NO literal `{{` left ────────────────────────

@test "prompt/render v2: the rendered c3 prompt contains no leftover {{ placeholder anywhere" {
  run bash "$RENDER" --template "$PROMPT_TEMPLATE_V2" --vars-json "$GOLDEN_VARS_V2" --output "$TEST_TMPDIR/rendered-v2.txt"
  [ "$status" -eq 0 ]
  ! grep -qF '{{' "$TEST_TMPDIR/rendered-v2.txt"
}

# ─── V6: the fake-Codex fixture receives EXACTLY the rendered v2 prompt ──────

@test "prompt/integration v2: _run_codex_isolated hands the fake-Codex fixture exactly the rendered v2 codex-prompt.txt" {
  local prompt_file="$TEST_TMPDIR/codex-prompt-v2.txt"
  run bash "$RENDER" --template "$PROMPT_TEMPLATE_V2" --vars-json "$GOLDEN_VARS_V2" --output "$prompt_file"
  [ "$status" -eq 0 ]

  local spy_dir="$TEST_TMPDIR/spy-v2"
  mkdir -p "$spy_dir"
  local capture="$TEST_TMPDIR/prompt-capture-v2.txt"
  cat > "$spy_dir/codex" <<EOF
#!/usr/bin/env bash
printf '%s' "\${!#}" > "$capture"
exec "$FAKE_CODEX_DIR/codex" "\$@"
EOF
  chmod +x "$spy_dir/codex"

  export FAKE_CODEX_MODE=valid
  export FAKE_CODEX_EXPECT_HEAD="$RH40"
  export FAKE_CODEX_EXPECT_MANIFEST_HASH="$BRIEF_HASH"
  PATH="$spy_dir:$PATH" run bash -c "
    source '$DISPATCH'
    _run_codex_isolated '$TEST_PROJECT_ROOT' '$prompt_file' \
      '$TEST_TMPDIR/events-v2.jsonl' '$TEST_TMPDIR/stderr-v2.txt' '$TEST_TMPDIR/last-v2.txt'
  "
  [ "$status" -eq 0 ]
  [ -f "$capture" ]
  [ "$(cat "$capture")" = "$(cat "$prompt_file")" ]
}

# ─── V7: regression proof — always-allowed reads vs allowed_recheck_commands ─
# The actual IMP-245 fix: the v2 golden render must contain language that
# distinguishes the always-permitted baseline read-only toolkit from the
# separate, narrower `allowed_recheck_commands` re-execution permission — this
# is what a v1 render never had, and what caused two real dogfood runs to
# return `unverifiable` for lack of it.

@test "prompt/regression v2 (IMP-245): the rendered v2 prompt distinguishes always-allowed reads from allowed_recheck_commands" {
  run bash "$RENDER" --template "$PROMPT_TEMPLATE_V2" --vars-json "$GOLDEN_VARS_V2" --output "$TEST_TMPDIR/rendered-v2.txt"
  [ "$status" -eq 0 ]
  grep -qF "Always-allowed basic read-only operations" "$TEST_TMPDIR/rendered-v2.txt"
  grep -qi "NEVER gated by" "$TEST_TMPDIR/rendered-v2.txt"
  grep -qF "STRONGER" "$TEST_TMPDIR/rendered-v2.txt"
}
