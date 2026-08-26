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
  p7="$(_pos "$f" 'class="golink')"

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

@test "prose cannot move a tile: contradicting prose leaves the tile section byte-identical" {
  # THE PREVIOUS CASE DOES NOT PROVE ITS OWN TITLE, WHICH IS WHY THIS ONE EXISTS.
  # Checking that one fixture's tiles equal that fixture's facts is consistent
  # with a renderer that lets prose override the numbers — the fixture's prose
  # simply agrees with its facts. "Computed from facts_json ONLY" is a claim
  # about INDEPENDENCE, and independence is only visible when the other input
  # is varied. So: same facts, two proses that shout the opposite numbers, and
  # the rendered tile section must not move by a byte.
  local facts loud f1 f2
  facts="$(_full_facts)"
  loud="$(jq -n '{
    summary: "Brána SELHALA, výsledek je FAIL a je to katastrofa.",
    core: "Trvalo 999 hodin, rozsah 4321 souborů, neuzavřeno 77.",
    ask: "Výsledek: FAIL. Neuzavřeno: 77. Rozsah: 4321 souborů. Trvalo: 999 hodin."
  }')"
  _render "$facts" "$(_full_prose)" "$TEST_TMPDIR/agree.html"
  _render "$facts" "$loud"           "$TEST_TMPDIR/contradict.html"

  f1="$(grep -F '<section class="tiles">' "$TEST_TMPDIR/agree.html")"
  f2="$(grep -F '<section class="tiles">' "$TEST_TMPDIR/contradict.html")"
  [ -n "$f1" ]
  [ "$f1" = "$f2" ]

  # And the tiles still say what the FACTS said, not what the prose shouted:
  # byte-equality alone would also hold if both renders were equally wrong.
  [[ "$f1" == *'<span class="k">Výsledek</span><span class="v">PASS</span>'* ]]
  [[ "$f1" == *'<span class="k">Neuzavřeno</span><span class="v">0</span>'* ]]
  [[ "$f1" != *"FAIL"* ]]
  [[ "$f1" != *"4321"* ]]
  [[ "$f1" != *"999"* ]]
  [[ "$f1" != *"77"* ]]
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
  refute_grep -q 'totally-made-up' "$TEST_TMPDIR/body.html"
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
  refute_grep -q 'Čeho se to týká' "$f"
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
  refute_grep -q 'class="golink' "$TEST_TMPDIR/body.html"
}

@test "an explicit relative detail href becomes a link; an external one is named, not linked" {
  local facts
  facts="$(_full_facts | jq '.detail.href = "detail.html"')"
  _render "$facts" "$(_full_prose)" "$TEST_TMPDIR/rel.html"
  grep -qF '<a class="golink" href="detail.html">' "$TEST_TMPDIR/rel.html"

  facts="$(_full_facts | jq '.detail.href = "https://example.com/detail"')"
  _render "$facts" "$(_full_prose)" "$TEST_TMPDIR/abs.html"
  refute_grep -q 'example.com' "$TEST_TMPDIR/abs.html"
  grep -qF '<div class="golink golink-flat">' "$TEST_TMPDIR/abs.html"
}

# ─── caps, enforced in code ─────────────────────────────────────────────────

@test "nine result items render five plus the explicit overflow count" {
  local facts
  facts="$(_full_facts | jq '.items = ["i1","i2","i3","i4","i5","i6","i7","i8","i9"]')"
  _render "$facts" "$(_full_prose)"
  local f="$TEST_TMPDIR/body.html"
  grep -qF '<li>i5</li>' "$f"
  refute_grep -qF '<li>i6</li>' "$f"
  grep -qF 'a dalších 4 v technickém detailu' "$f"
}

@test "five next steps render three plus the explicit overflow count" {
  local facts
  facts="$(_full_facts | jq '.next_steps = ["s1","s2","s3","s4","s5"]')"
  _render "$facts" "$(_full_prose)"
  local f="$TEST_TMPDIR/body.html"
  grep -qF '<li>s3</li>' "$f"
  refute_grep -qF '<li>s4</li>' "$f"
  grep -qF 'a dalších 2 v technickém detailu' "$f"
}

@test "a runaway sentence is truncated at the ~220 char cap with an ellipsis" {
  local long facts
  # Real words, deliberately: an unbroken 500-char alphanumeric run is a
  # high-entropy blob and the redactor eats it before the cap ever applies.
  long="$(for i in $(seq 1 100); do printf 'slovo%s ' "$i"; done)"
  facts="$(_full_facts | jq --arg s "$long" '.items = [$s]')"
  _render "$facts" "$(_full_prose)"
  refute_grep -qF 'slovo100' "$TEST_TMPDIR/body.html"
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
  refute_grep -qF '<script>' "$f"
}

