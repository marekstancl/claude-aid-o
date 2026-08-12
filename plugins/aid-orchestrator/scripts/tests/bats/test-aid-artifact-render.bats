#!/usr/bin/env bats
# aid-tier: t1
# test-aid-artifact-render.bats — golden fixtures for the deterministic
# artifact renderer (P080 Step 10).
#
# TESTABILITY BOUNDARY, STATED EXPLICITLY
#   Everything here is script-level. aid_artifact_render produces an artifact
#   BODY on disk and nothing more; it never publishes. Publication through the
#   Artifact tool is a live, session-level act owned by the controller
#   instruction, and NOTHING in this suite claims to cover it — the same
#   boundary aid-test-audit-chat-summary.sh draws for its own renderer.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  TEMPLATE="$AID_PLUGIN_PATH/defaults/templates/artifact-outcome.html"
  export TEMPLATE
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-artifact-render.sh"
}

teardown() {
  teardown_test_evidence_dir
}

# ─── fixtures ───────────────────────────────────────────────────────────────

_full_facts() {
  jq -n '{
    eyebrow: "Výsledek brány",
    title: "P080 běh brány",
    when: "12. 8. 2026, 10:00",
    tiles: {
      result:     {value: "PASS",       state: "ok"},
      duration:   {value: "3 min"},
      scope:      {value: "7 souborů"},
      unresolved: {value: "0",          state: "ok"}
    },
    items: ["první nález", "druhý nález"],
    next_steps: ["zkontroluj diff", "spusť brány"],
    links: ["Plán P080", {name: "Report brány"}],
    detail: {label: "technický detail v evidence/P080"},
    footer: "Vyrobil aid-artifact-render."
  }'
}

_full_prose() {
  jq -n '{
    summary: "Brána proběhla čistě, nic nezůstalo otevřené.",
    core: "Sedm souborů, dvě zjištění, obojí zavřené.",
    ask: "Mrkni na diff a řekni, jestli může jít dál."
  }'
}

# _render <facts> <prose> [outfile]
_render() {
  local facts="$1" prose="$2" out="${3:-$TEST_TMPDIR/body.html}"
  aid_artifact_render outcome "$facts" "$prose" "$out"
}

# _pos <file> <needle> — byte offset of the first occurrence, for order asserts.
_pos() {
  grep -abo -F -e "$2" "$1" | head -1 | cut -d: -f1
}

# ─── the seven blocks, and their order ──────────────────────────────────────

@test "full facts + prose render all seven blocks in the standard's order" {
  run _render "$(_full_facts)" "$(_full_prose)"
  [ "$status" -eq 0 ]

  local f="$TEST_TMPDIR/body.html"
  local p1 p2 p3 p4 p5 p6 p7
  p1="$(_pos "$f" '<header class="masthead">')"
  p2="$(_pos "$f" '<section class="tiles">')"
  p3="$(_pos "$f" '<h2>Shrnutí</h2>')"
  p4="$(_pos "$f" '<h2>Jádro</h2>')"
  p5="$(_pos "$f" '<h2>Čeho se to týká</h2>')"
  p6="$(_pos "$f" '<h2>Co se čeká ode mě</h2>')"
  p7="$(_pos "$f" 'class="golink"')"

  for v in "$p1" "$p2" "$p3" "$p4" "$p5" "$p6" "$p7"; do [ -n "$v" ]; done
  [ "$p1" -lt "$p2" ]
  [ "$p2" -lt "$p3" ]
  [ "$p3" -lt "$p4" ]
  [ "$p4" -lt "$p5" ]
  [ "$p5" -lt "$p6" ]
  [ "$p6" -lt "$p7" ]
}

@test "tiles are computed from facts_json only, with the four fixed slots" {
  _render "$(_full_facts)" "$(_full_prose)"
  local f="$TEST_TMPDIR/body.html"
  grep -qF '<div class="tile state-ok"><span class="k">Výsledek</span><span class="v">PASS</span></div>' "$f"
  grep -qF '<span class="k">Trvalo</span><span class="v">3 min</span>' "$f"
  grep -qF '<span class="k">Rozsah</span><span class="v">7 souborů</span>' "$f"
  grep -qF '<span class="k">Neuzavřeno</span>' "$f"
}

@test "a tile with no measured value renders the em dash, never a number" {
  local facts
  facts="$(_full_facts | jq 'del(.tiles.duration)')"
  _render "$facts" "$(_full_prose)"
  grep -qF '<span class="k">Trvalo</span><span class="v">—</span>' "$TEST_TMPDIR/body.html"
}

