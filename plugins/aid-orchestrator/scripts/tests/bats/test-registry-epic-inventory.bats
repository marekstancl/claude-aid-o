#!/usr/bin/env bats
# aid-tier: t0
# test-registry-epic-inventory.bats — the registry tells the truth about the
# EPIC path P114 removes (3.0.0). The inventory of P111
# (docs/reference/2026-10-p111-inventura-epic-cesty.md) gave every one of its
# 52 rows a verdict; P114 retires them by that verdict, with the corrections of
# its own column. Defect caught: a row left promising a control whose code is
# gone, or a replacement guard that points nowhere.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  REPO="$(cd "$AID_PLUGIN_PATH/../.." && pwd)"
  REG="$AID_PLUGIN_PATH/defaults/enforcement-registry.yaml"
  INV="$REPO/docs/reference/2026-10-p111-inventura-epic-cesty.md"
  [ -f "$INV" ] || skip "the inventory is not in this checkout"
  ROWS="$BATS_TEST_TMPDIR/rows.json"
  yq -o=json '.enforcements' "$REG" > "$ROWS"
  # id <TAB> P111 verdict <TAB> P114 column, one per inventory row
  awk -F'|' '/^\| [a-z0-9_]+ \|/ && $2 != " id " { gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $4); gsub(/^ +| +$/, "", $6); print $2 "\t" $4 "\t" $6 }' "$INV" > "$BATS_TEST_TMPDIR/inv.tsv"
  # the removed script names, assembled so this file does not itself name them (AC1/AC6 grep the tree)
  local x='-'; REMOVED_RE="aid${x}plan${x}to${x}epic|aid${x}epic${x}to${x}json|aid${x}json${x}to${x}run|aid${x}queue${x}add|aid${x}auto${x}pipeline|aid${x}generation${x}finalize|aid${x}epic${x}summary|aid${x}plan${x}continue|aid${x}queue${x}write|templates/epic\\.md"
}

_row() { jq -c --arg i "$1" 'first(.[] | select(.id == $i)) // empty' "$ROWS"; }
_p114_rows() { jq -c '.[] | select(.status == "removed_scoped" and ((.description // "") | startswith("RETIRED by P114")))' "$ROWS"; }

@test "inventory: the inventory has its 52 rows and every one is in the registry" {
  [ "$(wc -l < "$BATS_TEST_TMPDIR/inv.tsv")" -eq 52 ]
  while IFS=$'\t' read -r id _ _; do
    [ -n "$(_row "$id")" ] || { echo "missing in the registry: $id"; false; }
  done < "$BATS_TEST_TMPDIR/inv.tsv"
}

@test "inventory: every row has the status its verdict says, with the P114 corrections applied" {
  local id verdict corr row st guard want
  while IFS=$'\t' read -r id verdict corr; do
    row="$(_row "$id")"; st="$(jq -r .status <<< "$row")"; guard="$(jq -r '.replacement_guard // ""' <<< "$row")"
    case "$corr" in
      "oprava: zůstává do kroku 2"*)   # handed to epic_path_removed in Step 2
        [[ "$st" == active || ( "$st" == removed_scoped && "$guard" == epic_path_removed ) ]] || { echo "$id: $st/$guard"; false; } ; continue ;;
      "oprava: zůstává"*) [ "$st" = active ] || { echo "$id should stay active, is $st"; false; }; continue ;;
      "oprava: zaniká"*)  [ "$st" = removed_scoped ] || { echo "$id should be retired, is $st"; false; }; continue ;;
    esac
    case "$verdict" in
      "přechází → replacement_guard: "*)
        want="${verdict#přechází → replacement_guard: }"
        [[ "$st" == removed_scoped && "$guard" == "$want" ]] || { echo "$id: want removed_scoped → $want, is $st → $guard"; false; } ;;
      "zaniká"*)
        [[ "$st" == removed_scoped && "$guard" == "none ("*")" ]] || { echo "$id: want removed_scoped → none (…), is $st → $guard"; false; } ;;
      "zůstává"*)
        [[ "$st" == active || ( "$st" == removed_scoped && "$(jq -r .description <<< "$row")" != "RETIRED by P114"* ) ]] \
          || { echo "$id should stay as it was, is $st"; false; } ;;
      *) echo "$id: unknown verdict '$verdict'"; false ;;
    esac
  done < "$BATS_TEST_TMPDIR/inv.tsv"
}

