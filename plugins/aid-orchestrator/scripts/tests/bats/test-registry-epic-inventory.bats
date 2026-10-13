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
  REMOVED_RE='aid-plan-to-epic|aid-epic-to-json|aid-json-to-run|aid-queue-add|aid-auto-pipeline|aid-generation-finalize|aid-epic-summary|aid-plan-continue|aid-queue-write|templates/epic\.md'
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
  local gone='generation-fixture|test-plan-to-epic|test-epic-to-json|test-json-to-run|test-queue-add|test-full-pipeline|test-generation-finalize|test-aid-epic-summary|test-aid-plan-to-epic-fence|test-generation-resume|test-generation-labels|test-supersede-generation|test-generation-parsers|test-queue-continuation|test-queue-peek|test-queue-registry-rows|test-queue-revalidation|test-next-epic|test-plan-continue|test-continue-artifact|test-continue-spawn|test-epic-chain-freshness|test-epic-start-run-id'
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