@test "an unknown tile state is dropped to the plain tile, not emitted as a class" {
  local facts
  facts="$(_full_facts | jq '.tiles.result.state = "totally-made-up"')"
  _render "$facts" "$(_full_prose)"
  ! grep -q 'totally-made-up' "$TEST_TMPDIR/body.html"
  grep -qF '<div class="tile"><span class="k">Výsledek</span>' "$TEST_TMPDIR/body.html"
}

# ─── the missing-prose contract ─────────────────────────────────────────────

@test "empty prose renders the warning block and keeps the computed numbers" {
  run _render "$(_full_facts)" '{}'
  [ "$status" -eq 0 ]
  local f="$TEST_TMPDIR/body.html"
  grep -qF '<h2>Shrnutí chybí</h2>' "$f"
  grep -qF 'Shrnutí chybí — čísla výše jsou dopočítaná a platí.' "$f"
  # The tiles still hold: the page is half-empty and SAYS so.
  grep -qF '<span class="v">PASS</span>' "$f"
}

@test "malformed prose_json renders the warning block instead of failing" {
  run _render "$(_full_facts)" 'this is not json'
  [ "$status" -eq 0 ]
  grep -qF '<h2>Shrnutí chybí</h2>' "$TEST_TMPDIR/body.html"
}

# ─── block 6 is never absent ────────────────────────────────────────────────

@test "block 6 renders the one declared nothing-needed literal when nothing is asked" {
  local out="$TEST_TMPDIR/nothing-needed.html"
  run _render "$(_full_facts)" "$(_full_prose | jq '.ask = ""')" "$out"
  [ "$status" -eq 0 ]
  grep -qF '<h2>Co se čeká ode mě</h2>' "$out"
  grep -qF 'Nic — ozvu se, až bude hotovo' "$out"
}

@test "block 6 renders even when prose_json is absent entirely" {
  local out="$TEST_TMPDIR/no-prose.html"
  run _render "$(_full_facts)" '' "$out"
  [ "$status" -eq 0 ]
  grep -qF '<h2>Co se čeká ode mě</h2>' "$out"
  grep -qF 'Nic — ozvu se, až bude hotovo' "$out"
}

# ─── the conditional halves: blocks 5 and 7 ─────────────────────────────────

@test "no-links input omits block 5 and leaves the remaining order unchanged" {
  local facts f
  facts="$(_full_facts | jq 'del(.links)')"
  _render "$facts" "$(_full_prose)"
  f="$TEST_TMPDIR/body.html"
  ! grep -q 'Čeho se to týká' "$f"
  local p4 p6
  p4="$(_pos "$f" '<h2>Jádro</h2>')"
  p6="$(_pos "$f" '<h2>Co se čeká ode mě</h2>')"
  [ "$p4" -lt "$p6" ]
}

@test "no-detail input omits block 7 — a detail target is never inferred" {
  local facts
  facts="$(_full_facts | jq 'del(.detail)')"
  _render "$facts" "$(_full_prose)"
  # `class="golink"`, not `golink`: the vendored stylesheet defines .golink
  # whether or not the block renders.
  ! grep -q 'class="golink"' "$TEST_TMPDIR/body.html"
}

@test "an explicit relative detail href becomes a link; an external one is named, not linked" {
  local facts
  facts="$(_full_facts | jq '.detail.href = "detail.html"')"
  _render "$facts" "$(_full_prose)" "$TEST_TMPDIR/rel.html"
  grep -qF '<a class="golink" href="detail.html">' "$TEST_TMPDIR/rel.html"

  facts="$(_full_facts | jq '.detail.href = "https://example.com/detail"')"
  _render "$facts" "$(_full_prose)" "$TEST_TMPDIR/abs.html"
  ! grep -q 'example.com' "$TEST_TMPDIR/abs.html"
  grep -qF '<div class="golink">' "$TEST_TMPDIR/abs.html"
}

# ─── caps, enforced in code ─────────────────────────────────────────────────

@test "nine result items render five plus the explicit overflow count" {
  local facts
  facts="$(_full_facts | jq '.items = ["i1","i2","i3","i4","i5","i6","i7","i8","i9"]')"
  _render "$facts" "$(_full_prose)"
  local f="$TEST_TMPDIR/body.html"
  grep -qF '<li>i5</li>' "$f"
  ! grep -qF '<li>i6</li>' "$f"
  grep -qF 'a dalších 4 v technickém detailu' "$f"
}

