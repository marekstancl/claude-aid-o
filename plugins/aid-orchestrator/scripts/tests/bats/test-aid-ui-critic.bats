#!/usr/bin/env bats
# aid-tier: t1
# P113a step 1 - aid-ui-critic.py: the critic's role is built from the type's rubric and the project's
# context and frozen; the prompt carries no threshold; the score is a weighted mean the script computes;
# the closing verdict needs the median, no low rating and no low criterion. Two roles, owner and tech (13. 10. 2026),
# each with its own rubric; the ids come from the rubrics, which their authors own.

setup() {
  C="$BATS_TEST_DIRNAME/../../aid-ui-critic.py"
  P="$BATS_TEST_TMPDIR/p"; mkdir -p "$P/docs/content" "$P/site"
  printf '# Pekárna U Mlýna\nKváskový chleba v Brně, otevřeno denně od 6.\n' > "$P/docs/content/product-context.md"
  echo '<html lang="cs"><body>x</body></html>' > "$P/site/index.html"
}
# answer <score for every criterion> [jq edit]   (of the role in $ROLE)
answer() {
  ROLE="${ROLE:-owner}" python3 - "$1" > "$BATS_TEST_TMPDIR/a.json" <<'PY'
import sys, json, yaml, os
s = int(sys.argv[1]); r = yaml.safe_load(open(os.environ["K"] + "/web-local." + os.environ.get("ROLE", "owner") + ".yaml"))
lo = (yaml.safe_load(open(os.environ["K"] + "/web-local.yaml")).get("launch_only") or {}).get(os.environ.get("ROLE", "owner")) or []
r["criteria"] = [c for c in r["criteria"] if c["id"] not in lo]
anchor = lambda x: max(a for a in (4, 6, 8, 10) if a <= x) if x >= 4 else None
print(json.dumps({"criteria": [{"id": c["id"], "score": s, "anchor": anchor(s), "evidence": "úvod: nadpis a fotka pece",
  "missing_for_next": "více obrazu", "to_ten": {"studio": ["úvod: vlastní fotka ordinace přes celou šířku"] if s < 10 else [], "client": []}} for c in r["criteria"]], "findings": [{"id": "f1", "criterion": r["criteria"][0]["id"], "severity": "minor",
  "owner": "agent", "text": "opakované slovo", "fix": "zkrátit", "where": "úvod, druhý odstavec"}], "readiness": [{"item": "vlastní fotky"}], "summary": "Solidní web, chybí nálada."}))
PY
  [ -z "${2:-}" ] || { jq "$2" "$BATS_TEST_TMPDIR/a.json" > "$BATS_TEST_TMPDIR/b.json" && mv "$BATS_TEST_TMPDIR/b.json" "$BATS_TEST_TMPDIR/a.json"; }
}
export K="$BATS_TEST_DIRNAME/../../../skills/ui-design/critic"
first() { yq -r '.criteria[0].id' "$K/web-local.${ROLE:-owner}.yaml"; }
score() { python3 "$C" score "$P" "$BATS_TEST_TMPDIR/a.json" --role "${ROLE:-owner}"; }

@test "freeze builds both roles from their rubrics and the project context; never rewritten without --force; an edit is caught" {
  run python3 "$C" freeze "$P" --type web-local; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  F="$P/.aid-ui/critic/frozen.json"
  jq -e --arg o "$(ROLE=owner first)" --arg t "$(ROLE=tech first)" '.type == "web-local" and (.sha256 | length) == 64
     and (.roles.owner.role | contains("Pekárna U Mlýna") and contains($o)) and (.roles.tech.role | contains($t) and (contains($o) | not))
     and (.roles.owner.sha256 != .roles.tech.sha256) and (.rubric.task_test | length) > 0 and .rubric.persona.who == .roles.owner.rubric.persona.who' "$F" >/dev/null
  run python3 "$C" freeze "$P" --type web-local; [ "$status" -eq 1 ]; [[ "$output" == *"does not move"* ]]
  run python3 "$C" freeze "$P" --type nic; [ "$status" -eq 1 ] || [ "$status" -eq 2 ]
  run python3 "$C" prompt "$P"; [ "$status" -eq 2 ]   # a role is always named
  jq '.roles.tech.role += " a buď mírný"' "$F" > "$P/f.t" && mv "$P/f.t" "$F"
  run python3 "$C" prompt "$P" --role owner; [ "$status" -eq 1 ]; [[ "$output" == *"edited after freezing"* ]]
  # the schema is frozen with the roles: an edit of the stored schema is caught too
  python3 "$C" freeze "$P" --type web-local --force >/dev/null
  jq '.schema.required = ["summary"]' "$F" > "$P/f.t" && mv "$P/f.t" "$F"
  run python3 "$C" prompt "$P" --role tech; [ "$status" -eq 1 ]; [[ "$output" == *"edited after freezing"* ]]
  # a frozen critic of the one-role days is refused, not used
  python3 "$C" freeze "$P" --type web-local --force >/dev/null
  jq 'del(.roles) | .sha256 = "x"' "$F" > "$P/f.t" && mv "$P/f.t" "$F"
  run python3 "$C" prompt "$P" --role owner; [ "$status" -eq 1 ]; [[ "$output" == *"predates the two roles"* ]]
  # --force is refused once a loop has rounds
  mkdir -p "$P/.aid-ui/critic/rounds/r1"
  run python3 "$C" freeze "$P" --type web-local --force; [ "$status" -eq 1 ]; [[ "$output" == *"cannot change under it"* ]]
}

