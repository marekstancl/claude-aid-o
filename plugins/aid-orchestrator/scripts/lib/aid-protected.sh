# shellcheck shell=bash
# aid-protected.sh — is a proposed decision a PROTECTED impact (P117 (1), (11))? Code, never a model: what the
# stand-in may decide in an --auto run is bounded here, whatever its verdict says.
#
#   aid_protected_impact <state_root> <tree_root> <proposal.json> [run evidence dir]
#     prints "<class>: <why>" for the first protected impact and returns 1; prints nothing and returns 0 when
#     the proposal is technical. Classes: brief, money, data, security, production, foreign_api, foreign_repo,
#     gate, unevaluable. A proposal it cannot read, or a kind it does not know, is unevaluable (protected).
#
# Protected, from the brief: a point of the brief or its measurement; execution.yaml (gates, profiles,
# waivers) and the rest of .aid-o/config; the project's protected_paths (execution.yaml; default .env*,
# *secret*, *credential*, deploy/**, production compose and configuration); a repository outside repo_roots;
# a paid service or a new foreign API the proposal declares (external[]).
#
# The proposal (written by the controller, checked by the stand-in, re-checked here by every consumer):
#   {kind: scope_extension|no_change_step|visual_check|measurement_failed|rename,
#    step: <0-based index>, paths: [..], criterion: "AC<n>", rename: {old, new}, external: [..], why: ".."}

AID_PROTECTED_DEFAULT_PATHS='.env .env.* *secret* *credential* deploy/** **/deploy/** *.prod.yml *.prod.yaml docker-compose.prod* compose.prod* *production*'

# _aid_prot_glob <path> <glob> — ** spans directories, * stays inside one
_aid_prot_glob() {
  local re; re="$(printf '%s' "$2" | sed -e 's/[.+^$(){}|\\]/\\&/g' -e 's/\*\*\//\x01/g' -e 's/\*\*/\x02/g' -e 's/\*/[^\/]*/g' \
    -e 's/?/[^\/]/g' -e 's/\x01/(.*\/)?/g' -e 's/\x02/.*/g')"
  [[ "$1" =~ ^${re}$ ]]
}

aid_protected_impact() {
  local sroot="$1" troot="$2" prop="$3" ev="${4:-}" kind p g ex globs zf rel
  jq -e 'type == "object" and (.kind | type == "string")' "$prop" >/dev/null 2>&1 \
    || { echo "unevaluable: the proposal ${prop} is not a JSON object with a kind"; return 1; }
  kind="$(jq -r .kind "$prop")"
  case "$kind" in
    scope_extension|no_change_step|visual_check|measurement_failed|rename|blocked_step) ;;
    *) echo "unevaluable: the proposal kind '${kind}' is not one the stand-in may decide"; return 1 ;;
  esac
  ex="$(jq -r '(.external // [])[]' "$prop" 2>/dev/null)"
  [[ -z "$ex" ]] || { echo "money: the proposal calls an outside service (${ex//$'\n'/, }) — a paid service or a new foreign API is the PM's"; return 1; }

  # the paths it touches: paths[], both sides of a rename
  local exec_yaml="${sroot}/.aid-o/config/execution.yaml"
  globs="$AID_PROTECTED_DEFAULT_PATHS $(yq -r '(.protected_paths // [])[]' "$exec_yaml" 2>/dev/null | tr '\n' ' ')"
  zf="$(jq -r '.zadani // ""' "${ev:-/nonexistent}/plan.json" 2>/dev/null)"
  local rr; rr="$(jq -r '(.repo_roots // [])[] | .path // empty, .worktree // empty' "${ev:-/nonexistent}/plan.json" 2>/dev/null)"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if [[ "$p" == *..* ]]; then echo "unevaluable: the path ${p} climbs out with .."; return 1; fi
    if [[ "$p" == /* ]]; then
      if [[ "$p" == "${troot%/}/"* ]]; then rel="${p#"${troot%/}/"}"
      else
        local inside=0 r
        while IFS= read -r r; do [[ -n "$r" && "$p" == "${r%/}/"* ]] && { inside=1; rel="${p#"${r%/}/"}"; }; done <<< "$rr"
        (( inside )) || { echo "foreign_repo: ${p} is outside the plan's worktree and its repo_roots"; return 1; }
      fi
    else rel="${p#./}"; fi
    local lrel; lrel="$(tr '[:upper:]' '[:lower:]' <<< "$rel")"   # case-insensitive: .ENV is .env on many disks
    case "$lrel" in
      .aid-o/config/*|*/.aid-o/config/*|execution.yaml|*/execution.yaml)
        echo "gate: ${p} is AID's configuration (gates, profiles, waivers)"; return 1 ;;
      .aid-o/plans/*|*/.aid-o/plans/*)
        echo "brief: ${p} is the plan or its brief"; return 1 ;;
    esac
    rel="$lrel"
    [[ -n "$zf" && ( "$rel" == "$zf" || "$p" == "$zf" ) ]] && { echo "brief: ${p} is the brief"; return 1; }
    for g in $(tr '[:upper:]' '[:lower:]' <<< "$globs"); do
      # a pattern without a slash matches a file or a directory at any depth (as in .gitignore)
      { _aid_prot_glob "$rel" "$g" || { [[ "$g" != */* ]] && { _aid_prot_glob "$rel" "**/$g" || _aid_prot_glob "$rel" "**/$g/**"; }; }; } \
        && { echo "security: ${p} matches the protected path ${g}"; return 1; }
    done
  done < <(jq -r '(.paths // [])[], (.rename.old // empty), (.rename.new // empty)' "$prop" 2>/dev/null)

  if [[ "$kind" == blocked_step ]] && [[ "$(jq -r '.action // ""' "$prop")" != redispatch ]]; then
    echo "unevaluable: a blocked step is decided as a re-dispatch only; a rename or a widening is asked as its own kind (rename, scope_extension)"; return 1
  fi
  if [[ "$kind" == measurement_failed ]]; then
    # only a TECHNICAL failure of the step's measurement: the point stays, the close measures it again.
    # A point that ran and failed is the step's to fix, and dropping it is the PM's.
    local c pd r
    c="$(jq -r '.criterion // ""' "$prop")"; pd="${ev}/cp2/step-$(jq -r '.step // "x"' "$prop")/plan-diff.json"
    [[ "$c" =~ ^AC[0-9]+$ && -f "$pd" ]] || { echo "unevaluable: measurement_failed needs criterion AC<n> and the step's measurement (${pd})"; return 1; }
    declare -p AID_PD_UNMEASURED_RE >/dev/null 2>&1 || source "$(dirname "${BASH_SOURCE[0]}")/aid-unmeasured.sh"
    r="$(jq -r --arg c "$c" 'first(.results[] | select(.ac_label == $c) | .reason // "") // "missing"' "$pd")"
    [[ "$r" =~ $AID_PD_UNMEASURED_RE ]] \
      || { echo "brief: ${c} was measured ($(jq -r --arg c "$c" 'first(.results[] | select(.ac_label == $c) | .evidence // "") // "not in the measurement"' "$pd")) — not a technical failure; the step fixes it, or the PM defers the point"; return 1; }
  fi
  return 0
}