@test "five next steps render three plus the explicit overflow count" {
  local facts
  facts="$(_full_facts | jq '.next_steps = ["s1","s2","s3","s4","s5"]')"
  _render "$facts" "$(_full_prose)"
  local f="$TEST_TMPDIR/body.html"
  grep -qF '<li>s3</li>' "$f"
  ! grep -qF '<li>s4</li>' "$f"
  grep -qF 'a dalších 2 v technickém detailu' "$f"
}

@test "a runaway sentence is truncated at the ~220 char cap with an ellipsis" {
  local long facts
  # Real words, deliberately: an unbroken 500-char alphanumeric run is a
  # high-entropy blob and the redactor eats it before the cap ever applies.
  long="$(for i in $(seq 1 100); do printf 'slovo%s ' "$i"; done)"
  facts="$(_full_facts | jq --arg s "$long" '.items = [$s]')"
  _render "$facts" "$(_full_prose)"
  ! grep -qF 'slovo100' "$TEST_TMPDIR/body.html"
  grep -qF 'slovo1 ' "$TEST_TMPDIR/body.html"
  grep -qF '…</li>' "$TEST_TMPDIR/body.html"
}

# ─── escaping and single-pass substitution ──────────────────────────────────

@test "a title containing < and & is escaped, not left to corrupt the page" {
  local facts
  facts="$(_full_facts | jq '.title = "Sousto <script>alert(1)</script> & spol."')"
  _render "$facts" "$(_full_prose)"
  local f="$TEST_TMPDIR/body.html"
  grep -qF '&lt;script&gt;alert(1)&lt;/script&gt; &amp; spol.' "$f"
  ! grep -qF '<script>' "$f"
}

@test "prose containing markup is escaped too" {
  local prose
  prose="$(_full_prose | jq '.summary = "Rozbil se <b>build</b> & test."')"
  _render "$(_full_facts)" "$prose"
  grep -qF '&lt;b&gt;build&lt;/b&gt; &amp; test.' "$TEST_TMPDIR/body.html"
  ! grep -qF '<b>build</b>' "$TEST_TMPDIR/body.html"
}

@test "a fact containing a literal placeholder is inserted raw, never re-expanded" {
  local facts
  facts="$(_full_facts | jq '.title = "{{fact:tiles.result.value}} a {{prose:ask}}"')"
  _render "$facts" "$(_full_prose)"
  local f="$TEST_TMPDIR/body.html"
  grep -qF '{{fact:tiles.result.value}} a {{prose:ask}}' "$f"
  # Substitution is single pass — the title did not become "PASS a …".
  ! grep -qF '<h1>PASS a' "$f"
}

# ─── secret policy: redact, count, never silent ─────────────────────────────

@test "secrets in facts and prose are redacted and counted in the provenance footer" {
  local facts prose f
  facts="$(_full_facts | jq '.items = ["deploy s AKIAIOSFODNN7EXAMPLE", "curl -H \"Authorization: Bearer abcdefghijklmnopqrstuvwx\""]')"
  prose="$(_full_prose | jq '.core = "Selhalo na ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123 a password=hunter2xyz"')"
  _render "$facts" "$prose"
  f="$TEST_TMPDIR/body.html"
  ! grep -q 'AKIAIOSFODNN7EXAMPLE' "$f"
  ! grep -q 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123' "$f"
  ! grep -q 'hunter2xyz' "$f"
  grep -qF 'redacted:aws_access_key' "$f"
  grep -qF 'redacted:github_token' "$f"
  # The count is rendered, so a redaction can never be silent.
  grep -qE 'Redigováno tajemství: [1-9][0-9]*\.' "$f"
}

@test "a clean render still states the redaction count, as zero" {
  _render "$(_full_facts)" "$(_full_prose)"
  grep -qF 'Redigováno tajemství: 0.' "$TEST_TMPDIR/body.html"
}

# ─── the Artifact tool + CSP contract ───────────────────────────────────────

