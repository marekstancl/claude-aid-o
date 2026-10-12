#!/usr/bin/env bats
# aid-tier: t1
# P113a step 1 - aid-ui-critic.py: the critic's role is built from the type's rubric and the project's
# context and frozen; the prompt carries no threshold; the score is a weighted mean the script computes;
# the closing verdict needs the median, no low rating and no low criterion.

setup() {
  C="$BATS_TEST_DIRNAME/../../aid-ui-critic.py"
  P="$BATS_TEST_TMPDIR/p"; mkdir -p "$P/docs/content" "$P/site"
  printf '# Pekárna U Mlýna\nKváskový chleba v Brně, otevřeno denně od 6.\n' > "$P/docs/content/product-context.md"
  echo '<html lang="cs"><body>x</body></html>' > "$P/site/index.html"
}
# answer <score for every criterion> [jq edit]
answer() {
  python3 - "$1" > "$BATS_TEST_TMPDIR/a.json" <<'PY'
import sys, json, yaml, os
s = int(sys.argv[1]); r = yaml.safe_load(open(os.environ["RUB"]))
anchor = lambda x: max(a for a in (4, 6, 8, 10) if a <= x) if x >= 4 else 4
print(json.dumps({"criteria": [{"id": c["id"], "score": s, "anchor": anchor(s), "evidence": "úvod: nadpis a fotka pece",
  "missing_for_next": "více obrazu"} for c in r["criteria"]], "findings": [{"id": "f1", "criterion": "copy", "severity": "minor",
  "owner": "agent", "text": "opakované slovo", "fix": "zkrátit"}], "readiness": [{"item": "vlastní fotky"}], "summary": "Solidní web, chybí nálada."}))
PY
  [ -z "${2:-}" ] || { jq "$2" "$BATS_TEST_TMPDIR/a.json" > "$BATS_TEST_TMPDIR/b.json" && mv "$BATS_TEST_TMPDIR/b.json" "$BATS_TEST_TMPDIR/a.json"; }
}
export RUB="$BATS_TEST_DIRNAME/../../../skills/ui-design/critic/web-local.yaml"

@test "freeze builds the role from the rubric and the project context; never rewritten without --force; an edit is caught" {
  run python3 "$C" freeze "$P" --type web-local; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.type == "web-local" and (.sha256 | length) == 64 and (.role | contains("Pekárna U Mlýna")) and (.role | contains("first_impression"))' "$P/.aid-ui/critic/frozen.json" >/dev/null
  run python3 "$C" freeze "$P" --type web-local; [ "$status" -eq 1 ]; [[ "$output" == *"does not move"* ]]
  run python3 "$C" freeze "$P" --type nic; [ "$status" -eq 1 ] || [ "$status" -eq 2 ]
  jq '.role += " a buď mírný"' "$P/.aid-ui/critic/frozen.json" > "$P/f.t" && mv "$P/f.t" "$P/.aid-ui/critic/frozen.json"
  run python3 "$C" prompt "$P"; [ "$status" -eq 1 ]; [[ "$output" == *"edited after freezing"* ]]
}

@test "the prompt names no threshold and no acceptance; another project gets another role" {
  python3 "$C" freeze "$P" --type web-local >/dev/null
  run python3 "$C" prompt "$P"; [ "$status" -eq 0 ]
  ! grep -qiE "8/10|akcept|prah|threshold|accept" <<<"$output"
  grep -q "Nepočítej žádnou celkovou známku" <<<"$output"
  Q="$BATS_TEST_TMPDIR/q"; mkdir -p "$Q/docs/content"; printf '# Kadeřnictví Vlna\nStřih v Olomouci.\n' > "$Q/docs/content/product-context.md"
  python3 "$C" freeze "$Q" --type web-local >/dev/null
  [ "$(jq -r .sha256 "$P/.aid-ui/critic/frozen.json")" != "$(jq -r .sha256 "$Q/.aid-ui/critic/frozen.json")" ]
  jq -e '.role | contains("Kadeřnictví Vlna")' "$Q/.aid-ui/critic/frozen.json" >/dev/null
}

