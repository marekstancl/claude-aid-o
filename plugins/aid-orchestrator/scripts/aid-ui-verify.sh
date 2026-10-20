#!/usr/bin/env bash
# =============================================================================
# aid-ui-verify.sh — the /aid-ui verification gate (step 7) on the recorded build.
#
#   aid-ui-verify.sh <project>
#   aid-ui-verify.sh <project> --precheck   (P116) a web application's skeleton (<project>/site) over the model now, before
#     any role round: the app rows (app_flows, app_states, keyboard_flows, task_recovery) with axe and keyboard, on the
#     unapproved model too; nothing recorded in the state; .aid-ui/precheck/result.json; exit 0 green, 3 open rows
#   aid-ui-verify.sh <project> --quick   (P118) the same rows at the widest app width only, after every edit (about a
#     minute); .aid-ui/quick/result.json; never taken by self or a round
#   aid-ui-verify.sh <project> --copy-subject <out.json>   (P108) serves the recorded build and writes
#     only the copy of every page for the copy review; the gate result in .aid-ui/verify stays untouched
#   aid-ui-verify.sh --package-gate <plan or brief> [--launch]   (P115) the run gate check_ui_handover:
#     aid-ui-package.py gate (see its header) - skipped for a plan without ui_package, else the package, the site,
#     the open items and, once docs/ui/nasazeni.json exists, the deployed files, the live form and the rows below
#   aid-ui-verify.sh <project> --base-url <url>   (P115) the rows over a live address: no local preview, no
#     build-id check, no gate-record; form_delivery is N/A (the run gate posts the live form). Result in
#     .aid-ui/verify-live/result.json + live.json {url, site_sha256, run_at}; exit 0 no open row, 3 open rows.
#
# 1. The recorded build (docs/design/brand-state.json .build): recomputes the build id of
#    its site directory with `aid-ui-state.sh build-id` and refuses (exit 1) when it
#    differs — the gate only ever tests the build that was recorded.
# 2. Serves the site with `aid-ui-serve.sh preview <dir>` (AID_UI_PREVIEW_PORT, 3917;
#    a port held by another process -> exit 1 naming it), stopped again on exit.
# 3. `aid-ui-tool.sh verify` (lib/ui-fidelity/aid-ui-verify.mjs): every check of
#    checks.yaml (next to the coverage map; AID_UI_COVERAGE_MAP) over pages x viewports x
#    browsers (x flows x states x roles for an app) -> <project>/.aid-ui/verify/result.json
#    and full-page screenshots under .aid-ui/verify/shots/. A browser that cannot launch
#    (WebKit not installed) -> its rows not_covered with the install hint.
# 4. `aid-ui-state.sh gate-record <project> <result.json>`.
# A webapp (P116) first: `aid-ui-state.sh model-approved` (exit 1 on a model the PM did not approve or that changed
# since) and `aid-ui-flows.py generate` (the task scenarios from that model); its rows app_flows, app_states,
# keyboard_flows and task_recovery come from docs/design/screens.json (aid-ui-screens.py matrix).
#
# Inputs the checks read (all optional; missing -> the check's rows are not_covered):
# docs/content/facts.yaml, docs/content/tasks.yaml (P113a task test), docs/content/photos.yaml (P113a photo slots), docs/design/brand-package/, .aid-ui/scenarios/<flow id>.mjs,
# .aid-ui/test-credentials.json (test accounts only, never real ones), docs/seo/brief.md,
# DESIGN.md, docs/design/design-standard.md, docs/product-vision.md, docs/zakaznik/.
# Exit: 0 recorded with no open row, 3 recorded with open rows, 1 refused or failed, 2 usage.
# On the first run of step 7, design_standard_doc and customer_page are open by design
# (made in step 7 points 4 and 7b), so exit 3 is expected there.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COVERAGE_MAP="${AID_UI_COVERAGE_MAP:-$HERE/../skills/ui-design/coverage/map.yaml}"
die() { echo "ERROR: aid-ui-verify.sh: $1" >&2; exit 1; }

