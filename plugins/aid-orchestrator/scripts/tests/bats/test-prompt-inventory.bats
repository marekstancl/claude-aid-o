#!/usr/bin/env bats
# aid-tier: t0
# The prompt inventory (P107 Step 6): lines per prompt section, and every
# citation of every finding mapped to the section it came from. Defect it
# catches: a citation mapped to the wrong section — a CP1 reviewer's repository
# path counted as a prompt section, or a CP2 repository path outside the diff
# counted as diff.patch — which would make the report argue for cutting the
# part reviewers actually use.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  INV="$AID_PLUGIN_PATH/scripts/aid-prompt-inventory.sh"
  T="$(mktemp -d)"; EV="$T/proj/.aid-o/work/evidence"
  # cp1 round: one prompt with four sections, three findings by `reuse`
  local r="$EV/P9/cp1/round-1"; mkdir -p "$r/packet"
  { echo "# cp1 review, round 1"; echo "intro"; echo "## Rules"; echo "r1"; echo "r2"; echo "## Your role"; echo "role"; echo "## Standards"; echo "s";
    echo "## plan.md (also on disk: x; cite it as plan.md:<line>)"; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do echo "l$i"; done; } > "$r/prompt-reuse.md"
  jq -n '{round:1, prompt_lines:{reuse: 23}}' > "$r/round.json"
  jq -n '{findings:[
    {reported_by:["reuse"], evidence:"plan.md:12"},
    {reported_by:["reuse"], evidence:"bin/x.sh:3; plan.md:2-4"},
    {reported_by:["reuse"], evidence:""},
    {reported_by:["behaviour_edges"], evidence:"plan.md:1"}]}' > "$r/merged.json"
  # cp2 round: one prompt, diff.patch touches bin/x.sh, one finding citing it and one citing a file outside the diff
  local s="$EV/E-9-1_1/R-1/cp2/step-0/round-1"; mkdir -p "$s/packet"
  { echo "# cp2 review"; echo "## Rules"; echo "r"; echo "## diff.patch (also on disk)"; echo "d1"; echo "d2"; } > "$s/prompt-step_generalist.md"
  printf 'diff --git a/bin/x.sh b/bin/x.sh\n+++ b/bin/x.sh\n+echo\n' > "$s/packet/diff.patch"
  jq -n '{findings:[{reported_by:["step_generalist"], evidence:"bin/x.sh:1"},{reported_by:["step_generalist"], evidence:"lib/other.sh:5"}]}' > "$s/merged.json"
}
teardown() { rm -rf "$T"; }

@test "cp1: lines per section, citations per section, a repository path is outside the prompt, a blank evidence counts the finding, other roles are not counted" {
  run "$INV" "$EV" --json "$T/inv.json" --md "$T/inv.md"
  echo "$output"; [ "$status" -eq 0 ]
  local row; row="$(jq -c '.[] | select(.checkpoint=="cp1" and .role=="reuse")' "$T/inv.json")"
  [ "$(jq -r .project <<< "$row")" = "proj" ]
  [ "$(jq -r .lines_total_median <<< "$row")" = "23" ]
  [ "$(jq -r '.lines_by_section["Rules"]' <<< "$row")" = "2" ]
  [ "$(jq -r '.lines_by_section["plan.md"]' <<< "$row")" = "14" ]
  [ "$(jq -r '.lines_by_section["(before the first heading)"]' <<< "$row")" = "2" ]
  [ "$(jq -r .findings <<< "$row")" = "3" ]
  [ "$(jq -r '.citations_by_section["plan.md"]' <<< "$row")" = "2" ]
  [ "$(jq -r '.citations_by_section["repository (outside the prompt)"]' <<< "$row")" = "1" ]
  [ "$(jq -r '.never_cited | sort | join(",")' <<< "$row")" = "(before the first heading),Rules,Standards,Your role" ]
  grep -q '^| proj | reuse | 1 | 23 |' "$T/inv.md"
  grep -q '^## Sections no finding cited in any project' "$T/inv.md"
}

@test "cp2: a repository path the diff touches is diff.patch, one outside the diff is not" {
  run "$INV" "$EV" --json "$T/inv.json" --md "$T/inv.md"
  [ "$status" -eq 0 ]
  local row; row="$(jq -c '.[] | select(.checkpoint=="cp2" and .role=="step_generalist")' "$T/inv.json")"
  [ "$(jq -r '.citations_by_section["diff.patch"]' <<< "$row")" = "1" ]
  [ "$(jq -r '.citations_by_section["repository (outside the prompt)"]' <<< "$row")" = "1" ]
  [ "$(jq -r .lines_total_median <<< "$row")" = "6" ]    # no round.json: counted from the file
}

@test "a root with no prompts is refused; a round without merged.json is counted with zero findings and named" {
  mkdir -p "$T/empty"
  run "$INV" "$T/empty"
  [ "$status" -eq 1 ]; [[ "$output" == *"no review prompts found"* ]]
  rm "$EV/P9/cp1/round-1/merged.json"
  run "$INV" "$EV" --json "$T/inv.json"
  [ "$status" -eq 0 ]; [[ "$output" == *"no merged.json"* ]]
  [ "$(jq -r '.[] | select(.checkpoint=="cp1") | .findings' "$T/inv.json")" = "0" ]
}