@test "the body carries no html, head or body tag" {
  _render "$(_full_facts)" "$(_full_prose)"
  local f="$TEST_TMPDIR/body.html"
  # The page begins at <style> — the template's contributor header comment is
  # documentation, not content, and is stripped whole.
  # Line 1 AND line 2: `head -c 7` alone passed over a body that began with a
  # stray "<style> and </style> lines below," sentence sliced out of the
  # header comment.
  [ "$(sed -n '1p' "$f")" = "<style>" ]
  [ "$(sed -n '2p' "$f")" = ":root{" ]
  ! grep -q 'artifact-outcome.html' "$f"
  ! grep -q 'CONDITIONAL REGIONS' "$f"
  ! grep -qiE '<!doctype' "$f"
  ! grep -qiE '</?html[ >]' "$f"
  ! grep -qiE '</?head[ >]' "$f"
  ! grep -qiE '</?body[ >]' "$f"
}

@test "no external URL appears in any src, href or @import" {
  local facts
  facts="$(_full_facts | jq '.links = ["https://example.com/nope"] | .detail.href = "https://example.com/nope"')"
  _render "$facts" "$(_full_prose)" "$TEST_TMPDIR/csp.html"
  local f="$TEST_TMPDIR/csp.html"
  ! grep -qiE '@import' "$f"
  ! grep -qiE '(src|href)[[:space:]]*=[[:space:]]*"[[:space:]]*(https?:|//)' "$f"
  ! grep -qiE 'url\([[:space:]]*["'"'"']?(https?:|//)' "$f"
}

@test "the page is theme-aware in all three states and paints its own background" {
  _render "$(_full_facts)" "$(_full_prose)"
  local f="$TEST_TMPDIR/body.html"
  grep -qF ':root{' "$f"
  grep -qF '@media (prefers-color-scheme: dark){' "$f"
  grep -qF ':root:not([data-theme="light"]){' "$f"
  grep -qF ':root[data-theme="dark"]{' "$f"
  grep -qF 'background:var(--ground)' "$f"
}

# ─── the vendored style block ───────────────────────────────────────────────

@test "the vendored style block matches the sha256 recorded in the template header" {
  local recorded actual
  recorded="$(grep -oE 'sha256:[[:space:]]+[0-9a-f]{64}' "$TEMPLATE" | grep -oE '[0-9a-f]{64}')"
  [ -n "$recorded" ]
  actual="$(sed -n '/^<style>$/,/^<\/style>$/p' "$TEMPLATE" | sed '1d;$d' | sha256sum | cut -d' ' -f1)"
  [ "$recorded" = "$actual" ]
}

@test "the vendored style block is byte-identical to its recorded source" {
  local src
  src="$(grep -oE 'source:[[:space:]]+[^[:space:]]+' "$TEMPLATE" | awk '{print $2}')"
  [ -n "$src" ]
  # The source lives outside the plugin; where it is unreachable the sha256
  # test above still pins the template against silent drift.
  if [ ! -f "$src" ]; then
    skip "vendor source not reachable from this host: $src"
  fi
  python3 - "$src" "$TEMPLATE" <<'PY'
import re, sys, pathlib
src, tpl = pathlib.Path(sys.argv[1]).read_text(), pathlib.Path(sys.argv[2]).read_text()
upstream = re.search(r'^_CSS = """(.*?)"""', src, re.S | re.M).group(1)
vendored = re.search(r'^<style>\n(.*?)^</style>$', tpl, re.S | re.M).group(1)
sys.exit(0 if upstream == "\n" + vendored else 1)
PY
}

# ─── error handling ─────────────────────────────────────────────────────────

@test "invalid facts_json fails closed with the jq error" {
  run _render '{not json' "$(_full_prose)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid facts_json"* ]]
  [ ! -f "$TEST_TMPDIR/body.html" ]
}

@test "an unwritable out_path exits 3" {
  run _render "$(_full_facts)" "$(_full_prose)" "$TEST_TMPDIR/no/such/dir/body.html"
  [ "$status" -eq 3 ]
}

@test "an unknown template id fails rather than rendering an empty page" {
  run aid_artifact_render nosuchtemplate "$(_full_facts)" "$(_full_prose)" "$TEST_TMPDIR/x.html"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown template"* ]]
}

@test "facts_json and prose_json may be file paths as well as literals" {
  _full_facts > "$TEST_TMPDIR/facts.json"
  _full_prose > "$TEST_TMPDIR/prose.json"
  run aid_artifact_render outcome "$TEST_TMPDIR/facts.json" "$TEST_TMPDIR/prose.json" "$TEST_TMPDIR/frompath.html"
  [ "$status" -eq 0 ]
  grep -qF '<h1>P080 běh brány</h1>' "$TEST_TMPDIR/frompath.html"
}