USAGE="usage: aid-ui-verify.sh <project> [--copy-subject <out.json> | --base-url <url> | --precheck | --quick] | --package-gate <plan> [--launch]"
TOOL="${AID_UI_TOOL:-$HERE/aid-ui-tool.sh}"   # tests point it at a stub (no browser on the merge path)
if [[ "${1:-}" == --package-gate ]]; then   # P115: the run gate; parsed before the <project> forms
  (( $# == 2 )) || { (( $# == 3 )) && [[ "$3" == --launch ]]; } || { echo "$USAGE" >&2; exit 2; }
  exec python3 "$HERE/aid-ui-package.py" gate "${@:2}"
fi
subject=""; live=""
if (( $# == 2 )) && [[ "$2" == --precheck || "$2" == --quick ]]; then   # P116: the app skeleton's own gate before any role round
  MODE="${2#--}"   # P118: --quick = the same rows at one width (the desktop), after every edit; never what self takes
  PROJECT="$(realpath "$1")"; STATE="$PROJECT/docs/design/brand-state.json"
  [[ "$(jq -r '.variant.type // ""' "$STATE" 2>/dev/null)" == webapp ]] || die "--$MODE is for a web application (variant.type webapp)"
  site="$PROJECT/site"; [[ -f "$site/index.html" ]] || die "no skeleton in $site (aid-ui-serve.sh skeleton <project>)"
  python3 "$HERE/aid-ui-flows.py" generate "$PROJECT" >/dev/null || die "the task scenarios could not be generated from docs/design/screens.json (see above)"
  OUT="$PROJECT/.aid-ui/$MODE"; rm -rf "$OUT"; mkdir -p "$OUT"; STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq --argjson b "$(bash "$HERE/aid-ui-state.sh" build-json "$site")" --arg d "$site" '.build = ($b + {dir: $d})' "$STATE" > "$OUT/state.json"
  yq -o=json . "$(dirname "$COVERAGE_MAP")/checks.yaml" | jq '.checks |= with_entries(select(.key | IN("app_flows", "app_states", "keyboard_flows", "task_recovery", "axe", "keyboard")))
    | .viewports = (.app_rows.viewports // .viewports) | .browsers = (.app_rows.browsers // .browsers)
    | if $q then .viewports = [.viewports | max] | .app_rows.viewports = [.viewports[0]] else . end' --argjson q "$([[ $MODE == quick ]] && echo true || echo false)" > "$OUT/checks.json"   # a design check: the app rows' widths
  export AID_UI_PROJECT="$PROJECT"
  srv="$(bash "$HERE/aid-ui-serve.sh" preview "$site")" || exit 1
  trap 'AID_UI_PROJECT="$PROJECT" bash "$HERE/aid-ui-serve.sh" stop preview >/dev/null 2>&1 || true' EXIT
  bash "$TOOL" verify --state "$OUT/state.json" --checks "$OUT/checks.json" --site "$site" --base "$(sed -n 's/^URL: //p' <<<"$srv")" \
    --out "$OUT" --project "$PROJECT" --seo "$HERE/aid-ui-seo-check.py" || die "the $MODE run failed; no result"
  open="$(jq '[.rows[] | select(.status != "pass")] | length' "$OUT/result.json")"
  # P118: the gate's time per run, for the phases of a round (aid-ui-quality.py status)
  jq -cn --arg m "$MODE" --arg s "$STARTED" --arg e "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson o "$open" '{mode: $m, started: $s, ended: $e, open: $o}' >> "$PROJECT/.aid-ui/gate-times.jsonl"
  echo "${MODE^^}: $OUT/result.json ($open open rows)"
  jq -r '.rows[] | select(.status != "pass") | "  \(.status) \(.check) \(.page) \(.state) \(.viewport): \((.detail // "")[0:160])"' "$OUT/result.json" | head -20
  (( open == 0 )) || exit 3
  exit 0
fi
if (( $# == 3 )) && [[ "$2" == --copy-subject ]]; then subject="$(realpath -m "$3")"
elif (( $# == 3 )) && [[ "$2" == --base-url ]]; then live="$3"
  [[ "$live" =~ ^https?://[^[:space:]]+$ ]] || { echo "$USAGE (--base-url is an http(s) address)" >&2; exit 2; }
elif (( $# != 1 )); then echo "$USAGE" >&2; exit 2; fi
[[ -d "$1" ]] || { echo "$USAGE" >&2; exit 2; }
PROJECT="$(realpath "$1")"
STATE="$PROJECT/docs/design/brand-state.json"
[[ -f "$STATE" ]] || die "no $STATE; run aid-ui-state.sh init"
read -r id dir < <(jq -r '"\(.build.id // "-") \(.build.dir // "")"' "$STATE")
[[ -n "$dir" ]] || die "no build recorded; run aid-ui-state.sh build-record"
[[ -d "$dir" ]] || die "the recorded site directory $dir is gone"
if [[ -z "$live" ]]; then   # binds the LOCAL gate to the recorded build; the run gate compares the deployed files instead
  now_id="$(bash "$HERE/aid-ui-state.sh" build-id "$dir")"
  [[ "$now_id" == "$id" ]] || die "the site in $dir changed since build-record (build id $now_id, recorded $id); rebuild and run build-record again"
fi

# P116: a webapp is gated only on the model the owner approved, with its task scenarios generated from that model now
if [[ "$(jq -r '.variant.type // ""' "$STATE")" == webapp ]]; then   # every mode: the copy subject and the live rows too
  bash "$HERE/aid-ui-state.sh" model-approved "$PROJECT" >/dev/null || die "the gate of an app runs only on the model the owner approved (see above)"
  python3 "$HERE/aid-ui-flows.py" generate "$PROJECT" >/dev/null || die "the task scenarios could not be generated from docs/design/screens.json (see above)"
fi

OUT="$PROJECT/.aid-ui/verify"
[[ -z "$live" ]] || OUT="$PROJECT/.aid-ui/verify-live"
if [[ -n "$subject" ]]; then OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT   # subject only: the gate result stays
else rm -rf "$OUT"; mkdir -p "$OUT"; fi
yq -o=json . "$(dirname "$COVERAGE_MAP")/checks.yaml" > "$OUT/checks.json" || die "cannot read checks.yaml"
facts=()
if [[ -f "$PROJECT/docs/content/facts.yaml" ]]; then
  yq -o=json . "$PROJECT/docs/content/facts.yaml" > "$OUT/facts.json" || die "cannot read docs/content/facts.yaml"
  facts=(--facts "$OUT/facts.json")
fi
if [[ -f "$PROJECT/docs/content/tasks.yaml" ]]; then   # P113a: the task test (task_test row)
  yq -o=json . "$PROJECT/docs/content/tasks.yaml" > "$OUT/tasks.json" || die "cannot read docs/content/tasks.yaml"
  facts+=(--tasks "$OUT/tasks.json")
fi
if [[ -f "$PROJECT/docs/content/photos.yaml" ]]; then   # P113a: the photos the client owes (photo_slots row)
  yq -o=json . "$PROJECT/docs/content/photos.yaml" > "$OUT/photos.json" || die "cannot read docs/content/photos.yaml"
  facts+=(--photos "$OUT/photos.json")
fi

export AID_UI_PROJECT="$PROJECT"
if [[ -n "$live" ]]; then   # P115: the rows over the live address - no preview, nothing recorded in the state
  bash "$TOOL" verify --state "$STATE" --checks "$OUT/checks.json" --site "$dir" \
    --base "$live" --out "$OUT" --project "$PROJECT" --seo "$HERE/aid-ui-seo-check.py" --live 1 "${facts[@]}" \
    || die "aid-ui-verify.mjs failed over $live; no live result"
  jq -n --arg u "$live" --arg s "$(python3 "$HERE/aid-ui-motion.py" dirsha "$dir")" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg m "$(jq -r '.model_sha256 // ""' "$OUT/result.json")" \
    '{url: $u, site_sha256: $s, run_at: $at} + (if $m != "" then {model_sha256: $m} else {} end)' > "$OUT/live.json"   # P116: an app's live rows are of its model
  wo="$(jq -c '.warn_only // []' "$OUT/checks.json")"
  openf='[.rows[] | select(.status == "fail" or .status == "not_covered" or (.status == "warn" and (.check | IN($wo[]) | not)))]'
  open="$(jq --argjson wo "$wo" "$openf | length" "$OUT/result.json")"
  echo "LIVE RESULT: $OUT/result.json over $live ($open open rows)"
  (( open == 0 )) && exit 0
  jq -r --argjson wo "$wo" "$openf"' | .[] | "  \(.status) \(.check) \(.page) \(.viewport): \((.detail // "")[0:160])"' "$OUT/result.json" | head -20
  exit 3
fi
srv="$(AID_UI_PROJECT="$PROJECT" bash "$HERE/aid-ui-serve.sh" preview "$dir")" || exit 1   # the project: the form receiver reads .aid-ui/form.json
plog="${AID_UI_JOBS_DIR:-$PROJECT/.aid-ui/jobs}/$(sed -n 's/^JOB: //p' <<<"$srv")/stdout.log"   # form_delivery: no sent value in it
[[ -f "$plog" ]] && facts+=(--preview-log "$plog")
trap 'AID_UI_PROJECT="$PROJECT" bash "$HERE/aid-ui-serve.sh" stop preview >/dev/null 2>&1 || true; [[ -z "$subject" ]] || rm -rf "$OUT"' EXIT
url="$(sed -n 's/^URL: //p' <<<"$srv")"
if [[ -n "$subject" ]]; then
  mkdir -p "$(dirname "$subject")"
  bash "$TOOL" verify --state "$STATE" --checks "$OUT/checks.json" --site "$dir" \
    --base "$url" --out "$OUT" --project "$PROJECT" --seo "$HERE/aid-ui-seo-check.py" --copy-subject "$subject" \
    || die "copy subject failed"
  echo "BRÁNA NEBĚŽELA (jen texty pro kontrolu textů; result.json beze změny)"
  exit 0
fi

bash "$TOOL" verify --state "$STATE" --checks "$OUT/checks.json" --site "$dir" \
  --base "$url" --out "$OUT" --project "$PROJECT" --seo "$HERE/aid-ui-seo-check.py" "${facts[@]}" \
  || die "aid-ui-verify.mjs failed; no result recorded"
bash "$HERE/aid-ui-state.sh" gate-record "$PROJECT" "$OUT/result.json" || exit 1
wo="$(jq -c '.warn_only // []' "$OUT/checks.json")"
open="$(jq --argjson wo "$wo" '[.rows[] | select(.status == "fail" or .status == "not_covered" or (.status == "warn" and (.check | IN($wo[]) | not)))] | length' "$OUT/result.json")"
echo "RESULT: $OUT/result.json ($open open rows)"
(( open == 0 )) || exit 3
