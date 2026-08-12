#!/usr/bin/env bash
# aid-tier: t0
# test-communication-wiring.sh — the communication contract is actually wired.
#
# `skills/communication.md` defines the four PM decision cards, the D16 output
# products and the publish-before-present clause ONCE. A contract file nobody
# points at is decoration (AID principle #1), so this suite checks the wiring
# mechanically instead of trusting prose:
#
#   1. REFERENCE. Every surface that talks to the PM at a boundary names
#      `skills/communication.md` literally.
#   2. PUBLICATION. Every site that invokes a deterministic renderer also
#      carries the CANONICAL publish-before-present clause, verbatim. One
#      literal, defined in communication.md and pasted unchanged at each site —
#      a loose grep would pass on a paraphrase, which is exactly how two
#      differently-worded clauses ship and neither is enforced.
#      The sites are FOUR, not three: `skills/pipeline.md` carries two distinct
#      renderer invocations (gates phase and plan boundary) and each is asserted
#      separately, anchored on its own renderer name — listing the file once
#      would let the gates path pass on the plan path's clause.
#   3. SUPERSEDED FRAGMENTS. The shapes the contract replaces are gone: the
#      metrics-first DONE-review header in aid-run.md, the hardcoded Czech
#      language mandate in the two verify commands, and any second definition
#      of a card skeleton.
#
# Fences: a card quoted inside a ``` fence is an EXAMPLE, not a definition, so
# the card-uniqueness check counts UNFENCED occurrences only (same
# `fenced_stripped` awk as scripts/aid-lint-skill.sh). communication.md itself
# is exempt from that check and is verified separately to carry the skeleton —
# its cards are fenced examples by design.
#
# Expected state: this suite FAILS until the sweep step wires the surfaces, and
# passes afterwards. That is the point — it is the gate for that work.
#
# Exit: 0 = all cases pass, 1 = at least one case failed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CONTRACT="skills/communication.md"

# The canonical publish-before-present literal. Defined in communication.md and
# reused verbatim by every renderer wiring site. Keep these two in sync — the
# first case below fails loudly if the contract file stops carrying it.
PUBLISH_CLAUSE='Publish the artifact body via the Artifact tool, then present the chat card verbatim.'

# The distinctive Decision-required card line. Exactly one file may DEFINE it.
CARD_LINE='Potřebuji tvoje rozhodnutí:'

# The SECTION, not a line count, is what bounds a renderer site.
#
# This used to be `WINDOW=30` — the clause counted if it fell within thirty
# lines after any occurrence of the renderer's filename. Two things were wrong
# with that. A line count is not a structure: thirty lines reaches into
# whatever happens to follow, and the number was chosen to fit the current
# spacing, so ordinary editing silently changes what the test means. And the
# anchor was ANY occurrence of the filename — a prose mention, a changelog
# line, a "we used to call" sentence — so a site could be credited with an
# invocation it does not contain.
#
# Both are now structural. An anchor counts only when the filename is cited AS
# CODE (inside a fence, or backticked), which is how these surfaces write
# something meant to be executed. The clause must then appear between that
# anchor and the end of its section — the next markdown heading — so the gates
# clause still cannot satisfy the plan-boundary site, and the bound moves with
# the document instead of with a magic number.
#
# HONEST SCOPE, unchanged: these are LLM-executed prose surfaces. This proves a
# site INSTRUCTS publication in an executable form next to the invocation it
# belongs to. It cannot prove the controller published at runtime.

# _code_cite_lines <file> <needle> — line numbers where <needle> is cited as
# code: inside a ``` / ~~~ fence, or backticked on that line.
_code_cite_lines() {
  awk -v needle="$2" '
    /^[[:space:]]*(```|~~~)/ { infence = !infence; next }
    index($0, needle) > 0 {
      if (infence || $0 ~ /`[^`]*`/) print NR
    }
  ' "$1"
}

# _section_end <file> <from_line> — the last line of the section that begins at
# or contains <from_line>: the line before the next markdown heading, or EOF.
_section_end() {
  awk -v from="$2" 'NR > from && /^#{1,6} / { print NR - 1; exit } END { print NR }' "$1"
}

pass=0
fail=0

ok()   { printf '  PASS: %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL: %s\n' "$1" >&2; fail=$((fail + 1)); }
case_() { printf 'TEST: %s\n' "$1"; }

# ─── P072 Step 9: canonical result line for the aggregate collector ─────────
_emit_results() {
  set +e
  echo "Results: ${pass}/$((pass + fail)) passed, ${fail} failed"
  return 0
}
trap '_emit_results' EXIT