@test "phase: before the deployment the launch-only criteria are out of the role, the prompt and the score; at launch they are in" {
  lo="$(yq -r '.launch_only.tech[0]' "$K/web-local.yaml")"; [ -n "$lo" ] && [ "$lo" != null ]
  python3 "$C" freeze "$P" --type web-local >/dev/null
  jq -e --arg lo "$lo" '.phase == "build" and ([.roles.tech.rubric.criteria[].id] | index($lo)) == null and (.roles.tech.role | contains("Fáze: stavba"))' "$P/.aid-ui/critic/frozen.json" >/dev/null
  ROLE=tech; answer 9; run score; [ "$status" -eq 0 ] || { echo "$output"; return 1; }; jq -e --arg lo "$lo" '.criteria | has($lo) | not' <<<"$output" >/dev/null
  python3 "$C" freeze "$P" --type web-local --phase launch --force >/dev/null
  jq -e --arg lo "$lo" '.phase == "launch" and ([.roles.tech.rubric.criteria[].id] | index($lo)) != null and (.roles.tech.role | contains("Fáze: stavba") | not)' "$P/.aid-ui/critic/frozen.json" >/dev/null
  run python3 "$C" freeze "$P" --type web-local --phase nic --force; [ "$status" -eq 2 ]
}

@test "freeze drops context lines that talk about scores or acceptance" {
  printf '# Pekárna U Mlýna\nMinule 7,5/10, cílem je projít akceptací.\nKváskový chleba.\n' > "$P/docs/content/product-context.md"
  run python3 "$C" freeze "$P" --type web-local; [ "$status" -eq 0 ]; [[ "$output" == *"DROPPED 1"* ]]
  jq -e '(.roles.owner.role | contains("Kváskový")) and (.roles.tech.role | contains("7,5") | not)' "$P/.aid-ui/critic/frozen.json" >/dev/null
}

@test "the prompt names no threshold and no acceptance, carries the memory rules; another project gets another role" {
  python3 "$C" freeze "$P" --type web-local >/dev/null
  for r in owner tech; do
    run python3 "$C" prompt "$P" --role $r; [ "$status" -eq 0 ]
    ! grep -qiE "8/10|8,5|akcept|prah|threshold|accept" <<<"$output"
    grep -q "Nepočítej žádnou celkovou známku" <<<"$output"; grep -q "regression_of" <<<"$output"
  done
  Q="$BATS_TEST_TMPDIR/q"; mkdir -p "$Q/docs/content"; printf '# Kadeřnictví Vlna\nStřih v Olomouci.\n' > "$Q/docs/content/product-context.md"
  python3 "$C" freeze "$Q" --type web-local >/dev/null
  [ "$(jq -r .sha256 "$P/.aid-ui/critic/frozen.json")" != "$(jq -r .sha256 "$Q/.aid-ui/critic/frozen.json")" ]
  jq -e '.roles.owner.role | contains("Kadeřnictví Vlna")' "$Q/.aid-ui/critic/frozen.json" >/dev/null
}