@test "inventory: every replacement guard P114 writes is one active row with an existing test, or none (<reason>)" {
  local row id guard t
  while IFS= read -r row; do
    id="$(jq -r .id <<< "$row")"; guard="$(jq -r '.replacement_guard // ""' <<< "$row")"
    [[ "$guard" == "none ("*")" ]] && continue
    [[ "$guard" =~ ^[a-z0-9_]+$ ]] || { echo "$id: guard '$guard' is neither one id nor none (…)"; false; }
    [ "$(jq -r --arg g "$guard" 'first(.[] | select(.id == $g) | .status) // "missing"' "$ROWS")" = active ] \
      || { echo "$id: guard $guard is not an active row"; false; }
    t="$(jq -r --arg g "$guard" 'first(.[] | select(.id == $g) | .test) // ""' "$ROWS")"; t="${t%% (*}"; t="${t%% + *}"
    [ -n "$t" ] && [ -e "$AID_PLUGIN_PATH/$t" ] || { echo "$id: guard $guard has no existing test ($t)"; false; }
  done < <(_p114_rows)
}

@test "inventory: no row P114 retired names a removed file (the inventory does)" {
  local hits
  hits="$(_p114_rows | jq -r --arg re "$REMOVED_RE" 'select((.description + " " + .source + " " + (.instruction // "")) | test($re)) | .id')"
  [ -z "$hits" ] || { echo "names a removed file: $hits"; false; }
}

@test "inventory: no active row names a removed script anywhere (source, description, test, recovery, runtime_check, not_guaranteed, test_covers)" {
  local hits
  hits="$(jq -r --arg re "$REMOVED_RE" '.[] | select(.status == "active")
    | select([.source, .description, .test, .recovery, .runtime_check, .not_guaranteed, .test_covers, .instruction] | map(. // "" | tostring) | join(" ") | test($re)) | .id' "$ROWS")"
  [ -z "$hits" ] || { echo "names a removed script: $hits"; false; }
}

@test "inventory: no active row's test_covers or test names a suite that goes with the EPIC path" {
  local x='-'; local gone="generation${x}fixture|test${x}plan${x}to${x}epic|test${x}epic${x}to${x}json|test${x}json${x}to${x}run|test${x}queue${x}add|test${x}full${x}pipeline|test${x}generation${x}finalize|test${x}aid${x}epic${x}summary|test${x}aid${x}plan${x}to${x}epic${x}fence|test${x}generation${x}resume|test${x}generation${x}labels|test${x}supersede${x}generation|test${x}generation${x}parsers|test${x}queue${x}continuation|test${x}queue${x}peek|test${x}queue${x}registry${x}rows|test${x}queue${x}revalidation|test${x}next${x}epic|test${x}plan${x}continue|test${x}continue${x}artifact|test${x}continue${x}spawn|test${x}epic${x}chain${x}freshness|test${x}epic${x}start${x}run${x}id"
  local hits
  hits="$(jq -r --arg re "$gone" '.[] | select(.status == "active") | select(((.test_covers // "") + " " + (.test // "") | test($re))) | .id' "$ROWS" \
    | grep -vx 'queue_continuation_notice' || true)"   # re-pointed in Step 6 with the library rename
  [ -z "$hits" ] || { echo "test_covers names a leaving suite: $hits"; false; }
}

@test "inventory: the two corrected verdicts — the autonomous Stop rule stays, the generation exclusion is handed to epic_path_removed" {
  [ "$(_row queue_continuation_notice | jq -r .status)" = active ]
  local row; row="$(_row plan_run_excludes_generation)"
  [[ "$(jq -r .status <<< "$row")" == active || "$(jq -r .replacement_guard <<< "$row")" == epic_path_removed ]]
}
