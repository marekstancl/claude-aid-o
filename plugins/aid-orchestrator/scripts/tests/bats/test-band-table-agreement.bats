#!/usr/bin/env bats
# aid-tier: t0
# test-band-table-agreement.bats — the two band tables must not drift.
#
# WHY THIS SUITE EXISTS: the obligations-by-band split lives twice — as the
# machine table `_AID_LINT_BAND_OBLIGATIONS` in aid-plan-lint.sh, which decides,
# and as the human table in skills/plan-writing.md, which plan authors read.
# Two authorities that disagree are worse than one that is wrong, because the
# author obeys the one that does not decide. Found by a cross-provider wiring
# review, 2026-08-23 (no test asserted their agreement).

setup() {
  PLUGIN="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"   # plugins/aid-orchestrator
  LINT="${PLUGIN}/scripts/aid-plan-lint.sh"
  SKILL="${PLUGIN}/skills/plan-writing.md"
}

# The obligation names the lint knows, one per line.
_lint_obligations() {
  sed -n '/_AID_LINT_BAND_OBLIGATIONS=(/,/^)/p' "$LINT" \
    | grep -oE '"[a-z_]+:' | tr -d '":'
}

@test "every obligation the lint grades is named in the skill's band section" {
  local missing=""
  while read -r ob; do
    [[ -n "$ob" ]] || continue
    # step_fields is the skill's three-field row; the others carry their own name.
    case "$ob" in
      step_fields)   grep -q "Architecture Context" "$SKILL" || missing+=" $ob" ;;
      reuse_check)   grep -q "Reuse check" "$SKILL"          || missing+=" $ob" ;;
      standards)     grep -q "## Standards" "$SKILL"         || missing+=" $ob" ;;
      documentation) grep -qi "documentation" "$SKILL"       || missing+=" $ob" ;;
      *)             missing+=" $ob(unknown)" ;;
    esac
  done < <(_lint_obligations)
  [ -z "$missing" ] || { echo "not described in plan-writing.md:$missing"; false; }
}

@test "the skill's band section exists and names all three bands" {
  grep -q "Obligations by ceremony band" "$SKILL"
  grep -q '`full`' "$SKILL"
  grep -q '`medium`' "$SKILL"
  grep -q '`light`' "$SKILL"
}

@test "the lint grades exactly the four obligations this release ships" {
  run bash -c "sed -n '/_AID_LINT_BAND_OBLIGATIONS=(/,/^)/p' '$LINT' | grep -cE '\"[a-z_]+:'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 4 ]
}