# fenced_stripped <file> — body with fenced code blocks blanked out, line
# numbers preserved. Same awk as scripts/aid-lint-skill.sh's fenced_stripped().
fenced_stripped() {
  awk '
    /^[[:space:]]*```/ { infence = !infence; print ""; next }
    { if (infence) print ""; else print }
  ' "$1"
}

# ─── Case 1: the contract file exists and defines the canonical literals ────
case_ "communication.md is the single definition of the cards and the clause"
contract_path="${PLUGIN_ROOT}/${CONTRACT}"
if [[ ! -f "$contract_path" ]]; then
  bad "$CONTRACT is missing — nothing can be wired to it"
else
  if grep -qF -- "$PUBLISH_CLAUSE" "$contract_path"; then
    ok "the publish-before-present clause is defined in $CONTRACT"
  else
    bad "$CONTRACT does not carry the canonical clause: $PUBLISH_CLAUSE"
  fi
  if grep -qF -- "$CARD_LINE" "$contract_path"; then
    ok "the Decision-required card skeleton is defined in $CONTRACT"
  else
    bad "$CONTRACT does not carry the card line: $CARD_LINE"
  fi
fi

# ─── Case 2: every required surface references the contract ─────────────────
case_ "every PM-facing surface references skills/communication.md"
REQUIRED_SURFACES=(
  commands/aid-run.md
  commands/aid-do.md
  commands/aid-plan.md
  commands/aid-audit-tests.md
  skills/run-management.md
  skills/pipeline.md
  agents/reporter.md
  agents/simplifier.md
  commands/aid-verify-implementation.md
  commands/aid-verify-plan.md
)
for rel in "${REQUIRED_SURFACES[@]}"; do
  f="${PLUGIN_ROOT}/${rel}"
  if [[ ! -f "$f" ]]; then
    bad "$rel does not exist (required surface)"
  elif grep -qF -- "$CONTRACT" "$f"; then
    ok "$rel references $CONTRACT"
  else
    bad "$rel never names $CONTRACT — its final turn has no contract"
  fi
done

# ─── Case 3: publication wiring at every renderer site ──────────────────────
#
# Each entry is "<file>|<renderer anchor>|<site name>". The two pipeline.md
# rows are separate on purpose (see header).
case_ "every renderer site carries the publish-before-present clause verbatim"
RENDERER_SITES=(
  'commands/aid-run.md|aid-gate-outcome-summary.sh|gate boundary'
  'skills/pipeline.md|aid-gate-outcome-summary.sh|gates phase'
  'commands/aid-plan.md|aid-plan-close-summary.sh|plan-close boundary'
  'skills/pipeline.md|aid-plan-close-summary.sh|plan-boundary section'
)
for site in "${RENDERER_SITES[@]}"; do
  IFS='|' read -r rel anchor label <<<"$site"
  f="${PLUGIN_ROOT}/${rel}"
  if [[ ! -f "$f" ]]; then
    bad "$rel does not exist (renderer site: $label)"
    continue
  fi

  anchor_lines=$(_code_cite_lines "$f" "$anchor")
  if [[ -z "$anchor_lines" ]]; then
    if grep -qF -- "$anchor" "$f"; then
      bad "$rel ($label) mentions $anchor only in prose — a bare mention is not an invocation"
    else
      bad "$rel ($label) never invokes $anchor"
    fi
    continue
  fi

  found=0
  while IFS= read -r ln; do
    [[ -z "$ln" ]] && continue
    end="$(_section_end "$f" "$ln")"
    # NOT `sed … | grep -q`. Under `set -o pipefail`, grep -q exits on the first
    # match and sed dies of SIGPIPE, so the PIPELINE reports failure and the
    # clause is scored as absent. With the old 30-line window sed usually
    # finished before grep could close the pipe and the bug stayed hidden; a
    # section-sized range makes it fire every time. The section is materialised
    # first, and only then searched.
    section="$(sed -n "${ln},${end}p" "$f")"
    if grep -qF -- "$PUBLISH_CLAUSE" <<<"$section"; then
      found=1
      break
    fi
  done <<<"$anchor_lines"

  if [[ "$found" -eq 1 ]]; then
    ok "$rel ($label) publishes before presenting"
  else
    bad "$rel ($label) invokes $anchor as code but its section carries no publish-before-present clause"
  fi
done

# ─── Case 4: the metrics-first DONE-review header is gone ───────────────────
#
# The superseded shape opens the PM's DONE message with counters. The check is
# ORDERING, not vocabulary: metrics may still appear as a trailing detail line
# (that is where the contract puts identifiers), but they may not be the first
# line under the DONE REVIEW header. Scanned RAW — the block is a template
# inside a fence by design, so stripping fences would make this vacuous.
case_ "aid-run.md no longer opens the DONE review with metrics"
run_md="${PLUGIN_ROOT}/commands/aid-run.md"
if [[ ! -f "$run_md" ]]; then
  bad "commands/aid-run.md is missing"
else
  offender=$(awk '
    /DONE REVIEW/            { seen = 1; next }
    seen && /^[[:space:]]*$/ { next }
    seen                     { print NR ":" $0; seen = 0 }
  ' "$run_md" | grep -E ':[[:space:]]*Steps:' || true)
  if [[ -z "$offender" ]]; then
    ok "the DONE review opens with an outcome, not counters"
  else
    bad "metrics-first DONE-review header still present at ${offender}"
  fi
fi

# ─── Case 5: no hardcoded output language in the verify commands ────────────
#
# The language rule lives in communication.md (PM's conversation language;
# documents per document_language in defaults/orchestration.yaml). A command
# that hardcodes Czech contradicts it for every other PM.
case_ "the verify commands do not hardcode the PM's language"
for rel in commands/aid-verify-implementation.md commands/aid-verify-plan.md; do
  f="${PLUGIN_ROOT}/${rel}"
  if [[ ! -f "$f" ]]; then
    bad "$rel does not exist"
    continue
  fi
  hits=$(fenced_stripped "$f" | grep -niE 'czech' || true)
  if [[ -z "$hits" ]]; then
    ok "$rel leaves the output language to the contract"
  else
    while IFS= read -r h; do
      [[ -n "$h" ]] && bad "$rel hardcodes the output language at line ${h%%:*}"
    done <<<"$hits"
  fi
done

# ─── Case 6: exactly one file defines a card skeleton ───────────────────────
#
# Definitions are unfenced; a fenced copy is a quoted example and is allowed.
# communication.md is the one definer and is checked in case 1.
case_ "no card skeleton of any of the four types is defined outside the contract file"
#
# ALL FOUR CARDS, BY THEIR FIELD SETS — not one line of one card.
# This used to grep for the single Decision-required line `$CARD_LINE`. A
# duplicated Finished, Blocked or Progress skeleton was therefore invisible,
# and so was a re-defined Decision card that omitted that one line while
# copying the other four. The contract's value is that there is ONE definition
# of each card; a check that watches one fifth of one card does not defend it.
#
# A file DEFINES a skeleton when TWO OR MORE distinct field labels of the same
# card appear unfenced. Two, not one: a single `Hotovo:` is how any surface
# refers to the Finished card in passing, and a check that fired on that would
# be so noisy it would be waived. Two labels of the same card in a row is
# somebody writing the skeleton out again.
CARD_FIELDS_FINISHED=('Hotovo:' 'Změnilo se:' 'Ověřeno:' 'Další krok:')
CARD_FIELDS_DECISION=('Potřebuji tvoje rozhodnutí:' 'Proč teď:' 'Doporučení:' 'Alternativy:' 'Riziko / co není ověřeno:')
CARD_FIELDS_BLOCKED=('Zastaveno:' 'Dopad:' 'Doporučené řešení:' 'Pokud chceš převzít riziko:')

dupes=""
while IFS= read -r f; do
  rel="${f#"$PLUGIN_ROOT"/}"
  [[ "$rel" == "$CONTRACT" ]] && continue
  stripped="$(fenced_stripped "$f")"
  for card in FINISHED DECISION BLOCKED; do
    declare -n fields="CARD_FIELDS_${card}"
    hits=0; seen=""
    for lbl in "${fields[@]}"; do
      if grep -qF -- "$lbl" <<<"$stripped"; then
        hits=$((hits + 1)); seen+="${seen:+, }${lbl}"
      fi
    done
    unset -n fields
    if (( hits >= 2 )); then
      dupes+=$'\n'"    $rel — ${card} skeleton (${hits} of its field labels, unfenced: ${seen})"
    fi
  done
done < <(find "$PLUGIN_ROOT/commands" "$PLUGIN_ROOT/skills" "$PLUGIN_ROOT/agents" \
              "$PLUGIN_ROOT/defaults" "$PLUGIN_ROOT/reference" \
              -name '*.md' -type f 2>/dev/null | sort)

if [[ -z "$dupes" ]]; then
  ok "each of the three field-bearing cards is defined once, in $CONTRACT"
else
  bad "card skeleton re-defined outside $CONTRACT (unfenced):${dupes}"
fi

echo "----------------------------------------------------------------------"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