@test "prose containing markup is escaped too" {
  local prose
  prose="$(_full_prose | jq '.summary = "Rozbil se <b>build</b> & test."')"
  _render "$(_full_facts)" "$prose"
  grep -qF '&lt;b&gt;build&lt;/b&gt; &amp; test.' "$TEST_TMPDIR/body.html"
  refute_grep -qF '<b>build</b>' "$TEST_TMPDIR/body.html"
}

@test "a fact containing a literal placeholder is inserted raw, never re-expanded" {
  local facts
  facts="$(_full_facts | jq '.title = "{{fact:tiles.result.value}} a {{prose:ask}}"')"
  _render "$facts" "$(_full_prose)"
  local f="$TEST_TMPDIR/body.html"
  grep -qF '{{fact:tiles.result.value}} a {{prose:ask}}' "$f"
  # Substitution is single pass — the title did not become "PASS a …".
  refute_grep -qF '<h1>PASS a' "$f"
}

# ─── secret policy: redact, count, never silent ─────────────────────────────

@test "secrets in facts and prose are redacted and counted in the provenance footer" {
  local facts prose f
  facts="$(_full_facts | jq '.items = ["deploy s AKIAIOSFODNN7EXAMPLE", "curl -H \"Authorization: Bearer abcdefghijklmnopqrstuvwx\""]')"
  prose="$(_full_prose | jq '.core = "Selhalo na ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123 a password=hunter2xyz"')"
  _render "$facts" "$prose"
  f="$TEST_TMPDIR/body.html"
  refute_grep -q 'AKIAIOSFODNN7EXAMPLE' "$f"
  refute_grep -q 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123' "$f"
  refute_grep -q 'hunter2xyz' "$f"
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
  refute_grep -q 'artifact-outcome.html' "$f"
  refute_grep -q 'CONDITIONAL REGIONS' "$f"
  refute_grep -qiE '<!doctype' "$f"
  refute_grep -qiE '</?html[ >]' "$f"
  refute_grep -qiE '</?head[ >]' "$f"
  refute_grep -qiE '</?body[ >]' "$f"
}

@test "no external URL appears in any src, href or @import" {
  local facts
  facts="$(_full_facts | jq '.links = ["https://example.com/nope"] | .detail.href = "https://example.com/nope"')"
  _render "$facts" "$(_full_prose)" "$TEST_TMPDIR/csp.html"
  local f="$TEST_TMPDIR/csp.html"
  refute_grep -qiE '@import' "$f"
  refute_grep -qiE '(src|href)[[:space:]]*=[[:space:]]*"[[:space:]]*(https?:|//)' "$f"
  refute_grep -qiE 'url\([[:space:]]*["'"'"']?(https?:|//)' "$f"
}

