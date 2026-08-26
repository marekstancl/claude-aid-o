#!/usr/bin/env bash
# aid-tier: t2
# test-integration-handoff-rendering.sh — P080 Step 15.
#
# Drives the THREE renderers of the §14 delivery contract over checked-in
# fixture JSON, end to end, for the five delivery cases:
#
#   finished · decision-required · blocked · force-used (waiver present) ·
#   incomplete (canonical facts arrived, model prose did not)
#
#   scripts/lib/aid-artifact-render.sh       the generic body renderer (smoke —
#                                            the audit renderer is untouched by
#                                            this plan and is not driven here)
#   scripts/lib/aid-gate-outcome-summary.sh  the GATES boundary
#   scripts/lib/aid-plan-close-summary.sh    the plan-final / close boundary
#
# WHAT IT PROVES, AND WHAT IT DELIBERATELY DOES NOT
#   Proves: the card comes FIRST (the first non-empty stdout line is the
#   outcome/decision sentence — no JSON, no path, no identifier ahead of it),
#   the artifact body carries the ecosystem standard's blocks in order, a raw
#   technical list can never be the ONLY output, and no secret survives either
#   the page, the card or the FALLBACK card.
#
#   Does NOT prove anything about publication. The renderers write files and
#   print text; the Artifact tool call is a live controller act wired in
#   commands/*.md and skills/pipeline.md. This harness runs anywhere, including
#   a CI box with no Artifact tool at all.
#
# GOLDEN FIXTURES — TWO PER CASE, AND REGENERATION IS A HUMAN ACT
#   Each case has two goldens under fixtures/handoff/golden/:
#
#     <case>.blocks.txt   the BLOCK ORDER — headings and structural markers in
#                         document order. A LAYOUT SPINE, and nothing more: it
#                         is identical across every case that renders the same
#                         blocks, which is most of them.
#     <case>.content.txt  the CONTENT — tile labels and values, every list item
#                         and paragraph, the detail link, the provenance footer.
#                         This is the golden that distinguishes one case from
#                         another and pins the numbers, the redactions and the
#                         offered commands.
#
#   The spine alone used to be the whole golden set, and seven of its nine
#   files were byte-identical to one another: no tile value, redaction, link,
#   command or footer change could move any of them. Nine fixtures asserted one
#   property. The content golden is what makes "golden" true of this directory.
#
#   Both are byte-compared. Every input is a checked-in fixture, so both are
#   fully deterministic; the price is that a deliberate template wording change
#   churns the content goldens, which is why regeneration is explicit.
#
#   Regenerate with, and ONLY with:
#
#     AID_HANDOFF_GOLDEN_REGEN=1 bash plugins/aid-orchestrator/scripts/tests/test-integration-handoff-rendering.sh
#
#   That mode rewrites the goldens and exits 2 with the diff it applied — it
#   NEVER runs off a mismatch and never reports a pass, because a golden test
#   that regenerates its own expectation on failure proves nothing.
#
# NONDETERMINISM, NORMALISED IN THE OPEN
#   Normalisation happens HERE, visibly, before any comparison — never inside a
#   fixture. Sources found in these outputs:
#     1. the harness temp dir (run_dir / out_dir, and every path derived from
#        it: the provenance footer, the links block, the `Artifact:` line)
#        → <WORK>
#     2. the repo root, which the same paths can carry     → <REPO>
#     3. aid-plan-close-summary.sh's `date -u` render stamp → <TS>
#   Durations are NOT normalised: they are computed from the fixtures' own
#   duration_ms, so they are deterministic and worth asserting.
#
# FIXTURE PROVENANCE
#   Every fixture carries a `_provenance` string naming the producer whose
#   field set it was hand-authored from. They are hand-authored because the
#   repo has no PLAN-mode release-decision.json to copy (all are EPIC-mode,
#   plan_summary: null) and because a real gates report carries a run's own
#   absolute paths.
#
# THE MALICIOUS FIXTURES ARE THE POINT, NOT AN OVERSIGHT
#   Three fixtures deliberately carry secret-shaped strings so leakage is
#   proven IMPOSSIBLE rather than merely absent. Every specimen is synthetic
#   (a counting sequence, AWS's published documentation example, the bash.org
#   joke password). They are named in MALICIOUS_FIXTURES below, which is the
#   only exemption the repo-wide secret sweep grants — an unlisted fixture with
#   a secret shape fails the sweep.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_DIR}/../.." && pwd)"
FIX="${SCRIPT_DIR}/fixtures/handoff"
GOLDEN="${FIX}/golden"

