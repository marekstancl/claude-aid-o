#!/usr/bin/env bats
# test-pm-brief.bats — aid-pm-brief.sh (deterministic PM decision brief, E-059-2_2 Step 6).
#
# The decision fixtures are built at runtime with `jq` from the tracked protocol-v2 fixture
# (scripts/tests/fixtures/protocol-v2/release_decision/valid.json) into a fresh `mktemp -d`
# working dir. NO fixture file lives under a `.aid-o/` or `evidence/` path segment (both are
# gitignored), so there is no gitignore-trap to guard against here.
#
# The headline proof is the ISOLATED-DIR test (a): a dir containing ONLY release-decision.json
# still yields a complete brief. That is a structural cycle-break proof — stronger than a
# grep-negative — because the brief physically has no sibling file to read.

setup() {
  export TZ=UTC
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"   # .../plugins/aid-orchestrator
  export AID_PLUGIN_PATH="$PLUGIN_ROOT"
  SCRIPTS="$PLUGIN_ROOT/scripts"
  BRIEF="$SCRIPTS/aid-pm-brief.sh"
  VALIDATE="$SCRIPTS/aid-protocol-validate.sh"
  FIXTURE="$SCRIPTS/tests/fixtures/protocol-v2/release_decision/valid.json"

  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  DIR="$TEST_TMPDIR/evidence"
  mkdir -p "$DIR"
  DEC="$DIR/release-decision.json"
  BJ="$DIR/pm-decision-brief.json"
  BM="$DIR/pm-summary.md"
}

teardown() {
  cd /
  if [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]]; then
    chmod -R u+rwx "$TEST_TMPDIR" 2>/dev/null || true   # restore any chmod-555 seam dir
    rm -rf "$TEST_TMPDIR"
  fi
}

# ─── helpers ─────────────────────────────────────────────────────────────────

# Seed DEC from the tracked fixture with pm_brief_status reset to "pending" (as the Step-4
# aggregator emits it) so a patch-back to "generated" is observable, not a no-op.
_seed_valid() { jq '.release_decision.pm_brief_status="pending"' "$FIXTURE" > "$DEC"; }

# Seed DEC with a jq mutation applied on top of the pending reset.
_seed() { jq '.release_decision.pm_brief_status="pending" | '"$1" "$FIXTURE" > "$DEC"; }

_run() { run env AID_PLUGIN_PATH="$AID_PLUGIN_PATH" bash "$BRIEF" "$@"; }
_b() { jq -r "$1" "$BJ"; }
_d() { jq -r "$1" "$DEC"; }

# ─── (a) isolated-dir: structural cycle-break ────────────────────────────────

@test "(a) isolated-dir: a dir with ONLY release-decision.json → brief completes fully" {
  _seed_valid
  [ "$(ls -1 "$DIR" | wc -l)" -eq 1 ]                 # nothing but release-decision.json
  _run "$DIR"
  [ "$status" -eq 0 ]
  [ -f "$BJ" ]
  [ -f "$BM" ]
  [ "$(_b '.pm_decision_brief.communication_status')" == "complete" ]
  [ "$(_b '.artifact_type')" == "pm_decision_brief" ]
  [ "$(_b '.verdict.kind')" == "none" ]               # decision authority is the PM's, never the brief's
  [ "$(_d '.release_decision.pm_brief_status')" == "generated" ]
  # the ONLY files in the dir are the input + the two outputs — no sibling was read or created
  [ "$(ls -1 "$DIR" | wc -l)" -eq 3 ]
}

@test "(a) isolated-dir brief validates against the protocol v2 schema (exit 0)" {
  _seed_valid
  _run "$DIR"
  [ "$status" -eq 0 ]
  run bash "$VALIDATE" "$BJ"
  [ "$status" -eq 0 ]
}

# ─── (b) no-optimism: --validate catches a tampered (over-optimistic) brief ───