@test "score: weighted mean over assessable criteria, accepted from 8.5 with no criterion under 7; invalid answers refused" {
  python3 "$C" freeze "$P" --type web-local >/dev/null
  for ROLE in owner tech; do
    answer 9; run score; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    jq -e '.quality_score == 9 and .accepted == true and .findings_by_owner.agent == 1 and .readiness == ["vlastní fotky"]' <<<"$output" >/dev/null
    answer 8; run score; jq -e '.quality_score == 8 and .accepted == false' <<<"$output" >/dev/null   # 8 is under 8.5
    # one criterion 6 but a high mean: the floor of 7 refuses it
    answer 10 '(.criteria[0]) |= (.score = 6 | .anchor = 6 | .to_ten.studio = ["úvod: vlastní fotka ordinace přes celou šířku"])'
    run score; jq -e '.quality_score >= 9 and .min_criterion == 6 and .accepted == false' <<<"$output" >/dev/null
    # not assessable: left out and the weights re-normalised; without a reason refused
    answer 9 '(.criteria[0]) |= (.score = null | .anchor = null | .not_assessable = "nešlo ověřit")'
    run score; [ "$status" -eq 0 ]; jq -e --arg f "$(first)" '.quality_score == 9 and (.criteria | has($f) | not)' <<<"$output" >/dev/null
    answer 8 '(.criteria[0]) |= (.score = null | .anchor = null)'; run score; [ "$status" -eq 1 ]; [[ "$output" == *"not_assessable"* ]]
  done
  ROLE=owner
  answer 8 'del(.criteria[0])'; run score; [ "$status" -eq 1 ]; [[ "$output" == *"criteria answered"* ]]
  answer 8 '.criteria[0].score = 10'; run score; [ "$status" -eq 1 ]; [[ "$output" == *"does not sit on its anchor"* ]]
  answer 8 '.criteria[1] |= (.score = 2 | .anchor = 10)'; run score; [ "$status" -eq 1 ]; [[ "$output" == *"does not sit on its anchor"* ]]
  answer 3; run score; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  answer 8 'del(.findings[0].where)'; run score; [ "$status" -eq 1 ]; [[ "$output" == *"where"* ]]
  answer 8 '.criteria[0].not_assessable = "nešlo"'; run score; [ "$status" -eq 1 ]; [[ "$output" == *"schema"* ]]
  answer 8 '.criteria[0].missing_for_next = ""'; run score; [ "$status" -eq 1 ]
  answer 8 '.findings[0].owner = "studio"'; run score; [ "$status" -eq 1 ]; [[ "$output" == *"schema"* ]]
  # the path to 10 is required below 10
  answer 8 '.criteria[0].to_ten = {"studio": [], "client": []}'; run score; [ "$status" -eq 1 ]; [[ "$output" == *"no step to 10"* ]]
  answer 10; run score; [ "$status" -eq 0 ]
  # two scores where an open client item holds the criterion down: the loop counts the studio's, quality_now the web as it is
  answer 9 '.criteria[0] |= (.score = 5 | .anchor = 4 | .studio_score = 9 | .studio_anchor = 8 | .limited_by = ["oi-4"] | .to_ten.client = ["vlastné fotky lekára a tímu"])'
  run score; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.quality_score == 9 and .quality_now < 9 and .min_criterion == 9 and .limited_by == ["oi-4"] and .accepted == true' <<<"$output" >/dev/null
  answer 9 '.criteria[0] |= (.studio_score = 9 | .studio_anchor = 8)'; run score; [ "$status" -eq 1 ]; [[ "$output" == *"schema"* ]]   # no limited_by
  answer 9 '.criteria[0] |= (.score = 5 | .anchor = 4 | .studio_score = 9 | .studio_anchor = 8 | .limited_by = ["oi-4"])'; run score; [ "$status" -eq 1 ]; [[ "$output" == *"to_ten.client"* ]]
  answer 10 '.criteria[0].to_ten.studio = ["úvod: ještě jedna fotka navíc"]'; run score; [ "$status" -eq 1 ]; [[ "$output" == *"to_ten must be empty"* ]]
  answer 9 '.criteria[0] |= (.score = 9 | .studio_score = 6 | .studio_anchor = 6 | .limited_by = ["oi-4"] | .to_ten.client = ["vlastné fotky lekára"])'; run score; [ "$status" -eq 1 ]; [[ "$output" == *"under score"* ]]
  answer 9 '.criteria[0] |= (.score = 5 | .anchor = 4 | .studio_score = 9 | .studio_anchor = 6 | .limited_by = ["oi-4"] | .to_ten.client = ["vlastné fotky lekára"])'; run score; [ "$status" -eq 1 ]; [[ "$output" == *"studio_score 9 does not sit"* ]]
  answer 8 '.findings[0].regression_of = "r1-owner-f2"'; run score; [ "$status" -eq 0 ]   # the field is allowed; the client checks the id
  # a tech criterion in an owner answer is refused
  answer 8 ".findings[0].criterion = \"$(ROLE=tech first)\""; run score; [ "$status" -eq 1 ]; [[ "$output" == *"unknown criterion"* ]]
}

@test "verdict: median of three blind ratings of one role, none under 8, no criterion median under 7" {
  python3 "$C" freeze "$P" --type web-local >/dev/null
  ROLE=tech
  for s in 9 9 8; do answer $s; cp "$BATS_TEST_TMPDIR/a.json" "$BATS_TEST_TMPDIR/r$s-$RANDOM.json"; done
  run python3 "$C" verdict "$P" --role tech "$BATS_TEST_TMPDIR"/r*.json; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.role == "tech" and .ratings == 3 and .median_quality_score == 9 and .accepted == true and .publish_blocked_by == ["vlastní fotky"] and (.verdict | startswith("přijato, zveřejnění blokuje"))' <<<"$output" >/dev/null
  run python3 "$C" verdict "$P" --role tech "$BATS_TEST_TMPDIR"/r9-*.json; [ "$status" -eq 1 ]; [[ "$output" == *"exactly 3"* ]]
  answer 7; cp "$BATS_TEST_TMPDIR/a.json" "$BATS_TEST_TMPDIR/r-low.json"; rm "$(ls "$BATS_TEST_TMPDIR"/r8-*.json)"
  run python3 "$C" verdict "$P" --role tech "$BATS_TEST_TMPDIR"/r*.json; [ "$status" -eq 3 ]; jq -e '.accepted == false and .lowest_rating < 8 and .verdict == "nepřijato"' <<<"$output" >/dev/null
}
