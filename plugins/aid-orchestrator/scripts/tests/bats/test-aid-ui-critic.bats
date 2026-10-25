#!/usr/bin/env bats
# aid-tier: t2
# Nightly since 3.4.0 (15. 10. 2026): the merge path overran its 10 min and the /aid-ui studio is the
# dearest area outside the core; no plan run passes through it, so a regression here shows the next morning.
# P113a step 1 - aid-ui-critic.py: the critic's role is built from the type's rubric and the project's
# context and frozen; the prompt carries no threshold; the score is a weighted mean the script computes;
# the closing verdict needs the median, no low rating and no low criterion. Two roles, owner and tech (13. 10. 2026),
# each with its own rubric; the ids come from the rubrics, which their authors own.

setup() {
  export P
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
lo = [] if os.environ.get("KEEP_LAUNCH") else (yaml.safe_load(open(os.environ["K"] + "/web-local.yaml")).get("launch_only") or {}).get(os.environ.get("ROLE", "owner")) or []
r["criteria"] = [c for c in r["criteria"] if c["id"] not in lo]
try:   # P113: the finished web is rated with the rubrics of the look and the structure too (prefixed ids)
    fz = json.load(open(os.environ["P"] + "/.aid-ui/critic/frozen.json"))
    r["criteria"] += [dict(c, id=e["key"] + "." + c["id"]) for e in fz["roles"][os.environ.get("ROLE", "owner")]["rubrics"][1:] for c in e["rubric"]["criteria"]]
except (OSError, KeyError):
    pass
anchor = lambda x: max(a for a in (4, 6, 8, 10) if a <= x) if x >= 4 else None
print(json.dumps({"criteria": [{"id": c["id"], "score": s, "anchor": anchor(s), "evidence": "úvod: nadpis a fotka pece",
  "missing_for_next": "více obrazu", "to_ten": {"studio": ["úvod: vlastní fotka ordinace přes celou šířku"] if s < 10 else [], "client": []}} for c in r["criteria"]], "findings": [{"id": "f1", "criterion": r["criteria"][0]["id"], "severity": "minor",
  "owner": "agent", "kind": "remeslo", "blocking": False, "text": "opakované slovo", "fix": "zkrátit", "where": "úvod, druhý odstavec"}], "readiness": [{"item": "vlastní fotky"}], "summary": "Solidní web, chybí nálada."}))
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
  # at launch the criterion is answered and counted, and an answer without it is refused
  KEEP_LAUNCH=1 answer 9 "(.criteria[] | select(.id == \"$lo\")) |= (.score = 5 | .anchor = 4)"; run score; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e --arg lo "$lo" '.criteria[$lo] == 5 and .accepted == false' <<<"$output" >/dev/null
  answer 9; run score; [ "$status" -eq 1 ]; [[ "$output" == *"criteria answered"* ]]
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

# ---------------------------------------------------------------- P113 step 2: gates at the decision places
# mk <place> <role> <score> [jq edit] -> $BATS_TEST_TMPDIR/<role>.json: every criterion of the frozen place at <score>;
# DIRS="a b" gives one direction per id (logo, motion, look), each with rezim from REZIM (default nove)
mk() {
  python3 - "$1" "$2" "$3" > "$BATS_TEST_TMPDIR/$2.json" <<'PY'
import json, os, sys
place, role, s = sys.argv[1], sys.argv[2], int(sys.argv[3])
fz = json.load(open(os.environ["P"] + "/.aid-ui/critic/" + ("frozen.json" if place == "web" else "frozen/%s.json" % place)))
ids = [("" if e["key"] == place else e["key"] + ".") + c["id"] for e in fz["roles"][role]["rubrics"] for c in e["rubric"]["criteria"]]
anc = lambda x: None if x < 4 else max(a for a in (4, 6, 8, 10) if a <= x)
crit = [{"id": i, "score": s, "anchor": anc(s), "evidence": "karta směru, značka 512 px", "missing_for_next": "detail",
         "to_ten": {"studio": ["karta: dokreslit vlastní detail do značky"] if s < 10 else [], "client": []}} for i in ids]
a = {"findings": [], "readiness": [], "summary": "Hodnocení místa pro test."}
dirs = os.environ.get("DIRS", "").split()
if dirs:
    a["directions"] = [{"id": d, "rezim": os.environ.get("REZIM", "nove"), "zavedeny_motiv": "ne", "criteria": crit} for d in dirs]
else:
    a["criteria"] = crit
print(json.dumps(a, ensure_ascii=False))
PY
  [ -z "${4:-}" ] || { jq "$4" "$BATS_TEST_TMPDIR/$2.json" > "$BATS_TEST_TMPDIR/x.json" && mv "$BATS_TEST_TMPDIR/x.json" "$BATS_TEST_TMPDIR/$2.json"; }
}
sc() { python3 "$C" score "$P" "$BATS_TEST_TMPDIR/$2.json" --role "$2" --place "$1" ${3:+--metrics-dir "$3"}; }
st() { jq -r --arg d "$1" --arg r "${2:-}" '[.directions[] | select(.direction == $d and ($r == "" or .rubric == $r)) | .status] | join(",")'; }
logo_inputs() { mkdir -p "$P/.aid-ui/logo/cards"; for d in "$@"; do printf '%s' "$d" > "$P/.aid-ui/logo/cards/$d.png"; done; }
verdict_of() {   # verdict_of <place> [args]: both roles' scores of $T/owner.json and $T/tech.json -> place-verdict
  local pl="$1"; shift
  sc "$pl" owner > "$BATS_TEST_TMPDIR/so.json" && sc "$pl" tech > "$BATS_TEST_TMPDIR/st.json" &&
    python3 "$C" place-verdict "$P" --place "$pl" --score "$BATS_TEST_TMPDIR/so.json" --score "$BATS_TEST_TMPDIR/st.json" "$@"
}

@test "gates: when nove|oziveni|zavedeny_motiv pick the logo gates by the role's own mode; a when gate without the mode fails" {
  python3 "$C" freeze "$P" --type web-local --place logo >/dev/null; logo_inputs a
  DIRS="a" mk logo tech 8 '(.directions[0].criteria[] | select(.id == "myslenka")) |= (.score = 6 | .anchor = 6)'
  run sc logo tech; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(st a <<<"$output")" = failed ]   # a new mark: idea under 7
  jq -e '[.directions[0].gates[] | select(.ok == false) | .gate] == ["myslenka >= 7 when nove"]' <<<"$output" >/dev/null
  DIRS="a" REZIM=oziveni mk logo tech 8 '(.directions[0].criteria[] | select(.id == "myslenka")) |= (.score = 6 | .anchor = 6)'
  run sc logo tech; [ "$(st a <<<"$output")" = accepted ]   # a revival keeps its motif at 6, odlisnost 8 shows the own detail
  DIRS="a" mk logo tech 8 'del(.directions[0].rezim)'
  run sc logo tech; [ "$(st a <<<"$output")" = failed ]; [[ "$output" == *"role neuvedla režim"* ]]
  DIRS="a" mk logo tech 8 '.directions[0].zavedeny_motiv = "ano" | (.directions[0].criteria[] | select(.id == "navaznost_trvanlivost")) |= (.score = 5 | .anchor = 4)'
  run sc logo tech; [ "$(st a <<<"$output")" = failed ]   # an established motif: continuity under 6
}

@test "gates: any_of lets a revival through only with its own detail; a 6/6 redraw fails although its weighted mean passes" {
  python3 "$C" freeze "$P" --type web-local --place logo >/dev/null; logo_inputs a
  DIRS="a" REZIM=oziveni mk logo tech 8 '(.directions[0].criteria[] | select(.id == "myslenka" or .id == "odlisnost")) |= (.score = 6 | .anchor = 6)'
  run sc logo tech; [ "$(st a <<<"$output")" = failed ]
  jq -e '[.directions[0].gates[] | select(.ok == false) | .gate] == ["any_of myslenka|odlisnost >= 7 when oziveni"] and .directions[0].weighted >= 7' <<<"$output" >/dev/null
  DIRS="a" REZIM=oziveni mk logo tech 8 '(.directions[0].criteria[] | select(.id == "myslenka")) |= (.score = 6 | .anchor = 6) | (.directions[0].criteria[] | select(.id == "odlisnost")) |= (.score = 7 | .anchor = 6)'
  run sc logo tech; [ "$(st a <<<"$output")" = accepted ]
  # none of the any_of criteria assessable -> the gate fails
  DIRS="a" REZIM=oziveni mk logo tech 8 '(.directions[0].criteria[] | select(.id == "myslenka" or .id == "odlisnost")) |= (.score = null | .anchor = null | .not_assessable = "nejde posoudit")'
  run sc logo tech; [ "$(st a <<<"$output")" = failed ]; [[ "$output" == *"žádné kritérium nešlo posoudit"* ]]
}

@test "gates: weighted_min holds a direction whose every criterion passes its own gate" {
  python3 "$C" freeze "$P" --type web-local --place struktura >/dev/null; mkdir -p "$P/.aid-ui"; echo '{"pages": []}' > "$P/.aid-ui/structure.json"
  mk struktura tech 7; run sc struktura tech; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.directions[0].status == "failed" and ([.directions[0].gates[] | select(.ok == false) | .gate] == ["weighted >= 7.5"])' <<<"$output" >/dev/null
  mk struktura tech 8; run sc struktura tech; jq -e '.directions[0].status == "accepted" and .accepted == true' <<<"$output" >/dev/null
}

@test "gates (IMP-702): a required gate over facts or law fails when its criterion was not assessed; another gate is skipped; required is a bool" {
  python3 "$C" freeze "$P" --type web-local --place struktura >/dev/null; mkdir -p "$P/.aid-ui"; echo '{"pages": []}' > "$P/.aid-ui/structure.json"
  mk struktura tech 8 '(.criteria[] | select(.id == "pojmy_konvence_oboru")) |= (.score = null | .anchor = null | .not_assessable = "nejde posoudit")'
  run sc struktura tech; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.directions[0].status == "failed" and ([.directions[0].gates[] | select(.ok == false) | .why] == ["kritérium nešlo posoudit; tuto bránu nejde přeskočit"])' <<<"$output" >/dev/null
  mk struktura tech 8 '(.criteria[] | select(.id == "inventura_presun")) |= (.score = null | .anchor = null | .not_assessable = "bez předchůdce")'
  run sc struktura tech; jq -e '.directions[0].status == "accepted"' <<<"$output" >/dev/null   # not required: skipped as before
  printf 'gates:\n  - {criterion: a, min: 6, required: "ano", why: x}\n' > "$BATS_TEST_TMPDIR/g.yaml"
  run python3 - "$C" "$BATS_TEST_TMPDIR/g.yaml" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("c", sys.argv[1]); c = importlib.util.module_from_spec(s); s.loader.exec_module(c)
c.load_gates(sys.argv[2], ["a"])
PY
  [ "$status" -eq 2 ]; [[ "$output" == *"required is true or false"* ]]
}

@test "gates: motion metrics - a missing measurement fails, an animation over the limit fails, a measured one within passes" {
  python3 "$C" freeze "$P" --type web-local --place pohyb >/dev/null; mkdir -p "$P/.aid-ui/motion/v1"; echo '<html></html>' > "$P/.aid-ui/motion/v1/logo-animace.html"
  M="$BATS_TEST_TMPDIR/m"; mkdir -p "$M"
  DIRS="v1" mk pohyb tech 8; run sc pohyb tech "$M"; [ "$(st v1 <<<"$output")" = failed ]; [[ "$output" == *"nezměřeno"* ]]
  echo '{"web_logo_draw_ms": 2060, "web_logo_name_visible_ms": 0, "web_motion_running_after_ms": 400, "final_frame_diff_px": 0}' > "$M/metrics-pohyb-v1.json"
  run sc pohyb tech "$M"; [ "$(st v1 <<<"$output")" = failed ]
  jq -e '[.directions[0].metrics[] | select(.ok == false) | .metric] == ["web_logo_draw_ms"]' <<<"$output" >/dev/null
  echo '{"web_logo_draw_ms": 900, "web_logo_name_visible_ms": 0, "web_motion_running_after_ms": 400, "final_frame_diff_px": 0}' > "$M/metrics-pohyb-v1.json"
  run sc pohyb tech "$M"; [ "$(st v1 <<<"$output")" = accepted ]
  echo '{"not_applicable": true}' > "$M/metrics-pohyb-v1.json"
  run sc pohyb tech "$M"; [ "$(st v1 <<<"$output")" = failed ]; [[ "$output" == *"bez pohybu"* ]]   # only the place's without record waives it
}

@test "gates: a reservation only when the client's part holds the gate (studio_score + to_ten.client); a volba finding is no reservation" {
  python3 "$C" freeze "$P" --type web-local --place vzhled >/dev/null; mkdir -p "$P/.aid-ui/directions/a"; echo '<html></html>' > "$P/.aid-ui/directions/a/index.html"
  hold='(.directions[0].criteria[] | select(.id == "moje_obrazky_a_zakazky")) |= (.score = 5 | .anchor = 4 | .studio_score = 8 | .studio_anchor = 8 | .limited_by = ["oi-1"] | .to_ten.client = ["vlastní fotky provozovny a lidí"])'
  DIRS="a" mk vzhled owner 8 "$hold"; run sc vzhled owner; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.directions[0].status == "reservation" and .directions[0].reservation == ["moje_obrazky_a_zakazky"] and .accepted == true' <<<"$output" >/dev/null
  # the studio's own part under the gate too: failed, not a reservation
  DIRS="a" mk vzhled owner 8 '(.directions[0].criteria[] | select(.id == "moje_obrazky_a_zakazky")) |= (.score = 5 | .anchor = 4 | .studio_score = 6 | .studio_anchor = 6 | .limited_by = ["oi-1"] | .to_ten.client = ["vlastní fotky provozovny a lidí"])'
  run sc vzhled owner; [ "$(st a <<<"$output")" = failed ]
  # the client's taste on the failing criterion: never a reservation
  DIRS="a" mk vzhled owner 8 "$hold"' | .findings = [{"id": "v1", "criterion": "moje_obrazky_a_zakazky", "severity": "major", "owner": "client", "kind": "volba", "direction": "a", "text": "chci jiné fotky", "fix": "jiné fotky", "where": "úvod"}]'
  run sc vzhled owner; [ "$(st a <<<"$output")" = failed ]
}

@test "gates: D5 - a fact returns the place, a blocking craft defect takes its direction out, the client chooses among the rest" {
  python3 "$C" freeze "$P" --type web-local --place logo >/dev/null
  mkdir -p "$P/docs/content"; logo_inputs a b
  DIRS="a b" mk logo owner 8 '.choice = "a"'; DIRS="a b" mk logo tech 8
  run verdict_of logo; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.status == "accepted" and .chosen == "a" and .chosen_by == "client" and (.target | length) == 64' <<<"$output" >/dev/null
  # the expert's blocking craft defect on a: a is out, the client's choice of a is refused (exit 3), b remains
  DIRS="a b" mk logo tech 8 '.findings = [{"id": "t1", "criterion": "remeslo_tvaru", "severity": "blocking", "owner": "agent", "kind": "remeslo", "blocking": true, "direction": "a", "text": "kóta přes obrys", "fix": "odsadit", "where": "značka 512"}]'
  run verdict_of logo; [ "$status" -eq 3 ]; jq -e '.error == "client_choice_failed" and .passing == ["b"]' <<<"$output" >/dev/null
  DIRS="a b" mk logo owner 8 '.choice = "b"'; run verdict_of logo; jq -e '.status == "accepted" and .chosen == "b"' <<<"$output" >/dev/null
  # a fact without a direction (the whole place): returned whatever the scores
  DIRS="a b" mk logo tech 8 '.findings = [{"id": "t2", "criterion": "typografie", "severity": "major", "owner": "agent", "kind": "fakt", "blocking": true, "text": "rok založení na značce nesedí", "fix": "opravit", "where": "logo s názvem"}]'
  run verdict_of logo; [ "$status" -eq 0 ]; jq -e '.status == "returned" and (.blocked_by | map(.kind) | index("fakt")) != null' <<<"$output" >/dev/null
  # both roles report the same fact: listed once
  DIRS="a b" mk logo owner 8 '.choice = "b" | .findings = [{"id": "o2", "criterion": "muj_podnik", "severity": "major", "owner": "agent", "kind": "fakt", "blocking": true, "text": "rok založení na značce nesedí", "fix": "opravit", "where": "logo"}]'
  run verdict_of logo; [ "$(jq '[.blocked_by[] | select(.kind == "fakt")] | length' <<<"$output")" -eq 1 ]
}

@test "gates: every role rates every direction of the bundle - a missing or made-up direction is refused" {
  python3 "$C" freeze "$P" --type web-local --place logo >/dev/null; logo_inputs a b
  DIRS="a" mk logo tech 8; run sc logo tech; [ "$status" -eq 1 ]; [[ "$output" == *"bundle has ['a', 'b']"* ]]
  DIRS="a b x" mk logo tech 8; run sc logo tech; [ "$status" -eq 1 ]
  # the expert left the flag out (Trading 22. 10.): its own severity says it - blocking takes the direction out, major does not
  DIRS="a b" mk logo owner 8 '.choice = "a"'
  DIRS="a b" mk logo tech 8 '.findings = [{"id": "t1", "criterion": "remeslo_tvaru", "severity": "blocking", "owner": "agent", "kind": "remeslo", "direction": "a", "text": "kóta přes obrys", "fix": "odsadit", "where": "značka 512"}]'
  run verdict_of logo; [ "$status" -eq 3 ]; jq -e '.passing == ["b"]' <<<"$output" >/dev/null
  DIRS="a b" mk logo tech 8 '.findings = [{"id": "t1", "criterion": "remeslo_tvaru", "severity": "major", "owner": "agent", "kind": "remeslo", "direction": "a", "text": "kóta přes obrys", "fix": "odsadit", "where": "značka 512"}]'
  run verdict_of logo; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  # a craft finding without blocking: true does not take the direction out
  DIRS="a b" mk logo owner 8 '.choice = "a"'
  DIRS="a b" mk logo tech 8 '.findings = [{"id": "t1", "criterion": "remeslo_tvaru", "severity": "blocking", "owner": "agent", "kind": "remeslo", "blocking": false, "direction": "a", "text": "drobná nerovnost", "fix": "srovnat", "where": "značka 512"}]'
  run verdict_of logo; [ "$status" -eq 0 ]; jq -e '.chosen == "a" and .status == "accepted"' <<<"$output" >/dev/null
  # a finding without kind is not a valid answer
  DIRS="a b" mk logo tech 8 '.findings = [{"id": "t1", "criterion": "remeslo_tvaru", "severity": "major", "owner": "agent", "direction": "a", "text": "x", "fix": "srovnat", "where": "značka 512"}]'
  run sc logo tech; [ "$status" -eq 1 ]; [[ "$output" == *"kind"* ]]
}

@test "gates: the client cannot pick a direction that failed the client's own gate" {
  python3 "$C" freeze "$P" --type web-local --place logo >/dev/null
  logo_inputs a b
  DIRS="a b" mk logo owner 8 '.choice = "a" | (.directions[0].criteria[] | select(.id == "muj_podnik")) |= (.score = 6 | .anchor = 6)'
  DIRS="a b" mk logo tech 8
  run verdict_of logo; [ "$status" -eq 3 ]; jq -e '.chosen == "a" and .passing == ["b"]' <<<"$output" >/dev/null
}

@test "gates: web needs all six scores - the look and structure rubrics at web use their places' gates; five of six is incomplete" {
  python3 "$C" freeze "$P" --type web-local >/dev/null
  mk web owner 9; mk web tech 9 '(.criteria[] | select(.id == "vzhled.proporce_vyvazeni")) |= (.score = 6 | .anchor = 6)'
  run sc web tech; [ "$status" -eq 0 ]
  jq -e '([.directions[] | select(.rubric == "web") | .status] == ["accepted"]) and ([.directions[] | select(.rubric == "vzhled") | .status] == ["failed"]) and .accepted == false' <<<"$output" >/dev/null
  sc web owner > "$BATS_TEST_TMPDIR/so.json"; sc web tech > "$BATS_TEST_TMPDIR/st.json"
  jq 'del(.directions[] | select(.rubric == "struktura"))' "$BATS_TEST_TMPDIR/st.json" > "$BATS_TEST_TMPDIR/st5.json"
  run python3 "$C" place-verdict "$P" --place web --score "$BATS_TEST_TMPDIR/so.json" --score "$BATS_TEST_TMPDIR/st5.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"incomplete_place"* ]]
  run python3 "$C" place-verdict "$P" --place web --score "$BATS_TEST_TMPDIR/so.json"; [ "$status" -eq 1 ]; [[ "$output" == *"incomplete_place"* ]]
}

@test "gates: --pm-choice (manual mode, the client's pick kept) and --pm-veto" {
  python3 "$C" freeze "$P" --type web-local --place logo >/dev/null
  logo_inputs a b
  DIRS="a b" mk logo owner 8 '.choice = "a"'; DIRS="a b" mk logo tech 8
  run verdict_of logo --pm-choice b; [ "$status" -eq 2 ]   # a PM choice says why
  run verdict_of logo --pm-choice b --reason "PM chce klidnější"; [ "$status" -eq 0 ]
  jq -e '.status == "accepted" and .chosen == "b" and .chosen_by == "pm" and .client_choice == "a"' <<<"$output" >/dev/null
  run verdict_of logo --pm-veto "zaměnitelné s konkurentem"; jq -e '.status == "returned" and .pm_veto != null and (.blocked_by | map(.kind) | index("veto")) != null' <<<"$output" >/dev/null
}

@test "gates: a mark the PM supplied (--supplied) failing a gate is returned to the PM with the findings" {
  python3 "$C" freeze "$P" --type web-local --place logo >/dev/null
  logo_inputs dodano
  DIRS="dodano" mk logo owner 8; DIRS="dodano" mk logo tech 8 '(.directions[0].criteria[] | select(.id == "jednoduchost_skala")) |= (.score = 2 | .anchor = null)'
  run verdict_of logo --supplied; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.status == "returned" and .supplied == true and .chosen_by == "pm" and .out.dodano != null' <<<"$output" >/dev/null
  DIRS="dodano" mk logo tech 8; run verdict_of logo --supplied; jq -e '.status == "accepted" and .chosen == "dodano"' <<<"$output" >/dev/null
}

@test "gates: the closing audit reads its thresholds from the web gate files' audit block" {
  python3 "$C" freeze "$P" --type web-local >/dev/null
  [ "$(yq -r '.audit.median_min' "$K/web-local.tech.web.gates.yaml")" = 8.5 ]
  for i in 1 2 3; do mk web tech 9; cp "$BATS_TEST_TMPDIR/tech.json" "$BATS_TEST_TMPDIR/au$i.json"; done
  run python3 "$C" verdict "$P" --role tech "$BATS_TEST_TMPDIR"/au*.json; [ "$status" -eq 0 ]; jq -e '.accepted and .other_rubrics_ok' <<<"$output" >/dev/null
  # the look rubric at web failing in the audit: not accepted although the web rubric's median passes
  mk web tech 9 '(.criteria[] | select(.id == "vzhled.kontrast_pristupnost")) |= (.score = 5 | .anchor = 4)'; cp "$BATS_TEST_TMPDIR/tech.json" "$BATS_TEST_TMPDIR/au1.json"
  run python3 "$C" verdict "$P" --role tech "$BATS_TEST_TMPDIR"/au*.json; [ "$status" -eq 3 ]; jq -e '.other_rubrics_ok == false' <<<"$output" >/dev/null
  ! grep -nE '^ACCEPT, ACCEPT_ANY, FLOOR = ' "$C"
}