REGEN="${AID_HANDOFF_GOLDEN_REGEN:-0}"

pass=0; fail=0
pass_msg() { echo "  PASS: $1"; pass=$((pass + 1)); }
fail_msg() { echo "  FAIL: $1"; fail=$((fail + 1)); }

command -v jq >/dev/null 2>&1 || {
  echo "  FAIL: jq not installed"; echo "Results: 0/1 passed, 1 failed"; exit 1; }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# The libraries under test, sourced exactly as their callers do.
# shellcheck source=../lib/aid-artifact-render.sh
source "${PLUGIN_DIR}/scripts/lib/aid-artifact-render.sh"
# shellcheck source=../lib/aid-gate-outcome-summary.sh
source "${PLUGIN_DIR}/scripts/lib/aid-gate-outcome-summary.sh"
# shellcheck source=../lib/aid-plan-close-summary.sh
source "${PLUGIN_DIR}/scripts/lib/aid-plan-close-summary.sh"

# Fixtures that MAY carry secret shapes, and the reason each one does.
MALICIOUS_FIXTURES=(
  gate-report-malicious.json
  pm-brief-malicious.json
  malicious-fallback-output.txt
)

# The card labels from skills/communication.md. Structural labels, not prose:
# a fixture's Czech body text is never asserted, so another locale's prose
# passes this harness unchanged.
CARD_FINISHED='Hotovo:'
CARD_DECISION='Potřebuji tvoje rozhodnutí:'
CARD_BLOCKED='Zastaveno:'

# ─── normalisation ──────────────────────────────────────────────────────────
# Applied to renderer output before ANY comparison or dump. See the header for
# the enumerated sources.
_normalise() {
  sed -e "s#${WORK}#<WORK>#g" \
      -e "s#${REPO_ROOT}#<REPO>#g" \
      -e 's#[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}Z#<TS>#g'
}

# _spine <html_file> — the artifact's block order: every heading and structural
# marker, in document order, one per line.
_spine() {
  _normalise < "$1" \
    | grep -oE '<header class="masthead">|<section class="tiles">|<section class="block[^"]*">|<h2>[^<]*</h2>|class="golink"|<footer>'
}

# _content <html_file> — the artifact's CONTENT-BEARING elements, in document
# order: headings, tile labels and VALUES, every list item, the detail link and
# the provenance footer, plus the body paragraphs.
#
# WHY THIS EXISTS, AND WHY THE SPINE ALONE WAS NOT ENOUGH.
# The spine reduces a page to its block markers. That was deliberate — a
# wording edit inside a block should not churn nine fixtures — but the result
# was that SEVEN OF THE NINE goldens were byte-identical to each other, and the
# two that differed did so only by carrying the missing-prose block. A golden
# set in which most members are the same file cannot detect a changed tile
# value, a lost redaction, a dropped link, a rewritten command or a different
# footer; it detects a block moving, and nothing else. Nine files were being
# maintained to assert one property.
#
# Every input here is a checked-in fixture, so the content is fully
# deterministic and there is nothing to normalise beyond the three sources the
# header already enumerates. The tradeoff is accepted openly: a deliberate
# template wording change now churns the content goldens, and regeneration
# stays a human act.
_content() {
  _normalise < "$1" \
    | sed 's/></>\n</g' \
    | grep -E '^<(h1>|h2>|li>|p>|footer>|span class="[kv]">|div class="tile|a class="golink"|div class="golink")'
}

# _golden <case_name> <html_file> — compare the spine AND the content to their
# goldens, or, in the explicitly-invoked regeneration mode, rewrite both.
_golden() {
  # NOT one `local` statement: a name declared there is not yet visible to a
  # later assignment in the same statement, and under `set -u` that aborts.
  local name="$1" html="$2"
  local g="${GOLDEN}/${name}.blocks.txt"
  local actual="${WORK}/${name}.blocks.actual"
  _spine "$html" > "$actual"
  _golden_content "$name" "$html"
  if [[ "$REGEN" == "1" ]]; then
    if [[ -f "$g" ]] && diff -q "$g" "$actual" >/dev/null 2>&1; then
      echo "  REGEN: ${name} unchanged"
    else
      [[ -f "$g" ]] && diff -u "$g" "$actual" | sed 's/^/    /'
      cp "$actual" "$g"
      echo "  REGEN: ${name} rewritten"
    fi
    return 0
  fi
  if [[ ! -f "$g" ]]; then
    fail_msg "${name}: no golden at ${g} — regenerate deliberately (see this file's header)"
    return 1
  fi
  if diff -q "$g" "$actual" >/dev/null 2>&1; then
    pass_msg "${name}: artifact block order matches its golden"
    return 0
  fi
  fail_msg "${name}: artifact block order differs from ${g}"
  diff -u "$g" "$actual" | sed 's/^/    /'
  return 1
}