@test "(b) no-optimism: tampered brief (blocker removed) → --validate FAIL (exit!=0)" {
  _seed '.release_decision.release_ready=false
         | .release_decision.merge_mode="blocked"
         | .release_decision.blockers=[{"input_id":"delivery_gate","severity":"blocking","reason":"gates red"}]'
  _run "$DIR"
  [ "$status" -eq 0 ]                                  # a not-ready decision STILL yields a brief
  [ "$(_b '.pm_decision_brief.blockers | length')" -eq 1 ]
  # positive control: --validate PASSES on the faithful brief
  _run "$DIR" --validate
  [ "$status" -eq 0 ]
  # tamper: drop the blocker to paint a rosier picture than the decision
  jq '.pm_decision_brief.blockers = []' "$BJ" > "$BJ.tmp" && mv "$BJ.tmp" "$BJ"
  _run "$DIR" --validate
  [ "$status" -ne 0 ]                                  # optimism caught
  [ "$status" -eq 5 ]
}

@test "(b) no-optimism: tampered release_ready true->... echo mismatch → --validate FAIL" {
  _seed '.release_decision.release_ready=false | .release_decision.merge_mode="blocked"'
  _run "$DIR"
  [ "$status" -eq 0 ]
  jq '.pm_decision_brief.release_ready = true' "$BJ" > "$BJ.tmp" && mv "$BJ.tmp" "$BJ"
  _run "$DIR" --validate
  [ "$status" -ne 0 ]
}

# ─── (c) missing decision → incomplete + exit!=0 ─────────────────────────────

@test "(c) missing decision → communication_status incomplete + exit!=0" {
  # empty dir — no release-decision.json at all
  _run "$DIR"
  [ "$status" -ne 0 ]
  [ "$status" -eq 7 ]
  [ -f "$BJ" ]                                         # an incomplete brief is still emitted for the PM
  [ "$(_b '.pm_decision_brief.communication_status')" == "incomplete" ]
}

@test "(c) unparseable decision (garbage) → incomplete + exit!=0" {
  printf 'not json at all\n' > "$DEC"
  _run "$DIR"
  [ "$status" -ne 0 ]
  [ "$(_b '.pm_decision_brief.communication_status')" == "incomplete" ]
}

# ─── (d) delivered_summary_ref ECHO (path + null); no sibling read ────────────

@test "(d) delivered_summary_ref ECHO: a path is echoed VERBATIM (not resolved) — no sibling read" {
  # point at a path that deliberately does NOT exist on disk; the brief must echo it as-is
  _seed '.release_decision.delivered_summary_ref="evidence/does/not/exist/on/disk.md"'
  _run "$DIR"
  [ "$status" -eq 0 ]
  [ "$(_b '.pm_decision_brief.delivered_summary_ref')" == "evidence/does/not/exist/on/disk.md" ]
  # prove it was echoed, not opened: no such file was created and none is required
  [ ! -e "$DIR/evidence/does/not/exist/on/disk.md" ]
}

@test "(d) delivered_summary_ref ECHO: null in decision → echoed as null; brief still generates" {
  _seed '.release_decision.delivered_summary_ref=null'
  _run "$DIR"
  [ "$status" -eq 0 ]                                  # null never blocks
  [ "$(_b '.pm_decision_brief.delivered_summary_ref')" == "null" ]
  [ "$(_b '.pm_decision_brief.communication_status')" == "complete" ]
}

# ─── (e) patch-back: generated / failed / incomplete ─────────────────────────

@test "(e) patch-back generated: successful run → pm_brief_status generated in release-decision.json" {
  _seed_valid
  [ "$(_d '.release_decision.pm_brief_status')" == "pending" ]   # starts pending
  _run "$DIR"
  [ "$status" -eq 0 ]
  [ "$(_d '.release_decision.pm_brief_status')" == "generated" ]
}

@test "(e) patch-back failed: --out-dir seam (non-writable brief dir, writable decision) → failed" {
  _seed_valid
  local RO="$TEST_TMPDIR/ro-out"
  mkdir -p "$RO"
  chmod 555 "$RO"                                      # brief write fails; DEC dir stays writable
  _run "$DIR" --out-dir "$RO"
  [ "$status" -ne 0 ]
  [ "$status" -eq 6 ]
  [ ! -f "$RO/pm-decision-brief.json" ]               # brief was NOT written
  [ "$(_d '.release_decision.pm_brief_status')" == "failed" ]   # patch-back hit the writable DEC
  chmod 755 "$RO"
}