@test "score: weighted mean over assessable criteria, owners and readiness counted; invalid answers refused" {
  python3 "$C" freeze "$P" --type web-local >/dev/null
  answer 8; run python3 "$C" score "$P" "$BATS_TEST_TMPDIR/a.json"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.quality_score == 8 and .accepted == true and .findings_by_owner.agent == 1 and .readiness == ["vlastní fotky"]' <<<"$output" >/dev/null
  # first_impression 6 (weight 20) pulls the mean to 7.6 and the floor holds: not accepted
  answer 8 '(.criteria[] | select(.id == "first_impression")) |= (.score = 6 | .anchor = 6)'
  run python3 "$C" score "$P" "$BATS_TEST_TMPDIR/a.json"; jq -e '.quality_score == 7.6 and .accepted == false' <<<"$output" >/dev/null
  # one criterion 6 but a high mean: the floor of 7 refuses it
  answer 10 '(.criteria[] | select(.id == "accessibility")) |= (.score = 6 | .anchor = 6)'
  run python3 "$C" score "$P" "$BATS_TEST_TMPDIR/a.json"; jq -e '.quality_score >= 9 and .min_criterion == 6 and .accepted == false' <<<"$output" >/dev/null
  # not assessable: left out and the weights re-normalised; without a reason refused
  answer 8 '(.criteria[] | select(.id == "accessibility")) |= (.score = null | .anchor = null | .not_assessable = "bez čtečky nešlo ověřit")'
  run python3 "$C" score "$P" "$BATS_TEST_TMPDIR/a.json"; [ "$status" -eq 0 ]; jq -e '.quality_score == 8 and (.criteria | has("accessibility") | not)' <<<"$output" >/dev/null
  answer 8 '(.criteria[] | select(.id == "accessibility")) |= (.score = null | .anchor = null)'
  run python3 "$C" score "$P" "$BATS_TEST_TMPDIR/a.json"; [ "$status" -eq 1 ]; [[ "$output" == *"no score and no reason"* ]]
  answer 8 'del(.criteria[0])'; run python3 "$C" score "$P" "$BATS_TEST_TMPDIR/a.json"; [ "$status" -eq 1 ]; [[ "$output" == *"criteria answered"* ]]
  answer 8 '.criteria[0].score = 10'; run python3 "$C" score "$P" "$BATS_TEST_TMPDIR/a.json"; [ "$status" -eq 1 ]; [[ "$output" == *"does not sit on its anchor"* ]]
  answer 8 '.findings[0].owner = "studio"'; run python3 "$C" score "$P" "$BATS_TEST_TMPDIR/a.json"; [ "$status" -eq 1 ]; [[ "$output" == *"schema"* ]]
}

@test "verdict: median of blind ratings, no rating under 7.5, no criterion median under 7" {
  python3 "$C" freeze "$P" --type web-local >/dev/null
  for s in 8 9 8; do answer $s; cp "$BATS_TEST_TMPDIR/a.json" "$BATS_TEST_TMPDIR/r$s-$RANDOM.json"; done
  run python3 "$C" verdict "$P" "$BATS_TEST_TMPDIR"/r*.json; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.ratings == 3 and .median_quality_score == 8 and .accepted == true' <<<"$output" >/dev/null
  answer 7 '(.criteria[] | select(.id != "copy")) |= (.score = 7)'; cp "$BATS_TEST_TMPDIR/a.json" "$BATS_TEST_TMPDIR/r-low.json"
  run python3 "$C" verdict "$P" "$BATS_TEST_TMPDIR"/r*.json; [ "$status" -eq 3 ]; jq -e '.accepted == false and .lowest_rating < 7.5' <<<"$output" >/dev/null
}