@test "a detail href whose scheme hides behind leading whitespace is not linked" {
  # Browsers TRIM an href before resolving it, so " javascript:alert(1)" is an
  # executable scheme; anchoring the relative-only test at the raw string let it
  # through as a link. The label must still render, as plain text.
  local facts
  facts="$(_full_facts | jq '.detail = {label: "detail", href: " javascript:alert(1)"}')"
  _render "$facts" "$(_full_prose)" "$TEST_TMPDIR/ws.html"
  local f="$TEST_TMPDIR/ws.html"
  refute_grep -qi 'javascript' "$f"
  refute_grep -qF '<a class="golink"' "$f"
  grep -qF '<div class="golink golink-flat">detail</div>' "$f"
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

@test "the vendored style block matches BOTH its template header and the digest held in the test tree" {
  # TWO COMPARISONS, AND ONLY THE SECOND ONE IS A GUARD.
  # The template's own `sha256:` header line and the CSS it describes live in
  # the same file, so an edit that changes both agrees with itself and passes.
  # That comparison is kept — a header that drifts from its own body is still
  # worth catching — but it is not what makes this case able to fail. The
  # fixture digest under scripts/tests/fixtures/ is authored in a different
  # tree, so a restyle must be recorded there too, deliberately, by someone who
  # read the failure.
  local recorded actual expected
  actual="$(sed -n '/^<style>$/,/^<\/style>$/p' "$TEMPLATE" | sed '1d;$d' | sha256sum | cut -d' ' -f1)"

  recorded="$(grep -oE 'sha256:[[:space:]]+[0-9a-f]{64}' "$TEMPLATE" | grep -oE '[0-9a-f]{64}')"
  [ -n "$recorded" ]
  [ "$recorded" = "$actual" ]

  expected="$(grep -oE '^[0-9a-f]{64}$' "$AID_PLUGIN_PATH/scripts/tests/fixtures/artifact-outcome-css.sha256")"
  [ -n "$expected" ]
  [ "$expected" = "$actual" ]
}

@test "the vendored style block is byte-identical to its recorded source, or the run says it could not look" {
  local src
  src="${AID_ARTIFACT_CSS_SOURCE:-$(grep -oE 'source:[[:space:]]+[^[:space:]]+' "$TEMPLATE" | awk '{print $2}')}"
  [ -n "$src" ]
  # The source lives OUTSIDE the plugin and is genuinely absent in a consumer
  # checkout, so this cannot be a hard failure. It must not be an invisible one
  # either: bats reports a skip as a skip, and the reason names the path that
  # was not there, so nobody reads a green line as "the upstream was checked".
  # The standing guard while this is skipped is the fixture digest in the case
  # above — NOT the template's self-agreeing header, which proves nothing.
  # Set AID_ARTIFACT_CSS_SOURCE to point at the upstream on hosts that have it.
  if [ ! -f "$src" ]; then
    skip "upstream _CSS NOT compared — source unreachable at '$src'; the fixture digest is the only guard on this run"
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

@test "a write that dies mid-stream leaves no truncated page AND no temp debris" {
  # A file-size cap makes the write fail AFTER the first bytes have landed —
  # the shape a full disk or a quota has. Writing straight to out_path left a
  # truncated page sitting at the published path; the write goes through a temp
  # file and a rename, so out_path is either the whole page or untouched.
  #
  # `ulimit -f` delivers SIGXFSZ, which TERMINATES the writing shell by default:
  # the renderer's cleanup branch never ran, the function never returned, and a
  # partial `<out>.tmp.XXXXXX` was left in the output directory at exactly the
  # cap size. The case scored that as a pass because it only looked at out_path
  # and bats' teardown swept the debris away. The temp file is now asserted
  # gone, and the exit status asserted to be the renderer's own 3 rather than
  # 128+SIGXFSZ, which is what proves the signal was caught rather than fatal.
  local out="$TEST_TMPDIR/capped.html"
  printf 'PREVIOUS PAGE\n' > "$out"
  # Deliberately TINY inputs: under the cap, every intermediate the renderer
  # spills stays legal and the rendered page (the template is ~10 KB) is the
  # only thing that trips it. Full-size fixtures would abort earlier and the
  # case would pass without ever reaching the write.
  jq -nc '{title:"T", tiles:{result:{value:"PASS"}}}' > "$TEST_TMPDIR/capped-facts.json"
  jq -nc '{summary:"a", core:"b"}'                    > "$TEST_TMPDIR/capped-prose.json"

  run bash -c "ulimit -f 1
    source '$AID_PLUGIN_PATH/scripts/lib/aid-artifact-render.sh'
    aid_artifact_render outcome '$TEST_TMPDIR/capped-facts.json' '$TEST_TMPDIR/capped-prose.json' '$out'"
  # The renderer's own fail-closed status, not a signal death (153 = 128+25).
  [ "$status" -eq 3 ]
  # The previous page survives intact — no half-written artifact replaced it.
  [ "$(cat "$out")" = "PREVIOUS PAGE" ]
  # And nothing was left beside it. `find`, not a glob, so the assertion reports
  # the debris it found instead of comparing an unexpanded pattern.
  local debris
  debris="$(find "$TEST_TMPDIR" -maxdepth 1 -name 'capped.html.tmp.*' -print)"
  [ -z "$debris" ] || { echo "temp debris left behind: $debris"; false; }
}

@test "re-rendering an existing artifact keeps its mode — the rename must not demote it" {
  # The temp-file + rename write replaces the destination INODE, so the new
  # file arrived with mktemp's private 0600 and a 0640 page that a group reader
  # (or a web server) was serving became unreadable to it on the next render.
  local out="$TEST_TMPDIR/moded.html"
  run _render "$(_full_facts)" "$(_full_prose)" "$out"
  [ "$status" -eq 0 ]
  chmod 0640 "$out"
  run _render "$(_full_facts)" "$(_full_prose)" "$out"
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' "$out")" = "640" ]
  # A more permissive mode survives just as literally — the rule is "preserve",
  # not "clamp to something this file prefers".
  chmod 0664 "$out"
  run _render "$(_full_facts)" "$(_full_prose)" "$out"
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' "$out")" = "664" ]
}

@test "a FIRST render obeys the umask, not mktemp's private default" {
  # There is no destination mode to inherit, and 0600 is not what a plain `>`
  # would have produced — an artifact nobody but the running user can read is a
  # silent regression for every consumer of the page.
  local out="$TEST_TMPDIR/fresh.html"
  ( umask 022
    source "$AID_PLUGIN_PATH/scripts/lib/aid-artifact-render.sh"
    aid_artifact_render outcome "$(_full_facts)" "$(_full_prose)" "$out" )
  [ "$(stat -c '%a' "$out")" = "644" ]
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