@test "(e) patch-back incomplete: decision present but malformed (missing merge_mode) → incomplete" {
  _seed 'del(.release_decision.merge_mode)'
  _run "$DIR"
  [ "$status" -ne 0 ]
  [ "$status" -eq 7 ]
  [ "$(_b '.pm_decision_brief.communication_status')" == "incomplete" ]
  [ "$(_d '.release_decision.pm_brief_status')" == "incomplete" ]
}

@test "(e) patch-back is idempotent: a second run leaves pm_brief_status generated" {
  _seed_valid
  _run "$DIR"
  [ "$status" -eq 0 ]
  [ "$(_d '.release_decision.pm_brief_status')" == "generated" ]
  _run "$DIR"                                          # run again on the already-patched decision
  [ "$status" -eq 0 ]
  [ "$(_d '.release_decision.pm_brief_status')" == "generated" ]
}

@test "(e) named limit: wholesale read-only evidence dir → pm_brief_status stays pending (not failed)" {
  _seed_valid
  chmod 555 "$DIR"                                     # the WHOLE evidence dir is read-only
  _run "$DIR"
  [ "$status" -ne 0 ]                                  # brief write + patch-back both blocked
  chmod 755 "$DIR"
  [ "$(_d '.release_decision.pm_brief_status')" == "pending" ]   # patch-back could not run
}

# ─── (f) auto-merge: brief STILL generates (no auto-only shortcut) ────────────

@test "(f) auto-merge: merge_mode auto → brief STILL generates (no shortcut that skips it)" {
  _seed '.release_decision.merge_mode="auto"'
  _run "$DIR"
  [ "$status" -eq 0 ]
  [ "$(_b '.pm_decision_brief.merge_mode')" == "auto" ]
  [ "$(_b '.pm_decision_brief.communication_status')" == "complete" ]
  [ "$(_d '.release_decision.pm_brief_status')" == "generated" ]
}

@test "(f) auto-merge is never silent: pm-summary.md legibly shows the review signals" {
  _seed '.release_decision.merge_mode="auto"'
  _run "$DIR"
  [ "$status" -eq 0 ]
  grep -qi "auto-merge"           "$BM"
  grep -qi "Reporter"             "$BM"
  grep -qi "Simplifier"           "$BM"
  grep -qi "Evidence verification" "$BM"
}

# ─── mechanical honesty: every status legible in pm-summary.md (any merge mode) ──

@test "pm-summary.md legibly shows evidence/Reporter/Simplifier/blocker/waiver status" {
  _seed_valid
  _run "$DIR"
  [ "$status" -eq 0 ]
  grep -q  "Release ready"         "$BM"
  grep -q  "Merge mode"            "$BM"
  grep -qi "Evidence verification" "$BM"
  grep -qi "Reporter"              "$BM"
  grep -qi "Simplifier"            "$BM"
  grep -qi "Blockers"              "$BM"
  grep -qi "Waivers applied"       "$BM"
  grep -qi "Summary for PM"        "$BM"
}

# ─── determinism: only created_at varies between two runs ─────────────────────

@test "determinism: two runs → brief payloads identical after del(.created_at)" {
  _seed_valid
  _run "$DIR"
  [ "$status" -eq 0 ]
  local a; a="$(jq -S 'del(.created_at)' "$BJ")"
  _run "$DIR"
  [ "$status" -eq 0 ]
  local b; b="$(jq -S 'del(.created_at)' "$BJ")"
  [ "$a" == "$b" ]
}

# ─── usage guard ─────────────────────────────────────────────────────────────

@test "usage: no evidence_dir argument → exit 2" {
  _run
  [ "$status" -eq 2 ]
}

# ─── REGRESSION: empty/whitespace-only decision (jq 1.6 edge case) ──────────

@test "REGRESSION: release-decision.json EMPTY (0-byte) → communication_status incomplete + exit!=0" {
  : > "$DEC"    # truncate to 0 bytes
  _run "$DIR"
  [ "$status" -ne 0 ]
  [ "$status" -eq 7 ]
  [ -f "$BJ" ]
  [ "$(_b '.pm_decision_brief.communication_status')" == "incomplete" ]
}

