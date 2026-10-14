#!/usr/bin/env bash
# =============================================================================
# aid-ui-verify.sh — the /aid-ui verification gate (step 7) on the recorded build.
#
#   aid-ui-verify.sh <project>
#   aid-ui-verify.sh <project> --copy-subject <out.json>   (P108) serves the recorded build and writes
#     only the copy of every page for the copy review; the gate result in .aid-ui/verify stays untouched
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

subject=""
if (( $# == 3 )) && [[ "$2" == --copy-subject ]]; then subject="$(realpath -m "$3")"
elif (( $# != 1 )); then echo "usage: aid-ui-verify.sh <project> [--copy-subject <out.json>]" >&2; exit 2; fi
[[ -d "$1" ]] || { echo "usage: aid-ui-verify.sh <project> [--copy-subject <out.json>]" >&2; exit 2; }
PROJECT="$(realpath "$1")"
STATE="$PROJECT/docs/design/brand-state.json"
[[ -f "$STATE" ]] || die "no $STATE; run aid-ui-state.sh init"
read -r id dir < <(jq -r '"\(.build.id // "-") \(.build.dir // "")"' "$STATE")
[[ -n "$dir" ]] || die "no build recorded; run aid-ui-state.sh build-record"
[[ -d "$dir" ]] || die "the recorded site directory $dir is gone"
now_id="$(bash "$HERE/aid-ui-state.sh" build-id "$dir")"
[[ "$now_id" == "$id" ]] || die "the site in $dir changed since build-record (build id $now_id, recorded $id); rebuild and run build-record again"

OUT="$PROJECT/.aid-ui/verify"
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
srv="$(AID_UI_PROJECT="$PROJECT" bash "$HERE/aid-ui-serve.sh" preview "$dir")" || exit 1   # the project: the form receiver reads .aid-ui/form.json
plog="${AID_UI_JOBS_DIR:-$PROJECT/.aid-ui/jobs}/$(sed -n 's/^JOB: //p' <<<"$srv")/stdout.log"   # form_delivery: no sent value in it
[[ -f "$plog" ]] && facts+=(--preview-log "$plog")
trap 'AID_UI_PROJECT="$PROJECT" bash "$HERE/aid-ui-serve.sh" stop preview >/dev/null 2>&1 || true; [[ -z "$subject" ]] || rm -rf "$OUT"' EXIT
url="$(sed -n 's/^URL: //p' <<<"$srv")"
if [[ -n "$subject" ]]; then
  mkdir -p "$(dirname "$subject")"
  bash "$HERE/aid-ui-tool.sh" verify --state "$STATE" --checks "$OUT/checks.json" --site "$dir" \
    --base "$url" --out "$OUT" --project "$PROJECT" --seo "$HERE/aid-ui-seo-check.py" --copy-subject "$subject" \
    || die "copy subject failed"
  echo "BRÁNA NEBĚŽELA (jen texty pro kontrolu textů; result.json beze změny)"
  exit 0
fi

bash "$HERE/aid-ui-tool.sh" verify --state "$STATE" --checks "$OUT/checks.json" --site "$dir" \
  --base "$url" --out "$OUT" --project "$PROJECT" --seo "$HERE/aid-ui-seo-check.py" "${facts[@]}" \
  || die "aid-ui-verify.mjs failed; no result recorded"
bash "$HERE/aid-ui-state.sh" gate-record "$PROJECT" "$OUT/result.json" || exit 1
wo="$(jq -c '.warn_only // []' "$OUT/checks.json")"
open="$(jq --argjson wo "$wo" '[.rows[] | select(.status == "fail" or .status == "not_covered" or (.status == "warn" and (.check | IN($wo[]) | not)))] | length' "$OUT/result.json")"
echo "RESULT: $OUT/result.json ($open open rows)"
(( open == 0 )) || exit 3