# _golden_content <case_name> <html_file> — the content half of _golden.
_golden_content() {
  local name="$1" html="$2"
  local g="${GOLDEN}/${name}.content.txt"
  local actual="${WORK}/${name}.content.actual"
  _content "$html" > "$actual"
  if [[ "$REGEN" == "1" ]]; then
    if [[ -f "$g" ]] && diff -q "$g" "$actual" >/dev/null 2>&1; then
      echo "  REGEN: ${name} content unchanged"
    else
      [[ -f "$g" ]] && diff -u "$g" "$actual" | sed 's/^/    /'
      cp "$actual" "$g"
      echo "  REGEN: ${name} content rewritten"
    fi
    return 0
  fi
  if [[ ! -f "$g" ]]; then
    fail_msg "${name}: no content golden at ${g} — regenerate deliberately (see this file's header)"
    return 1
  fi
  if diff -q "$g" "$actual" >/dev/null 2>&1; then
    pass_msg "${name}: tile values, list items, links and footer match their content golden"
    return 0
  fi
  fail_msg "${name}: artifact CONTENT differs from ${g}"
  diff -u "$g" "$actual" | sed 's/^/    /'
  return 1
}

# _assert_seven_blocks <case> <html> — the standard's mandatory blocks, in
# order, by byte offset. Structural markers only; no Czech literal is asserted.
_assert_seven_blocks() {
  local name="$1" f="$2" v p=() m
  for m in '<header class="masthead">' '<section class="tiles">' '<h2>Shrnutí</h2>' \
           '<h2>Jádro</h2>' '<h2>Co se čeká ode mě</h2>' '<footer>'; do
    v="$(grep -abo -F -e "$m" "$f" | head -1 | cut -d: -f1)"
    if [[ -z "$v" ]]; then
      fail_msg "${name}: rendered body is missing the mandatory block marker '${m}'"
      return 1
    fi
    p+=("$v")
  done
  local i
  for (( i = 1; i < ${#p[@]}; i++ )); do
    if (( p[i] <= p[i-1] )); then
      fail_msg "${name}: mandatory blocks are out of order (offset ${p[i]} follows ${p[i-1]})"
      return 1
    fi
  done
  pass_msg "${name}: mandatory artifact blocks present and in the standard's order"
  return 0
}

# _assert_card_first <case> <card_file> <expected_label>
#   The outcome sentence is the FIRST non-empty line, and nothing structural
#   precedes it: no JSON, no path, no identifier.
_assert_card_first() {
  local name="$1" cf="$2" label="$3" first
  first="$(grep -m1 -v '^[[:space:]]*$' "$cf" || true)"
  if [[ "$first" != "$label"* ]]; then
    fail_msg "${name}: first non-empty card line is not the '${label}' outcome sentence"
    echo "    got: ${first}" ; return 1
  fi
  if [[ "$first" == *'{'* || "$first" == *'/'* || "$first" == *'.json'* ]]; then
    fail_msg "${name}: the outcome sentence carries JSON or a path before the decision"
    echo "    got: ${first}" ; return 1
  fi
  # Identifiers and the detail link are optional FINAL lines.
  local last
  last="$(grep -v '^[[:space:]]*$' "$cf" | tail -1)"
  if [[ "$last" != Artifact* ]]; then
    fail_msg "${name}: the artifact reference is not the card's last line (got: ${last})"
    return 1
  fi
  pass_msg "${name}: card leads with the '${label}' outcome and ends with the artifact reference"
  return 0
}

# _run_renderer <case> <card_out> <fn> [args...]
#   Runs a renderer, capturing stdout and stderr separately. A nonzero exit
#   prints the case name and the child's stderr VERBATIM — this harness never
#   swallows a renderer's diagnostics.
_run_renderer() {
  local name="$1" card="$2"; shift 2
  local err="${WORK}/${name}.stderr" rc=0
  "$@" > "$card" 2> "$err" || rc=$?
  if (( rc != 0 )); then
    fail_msg "${name}: renderer exited ${rc}"
    echo "    --- ${name} stderr (verbatim) ---"
    sed 's/^/    /' "$err"
    echo "    --- end ${name} stderr ---"
    return 1
  fi
  if [[ -s "$err" ]]; then
    echo "    note: ${name} wrote to stderr while succeeding:"
    sed 's/^/    /' "$err"
  fi
  return 0
}

# ─── the five delivery cases ────────────────────────────────────────────────

echo "== delivery cases =="

# Case 1a: FINISHED — the gate boundary.
GRUN="${WORK}/finished-gate"; mkdir -p "${GRUN}/gates"
cp "${FIX}/gate-report-finished.json" "${GRUN}/gates/gates_report.json"
if _run_renderer finished-gate "${WORK}/finished-gate.card" aid_gate_outcome_render "" "$GRUN"; then
  _assert_card_first finished-gate "${WORK}/finished-gate.card" "$CARD_FINISHED"
  _assert_seven_blocks finished-gate "${GRUN}/gate-outcome-artifact.html"
  _golden finished-gate "${GRUN}/gate-outcome-artifact.html"
  # The tile is still COUNTED from the report — P089 Step 3 only changed what it
  # counts. The headline is now HOW MANY FAILED (so a green run reads "Nic
  # neselhalo"), and the numbers moved into four closed categories: ověřeno /
  # selhalo / neběželo / prominuto. This asserts the counted half of that, which
  # is the property the case is about; "2/2 prošlo" was the old wording of the
  # same idea and is gone from the renderer, not from the requirement.
  if grep -qF '<span class="v">2 brány</span>' "${GRUN}/gate-outcome-artifact.html" \
     && grep -qF '<span class="k">Ověřeno</span>' "${GRUN}/gate-outcome-artifact.html"; then
    pass_msg "finished-gate: the result tile is COUNTED from the report, not asserted"
  else
    fail_msg "finished-gate: expected a computed 'Ověřeno 2 brány' tile"
  fi
fi

# Case 1b: FINISHED — the plan-final / close boundary.
POUT="${WORK}/finished-plan"; mkdir -p "$POUT"
if _run_renderer finished-plan "${WORK}/finished-plan.card" \
     aid_plan_close_render "${FIX}/pm-brief-finished.json" "${FIX}/release-decision-merged.json" P080 "$POUT"; then
  _assert_card_first finished-plan "${WORK}/finished-plan.card" "$CARD_FINISHED"
  _assert_seven_blocks finished-plan "${POUT}/plan-close-artifact.html"
  _golden finished-plan "${POUT}/plan-close-artifact.html"
  if grep -qF '<span class="v">3/3 EPIKŮ</span>' "${POUT}/plan-close-artifact.html"; then
    pass_msg "finished-plan: the EPIC tile is COUNTED from the epics array"
  else
    fail_msg "finished-plan: expected a computed 3/3 EPIC tile"
  fi
fi

# Case 2: DECISION-REQUIRED — plan not release-ready.
DOUT="${WORK}/decision"; mkdir -p "$DOUT"
if _run_renderer decision "${WORK}/decision.card" \
     aid_plan_close_render "${FIX}/pm-brief-decision-required.json" "${FIX}/release-decision-open.json" P080 "$DOUT"; then
  _assert_card_first decision "${WORK}/decision.card" "$CARD_DECISION"
  _assert_seven_blocks decision "${DOUT}/plan-close-artifact.html"
  _golden decision "${DOUT}/plan-close-artifact.html"
  # The offered options must be the commands this HEAD actually ships, and the
  # rollback that has no revert commit must be declared inapplicable rather
  # than printed as an uninvocable line.
  if grep -qF 'aid-plan-fsm.sh plan-merge-to-main P080 --decision' "${WORK}/decision.card" \
     && grep -qF 'aid-plan-fsm.sh plan-close P080' "${WORK}/decision.card" \
     && ! grep -qF 'plan-rollback' "${WORK}/decision.card"; then
    pass_msg "decision: exactly the shipped commands are offered, rollback withheld while nothing is merged"
  else
    fail_msg "decision: the offered option set is not the shipped command set"
  fi
fi

# Case 3: BLOCKED — a required gate failed.
BRUN="${WORK}/blocked"; mkdir -p "${BRUN}/gates"
cp "${FIX}/gate-report-blocked.json" "${BRUN}/gates/gates_report.json"
if _run_renderer blocked "${WORK}/blocked.card" aid_gate_outcome_render "" "$BRUN"; then
  _assert_card_first blocked "${WORK}/blocked.card" "$CARD_BLOCKED"
  _assert_seven_blocks blocked "${BRUN}/gate-outcome-artifact.html"
  _golden blocked "${BRUN}/gate-outcome-artifact.html"
  # The reproduction step is the gate's OWN command from _command_log — never
  # an invented remediation.
  if grep -qF 'bash scripts/tests/run-all-tests.sh --tier t1' "${WORK}/blocked.card" \
     && grep -qF -- '--force --reason' "${WORK}/blocked.card"; then
    pass_msg "blocked: the card carries the gate's own command and the exact public force command"
  else
    fail_msg "blocked: the card is missing the reproduction command or the force command"
  fi
fi

# Case 4: FORCE-USED — a required gate failed and the PM waived it.
WRUN="${WORK}/force-used"; mkdir -p "${WRUN}/gates"
cp "${FIX}/gate-report-force-used.json" "${WRUN}/gates/gates_report.json"
if _run_renderer force-used "${WORK}/force-used.card" \
     aid_gate_outcome_render "" "$WRUN" "${FIX}/waivers"; then
  _assert_card_first force-used "${WORK}/force-used.card" "$CARD_FINISHED"
  _assert_seven_blocks force-used "${WRUN}/gate-outcome-artifact.html"
  _golden force-used "${WRUN}/gate-outcome-artifact.html"
  # A waiver is PM risk acceptance, never a pass — on BOTH surfaces.
  #
  # THE NEGATIVE IS SCOPED TO THE WAIVED GATE'S OWN LINE, AND COVERS CZECH.
  # It used to be `! grep -qF 'passed' <whole file>` — one English word, over a
  # document that is otherwise entirely Czech. A renderer that labelled the
  # waived row `prošla` would have satisfied it exactly, which is the label a
  # Czech renderer would actually reach for. It also could not be tightened
  # document-wide, because the legitimate result tile says "1/2 prošlo": the
  # word is fine on the COUNT and forbidden on the WAIVED ROW, so the row is
  # what gets isolated and asserted.
  # The page is one long line, so its unit is the <li>, not the line; the card's
  # unit IS the line. Each surface is cut at its own granularity — cutting the
  # page by line would drag the neighbouring "Prošlo 1, …" count sentence into
  # the waived row and fail on legitimate text.
  # THE TOKEN IS CZECH NOW, and that is the renderer being right rather than
  # this test being wrong. P089 Step 3 gave the gates page four closed
  # categories — ověřeno / selhalo / neběželo / PROMINUTO — on a page that is
  # Czech throughout; `waived` was the English label of the same idea and no
  # longer appears anywhere. The requirement is unchanged and is what these two
  # helpers still isolate: the waived gate must be VISIBLY waived on its own
  # row, never absorbed into the pass count. `prominut` is the shared stem of
  # prominuta / prominuto / prominuty, so no form escapes.
  _waived_units_page() { grep -oE '<li>[^<]*</li>' "$1" | grep -Ei 'waived|prominut'; }
  _waived_units_card() { grep -Ei 'waived|prominut' "$1"; }
  _pass_semantics() {  # any pass label, English or Czech, in the given text
    # Word forms are case-insensitive; the two-letter and all-caps LABELS are
    # not. `OK` folded to lowercase matches inside ordinary Czech words — the
    # first draft of this helper fired on "Další krok:" — so a label only
    # counts as a label when it is written as one.
    grep -qiE 'passed|prošl[aoyi]|prošel|úspěch|success' <<<"$1" && return 0
    grep -qE '\b(OK|PASS|PASSED)\b|✅' <<<"$1" && return 0
    return 1
  }
  wl_page="$(_waived_units_page "${WRUN}/gate-outcome-artifact.html")"
  wl_card="$(_waived_units_card "${WORK}/force-used.card")"
  waiver_problems=()
  [[ "$wl_page" == *'tests'* ]] || waiver_problems+=("the page has no result item marking gate 'tests' as waived")
  [[ -n "$wl_card" ]] || waiver_problems+=("the card never says the word waived")
  ! _pass_semantics "$wl_page" || waiver_problems+=("the page's waived row carries pass semantics: ${wl_page}")
  ! _pass_semantics "$wl_card" || waiver_problems+=("the card's waived row carries pass semantics: ${wl_card}")
  # The counts must not absorb the waiver on EITHER surface: the tile counts it
  # out of the passes, and the card states the waived count explicitly.
  # THE SAME REQUIREMENT ON THE SURFACE P089 STEP 3 BUILT. The counts must not
  # absorb the waiver, and the new page states that more plainly than the old
  # one did: the result tile NAMES the waiver ("Nic neselhalo, 1 prominuta"),
  # the verified count EXCLUDES it ("Ověřeno 1 brána" out of two), and the core
  # line spells out all four categories. The old assertions read "1/2 prošlo"
  # and a bare unresolved tile, which are the previous wording of this idea.
  grep -qE '<span class="v">[^<]*1 prominut[ay][^<]*</span>' "${WRUN}/gate-outcome-artifact.html" \
    || waiver_problems+=("the page's result tile does not name the waiver — it absorbed it into the pass count")
  grep -qF '<span class="v">1 brána</span>' "${WRUN}/gate-outcome-artifact.html" \
    || waiver_problems+=("the page's verified tile does not EXCLUDE the waived gate")
  grep -qE 'prominuto 1\b' "${WRUN}/gate-outcome-artifact.html" \
    || waiver_problems+=("the page's core line does not state the waived count")
  grep -qE 'prominut[oaé]' "${WORK}/force-used.card" \
    || waiver_problems+=("the card does not state the waived count")
  if (( ${#waiver_problems[@]} == 0 )); then
    pass_msg "force-used: the waived row carries no pass label (EN or CZ) on either surface, and both surfaces count it unresolved"
  else
    fail_msg "force-used: ${waiver_problems[*]}"
  fi
  if grep -qF 'flaky suite under investigation' "${WRUN}/gate-outcome-artifact.html"; then
    pass_msg "force-used: the waiver receipt enriched the line"
  else
    fail_msg "force-used: the waiver receipt detail did not reach the page"
  fi
fi

# Case 5: an INVALID brief is REFUSED, and no page is written.
#
# This case used to drive the renderer with `pm-brief-incomplete.json` and assert
# that a page rendered carrying the generic "prose missing" alarm. It had been
# failing on main — unseen, because this suite is `aid-tier: t2` and the nightly
# that runs it had not completed for days — and the resolution (cross-model
# review, 2026-08-14) is that the FIXTURE is invalid, not the caller:
#
#   * `summary_for_pm` at this boundary is NOT model prose. aid-release-policy.sh
#     constructs it, aid-pm-brief.sh echoes it deterministically, and the
#     protocol validator requires a non-empty string.
#   * the fixture declares `communication_status: "degraded"`, which the shipped
#     schema (defaults/schemas/pm-decision-brief.schema.json) does not permit at
#     all — its enum is complete | incomplete.
#
# The generic alarm in lib/aid-artifact-render.sh remains a real capability for a
# DECLARED degraded state — Case 5b below exercises it — but it is not a licence
# for the plan-close caller to render a handoff whose machine input is malformed.
# If "the prose may be absent here" ever becomes real product intent it needs a
# declared protocol state (producer + schema + validator + caller + fixture
# together), not a relaxed `str_req`, and the alarm golden comes back with it.
IOUT="${WORK}/incomplete"; mkdir -p "$IOUT"
ierr="${WORK}/incomplete.stderr"
if aid_plan_close_render "${FIX}/pm-brief-incomplete.json" "${FIX}/release-decision-merged.json" \
     P080 "$IOUT" > "${WORK}/incomplete.card" 2> "$ierr"; then
  fail_msg "invalid-brief: the renderer ACCEPTED a brief with an empty summary_for_pm"
else
  pass_msg "invalid-brief: the renderer refuses rather than rendering a handoff from malformed input"
  if grep -qF 'summary_for_pm' "$ierr"; then
    pass_msg "invalid-brief: the refusal names the offending field"
  else
    fail_msg "invalid-brief: the refusal does not name summary_for_pm — a nameless refusal is not diagnosable"
  fi
  if [[ ! -s "${IOUT}/plan-close-artifact.html" ]]; then
    pass_msg "invalid-brief: no page was written"
  else
    fail_msg "invalid-brief: a page was written despite the refusal"
  fi
fi

# Case 5b: the same at the GENERIC renderer — facts, no prose at all. This is
# the smoke pass over aid_artifact_render itself (the audit renderer is
# untouched by this plan and is not driven here).
SOUT="${WORK}/smoke-no-prose.html"
if _run_renderer smoke-no-prose "${WORK}/smoke-no-prose.stdout" \
     aid_artifact_render outcome "${FIX}/artifact-facts-no-prose.json" "" "$SOUT"; then
  _assert_seven_blocks smoke-no-prose "$SOUT"
  _golden smoke-no-prose "$SOUT"
  # Block 6 never disappears, and the caps are enforced with a TRUE remainder.
  # 6 items against a cap of 5 and 4 next steps against a cap of 3 both leave a
  # remainder of exactly 1, so the overflow line must appear TWICE.
  # Both literals typed out HERE rather than sourced from the library under
  # test: an expectation read from the implementation is the implementation
  # agreeing with itself, and a change that rewrites the sentence would move
  # both sides of the comparison at once. (This reasoning used to live at the
  # incomplete case, which is now a refusal case and no longer states it.)
  # `$_AID_ARTIFACT_ASK_NOTHING` and `$(_aid_artifact_overflow 1)` both come
  # from the library under test, so they moved with any change to it.
  if grep -qF 'Nic — ozvu se, až bude hotovo' "$SOUT" \
     && [[ "$(grep -oF 'a dalších 1 v technickém detailu' "$SOUT" | wc -l)" == "2" ]]; then
    pass_msg "smoke-no-prose: the ask block survives an empty prose input and the caps report true remainders"
  else
    fail_msg "smoke-no-prose: the ask block or the overflow literal is missing"
  fi
  # The body is a BODY: the Artifact tool supplies the skeleton.
  # The alternatives are anchored on purpose: a bare `<head` also matches the
  # masthead's own `<header`, which is legitimate body content.
  if ! grep -qiE '<!doctype|<html[ >]|<head>|<body[ >]|</body>' "$SOUT" \
     && ! grep -qiE '(src|href)="(https?:)?//' "$SOUT"; then
    pass_msg "smoke-no-prose: body-only and CSP-clean — no skeleton tags, no external origin"
  else
    fail_msg "smoke-no-prose: the body carries skeleton tags or an external asset"
  fi
fi

# ─── secrets ────────────────────────────────────────────────────────────────

echo "== secrets =="

# AC: no fixture contains a real secret/token pattern. The sweep uses the
# SHIPPED detector table, not a copy of it, so a new detector widens the sweep
# automatically.
#
# high_entropy_blob is handled separately and precisely rather than exempted:
# a 40-char hex git SHA matches it, and SHAs are legitimate fixture content
# (the renderers shorten them to 12 chars before they reach a page). Any
# high-entropy hit that is NOT a 40-hex SHA fails.
_is_allowed_fixture() {
  local b; b="$(basename "$1")"
  local m; for m in "${MALICIOUS_FIXTURES[@]}"; do [[ "$b" == "$m" ]] && return 0; done
  return 1
}

for m in "${MALICIOUS_FIXTURES[@]}"; do
  if [[ -f "${FIX}/${m}" ]]; then
    pass_msg "declared malicious fixture ${m} exists (the allowlist cannot rot into a blanket exemption)"
  else
    fail_msg "declared malicious fixture ${m} is missing — remove it from MALICIOUS_FIXTURES or restore it"
  fi
done

sweep_bad=0
while IFS= read -r f; do
  _is_allowed_fixture "$f" && continue
  for entry in "${_AID_ARTIFACT_DETECTORS[@]}"; do
    dname="${entry%%|*}"; dre="${entry#*|}"
    while IFS= read -r hit; do
      [[ -n "$hit" ]] || continue
      if [[ "$dname" == "high_entropy_blob" ]]; then
        [[ "$hit" =~ ^[0-9a-f]{40}$ ]] && continue
      fi
      fail_msg "fixture $(basename "$f") carries a ${dname}-shaped string: ${hit:0:12}…"
      sweep_bad=1
    done < <(grep -oE -e "$dre" "$f" 2>/dev/null || true)
  done
done < <(find "$FIX" -type f ! -path "${GOLDEN}/*")
(( sweep_bad == 0 )) && pass_msg "no non-allowlisted fixture carries a secret shape (swept with the shipped detector table)"

# Runtime leakage through the GATE renderer: the malicious report puts secrets
# in a gate row's `output`, in a gate NAME and in a _command_log command — the
# three places a run can carry tooling-controlled text to a human surface.
MRUN="${WORK}/malicious-gate"; mkdir -p "${MRUN}/gates"
cp "${FIX}/gate-report-malicious.json" "${MRUN}/gates/gates_report.json"
SPECIMENS=(
  'ghp_0123456789abcdefghijklmnopqrstuvwxyz'
  'ghp_0123456789abcdefghijklmnop'
  'AKIAIOSFODNN7EXAMPLE'
  'password=hunter2'
  'Bearer abcdefghijklmnopqrstuvwxyz012345'
)
if _run_renderer malicious-gate "${WORK}/malicious-gate.card" aid_gate_outcome_render "" "$MRUN"; then
  leaked=""
  for s in "${SPECIMENS[@]}"; do
    grep -qF -- "$s" "${MRUN}/gate-outcome-artifact.html" && leaked+=" page:${s:0:10}…"
    grep -qF -- "$s" "${WORK}/malicious-gate.card" && leaked+=" card:${s:0:10}…"
  done
  if [[ -z "$leaked" ]]; then
    pass_msg "malicious-gate: no specimen survives into the page or the chat card"
  else
    fail_msg "malicious-gate: leaked ->${leaked}"
  fi
  if grep -qE 'Redigováno tajemství: [1-9]' "${MRUN}/gate-outcome-artifact.html"; then
    pass_msg "malicious-gate: the provenance footer reports a non-zero redaction count"
  else
    fail_msg "malicious-gate: redaction happened silently — the footer count is zero"
  fi
  _golden malicious-gate "${MRUN}/gate-outcome-artifact.html"
fi

# Runtime leakage through the PLAN-CLOSE renderer: the secret sits in the
# model-written prose and in a blocker, i.e. on both halves of that page.
MOUT="${WORK}/malicious-plan"; mkdir -p "$MOUT"
if _run_renderer malicious-plan "${WORK}/malicious-plan.card" \
     aid_plan_close_render "${FIX}/pm-brief-malicious.json" "${FIX}/release-decision-open.json" P080 "$MOUT"; then
  leaked=""
  for s in "${SPECIMENS[@]}"; do
    grep -qF -- "$s" "${MOUT}/plan-close-artifact.html" && leaked+=" page:${s:0:10}…"
    grep -qF -- "$s" "${WORK}/malicious-plan.card" && leaked+=" card:${s:0:10}…"
  done
  if [[ -z "$leaked" ]]; then
    pass_msg "malicious-plan: no specimen survives into the page or the chat card"
  else
    fail_msg "malicious-plan: leaked ->${leaked}"
  fi
  if grep -qE 'Redigováno tajemství: [1-9]' "${MOUT}/plan-close-artifact.html"; then
    pass_msg "malicious-plan: the provenance footer reports a non-zero redaction count"
  else
    fail_msg "malicious-plan: redaction happened silently — the footer count is zero"
  fi
  _golden malicious-plan "${MOUT}/plan-close-artifact.html"
fi

# The FAILURE path. When a renderer cannot run, the controller falls back to a
# hand-built card — and that path must go through aid_gate_outcome_redact, the
# one callable entry point onto the same detector table. A fixture carrying one
# specimen of EVERY shipped detector proves the bypass is closed in code.
RAW="$(cat "${FIX}/malicious-fallback-output.txt")"
REDACTED="$(aid_gate_outcome_redact "$RAW")"
fallback_bad=0
for entry in "${_AID_ARTIFACT_DETECTORS[@]}"; do
  dname="${entry%%|*}"; dre="${entry#*|}"
  mapfile -t hits < <(grep -oE -e "$dre" "${FIX}/malicious-fallback-output.txt" 2>/dev/null || true)
  if (( ${#hits[@]} == 0 )); then
    fail_msg "fallback fixture carries no specimen for detector ${dname} — add one, or the fallback proof has a hole"
    fallback_bad=1
    continue
  fi
  for h in "${hits[@]}"; do
    if [[ "$REDACTED" == *"$h"* ]]; then
      fail_msg "fallback card leaked a ${dname} specimen: ${h:0:12}…"
      fallback_bad=1
    fi
  done
done
if (( fallback_bad == 0 )); then
  pass_msg "fallback card: every shipped detector has a specimen and none survives aid_gate_outcome_redact"
fi
if [[ "$REDACTED" == *'<redacted:'* ]]; then
  pass_msg "fallback card: redaction is visible, not silent"
else
  fail_msg "fallback card: nothing was marked as redacted"
fi

# ─── result ─────────────────────────────────────────────────────────────────

if [[ "$REGEN" == "1" ]]; then
  echo
  echo "GOLDENS REGENERATED. Review the diffs above, then re-run WITHOUT AID_HANDOFF_GOLDEN_REGEN."
  echo "Results: 0/1 passed, 1 failed (regeneration mode never reports a pass)"
  exit 2
fi

total=$((pass + fail))
echo
echo "Results: ${pass}/${total} passed, ${fail} failed"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