@test "REGRESSION: release-decision.json WHITESPACE-ONLY → communication_status incomplete + exit!=0" {
  printf '\n' > "$DEC"
  _run "$DIR"
  [ "$status" -ne 0 ]
  [ "$status" -eq 7 ]
  [ -f "$BJ" ]
  [ "$(_b '.pm_decision_brief.communication_status')" == "incomplete" ]
}

# ─── IMP-264: revision freshness is computed at READ TIME, not echoed from the frozen snapshot ──
#
@test "IMP-264: recorded head_sha == current HEAD → brief revision is fresh (true/current)" {
  local GDIR="$TEST_TMPDIR/gitrepo"
  rm -rf "$GDIR"; mkdir -p "$GDIR/ev"
  git -C "$GDIR" init -q; git -C "$GDIR" config user.email t@t; git -C "$GDIR" config user.name t
  git -C "$GDIR" commit -q --allow-empty -m base
  local head; head="$(git -C "$GDIR" rev-parse HEAD)"
  jq --arg h "$head" '.release_decision.pm_brief_status="pending" | .revision.head_sha=$h | .revision.head_is_current=true | .revision.freshness="current"' \
     "$FIXTURE" > "$GDIR/ev/release-decision.json"
  run env AID_PLUGIN_PATH="$AID_PLUGIN_PATH" bash "$BRIEF" "$GDIR/ev"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.revision.head_is_current' "$GDIR/ev/pm-decision-brief.json")" == "true" ]
  [ "$(jq -r '.revision.freshness' "$GDIR/ev/pm-decision-brief.json")" == "current" ]
}

@test "IMP-264: post-generation commit (recorded != current HEAD) → brief revision is stale, head_sha preserved" {
  local GDIR="$TEST_TMPDIR/gitrepo"
  rm -rf "$GDIR"; mkdir -p "$GDIR/ev"
  git -C "$GDIR" init -q; git -C "$GDIR" config user.email t@t; git -C "$GDIR" config user.name t
  git -C "$GDIR" commit -q --allow-empty -m A
  local a; a="$(git -C "$GDIR" rev-parse HEAD)"
  # decision generated at A, claiming currentness (frozen true/current)
  jq --arg h "$a" '.release_decision.pm_brief_status="pending" | .revision.head_sha=$h | .revision.head_is_current=true | .revision.freshness="current"' \
     "$FIXTURE" > "$GDIR/ev/release-decision.json"
  git -C "$GDIR" commit -q --allow-empty -m B    # post-generation commit lands → HEAD moves off A
  run env AID_PLUGIN_PATH="$AID_PLUGIN_PATH" bash "$BRIEF" "$GDIR/ev"
  [ "$status" -eq 0 ]
  # frozen true/current is NOT trusted: read-time freshness against current HEAD → stale
  [ "$(jq -r '.revision.head_is_current' "$GDIR/ev/pm-decision-brief.json")" == "false" ]
  [ "$(jq -r '.revision.freshness' "$GDIR/ev/pm-decision-brief.json")" == "stale" ]
  # the referenced SHA (commit A) is preserved verbatim — freshness is computed, the reference is not rewritten
  [ "$(jq -r '.revision.head_sha' "$GDIR/ev/pm-decision-brief.json")" == "$a" ]
}

@test "IMP-264: non-hex / unresolvable recorded head_sha → fail-closed stale (never silently fresh)" {
  local GDIR="$TEST_TMPDIR/gitrepo"
  rm -rf "$GDIR"; mkdir -p "$GDIR/ev"
  git -C "$GDIR" init -q; git -C "$GDIR" config user.email t@t; git -C "$GDIR" config user.name t
  git -C "$GDIR" commit -q --allow-empty -m base
  jq '.release_decision.pm_brief_status="pending" | .revision.head_sha="abc123def456" | .revision.head_is_current=true | .revision.freshness="current"' \
     "$FIXTURE" > "$GDIR/ev/release-decision.json"
  run env AID_PLUGIN_PATH="$AID_PLUGIN_PATH" bash "$BRIEF" "$GDIR/ev"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.revision.head_is_current' "$GDIR/ev/pm-decision-brief.json")" == "false" ]
  [ "$(jq -r '.revision.freshness' "$GDIR/ev/pm-decision-brief.json")" == "stale" ]
  [ "$(jq -r '.revision.head_sha' "$GDIR/ev/pm-decision-brief.json")" == "abc123def456" ]
}
